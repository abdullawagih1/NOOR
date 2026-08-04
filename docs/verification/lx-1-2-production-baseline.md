# LX-1.2 — Production and Authentication Baseline

Captured before any LX-1.2 code change, per mission §7. Commit at capture time: `ed50da3` (the LX-1.1.1 closing commit — `git log -1` at the start of this mission).

## Production `/` (before LX-1.2)

- Fully static Server Component (`○` in the build route table), no `dynamic` export, no `generateMetadata`.
- Inline hero/capabilities/trust sections — no `LegacyPublicLanding.tsx` extraction existed; everything lived directly in `apps/web/app/page.tsx` (116 lines).
- Hero CTA: hardcoded `<Link href="/login"><Button variant="primary">Sign in to NOOR</Button></Link>` — always "Sign in," regardless of the visitor's authentication state.
- `PublicShell`'s header/footer "Sign in" link: hardcoded `href="/login"`.
- Metadata: inherited entirely from `apps/web/app/layout.tsx`'s static `export const metadata` — title "Noor — Clinical Intelligence OS", a single fixed description, no page-specific `generateMetadata`, no `robots.ts`, no `sitemap.ts` (neither file existed in the repo).
- Lighthouse (desktop preset, real GPU headless Chromium, `next start` production build): Performance 1.00, Accessibility 1.00, Best Practices 1.00, SEO 1.00, LCP 0.6s, CLS 0, 194 KiB total byte weight — matches the LX-1.1.1 verification report's own regression-check baseline exactly (re-confirmed this mission, not re-measured from scratch).

## Reduced motion (before LX-1.2)

Not applicable to the legacy landing — it has no motion at all (static HTML/CSS only). The cinematic prototype's own reduced-motion path (LX-1.1.1) was unaffected by anything measured here.

## Login behavior (before LX-1.2) — the reported defect, confirmed directly

`apps/web/lib/auth/actions.ts::signInWithPassword`, prior version:

```ts
const next = sanitizeNextPath(String(formData.get("next") ?? ""));
...
const { error } = await supabase.auth.signInWithPassword({ email, password });
if (error) { redirect(`/login?error=...`); }
redirect(next);
```

`sanitizeNextPath("")` returns `"/"` — so a visitor who reached `/login` with no explicit `next` query parameter (the overwhelmingly common case: clicking "Sign in" from the public landing) was redirected straight back to the public landing page after a successful sign-in, never to their workspace. Confirmed by direct code reading, not assumed — this is the exact defect mission §3.3 reports.

`apps/web/app/auth/callback/route.ts` (the magic-link/password-reset exchange route) had the identical pattern: `sanitizeNextPath(searchParams.get("next"))` defaulting to `/` and redirecting there literally.

No canonical post-login destination resolver existed anywhere in the codebase before this mission — `getAuthenticatedContext()` (`apps/web/lib/auth/context.ts`) already resolved a caller's real permission set, but nothing mapped that permission set to a default workspace route.

## Unauthenticated CTA path (before and after — unchanged)

`/` → "Sign in to NOOR"/"Sign in" → `/login` → real credentials → workspace. This mission does not change the unauthenticated path at all, only the previously-missing authenticated-visitor and post-login-workspace-resolution behavior.

## Authenticated root-page behavior (before LX-1.2)

Did not exist as a distinct behavior: `/` rendered identical, static, always-"Sign in" markup regardless of whether the visitor already had a valid session. Confirmed by reading `page.tsx`'s prior source — no auth check of any kind was present on the route.

## Current root-route bundle size (before LX-1.2, for comparison)

`/` : `3.01 kB` size (unchanged by this mission's build output, see LX-1.2 architecture doc), but **First Load JS was smaller** before this mission since the route carried no `resolveLandingCta()`/Supabase dependency and no cinematic-component static import. This is a real, measured, honest trade-off — see `NOOR_CINEMATIC_PERFORMANCE_BUDGET.md`'s LX-1.2 section for the exact before/after numbers this mission measured.

## Known defects at baseline

1. Successful login always redirects to `/` (mission §3.3, confirmed above).
2. No feature flag exists — `/` can only ever render the legacy landing; there is no code path for a production-grade cinematic integration.
3. No `robots.txt`/`sitemap.xml` exist anywhere in the app.
4. No auth-aware CTA anywhere in the public landing.
