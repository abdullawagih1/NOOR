# NOOR Cinematic Scene Timeline

Status: **LX-1.1 — In Progress** (scroll ranges below are the values
actually implemented in `useMasterTimeline.ts` and verified by the
motion-state tests in the verification report — not aspirational)

## Master timeline

One `ScrollTrigger` bound to the page's own scroll (never a nested
container), spanning a `4200px` scroll distance (`pin: false` — see
`NOOR_CINEMATIC_TECHNICAL_ARCHITECTURE.md` for why the canvas is
`position: sticky`, not GSAP-pinned, and what that changes). Progress
`0..1` maps to scene boundaries below. Ranges are uneven by design —
Scene 6 (Product Vision) is deliberately the shortest and calmest;
Scene 7 (Reverse Traceability) is the longest, since it re-traverses
five prior stages.

| Scene | Scroll range | % of total | Narrative |
| --- | --- | --- | --- |
| 1 — Trusted Source | 0%–14% | 14% | Clinical intelligence begins with a source you can trust |
| 2 — Secure Intake | 14%–28% | 14% | Trust is established before processing begins |
| 3 — Human Review | 28%–43% | 15% | Automation prepares the evidence; humans decide when it's ready |
| 4 — Structured Knowledge | 43%–59% | 16% | Reviewed pages become structured knowledge without losing their source |
| 5 — Retrieval Foundation | 59%–73% | 14% | Retrieval quality is measured before it's trusted |
| 6 — Product Vision | 73%–86% | 13% | Clinical intelligence should remain connected to the evidence that supports it |
| 7 — Reverse Traceability | 86%–100% | 14% | Nothing should be lost between intelligence and its source |

## Per-scene specification

### Scene 1 — Trusted Source (0%–14%)

- **Object state:** `DocumentStack` at rest, layers slightly separated with a depth offset that resolves as scroll progresses.
- **Camera:** dolly from `[0, 0.3, 6.5]` to `[0, 0.3, 5.0]` (see camera map).
- **Text:** headline "Clinical intelligence begins with a source you can trust." / supporting copy / status chip "Available foundation".
- **Status:** Available foundation.

### Scene 2 — Secure Intake (14%–28%)

- **Object state:** `VerificationRing` fades in and resolves pending→verified; invalid-path object approaches and visibly stops outside the ring.
- **Camera:** orbits to `[1.6, 0.6, 4.4]`, target shifts to reveal the ring.
- **Text:** headline "Trust is established before processing begins." / supporting copy / status chip "Available foundation".
- **Status:** Available foundation.

### Scene 3 — Human Review (28%–43%)

- **Object state:** one page detaches and enlarges; `finding` marker visible; lock glyph closed. At ~38% (near the end of this scene's range) the lock resolves open and an emerald pulse travels along the (not-yet-visible-to-the-user) provenance spine's first segment.
- **Camera:** moves to `[0.6, 0.9, 3.0]`, page-detail framing.
- **Text:** headline "Human review is not friction. It is the safety layer." / supporting copy / status chip "Available foundation".
- **Rule honored:** the lock only resolves as a function of scroll position past a fixed threshold within the scene — never on a timer, never before the user reaches that point (mission §15's explicit rule).

### Scene 4 — Structured Knowledge (43%–59%)

- **Object state:** highlighted regions on the enlarged page detach into 3 `StructuredBlocks`, each connected by a `ProvenanceThread` back to its origin point on the still-visible page.
- **Camera:** pulls back to `[2.4, 1.1, 5.0]`, then drifts laterally to `[3.4, 1.1, 4.2]` within the same scene range.
- **Text:** headline "Structure the knowledge. Keep the provenance." / supporting copy / status chip "Available foundation".

### Scene 5 — Retrieval Foundation (59%–73%)

- **Object state:** the 3 blocks reposition into a ranked row (largest/closest = most relevant); the cyan query beam arrives and terminates at the top candidate; particle field activates (representational, not decorative).
- **Camera:** centers at `[0, 1.5, 6.2]`, facing the row.
- **Text:** headline "Retrieval quality is measured before it's trusted." / supporting copy / status chip "**Internal evaluation foundation**" (explicit, non-clinician-facing label — mission §17's product-truth rule).

### Scene 6 — Product Vision (73%–86%)

- **Object state:** `WorkspacePanel` condenses in front of the ranked row, connected by the thread material; no readable content inside the canvas.
- **Camera:** tightens to `[0, 1.9, 4.6]` — the calmest, smallest-FOV scene on the page.
- **Text:** headline "Building toward clinical intelligence that stays connected to evidence." / supporting copy / status chip "**Product vision**" (large, visible — never fine print). A small "Synthetic demonstration — not clinical guidance" label accompanies the panel's DOM overlay.

### Scene 7 — Reverse Traceability (86%–100%)

- **Object state:** no new geometry — the camera retraces the existing `ProvenanceThread` spine backward through Scenes 6→5→4→3→2→1's exact keyframes.
- **Camera:** starts at Scene 6's end position, ends at `[0, 1.0, 9.5]` — pulled back further than Scene 1's own start, revealing the complete assembly.
- **Text:** stage labels crossfade in the same reverse order (Intelligence statement → Supporting evidence → Retrieved chunk → Exact source span → Original page → Trusted guideline), each remaining visible in a dimmed breadcrumb once passed (never removed — same rule LX-1.0 established for its own traceability scene).
- **Final headline:** "Nothing is lost between intelligence and its source."
- **Final CTA (appears at 98%–100%):** "Build clinical intelligence on evidence you can trace." — primary "Sign in to NOOR" (→ `/login`), secondary "Explore the evidence journey again" (smooth-scrolls to 0%).

## Timing notes

Ranges above were tuned twice during real browser testing (Playwright
motion-state checks): Scene 3 was widened from an initial 12% to 15%
because the lock-resolution threshold needed enough scroll distance to
read as scroll-driven rather than instantaneous; Scene 6 was narrowed
to 13% specifically to keep it the calmest, shortest scene as designed.
