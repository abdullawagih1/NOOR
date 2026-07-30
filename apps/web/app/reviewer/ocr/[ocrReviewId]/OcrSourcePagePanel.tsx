"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { createOcrReviewSourceAccessAction } from "@/lib/ocr/actions";

/**
 * Client Component mirroring
 * apps/web/app/reviewer/extractions/[reviewId]/SourcePdfPanel.tsx one layer
 * deeper — mints its own short-lived signed URL for the original PDF page
 * (never persisted, never logged), re-minted shortly before expiry. Same
 * browser-native <iframe> + #page=N convention and the same documented
 * per-browser page-jump limitation.
 */
export function OcrSourcePagePanel({ extractionRunId, pageNumber }: { extractionRunId: string; pageNumber: number }) {
  const [signedUrl, setSignedUrl] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const refreshTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const fetchSignedUrl = useCallback(async () => {
    try {
      const access = await createOcrReviewSourceAccessAction(extractionRunId);
      setSignedUrl(access.signedUrl);
      setError(null);
      const msUntilExpiry = new Date(access.expiresAt).getTime() - Date.now();
      if (refreshTimer.current) clearTimeout(refreshTimer.current);
      refreshTimer.current = setTimeout(fetchSignedUrl, Math.max(msUntilExpiry - 30_000, 10_000));
    } catch {
      setError("Could not load the source document. It may have expired — try refreshing.");
    }
  }, [extractionRunId]);

  useEffect(() => {
    void fetchSignedUrl();
    return () => {
      if (refreshTimer.current) clearTimeout(refreshTimer.current);
    };
  }, [fetchSignedUrl]);

  if (error) {
    return (
      <div className="flex h-full items-center justify-center rounded-sm border border-border bg-surface p-md text-sm text-muted" role="alert">
        {error}
      </div>
    );
  }

  if (!signedUrl) {
    return (
      <div className="flex h-full items-center justify-center rounded-sm border border-border bg-surface p-md text-sm text-muted">
        Loading original page…
      </div>
    );
  }

  return (
    <iframe
      key={signedUrl}
      src={`${signedUrl}#page=${pageNumber}`}
      title="Original source page"
      className="h-full min-h-[480px] w-full rounded-sm border border-border"
    />
  );
}
