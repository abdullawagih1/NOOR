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

if (failures > 0) {
  console.log(`\n${failures} test(s) failed.`);
  process.exit(1);
}
console.log("\nAll redirect-safety tests passed.");
