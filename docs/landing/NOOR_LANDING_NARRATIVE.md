# NOOR Landing Narrative

Status: **LX-1.0 — In Progress**

## 1. Audiences

### Primary

- Clinical leaders (CMOs, medical directors)
- Quality and patient-safety leaders
- Medical knowledge / clinical governance teams
- Healthcare innovation leaders
- Clinical informatics teams
- Health-system decision-makers evaluating whether to bring NOOR in

These readers care about **governance, control, and defensibility** —
"if I bring this into my organization, can I explain and defend how it
handles evidence?" They are not evaluating code; they are evaluating
process integrity.

### Secondary

- Clinical reviewers (the people who will actually use the review
  workflows day to day)
- Evidence-governance / regulatory-adjacent stakeholders
- Technical healthcare partners and AI-governance stakeholders
  evaluating NOOR as an infrastructure choice
- Potential institutional partners

### Explicitly not the primary audience

Software developers, individual patients, consumer-health users, and
general AI hobbyists. Developer-level detail (checksums, deterministic
processing, exact source spans) appears throughout the narrative, but
strictly as **proof of the governance claim**, never as the narrative's
subject. A clinical leader should never feel like they wandered into a
developer changelog.

## 2. Central message

> Clinical intelligence should begin with evidence that can be
> reviewed, governed, and traced.

Every section either builds toward this message or demonstrates it in
action. NOOR is not pitched as an AI product with governance bolted
on; it is pitched as a governance-first system that is building toward
AI on that foundation — the order matters and is the entire point.

## 3. Emotional progression

```
Trust → Understanding → Technical confidence → Clinical confidence → Product ambition → Clear invitation
```

Mapped to acts:

| Emotional beat | Act | What produces the feeling |
| --- | --- | --- |
| Trust | I–II | Opening on a verified source, not a chatbot; explicit human review shown as strength |
| Understanding | II | The five-stage evidence journey made visible and legible |
| Technical confidence | II–III | Deterministic processing, checksums, exact spans — shown, not just claimed |
| Clinical confidence | III–IV | Honest retrieval-evaluation framing; the traceability reversal proving nothing gets lost |
| Product ambition | VII (future-vision section) | A restrained, clearly-labeled glimpse of where this leads |
| Clear invitation | V | A calm, single, real CTA |

## 4. Act structure

### Act I — The Problem (Section 1, part of Section 9)

Clinical intelligence cannot begin with unverified text. Clinical
sources are complex; processing can introduce loss or ambiguity; many
AI systems hide their transformation steps; trust requires provenance
and human control. No competitor is named. No industry-wide statistic
is invented — the problem is stated as a design principle NOOR holds,
not as an accusation against anyone else.

### Act II — The NOOR Method (Sections 2–5)

The currently *available* foundation, shown as a journey:

```
Trusted Source → Secure Intake → Deterministic Processing → Human Review → Structured Knowledge
```

Every claim in this act maps to an "Available" row in
`NOOR_LANDING_CAPABILITY_TRUTH_MATRIX.md`.

### Act III — Retrieval and Intelligence (Sections 6–7)

Section 6 (Retrieval Foundation) reports the real, hosted-verified
evaluation work (S1-E1 lexical baseline, S1-E2 vector baseline,
compared honestly against frozen human judgments) — framed as
*measurement discipline*, not a finished clinician-facing search
product. Section 7 (AI Clinical Intelligence Vision) is explicitly and
visibly labeled **Product vision** — no generation pipeline exists, so
none is implied.

### Act IV — Traceability (Section 8)

The signature reversal: starting from a (labeled, future-vision)
intelligence statement and walking backward — evidence → chunk →
source span → original page → trusted guideline. This is the one
place the *future* vision and the *available* foundation touch directly:
the reversal is only believable because Acts II–III already proved
every step of the forward journey is real and inspectable.

### Act V — Invitation (Section 10)

One calm CTA: **Sign in to NOOR**. No fabricated urgency, no fake demo
route, no fake logos.

## 5. Section order (final)

1. Hero
2. Trusted Clinical Sources
3. Secure Intake
4. Human Review
5. Structured Knowledge
6. Retrieval Foundation
7. AI Clinical Intelligence Vision (labeled: Product vision)
8. Traceable Evidence (signature scene)
9. Governance and Safety
10. Final CTA

## 6. CTA strategy

- Primary CTA, used in the hero and the final section: **"Sign in to
  NOOR"** → `/login` (a real, existing route).
- Secondary CTA, hero only: **"Explore the evidence journey"** → an
  in-page anchor to Section 2, not a new route.
- No "Request a demo," no waitlist form, no fabricated contact
  pipeline. NOOR is organization-provisioned; the honest secondary
  message is "NOOR currently uses organization-provisioned access,"
  not an invented lead-capture flow.

## 7. Safety and future-vision positioning

- Every future-facing claim carries a visible status word (`Product
  vision`, `In development`, `Building toward`) as body content, not
  fine print — matching the mission's explicit prohibition on hiding
  incomplete status in small type.
- The Governance section states plainly what NOOR does **not** claim:
  no regulatory or medical-device certification, no replacement of
  clinician authority, no autonomous decision-making.
- Vocabulary banned throughout (content system enforces this
  mechanically — see `NOOR_LANDING_CONTENT_SYSTEM.md` §Prohibited
  terminology): revolutionary, game-changing, magical, autonomous
  doctor, replace clinicians, zero hallucinations, perfect accuracy,
  guaranteed safety, medical superintelligence, instant diagnosis.
