# Guideline Registry — Domain Model

Source: `supabase/migrations/0005_guideline_registry_and_lifecycle.sql`.
This document is updated in the same PR as any change to the registry
schema.

## Entity hierarchy

```
Clinical Domain
  └── Guideline (logical publication identity)
        └── Guideline Authority (many guidelines share one authority)
        └── Guideline Version (draft → ... → active/superseded/withdrawn)
              └── Clinical Review (append-only, gates approval)
              └── Lifecycle Event (append-only history of every transition)
```

## Clinical Domains (`clinical_domains`)

Organization-scoped category a guideline belongs to (e.g. "Adult
Hypertension"). `code` is unique per organization. `is_active` toggles
visibility rather than deleting a domain once it may be referenced —
deactivation, not destructive deletion, per the mission's requirement.

No domain is seeded by the migration itself. Any domain used in
Development/test data is explicitly documented as **pending human clinical
confirmation** (see `PROJECT_STATE.md` gap G-03) — Noor does not assume a
default clinical scope.

## Guideline Authorities (`guideline_authorities`)

A professional society, ministry, or other guideline-producing body.
`is_verified` is a boolean the registry never infers from the presence of
an `official_website` value — it is set explicitly by whoever manages
authorities (`guideline_authorities.manage` permission), with
`verification_notes` recording the basis for that decision. An unverified
authority is still usable (so registry entry isn't blocked on an external
verification workflow), but the Admin Registry UI visibly flags it
("Unverified authority") wherever it's shown, so nobody mistakes an
unverified authority for an approved trust signal.

## Guidelines (`guidelines`)

The logical publication identity that spans versions — "Adult Hypertension
Management" is one guideline; "v1.0", "v1.1" are its versions.
`internal_code` is unique per organization. `current_active_version_id`
points at whichever version (if any) is currently `active` — it is
maintained exclusively by `transition_guideline_version()` (see
`guideline-lifecycle.md`), never written directly by client code.

`clinical_domain_id` and `authority_id` must belong to the same
organization as the guideline itself — enforced by composite foreign keys,
not application logic (see `docs/database/guideline-registry-schema.md`).

## Guideline Versions (`guideline_versions`)

The unit the clinical publication lifecycle actually applies to (see
`guideline-lifecycle.md` for the full state machine). Carries dates
(publication/effective/review-due/expiry), registry-only content metadata
(`evidence_scope`, `target_population`, `excluded_population`,
`methodology_summary`, `notes`), and the actor/timestamp pair for every
lifecycle milestone (`approved_at`/`approved_by`, `activated_at`/
`activated_by`, `superseded_at`/`superseded_by`, `withdrawn_at`/
`withdrawn_by`/`withdrawal_reason`).

**No file or document-processing reference exists on this table.** See
ADR 0007 — the clinical publication lifecycle and the (not-yet-built)
document-processing lifecycle are deliberately separate concerns.

`supersedes_version_id` records lineage: which earlier version of the
*same* guideline this one replaces. Set automatically on activation if not
already provided (see the lifecycle doc), and constrained to the same
`guideline_id` by a composite foreign key — cross-guideline supersession is
structurally impossible, not just application-checked.

## Clinical Reviews (`guideline_reviews`)

Append-only review decisions against a specific version, submitted only
while that version is `ready_for_review`. A review does not itself change
`lifecycle_status` — see the lifecycle doc for why review and transition
are deliberately separate actions. `review_status` is one of `pending`,
`changes_requested`, `recommended_for_approval`, `rejected`. A version's
own creator can never submit a review of it (database trigger
`prevent_self_review`, independent of whether they also hold
`guidelines.review`).

## Lifecycle Events (`guideline_lifecycle_events`)

Append-only history of every status transition a version has gone through:
`from_status`, `to_status`, `reason` (populated whenever the transition
required one), `actor_id`, `correlation_id`, `metadata`. Every row here is
paired with a general `audit_events` row carrying the same
`correlation_id` — this table is the guideline-registry-specific detail;
`audit_events` is the cross-cutting, organization-wide audit trail.

## What this task does not include

PDF/document upload, storage wiring, OCR, parsing, chunking, embeddings,
vector search, reranking, LLM generation, citation rendering, FHIR/EHR
integration, or patient data — all explicitly out of scope (see the Sprint
1 mission and `KNOWN_LIMITATIONS.md`).
