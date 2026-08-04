import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";

/**
 * Source-level regression checks for the LX-1.1.1 cinematic Preview
 * gate (mission §5/§28): the /design/cinematic-landing route must stay
 * 404 on a real production build unless NOOR_CINEMATIC_PREVIEW_ENABLED
 * is exactly "true", and must render dynamically so the gate is a
 * genuine per-request check rather than a value baked in at build
 * time. Same lightweight source-check pattern as every other test file
 * in this directory — the actual 404-vs-200 behavior against a real
 * production build was verified manually via curl, recorded in
 * docs/verification/lx-1-1-1-cinematic-polish-verification.md and
 * docs/landing/NOOR_CINEMATIC_PREVIEW_DEPLOYMENT.md.
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

const cinematicDir = join(__dirname, "..", "app", "design", "cinematic-landing");
const read = (relativePath: string) => readFileSync(join(cinematicDir, relativePath), "utf-8");

check("cinematic-landing page forces dynamic rendering (no build-time-baked gate)", () => {
  const source = read("page.tsx");
  assert.match(source, /export const dynamic = "force-dynamic";/);
});

check("cinematic-landing page 404s in production unless the Preview flag is exactly \"true\"", () => {
  const source = read("page.tsx");
  assert.match(source, /process\.env\.NODE_ENV === "production"/);
  assert.match(source, /process\.env\.NOOR_CINEMATIC_PREVIEW_ENABLED === "true"/);
  assert.match(source, /notFound\(\)/);
});

check("the Preview gate check runs before any client-side experience is imported and rendered", () => {
  const source = read("page.tsx");
  const gateIndex = source.indexOf("notFound()");
  const experienceUsageIndex = source.indexOf("<CinematicExperience");
  assert.ok(gateIndex > -1, "notFound() call not found");
  assert.ok(experienceUsageIndex > -1, "<CinematicExperience usage not found");
  assert.ok(gateIndex < experienceUsageIndex, "gate must run before the experience is rendered");
});

check(".env.example documents NOOR_CINEMATIC_PREVIEW_ENABLED", () => {
  const source = readFileSync(join(__dirname, "..", ".env.example"), "utf-8");
  assert.match(source, /NOOR_CINEMATIC_PREVIEW_ENABLED/);
});

if (failures > 0) {
  console.log(`\n${failures} test(s) failed.`);
  process.exit(1);
}
console.log("\nAll cinematic Preview-gate regression tests passed.");
