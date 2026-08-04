import assert from "node:assert/strict";
import { resolvePostLoginDestination, resolveDefaultWorkspacePath } from "../lib/auth/redirect";
import { PERMISSIONS } from "../lib/auth/permissions";

/**
 * LX-1.2 mission §24's login routing test matrix, expressed against
 * the pure `resolvePostLoginDestination` resolver — no Supabase/DB
 * dependency, matching every other test file's convention in this
 * directory. Real end-to-end confirmation (an actual browser
 * completing a real sign-in) is recorded separately in
 * docs/verification/lx-1-2-production-integration.md.
 */

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

const CLINICIAN = { kind: "authorized" as const, permissionKeys: [PERMISSIONS.WORKSPACE_CLINICIAN_ACCESS] };
const ADMIN = { kind: "authorized" as const, permissionKeys: [PERMISSIONS.WORKSPACE_ADMIN_ACCESS] };
const NO_WORKSPACE_PERMISSION = { kind: "authorized" as const, permissionKeys: [PERMISSIONS.GUIDELINES_READ_ACTIVE] };
const NO_MEMBERSHIP = { kind: "no_active_membership" as const };
const NO_PROFILE = { kind: "no_profile" as const };
const UNAUTHENTICATED = { kind: "unauthenticated" as const };

check("successful login with no requested path resolves to the authorized default workspace", () => {
  assert.equal(resolvePostLoginDestination(undefined, CLINICIAN), "/clinician");
  assert.equal(resolvePostLoginDestination("", ADMIN), "/admin");
});

check('an explicit "/" requested path is treated the same as no request at all', () => {
  assert.equal(resolvePostLoginDestination("/", CLINICIAN), "/clinician");
});

check("a safe internal path the caller is authorized for is honored", () => {
  assert.equal(resolvePostLoginDestination("/clinician/documents", CLINICIAN), "/clinician/documents");
  assert.equal(resolvePostLoginDestination("/admin", ADMIN), "/admin");
});

check("a non-workspace-gated safe path is honored regardless of membership state (e.g. password reset)", () => {
  assert.equal(resolvePostLoginDestination("/update-password", CLINICIAN), "/update-password");
  assert.equal(resolvePostLoginDestination("/update-password", NO_MEMBERSHIP), "/update-password");
  assert.equal(resolvePostLoginDestination("/knowledge/guidelines", CLINICIAN), "/knowledge/guidelines");
});

check("a requested workspace path the caller is NOT authorized for falls back to their own default workspace", () => {
  assert.equal(resolvePostLoginDestination("/admin", CLINICIAN), "/clinician");
});

check("a requested workspace path with no authorized workspace at all falls back to /access-denied", () => {
  assert.equal(resolvePostLoginDestination("/admin", NO_WORKSPACE_PERMISSION), "/access-denied");
});

check("an external URL in the requested path is ignored, never followed (open-redirect protection)", () => {
  assert.equal(resolvePostLoginDestination("https://evil.example/phish", CLINICIAN), "/clinician");
  assert.equal(resolvePostLoginDestination("//evil.example", ADMIN), "/admin");
});

check("no active membership resolves to /access-denied", () => {
  assert.equal(resolvePostLoginDestination(undefined, NO_MEMBERSHIP), "/access-denied");
  assert.equal(resolvePostLoginDestination("/", NO_MEMBERSHIP), "/access-denied");
});

check("no profile row resolves to /access-denied", () => {
  assert.equal(resolvePostLoginDestination(undefined, NO_PROFILE), "/access-denied");
});

check("an authorized membership with no workspace-access permission at all resolves to /access-denied", () => {
  assert.equal(resolvePostLoginDestination(undefined, NO_WORKSPACE_PERMISSION), "/access-denied");
});

check("unauthenticated access never resolves to a workspace", () => {
  assert.equal(resolvePostLoginDestination(undefined, UNAUTHENTICATED), "/access-denied");
});

check("resolvePostLoginDestination never returns the public landing page", () => {
  const allAccessStates = [CLINICIAN, ADMIN, NO_WORKSPACE_PERMISSION, NO_MEMBERSHIP, NO_PROFILE, UNAUTHENTICATED];
  const allRequestedPaths = [undefined, "", "/", "/admin", "/clinician", "https://evil.example", "//evil.example"];
  for (const access of allAccessStates) {
    for (const requestedPath of allRequestedPaths) {
      assert.notEqual(resolvePostLoginDestination(requestedPath, access), "/");
    }
  }
});

check("resolveDefaultWorkspacePath maps each workspace-access permission to its own route", () => {
  assert.equal(resolveDefaultWorkspacePath([PERMISSIONS.WORKSPACE_ADMIN_ACCESS]), "/admin");
  assert.equal(resolveDefaultWorkspacePath([PERMISSIONS.WORKSPACE_QUALITY_ACCESS]), "/quality");
  assert.equal(resolveDefaultWorkspacePath([PERMISSIONS.WORKSPACE_REVIEWER_ACCESS]), "/reviewer");
  assert.equal(resolveDefaultWorkspacePath([PERMISSIONS.WORKSPACE_CLINICIAN_ACCESS]), "/clinician");
  assert.equal(resolveDefaultWorkspacePath([]), null);
  assert.equal(resolveDefaultWorkspacePath([PERMISSIONS.GUIDELINES_READ_ACTIVE]), null);
});

if (failures > 0) {
  console.log(`\n${failures} test(s) failed.`);
  process.exit(1);
}
console.log("\nAll post-login redirect resolver tests passed.");
