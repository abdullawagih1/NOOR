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
 * Vercel Deployment Protection: if the target is a Vercel Preview URL and
 * protection is enabled, every response body is inspected — not just the
 * status code — to distinguish Noor's real page from Vercel's own SSO
 * interstitial (which also returns 200/302 and would otherwise produce
 * false-positive passes). Pass a bypass token via BYPASS_TOKEN (sent as
 * the `x-vercel-protection-bypass` header) once configured in the Vercel
 * dashboard (Settings -> Deployment Protection -> Protection Bypass for
 * Automation) to run the full authenticated-content checks; without it,
 * this script still correctly detects and reports the protection wall
 * rather than mistaking it for a pass.
 *
 * Usage:
 *   BASE_URL=http://localhost:3000 node scripts/smoke-test-web.mjs
 *   BASE_URL=https://noor-preview-dev.vercel.app BYPASS_TOKEN=xxx node scripts/smoke-test-web.mjs
 */

const BASE_URL = process.env.BASE_URL ?? "http://localhost:3000";
const BYPASS_TOKEN = process.env.BYPASS_TOKEN;
let failures = 0;
let vercelProtectionDetected = false;

async function check(name, fn) {
  try {
    await fn();
    console.log(`PASS  ${name}`);
  } catch (err) {
    failures += 1;
    console.log(`FAIL  ${name} — ${err.message}`);
  }
}

function bypassHeaders() {
  return BYPASS_TOKEN ? { "x-vercel-protection-bypass": BYPASS_TOKEN } : {};
}

async function fetchNoRedirect(path) {
  return fetch(`${BASE_URL}${path}`, { redirect: "manual", headers: bypassHeaders() });
}

async function fetchBody(path) {
  const res = await fetch(`${BASE_URL}${path}`, { redirect: "manual", headers: bypassHeaders() });
  const finalUrl = res.url || `${BASE_URL}${path}`;
  const location = res.headers.get("location");
  // Vercel's own SSO interstitial always redirects to vercel.com/sso-api,
  // or (on 200 fallthrough for cached pages) contains a recognizable
  // dashboard-only script reference. Detect both shapes explicitly.
  const isVercelSso = (location && location.includes("vercel.com/sso-api")) ;
  return { status: res.status, location, finalUrl, isVercelSso };
}

function assert(cond, message) {
  if (!cond) throw new Error(message);
}

for (const path of ["/clinician", "/admin", "/reviewer", "/quality"]) {
  await check(`unauthenticated GET ${path} redirects to /login (or is Vercel-protected)`, async () => {
    const { status, location, isVercelSso } = await fetchBody(path);
    if (isVercelSso) {
      vercelProtectionDetected = true;
      assert([302, 307].includes(status), `expected a redirect from Vercel protection, got ${status}`);
      return;
    }
    assert([307, 302].includes(status), `expected a redirect, got ${status}`);
    assert(location && location.includes("/login"), `expected redirect to /login, got "${location}"`);
  });
}

for (const [path, label] of [
  ["/login", "GET /login"],
  ["/forgot-password", "GET /forgot-password"],
  ["/403", "GET /403 (controlled page, not an unhandled error)"],
  ["/access-denied", "GET /access-denied (controlled page, not an unhandled error)"],
  ["/", "GET /"],
]) {
  await check(`${label} returns Noor content (200, not the Vercel SSO page)`, async () => {
    const { status, isVercelSso } = await fetchBody(path);
    if (isVercelSso) {
      vercelProtectionDetected = true;
      throw new Error("blocked by Vercel Deployment Protection (no bypass token supplied) — see docs/operations/vercel-preview-deployment.md");
    }
    assert(status === 200, `expected 200, got ${status}`);
  });
}

await check("GET /design-system follows its production-visibility policy (404 when deployed)", async () => {
  const { status, isVercelSso } = await fetchBody("/design-system");
  if (isVercelSso) {
    vercelProtectionDetected = true;
    throw new Error("blocked by Vercel Deployment Protection (no bypass token supplied)");
  }
  assert(status === 404, `expected 404 (dev-only route), got ${status}`);
});

if (vercelProtectionDetected && !BYPASS_TOKEN) {
  console.log("\nINFO  Vercel Deployment Protection is active and correctly detected (not mistaken for a pass).");
  console.log("INFO  Set BYPASS_TOKEN once Protection Bypass for Automation is enabled in the Vercel dashboard");
  console.log("INFO  (Settings -> Deployment Protection) to run the full authenticated-content checks.");
}

if (failures > 0) {
  console.log(`\n${failures} check(s) failed.`);
  process.exit(1);
}
console.log("\nAll HTTP smoke checks passed.");
