# ADR 0006: Next.js security-advisory version strategy

**Status:** Accepted
**Source:** Sprint 0.5 mission §20

## Current version at start of this ADR

`next@14.2.35` (the latest **stable** 14.x release — `npm view next versions`
confirms 14.3.0 only exists as a canary, never shipped stable).

## Advisories (from `npm audit`, this session)

`next@14.2.35` was flagged for the following, all high severity unless
noted:

| Advisory | GHSA |
|---|---|
| DoS via Image Optimizer `remotePatterns` | GHSA-9g9p-9gw9-jx7f |
| HTTP request deserialization DoS (React Server Components) | GHSA-h25m-26qc-wcjf |
| HTTP request smuggling in rewrites | GHSA-ggv3-7p47-pfv8 |
| Unbounded `next/image` disk cache growth | GHSA-3x4c-7xq6-9pq8 |
| DoS with Server Components (×2 advisories) | GHSA-q4gf-8mx6-v5v3, GHSA-8h8q-6873-q5fj |
| Middleware/Proxy redirect cache-poisoning | GHSA-3g8h-86w9-wvmq |
| XSS in App Router via CSP nonces | GHSA-ffhc-5mcf-pf4q |
| Cache poisoning via RSC cache-busting collisions | GHSA-vfv6-92ff-j949 |
| XSS in `beforeInteractive` scripts | GHSA-gx5p-jg67-6x7h |
| DoS in Image Optimization API | GHSA-h64f-5h5j-jqjh |
| SSRF via WebSocket upgrades | GHSA-c4j6-fc7j-m34r |
| Cache poisoning in RSC responses | GHSA-wfc6-r584-vfw7 |
| Middleware/Proxy bypass (Pages Router i18n) | GHSA-36qx-fr4f-26g5 |
| **DoS in App Router via Server Actions** | GHSA-m99w-x7hq-7vfj |
| SSRF in Server Actions on custom servers | GHSA-89xv-2m56-2m9x |
| Cache confusion of response bodies (×2) | GHSA-68g3-v927-f742, GHSA-4633-3j49-mh5q |
| Unbounded Server Action payload (Edge runtime) | GHSA-4c39-4ccg-62r3 |
| SSRF in rewrites via attacker-controlled hostname | GHSA-p9j2-gv94-2wf4 |
| Unauthenticated disclosure of internal Server Function endpoints | GHSA-955p-x3mx-jcvp |

## Exposure analysis

Noor's `apps/web` uses: App Router, Middleware (session refresh),
**Server Actions** extensively (login, logout, password reset), and no
custom server, no `next/image`, no Pages Router, no i18n routing. That
directly implicates the **Server Actions DoS/SSRF/disclosure** advisories
(GHSA-m99w-x7hq-7vfj, GHSA-89xv-2m56-2m9x, GHSA-955p-x3mx-jcvp,
GHSA-4c39-4ccg-62r3) and the **Middleware cache-poisoning** advisory
(GHSA-3g8h-86w9-wvmq) as genuinely relevant to our actual attack surface —
not theoretical. The Image Optimizer and Pages/i18n advisories don't apply
to current usage but would the moment either feature is adopted.

## Was there a non-breaking fix?

No. `14.2.35` is the newest stable 14.x release; every one of the advisories
above is fixed only in `next@15.x`/`16.x`. There is no smaller step within
the 14 line.

## Spike: upgrade to next@15.5.21 (this session, git worktree `spike/next-15-upgrade`)

Chose 15.5.21 (latest stable 15.x) over jumping straight to 16.2.11 — it's
the smaller version step, and 16 additionally removes `next lint` outright
(15 only deprecates it with a working codemod path), so 15 is the more
conservative target to actually test first.

**Breaking change hit immediately:** Next 15's "Async Request APIs" — the
same change documented in Next's own 15.0 upgrade guide. `cookies()` in
`apps/web/lib/supabase/server.ts` now returns `Promise<ReadonlyRequestCookies>`
instead of the value directly:

```
lib/supabase/server.ts(32,28): error TS2339: Property 'getAll' does not
exist on type 'Promise<ReadonlyRequestCookies>'.
```

Same for the `searchParams` prop on any page reading query params
(`/login`, `/forgot-password`, `/update-password` — 3 files) — it's now
`Promise<{...}>`, not the object directly.

### Fix applied (5 call sites + 1 function signature + 3 page props)

* `lib/supabase/server.ts`: `createClient()` → `async createClient()`,
  `cookies()` → `await cookies()`.
* `lib/auth/context.ts`, `lib/auth/actions.ts` (4 call sites),
  `app/auth/callback/route.ts`: `createClient()` → `await createClient()`.
* `app/login/page.tsx`, `app/forgot-password/page.tsx`,
  `app/update-password/page.tsx`: page component → `async`, `searchParams`
  prop typed as `Promise<...>`, destructured via `await searchParams`.

### Result after the fix (spike, then ported to `main` and re-verified there)

```
$ npm run typecheck --workspace=apps/web   → exit 0
$ npm run lint --workspace=apps/web        → "No ESLint warnings or errors"
                                              (with a deprecation notice:
                                              `next lint` removed in Next 16,
                                              codemod path documented)
$ npm run test --workspace=apps/web        → 8/8 assertions pass
$ npm run build --workspace=apps/web       → Compiled successfully,
                                              10 routes generated identically
                                              to the pre-upgrade build
```

`npm audit` after the upgrade: `next` no longer appears at all. Remaining
findings are `esbuild`/`postcss` (moderate, dev-tooling-only, transitive via
ESLint/Tailwind — never shipped to a client bundle) and a **new** one:
`sharp` (high — inherited libvips CVEs), pulled in transitively by Next 15's
image-optimization dependency chain. Noor's `apps/web` does not use
`next/image` anywhere, so this new transitive dependency has no active code
path in this app today — flagged here for visibility, not treated as
blocking, and worth re-checking if `next/image` is ever adopted.

## Decision

**Upgrade now.** Applied directly to `main` in this session (not deferred to
a follow-up), because the spike showed the fix is small (7 files, ~10
lines), mechanical (matches Next's own documented migration path), fully
green across lint/typecheck/test/build, and resolves every current
Next-specific advisory including the ones that are genuinely reachable
through Noor's Server Action and Middleware usage. Waiting would mean
shipping known, reachable DoS/SSRF advisories in exactly the code paths
(Server Actions, Middleware) this session just built real authentication
on top of.

**Risk owner:** Frontend/DevOps.
**Deadline:** N/A — already applied as of this ADR.
**Follow-up (Sprint 1, non-blocking):** migrate `next lint` to the ESLint
CLI before Next 16 removes it (`npx @next/codemod@canary
next-lint-to-eslint-cli .`); re-run `npm audit` after the hosted Supabase
project exists to confirm the `sharp` transitive advisory is still inert
before ever adopting `next/image`.
