import assert from "node:assert/strict";
import { getPublicLandingExperience } from "../lib/publicLanding/getPublicLandingExperience";

/**
 * LX-1.2 mission §8: the server-controlled public-landing selector
 * must fail closed to "legacy" on any value other than exactly
 * "cinematic" — missing, empty, malformed, or misspelled. Directly
 * mutates process.env within this process (never touches the real
 * .env files); restored at the end so it can't leak into any test
 * file that runs after it in the same `tsx tests/*.test.ts` chain.
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

const ENV_KEY = "NOOR_PUBLIC_LANDING_EXPERIENCE";
const original = process.env[ENV_KEY];

function withEnv(value: string | undefined, fn: () => void) {
  if (value === undefined) delete process.env[ENV_KEY];
  else process.env[ENV_KEY] = value;
  fn();
}

check('exactly "cinematic" resolves to the cinematic experience', () => {
  withEnv("cinematic", () => {
    assert.equal(getPublicLandingExperience(), "cinematic");
  });
});

check('exactly "legacy" resolves to legacy', () => {
  withEnv("legacy", () => {
    assert.equal(getPublicLandingExperience(), "legacy");
  });
});

check("a missing/unset variable fails closed to legacy", () => {
  withEnv(undefined, () => {
    assert.equal(getPublicLandingExperience(), "legacy");
  });
});

check("an empty string fails closed to legacy", () => {
  withEnv("", () => {
    assert.equal(getPublicLandingExperience(), "legacy");
  });
});

check("a malformed/misspelled value fails closed to legacy, never crashes", () => {
  for (const bad of ["Cinematic", "CINEMATIC", " cinematic", "cinematic ", "cinema", "true", "1", "null", "undefined"]) {
    withEnv(bad, () => {
      assert.equal(getPublicLandingExperience(), "legacy");
    });
  }
});

if (original === undefined) delete process.env[ENV_KEY];
else process.env[ENV_KEY] = original;

if (failures > 0) {
  console.log(`\n${failures} test(s) failed.`);
  process.exit(1);
}
console.log("\nAll public-landing feature-flag tests passed.");
