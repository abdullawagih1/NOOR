import assert from "node:assert/strict";
import {
  datasetCreateSchema,
  datasetUpdateSchema,
  datasetIdSchema,
  datasetReturnToDraftSchema,
  corpusItemAddSchema,
  corpusItemRemoveSchema,
  queryCreateSchema,
  queryUpdateSchema,
  judgmentCreateSchema,
  judgmentUpdateSchema,
  createRunSchema,
  cancelRunSchema,
  failureAnnotationCreateSchema,
  failureAnnotationUpdateSchema,
} from "../lib/retrieval-evaluation/schemas";

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

const DATASET_ID = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
const QUERY_ID = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";
const CORPUS_ITEM_ID = "cccccccc-cccc-cccc-cccc-cccccccccccc";
const CHUNK_ID = "dddddddd-dddd-dddd-dddd-dddddddddddd";
const JUDGMENT_ID = "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee";
const RUN_ID = "ffffffff-ffff-ffff-ffff-ffffffffffff";
const FAILURE_ID = "11111111-1111-1111-1111-111111111111";

check("datasetCreateSchema accepts a minimal valid dataset", () => {
  const result = datasetCreateSchema.safeParse({ logicalName: "noor-retrieval-eval-foundation", version: "1", title: "Foundation dataset" });
  assert.ok(result.success);
});
check("datasetCreateSchema coerces version to a number", () => {
  const result = datasetCreateSchema.safeParse({ logicalName: "x", version: "2", title: "t" });
  assert.ok(result.success);
  if (result.success) assert.equal(result.data.version, 2);
});
check("datasetCreateSchema rejects an empty logical name", () => {
  const result = datasetCreateSchema.safeParse({ logicalName: "", version: "1", title: "t" });
  assert.equal(result.success, false);
});
check("datasetCreateSchema rejects version 0", () => {
  const result = datasetCreateSchema.safeParse({ logicalName: "x", version: "0", title: "t" });
  assert.equal(result.success, false);
});
check("datasetCreateSchema rejects an unknown language in languageScope", () => {
  const result = datasetCreateSchema.safeParse({ logicalName: "x", version: "1", title: "t", languageScope: ["fr"] });
  assert.equal(result.success, false);
});
check("datasetCreateSchema accepts en/ar/mixed language scope", () => {
  const result = datasetCreateSchema.safeParse({ logicalName: "x", version: "1", title: "t", languageScope: ["en", "ar", "mixed"] });
  assert.ok(result.success);
});

check("datasetUpdateSchema accepts a dataset id with no other fields", () => {
  const result = datasetUpdateSchema.safeParse({ datasetId: DATASET_ID });
  assert.ok(result.success);
});
check("datasetUpdateSchema rejects a non-uuid dataset id", () => {
  const result = datasetUpdateSchema.safeParse({ datasetId: "not-a-uuid" });
  assert.equal(result.success, false);
});

check("datasetIdSchema requires a valid uuid", () => {
  const result = datasetIdSchema.safeParse({ datasetId: DATASET_ID });
  assert.ok(result.success);
});

check("datasetReturnToDraftSchema requires a non-empty reason", () => {
  const result = datasetReturnToDraftSchema.safeParse({ datasetId: DATASET_ID, reason: "" });
  assert.equal(result.success, false);
});
check("datasetReturnToDraftSchema accepts a valid reason", () => {
  const result = datasetReturnToDraftSchema.safeParse({ datasetId: DATASET_ID, reason: "corpus item needs replacing" });
  assert.ok(result.success);
});

check("corpusItemAddSchema requires both ids to be valid uuids", () => {
  const result = corpusItemAddSchema.safeParse({ datasetId: DATASET_ID, chunkId: CHUNK_ID });
  assert.ok(result.success);
});
check("corpusItemAddSchema rejects a non-uuid chunk id", () => {
  const result = corpusItemAddSchema.safeParse({ datasetId: DATASET_ID, chunkId: "not-a-uuid" });
  assert.equal(result.success, false);
});

check("corpusItemRemoveSchema accepts valid ids", () => {
  const result = corpusItemRemoveSchema.safeParse({ datasetId: DATASET_ID, corpusItemId: CORPUS_ITEM_ID });
  assert.ok(result.success);
});

check("queryCreateSchema accepts a valid english_exact query", () => {
  const result = queryCreateSchema.safeParse({
    datasetId: DATASET_ID,
    queryKey: "q-en-exact",
    queryText: "blood pressure measurement",
    language: "en",
    category: "english_exact",
    difficulty: "basic",
  });
  assert.ok(result.success);
});
check("queryCreateSchema rejects an unknown category", () => {
  const result = queryCreateSchema.safeParse({
    datasetId: DATASET_ID,
    queryKey: "q1",
    queryText: "x",
    language: "en",
    category: "not_a_real_category",
    difficulty: "basic",
  });
  assert.equal(result.success, false);
});
check("queryCreateSchema rejects an unknown difficulty", () => {
  const result = queryCreateSchema.safeParse({
    datasetId: DATASET_ID,
    queryKey: "q1",
    queryText: "x",
    language: "en",
    category: "keyword_lookup",
    difficulty: "impossible",
  });
  assert.equal(result.success, false);
});
check("queryCreateSchema coerces isNegativeControl and defaults to false", () => {
  const result = queryCreateSchema.safeParse({
    datasetId: DATASET_ID,
    queryKey: "q1",
    queryText: "x",
    language: "en",
    category: "negative_control",
    difficulty: "basic",
  });
  assert.ok(result.success);
  if (result.success) assert.equal(result.data.isNegativeControl, false);
});
check("queryCreateSchema rejects empty query text", () => {
  const result = queryCreateSchema.safeParse({
    datasetId: DATASET_ID,
    queryKey: "q1",
    queryText: "",
    language: "en",
    category: "keyword_lookup",
    difficulty: "basic",
  });
  assert.equal(result.success, false);
});

check("queryUpdateSchema accepts a partial update", () => {
  // z.coerce.boolean() follows JS Boolean() coercion — any non-empty
  // string (including "false") coerces to true. The server action never
  // passes a string here (it resolves to a real boolean before calling
  // this schema — see createEvaluationQueryAction's checkbox() helper).
  const result = queryUpdateSchema.safeParse({ datasetId: DATASET_ID, queryId: QUERY_ID, active: false });
  assert.ok(result.success);
  if (result.success) assert.equal(result.data.active, false);
});

check("judgmentCreateSchema accepts a valid grade", () => {
  const result = judgmentCreateSchema.safeParse({ datasetId: DATASET_ID, queryId: QUERY_ID, corpusItemId: CORPUS_ITEM_ID, relevanceGrade: "3" });
  assert.ok(result.success);
  if (result.success) assert.equal(result.data.relevanceGrade, 3);
});
check("judgmentCreateSchema rejects grade 4", () => {
  const result = judgmentCreateSchema.safeParse({ datasetId: DATASET_ID, queryId: QUERY_ID, corpusItemId: CORPUS_ITEM_ID, relevanceGrade: "4" });
  assert.equal(result.success, false);
});
check("judgmentCreateSchema rejects a negative grade", () => {
  const result = judgmentCreateSchema.safeParse({ datasetId: DATASET_ID, queryId: QUERY_ID, corpusItemId: CORPUS_ITEM_ID, relevanceGrade: "-1" });
  assert.equal(result.success, false);
});
check("judgmentCreateSchema accepts grade 0 (not relevant)", () => {
  const result = judgmentCreateSchema.safeParse({ datasetId: DATASET_ID, queryId: QUERY_ID, corpusItemId: CORPUS_ITEM_ID, relevanceGrade: "0" });
  assert.ok(result.success);
});

check("judgmentUpdateSchema accepts a review status", () => {
  const result = judgmentUpdateSchema.safeParse({ datasetId: DATASET_ID, judgmentId: JUDGMENT_ID, reviewStatus: "confirmed" });
  assert.ok(result.success);
});
check("judgmentUpdateSchema rejects an unknown review status", () => {
  const result = judgmentUpdateSchema.safeParse({ datasetId: DATASET_ID, judgmentId: JUDGMENT_ID, reviewStatus: "not_a_status" });
  assert.equal(result.success, false);
});

check("createRunSchema accepts no overrides", () => {
  const result = createRunSchema.safeParse({ datasetId: DATASET_ID });
  assert.ok(result.success);
});
check("createRunSchema coerces relevanceThreshold", () => {
  const result = createRunSchema.safeParse({ datasetId: DATASET_ID, relevanceThreshold: "2" });
  assert.ok(result.success);
  if (result.success) assert.equal(result.data.relevanceThreshold, 2);
});
check("createRunSchema rejects a relevanceThreshold above 3", () => {
  const result = createRunSchema.safeParse({ datasetId: DATASET_ID, relevanceThreshold: "4" });
  assert.equal(result.success, false);
});

check("cancelRunSchema requires a non-empty reason", () => {
  const result = cancelRunSchema.safeParse({ datasetId: DATASET_ID, runId: RUN_ID, reason: "" });
  assert.equal(result.success, false);
});
check("cancelRunSchema accepts a valid reason", () => {
  const result = cancelRunSchema.safeParse({ datasetId: DATASET_ID, runId: RUN_ID, reason: "wrong config version" });
  assert.ok(result.success);
});

check("failureAnnotationCreateSchema accepts a valid category", () => {
  const result = failureAnnotationCreateSchema.safeParse({ datasetId: DATASET_ID, runId: RUN_ID, queryId: QUERY_ID, failureCategory: "judgment_gap" });
  assert.ok(result.success);
});
check("failureAnnotationCreateSchema rejects an unknown category", () => {
  const result = failureAnnotationCreateSchema.safeParse({ datasetId: DATASET_ID, runId: RUN_ID, queryId: QUERY_ID, failureCategory: "made_up_category" });
  assert.equal(result.success, false);
});

check("failureAnnotationUpdateSchema accepts a status-only update", () => {
  const result = failureAnnotationUpdateSchema.safeParse({ datasetId: DATASET_ID, runId: RUN_ID, failureId: FAILURE_ID, status: "resolved" });
  assert.ok(result.success);
});
check("failureAnnotationUpdateSchema rejects an unknown status", () => {
  const result = failureAnnotationUpdateSchema.safeParse({ datasetId: DATASET_ID, runId: RUN_ID, failureId: FAILURE_ID, status: "not_a_status" });
  assert.equal(result.success, false);
});

if (failures > 0) {
  console.log(`\n${failures} test(s) failed.`);
  process.exit(1);
}
console.log("\nAll retrieval-evaluation schema tests passed.");
