import { createHash } from "node:crypto";
import { PDF_SIGNATURE, MAX_UPLOAD_SIZE_BYTES } from "@/lib/documents/config";

export interface StreamedFileFacts {
  sizeBytes: number;
  /** null when the stream was aborted early because it exceeded the size limit — a partial hash would be meaningless. */
  sha256: string | null;
  signatureValid: boolean;
  oversized: boolean;
  /** Exposed only for testability (proving multi-chunk streams are actually read incrementally) — not used by callers. */
  chunksRead: number;
}

/**
 * Incrementally computes size, SHA-256, and PDF-signature validity from a
 * Web ReadableStream — never buffers the whole file into memory. Used by
 * completeGuidelineUploadAction against a raw `fetch()` of the Storage
 * object (not supabase-js's `.download()`, which returns a Blob and
 * therefore forces a full-buffer read for a file up to
 * MAX_UPLOAD_SIZE_BYTES). See docs/database/secure-document-intake-schema.md
 * and PROJECT_STATE.md for the Sprint 1.2A streaming-verification review.
 *
 * An oversized stream is cancelled as soon as the limit is exceeded —
 * the remaining bytes are never downloaded, and `sha256` is reported as
 * null (a partial hash over a truncated file would be misleading, not a
 * real checksum of anything).
 */
export async function computeFileFactsFromStream(
  body: ReadableStream<Uint8Array>,
  maxSizeBytes: number = MAX_UPLOAD_SIZE_BYTES
): Promise<StreamedFileFacts> {
  const reader = body.getReader();
  const hash = createHash("sha256");
  let sizeBytes = 0;
  let chunksRead = 0;
  let signatureChecked = false;
  let signatureValid = false;
  let firstBytes = Buffer.alloc(0);
  let oversized = false;

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    chunksRead += 1;
    const chunk = Buffer.from(value);
    sizeBytes += chunk.byteLength;

    if (!signatureChecked) {
      firstBytes = Buffer.concat([firstBytes, chunk]);
      if (firstBytes.byteLength >= PDF_SIGNATURE.length) {
        signatureValid = firstBytes.subarray(0, PDF_SIGNATURE.length).toString("latin1") === PDF_SIGNATURE;
        signatureChecked = true;
      }
    }

    hash.update(chunk);

    if (sizeBytes > maxSizeBytes) {
      oversized = true;
      await reader.cancel("file exceeds the configured size limit");
      break;
    }
  }

  if (!signatureChecked) {
    // Stream ended before PDF_SIGNATURE.length bytes arrived (empty or tiny file).
    signatureValid = firstBytes.subarray(0, PDF_SIGNATURE.length).toString("latin1") === PDF_SIGNATURE;
  }

  return {
    sizeBytes,
    sha256: oversized ? null : hash.digest("hex"),
    signatureValid,
    oversized,
    chunksRead,
  };
}
