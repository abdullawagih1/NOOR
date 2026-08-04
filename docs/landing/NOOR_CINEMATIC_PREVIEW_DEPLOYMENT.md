# NOOR Cinematic Preview Deployment

Status: **LX-1.2 — Complete.** Records the narrow, env-var-gated
exception that lets the cinematic route be measured against a real
production build (mission §5/§28) — required because LX-1.1's
performance numbers came entirely from `next dev` / headless
SwiftShader and could not be trusted as production evidence.

## LX-1.2 addendum — used together with `NOOR_PUBLIC_LANDING_EXPERIENCE`

This mission's Preview deployment set **both** flags together in the
Preview environment scope:

```
NOOR_CINEMATIC_PREVIEW_ENABLED=true    (unblocks /design/cinematic-landing)
NOOR_PUBLIC_LANDING_EXPERIENCE=cinematic  (makes the public "/" root render it too)
```

They are independent and serve different purposes — the first is a
narrow internal-route exception (LX-1.1.1), the second is the
production feature flag (LX-1.2, see `NOOR_PUBLIC_LANDING_FEATURE_FLAG.md`).
Both were confirmed scoped to `preview` only via `vercel env ls` —
absent entirely from `production`. A real Preview deployment was
created this mission (`dpl_92fYPP9zUMxKT6fuMxBFGw6VzJa2`, later
`dpl_9f5QMxk6G4NfSnSKrXXqexyUQXnz` after the rollback rehearsal),
confirmed `status: Ready`, `target: preview`, and Deployment
Protection confirmed still active (a `302` on an unauthenticated
`curl`) throughout. Direct HTTP content verification of the Preview
URL itself was blocked by that same Deployment Protection — no
bypass token was available in this session (provisioning one is a
one-time Vercel dashboard action, not reachable via CLI/API — see
`scripts/smoke-test-web.mjs`'s own documented `BYPASS_TOKEN`
mechanism from an earlier sprint). Build logs (`vercel inspect
--logs`, which are authenticated CLI calls, not subject to
Deployment Protection) confirmed the deployed route table exactly
matches the extensively-verified local production build
(`/`, `/design/cinematic-landing`, `/robots.txt`, `/sitemap.xml`, all
present) — see `docs/verification/lx-1-2-production-integration.md`
for the full record.

## The gate

```ts
// apps/web/app/design/cinematic-landing/page.tsx
const isProduction = process.env.NODE_ENV === "production";
const previewEnabled = process.env.NOOR_CINEMATIC_PREVIEW_ENABLED === "true";
if (isProduction && !previewEnabled) {
  notFound();
}
```

| Environment | `NODE_ENV` | `NOOR_CINEMATIC_PREVIEW_ENABLED` | Route |
| --- | --- | --- | --- |
| Local development | `development` | (irrelevant) | Available |
| A deliberately-configured Vercel Preview | `production` | `"true"` | Available |
| Every other production build (the real public site) | `production` | unset / not exactly `"true"` | 404 |

This is a **server-side** check (`page.tsx`'s own top-level code, run
before any client code), not client-side hiding — there is nothing to
bypass in the browser.

## `dynamic = "force-dynamic"` — a real bug this gate surfaced

The route was originally left as Next's default (static export where
possible). The very first attempt to build with
`NOOR_CINEMATIC_PREVIEW_ENABLED=true` — i.e., the first time Next
actually tried to render the full page tree instead of immediately
hitting `notFound()` — failed with a real, genuine build error:

```
⨯ useSearchParams() should be wrapped in a suspense boundary at page "/design/cinematic-landing"
```

`CinematicExperience` reads `useSearchParams()` for `?debug=1`, which
Next's static exporter refuses to prerender without a `Suspense`
boundary. A second, related problem: a statically-exported page bakes
in whatever the env var was at **build** time, permanently — starting
the server with the flag set after building without it had no effect,
confirmed directly by testing both orders.

**Fixed** with `export const dynamic = "force-dynamic";` — this both
resolves the `useSearchParams()` prerender error (dynamic rendering has
no such constraint) and makes the gate a genuine per-request check,
the more literal reading of "gate at the server-route level." Verified
directly: the same compiled production build responds 404 without the
env var and 200 with it set at server-start time, with no rebuild
between the two checks.

## What this does NOT change

- Vercel's own Deployment Protection remains fully in effect — this
  env var is orthogonal to it, never a substitute. A Preview
  deployment with `NOOR_CINEMATIC_PREVIEW_ENABLED=true` still requires
  whatever authentication Deployment Protection already enforces for
  that project.
- The route is never linked from public navigation, never indexed
  (no meta description, matching every other Development-only route),
  and exposes no private data or provider secrets.
- The real, public production deployment (the one actual visitors
  reach) has no reason to ever set this variable — it should remain
  unset there permanently.

## How to use it for a real measurement pass

1. In the relevant Vercel Preview deployment's environment variables (Preview scope only, never Production), set `NOOR_CINEMATIC_PREVIEW_ENABLED=true`.
2. Deploy normally — Vercel's own build runs with that variable present, so the built output already reflects it (no separate step needed, matching how `next build` behaves locally when the variable is set before building).
3. Run Lighthouse / real-GPU FPS measurement / axe against the Preview URL, subject to whatever Deployment Protection authentication that Preview requires.
4. Remove the variable (or set it to `false`) once the measurement pass is done, or let the Preview deployment simply expire.

## Local reproduction (what this mission actually ran)

```bash
NOOR_CINEMATIC_PREVIEW_ENABLED=true npm run build --workspace=apps/web
NOOR_CINEMATIC_PREVIEW_ENABLED=true npm run start --workspace=apps/web -- -p 4582
curl http://localhost:4582/                          # 200 — production `/` unaffected
curl http://localhost:4582/design/cinematic-landing   # 200 — only because the env var is set
```

and, to prove the negative case on the identical build artifact:

```bash
npm run start --workspace=apps/web -- -p 4560   # no env var this time
curl http://localhost:4560/design/cinematic-landing   # 404
```

Both were run for real this mission — see
`docs/verification/lx-1-1-1-cinematic-polish-verification.md` §Preview
gate verification for the exact commands and their real output.
