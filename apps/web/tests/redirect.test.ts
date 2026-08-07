import assert from "node:assert/strict";
import { sanitizeNextPath } from "../lib/auth/redirect";

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

check("empty/undefined/null next falls back to /", () => {
  assert.equal(sanitizeNextPath(undefined), "/");
  assert.equal(sanitizeNextPath(null), "/");
  assert.equal(sanitizeNextPath(""), "/");
});

check("a plain relative path is preserved", () => {
  assert.equal(sanitizeNextPath("/clinician"), "/clinician");
  assert.equal(sanitizeNextPath("/admin/settings?tab=roles"), "/admin/settings?tab=roles");
});

check("absolute URLs are rejected (open-redirect prevention)", () => {
  assert.equal(sanitizeNextPath("https://evil.example/phish"), "/");
  assert.equal(sanitizeNextPath("http://evil.example"), "/");
});

check("protocol-relative // paths are rejected", () => {
  assert.equal(sanitizeNextPath("//evil.example"), "/");
  assert.equal(sanitizeNextPath("///evil.example"), "/");
});

check("a path not starting with / is rejected", () => {
  assert.equal(sanitizeNextPath("evil.example"), "/");
  assert.equal(sanitizeNextPath("javascript:alert(1)"), "/");
});

check("a scheme embedded later in the string is still rejected", () => {
  assert.equal(sanitizeNextPath("/redirect?to=https://evil.example"), "/");
});

check("LX-1.3: backslash-based open-redirect variants are rejected (WHATWG URL parser, not string prefixes)", () => {
  // new URL("/\\evil.example", base).origin resolves OFF the base
  // origin — confirmed directly against Node's own URL parser this
  // mission — even though it happens to render as same-origin in a
  // Chromium address bar. Reject regardless of any one browser's
  // navigation-specific normalization.
  for (const attack of ["/\\evil.example", "\\/evil.example", "\\\\evil.example", "/\\/evil.example", "/\\\\evil.example"]) {
    assert.equal(sanitizeNextPath(attack), "/", `expected "/" for ${JSON.stringify(attack)}`);
  }
});

check("LX-1.3: encoded-slash and mixed-encoding tricks resolve same-origin, never escape (real WHATWG URL resolution)", () => {
  // These do NOT resolve off-origin (confirmed via new URL(...).origin
  // staying the sanitize base), so they are honored as literal,
  // same-origin (if unusual) paths — the destination route's own
  // layout still enforces whatever authorization it needs on arrival.
  for (const benign of ["/%2F%2Fevil.example", "/redirect?next=https://evil.example", "/path%2e%2e/evil"]) {
    const result = sanitizeNextPath(benign);
    assert.ok(result.startsWith("/"), `expected a same-origin path for ${JSON.stringify(benign)}, got ${result}`);
    assert.equal(result.includes("://"), false);
  }
});

check("LX-1.3: a malformed URI sequence never throws, always fails closed", () => {
  assert.equal(sanitizeNextPath("/%"), "/%");
  assert.equal(sanitizeNextPath("/%zz"), "/%zz");
});

if (failures > 0) {
  console.log(`\n${failures} test(s) failed.`);
  process.exit(1);
}
console.log("\nAll redirect-safety tests passed.");
