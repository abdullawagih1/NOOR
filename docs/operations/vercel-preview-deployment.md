# Vercel Preview Deployment

## Status

**Deployed and configured with hosted Development Supabase values.**
Deployment Protection remains enabled (kept on purpose, per mission
policy — see below); full authenticated HTTP verification needs one
remaining **dashboard-only** action (Protection Bypass secret).

## Stable Preview alias

Vercel's per-deployment URLs are ephemeral (`noor-<random>-....vercel.app`)
and change on every deploy, which is awkward for a Supabase Auth redirect
allowlist. This session created an explicit, stable alias instead:

```
https://noor-preview-dev.vercel.app
```

**Re-point it after every future Preview deploy:**
```bash
vercel deploy --target=preview
# note the returned Preview URL, e.g. noor-xxxxx-abdullah-wagihs-projects.vercel.app
vercel alias set noor-xxxxx-abdullah-wagihs-projects.vercel.app noor-preview-dev.vercel.app
```

Supabase's Auth redirect allowlist points at this stable alias, not at any
specific deployment URL — see `docs/operations/hosted-supabase-setup.md`.

## Environment configuration (this session)

Preview-scoped variables set via `vercel env add <name> preview` (values
never printed, piped from a local file, encrypted at rest in Vercel):

```
APP_ENV=preview
NEXT_PUBLIC_APP_URL=https://noor-preview-dev.vercel.app
NEXT_PUBLIC_SUPABASE_URL=https://quohfsaqeqzbbvmrhmbr.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=<hosted Development anon key>
SUPABASE_URL=https://quohfsaqeqzbbvmrhmbr.supabase.co
SUPABASE_SERVICE_ROLE_KEY=<hosted Development service-role key>
```

`WORKER_BASE_URL`/`WORKER_INTERNAL_TOKEN` were **not** added — no Web→Worker
call site exists yet (Sprint 1), matching the "don't add Worker variables
prematurely" rule.

Confirm what's set (names only, values always show `Encrypted`):
```bash
vercel env ls preview
```

## Monorepo configuration (fixed in a prior session, still correct)

Root Directory = `apps/web`, framework = `nextjs`, set via the Vercel REST
API (no CLI subcommand exists for Root Directory). `vercel link` must be
run from the **repository root**, not `apps/web` — see
`docs/verification/sprint-0.5-hosted-verification.md` for why (a
subdirectory-scoped link previously failed to resolve the `@noor/ui`
workspace package).

## Deploying

```bash
# from the repository root
vercel deploy --target=preview            # every Preview deploy
vercel alias set <new-url> noor-preview-dev.vercel.app   # keep the stable alias current
vercel --prod                             # only with explicit approval — do not run casually
```

A project's **first-ever** deployment lands as `target: production`
regardless of flags (empirically confirmed, undocumented Vercel behavior)
— only relevant once, already happened in a prior session with no working
credentials wired to it at the time.

## Deployment Protection — kept enabled, by design

This project's "Vercel Authentication" protects every route, including
`/login` and `/` — not just the app's own protected workspace routes. This
was **not disabled** this session, per explicit mission policy: Deployment
Protection is a legitimate security control (Preview URLs often contain
pre-release code and, once real data exists, could expose it to anyone
with the link) and disabling it is the project owner's call, not
something to change unilaterally for testing convenience.

**Remaining step — dashboard only, not reachable via API or CLI in this
session** (confirmed: `PATCH /v9/projects/{id}` with a `protectionBypass`
field returns `400 should NOT have additional property`; two plausible
dedicated endpoints both 404):

> Vercel dashboard → `noor` project → Settings → Deployment Protection →
> **Protection Bypass for Automation** → enable. Vercel generates
> `VERCEL_AUTOMATION_BYPASS_SECRET` — copy it into a secure local
> environment or a GitHub Actions secret, never into a committed file.

## Preview smoke tests

```bash
# Without a bypass token: correctly detects and reports the protection
# wall rather than false-passing against Vercel's own SSO page.
BASE_URL=https://noor-preview-dev.vercel.app node scripts/smoke-test-web.mjs

# With a bypass token (once configured above): runs the full
# authenticated-content checks.
BASE_URL=https://noor-preview-dev.vercel.app BYPASS_TOKEN=<secret> node scripts/smoke-test-web.mjs
```

`scripts/smoke-test-web.mjs` inspects response **bodies**, not just status
codes — a redirect to `vercel.com/sso-api` is explicitly detected and
labeled, never mistaken for a real Noor page. This fixes an actual
false-positive bug from a prior session, where `fetch()` auto-following
that redirect produced misleading "200 OK" passes.

## Local dev

```bash
npm run dev --workspace=apps/web
```

`apps/web/.env.local` (git-ignored) needs the same Supabase values as
above, sourced from `supabase status` for local CLI verification or from
the hosted Development project for testing against real hosted data.
