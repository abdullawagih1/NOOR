import assert from "node:assert/strict";
import { createEmbeddingJobSchema, cancelEmbeddingRunSchema } from "../lib/embeddings/schemas";

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

const SOURCE_DOCUMENT_ID = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
const EMBEDDING_RUN_ID = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";

check("createEmbeddingJobSchema accepts a valid source document id", () => {
  const result = createEmbeddingJobSchema.safeParse({ sourceDocumentId: SOURCE_DOCUMENT_ID });
  assert.ok(result.success);
});
check("createEmbeddingJobSchema rejects a non-uuid source document id", () => {
  const result = createEmbeddingJobSchema.safeParse({ sourceDocumentId: "not-a-uuid" });
  assert.equal(result.success, false);
});
check("createEmbeddingJobSchema rejects a missing source document id", () => {
  const result = createEmbeddingJobSchema.safeParse({});
  assert.equal(result.success, false);
});

check("cancelEmbeddingRunSchema requires a non-empty reason", () => {
  const result = cancelEmbeddingRunSchema.safeParse({ embeddingRunId: EMBEDDING_RUN_ID, reason: "" });
  assert.equal(result.success, false);
});
check("cancelEmbeddingRunSchema accepts a valid reason", () => {
  const result = cancelEmbeddingRunSchema.safeParse({ embeddingRunId: EMBEDDING_RUN_ID, reason: "wrong model revision" });
  assert.ok(result.success);
});
check("cancelEmbeddingRunSchema rejects a non-uuid embedding run id", () => {
  const result = cancelEmbeddingRunSchema.safeParse({ embeddingRunId: "not-a-uuid", reason: "wrong model revision" });
  assert.equal(result.success, false);
});

if (failures > 0) {
  console.log(`\n${failures} test(s) failed.`);
  process.exit(1);
}
console.log("\nAll embeddings schema tests passed.");
