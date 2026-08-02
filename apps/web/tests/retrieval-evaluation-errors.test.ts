import assert from "node:assert/strict";
import { toRetrievalEvaluationError } from "../lib/retrieval-evaluation/errors";

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

check("maps permission denied", () => {
  const result = toRetrievalEvaluationError({ code: "42501", message: "permission denied" });
  assert.equal(result.code, "permission_denied");
});

check("maps self-review block", () => {
  const result = toRetrievalEvaluationError({ message: "a dataset creator cannot review their own dataset for freezing" });
  assert.equal(result.code, "self_review_blocked");
});

check("maps missing corpus item requirement", () => {
  const result = toRetrievalEvaluationError({ message: "a dataset needs at least one corpus item before review" });
  assert.equal(result.code, "corpus_item_required");
});

check("maps missing active query requirement", () => {
  const result = toRetrievalEvaluationError({ message: "a dataset needs at least one active query before review" });
  assert.equal(result.code, "active_query_required");
});

check("maps judgment coverage incomplete", () => {
  const result = toRetrievalEvaluationError({ message: "the following queries have no relevant (grade >= 2) judgment: q-en-exact" });
  assert.equal(result.code, "judgment_coverage_incomplete");
});

check("maps negative-control false positive", () => {
  const result = toRetrievalEvaluationError({ message: "the following negative-control queries have a positive relevance judgment: q-negative" });
  assert.equal(result.code, "negative_control_false_positive");
});

check("maps dataset-not-frozen for evaluation runs", () => {
  const result = toRetrievalEvaluationError({ message: "evaluation runs require a frozen dataset (current status: draft)" });
  assert.equal(result.code, "dataset_not_frozen");
});

check("maps not-currently-embedding-ready chunk", () => {
  const result = toRetrievalEvaluationError({ message: "chunk 123 is not currently embedding-ready (status: rechunk_required)" });
  assert.equal(result.code, "not_embedding_ready");
});

check("maps dataset no longer frozen", () => {
  const result = toRetrievalEvaluationError({ message: "dataset x is no longer frozen (status: archived)" });
  assert.equal(result.code, "dataset_no_longer_frozen");
});

check("maps invalid relevance grade", () => {
  const result = toRetrievalEvaluationError({ message: "relevance_grade must be 0, 1, 2, or 3" });
  assert.equal(result.code, "invalid_relevance_grade");
});

check("maps not-draft edit rejection", () => {
  const result = toRetrievalEvaluationError({ message: "corpus items can only be added while the dataset is draft (current status: frozen)" });
  assert.equal(result.code, "not_draft");
});

check("maps not-ready-for-review rejection", () => {
  const result = toRetrievalEvaluationError({ message: "only a ready_for_review dataset can return to draft (current status: draft)" });
  assert.equal(result.code, "not_ready_for_review");
});

check("maps reason-required rejection", () => {
  const result = toRetrievalEvaluationError({ message: "cancelling a run requires a reason" });
  assert.equal(result.code, "reason_required");
});

check("maps not-running cancellation rejection", () => {
  const result = toRetrievalEvaluationError({ message: "only a running evaluation run can be cancelled (current status: succeeded)" });
  assert.equal(result.code, "not_running");
});

check("maps immutable-record rejection", () => {
  const result = toRetrievalEvaluationError({ message: "an archived dataset is immutable" });
  assert.equal(result.code, "immutable");
});

check("maps failure-annotation content immutability", () => {
  const result = toRetrievalEvaluationError({ message: "a failure annotation's core content is immutable once created" });
  assert.equal(result.code, "failure_content_immutable");
});

check("maps duplicate dataset version", () => {
  const result = toRetrievalEvaluationError({ message: 'duplicate key value violates unique constraint "retrieval_evaluation_datasets_organization_id_logical_name_version_key"' });
  assert.equal(result.code, "duplicate");
});

check("maps not-found", () => {
  const result = toRetrievalEvaluationError({ message: "dataset not found: 00000000-0000-0000-0000-000000000000" });
  assert.equal(result.code, "not_found");
});

check("falls back to unknown for an unrecognized message and never leaks internals", () => {
  const result = toRetrievalEvaluationError({ message: "something entirely unexpected happened deep in postgres internals" });
  assert.equal(result.code, "unknown");
  assert.ok(!result.message.includes("postgres internals"));
});

if (failures > 0) {
  console.log(`\n${failures} test(s) failed.`);
  process.exit(1);
}
console.log("\nAll retrieval-evaluation error-mapping tests passed.");
