# NOOR Cinematic Launch Monitoring

Status: **LX-1.3 — Complete.** Defines the first launch-period checks for a future LX-1.4, honestly scoped to what this app can actually observe today.

## What can actually be monitored today

Per `NOOR_CINEMATIC_OBSERVABILITY.md`: **no first-party or third-party observability pipeline exists in this app.** No new vendor was added this mission (explicitly out of scope unless a genuine safety requirement demanded it — none did). This means the checks below describe what a human operator can check manually via existing tooling (Vercel's own dashboard/CLI, direct HTTP checks, real browser spot-checks) — not automated alerting, since no automated telemetry collection exists yet.

## Manual launch-period checks (LX-1.4, day of / first 24-48h)

| Check | How | Frequency |
| --- | --- | --- |
| HTTP status of `/` | `curl -o /dev/null -w "%{http_code}" https://<production-domain>/` | Immediately post-launch, then hourly for the first day |
| HTTP status of `/login` | Same | Same |
| Root loads with correct experience | Real browser visit, confirm cinematic scene 1 renders | Immediately post-launch |
| Login succeeds and redirects correctly | Real (synthetic or real) account sign-in, confirm landing on a workspace, never `/` | Immediately post-launch |
| Vercel deployment status | `vercel inspect <url>` / dashboard | Immediately post-launch |
| Vercel function error rate | Vercel dashboard's own built-in metrics (Functions tab) | First 24-48h, periodic |
| Real Lighthouse spot-check | `npx lighthouse <production-url>` (desktop and mobile) | Within first few hours, then daily for the first week |
| Console-error spot-check | Real browser DevTools, manual scroll-through | Within first few hours |

## Explicit rollback criteria

### Rollback immediately if

- `/` returns a non-200 status for any real visitor (matches R-01's exact failure mode — this mission's own incident).
- `/login` regresses (returns non-200, or a successful sign-in no longer reaches a workspace).
- The post-login redirect regresses (any successful sign-in defaults back to `/` — the original reported defect).
- Widespread WebGL initialization failures are observed across multiple real visitors/browsers (distinct from the graceful, tested static-fallback path — this would mean the fallback ITSELF is failing).
- A severe, broad mobile usability issue is reported (e.g., the two-zone layout breaking, CTA unreachable) beyond the already-disclosed R-03 performance gap.
- Any security issue is discovered (a secret exposed, an open redirect found in production traffic, an auth bypass).

### Investigate before rolling back if

- An isolated, low-tier device/browser shows a performance complaint but the broad viewport/browser matrix (this mission's own evidence) continues to look healthy.
- A non-blocking visual discrepancy is reported (e.g., a minor rendering difference on one specific GPU/driver combination).
- A single-browser cosmetic defect is found that doesn't affect functionality or the core narrative.

## How to roll back

See `docs/landing/NOOR_CINEMATIC_ROLLBACK_RUNBOOK.md` — set `NOOR_PUBLIC_LANDING_EXPERIENCE=legacy` on Production, redeploy. No code revert required. Rehearsed twice (LX-1.2 and LX-1.3), both under ~2 minutes total.

## What this mission does NOT claim

This is not a real production alerting/monitoring system — it is a documented manual checklist for a human operator, because no automated telemetry exists. If LX-1.4 or a future mission wants real automated alerting (error-rate thresholds, automatic rollback triggers, etc.), that requires deliberately adding first-party Web Vitals collection or a monitoring vendor, which is explicitly out of this mission's scope per its own instruction not to add new vendors without a genuine safety requirement.
