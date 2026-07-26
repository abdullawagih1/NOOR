import assert from "node:assert/strict";
import { toDocumentIntakeError } from "../lib/documents/errors";

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

check("maps a 42501 permission-denied Postgres error", () => {
  const err = toDocumentIntakeError({ code: "42501", message: "permission denied: guideline_documents.upload required" });
  assert.equal(err.code, "permission_denied");
});

check("maps a not-eligible-for-upload message", () => {
  const err = toDocumentIntakeError({ message: "guideline version status active is not eligible for a new source document upload" });
  assert.equal(err.code, "not_eligible");
});

check("maps an already-has-a-primary message", () => {
  const err = toDocumentIntakeError({ message: "this guideline version already has an active primary source document; it cannot be replaced" });
  assert.equal(err.code, "already_has_primary");
});

check("maps an unsupported-file-type message", () => {
  const err = toDocumentIntakeError({ message: "only application/pdf (.pdf) is supported in this release" });
  assert.equal(err.code, "unsupported_file_type");
});

check("maps an expired-session message", () => {
  const err = toDocumentIntakeError({ message: "upload session expired" });
  assert.equal(err.code, "session_expired");
});

check("maps an immutability message without leaking column names", () => {
  const err = toDocumentIntakeError({
    message: "a verified or registered source document's file identity cannot be changed; create a new guideline version instead",
  });
  assert.equal(err.code, "immutable");
  assert.ok(!err.message.includes("sha256"));
});

check("falls back to a generic, safe message for an unrecognized error", () => {
  const err = toDocumentIntakeError({ message: 'null value in column "organization_id" violates not-null constraint' });
  assert.equal(err.code, "unknown");
  assert.ok(!err.message.includes("organization_id"));
});

if (failures > 0) {
  console.log(`\n${failures} test(s) failed.`);
  process.exit(1);
}
console.log("\nAll document-intake error-mapping tests passed.");
