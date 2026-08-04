# NOOR Cinematic Composition Map

Status: **LX-1.1.1 — Complete.** For every scene: camera state
(cross-referenced from `NOOR_CINEMATIC_CAMERA_MAP.md`, not
re-derived), object scale/screen-space bounds as actually measured
from a real screenshot, text column position, negative space, and the
primary/secondary focal point.

## Global composition rule

Every scene's text column sits in a fixed left-anchored zone
(`max-w-2xl`, `px-lg`/`sm:px-xl`/`lg:px-xxl`) with a directional
gradient wash for contrast; the Evidence Core occupies the right/center
of the frame. This split is deliberate and constant across all 7
scenes so the reader's eye always knows where text lives vs. where the
object lives — text and object never compete for the same screen
region, addressing mission §3.7's "canvas competing with text."

| Scene | Camera (see camera map) | Object screen-space bounds (measured) | Text column | Primary focal point | Secondary focal point | Negative space | Mobile | Reduced-motion |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 — Trusted Source | Hold `z=4.6`→`z=3.3`, FOV 38 | ~45% of viewport width, centered right-of-text | Left, `max-w-2xl` | The two page-layer towers | The dim, not-yet-lit aperture between them | Above/below the core, deliberately calm | Core in the top 46vh visual zone; text below | Full document-stack SVG illustration, right-anchored |
| 2 — Secure Intake | Hold `z=3.3`→`z=3.0`, orbit right | Towers ~40% width; invalid object enters from the right edge | Left | The 4 sequential verification nodes lighting in order | The invalid object's approach-and-stop path | Right margin, where the invalid object travels | Same visual-zone split; invalid-path animation simplified to a single stop-frame | Gateway + valid/rejected paths illustration |
| 3 — Human Review | Hold `z=3.0`→`z=2.35`, page-detail framing | Aperture/lock fills ~35% width, largest single focal object on the page | Left | The aperture's shackle (locked → open) | The finding marker on the tower's front page | Above the aperture, where the emerald pulse travels | Lock icon + text; camera holds closer given limited mobile screen height | Original page / extracted representation / finding / accepted-state illustration |
| 4 — Structured Knowledge | Hold `z=2.35`→`z=3.1`, pulls back | 5 blocks spread across ~50% width once formed | Left | The 3 blocks that continue to Scene 5 | The 2 that don't (visually identical, positioned differently, honest about "not every candidate is used") | Between the tower and the blocks, where provenance threads run | Fewer simultaneous block formations shown given reduced particle/geometry budget | Page → highlighted spans → chunks diagram with persistent connecting lines |
| 5 — Retrieval | Hold `z=3.1`→`z=4.0`, centers on the row | Ranked row ~55% width | Left | Rank badge "1" (DOM-projected, always brightest) | The query beam's arrival | Right of the row, where lower-ranked candidates fade | Rank badges remain DOM-projected (position recalculated for the mobile canvas) | Query + 3 ranked evidence blocks + relevance labels illustration |
| 6 — Product Vision | Hold `z=4.0`→`z=3.4`, tightest FOV | Workspace panel ~30% width, deliberately the smallest/calmest object on the page | Left | The condensing panel | The thread connecting it back to the ranked row | Generous — this is the calmest scene by design | Panel scaled to fit the 46vh band without crowding | Workspace + 3 evidence links + Product Vision label illustration |
| 7 — Reverse Traceability | 6 real stops (camera map) | Varies per stop — reuses each prior scene's own object bounds | Left, breadcrumb-style layer list appended | The traceability marker (a bright ring) | The full assembly at the final composition | Widens progressively toward the final full-Core reveal | Static 6-layer stacked list (no camera stops) | Complete 6-layer reverse-traceability diagram, no camera required |

## Desktop viewport verification

Composition bounds above were measured against real Playwright
screenshots at 1440×900 (the mission's specified target) — see
`docs/verification/screenshots/lx-1-1-1/` for the exact frames each
row's percentage estimate is drawn from.

## No unintentional empty space

Every scene keeps at least one of: the Evidence Core, a lit
verification/rank node, or the traceability marker inside the primary
visual half of the frame at all times once its hold phase begins —
verified by the same screenshot set. The one deliberate exception is
Scene 6, whose calm negative space is a compositional choice (mission
§13's "generous clinical whitespace"), not an oversight.
