import assert from "node:assert/strict";
import { toChunkingReviewError } from "../lib/chunking/errors";

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
  const result = toChunkingReviewError({ code: "42501", message: "permission denied for function submit_document_chunking_review" });
  assert.equal(result.code, "permission_denied");
  assert.ok(!result.message.includes("function submit_document_chunking_review"));
});

check("maps self-review denial to permission_denied without leaking internals", () => {
  const result = toChunkingReviewError({ message: "a reviewer who uploaded or registered the source document cannot review its own chunking output" });
  assert.equal(result.code, "permission_denied");
});

check("maps not-eligible error", () => {
  const result = toChunkingReviewError({ message: "this document is not chunking-eligible (review status: pending_review)" });
  assert.equal(result.code, "not_eligible");
});

check("maps no-extraction-run error", () => {
  const result = toChunkingReviewError({ message: "no succeeded extraction run exists for this document" });
  assert.equal(result.code, "no_extraction_run");
});

check("maps run-not-succeeded error", () => {
  const result = toChunkingReviewError({ message: "a chunking review can only be created for a succeeded run (current status: running)" });
  assert.equal(result.code, "run_not_succeeded");
});

check("maps reviewer-lacks-permission error", () => {
  const result = toChunkingReviewError({ message: "reviewer 11111111-... does not hold chunking review permission in this organization" });
  assert.equal(result.code, "reviewer_lacks_permission");
});

check("maps chunks-not-reviewed error", () => {
  const result = toChunkingReviewError({ message: "every chunk must be marked reviewed before a final decision can be submitted (1 of 3 reviewed)" });
  assert.equal(result.code, "chunks_not_reviewed");
});

check("maps accepted-blocked-by-open-findings error", () => {
  const result = toChunkingReviewError({ message: "accepted requires zero open critical or major findings (open critical=1, open major=0)" });
  assert.equal(result.code, "open_findings_block_accept");
});

check("maps missing warning_summary error", () => {
  const result = toChunkingReviewError({ message: "accepted_with_warnings requires a warning_summary" });
  assert.equal(result.code, "warning_summary_required");
});

check("maps missing rechunk-supporting-finding error", () => {
  const result = toChunkingReviewError({ message: "rechunk_required requires at least one supporting finding" });
  assert.equal(result.code, "rechunk_finding_required");
});

check("maps missing rejected-supporting-finding error", () => {
  const result = toChunkingReviewError({ message: "rejected requires at least one major or critical finding to exist" });
  assert.equal(result.code, "rejected_finding_required");
});

check("maps generic decision_reason-required error", () => {
  const result = toChunkingReviewError({ message: "rechunk_required requires a decision_reason" });
  assert.equal(result.code, "decision_reason_required");
});

check("maps immutability error", () => {
  const result = toChunkingReviewError({ message: "chunking review 11111111-... is already terminal (status: accepted) and cannot be modified" });
  assert.equal(result.code, "immutable");
});

check("maps not-reopenable error", () => {
  const result = toChunkingReviewError({ message: "only a submitted, non-invalidated chunking decision can be reopened (current status: pending_review)" });
  assert.equal(result.code, "not_reopenable");
});

check("maps not-invalidatable error", () => {
  const result = toChunkingReviewError({ message: "only a succeeded or reused chunking run can be invalidated (current status: failed)" });
  assert.equal(result.code, "not_invalidatable");
});

check("falls back to unknown for an unrecognized message", () => {
  const result = toChunkingReviewError({ message: "something entirely unexpected happened deep in postgres internals" });
  assert.equal(result.code, "unknown");
  assert.ok(!result.message.includes("postgres internals"));
});

if (failures > 0) {
  console.log(`\n${failures} test(s) failed.`);
  process.exit(1);
}
console.log("\nAll chunking error-mapping tests passed.");
