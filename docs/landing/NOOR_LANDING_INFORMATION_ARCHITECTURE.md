# NOOR Landing Information Architecture

Status: **LX-1.0 — In Progress**

| # | Section | Narrative Purpose | Emotional Goal | Product Truth Status | Primary Visual | Interaction | CTA | Desktop Behavior | Mobile Behavior | Reduced-Motion Behavior | Performance Risk | Accessibility Risk |
| - | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | Hero | State the central thesis before any product detail | Trust | Available (the journey shown is the real S1-A→S1-D3 pipeline) | Evidence-flow strip: Source → Verified → Reviewed → Structured → Traceable | Short, non-looping entrance sequence; pauses at rest | Sign in to NOOR (primary) / Explore the evidence journey (secondary anchor) | Framer Motion staggered entrance, ~600ms total, plays once on load | Same sequence, shorter travel distance, no horizontal scroll | Static end-state shown immediately, no animation | Low — CSS/SVG + Framer Motion only, no images above the fold | Must not autoplay indefinitely; respects `prefers-reduced-motion` from first paint |
| 2 | Trusted Clinical Sources | Show NOOR begins with controlled source material | Trust → Understanding | Available (S1-A) | Guideline document card with authority/version/checksum metadata | Scroll-triggered reveal; status chip animates pending → verified once | (none — informational) | Framer Motion `whileInView` reveal | Same card, stacked, same reveal trigger | Reveal shows final state directly, no state-machine animation | Low | Status change must also be announced via text, not color alone |
| 3 | Secure Intake | Show safe, controlled ingestion | Understanding | Available (S1-B) | File moving through a validation channel with SHA-256/tenant-boundary labels | Scroll-triggered; one visible "invalid path stops" branch | (none) | Framer Motion path animation | Simplified single-path version (no branch demo) on narrow viewports | Both paths shown as static labeled states | Low | Node/edge labels must be real text, not canvas-only |
| 4 | Human Review | Reframe human review as the trust-producing feature, not friction | Understanding → Technical confidence | Available (S1-D1/S1-D2) | 4-column scene: source page / extracted text / finding / reviewer decision | Scroll-driven state change: pending → highlighted finding → accepted → downstream unlocks | (none) | Framer Motion layout animation across the 4 columns | Columns stack vertically; state changes remain, no horizontal scroll | All 4 states shown at once, statically, in reading order | Low–moderate (layout animation) | Downstream "unlock" must not remove content from the accessibility tree before/after reveal |
| 5 | Structured Knowledge | Show the provenance-preserving path from page to chunk | Technical confidence | Available (S1-D3) | Page with highlighted spans assembling into connected chunk cards | Scroll-driven: spans highlight in sequence, then connect to chunk nodes via a visible line | (none) | Framer Motion + a light SVG connector | Fewer spans shown at once; connector remains | Final connected state shown directly | Moderate (SVG path draws) | Connector meaning must be stated in text near it, not implied by line alone |
| 6 | Retrieval Foundation | State retrieval-evaluation honestly | Technical confidence → Clinical confidence | In development / Available-as-evaluation (S1-E1, S1-E2) | Query → ranked evidence candidates → exact source location, with an explicit "Evaluation framework" status chip | Scroll reveal of the ranking list with relevance indicator | (none) | Framer Motion stagger on list items | List collapses to top-3 candidates | List shown fully expanded, no stagger | Low | Status chip text must be read by screen readers alongside the visual label |
| 7 | AI Clinical Intelligence Vision | Present the future vision honestly, clearly labeled | Product ambition | Future vision | Structured evidence workspace mockup with a visible "Product vision" banner | Minimal — mostly static, one subtle hover state on the mock question bar | (none) | Framer Motion fade-in only | Same, single column | Same (already minimal motion) | Low | The "Product vision" label must be in the accessible name of the section, not decorative-only |
| 8 | Traceable Evidence (signature scene) | Demonstrate reverse traceability | Clinical confidence (culmination) | Available, applied to a labeled future-vision starting statement | Pinned, scroll-scrubbed reversal: statement → evidence → chunk → span → page → guideline | GSAP ScrollTrigger pinned timeline on desktop | (none) | GSAP pinned/scrubbed sequence, 5 stages | No pinning; a vertically-stacked static sequence with a manual "Next" affordance replaces scroll-scrubbing entirely | Identical to mobile behavior: static stacked sequence, no scrub, no pin | Highest of all sections — isolated, dynamically imported, measured independently | No scroll-trapping; keyboard users get explicit next/previous controls, never scroll-locked |
| 9 | Governance and Safety | State control guarantees and explicit non-claims | Trust (reinforced) | Available (tenant isolation, immutable provenance, audit — all hosted-verified across every sprint) | A plain, non-animated grid of governance statements | None beyond standard reveal | (none) | Framer Motion `whileInView` fade, no stagger needed | Same, single column | Same | Negligible | Plain text, no icon-only meaning |
| 10 | Final CTA | Single, calm, real invitation | Clear invitation | Available (`/login` is real) | Headline + one button | None | Sign in to NOOR | Framer Motion fade | Same | Same | Negligible | Button target size ≥ 44×44px |

## Text wireframe (single-column reading order, matches DOM order)

```
[Header: Noor logo | Sign in]

[Hero]
  eyebrow: "Clinical Intelligence OS"
  h1: "Evidence comes before intelligence."
  p:  supporting paragraph
  [evidence-flow visual]
  [Sign in to NOOR] [Explore the evidence journey ↓]

[Section 2: Trusted Clinical Sources]
  eyebrow, h2, p
  [document card]

[Section 3: Secure Intake]
  eyebrow, h2, p
  [validation channel visual]

[Section 4: Human Review]
  eyebrow, h2, p
  [4-column review scene]

[Section 5: Structured Knowledge]
  eyebrow, h2, p
  [page-to-chunk visual]

[Section 6: Retrieval Foundation]
  eyebrow, h2, p, status chip: "Evaluation framework — internal, not yet clinician-facing"
  [ranked-candidate visual]

[Section 7: AI Clinical Intelligence Vision]
  eyebrow, h2, p, status chip: "Product vision"
  [evidence workspace mock]

[Section 8: Traceable Evidence]
  eyebrow, h2, p
  [reverse-traceability sequence]

[Section 9: Governance and Safety]
  eyebrow, h2
  [governance statement grid, incl. explicit non-claims]

[Section 10: Final CTA]
  h2
  [Sign in to NOOR]

[Footer: Noor — Clinical Intelligence OS | © year | Sign in]
```

All copy, visuals, and interactions above exist in full detail in
`NOOR_LANDING_CONTENT_SYSTEM.md` and `NOOR_LANDING_STORYBOARD.md`. This
table is the structural contract; those documents are the content and
motion contracts.
