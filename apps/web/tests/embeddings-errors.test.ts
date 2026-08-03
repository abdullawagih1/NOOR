import assert from "node:assert/strict";
import { toEmbeddingError } from "../lib/embeddings/errors";

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
  const result = toEmbeddingError({ code: "42501", message: "permission denied" });
  assert.equal(result.code, "permission_denied");
});

check("maps authentication required", () => {
  const result = toEmbeddingError({ message: "authentication required" });
  assert.equal(result.code, "permission_denied");
});

check("maps embedding_input_not_ready", () => {
  const result = toEmbeddingError({ message: "embedding_input_not_ready: no succeeded chunking run exists for this document" });
  assert.equal(result.code, "embedding_input_not_ready");
});

check("maps embedding_configuration_not_approved", () => {
  const result = toEmbeddingError({ message: "embedding_configuration_not_approved" });
  assert.equal(result.code, "embedding_configuration_not_approved");
});

check("maps reason-required rejection", () => {
  const result = toEmbeddingError({ message: "cancelling an embedding run requires a reason" });
  assert.equal(result.code, "reason_required");
});

check("maps not-cancellable rejection", () => {
  const result = toEmbeddingError({ message: "only a created, queued, or processing embedding run can be cancelled (current status: succeeded)" });
  assert.equal(result.code, "not_cancellable");
});

check("maps already-terminal immutability", () => {
  const result = toEmbeddingError({ message: "embedding run 123 is already terminal (status: succeeded) and cannot be modified" });
  assert.equal(result.code, "immutable");
});

check("maps succeeded-chunk immutability", () => {
  const result = toEmbeddingError({ message: "chunk embedding 123 is immutable once succeeded" });
  assert.equal(result.code, "immutable");
});

check("maps vector checksum conflict", () => {
  const result = toEmbeddingError({ message: "embedding_vector_checksum_failed: conflicting vector checksum for identity abc" });
  assert.equal(result.code, "vector_checksum_conflict");
});

check("maps vector dimension mismatch", () => {
  const result = toEmbeddingError({ message: "embedding_dimension_mismatch: expected 768, got 512" });
  assert.equal(result.code, "vector_dimension_mismatch");
});

check("maps not-found", () => {
  const result = toEmbeddingError({ message: "embedding run not found: 00000000-0000-0000-0000-000000000000" });
  assert.equal(result.code, "not_found");
});

check("falls back to unknown for an unrecognized message and never leaks internals", () => {
  const result = toEmbeddingError({ message: "something entirely unexpected happened deep in postgres internals" });
  assert.equal(result.code, "unknown");
  assert.ok(!result.message.includes("postgres internals"));
});

if (failures > 0) {
  console.log(`\n${failures} test(s) failed.`);
  process.exit(1);
}
console.log("\nAll embeddings error-mapping tests passed.");
