# NOOR Landing SEO and Metadata Plan

Status: **LX-1.0 — In Progress**

This plan describes metadata for the *future* LX-1.2 production
landing. It does not change the current `apps/web/app/layout.tsx` or
`apps/web/app/page.tsx` metadata during LX-1.0.

## Page metadata

- **Title:** "NOOR — Clinical Intelligence OS" (unchanged — already accurate and concise; the current `layout.tsx` metadata is correct and reusable as-is)
- **Meta description:** "NOOR governs clinical guideline evidence through controlled intake, human review, and traceable knowledge — the foundation for evidence-grounded clinical intelligence." (revised from the current "Evidence-grounded clinical decision support for healthcare organizations" to reflect the real, verified foundation rather than implying the decision-support product already exists)
- **Open Graph title:** same as page title
- **Open Graph description:** same as meta description
- **Social-preview direction:** reuse the existing `/brand/social-preview.png` asset (already referenced in `layout.tsx`) — no new social-preview image is created during LX-1.0; a future refresh depicting the evidence-journey visual is a candidate for LX-1.2, not required for launch
- **Canonical route:** `/` (unchanged)

## Structured data

No `Organization`/`SoftwareApplication` JSON-LD is recommended yet —
adding structured data implying a specific product category or
certification without a genuine backing claim risks exactly the kind
of overstatement this mission prohibits. Revisit once the product has
a stable, public-facing feature set beyond internal evaluation
frameworks.

## Heading hierarchy

```
h1 — Hero headline (one per page)
h2 — Each of the 9 subsequent section headlines
h3 — none needed at this outline depth; introduced only if a section's
     internal structure (e.g. Governance's statement grid) genuinely
     needs a third level
```

## Semantic section structure

Each of the 10 sections in `NOOR_LANDING_INFORMATION_ARCHITECTURE.md`
renders as a `<section>` with an `aria-labelledby` pointing at its own
heading — matching plain, crawlable HTML rather than relying on
generic `<div>` soup.

## Crawlable content requirement

All headline, supporting copy, proof points, and status labels exist
in server-rendered HTML (Technical Architecture §Server Component
boundaries) — a crawler that does not execute JavaScript still reads
the complete, correctly-labeled narrative, including every "Available"
/ "In development" / "Product vision" status word. No content is
injected only after a scroll-triggered animation resolves.

## What this plan explicitly does not add

No certification, partnership, or compliance claim in metadata beyond
what `NOOR_LANDING_CAPABILITY_TRUTH_MATRIX.md` allows. No fabricated
`ratingValue`/review structured data. No analytics or tracking pixels
(see the mission's own §30 — out of scope for LX-1.0 regardless).
