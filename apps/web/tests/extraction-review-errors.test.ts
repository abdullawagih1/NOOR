import assert from "node:assert/strict";
import { toExtractionReviewError } from "../lib/extraction-review/errors";

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
  const result = toExtractionReviewError({ code: "42501", message: "permission denied for function submit_document_extraction_review" });
  assert.equal(result.code, "permission_denied");
  assert.ok(!result.message.includes("function submit_document_extraction_review"));
});

check("maps self-review denial to permission_denied without leaking internals", () => {
  const result = toExtractionReviewError({ message: "a reviewer who uploaded or registered the source document cannot review its own extraction" });
  assert.equal(result.code, "permission_denied");
});

check("maps 'not_succeeded' extraction run error", () => {
  const result = toExtractionReviewError({ message: "extraction review can only be opened for a succeeded extraction run (current status: running)" });
  assert.equal(result.code, "not_succeeded");
});

check("maps page coverage error", () => {
  const result = toExtractionReviewError({ message: "every page must be marked reviewed before a final decision can be submitted (1 of 3 reviewed)" });
  assert.equal(result.code, "pages_not_reviewed");
});

check("maps accepted-blocked-by-open-findings error", () => {
  const result = toExtractionReviewError({ message: "accepted requires zero open critical or major findings (open critical=1, open major=0)" });
  assert.equal(result.code, "open_findings_block_accept");
});

check("maps missing warning_summary error", () => {
  const result = toExtractionReviewError({ message: "accepted_with_warnings requires a warning_summary" });
  assert.equal(result.code, "warning_summary_required");
});

check("maps missing OCR-supporting-finding error", () => {
  const result = toExtractionReviewError({ message: "ocr_required requires at least one supporting finding (image_only_page, suspected_scanned_page, missing_text, partial_text, or unexpected_blank_page)" });
  assert.equal(result.code, "ocr_finding_required");
});

check("maps generic decision_reason-required error", () => {
  const result = toExtractionReviewError({ message: "reprocessing_required requires a decision_reason" });
  assert.equal(result.code, "decision_reason_required");
});

check("maps rejected-needs-finding error", () => {
  const result = toExtractionReviewError({ message: "rejected requires at least one major or critical finding to exist" });
  assert.equal(result.code, "rejected_finding_required");
});

check("maps immutability error", () => {
  const result = toExtractionReviewError({ message: "a submitted extraction review round is immutable; reopen it to create a new round" });
  assert.equal(result.code, "immutable");
});

check("maps resolution-note-required error", () => {
  const result = toExtractionReviewError({ message: "dismissing or accepting the risk of a critical finding requires a resolution note" });
  assert.equal(result.code, "resolution_note_required");
});

check("falls back to unknown for an unrecognized message", () => {
  const result = toExtractionReviewError({ message: "something entirely unexpected happened deep in postgres internals" });
  assert.equal(result.code, "unknown");
  assert.ok(!result.message.includes("postgres internals"));
});

if (failures > 0) {
  console.log(`\n${failures} test(s) failed.`);
  process.exit(1);
}
console.log("\nAll extraction-review error-mapping tests passed.");
