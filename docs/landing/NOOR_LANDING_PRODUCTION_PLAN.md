# NOOR Landing Production Implementation Plan

Status: **LX-1.0 — In Progress**

This plan breaks the remaining landing work into four phases. LX-1.0
(this mission) delivers the narrative, storyboard, motion system, and
browser-rendered technical prototypes only. **LX-1.2 does not begin
during this mission.**

## LX-1.1 — Visual and Motion Prototype Approval

- **Scope:** No code changes. The user reviews the LX-1.0 narrative, capability truth matrix, storyboard, and the 6 working prototypes at `/design/landing-experience`, and either approves the direction, requests changes, or rejects specific scenes.
- **Inputs:** every LX-1.0 deliverable listed in this mission's §34, plus the browser evidence in `docs/verification/lx-1-0-narrative-motion-prototype.md`.
- **Deliverables:** a recorded decision (approved / changes requested / rejected) per scene, and an updated storyboard if changes are requested.
- **Tests:** none — this is a review gate, not an implementation phase.
- **Acceptance gate:** explicit user sign-off on the narrative direction and each prototype scene before LX-1.2 may begin.
- **Dependencies:** LX-1.0 complete.
- **Risks:** scope creep if approval is partial — mitigated by approving per-scene rather than all-or-nothing.
- **Estimated component boundaries:** N/A (no implementation).
- **Production route impact:** none.

## LX-1.2 — Production Landing Implementation

- **Scope:** Build the real `packages/ui/components/landing/*` (or `apps/web`-local equivalent, decided at kickoff) components for all 10 approved scenes; replace `apps/web/app/page.tsx` content with the new narrative, reusing `PublicShell` unchanged; wire the two real CTAs (`/login`, in-page anchor).
- **Inputs:** the LX-1.1 approval record; the approved storyboard/motion system/content system as authored (or as amended) in LX-1.0.
- **Deliverables:** the new `/` page; any new shared components; updated `NOOR_LANDING_SEO_AND_METADATA.md`-described metadata actually applied to `layout.tsx`/`page.tsx`.
- **Tests:** `apps/web` lint/typecheck/test/build; a new Playwright regression pass for the production route at all required viewports; an `@axe-core/playwright` scan of the shipped page (not just the prototype gallery).
- **Acceptance gate:** production route passes the same bar the current `/` page already meets in `LX-1-0_BASELINE.md` §4 (Lighthouse Accessibility/Best Practices/SEO not regressing below the recorded baseline; Performance judged against `NOOR_LANDING_PERFORMANCE_BUDGET.md`'s production targets, not the current page's near-zero-JS baseline).
- **Dependencies:** LX-1.1 approval.
- **Risks:** bundle growth from Framer Motion/GSAP if not properly code-split — mitigated by the dynamic-import strategy already specified in `NOOR_LANDING_TECHNICAL_ARCHITECTURE.md`.
- **Estimated component boundaries:** ~10 scene components + 1 shared `MotionBoundary`/reduced-motion hook + 1 GSAP-only traceability timeline component, per the Technical Architecture doc.
- **Production route impact:** `/` changes for the first time since UX-1.1.

## LX-1.3 — Performance and Accessibility Hardening

- **Scope:** Real Lighthouse/axe verification against the deployed Vercel Preview (not localhost, resolving the mobile-throttling measurement caveat flagged in `LX-1-0_BASELINE.md` §4.4); tune bundle splitting; fix any regression found.
- **Inputs:** the shipped LX-1.2 page on a real Preview URL.
- **Deliverables:** an updated performance/accessibility report against real infrastructure; any follow-up fixes.
- **Tests:** Lighthouse (desktop + mobile, real Preview URL), `@axe-core/playwright`, manual keyboard/RTL spot-check.
- **Acceptance gate:** meets every target in `NOOR_LANDING_PERFORMANCE_BUDGET.md`'s "Production targets" table.
- **Dependencies:** LX-1.2 deployed to a Preview URL.
- **Risks:** the real mobile numbers may differ meaningfully from the artifact-affected localhost baseline in either direction — budget contingency for at least one hardening pass.
- **Estimated component boundaries:** no new components; tuning only.
- **Production route impact:** none beyond the already-shipped LX-1.2 page (unless a fix requires a code change, which stays within the same route).

## LX-1.4 — Visual Acceptance and Launch

- **Scope:** Final Playwright screenshot evidence at all required viewports (matching the rigor of every prior sprint's visual-acceptance step, e.g. UX-1.1, S1-E2), explicit user visual acceptance, production deploy.
- **Inputs:** LX-1.3's hardened page.
- **Deliverables:** visual-acceptance screenshots; updated status docs (`PROJECT_STATE.md`, `SPRINT_CURRENT.md`, `MASTER_BACKLOG.md`, `CHANGELOG.md`); a production Vercel deploy (`vercel --prod`, only after explicit user go-ahead, matching this repository's established deploy-confirmation discipline).
- **Tests:** full CI green; production smoke test.
- **Acceptance gate:** explicit user visual acceptance, matching the bar set by UX-1.1's own acceptance gate.
- **Dependencies:** LX-1.3 complete.
- **Risks:** none beyond standard deploy risk, mitigated by the existing `scripts/preflight-vercel-deploy.mjs` guard.
- **Estimated component boundaries:** none new.
- **Production route impact:** `/` goes live with the new experience for real visitors.

None of LX-1.1–LX-1.4 begin automatically. Each requires the prior
phase's acceptance gate to close first, and LX-1.1 specifically
requires the user's explicit review of this mission's output.
