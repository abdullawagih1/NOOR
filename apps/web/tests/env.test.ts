import assert from "node:assert/strict";
import { getPublicEnv } from "../lib/env/public";
// Imports the unguarded schema module directly — lib/env/server.ts's
// `server-only` import throws unconditionally outside Next's own bundler,
// including under a plain tsx/Node test run. See lib/env/serverSchema.ts.
import { parseServerEnv as getServerEnv } from "../lib/env/serverSchema";

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

function withEnv(vars: Record<string, string | undefined>, fn: () => void) {
  const original: Record<string, string | undefined> = {};
  for (const key of Object.keys(vars)) {
    original[key] = process.env[key];
    if (vars[key] === undefined) delete process.env[key];
    else process.env[key] = vars[key];
  }
  try {
    fn();
  } finally {
    for (const key of Object.keys(original)) {
      if (original[key] === undefined) delete process.env[key];
      else process.env[key] = original[key];
    }
  }
}

const VALID_PUBLIC = {
  NEXT_PUBLIC_SUPABASE_URL: "http://127.0.0.1:54321",
  NEXT_PUBLIC_SUPABASE_ANON_KEY: "test-anon-key",
  NEXT_PUBLIC_APP_URL: "http://localhost:3000",
};

check("valid public environment parses successfully", () => {
  withEnv(VALID_PUBLIC, () => {
    const env = getPublicEnv();
    assert.equal(env.NEXT_PUBLIC_SUPABASE_URL, VALID_PUBLIC.NEXT_PUBLIC_SUPABASE_URL);
    assert.equal(env.NEXT_PUBLIC_SUPABASE_ANON_KEY, VALID_PUBLIC.NEXT_PUBLIC_SUPABASE_ANON_KEY);
  });
});

check("missing NEXT_PUBLIC_SUPABASE_URL fails clearly", () => {
  withEnv({ ...VALID_PUBLIC, NEXT_PUBLIC_SUPABASE_URL: undefined }, () => {
    assert.throws(() => getPublicEnv(), /NEXT_PUBLIC_SUPABASE_URL/);
  });
});

check("missing NEXT_PUBLIC_SUPABASE_ANON_KEY fails clearly", () => {
  withEnv({ ...VALID_PUBLIC, NEXT_PUBLIC_SUPABASE_ANON_KEY: undefined }, () => {
    assert.throws(() => getPublicEnv(), /NEXT_PUBLIC_SUPABASE_ANON_KEY/);
  });
});

check("malformed NEXT_PUBLIC_SUPABASE_URL fails clearly (not just truthiness)", () => {
  withEnv({ ...VALID_PUBLIC, NEXT_PUBLIC_SUPABASE_URL: "not-a-url" }, () => {
    assert.throws(() => getPublicEnv());
  });
});

check("NEXT_PUBLIC_APP_URL defaults to localhost when unset (matches prior behavior)", () => {
  withEnv({ ...VALID_PUBLIC, NEXT_PUBLIC_APP_URL: undefined }, () => {
    const env = getPublicEnv();
    assert.equal(env.NEXT_PUBLIC_APP_URL, "http://localhost:3000");
  });
});

check("valid server environment parses successfully", () => {
  withEnv({ SUPABASE_SERVICE_ROLE_KEY: "test-service-role-key" }, () => {
    const env = getServerEnv();
    assert.equal(env.SUPABASE_SERVICE_ROLE_KEY, "test-service-role-key");
  });
});

check("missing SUPABASE_SERVICE_ROLE_KEY fails clearly", () => {
  withEnv({ SUPABASE_SERVICE_ROLE_KEY: undefined }, () => {
    assert.throws(() => getServerEnv(), /SUPABASE_SERVICE_ROLE_KEY/);
  });
});

check("optional WORKER_BASE_URL / WORKER_INTERNAL_TOKEN being unset does not fail", () => {
  withEnv(
    { SUPABASE_SERVICE_ROLE_KEY: "test-service-role-key", WORKER_BASE_URL: undefined, WORKER_INTERNAL_TOKEN: undefined },
    () => {
      const env = getServerEnv();
      assert.equal(env.WORKER_BASE_URL, undefined);
      assert.equal(env.WORKER_INTERNAL_TOKEN, undefined);
    }
  );
});

check("a configured-but-too-short WORKER_INTERNAL_TOKEN still fails (validated when present)", () => {
  withEnv(
    { SUPABASE_SERVICE_ROLE_KEY: "test-service-role-key", WORKER_INTERNAL_TOKEN: "too-short" },
    () => {
      assert.throws(() => getServerEnv(), /WORKER_INTERNAL_TOKEN/);
    }
  );
});

if (failures > 0) {
  console.log(`\n${failures} test(s) failed.`);
  process.exit(1);
}
console.log("\nAll environment-validation tests passed.");
