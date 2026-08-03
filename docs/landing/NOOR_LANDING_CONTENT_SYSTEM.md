# NOOR Landing Content System

Status: **LX-1.0 — In Progress**

Writing style: clear, precise, calm, confident, clinical, evidence-led,
minimal jargon. Every claim below is checked against
`NOOR_LANDING_CAPABILITY_TRUTH_MATRIX.md`.

## Global prohibited terminology (applies to every section)

revolutionary, game-changing, magical, autonomous doctor, replace
clinicians, zero hallucinations, perfect accuracy, guaranteed safety,
medical superintelligence, instant diagnosis. Do not overuse "AI" —
each section uses it at most once, and only where the claim is real.

## Section 1 — Hero

- **Eyebrow:** Clinical Intelligence OS
- **Headline:** "Evidence comes before intelligence."
- **Supporting copy:** "NOOR transforms trusted clinical sources into governed, reviewable, and traceable knowledge — preserving provenance at every step."
- **Proof points:** none (hero states the thesis; proof follows in Sections 2–5)
- **Status label:** none needed — this is a principle statement, not a capability claim
- **CTA:** "Sign in to NOOR" (primary, → `/login`) · "Explore the evidence journey" (secondary, → `#trusted-sources`)
- **Accessibility label:** the evidence-flow visual's accessible name is "Illustration: a source document moving through verification, review, and structuring into traceable knowledge" — the full state sequence is also present as visible text, not only in the animation.
- **Motion narration:** source icon appears → a checkmark resolves ("verified") → an eye icon resolves ("reviewed") → the icon reshapes into a structured node ("structured") → a thin line extends to a small anchor icon ("traceable"). Plays once, comes to rest; never loops automatically.
- **Mobile copy variation:** none needed — copy is already concise.

## Section 2 — Trusted Clinical Sources

- **Eyebrow:** Foundation
- **Headline:** "Every knowledge object begins with a registered source."
- **Supporting copy:** "A guideline enters NOOR with an explicit authority, a version, and a verified file — before any processing begins."
- **Proof points:** authority metadata, version state, SHA-256 fingerprint, verification state
- **Status label:** "Available" (shown as a small `SemanticStatusBadge`-style chip using the existing `verified` semantic token, not a new color)
- **CTA:** none
- **Accessibility label:** document card's status change is announced via visible text ("Pending" → "Verified"), never color alone
- **Motion narration:** document card enters → checksum indicator resolves → status chip flips from pending to verified
- **Mobile copy variation:** none

## Section 3 — Secure Intake

- **Eyebrow:** Controlled Ingestion
- **Headline:** "Intake is private, verified, and tenant-isolated."
- **Supporting copy:** "Every uploaded file is checksummed and validated inside your organization's boundary before it ever reaches processing."
- **Proof points:** private upload session, SHA-256, tenant boundary, controlled processing queue
- **Status label:** "Available"
- **CTA:** none
- **Accessibility label:** the "invalid path stops" branch has a text label ("Invalid — processing does not continue"), not just a red icon
- **Motion narration:** file icon enters a channel → a checksum resolves → a valid path continues to a queue icon; a second, illustrative invalid file visibly stops before the queue
- **Mobile copy variation:** on narrow viewports, show only the valid path; the invalid-path branch collapses to one static labeled state beneath it rather than a parallel animated branch
- **Prohibited terminology (section-specific):** do not describe intake as "instant" — jobs are asynchronous and durable, not synchronous

## Section 4 — Human Review

- **Eyebrow:** Human Review
- **Headline:** "Automation prepares the evidence. Human review decides when it's ready."
- **Supporting copy:** "A reviewer compares the extracted page against its source, resolves any finding, and only then does the accepted page continue downstream."
- **Proof points:** original source page, extracted representation, finding, reviewer decision, downstream unlock
- **Status label:** "Available"
- **CTA:** none
- **Accessibility label:** the "downstream path unlocks" state change is exposed via `aria-live="polite"` text, not merely a visual transform
- **Motion narration:** source and extracted representation align side-by-side → a finding is highlighted → a decision resolves (accepted) → a downstream path visibly opens
- **Mobile copy variation:** the 4-column layout becomes a vertical 4-step sequence; identical content, no information dropped
- **Prohibited terminology:** never call this "automated quality assurance" — the decision is explicitly human

## Section 5 — Structured Knowledge

- **Eyebrow:** Structured Knowledge
- **Headline:** "Reviewed pages become provenance-preserving knowledge."
- **Supporting copy:** "Accepted pages are broken into exact, checksum-bound spans — each chunk keeps a visible line back to the page it came from."
- **Proof points:** accepted page, canonical representation, source spans, deterministic chunks, checksum indicator
- **Status label:** "Available"
- **CTA:** none
- **Accessibility label:** the connector line between chunk and source is described in adjacent text ("Chunk 2 — from page 4, characters 812–1,140"), not implied only by an SVG path
- **Motion narration:** page regions highlight in sequence → highlighted spans assemble into chunk cards → a thin line remains visibly connecting each chunk to its source region
- **Mobile copy variation:** fewer spans animate concurrently (2 at a time instead of all); final connected state is identical
- **Prohibited terminology:** never "AI-powered chunking" — chunking is deterministic, not model-driven

## Section 6 — Retrieval Foundation

- **Eyebrow:** Retrieval, Measured Honestly
- **Headline:** "Retrieval quality is measured before it's trusted."
- **Supporting copy:** "A frozen, human-judged evaluation set lets us compare retrieval methods honestly — including where a newer method doesn't win."
- **Proof points:** frozen evaluation set, human relevance judgment, ranked evidence, lexical-vs-semantic comparison
- **Status label:** "Evaluation framework — internal, not yet clinician-facing" (explicit, visible, not fine print)
- **CTA:** none
- **Accessibility label:** the status label is part of the section's accessible name, read before the visual content
- **Motion narration:** a synthetic query appears → ranked candidates stagger in with a relevance indicator → one candidate's exact source location highlights
- **Mobile copy variation:** ranked list truncates to top 3 with a "+N more evaluated" text note
- **Prohibited terminology:** never imply this is a finished clinician search feature

## Section 7 — AI Clinical Intelligence Vision

- **Eyebrow:** Product Vision
- **Headline:** "Clinical intelligence should stay connected to the evidence that supports it."
- **Supporting copy:** "We're building toward a workspace where a clinical question and its supporting evidence stay side by side — always traceable, always reviewable."
- **Proof points:** none (explicitly unbuilt) — the mock shows structure only, using synthetic non-clinical placeholder content
- **Status label:** "Product vision" (large, visible, part of the heading area, not a footnote)
- **CTA:** none
- **Accessibility label:** "Mockup — product vision, not an available feature" stated in the accessible name
- **Motion narration:** a single fade-in; no state-machine animation, since nothing is actually running
- **Mobile copy variation:** none
- **Prohibited terminology:** no diagnosis, dosage, or patient-specific content of any kind, even as placeholder

## Section 8 — Traceable Evidence (signature scene)

- **Eyebrow:** The Reverse Journey
- **Headline:** "Every statement can be walked back to its source."
- **Supporting copy:** "Start from a claim. Follow it to its evidence, its chunk, its exact span, its page, and the guideline it came from."
- **Proof points:** the full reversal chain, using the same real chunk/page/guideline concepts already proven in Sections 2–5
- **Status label:** the starting statement is explicitly labeled "Illustrative — product vision" since claim generation itself doesn't exist yet; every step *after* that (evidence → chunk → span → page → guideline) is labeled "Available" since that traceability machinery is real
- **CTA:** none
- **Accessibility label:** each of the 5 stages has a persistent text label in the DOM at all times — nothing is revealed only by scroll position for a screen reader
- **Motion narration:** GSAP pinned/scrubbed sequence — statement recedes as evidence highlights, evidence recedes as the chunk highlights, and so on, ending on the original guideline
- **Mobile copy variation:** replaced entirely by a static, manually-advanced 5-step sequence (no pinning, no scrubbing — see Motion System §Reduced-motion and mobile rules)
- **Prohibited terminology:** never state the illustrative claim as something NOOR actually generated today

## Section 9 — Governance and Safety

- **Eyebrow:** Governance
- **Headline:** "Built for evidence governance, not black-box automation."
- **Supporting copy:** "Human gates, tenant isolation, versioned sources, immutable provenance, and auditable decisions run through every stage above."
- **Proof points:** human gates, tenant isolation, versioned sources, immutable provenance, auditable decisions, no silent state transitions
- **Status label:** "Available" for every listed guarantee
- **CTA:** none
- **Accessibility label:** plain text list, no icon-only meaning
- **Motion narration:** simple `whileInView` fade, no stagger
- **Mobile copy variation:** none
- **Explicit non-claims (must appear as visible text, not omitted):** "NOOR does not claim regulatory or medical-device certification." "Clinicians retain authority over every clinical decision NOOR supports."

## Section 10 — Final CTA

- **Eyebrow:** none
- **Headline:** "Build clinical intelligence on evidence you can trace."
- **Supporting copy:** "NOOR currently uses organization-provisioned access."
- **Proof points:** none
- **Status label:** none
- **CTA:** "Sign in to NOOR" (→ `/login`)
- **Accessibility label:** standard button semantics, ≥44×44px target
- **Motion narration:** simple fade
- **Mobile copy variation:** none
- **Prohibited terminology:** no fake customer logos, testimonials, usage statistics, or hospital-partnership claims
