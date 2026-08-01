import assert from "node:assert/strict";
import {
  chunkingJobCreateSchema,
  chunkingReviewReasonSchema,
  chunkingRunReasonSchema,
  chunkingReviewAssignSchema,
  chunkReviewedSchema,
  chunkFindingCreateSchema,
  chunkFindingStatusUpdateSchema,
  chunkingReviewSubmitSchema,
} from "../lib/chunking/schemas";

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

const DOCUMENT_ID = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
const REVIEW_ID = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";
const RUN_ID = "cccccccc-cccc-cccc-cccc-cccccccccccc";
const FINDING_ID = "dddddddd-dddd-dddd-dddd-dddddddddddd";
const USER_ID = "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee";

check("chunkingJobCreateSchema accepts a valid source document id", () => {
  const result = chunkingJobCreateSchema.safeParse({ sourceDocumentId: DOCUMENT_ID });
  assert.ok(result.success);
});
check("chunkingJobCreateSchema rejects a non-uuid", () => {
  const result = chunkingJobCreateSchema.safeParse({ sourceDocumentId: "not-a-uuid" });
  assert.equal(result.success, false);
});

check("chunkingReviewReasonSchema requires a non-empty reason", () => {
  const result = chunkingReviewReasonSchema.safeParse({ chunkingReviewId: REVIEW_ID, reason: "" });
  assert.equal(result.success, false);
});
check("chunkingReviewReasonSchema accepts a valid reason", () => {
  const result = chunkingReviewReasonSchema.safeParse({ chunkingReviewId: REVIEW_ID, reason: "boundary looked wrong" });
  assert.ok(result.success);
});

check("chunkingRunReasonSchema requires a non-empty reason", () => {
  const result = chunkingRunReasonSchema.safeParse({ chunkingRunId: RUN_ID, reason: "" });
  assert.equal(result.success, false);
});

check("chunkingReviewAssignSchema requires valid UUIDs", () => {
  const result = chunkingReviewAssignSchema.safeParse({ chunkingReviewId: REVIEW_ID, reviewerUserId: USER_ID });
  assert.ok(result.success);
});
check("chunkingReviewAssignSchema rejects a non-uuid reviewer id", () => {
  const result = chunkingReviewAssignSchema.safeParse({ chunkingReviewId: REVIEW_ID, reviewerUserId: "not-a-uuid" });
  assert.equal(result.success, false);
});

check("chunkReviewedSchema coerces a string chunk index", () => {
  const result = chunkReviewedSchema.safeParse({ chunkingReviewId: REVIEW_ID, chunkIndex: "3", reviewStatus: "reviewed_clear" });
  assert.ok(result.success);
  if (result.success) assert.equal(result.data.chunkIndex, 3);
});
check("chunkReviewedSchema rejects chunk index 0", () => {
  const result = chunkReviewedSchema.safeParse({ chunkingReviewId: REVIEW_ID, chunkIndex: "0", reviewStatus: "reviewed_clear" });
  assert.equal(result.success, false);
});
check("chunkReviewedSchema rejects unreviewed as a decision (not a valid reviewer decision)", () => {
  const result = chunkReviewedSchema.safeParse({ chunkingReviewId: REVIEW_ID, chunkIndex: "1", reviewStatus: "unreviewed" });
  assert.equal(result.success, false);
});

check("chunkFindingCreateSchema accepts a valid finding", () => {
  const result = chunkFindingCreateSchema.safeParse({
    chunkingReviewId: REVIEW_ID,
    chunkIndex: 1,
    findingType: "boundary_splits_sentence",
    severity: "major",
    title: "Chunk cuts mid-sentence",
  });
  assert.ok(result.success);
});
check("chunkFindingCreateSchema accepts a finding with no chunkIndex (run-level finding)", () => {
  const result = chunkFindingCreateSchema.safeParse({
    chunkingReviewId: REVIEW_ID,
    findingType: "artifact_integrity_issue",
    severity: "critical",
    title: "Artifact checksum mismatch",
  });
  assert.ok(result.success);
});
check("chunkFindingCreateSchema rejects an unknown finding type", () => {
  const result = chunkFindingCreateSchema.safeParse({
    chunkingReviewId: REVIEW_ID,
    chunkIndex: 1,
    findingType: "not_a_real_type",
    severity: "minor",
    title: "x",
  });
  assert.equal(result.success, false);
});
check("chunkFindingCreateSchema rejects an empty title", () => {
  const result = chunkFindingCreateSchema.safeParse({
    chunkingReviewId: REVIEW_ID,
    chunkIndex: 1,
    findingType: "oversized_chunk",
    severity: "informational",
    title: "",
  });
  assert.equal(result.success, false);
});

check("chunkFindingStatusUpdateSchema accepts a valid resolution", () => {
  const result = chunkFindingStatusUpdateSchema.safeParse({ chunkingReviewId: REVIEW_ID, findingId: FINDING_ID, status: "resolved" });
  assert.ok(result.success);
});
check("chunkFindingStatusUpdateSchema rejects an unknown status", () => {
  const result = chunkFindingStatusUpdateSchema.safeParse({ chunkingReviewId: REVIEW_ID, findingId: FINDING_ID, status: "closed" });
  assert.equal(result.success, false);
});

check("chunkingReviewSubmitSchema accepts a valid accepted decision", () => {
  const result = chunkingReviewSubmitSchema.safeParse({ chunkingReviewId: REVIEW_ID, targetStatus: "accepted" });
  assert.ok(result.success);
});
check("chunkingReviewSubmitSchema rejects pending_review as a target status (not a valid decision outcome)", () => {
  const result = chunkingReviewSubmitSchema.safeParse({ chunkingReviewId: REVIEW_ID, targetStatus: "pending_review" });
  assert.equal(result.success, false);
});

if (failures > 0) {
  console.log(`\n${failures} test(s) failed.`);
  process.exit(1);
}
console.log("\nAll chunking schema tests passed.");
