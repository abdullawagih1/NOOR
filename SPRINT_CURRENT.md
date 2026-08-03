# Sprint Current: LX-1.0 — Immersive Landing Narrative and Motion Blueprint

**Status:** LX-1.0 — Narrative and Motion Blueprint Complete, Pending
User Approval. See
`docs/verification/lx-1-0-narrative-motion-prototype.md` for the full
record, including 4 real bugs found and fixed (opacity-driven text
contrast failures, a token/background contrast mismatch, a missing
keyboard-focusability fix, and a real mobile/reduced-motion
architecture gap caught by an automated accessibility scan) and an
honestly documented environment quirk (an `npm-cli.js` hang on this
Windows/git-bash setup, root-caused and worked around, unrelated to any
test or product defect).

This is a **separate, dedicated landing-experience workstream** — not
a platform sprint. It does not touch the database, RLS, permissions,
Worker, or any backend code, and it does not replace or modify the
production `/` landing page. Workstreams `S1-A` through `S1-E2` and
`UX-1`/`UX-1.1` remain closed exactly as previously verified; the
platform's next step is still `S1-E3 — Hybrid Retrieval` (unchanged,
see `MASTER_BACKLOG.md`). LX-1.0 exists to plan and technically
de-risk a *future* landing redesign before any production
implementation begins.

## What this workstream does

Produces a complete, evidence-grounded narrative and motion blueprint
for NOOR's future landing page: a Capability Truth Matrix built from
real repository evidence (not assumption), a 10-section information
architecture and content system, a full storyboard and motion system,
a Three.js decision (not required), a performance budget and
accessibility plan, and a Development-only prototype gallery
(`/design/landing-experience`, 404s in production, same gating pattern
as `/design-system`) containing 6 working technical prototypes plus an
isolated RTL structural preview — verified with real Lighthouse,
Playwright, and `@axe-core/playwright` runs, not claimed from reading
the code.

## Explicitly out of scope this workstream

Replacing the production landing page, beginning production
implementation (LX-1.2), any database/RLS/permissions/storage/Worker
change, any clinical or regulatory claim, any fabricated
customer/testimonial/statistic content, Three.js (no approved use case
exists), and starting LX-1.1 without the user's explicit review.

## Objectives

- [x] Repository audit (git state, current landing page, design tokens, dependencies, routes, CI) — `docs/landing/LX-1-0_BASELINE.md`.
- [x] Current landing baseline captured for real (4 viewport screenshots, real Lighthouse desktop + mobile runs, real production bundle sizes).
- [x] Capability Truth Matrix — every landing claim traces to a verified repository row.
- [x] Final narrative, audiences, 5-act structure, CTA strategy.
- [x] Information architecture (10 sections) and section-level content system.
- [x] Full storyboard — every scene's motion has an explicit narrative meaning.
- [x] Motion system (tokens, hierarchy, pin/scrub rules, reduced-motion equivalents for every scene).
- [x] Visual language, RTL structural rules, performance budget, accessibility plan, technical architecture, SEO/metadata plan, Three.js decision (not required), production plan (LX-1.1 → LX-1.4).
- [x] Development-only prototype gallery with 6 working prototypes (Framer Motion ×5, GSAP + ScrollTrigger ×1) + RTL structural preview.
- [x] Real browser verification: 15 screenshots, `@axe-core/playwright` scans (0 violations across desktop/reduced-motion/mobile/RTL after fixes), production-route-protection confirmed on a real server (`curl` 200 on `/`, 404 on the prototype route and on `/design-system`).
- [x] Full `apps/web` verification (typecheck/lint/build/21 test files, 141 assertions) plus `packages/ui`/`packages/clinical-schemas` — all clean.
- [x] Production `/` page confirmed byte-for-byte unchanged (`git diff --stat` empty).
- [x] Status docs updated (this file, PROJECT_STATE, MASTER_BACKLOG, CHANGELOG, KNOWN_LIMITATIONS).

## Real bugs found and fixed this workstream

1. Four scenes (`HeroEvidenceFlowScene`, `SourceVerificationScene`, `StructuredKnowledgeScene`, `RetrievalScene`) dimmed "unresolved" state text via `opacity` on a wrapping element that also contained the label — blending text color toward the background and dropping WCAG contrast as low as **1.36:1** against a 4.5:1 requirement. Caught by a real `@axe-core/playwright` scan, not by inspection. Fixed by animating only the decorative icon/element, never the text.
2. `text-muted` (`#59718F`) clears AA against white/blue-tinted backgrounds but only reaches **4.31:1** against the teal-tinted `accent-soft` background used for "active" states in two scenes — just under the 4.5:1 minimum. Fixed by switching those specific labels to `text-body`.
3. A scrollable prototype-stage container and the traceability scene's internal scroller were not keyboard-focusable (`scrollable-region-focusable`, caught at the 390px mobile viewport). Fixed with `tabIndex`/`role`/`aria-label`.
4. A real gap between the documented architecture and the shipped code: the traceability scene branched only on the reduced-motion preference, not on viewport width, contradicting this mission's own rule that mobile never gets the pinned/scrubbed version. Caught by the mobile accessibility scan, not by review. Fixed with a real `matchMedia` viewport check.
5. (Environment, not product) `npm run test --workspace=apps/web` hung indefinitely via the `npm-cli.js` wrapper on this Windows/git-bash setup, traced to orphaned npm/`next dev` processes left over from earlier verification steps in the same long session. Root-caused via `Get-CimInstance Win32_Process`, resolved by killing the orphans; the identical test command chain run directly (bypassing `npm-cli.js`) completed cleanly with all 21 files passing.

## Next step

```text
User review of the LX-1.0 narrative, storyboard, and browser-rendered motion prototypes
```

Do not start LX-1.1 automatically. Do not begin LX-1.2 (production
implementation) under any circumstance until LX-1.1 approval closes.
The platform's own next step remains `S1-E3 — Hybrid Retrieval`,
unaffected by this workstream.
