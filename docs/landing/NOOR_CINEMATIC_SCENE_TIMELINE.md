# NOOR Cinematic Scene Timeline

Status: **LX-1.1.1 — Complete** (scroll ranges below are the values
actually implemented in `sceneConfig.ts` and verified by the
calibrated motion-state checkpoints in
`docs/verification/lx-1-1-1-cinematic-polish-verification.md` — not
aspirational).

## What changed from LX-1.1

The user's rejection named the acceptance recording as "too fast" and
the scroll boundaries as not giving each scene a real hold. Two
concrete changes, both in code, not just documentation:

1. **`DESKTOP_VH_MULTIPLIER` widened from 6 to 8.5** (mobile 4.2→6.5) — every scene now spans more real scroll distance to read, observe, and register cause-and-effect in.
2. **Every scene's camera path is now `[hold, hold, move]`** (`holdThenMove()` in `sceneConfig.ts`) instead of a single continuous dolly across the scene's entire range — the camera sits still for the first ~55% of a scene's local progress, then moves in the final ~45%. See `NOOR_CINEMATIC_CAMERA_MAP.md`.

## Master timeline

One `ScrollTrigger` bound to the page's own scroll (never a nested
container, never GSAP-`pin`ned — the copy uses CSS `position: sticky`
instead, see `NOOR_CINEMATIC_TECHNICAL_ARCHITECTURE.md`). Progress
`0..1` maps to the scene boundaries below.

| Scene | Scroll range | % of total | Narrative |
| --- | --- | --- | --- |
| 1 — Trusted Source | 0%–13% | 13% | Clinical intelligence begins with a source you can trust |
| 2 — Secure Intake | 13%–27% | 14% | Trust is established before processing begins |
| 3 — Human Review | 27%–44% | 17% | Automation prepares the evidence; humans decide when it's ready |
| 4 — Structured Knowledge | 44%–59% | 15% | Reviewed pages become structured knowledge without losing their source |
| 5 — Retrieval Foundation | 59%–73% | 14% | Retrieval quality is measured before it's trusted |
| 6 — Product Vision | 73%–84% | 11% | Clinical intelligence should remain connected to the evidence that supports it |
| 7 — Reverse Traceability | 84%–100% | 16% | Nothing should be lost between intelligence and its source |

Scene 3 (Human Review) is now the widest available-foundation scene —
it carries the most cause-and-effect (finding → locked → accepted →
pulse → unlocked) and needed the most room after real browser testing
showed the accept-threshold transition reading as abrupt at the
previous, narrower range.

## Per-scene specification

### Scene 1 — Trusted Source (0%–13%)

- **Object state:** the N-spine's two page-layer towers resolve from a spread/scattered state to their resting stacked position; the left tower's base "source registered" node lights up (emerald).
- **Camera:** holds at `[0, 0.15, 4.6]` (close — the core fills a large share of the frame from the very first paint, addressing "core too small" feedback), moves to `[0, 0.15, 3.3]` in the scene's final 45%.
- **Text:** `<h1>` "Clinical intelligence begins with a source you can trust." (the page's one required `<h1>` — a real axe scan caught every scene using `<h2>`, leaving the page with none) / supporting copy / status chip "Available foundation".

### Scene 2 — Secure Intake (13%–27%)

- **Object state:** 4 sequential verification nodes (file identity, SHA-256, tenant boundary, private registration — mission §12's explicit 4-state list) light up in order along the tower base; a second, smaller, duller document approaches from off-frame, fails validation partway (`invalidRejected` crossing 0.5), turns toward the critical color, and stops before reaching the spine — never crossing it.
- **Camera:** holds at `[0, 0.15, 3.3]`, moves to `[0.9, 0.35, 3.0]`.
- **Text:** headline "Trust is established before processing begins." / status chip "Available foundation".

### Scene 3 — Human Review (27%–44%)

- **Object state:** a finding marker highlights on the tower's front page; the central aperture's shackle stays closed (locked). At a fixed local-progress threshold (68% of the scene, `ACCEPT_THRESHOLD` in `EvidenceCoreScene.ts` — never a timer), the shackle rotates open, the finding fades (its job is done once accepted), and an emerald point light pulses outward along the bridge toward the right tower.
- **Camera:** holds at `[0.9, 0.35, 3.0]`, moves to `[0.35, 0.55, 2.35]` — a closer, page-detail framing.
- **Text:** headline "Human review is not friction. It is the safety layer." / status chip "Available foundation".
- **Rule honored:** the lock only resolves as a function of scroll position past the fixed threshold — never on a timer, never before the user reaches that point (mission §15/§3.5's explicit rule, re-verified this mission via a calibrated checkpoint at local progress 0.62 showing the pre-accept state and 0.72 showing post-accept).

### Scene 4 — Structured Knowledge (44%–59%)

- **Object state:** 5 structured blocks (3 that continue to Scene 5 as ranked candidates, 2 that don't — mission §15's "at least five candidates" requirement) detach from the tower's highlighted spans, each connected by a provenance thread back to its exact origin point.
- **Camera:** holds at `[0.35, 0.55, 2.35]`, moves to `[1.5, 0.65, 3.1]`.
- **Text:** headline "Structure the knowledge. Keep the provenance." / status chip "Available foundation".

### Scene 5 — Retrieval Foundation (59%–73%)

- **Object state:** the 3 candidate blocks (of the 5 total) reposition into a ranked row (largest/closest = most relevant); a cyan query beam arrives from off-frame and terminates at the top candidate; DOM rank badges ("1", "2", "3") project onto their exact screen position via `EvidenceCoreScene.getScreenAnchors()` (mission §15's "visible rank numbers"); particle field activates.
- **Camera:** holds at `[1.5, 0.65, 3.1]`, moves to `[0.1, 1.0, 4.0]`.
- **Text:** headline "Retrieval quality is measured before it's trusted." / status chip "**Internal evaluation foundation**" (explicit, non-clinician-facing label — mission's product-truth rule).

### Scene 6 — Product Vision (73%–84%)

- **Object state:** the workspace panel condenses in front of the ranked row, connected by the same thread material; no readable content inside the canvas.
- **Camera:** holds at `[0.1, 1.0, 4.0]`, moves to `[0, 1.35, 3.4]` — the calmest, smallest-FOV scene on the page.
- **Text:** headline "Building toward clinical intelligence that stays connected to evidence." / status chip "**Product vision**" (large, visible — never fine print). A "Synthetic demonstration — not clinical guidance" label accompanies the panel's DOM overlay.

### Scene 7 — Reverse Traceability (84%–100%)

- **Object state:** no new geometry — a bright traceability marker (a ring) moves between 6 named anchor positions (`TRACEABILITY_LAYERS` in `sceneConfig.ts`) as local progress advances, each anchor projected to a DOM label via the same screen-anchor system Scene 5 uses for rank badges. This is the concrete fix for the rejected "reverse traceability is only labels and fades" defect — every stop now has both a real camera framing AND a distinct, camera-tracked visual marker + label, not an implicit camera position alone.
- **Camera:** 6 real stops reusing Scenes 6→5→4→3→2→1's own hold framings in reverse (see `NOOR_CINEMATIC_CAMERA_MAP.md`'s Scene 7 table for exact local-progress boundaries), ending on the full composition at `[0, 0.75, 6.4]`.
- **Text:** the 6 layer labels ("Intelligence statement" → "Supporting evidence" → "Retrieved chunk" → "Exact source span" → "Original page" → "Trusted guideline") appear as a persistent DOM breadcrumb-style projection, always reflecting the current marker position — never removed once passed.
- **Final headline:** "Nothing is lost between intelligence and its source."
- **Final CTA (appears near 99–100%):** "Build clinical intelligence on evidence you can trace." — primary "Sign in to NOOR" (→ `/login`), secondary "Explore the evidence journey again" (smooth-scrolls to 0%).

## Timing notes (LX-1.1.1)

Ranges above were re-tuned during real browser testing with a
**calibrated** binary-search helper (not an approximation from
`document.body.scrollHeight`, which was caught drifting up to 16
percentage points from the app's real reported progress in LX-1.1's
own verification) — every checkpoint in the verification report is
confirmed against the app's own `window.__noorCinematicTimeline` test
global, not assumed from scroll position.
