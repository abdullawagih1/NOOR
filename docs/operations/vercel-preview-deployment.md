# Vercel Preview Deployment

## Status as of Sprint 0.5

**Deployment pipeline: verified working.** Full HTTP behavioral
verification against the live Preview URL: **BLOCKED** by Vercel's default
Deployment Protection (see below) — a project setting, not a code issue.

## What was actually done this session

The Vercel CLI was already authenticated on this machine
(`vercel whoami` → a real account). The monorepo root/framework
configuration was **not** correct on the first attempt and had to be fixed:

1. `vercel link` run from `apps/web` created a project whose upload scope
   was *only* `apps/web` (42 files) — it had no visibility into the root
   `package.json`/lockfile or `packages/ui`. The build failed:
   ```
   npm error 404 Not Found - GET https://registry.npmjs.org/@noor%2fui
   ```
   This is the real, empirical reason a monorepo needs its **Root
   Directory** project setting configured, not just "run vercel from the
   app folder."
2. Fixed via the Vercel REST API (`PATCH /v9/projects/{id}`) since the CLI
   has no subcommand for it: `rootDirectory: "apps/web"`, `framework:
   "nextjs"`.
3. Re-linked from the **repository root** and deployed again — this time
   2.2MB uploaded (the whole repo) and the build succeeded.
4. First deployment landed as `target: production` even though `--yes` was
   used (undocumented but empirically confirmed Vercel behavior: **a
   project's first-ever deployment is always Production**, regardless of
   `--target`/`--prod` flags). No harm done — the deployment has no working
   Supabase credentials wired, so it serves only the static pages.
5. A second deploy with `--target=preview` correctly returned
   `target: preview` (confirmed via `vercel inspect`) — this is the
   reproducible path going forward.

## The real blocker: Vercel Deployment Protection ("Vercel Authentication")

Every route on the deployed URL — **including `/login`, `/`, and `/403`,
not just the protected workspace routes** — redirects unauthenticated
visitors to `vercel.com/sso-api`:

```
$ curl -sD - -o /dev/null https://<preview-url>/login
HTTP/1.1 302 Found
Location: https://vercel.com/sso-api?url=...
```

This is the team's default "Vercel Authentication" protection, which gates
*any* visitor who isn't logged into Vercel and a member of this team — it
runs in front of the Next.js app entirely, before our own middleware ever
executes. An HTTP smoke test that doesn't inspect the response *body* (only
the status code) will silently pass against Vercel's own SSO interstitial
page instead of Noor's actual page — this happened once during this
session's testing and was caught by checking the response body, not
trusted at face value. Treat any future Preview URL smoke-test "200 OK"
result as unverified until the body is confirmed to be Noor's own HTML, not
Vercel's.

**This needs one of two decisions, made deliberately, not silently
bypassed:**

1. Disable "Vercel Authentication" for this project (Project Settings →
   Deployment Protection) — makes Preview URLs reachable by anyone with the
   link, including automated smoke tests and any teammate without a Vercel
   seat.
2. Keep it enabled and use **"Protection Bypass for Automation"** (Project
   Settings → Deployment Protection → generates a secret) — pass it as
   `x-vercel-protection-bypass: <secret>` header (or
   `?x-vercel-set-bypass-cookie=true` query param once) from CI/smoke-test
   scripts, keeping protection on for casual visitors.

Neither was chosen in this session — it's a security-posture decision for
the project owner, not something to change unilaterally.

## Reproducing this deployment

```bash
# from the repository root
vercel link --yes --project noor          # once
vercel deploy --target=preview            # every subsequent Preview
vercel --prod                             # only with explicit approval
```

## Preview smoke tests (once hosted Supabase + protection bypass exist)

```bash
BASE_URL=https://<preview-url> node scripts/smoke-test-web.mjs
```

If Deployment Protection is on, add the bypass header to every request in
that script first (`x-vercel-protection-bypass`), or the results will be
false positives against Vercel's SSO page — see the warning above.
