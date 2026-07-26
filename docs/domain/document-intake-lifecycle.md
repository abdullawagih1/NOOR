# Document Intake — State Machines and Permission Matrix

Source: `supabase/migrations/0006_secure_guideline_document_intake.sql`.
See ADR 0008 for why three state machines (clinical publication, upload
session, processing job) — plus a fourth, document-status track — are kept
separate rather than merged.

## Upload session lifecycle (`document_upload_sessions.status`)

```
created → authorized → completed
                     → expired
                     → rejected
                     → cancelled
```

Simplified from the mission's suggested 8-state list — `uploaded` and
`verified` are tracked on the *document* instead of the session (see
`guideline-source-documents.md`). In this implementation, `created` and
`authorized` happen in the same database call
(`create_guideline_upload_session`), so a session is always observed
already `authorized`.

| Transition | Trigger | Enforcement |
|---|---|---|
| `authorized → completed` | `complete_guideline_upload()` succeeds (document accepted) | Function-internal; session locked `FOR UPDATE` |
| `authorized → rejected` | `complete_guideline_upload()` runs but the document fails verification/duplicate check | Same function |
| `authorized → expired` | `complete_guideline_upload()` is called after `expires_at` (30 minutes) | Same function, checked first |
| `created/authorized → cancelled` | `cancel_upload_session()`, caller-initiated | Only reachable from `created`/`authorized`; any other status raises |

Replaying `complete_guideline_upload()` against an already-terminal session
(`completed`/`rejected`/`expired`/`cancelled`) returns the existing outcome
idempotently rather than re-processing — verified in
`supabase/tests/rls/005_document_intake.sql` TEST 7.

## Document status (`guideline_source_documents.status`)

```
pending_upload → uploaded → verified → registered
                                     ↘ rejected
                          ↘ quarantined (from verified/registered, manual QA override)
```

In this implementation, `uploaded`/`verified`/`registered` collapse to a
single atomic transition inside `complete_guideline_upload()` — there is no
observable gap where a document sits at `uploaded` or `verified` without
also being `registered`, because registration is not a separate manual
clinical decision in this slice (see "Registration is automatic" below).
`quarantined` is the one status reachable independently, via
`quarantine_guideline_source_document()` — a manual QA override, gated by
`guideline_documents.reject`.

## Processing job status (`document_processing_jobs.status`)

```
queued → claimed → processing → succeeded
                              ↘ failed
      ↘ cancelled                ↘ dead_lettered
```

**This sprint only ever produces `queued`.** `claimed`/`processing`/
`succeeded`/`failed`/`dead_lettered` are schema foundation for Sprint 1.2
(S1-C, `MASTER_BACKLOG.md`) — no code in this migration transitions a job
into any of those states. `cancel_processing_job()` moves `queued →
cancelled`; any other current status is rejected. Quarantining a document
also cascades: any of its `queued`/`claimed`/`processing` jobs are
cancelled automatically.

## Registration is automatic, not a separate manual gate

The Sprint 1.1 mission listed `guideline_documents.register` as a
permission and `registered_by`/`registered_at` as document fields, but its
own suggested operation list (§24) has no separate "register" function —
only `completeGuidelineUpload`. This implementation follows that: once the
Next.js server independently verifies a file (existence, size, PDF
signature, checksum — see ADR 0008), `complete_guideline_upload()`
verifies AND registers it in the same call, gated by
`guideline_documents.upload` alone. `guideline_documents.register` is
still seeded and mapped to the same roles as `upload` (organization_admin,
knowledge_manager) — reserved for if registration is ever split into its
own manual step later — but nothing currently checks it independently.
Likewise `guideline_documents.verify` is seeded and mapped to
`quality_manager` but reserved for a future manual re-verification
workflow; the only function `quality_manager` can currently act on a
registered document with is `quarantine_guideline_source_document()`
(gated by `guideline_documents.reject`).

## Permission matrix

| Permission | Grants ability to | Roles |
|---|---|---|
| `guideline_documents.read` | Read source documents and upload sessions | `knowledge_manager`, `organization_admin`, `clinical_reviewer`, `quality_manager`, `safety_officer`, `auditor` |
| `guideline_documents.upload` | Create upload sessions; complete uploads (verify + register + queue job) | `knowledge_manager`, `organization_admin` |
| `guideline_documents.verify` | Reserved — no function checks this independently yet | `quality_manager` |
| `guideline_documents.reject` | Quarantine a registered document (cascades job cancellation) | `quality_manager`, `safety_officer` |
| `guideline_documents.register` | Reserved — registration is automatic within `upload` today | `knowledge_manager`, `organization_admin` |
| `guideline_processing_jobs.read` | Read job status | `knowledge_manager`, `organization_admin`, `clinical_reviewer`, `quality_manager`, `safety_officer`, `auditor` |
| `guideline_processing_jobs.create` | Reserved — job creation is automatic within `upload` today | `knowledge_manager`, `organization_admin` |
| `guideline_processing_jobs.cancel` | Cancel a queued job | `quality_manager` |

**Clinicians hold none of these permissions** (mission §19) — they never
receive a private Storage path, and RLS structurally returns zero rows for
every one of the five new tables to a clinician session, regardless of UI.
`safety_officer` additionally received `guideline_documents.reject`
(quarantine) beyond the mission's literal suggested table, consistent with
the same "can contain a discovered problem" extension migration 0005 gave
it for `guidelines.withdraw`.

## Read visibility

All five new tables are RLS-gated purely by `guideline_documents.read` /
`guideline_processing_jobs.read` — there is no separate "own upload only"
restriction; any org member with read access sees all of their
organization's intake activity. Reviewers hold read access so they can see
what source document backs a version they're reviewing, without being able
to act on it.
