# NOOR Cinematic Rollback Runbook

Status: **LX-1.2 — Complete. Rehearsed for real against the live Vercel project, not simulated.**

## The guarantee

Rolling the public `/` route back from the cinematic experience to the legacy experience never requires a code revert, a git operation, or a rebuild triggered by a source change — only an environment variable change followed by a redeploy (Vercel bakes each deployment's environment variables in as a snapshot at deploy time, so a variable change alone does not retroactively affect an already-live deployment; a new deployment is required to pick it up).

## Required permissions

Write access to the Vercel project's environment variables (`vercel env add`/`vercel env rm`, or the equivalent dashboard page) and deploy permission on the project (`vercel deploy`).

## Procedure

```bash
# 1. Remove the current Preview-scoped value.
vercel env rm NOOR_PUBLIC_LANDING_EXPERIENCE preview -y

# 2. Add the rollback value.
echo "legacy" | vercel env add NOOR_PUBLIC_LANDING_EXPERIENCE preview

# 3. Deploy — this is the step that actually applies the new value.
vercel deploy

# 4. Verify the new deployment is Ready and still target=preview.
vercel inspect <new-deployment-url>
```

To roll forward again (restore cinematic for review), repeat with `cinematic` in step 2.

**Production is never touched by this procedure** — every step above operates on the `preview` environment scope only. Production's `NOOR_PUBLIC_LANDING_EXPERIENCE` variable does not exist in the Vercel project at all (confirmed via `vercel env ls production` — zero rows), so Production fails closed to `legacy` unconditionally regardless of anything done to Preview.

## Real rehearsal performed this mission

| Step | Deployment ID | Target | Status | Flag value |
| --- | --- | --- | --- | --- |
| 1. Initial cinematic Preview | `dpl_92fYPP9zUMxKT6fuMxBFGw6VzJa2` | preview | Ready | `cinematic` |
| 2. Rollback | `dpl_FFYZMFZD8RiEtjU4oSenZv644rkz` | preview | Ready | `legacy` |
| 3. Restoration (final state, for user review) | `dpl_9f5QMxk6G4NfSnSKrXXqexyUQXnz` | preview | Ready | `cinematic` |

**Time to rollback (env change + full redeploy + Ready confirmation): 57 seconds.** No code revert was performed or required at any point in this sequence — confirmed directly via `git status` immediately before and after, unchanged.

## Verification checklist per rollback

- [x] `vercel inspect <url>` reports `status: ● Ready` and `target: preview`.
- [x] `vercel env ls` shows the intended value for `NOOR_PUBLIC_LANDING_EXPERIENCE` in the `preview` scope only.
- [x] `curl -o /dev/null -w "%{http_code}" <url>` returns `302` (Vercel Deployment Protection's SSO redirect) — confirms protection remained enabled throughout every step of the rehearsal, never disabled.
- [x] `vercel inspect <url> --logs` shows the expected route table (`/`, `/design/cinematic-landing`, `/robots.txt`, `/sitemap.xml`) — confirms the build itself is healthy regardless of the runtime flag value.
- [x] Auth routes (`/login`, `/auth/callback`) are present in every build's route table — confirmed via the same `--logs` check; no rollback of this flag can ever affect auth routing since they are flag-independent.

## Cache behavior

Vercel's edge/CDN caching for a dynamically-rendered route (`/` carries `dynamic = "force-dynamic"`) does not cache the HTML response itself — each request is served fresh from the function, so there is no stale-cache risk after a rollback deploy completes. Static assets (`/_next/static/*`) are content-hashed and immutable, so they carry no rollback risk either.

## Known operational risks

- **A Preview deployment's environment snapshot is frozen at deploy time.** Changing the Preview-scoped variable does not affect deployments already live — only new ones. If someone is actively reviewing an OLD Preview URL when the variable changes, they will keep seeing the old behavior until a fresh deployment targets that same alias (or until they open the newest Preview URL).
- **This runbook covers the Preview environment only.** A future LX-1.4 production rollback (after cinematic ever ships to Production) would follow the identical procedure against the `production` scope instead — not rehearsed this mission, since Production never left `legacy`.
- **Vercel CLI access is required.** There is no in-app admin toggle for this flag; an operator without Vercel project access cannot perform this rollback themselves.
