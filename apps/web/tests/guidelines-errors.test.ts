import assert from "node:assert/strict";
import { toGuidelineRegistryError } from "../lib/guidelines/errors";

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
  const err = toGuidelineRegistryError({ code: "42501", message: "permission denied: guidelines.approve required" });
  assert.equal(err.code, "permission_denied");
});

check("maps a unique_violation to a duplicate error, without leaking the constraint name", () => {
  const err = toGuidelineRegistryError({ code: "23505", message: 'duplicate key value violates unique constraint "guidelines_organization_id_internal_code_key"' });
  assert.equal(err.code, "duplicate");
  assert.ok(!err.message.includes("guidelines_organization_id_internal_code_key"));
});

check("maps an illegal-transition message", () => {
  const err = toGuidelineRegistryError({ message: "illegal lifecycle transition: draft -> active" });
  assert.equal(err.code, "illegal_transition");
});

check("maps a missing-review-recommendation message", () => {
  const err = toGuidelineRegistryError({ message: "approval requires at least one review recommending approval" });
  assert.equal(err.code, "review_required");
});

check("maps a self-approval message", () => {
  const err = toGuidelineRegistryError({ message: "self-approval is not permitted: the version author cannot approve their own version" });
  assert.equal(err.code, "self_action_blocked");
});

check("maps a self-review message", () => {
  const err = toGuidelineRegistryError({ message: "a guideline version cannot be reviewed by its own creator" });
  assert.equal(err.code, "self_action_blocked");
});

check("maps a missing-reason message", () => {
  const err = toGuidelineRegistryError({ message: "a withdrawal reason is required" });
  assert.equal(err.code, "reason_required");
});

check("falls back to a generic, safe message for an unrecognized error", () => {
  const err = toGuidelineRegistryError({ message: 'null value in column "organization_id" violates not-null constraint' });
  assert.equal(err.code, "unknown");
  assert.ok(!err.message.includes("organization_id"));
});

if (failures > 0) {
  console.log(`\n${failures} test(s) failed.`);
  process.exit(1);
}
console.log("\nAll guideline registry error-mapping tests passed.");
