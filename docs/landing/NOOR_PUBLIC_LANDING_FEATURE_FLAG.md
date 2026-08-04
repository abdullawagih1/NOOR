# NOOR Public Landing Feature Flag

Status: **LX-1.2 — Complete.** Defines the server-controlled selector between the legacy and cinematic public landing experiences at `/`.

## Configuration

```
NOOR_PUBLIC_LANDING_EXPERIENCE=legacy | cinematic
```

Resolved by `apps/web/lib/publicLanding/getPublicLandingExperience.ts`:

```ts
export function getPublicLandingExperience(): PublicLandingExperience {
  const raw = process.env.NOOR_PUBLIC_LANDING_EXPERIENCE;
  return raw === "cinematic" ? "cinematic" : "legacy";
}
```

- Read directly via `process.env`, never through the Zod-validated env modules (`lib/env/public.ts`/`serverSchema.ts`) — same precedent as `NOOR_CINEMATIC_PREVIEW_ENABLED` (LX-1.1.1).
- **Never** a `NEXT_PUBLIC_` variable — this is resolved exclusively on the server, inside `apps/web/app/page.tsx`'s Server Component body, before any HTML is sent. There is no client-side code anywhere that reads or could read this variable.
- Resolved once per request (not cached across requests, not memoized) — a value change takes effect on the very next request to a route serving this build, with no code change required.

## Fail-safe behavior

Only the literal string `"cinematic"` selects the cinematic experience. Every other value — unset, empty string, `"Cinematic"` (wrong case), `"cinema"` (typo), `"true"`, `"1"` — fails closed to `"legacy"`. Verified directly by a committed unit test (`apps/web/tests/public-landing-feature-flag.test.ts`, 5 checks including 9 distinct malformed-value cases) — the flag cannot silently misconfigure itself into showing the unapproved experience to the public.

## Root route selection (`apps/web/app/page.tsx`)

```tsx
export default async function HomePage() {
  const experience = getPublicLandingExperience();
  const cta = await resolveLandingCta();
  if (experience === "cinematic") {
    return <CinematicPublicLanding cta={cta} />;
  }
  return <LegacyPublicLanding cta={cta} />;
}
```

One experience per request, entirely server-side — no dual render-and-hide, no client-side switch, no loading placeholder while choosing. See `NOOR_CINEMATIC_PRODUCTION_ARCHITECTURE.md` for the full component boundary.

## Environment state matrix

| Environment | `NOOR_PUBLIC_LANDING_EXPERIENCE` | `/` renders | Verified |
| --- | --- | --- | --- |
| Local development (recommended) | `cinematic` | Cinematic | Yes — local production build, real-GPU, axe/Lighthouse/FPS all passed |
| CI (`apps/web` test suite) | both, via unit tests | N/A (tested as a pure function, not a live server) | Yes — `public-landing-feature-flag.test.ts` exercises both values + 9 malformed cases |
| Vercel Preview (this mission) | `cinematic` | Cinematic | Yes — real deployment `dpl_9f5QMxk6G4NfSnSKrXXqexyUQXnz`, Deployment Protection confirmed active (302 on unauthenticated request); build logs confirm the same route table as the verified local build |
| Production (this mission) | unset (absent entirely from the Vercel project's Production environment variables — confirmed via `vercel env ls production`, zero rows) | Legacy | Yes — `https://noor-clinical-intelligence-os.vercel.app/` returns 200 with the unchanged legacy hero text, confirmed directly this mission |
| Future LX-1.4 launch | `cinematic` (Production scope) | Cinematic | Only after explicit, separate user approval — not part of this mission |

## Rollback procedure

See `NOOR_CINEMATIC_ROLLBACK_RUNBOOK.md` for the full rehearsed procedure. Summary: change the Preview-scoped `NOOR_PUBLIC_LANDING_EXPERIENCE` value via `vercel env rm`/`vercel env add`, then `vercel deploy` — no code revert, no git operation required. Rehearsed for real this mission (~57 seconds cinematic → legacy, then restored back to cinematic for user review).

## Test matrix

| Test | File | What it proves |
| --- | --- | --- |
| Flag resolution, all malformed-value cases | `apps/web/tests/public-landing-feature-flag.test.ts` | Fails closed to legacy in every case except the exact string `"cinematic"` |
| Root selects exactly one branch, server-side, dynamic | `apps/web/tests/public-root-integration.test.ts` | No dual render, no client switch, `dynamic="force-dynamic"` present |
| Legacy content unchanged | `apps/web/tests/public-pages-content.test.ts` | The extracted `LegacyPublicLanding.tsx` still carries the exact pre-LX-1.2 copy/h1/CTA structure |
| Real local production build, both flag values | This mission's verification (`docs/verification/lx-1-2-production-integration.md`) | Real HTTP responses confirmed rendering the correct branch, zero cross-contamination of chunks/content |
