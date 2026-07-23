# Noor V1 — Intended Use (Draft)

**Status:** Draft — requires clinical partner sign-off before Sprint 1 knowledge
activation. Not a regulatory or clinical approval document.

## Intended purpose

Noor V1 helps qualified healthcare professionals retrieve and review
recommendations from an approved clinical guideline for one defined clinical
domain. It presents evidence-grounded, cited answers and explicitly refuses
to answer when evidence is insufficient, conflicting, or out of scope.

## Intended users

Clinicians, clinical pharmacists, clinical reviewers, knowledge managers,
quality/safety reviewers, and organization administrators acting within a
healthcare organization. Noor is **not** intended for direct patient use in
V1.

## Intended clinical domain

**Working default (pending confirmation): Adult Hypertension.**
Alternative candidates under consideration: type 2 diabetes screening,
chronic kidney disease monitoring, adult asthma, antibiotic stewardship.
V1 supports exactly one domain at a time.

## What Noor V1 does

* Retrieves and displays approved, versioned guideline text relevant to a
  clinician's question.
* Generates a structured, cited summary strictly grounded in retrieved
  evidence.
* Flags insufficient, partial, or conflicting evidence rather than guessing.
* Preserves full traceability: document, version, section, page, retrieval
  run, prompt version, model version, verification result.

## What Noor V1 explicitly does not do

* Does not access, store, or reason over real patient records or PHI.
* Does not integrate with an EHR/HIS or synchronize via FHIR.
* Does not recommend medications, dosing, or patient-specific treatment.
* Does not predict clinical risk or operate autonomous clinical actions.
* Does not replace the clinician's judgment or final decision authority.
* Does not search the open internet during clinical answering.

## Out-of-scope question handling

Questions outside the confirmed clinical domain, or requiring patient-specific
judgment Noor cannot ground in the approved guideline, must be classified
`out_of_scope` and refused with an explanation — never partially answered.

## Human oversight

Every Noor V1 answer requires clinician review (`requires_clinician_review:
true` is a fixed field in the structured answer contract, not a toggle). A
clinical reviewer must approve each guideline version before its content is
retrievable at all (see the knowledge lifecycle in
`docs/architecture/DECISIONS.md`).

## Open items pending clinical partner confirmation

1. Final clinical domain selection.
2. Named clinical reviewer(s) and their availability.
3. Language scope (English only vs. English + Arabic) for V1 launch.
4. Source guideline authority/authorities to register first.
