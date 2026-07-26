import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
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
const migrationsDir = path.resolve(here, "../../../supabase/migrations");

// Permissions are seeded across multiple migrations as the app grows
// (0002 for Sprint 0 workspace access, 0005 for the guideline registry,
// etc.) — concatenate every migration file rather than pinning to one, so
// this test keeps working as new permission-bearing migrations are added.
const migrationSql = readdirSync(migrationsDir)
  .filter((f) => f.endsWith(".sql"))
  .sort()
  .map((f) => readFileSync(path.join(migrationsDir, f), "utf8"))
  .join("\n");

check("every PERMISSIONS constant used by the app is actually seeded in a migration", () => {
  for (const key of Object.values(PERMISSIONS)) {
    assert.ok(
      migrationSql.includes(`'${key}'`),
      `permission key "${key}" is referenced in lib/auth/permissions.ts but not seeded in any supabase/migrations/*.sql file`
    );
  }
});

check("each workspace permission is mapped to at least one role across migrations", () => {
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
      `"${key}" is seeded but never mapped to a role in any (role_key, permission_key) VALUES list`
    );
  }
});

check("each guideline registry permission is mapped to at least one role", () => {
  const guidelinePermissions = [
    PERMISSIONS.GUIDELINES_READ_ACTIVE,
    PERMISSIONS.GUIDELINES_READ_ALL,
    PERMISSIONS.GUIDELINES_CREATE,
    PERMISSIONS.GUIDELINES_UPDATE_DRAFT,
    PERMISSIONS.GUIDELINES_SUBMIT_FOR_REVIEW,
    PERMISSIONS.GUIDELINES_REVIEW,
    PERMISSIONS.GUIDELINES_APPROVE,
    PERMISSIONS.GUIDELINES_ACTIVATE,
    PERMISSIONS.GUIDELINES_SUPERSEDE,
    PERMISSIONS.GUIDELINES_WITHDRAW,
    PERMISSIONS.GUIDELINE_AUTHORITIES_MANAGE,
    PERMISSIONS.CLINICAL_DOMAINS_MANAGE,
  ];
  for (const key of guidelinePermissions) {
    const mappingCount = (migrationSql.match(new RegExp(`'${key}'`, "g")) ?? []).length;
    assert.ok(mappingCount >= 2, `"${key}" is seeded but never mapped to a role in any (role_key, permission_key) VALUES list`);
  }
});

if (failures > 0) {
  console.log(`\n${failures} test(s) failed.`);
  process.exit(1);
}
console.log("\nAll permission-consistency tests passed.");
