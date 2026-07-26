import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";
import { MAX_UPLOAD_SIZE_BYTES } from "../lib/documents/config";

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
const migrationPath = path.resolve(here, "../../../supabase/migrations/0006_secure_guideline_document_intake.sql");
const migrationSql = readFileSync(migrationPath, "utf8");

check("MAX_UPLOAD_SIZE_BYTES matches the hardcoded limit in migration 0006", () => {
  assert.equal(MAX_UPLOAD_SIZE_BYTES, 52_428_800, "the canonical TS constant itself must stay 50 MB");
  assert.ok(
    migrationSql.includes(String(MAX_UPLOAD_SIZE_BYTES)),
    `migration 0006 does not contain the byte value ${MAX_UPLOAD_SIZE_BYTES} — the SQL-side size guard has drifted from apps/web/lib/documents/config.ts`
  );
});

if (failures > 0) {
  console.log(`\n${failures} test(s) failed.`);
  process.exit(1);
}
console.log("\nAll document-intake config consistency tests passed.");
