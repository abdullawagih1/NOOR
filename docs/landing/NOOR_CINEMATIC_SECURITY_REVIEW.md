# NOOR Cinematic Landing — Security Review

Status: **LX-1.3 — Complete.**

## Open redirect

`sanitizeNextPath()`/`resolvePostLoginDestination()` re-audited with an expanded adversarial matrix (mission §34): absolute URLs, protocol-relative (`//`), `javascript:`/`data:` schemes, backslash variants, encoded/double-encoded slashes, nested `next` parameters. **One real, evidence-based gap found and fixed**: a leading `/\host` string resolves off-origin under WHATWG URL parsing (confirmed via Node's own `URL` constructor — `new URL("/\\evil.example", base).origin !== base`), even though a live Chromium address-bar navigation happens to normalize it to same-origin (browser-specific behavior, not guaranteed elsewhere). Fixed by rejecting any backslash outright and resolving every candidate against a fixed internal placeholder origin via the `URL` constructor rather than continuing to stack string-prefix checks. Regression tests: `apps/web/tests/redirect.test.ts` (backslash variants, encoded-slash cases, malformed-URI-never-throws).

Live browser-driven verification (11 attack strings against the real `/login` route) confirmed every case either stays same-origin or is sanitized to `/` — see `docs/verification/screenshots/lx-1-3/open-redirect-live-results.json`.

## Secrets

- Compiled client bundle (`apps/web/.next/static/chunks/*.js`) scanned for `service_role`, literal `SUPABASE_SERVICE_ROLE_KEY`/`WORKER_INTERNAL_TOKEN` assignments, and generic secret-key-shaped strings (`sk_live`, `sk_test`, AWS access-key pattern). **Zero hits.**
- `SUPABASE_SERVICE_ROLE_KEY` is never imported by any client-bundled module — confirmed by the same bundle scan.
- No Vercel platform secrets, no test credentials, and no auth cookies are read by client-side JS beyond what `@supabase/ssr`'s own cookie-based session mechanism requires (unchanged from the existing, previously-reviewed auth architecture).

## External network requests

Every network request from a full scroll through the cinematic root (`/`) was captured. **Zero external (non-app) origins** — confirmed via `docs/verification/screenshots/lx-1-3/security-network-audit.json`. Specifically verified:

- `three` is bundled locally, not loaded from a CDN.
- No remote textures or 3D model assets — every visual is procedurally generated geometry/materials.
- No hidden analytics/telemetry calls (consistent with `NOOR_CINEMATIC_OBSERVABILITY.md`'s finding that no observability vendor exists in this app at all).
- No external shader assets.
- Fonts are loaded via `next/font` (self-hosted at build time, not a remote Google Fonts request at runtime) — unchanged, pre-existing pattern.

## CSP

**No Content-Security-Policy is configured anywhere in the application** — confirmed via direct inspection of `apps/web/next.config.mjs` (no `headers()` function) and the repository root (no `vercel.json`). This is the existing baseline for the ENTIRE app, not something specific to or newly introduced by the cinematic landing. Classified **MEDIUM**, out of this mission's scope to introduce (a CSP rollout should be a deliberate, whole-app decision, not bolted on narrowly for one route) — see `NOOR_LAUNCH_RISK_REGISTER.md` R-05. Nothing in the cinematic landing's own runtime behavior would be incompatible with a reasonably strict CSP were one added later (no inline scripts beyond Next's own required hydration bootstrapping, no `eval`, no remote origins as shown above).

## Environment variables

- `NOOR_PUBLIC_LANDING_EXPERIENCE` and `NOOR_CINEMATIC_PREVIEW_ENABLED` are both server-only, read via raw `process.env` inline in Server Components — never exposed as `NEXT_PUBLIC_` variables, never resolvable from client JS.
- **A real, severe, unrelated finding this mission**: Production's Vercel environment had zero variables configured at all (see `NOOR_LAUNCH_RISK_REGISTER.md` R-01) — fixed by restoring the correct `NEXT_PUBLIC_*`/service-role values, all of which are the same values already correctly scoped to Preview.
- `NEXT_PUBLIC_SUPABASE_ANON_KEY` is, by Supabase's own design, intended to be public/client-exposed (RLS is the actual authorization boundary, not secrecy of the anon key) — its presence in the client bundle is expected and correct, not a leak.

## No clinical-data calls from the public route

The cinematic landing makes zero calls to any clinical-data table or endpoint — its only Supabase interaction is the auth-aware CTA's `getAuthenticatedContext()` call (session/membership/permission resolution only). Confirmed by source review: no `guidelines`, `guideline_documents`, `retrieval_evaluation`, or `document_embeddings` table is referenced anywhere in `apps/web/app/page.tsx`, `LegacyPublicLanding.tsx`, `CinematicPublicLanding.tsx`, or any of their imports.

## Summary

| Check | Result |
| --- | --- |
| Open redirect | 1 real gap found and fixed (backslash variant); all other attack classes already safe |
| Secrets in client bundle | 0 found |
| External network origins | 0 found |
| CSP | Absent (pre-existing, whole-app, MEDIUM, out of scope) |
| Clinical-data calls from public route | 0 |
| Debug UI reachable in production | 0 (confirmed via the existing `?debug=1` production hard-disable, unchanged) |
