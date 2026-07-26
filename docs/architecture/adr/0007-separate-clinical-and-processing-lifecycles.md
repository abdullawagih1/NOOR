# ADR 0007: Separate clinical-publication and document-processing lifecycles

**Status:** Accepted
**Source:** Sprint 1 mission — Guideline Registry Schema and Lifecycle

## Decision

A guideline version's clinical publication state and its source document's
processing state are two distinct state machines, tracked in two distinct
places, and must never be merged into one status column or one table.

**Clinical publication lifecycle** (this task, `guideline_versions.lifecycle_status`):

```
draft → ready_for_review → approved → active → superseded → withdrawn
```

Governs whether Noor may present a version's content as active clinical
evidence. Owned by the Clinical Safety / Quality workflow: review, approval,
activation, supersession, withdrawal.

**Document-processing lifecycle** (a later Sprint 1 task, not implemented
here):

```
uploaded → queued → processing → processed → failed
```

Will govern whether a source PDF has been parsed, chunked, and embedded.
Owned by the ingestion pipeline: upload, OCR/parsing, chunking, embedding.

## Rationale

The two are correlated but not equivalent:

* A guideline version can be clinically `approved` only once whatever
  future content-verification requirements the processing pipeline defines
  are satisfied — but "processing succeeded" is never sufficient on its own
  to make something clinically `active`, and "clinically active" must never
  be inferred from "processing succeeded."
* Processing is a technical, retryable, file-level concern (a corrupted PDF
  fails into `parsing_failed`, gets re-uploaded, tried again) with no
  clinical-safety weight of its own. Publication is a clinical-governance
  concern (review, approval, revocation) that must never be reachable by a
  storage or parsing side effect.
* Conflating them into one column would let a purely technical event (e.g.
  "parsing finished") accidentally satisfy or bypass a clinical-safety gate,
  or would force clinical states to model file-processing mechanics they
  have nothing to do with.

## Consequences

* `guideline_versions` (this migration, `0005_guideline_registry_and_lifecycle.sql`)
  carries only `lifecycle_status` — the clinical publication state. It has
  no `processing_status` column.
* Nullable, future-facing metadata for a source file (e.g. a file reference)
  may exist on `guideline_versions` as inert metadata only; no processing
  workflow, upload UI, storage wiring, or status transitions for it are
  implemented in this task (see `KNOWN_LIMITATIONS.md`).
* When the document-processing pipeline is built (Sprint 1, follow-on task),
  it gets its own table (e.g. `document_processing_jobs`) and its own status
  column, referencing a `guideline_version_id` but never writing to
  `guideline_versions.lifecycle_status` directly. Any future rule that makes
  processing a *precondition* for review/approval must be enforced as an
  explicit check inside the clinical transition function
  (`transition_guideline_version`), not by merging the two state machines.
