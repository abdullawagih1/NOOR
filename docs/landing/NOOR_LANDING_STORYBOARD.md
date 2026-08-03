# NOOR Landing Storyboard

Status: **LX-1.0 — In Progress**

Every scene below states its narrative meaning explicitly — no scene
is described only as "animate on scroll."

## Scene 1 — Hero evidence flow

- **Scroll range:** 0 (visible on load, not scroll-triggered)
- **Visible content:** headline, supporting copy, CTAs, a horizontal 5-node evidence-flow strip
- **Primary visual object:** a small document glyph
- **Motion start state:** all 5 nodes present but dim/outline-only
- **Motion end state:** all 5 nodes filled/resolved in sequence, ending at "Traceable"
- **Narrative meaning:** this *is* the thesis — evidence becomes intelligence through a visible, ordered process, not a black box
- **User control:** none needed (short, one-shot, ~600ms); no play/pause required in production (prototype gallery adds controls for review purposes only)
- **Reduced-motion equivalent:** all 5 nodes render already-resolved, statically, in their final state
- **Mobile fallback:** same 5 nodes, vertical strip instead of horizontal, same one-shot behavior
- **Technical implementation candidate:** Framer Motion (`staggerChildren`)
- **Performance risk:** low — no images, pure CSS/SVG shapes

## Scene 2 — Trusted source verification

- **Scroll range:** section 2 enters viewport (≈10–20% scroll)
- **Visible content:** a document card with authority, version, and checksum metadata
- **Primary visual object:** the document card's status chip
- **Motion start state:** chip reads "Pending"
- **Motion end state:** chip reads "Verified" (emerald `verified` token)
- **Narrative meaning:** trust starts before any AI is involved — with a verified, versioned source
- **User control:** none (auto-triggered once, on first entry into viewport, never replays on re-scroll)
- **Reduced-motion equivalent:** chip renders directly in the "Verified" end state
- **Mobile fallback:** identical, single column
- **Technical implementation candidate:** Framer Motion `whileInView`
- **Performance risk:** low

## Scene 3 — Secure intake validation channel

- **Scroll range:** section 3 enters viewport (≈20–30%)
- **Visible content:** a horizontal channel with checksum/tenant-boundary labels; a valid file continues through, an illustrative invalid file stops
- **Primary visual object:** two small file glyphs (valid / invalid)
- **Motion start state:** both file glyphs at the channel's entrance
- **Motion end state:** valid glyph reaches the queue icon; invalid glyph is visibly stopped mid-channel with a labeled state
- **Narrative meaning:** security is a working control, not a decorative lock icon — the negative case is shown, not just the happy path
- **User control:** none
- **Reduced-motion equivalent:** both end states shown directly, no travel animation
- **Mobile fallback:** invalid-path branch collapses to a single static labeled row beneath the valid path
- **Technical implementation candidate:** Framer Motion (`animate` with `x` transform along a path)
- **Performance risk:** low

## Scene 4 — Human review gate

- **Scroll range:** section 4 enters viewport (≈30–45%)
- **Visible content:** 4 columns — source page / extracted representation / finding / reviewer decision
- **Primary visual object:** the "finding" highlight and the decision toggle
- **Motion start state:** finding unresolved (neutral state)
- **Motion end state:** finding resolved to "Accepted"; a 5th, initially-locked "downstream" indicator visibly unlocks
- **Narrative meaning:** human review is the gate that makes everything after it trustworthy — shown as an explicit unlock, not implied
- **User control:** none in production; prototype gallery adds a manual "resolve finding" button to demonstrate the interaction is deliberate, not automatic
- **Reduced-motion equivalent:** all 4(+1) states shown at once, statically, left to right in reading order
- **Mobile fallback:** columns stack vertically in the same order
- **Technical implementation candidate:** Framer Motion `layout` animation
- **Performance risk:** moderate (layout animation across 4 elements) — kept to opacity/transform only, no reflow-triggering properties

## Scene 5 — Structured knowledge assembly

- **Scroll range:** section 5 enters viewport (≈45–55%)
- **Visible content:** a page with 3 highlighted text regions assembling into 3 connected chunk cards
- **Primary visual object:** the connecting line between a highlighted region and its resulting chunk card
- **Motion start state:** page shown with no highlights
- **Motion end state:** 3 regions highlighted, 3 chunk cards visible, 3 connector lines drawn
- **Narrative meaning:** structure is derived from the page and never disconnected from it — the connector line is the whole point
- **User control:** none
- **Reduced-motion equivalent:** all highlights/cards/connectors rendered in their final state at once
- **Mobile fallback:** 2 regions animate at a time instead of 3 simultaneously; final state identical
- **Technical implementation candidate:** Framer Motion + a light inline SVG path for the connector (`pathLength` animation)
- **Performance risk:** moderate (SVG path draw) — one section only, dynamically mounted

## Scene 6 — Retrieval ranking illustration

- **Scroll range:** section 6 enters viewport (≈55–65%)
- **Visible content:** a synthetic query, a staggered list of ranked evidence candidates with relevance indicators, one candidate's exact source location highlighted
- **Primary visual object:** the ranked list
- **Motion start state:** list items absent/collapsed
- **Motion end state:** list items staggered into view, top candidate's source location highlighted
- **Narrative meaning:** retrieval quality is demonstrated as a measured, ranked process — with an explicit "evaluation framework" status, not a live clinician feature
- **User control:** none
- **Reduced-motion equivalent:** full list shown at once, no stagger
- **Mobile fallback:** list truncates to top 3 + "+N more evaluated" text
- **Technical implementation candidate:** Framer Motion (`staggerChildren`)
- **Performance risk:** low

## Scene 7 — AI clinical intelligence vision mock

- **Scroll range:** section 7 enters viewport (≈65–72%)
- **Visible content:** a structured evidence-workspace mockup (synthetic, non-clinical) with a visible "Product vision" banner
- **Primary visual object:** the mock workspace panel
- **Motion start state:** panel at 0 opacity
- **Motion end state:** panel fully visible
- **Narrative meaning:** the vision is shown, not simulated as working — deliberately the least-animated scene on the page, since nothing here is actually running
- **User control:** none
- **Reduced-motion equivalent:** identical (already minimal motion)
- **Mobile fallback:** identical, single column
- **Technical implementation candidate:** Framer Motion fade only
- **Performance risk:** low

## Scene 8 — Reverse traceability (signature scene)

- **Scroll range:** section 8, pinned for the duration of a ~400vh scroll region on desktop (≈72–92%)
- **Visible content:** 5 stages in sequence — illustrative intelligence statement → supporting evidence → retrieved chunk → exact source span → original page/guideline
- **Primary visual object:** a single focal card that morphs/recedes between the 5 stages, with a persistent breadcrumb of prior stages remaining visible (dimmed, not removed) so context is never lost
- **Motion start state:** stage 1 (statement) at full focus, breadcrumb empty
- **Motion end state:** stage 5 (guideline) at full focus, breadcrumb shows all 5 stages
- **Narrative meaning:** this is NOOR's product signature — proof that nothing is lost between an intelligence-layer claim and its original source
- **User control:** on desktop, scroll position controls timeline position (GSAP ScrollTrigger `scrub`); the prototype gallery additionally exposes play/pause/reset and a scrubber for review purposes
- **Reduced-motion equivalent:** no pinning, no scrubbing — a static, vertically-stacked sequence of all 5 stages with a manual "Next stage" / "Previous stage" button pair; identical content and order
- **Mobile fallback:** identical to the reduced-motion equivalent (mobile never gets the pinned/scrubbed version, per the mission's explicit "avoid long pinned sections" rule for mobile)
- **Technical implementation candidate:** GSAP + ScrollTrigger (desktop only, dynamically imported); DOM/CSS for the static reduced-motion/mobile version
- **Performance risk:** highest on the page — isolated in its own client component, dynamically imported, measured independently in the Performance Budget doc; GSAP/ScrollTrigger cleaned up on unmount

## Scene 9 — Governance grid

- **Scroll range:** section 9 enters viewport (≈92–97%)
- **Visible content:** a plain grid of governance statements, including explicit non-claims
- **Primary visual object:** none decorative — text-led by design
- **Motion start state / end state:** simple opacity fade
- **Narrative meaning:** trust is reinforced with plain, unembellished statements — deliberately the calmest section on the page
- **User control:** none
- **Reduced-motion equivalent:** identical (already minimal)
- **Mobile fallback:** identical, single column
- **Technical implementation candidate:** Framer Motion fade
- **Performance risk:** negligible

## Scene 10 — Final CTA

- **Scroll range:** section 10, page end (≈97–100%)
- **Visible content:** headline + one button
- **Primary visual object:** the CTA button
- **Motion start state / end state:** simple fade
- **Narrative meaning:** a calm, singular invitation — no urgency manufactured
- **User control:** none
- **Reduced-motion equivalent:** identical
- **Mobile fallback:** identical
- **Technical implementation candidate:** Framer Motion fade
- **Performance risk:** negligible
