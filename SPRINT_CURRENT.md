# Sprint Current: LX-1.3 — Production Hardening, Reliability, Accessibility, SEO, Performance, and Launch Readiness

**Status:** LX-1.3 — Hardening Complete, Launch Readiness Failed,
Blockers Remaining. See
`docs/verification/lx-1-3-hardening-report.md` and
`docs/launch/NOOR_CINEMATIC_GO_NO_GO.md` for the full record.

This is the final technical hardening gate before a possible
LX-1.4 Controlled Production Launch — not a platform sprint, and not
a redesign. The approved cinematic visual/narrative direction was not
touched. Production continued to serve the **legacy** landing
throughout this entire mission — confirmed via `vercel env ls
production` before and after every change made. The platform's next
step remains `S1-E3 — Hybrid Retrieval`, unaffected.

## What this mission does

Answers one question with evidence: is the approved cinematic landing
technically safe to enable in Production? Verdict: **not yet** — one
real, honestly-measured performance gap remains (see below). Along the
way, this mission found and fixed a real, active production outage
unrelated to the launch-readiness question itself, and closed two
other real gaps (an open-redirect hardening issue, and the SEO
metadata-streaming limitation LX-1.2 had left unresolved).

## Objectives

- [x] Repository audit — every LX-1.2 claim re-verified against the actual code, not assumed.
- [x] **Real production incident found and fixed**: Production had zero environment variables configured, causing HTTP 500 on `/` and `/login`. Fixed with explicit user approval; re-verified 200 on both routes.
- [x] Feature-flag hardening — expanded adversarial-value test matrix (19 total cases across LX-1.2+LX-1.3), all fail closed.
- [x] Rollback rehearsed a second time — cinematic → legacy → cinematic, no code revert, under 2 minutes.
- [x] 3-run Lighthouse methodology (never cherry-picking) — desktop clean, **mobile median 0.89, below target — the one open gap**.
- [x] Scene-by-scene FPS re-measured twice — no regression from LX-1.2's Scene 5 optimization (56-61fps every scene).
- [x] Quality-tier downgrade, tab-visibility hide/restore, scroll reliability (fast-forward/reverse/jump/reload) all verified.
- [x] 20-cycle Three.js mount/unmount lifecycle test, using real in-app SPA navigation (the rigorous variant) — 0.00MB heap growth, 1 surviving canvas.
- [x] WebGL init failure, real context loss, simulated renderer exception, full JS-disabled — all degrade to the complete static/semantic fallback, 0 raw stack traces.
- [x] **Real Firefox and WebKit browser binaries installed this mission** (previously absent) — both render correctly, 0 console errors, 0 axe violations, matching Chromium's real-GPU results.
- [x] 16-viewport responsive matrix + orientation change — 0 overflow, CTA always reachable.
- [x] Accessibility: axe (0 violations across every scanned state), real keyboard traversal, 125/150/200% zoom, forced-colors emulation. Real screen-reader testing marked LIMITED (no NVDA available in this environment).
- [x] **SEO metadata-streaming gap fixed** (not just documented) — root-caused via official, freshly-fetched Next.js docs; fixed via the officially-supported `htmlLimitedBots` config switch. Lighthouse SEO now 1.00.
- [x] **Real open-redirect hardening gap found and fixed** — a backslash-prefixed `next` value resolved off-origin under WHATWG URL parsing; sanitizer rewritten to use the `URL` constructor instead of string prefixes.
- [x] The previously-missing authentication-journey video (an LX-1.2 gap) is now recorded, using a real, fully-cleaned-up synthetic account against the hosted Supabase project.
- [x] Security review: 0 secrets in the compiled client bundle, 0 external network origins.
- [x] Product truth and synthetic-content re-audited — no status changes, no upgraded claims.
- [x] Observability readiness and a launch-monitoring checklist documented; no new vendor added.
- [x] 7 clean acceptance recordings + full screenshot set, all inspected before being reported.
- [x] Launch risk register, test matrix, and Go/No-Go documents completed with an explicit, non-subjective decision.
- [x] All 25 `apps/web` test files + typecheck + lint pass. `packages/ui`/`packages/clinical-schemas` clean. `apps/worker`'s pytest blocked by a pre-existing, unrelated local `.env` gap — documented, not fixed (out of scope).
- [x] No backend/database/Worker file touched — confirmed via `git status`.

## Real bugs/gaps found and fixed (or honestly documented) this workstream

1. **A real, active Production outage** (missing Supabase environment variables, causing `/` and `/login` to 500) — found first, fixed immediately with explicit user approval, before any planned hardening work began.
2. **A real open-redirect hardening gap** — `sanitizeNextPath()`'s string-prefix checks missed a backslash-based bypass that WHATWG URL resolution treats as off-origin; fixed with a `URL`-constructor-based check.
3. **The LX-1.2 SEO metadata-streaming limitation, genuinely resolved** — not chased in LX-1.2 for lack of a known fix; LX-1.3 found Next's own official `htmlLimitedBots` switch via fresh documentation research and applied it.
4. **The previously-missing authentication video**, recorded.
5. **One real, unresolved, honestly-reported gap**: cinematic mobile Lighthouse Performance median (0.89) falls short of the ≥90 target under proper 3-run methodology — the sole reason this mission's own Go/No-Go verdict is NO-GO rather than GO.

## Next step

```text
Resolve the listed launch blockers and repeat the failed LX-1.3 gates
```

Specifically: investigate and close the cinematic mobile performance
gap (or obtain an explicit, informed user decision to accept it as a
bounded trade-off), then re-run the 3-run mobile Lighthouse gate
before returning to the Go/No-Go document. Do not enable the
cinematic landing publicly in Production. Do not begin LX-1.4
automatically. The platform's own next step remains `S1-E3 — Hybrid
Retrieval`, unaffected by this workstream.
