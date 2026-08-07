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

check("LX-1.3: an expanded adversarial/malformed-value matrix all fail closed to legacy, never crash", () => {
  const adversarial = [
    "cinematicx",
    "   ",
    "\t\n",
    "https://example.com/cinematic",
    JSON.stringify({ experience: "cinematic" }),
    "cinematic".repeat(5000), // ~45,000 chars — a pathologically long value
    "cinematic;true",
    "CiNeMaTiC",
    "𝕔𝕚𝕟𝕖𝕞𝕒𝕥𝕚𝕔", // unicode look-alike, must not fuzzy-match
  ];
  for (const bad of adversarial) {
    withEnv(bad, () => {
      assert.equal(getPublicLandingExperience(), "legacy");
    });
  }
});

check("LX-1.3: a real, investigated finding — process.env truncates embedded null bytes (Node/OS behavior, not this resolver's logic)", () => {
  // `"cinematic\0garbage"` assigned to process.env is silently truncated by
  // Node to `"cinematic"` (confirmed directly: process.env mirrors C-string,
  // null-terminated OS environment-variable semantics). This is NOT a bug
  // in getPublicLandingExperience() — by the time its own `=== "cinematic"`
  // check runs, the value genuinely IS the string "cinematic". Recorded
  // here as a documented, understood behavior (LX-1.3 mission §10) rather
  // than an unexplained test failure: exploiting it would require the
  // same environment-variable write access that could just set the flag
  // directly, so it carries no real escalation risk.
  withEnv("cinematic\0garbage-after-null-byte", () => {
    assert.equal(process.env[ENV_KEY], "cinematic", "process.env truncated the value at the null byte, as expected");
    assert.equal(getPublicLandingExperience(), "cinematic");
  });
});

if (original === undefined) delete process.env[ENV_KEY];
else process.env[ENV_KEY] = original;

if (failures > 0) {
  console.log(`\n${failures} test(s) failed.`);
  process.exit(1);
}
console.log("\nAll public-landing feature-flag tests passed.");
