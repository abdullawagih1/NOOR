import assert from "node:assert/strict";
import {
  clinicalDomainCreateSchema,
  guidelineAuthorityCreateSchema,
  guidelineCreateSchema,
  guidelineVersionCreateSchema,
  guidelineReviewSubmitSchema,
  lifecycleTransitionSchema,
} from "../lib/guidelines/schemas";

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

const ORG_ID = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
const DOMAIN_ID = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";
const AUTHORITY_ID = "cccccccc-cccc-cccc-cccc-cccccccccccc";
const VERSION_ID = "dddddddd-dddd-dddd-dddd-dddddddddddd";
const GUIDELINE_ID = "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee";

check("clinicalDomainCreateSchema accepts a valid domain", () => {
  const result = clinicalDomainCreateSchema.safeParse({ organizationId: ORG_ID, code: "hypertension", name: "Adult Hypertension" });
  assert.ok(result.success);
});

check("clinicalDomainCreateSchema rejects an empty code", () => {
  const result = clinicalDomainCreateSchema.safeParse({ organizationId: ORG_ID, code: "  ", name: "Adult Hypertension" });
  assert.equal(result.success, false);
});

check("guidelineAuthorityCreateSchema defaults isVerified to false", () => {
  const result = guidelineAuthorityCreateSchema.safeParse({ organizationId: ORG_ID, name: "Test Authority" });
  assert.ok(result.success);
  if (result.success) assert.equal(result.data.isVerified, false);
});

check("guidelineCreateSchema requires a canonical title", () => {
  const result = guidelineCreateSchema.safeParse({
    organizationId: ORG_ID,
    clinicalDomainId: DOMAIN_ID,
    authorityId: AUTHORITY_ID,
    internalCode: "HTN-001",
    canonicalTitle: "",
  });
  assert.equal(result.success, false);
});

check("guidelineCreateSchema rejects a non-uuid domain id", () => {
  const result = guidelineCreateSchema.safeParse({
    organizationId: ORG_ID,
    clinicalDomainId: "not-a-uuid",
    authorityId: AUTHORITY_ID,
    internalCode: "HTN-001",
    canonicalTitle: "Adult Hypertension Management",
  });
  assert.equal(result.success, false);
});

check("guidelineVersionCreateSchema rejects effective date before publication date", () => {
  const result = guidelineVersionCreateSchema.safeParse({
    guidelineId: GUIDELINE_ID,
    versionLabel: "v1.0",
    publicationDate: "2024-06-01",
    effectiveDate: "2024-01-01",
  });
  assert.equal(result.success, false);
});

check("guidelineVersionCreateSchema rejects expiry date before effective date", () => {
  const result = guidelineVersionCreateSchema.safeParse({
    guidelineId: GUIDELINE_ID,
    versionLabel: "v1.0",
    effectiveDate: "2024-06-01",
    expiryDate: "2024-01-01",
  });
  assert.equal(result.success, false);
});

check("guidelineVersionCreateSchema accepts valid, well-ordered dates", () => {
  const result = guidelineVersionCreateSchema.safeParse({
    guidelineId: GUIDELINE_ID,
    versionLabel: "v1.0",
    publicationDate: "2024-01-01",
    effectiveDate: "2024-02-01",
    expiryDate: "2026-01-01",
  });
  assert.ok(result.success);
});

check("guidelineReviewSubmitSchema rejects an invalid review status", () => {
  const result = guidelineReviewSubmitSchema.safeParse({ guidelineVersionId: VERSION_ID, reviewStatus: "approved" });
  assert.equal(result.success, false);
});

check("lifecycleTransitionSchema requires a reason for withdrawal", () => {
  const result = lifecycleTransitionSchema.safeParse({ versionId: VERSION_ID, targetStatus: "withdrawn" });
  assert.equal(result.success, false);
});

check("lifecycleTransitionSchema accepts withdrawal with a reason", () => {
  const result = lifecycleTransitionSchema.safeParse({
    versionId: VERSION_ID,
    targetStatus: "withdrawn",
    reason: "Superseding authority guidance retracted",
  });
  assert.ok(result.success);
});

check("lifecycleTransitionSchema does not require a reason for draft -> ready_for_review", () => {
  const result = lifecycleTransitionSchema.safeParse({ versionId: VERSION_ID, targetStatus: "ready_for_review" });
  assert.ok(result.success);
});

check("lifecycleTransitionSchema rejects an unknown target status", () => {
  const result = lifecycleTransitionSchema.safeParse({ versionId: VERSION_ID, targetStatus: "published" });
  assert.equal(result.success, false);
});

if (failures > 0) {
  console.log(`\n${failures} test(s) failed.`);
  process.exit(1);
}
console.log("\nAll guideline registry schema tests passed.");
