import assert from "node:assert/strict";
import {
  findingCreateSchema,
  findingStatusUpdateSchema,
  pageReviewedSchema,
  reviewSubmitSchema,
  reviewReasonSchema,
  reviewAssignSchema,
} from "../lib/extraction-review/schemas";

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

const REVIEW_ID = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
const PAGE_ID = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";
const FINDING_ID = "cccccccc-cccc-cccc-cccc-cccccccccccc";
const USER_ID = "dddddddd-dddd-dddd-dddd-dddddddddddd";

check("findingCreateSchema accepts a valid page-level finding", () => {
  const result = findingCreateSchema.safeParse({
    reviewId: REVIEW_ID,
    extractionPageId: PAGE_ID,
    findingType: "garbled_characters",
    severity: "critical",
    title: "Arabic text is garbled",
    description: "Every character is mis-shaped",
  });
  assert.ok(result.success);
});

check("findingCreateSchema accepts a valid document-level finding (no page)", () => {
  const result = findingCreateSchema.safeParse({
    reviewId: REVIEW_ID,
    findingType: "metadata_mismatch",
    severity: "informational",
    title: "Title casing differs",
  });
  assert.ok(result.success);
});

check("findingCreateSchema rejects an unknown finding type", () => {
  const result = findingCreateSchema.safeParse({
    reviewId: REVIEW_ID,
    findingType: "not_a_real_type",
    severity: "minor",
    title: "x",
  });
  assert.equal(result.success, false);
});

check("findingCreateSchema rejects an unknown severity", () => {
  const result = findingCreateSchema.safeParse({
    reviewId: REVIEW_ID,
    findingType: "other",
    severity: "extreme",
    title: "x",
    description: "needed for other",
  });
  assert.equal(result.success, false);
});

check("findingCreateSchema rejects an empty title", () => {
  const result = findingCreateSchema.safeParse({
    reviewId: REVIEW_ID,
    findingType: "missing_text",
    severity: "major",
    title: "",
  });
  assert.equal(result.success, false);
});

check("findingStatusUpdateSchema accepts a valid resolution", () => {
  const result = findingStatusUpdateSchema.safeParse({
    findingId: FINDING_ID,
    status: "resolved",
    resolutionNote: "Confirmed acceptable",
  });
  assert.ok(result.success);
});

check("findingStatusUpdateSchema rejects an unknown status", () => {
  const result = findingStatusUpdateSchema.safeParse({ findingId: FINDING_ID, status: "closed" });
  assert.equal(result.success, false);
});

check("pageReviewedSchema coerces a string page number", () => {
  const result = pageReviewedSchema.safeParse({
    reviewId: REVIEW_ID,
    pageNumber: "3",
    pageReviewStatus: "reviewed_clear",
  });
  assert.ok(result.success);
  if (result.success) assert.equal(result.data.pageNumber, 3);
});

check("pageReviewedSchema rejects page number 0", () => {
  const result = pageReviewedSchema.safeParse({
    reviewId: REVIEW_ID,
    pageNumber: "0",
    pageReviewStatus: "reviewed_clear",
  });
  assert.equal(result.success, false);
});

check("reviewSubmitSchema accepts a valid accepted decision", () => {
  const result = reviewSubmitSchema.safeParse({ reviewId: REVIEW_ID, targetStatus: "accepted" });
  assert.ok(result.success);
});

check("reviewSubmitSchema rejects an unknown target status", () => {
  const result = reviewSubmitSchema.safeParse({ reviewId: REVIEW_ID, targetStatus: "approved" });
  assert.equal(result.success, false);
});

check("reviewReasonSchema requires a non-empty reason", () => {
  const result = reviewReasonSchema.safeParse({ reviewId: REVIEW_ID, reason: "" });
  assert.equal(result.success, false);
});
check("reviewReasonSchema accepts a valid reason", () => {
  const result = reviewReasonSchema.safeParse({ reviewId: REVIEW_ID, reason: "Quality wants a second pass" });
  assert.ok(result.success);
});

check("reviewAssignSchema requires valid UUIDs", () => {
  const result = reviewAssignSchema.safeParse({ reviewId: REVIEW_ID, reviewerUserId: USER_ID });
  assert.ok(result.success);
});
check("reviewAssignSchema rejects a non-uuid reviewer id", () => {
  const result = reviewAssignSchema.safeParse({ reviewId: REVIEW_ID, reviewerUserId: "not-a-uuid" });
  assert.equal(result.success, false);
});

if (failures > 0) {
  console.log(`\n${failures} test(s) failed.`);
  process.exit(1);
}
console.log("\nAll extraction-review schema tests passed.");
