import assert from "node:assert/strict";
import { toOcrReviewError } from "../lib/ocr/errors";

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

check("maps a raw permission-denied error to a safe message", () => {
  const result = toOcrReviewError({ code: "42501", message: "permission denied for function submit_document_ocr_review" });
  assert.equal(result.code, "permission_denied");
  assert.ok(!result.message.includes("function submit_document_ocr_review"));
});

check("maps self-review denial to permission_denied without leaking internals", () => {
  const result = toOcrReviewError({ message: "a reviewer who uploaded or registered the source document cannot review its own OCR output" });
  assert.equal(result.code, "permission_denied");
});

check("maps not-ocr-required error", () => {
  const result = toOcrReviewError({ message: "an OCR request can only be created from an ocr_required extraction review (current status: accepted)" });
  assert.equal(result.code, "not_ocr_required");
});

check("maps superseded-round error", () => {
  const result = toOcrReviewError({ message: "this extraction review round has been superseded by a later round" });
  assert.equal(result.code, "superseded");
});

check("maps no-ocr-candidate-pages error", () => {
  const result = toOcrReviewError({ message: "no pages were marked ocr_candidate in this extraction review; nothing to request" });
  assert.equal(result.code, "no_ocr_candidate_pages");
});

check("maps already-terminal cancellation error", () => {
  const result = toOcrReviewError({ message: "this OCR request is already terminal (status: accepted) and cannot be cancelled" });
  assert.equal(result.code, "already_terminal");
});

check("maps pages-not-terminal error", () => {
  const result = toOcrReviewError({ message: "all OCR page jobs must reach a terminal execution state before a review can be opened (2 still pending)" });
  assert.equal(result.code, "pages_not_terminal");
});

check("maps page coverage error", () => {
  const result = toOcrReviewError({ message: "every OCR page must be marked reviewed before a final decision can be submitted (1 of 3 reviewed)" });
  assert.equal(result.code, "pages_not_reviewed");
});

check("maps accepted-requires-succeeded-pages error", () => {
  const result = toOcrReviewError({ message: "accepted requires every requested OCR page to have succeeded" });
  assert.equal(result.code, "pages_not_succeeded");
});

check("maps accepted-blocked-by-open-findings error", () => {
  const result = toOcrReviewError({ message: "accepted requires zero open critical or major OCR findings (open critical=1, open major=0)" });
  assert.equal(result.code, "open_findings_block_accept");
});

check("maps missing warning_summary error", () => {
  const result = toOcrReviewError({ message: "accepted_with_warnings requires a warning_summary" });
  assert.equal(result.code, "warning_summary_required");
});

check("maps missing reprocessing-supporting-finding error", () => {
  const result = toOcrReviewError({ message: "reprocessing_required requires at least one supporting OCR finding" });
  assert.equal(result.code, "reprocessing_finding_required");
});

check("maps generic decision_reason-required error", () => {
  const result = toOcrReviewError({ message: "rejected requires a decision_reason" });
  assert.equal(result.code, "decision_reason_required");
});

check("maps immutability error", () => {
  const result = toOcrReviewError({ message: "a submitted OCR review round is immutable; reopen it to create a new round" });
  assert.equal(result.code, "immutable");
});

check("maps resolution-note-required error", () => {
  const result = toOcrReviewError({ message: "dismissing or accepting the risk of a critical OCR finding requires a resolution note" });
  assert.equal(result.code, "resolution_note_required");
});

check("falls back to unknown for an unrecognized message", () => {
  const result = toOcrReviewError({ message: "something entirely unexpected happened deep in postgres internals" });
  assert.equal(result.code, "unknown");
  assert.ok(!result.message.includes("postgres internals"));
});

if (failures > 0) {
  console.log(`\n${failures} test(s) failed.`);
  process.exit(1);
}
console.log("\nAll OCR error-mapping tests passed.");
