import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";
import { PERMISSIONS } from "../lib/auth/permissions";

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

const here = path.dirname(fileURLToPath(import.meta.url));
const migrationPath = path.resolve(here, "../../../supabase/migrations/0002_sprint0_auth_hardening.sql");
const migrationSql = readFileSync(migrationPath, "utf8");

check("every PERMISSIONS constant used by the app is actually seeded in migration 0002", () => {
  for (const key of Object.values(PERMISSIONS)) {
    assert.ok(
      migrationSql.includes(`'${key}'`),
      `permission key "${key}" is referenced in lib/auth/permissions.ts but not seeded in 0002_sprint0_auth_hardening.sql`
    );
  }
});

check("each workspace permission is mapped to at least one role in migration 0002", () => {
  const workspacePermissions = [
    PERMISSIONS.WORKSPACE_CLINICIAN_ACCESS,
    PERMISSIONS.WORKSPACE_ADMIN_ACCESS,
    PERMISSIONS.WORKSPACE_REVIEWER_ACCESS,
    PERMISSIONS.WORKSPACE_QUALITY_ACCESS,
  ];
  for (const key of workspacePermissions) {
    const mappingCount = (migrationSql.match(new RegExp(`'${key}'`, "g")) ?? []).length;
    // 1 occurrence = the permissions seed row itself; a real role mapping needs at least one more.
    assert.ok(
      mappingCount >= 2,
      `"${key}" is seeded but never mapped to a role in the (role_key, permission_key) VALUES list`
    );
  }
});

if (failures > 0) {
  console.log(`\n${failures} test(s) failed.`);
  process.exit(1);
}
console.log("\nAll permission-consistency tests passed.");
