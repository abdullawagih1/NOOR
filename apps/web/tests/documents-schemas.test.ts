import assert from "node:assert/strict";
import {
  uploadSessionRequestSchema,
  uploadCompletionSchema,
  jobCancellationSchema,
  quarantineDocumentSchema,
  cancelUploadSessionSchema,
} from "../lib/documents/schemas";
import { MAX_UPLOAD_SIZE_BYTES } from "../lib/documents/config";

let failures = 0;

function check(name: string, fn: () => void) {
  try {
    fn();
    console.log(`PASS  ${name}`);
  } catch (err) {
    failures += 1;
    console.log(`FAIL  ${name} — ${(err as Error).message}`);
  }
}

const VERSION_ID = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
const SESSION_ID = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";
const DOC_ID = "cccccccc-cccc-cccc-cccc-cccccccccccc";
const JOB_ID = "dddddddd-dddd-dddd-dddd-dddddddddddd";
const VALID_SHA = "a".repeat(64);

check("uploadSessionRequestSchema accepts a valid PDF request", () => {
  const result = uploadSessionRequestSchema.safeParse({
    guidelineVersionId: VERSION_ID,
    filename: "guideline.pdf",
    declaredMediaType: "application/pdf",
    expectedSizeBytes: 1000,
  });
  assert.ok(result.success);
});

check("uploadSessionRequestSchema rejects a non-pdf filename", () => {
  const result = uploadSessionRequestSchema.safeParse({
    guidelineVersionId: VERSION_ID,
    filename: "guideline.docx",
    declaredMediaType: "application/pdf",
  });
  assert.equal(result.success, false);
});

check("uploadSessionRequestSchema rejects a non-pdf declared media type", () => {
  const result = uploadSessionRequestSchema.safeParse({
    guidelineVersionId: VERSION_ID,
    filename: "guideline.pdf",
    declaredMediaType: "application/msword",
  });
  assert.equal(result.success, false);
});

check("uploadSessionRequestSchema rejects zero-byte expected size", () => {
  const result = uploadSessionRequestSchema.safeParse({
    guidelineVersionId: VERSION_ID,
    filename: "guideline.pdf",
    declaredMediaType: "application/pdf",
    expectedSizeBytes: 0,
  });
  assert.equal(result.success, false);
});

check("uploadSessionRequestSchema rejects a size over the canonical limit", () => {
  const result = uploadSessionRequestSchema.safeParse({
    guidelineVersionId: VERSION_ID,
    filename: "guideline.pdf",
    declaredMediaType: "application/pdf",
    expectedSizeBytes: MAX_UPLOAD_SIZE_BYTES + 1,
  });
  assert.equal(result.success, false);
});

check("uploadSessionRequestSchema accepts a size exactly at the canonical limit", () => {
  const result = uploadSessionRequestSchema.safeParse({
    guidelineVersionId: VERSION_ID,
    filename: "guideline.pdf",
    declaredMediaType: "application/pdf",
    expectedSizeBytes: MAX_UPLOAD_SIZE_BYTES,
  });
  assert.ok(result.success);
});

check("uploadSessionRequestSchema rejects a malformed expectedSha256", () => {
  const result = uploadSessionRequestSchema.safeParse({
    guidelineVersionId: VERSION_ID,
    filename: "guideline.pdf",
    declaredMediaType: "application/pdf",
    expectedSha256: "not-a-hash",
  });
  assert.equal(result.success, false);
});

check("uploadSessionRequestSchema accepts a valid expectedSha256", () => {
  const result = uploadSessionRequestSchema.safeParse({
    guidelineVersionId: VERSION_ID,
    filename: "guideline.pdf",
    declaredMediaType: "application/pdf",
    expectedSha256: VALID_SHA,
  });
  assert.ok(result.success);
});

check("uploadCompletionSchema requires a valid session id", () => {
  const result = uploadCompletionSchema.safeParse({ uploadSessionId: "not-a-uuid" });
  assert.equal(result.success, false);
});
check("uploadCompletionSchema accepts a valid session id", () => {
  const result = uploadCompletionSchema.safeParse({ uploadSessionId: SESSION_ID });
  assert.ok(result.success);
});

check("quarantineDocumentSchema requires a non-empty reason", () => {
  const result = quarantineDocumentSchema.safeParse({ sourceDocumentId: DOC_ID, reason: "" });
  assert.equal(result.success, false);
});
check("quarantineDocumentSchema accepts a valid reason", () => {
  const result = quarantineDocumentSchema.safeParse({ sourceDocumentId: DOC_ID, reason: "Discovered a formatting issue" });
  assert.ok(result.success);
});

check("jobCancellationSchema allows an optional reason", () => {
  const result = jobCancellationSchema.safeParse({ processingJobId: JOB_ID });
  assert.ok(result.success);
});

check("cancelUploadSessionSchema requires a valid session id", () => {
  const result = cancelUploadSessionSchema.safeParse({ uploadSessionId: "nope" });
  assert.equal(result.success, false);
});

if (failures > 0) {
  console.log(`\n${failures} test(s) failed.`);
  process.exit(1);
}
console.log("\nAll document-intake schema tests passed.");
