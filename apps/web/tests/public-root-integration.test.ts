import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";

/**
 * Source-level regression checks for the LX-1.2 root-route
 * integration (mission §10/§43): "/" must select ONE experience
 * server-side per request via getPublicLandingExperience(), never a
 * client-side switch, never both branches rendered and hidden with
 * CSS. Same lightweight source-check pattern as every other test file
 * in this directory.
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

const appDir = join(__dirname, "..", "app");
const read = (relativePath: string) => readFileSync(join(appDir, relativePath), "utf-8");

const rootPage = read("page.tsx");

check('root page resolves the experience via getPublicLandingExperience(), not a hardcoded value', () => {
  assert.match(rootPage, /getPublicLandingExperience\(\)/);
});

check("root page selects exactly one branch — no dual render-and-hide", () => {
  const legacyCount = (rootPage.match(/<LegacyPublicLanding/g) ?? []).length;
  const cinematicCount = (rootPage.match(/<CinematicPublicLanding/g) ?? []).length;
  assert.equal(legacyCount, 1, "expected exactly one <LegacyPublicLanding usage");
  assert.equal(cinematicCount, 1, "expected exactly one <CinematicPublicLanding usage");
  // Both appear once in source because of the if/else branch — assert
  // there is no CSS-hiding pattern (hidden/display:none) anywhere
  // near either, which would indicate both are actually mounted.
  assert.equal(/hidden\b|display:\s*none/i.test(rootPage), false);
});

check("root page is a Server Component (no \"use client\" directive) — the selection happens before any client hydration", () => {
  assert.equal(rootPage.trimStart().startsWith('"use client"'), false);
});

check("root page forces dynamic rendering (the flag/CTA decision is a genuine per-request check, not baked in at build time)", () => {
  assert.match(rootPage, /export const dynamic = "force-dynamic";/);
});

check("root page resolves an auth-aware CTA server-side rather than hardcoding /login", () => {
  assert.match(rootPage, /resolveLandingCta\(\)/);
});

check("LegacyPublicLanding and CinematicPublicLanding both accept the resolved cta as a prop, not a hardcoded href", () => {
  const legacy = read("LegacyPublicLanding.tsx");
  assert.doesNotMatch(legacy, /href="\/login"/);
  assert.match(legacy, /cta\.href/);

  const cinematic = read(join("design", "cinematic-landing", "CinematicPublicLanding.tsx"));
  assert.match(cinematic, /cta=\{cta\}/);
});

check("the internal /design/cinematic-landing route renders the same production component, not a separate copy of the scene markup", () => {
  const designRoute = read(join("design", "cinematic-landing", "page.tsx"));
  assert.match(designRoute, /<CinematicPublicLanding/);
  assert.doesNotMatch(designRoute, /SCENES\.map/);
});

if (failures > 0) {
  console.log(`\n${failures} test(s) failed.`);
  process.exit(1);
}
console.log("\nAll public-root integration tests passed.");
