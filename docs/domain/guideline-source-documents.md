# Guideline Source Documents — Domain Model

Source: `supabase/migrations/0006_secure_guideline_document_intake.sql`.
Companion doc: `docs/domain/document-intake-lifecycle.md` (state machines),
ADR 0008 (why intake and processing are separate concerns from the clinical
publication lifecycle).

## Entity hierarchy

```
Guideline Version
  └── Guideline Source Document (exactly one primary_guideline at a time)
        └── Upload Session (authorizes one upload attempt)
        └── Processing Job (queued only in this sprint — see ADR 0008)
              └── Processing Attempt (foundation only, stays empty)
        └── Intake Event (append-only history of everything above)
```

## Guideline Source Documents (`guideline_source_documents`)

The record of a file associated with a guideline version. `document_role`
is one of `primary_guideline`, `appendix`, `supplement`, `correction`,
`supporting_material` — this sprint only ever produces `primary_guideline`
rows (the other four are reserved schema headroom, not yet reachable via
any function). Exactly one non-rejected, non-quarantined `primary_guideline`
document may exist per guideline version at a time — a database guarantee
(`guideline_source_documents_one_primary_per_version`, a partial unique
index), not an application check.

`status` collapses what the Sprint 1.1 mission's field list called
"registration_status" and "verification_status" into one column
(`pending_upload → uploaded → verified → registered`, with `rejected` /
`quarantined` as failures) — see ADR 0008 for why a single column, not two.

**File identity is immutable once verified or registered.** A trigger
(`prevent_verified_source_document_mutation`) blocks any change to
`sha256`, `storage_path`, `storage_bucket`, or `detected_media_type` once
`status` is `verified` or `registered`, for every role — not just
`authenticated`. Correcting a source document after that point means
creating a new guideline version, never editing the existing one.

## Eligibility — which guideline versions may receive a new source document

| `guideline_versions.lifecycle_status` | New primary upload allowed? |
|---|---|
| `draft` | Yes |
| `ready_for_review` | Yes |
| `approved` | Yes, only if no non-rejected primary already exists |
| `active` | **No** — released, immutable; references its existing source |
| `superseded` | **No** |
| `withdrawn` | **No** |

A version that already has a non-rejected/non-quarantined primary document
also cannot receive a second one, regardless of lifecycle status — the
combination of "eligible lifecycle status" AND "no existing active primary"
is what `create_guideline_upload_session()` checks. If a released version
needs different source content, the answer is always a new guideline
version, never replacing the existing document.

## Duplicate policy (SHA-256 based)

| Scope | Behavior |
|---|---|
| Same guideline version | Structurally can't occur in normal use (a version can only ever have one active primary at a time — see above); `complete_guideline_upload()` still checks and rejects it as defense in depth |
| Different version, same organization | **Allowed** — a new guideline version legitimately re-registering the same source file is a real scenario. Explicitly recorded (`guideline_document.duplicate_detected` event + audit event), never blocked |
| Different organization | Structurally invisible — every duplicate query is scoped to the caller's own `organization_id`, so no query can ever observe another organization's checksum. No special-case code is needed; this is a property of correct tenant scoping, not an extra check |

## Upload Sessions (`document_upload_sessions`)

Authorizes exactly one upload attempt to one server-generated path. See
`docs/domain/document-intake-lifecycle.md` for the full state machine.
Session state and document state are related but deliberately not the same
column (ADR 0008) — a session being `completed` means the authorization
was consumed; the document's own `status` is what says whether the result
was actually trustworthy.

## Processing Jobs (`document_processing_jobs`) and Attempts

A `document_processing_jobs` row is created — status `queued` — the moment
a document is successfully verified and registered, with
`job_type = 'document_parsing'` (reusing the Worker's existing
`JobOperation` name from `apps/worker/app/main.py`, not inventing a new
one — see ADR 0008). **No claiming or execution happens in this sprint** —
that is Sprint 1.2 (S1-C, `MASTER_BACKLOG.md`). At most one job per
document+type may be `queued`/`claimed`/`processing` simultaneously (a
partial unique index). `document_processing_attempts` exists as schema
foundation for future retry/recovery semantics and stays empty this sprint.

## Intake Events (`document_intake_events`)

Append-only history of every intake action, integrated with the
cross-cutting `audit_events` table (every event here has a matching
`audit_events` row carrying the same `correlation_id`). Enforced append-only
for every runtime role via the same REVOKE + trigger + documented
`noor.allow_audit_maintenance` override pattern already established for
`audit_events` (0002) and `guideline_lifecycle_events` (0005) — the exact
same trigger function is reused, not redefined a third time.

## What this task does not include

PDF text extraction, OCR, page rendering, table/section extraction,
chunking, embeddings, pgvector indexing, retrieval, reranking, LLM calls,
answer generation, citation extraction, malware scanning beyond PDF
signature validation, or real clinical documents. See
`KNOWN_LIMITATIONS.md`.
