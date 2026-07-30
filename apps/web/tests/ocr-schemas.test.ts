import assert from "node:assert/strict";
import {
  ocrRequestCreateSchema,
  ocrRequestReasonSchema,
  ocrReviewReasonSchema,
  ocrReviewAssignSchema,
  ocrPageReviewedSchema,
  ocrFindingCreateSchema,
  ocrFindingStatusUpdateSchema,
  ocrReviewSubmitSchema,
} from "../lib/ocr/schemas";

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
const REQUEST_ID = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";
const FINDING_ID = "cccccccc-cccc-cccc-cccc-cccccccccccc";
const USER_ID = "dddddddd-dddd-dddd-dddd-dddddddddddd";

check("ocrRequestCreateSchema accepts a valid extraction review id", () => {
  const result = ocrRequestCreateSchema.safeParse({ extractionReviewId: REVIEW_ID });
  assert.ok(result.success);
});
check("ocrRequestCreateSchema rejects a non-uuid", () => {
  const result = ocrRequestCreateSchema.safeParse({ extractionReviewId: "not-a-uuid" });
  assert.equal(result.success, false);
});

check("ocrRequestReasonSchema requires a non-empty reason", () => {
  const result = ocrRequestReasonSchema.safeParse({ ocrRequestId: REQUEST_ID, reason: "" });
  assert.equal(result.success, false);
});
check("ocrRequestReasonSchema accepts a valid reason", () => {
  const result = ocrRequestReasonSchema.safeParse({ ocrRequestId: REQUEST_ID, reason: "no longer needed" });
  assert.ok(result.success);
});

check("ocrReviewReasonSchema requires a non-empty reason", () => {
  const result = ocrReviewReasonSchema.safeParse({ ocrReviewId: REVIEW_ID, reason: "" });
  assert.equal(result.success, false);
});

check("ocrReviewAssignSchema requires valid UUIDs", () => {
  const result = ocrReviewAssignSchema.safeParse({ ocrReviewId: REVIEW_ID, reviewerUserId: USER_ID });
  assert.ok(result.success);
});
check("ocrReviewAssignSchema rejects a non-uuid reviewer id", () => {
  const result = ocrReviewAssignSchema.safeParse({ ocrReviewId: REVIEW_ID, reviewerUserId: "not-a-uuid" });
  assert.equal(result.success, false);
});

check("ocrPageReviewedSchema coerces a string page number", () => {
  const result = ocrPageReviewedSchema.safeParse({ ocrReviewId: REVIEW_ID, pageNumber: "3", pageReviewStatus: "accepted" });
  assert.ok(result.success);
  if (result.success) assert.equal(result.data.pageNumber, 3);
});
check("ocrPageReviewedSchema rejects page number 0", () => {
  const result = ocrPageReviewedSchema.safeParse({ ocrReviewId: REVIEW_ID, pageNumber: "0", pageReviewStatus: "accepted" });
  assert.equal(result.success, false);
});
check("ocrPageReviewedSchema rejects ocr_required as a page review status (not a valid OCR page decision)", () => {
  const result = ocrPageReviewedSchema.safeParse({ ocrReviewId: REVIEW_ID, pageNumber: "1", pageReviewStatus: "ocr_required" });
  assert.equal(result.success, false);
});

check("ocrFindingCreateSchema accepts a valid finding", () => {
  const result = ocrFindingCreateSchema.safeParse({
    ocrReviewId: REVIEW_ID,
    pageNumber: 1,
    findingType: "arabic_recognition_issue",
    severity: "major",
    title: "Arabic letters mis-shaped",
  });
  assert.ok(result.success);
});
check("ocrFindingCreateSchema rejects an unknown finding type", () => {
  const result = ocrFindingCreateSchema.safeParse({
    ocrReviewId: REVIEW_ID,
    pageNumber: 1,
    findingType: "not_a_real_type",
    severity: "minor",
    title: "x",
  });
  assert.equal(result.success, false);
});
check("ocrFindingCreateSchema rejects an empty title", () => {
  const result = ocrFindingCreateSchema.safeParse({
    ocrReviewId: REVIEW_ID,
    pageNumber: 1,
    findingType: "low_confidence",
    severity: "informational",
    title: "",
  });
  assert.equal(result.success, false);
});

check("ocrFindingStatusUpdateSchema accepts a valid resolution", () => {
  const result = ocrFindingStatusUpdateSchema.safeParse({ ocrReviewId: REVIEW_ID, findingId: FINDING_ID, status: "resolved" });
  assert.ok(result.success);
});
check("ocrFindingStatusUpdateSchema rejects an unknown status", () => {
  const result = ocrFindingStatusUpdateSchema.safeParse({ ocrReviewId: REVIEW_ID, findingId: FINDING_ID, status: "closed" });
  assert.equal(result.success, false);
});

check("ocrReviewSubmitSchema accepts a valid accepted decision", () => {
  const result = ocrReviewSubmitSchema.safeParse({ ocrReviewId: REVIEW_ID, targetStatus: "accepted" });
  assert.ok(result.success);
});
check("ocrReviewSubmitSchema rejects ocr_required as a target status (not a valid OCR review outcome)", () => {
  const result = ocrReviewSubmitSchema.safeParse({ ocrReviewId: REVIEW_ID, targetStatus: "ocr_required" });
  assert.equal(result.success, false);
});

if (failures > 0) {
  console.log(`\n${failures} test(s) failed.`);
  process.exit(1);
}
console.log("\nAll OCR schema tests passed.");
