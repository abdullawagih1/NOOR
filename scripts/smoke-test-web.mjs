#!/usr/bin/env node
/**
 * HTTP-level smoke test against a running `next start` (or Vercel Preview)
 * instance. Tests what's reliably checkable without a browser: middleware
 * route protection, page availability, and the dev-only showcase route's
 * production behavior.
 *
 * Deliberately does NOT attempt to submit the login/reset Server Actions —
 * Next's Server Action wire protocol (the `Next-Action` header + RSC
 * payload) is bundle-specific and not a stable target for a plain-fetch
 * script. Login/logout/password-reset correctness against real Supabase is
 * proven independently via direct GoTrue/PostgREST calls (see
 * PROJECT_STATE.md) — full browser-driven login-form E2E is a documented
 * Sprint 1 gap (Playwright), not fabricated here.
 *
 * Usage: BASE_URL=http://localhost:3000 node scripts/smoke-test-web.mjs
 */

const BASE_URL = process.env.BASE_URL ?? "http://localhost:3000";
let failures = 0;

async function check(name, fn) {
  try {
    await fn();
    console.log(`PASS  ${name}`);
  } catch (err) {
    failures += 1;
    console.log(`FAIL  ${name} — ${err.message}`);
  }
}

async function fetchNoRedirect(path) {
  return fetch(`${BASE_URL}${path}`, { redirect: "manual" });
}

function assert(cond, message) {
  if (!cond) throw new Error(message);
}

for (const path of ["/clinician", "/admin", "/reviewer", "/quality"]) {
  await check(`unauthenticated GET ${path} redirects to /login`, async () => {
    const res = await fetchNoRedirect(path);
    assert([307, 302].includes(res.status), `expected a redirect, got ${res.status}`);
    const location = res.headers.get("location") ?? "";
    assert(location.includes("/login"), `expected redirect to /login, got "${location}"`);
  });
}

await check("GET /login returns 200", async () => {
  const res = await fetch(`${BASE_URL}/login`);
  assert(res.status === 200, `expected 200, got ${res.status}`);
});

await check("GET /forgot-password returns 200", async () => {
  const res = await fetch(`${BASE_URL}/forgot-password`);
  assert(res.status === 200, `expected 200, got ${res.status}`);
});

await check("GET /403 returns 200 (controlled page, not an unhandled error)", async () => {
  const res = await fetch(`${BASE_URL}/403`);
  assert(res.status === 200, `expected 200, got ${res.status}`);
});

await check("GET /access-denied returns 200 (controlled page, not an unhandled error)", async () => {
  const res = await fetch(`${BASE_URL}/access-denied`);
  assert(res.status === 200, `expected 200, got ${res.status}`);
});

await check("GET /design-system 404s in a production build", async () => {
  const res = await fetch(`${BASE_URL}/design-system`);
  assert(res.status === 404, `expected 404 (dev-only route), got ${res.status}`);
});

await check("GET / returns 200", async () => {
  const res = await fetch(`${BASE_URL}/`);
  assert(res.status === 200, `expected 200, got ${res.status}`);
});

if (failures > 0) {
  console.log(`\n${failures} check(s) failed.`);
  process.exit(1);
}
console.log("\nAll HTTP smoke checks passed.");
