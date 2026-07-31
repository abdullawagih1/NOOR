import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";

/**
 * Source-level content/regression checks for the public and auth
 * surfaces (UX-1.1). This repository has no React-DOM render harness,
 * so these check the actual page source text — the same lightweight
 * pattern every other test file in this directory already uses — not a
 * full rendered-DOM assertion. Real visual verification is the
 * screenshot evidence in docs/verification/ux-1-1-visual-acceptance.md.
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

function h1Count(source: string): number {
  return (source.match(/<h1[\s>]/g) ?? []).length;
}

const BANNED_STRINGS = [
  "Sprint 0.5",
  "no clinical data or generation pipeline",
  "content stubs",
  "Noor V1 — Sprint",
];

check("root page contains none of the retired Sprint 0.5 / placeholder phrases", () => {
  const source = read("page.tsx");
  for (const banned of BANNED_STRINGS) {
    assert.equal(source.includes(banned), false, `found banned phrase: "${banned}"`);
  }
});

check("root page has exactly one <h1>", () => {
  assert.equal(h1Count(read("page.tsx")), 1);
});

check("root page states the real product name and tagline", () => {
  const source = read("page.tsx");
  assert.match(source, /NOOR — Clinical Intelligence OS/);
  assert.match(source, /Evidence-governed knowledge operations for clinical teams/);
});

check("root page does not expose protected workspace routes as raw public links", () => {
  const source = read("page.tsx");
  for (const route of ["/clinician\"", "/admin\"", "/reviewer\"", "/quality\""]) {
    assert.equal(source.includes(`href="${route.replace(/"/g, "")}"`), false, `found a raw link to ${route}`);
  }
});

check("root page's only call-to-action point is /login", () => {
  const source = read("page.tsx");
  assert.match(source, /href="\/login"/);
});

check("root page does not claim retrieval or clinical answer generation is available", () => {
  const source = read("page.tsx");
  assert.match(source, /Retrieval and clinical answer generation are future work, not yet available/);
});

check("login page has exactly one <h1> and the corrected copy", () => {
  const source = read(join("login", "page.tsx"));
  assert.equal(h1Count(source), 1);
  assert.match(source, /Sign in to NOOR/);
  assert.match(source, /organization-provisioned access/);
});

check("login page uses the two-column AuthSplitShell, not a bare centered <main>", () => {
  const source = read(join("login", "page.tsx"));
  assert.match(source, /AuthSplitShell/);
});

check("403 and access-denied pages share the same AuthCardShell (not duplicated layout CSS)", () => {
  for (const page of [join("403", "page.tsx"), join("access-denied", "page.tsx")]) {
    const source = read(page);
    assert.match(source, /AuthCardShell/);
  }
});

check("not-found and error pages exist and use the shared shell", () => {
  for (const page of ["not-found.tsx", "error.tsx"]) {
    const source = read(page);
    assert.match(source, /AuthCardShell/);
  }
});

check("error page never renders the raw error message or stack", () => {
  const source = read("error.tsx");
  // Matches actual JSX interpolation ({error.message}), not prose in a
  // comment explaining what is deliberately NOT rendered.
  assert.equal(/\{error\.message\}/.test(source), false);
  assert.equal(/\{error\.stack\}/.test(source), false);
});

check("root <html> pins data-theme=\"light\" (regression guard for the OS-dark-mode bug)", () => {
  const source = read("layout.tsx");
  assert.match(source, /data-theme="light"/);
});

if (failures > 0) {
  console.log(`\n${failures} test(s) failed.`);
  process.exit(1);
}
console.log("\nAll public-page content/regression tests passed.");
