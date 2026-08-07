# NOOR Cinematic Landing — Auth Integration

Status: **LX-1.3 — Complete.** Records the post-login redirect defect (mission §3.3/§23), its root cause, the fix, and the real verification evidence.

## LX-1.3 update — the missing video recorded, a real open-redirect gap found and fixed

1. **The authentication-journey video** flagged as missing in LX-1.2's own report is now recorded (`docs/verification/videos/lx-1-3/05-authentication-journey.webm`) — same real-hosted-Supabase, synthetic-account methodology, this time captured on video and verified frame-by-frame.
2. **A real, evidence-based open-redirect hardening gap** was found via WHATWG URL-parser analysis: `sanitizeNextPath()` only checked string prefixes and did not reject a leading `/\host` — confirmed via Node's own `URL` constructor that this resolves OFF the intended origin under standard URL resolution (`new URL("/\\evil.example", base).origin !== base`), even though one specific browser's address-bar navigation happens to normalize it back to same-origin. Fixed: the sanitizer now rejects any backslash outright and resolves every candidate against a fixed placeholder origin via the `URL` constructor rather than continuing to stack string-prefix checks. See `docs/landing/NOOR_CINEMATIC_SECURITY_REVIEW.md` and the regression tests in `apps/web/tests/redirect.test.ts`.
3. **Re-verified**: the full login-routing test matrix (mission §24/§33) still passes end-to-end after the hardening change — 13 unit-test cases plus the real E2E run, all green.

## The defect, confirmed (LX-1.2, unchanged)

`apps/web/lib/auth/actions.ts::signInWithPassword` redirected every successful sign-in to whatever `next` resolved to — and `sanitizeNextPath("")` returns `"/"`, so a visitor who reached `/login` with no explicit `next` parameter (the common case: clicking "Sign in" from the landing page) was sent back to the public landing after successfully authenticating, never to their actual workspace. Confirmed by reading the code directly before making any change — not assumed from the mission description alone.

## The fix — one canonical resolver

`apps/web/lib/auth/redirect.ts::resolvePostLoginDestination(requestedPath, access)`:

```ts
export function resolvePostLoginDestination(requestedPath, access): string {
  const permissionKeys = access.kind === "authorized" ? access.permissionKeys ?? [] : [];
  const safeNext = sanitizeNextPath(requestedPath);

  if (safeNext !== "/") {
    const gated = matchWorkspaceRoute(safeNext);
    if (!gated || permissionKeys.includes(gated.permission)) {
      return safeNext;
    }
  }
  if (access.kind === "authorized") {
    const defaultWorkspace = resolveDefaultWorkspacePath(permissionKeys);
    if (defaultWorkspace) return defaultWorkspace;
  }
  return "/access-denied";
}
```

### Routing priority (matches mission §23 exactly)

1. A safe, same-origin `requestedPath` that isn't exactly `"/"`. If it targets one of the 4 permission-gated workspace roots (`/admin`, `/quality`, `/reviewer`, `/clinician`), it's honored only if the caller actually holds that permission; otherwise the resolver falls through to step 2 rather than denying outright. If it targets anything else (`/update-password`, a `/knowledge/...` deep link, etc.) it's honored unconditionally — that destination's own layout enforces whatever authorization it needs on arrival, exactly as it already does for every other route in this app.
2. The caller's own authorized default workspace, derived from their active membership's permission set (`WORKSPACE_ADMIN_ACCESS → /admin`, `WORKSPACE_QUALITY_ACCESS → /quality`, `WORKSPACE_REVIEWER_ACCESS → /reviewer`, `WORKSPACE_CLINICIAN_ACCESS → /clinician`).
3. `/access-denied` — no active membership, no profile row, or (only reached when there was no specific request) a membership whose role grants none of the 4 workspace-access permissions at all.

**Never returns `"/"`.** Verified directly by a unit test that exhaustively checks every access-state × requested-path combination in the test matrix below.

### Why a non-gated requested path is honored regardless of membership state

The password-reset flow (`requestPasswordReset` → email link → `/auth/callback?next=/update-password`) depends on `next` being honored even for a caller whose membership hasn't been (or can't be) resolved yet — `/update-password` itself only requires a valid session, not an active organization membership. An earlier draft of this resolver checked `access.kind !== "authorized"` before anything else, which would have sent such a caller to `/access-denied` instead of letting them finish resetting their password — caught and fixed before shipping, by reasoning through the consequence, not by a failed test.

## Wiring — 3 call sites, one resolver

| Call site | File | What changed |
| --- | --- | --- |
| Password sign-in | `lib/auth/actions.ts::signInWithPassword` | After a successful `signInWithPassword`, calls `getAuthenticatedContext()` + `resolvePostLoginDestination()` instead of `redirect(next)` directly |
| Magic-link/reset exchange | `app/auth/callback/route.ts` | Same resolver, same pattern |
| Already-authenticated visitor to `/login` | `app/login/page.tsx` | New: if a session already exists (and no `error`/`notice` query param — those states are only ever reached without a session), redirects immediately via the same resolver instead of rendering the credentials form |

`toPostLoginAccess()` (`lib/auth/context.ts`) adapts `getAuthenticatedContext()`'s discriminated-union result into the resolver's flat structural input — kept as one shared function so the 3 call sites can't drift from each other.

## Root CTA — "Open NOOR"

`resolveLandingCta()` (`lib/publicLanding/resolveLandingCta.ts`) computes the same destination for the public landing's primary CTA: "Sign in" for an unauthenticated visitor, "Open NOOR" pointed at `resolvePostLoginDestination(undefined, ...)` for an authenticated one — the exact same destination clicking "Sign in" while already authenticated would reach, so the two paths never disagree.

## Login routing test matrix (mission §24)

| Scenario | Expected destination | Verified |
| --- | --- | --- |
| Unauthenticated visitor, `/` → Sign in → `/login` | `/login` | Real E2E (synthetic account, real hosted Supabase, real browser) |
| Successful login, authorized workspace, no `next` | Authorized workspace (never `/`) | Real E2E — landed on `/clinician` |
| Login with `next=<safe authorized path>` | That path | Unit test |
| Login with `next=<unauthorized workspace path>` | Caller's own default workspace | Unit test |
| Login with `next=<external URL>` | Ignored — caller's own default workspace | Unit test (both `https://` and `//` forms) |
| No active membership | `/access-denied` | Unit test |
| Authenticated visitor clicking Sign in / visiting `/login` | Authorized workspace, form never shown | Real E2E |
| Authenticated visitor visiting `/` | "Open NOOR" → authorized workspace | Real E2E, screenshot captured |

## Real end-to-end verification (not just unit tests)

A synthetic, organization-provisioned test account was created via the Supabase Admin API against the real hosted "Noor Development" project (no self-serve signup exists — this app is organization-provisioned access only), given an active `clinician` membership, and driven through a real Chromium browser against a real local production build:

1. Unauthenticated `/` → CTA href is `/login`. **Pass.**
2. Real credentials submitted at `/login` with no `next` → landed on `/clinician`, never `/`. **Pass — the defect is fixed.**
3. Already-authenticated visit to `/login` → redirected straight to `/clinician`, form never shown. **Pass.**
4. Authenticated `/` → CTA reads "Open NOOR", `href="/clinician"`. **Pass.**

All test data (auth user, profile row, membership row) was deleted immediately after, and cleanup was itself verified: a follow-up query confirmed zero residual `profiles`/`organization_memberships` rows for the synthetic user ID. Full run log: `docs/verification/screenshots/lx-1-2/auth-e2e-results.json`. Screenshot: `docs/verification/screenshots/lx-1-2/authenticated-root-cta.png`.

## Open-redirect protection — unchanged, re-verified

`sanitizeNextPath()` (unchanged from before this mission) rejects absolute URLs, protocol-relative (`//host`) strings, and non-`/`-prefixed strings — re-verified by the pre-existing `redirect.test.ts` (6 checks, all passing) plus new coverage in `post-login-redirect.test.ts` confirming the resolver itself never follows an external URL through to a redirect.
