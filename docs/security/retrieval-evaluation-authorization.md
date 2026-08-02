# Retrieval Evaluation Authorization

Sprint 1-E1. Mirrors `docs/security/chunking-authorization.md` one layer
over, applied to an internal Quality-workspace feature rather than a
guideline-content pipeline.

## Two trust boundaries, never conflated

1. **Client-facing functions** (`create_retrieval_evaluation_dataset`,
   `add_evaluation_corpus_item`, `create_evaluation_query`,
   `create_relevance_judgment`, `freeze_retrieval_evaluation_dataset`,
   `create_retrieval_evaluation_run`, `create_failure_annotation`, etc.)
   — authenticated via `auth.uid()` and gated by
   `assert_permission(organization_id, 'retrieval_evaluation.*')`.
   Granted to `authenticated`, revoked from `anon`.
2. **Worker-only functions** (`get_retrieval_evaluation_job_context`,
   `get_retrieval_candidates`, `finalize_retrieval_evaluation_run`,
   `fail_retrieval_evaluation_run`) — authenticated via
   `assert_lease_owner()` against a claimed `document_processing_jobs`
   lease, **never** via organization permissions. Explicitly revoked
   from both `authenticated` and `anon`; only reachable via the
   `service_role` credential the Worker holds.

These two boundaries must never be mixed, for the same reason
documented in `docs/database/deterministic-chunking-schema.md`:
service_role's JWT carries no `sub` claim, so any permission-gated
function called from Worker code always fails `auth.uid() is not null`.

## Permission model

| Permission | Who (default role mapping) |
|---|---|
| `retrieval_evaluation.read` | organization_admin, quality_manager, clinical_reviewer, safety_officer, auditor |
| `retrieval_evaluation.create_dataset` | organization_admin, quality_manager |
| `retrieval_evaluation.edit_dataset` | quality_manager, clinical_reviewer |
| `retrieval_evaluation.review_dataset` | quality_manager, clinical_reviewer |
| `retrieval_evaluation.freeze_dataset` | quality_manager |
| `retrieval_evaluation.archive_dataset` | quality_manager |
| `retrieval_evaluation.run` | quality_manager |
| `retrieval_evaluation.cancel_run` | quality_manager |
| `retrieval_evaluation.read_results` | quality_manager, clinical_reviewer |
| `retrieval_evaluation.read_artifacts` | quality_manager |
| `retrieval_evaluation.annotate_failures` | quality_manager |

`clinician` holds none of these — retrieval evaluation is an internal
Quality-workspace concern with zero clinician-facing surface (it is
never exposed as a search endpoint; see ADR 0015's boundaries). Note
that `clinical_reviewer` can edit/review a draft dataset and read
results, but cannot freeze, archive, run, or annotate failures — those
require `quality_manager`, keeping the "who curated the content" role
distinct from "who controls when it becomes an official measurement."

## Two-person review, not just self-review avoidance

Unlike extraction/OCR/chunking's technical review (which blocks a
reviewer from reviewing their own uploaded/registered source document),
`freeze_retrieval_evaluation_dataset` blocks a dataset's own **creator**
from being its own **reviewer**
(`mark_evaluation_dataset_reviewed` rejects `v_actor = v_dataset.created_by`)
— enforced in SQL, not just as a UI convention, so it holds even if a
future client bypasses the Quality workspace UI and calls the RPC
directly.

## RLS

Every one of the 9 retrieval-evaluation tables (`retrieval_evaluation_datasets`,
`retrieval_evaluation_corpus_items`, `retrieval_evaluation_queries`,
`retrieval_relevance_judgments`, `retrieval_evaluation_search_documents`,
`retrieval_evaluation_runs`, `retrieval_evaluation_results`,
`retrieval_evaluation_metrics`, `retrieval_evaluation_failures`) carries
a single SELECT policy gated on `has_permission_in_organization`
(`retrieval_evaluation.read` for the first 5, `retrieval_evaluation.read_results`
for the last 4). All mutation happens through `security definer`
functions — there are no direct table-level INSERT/UPDATE/DELETE grants
for `authenticated`.

## Storage authorization

The `guideline-processed` Storage bucket's read policy is extended once
more to accept `retrieval_evaluation.read_artifacts` as an authorizing
permission for objects under a
`.../retrieval-evaluation/<dataset_id>/...` path — a reader with only
`guideline_chunking.read_artifacts`, for instance, cannot read an
evaluation artifact, and vice versa.

## No new secrets, no new external calls

This sprint introduces zero new credentials and zero new external
API/provider calls. Candidate recall runs entirely inside PostgreSQL
(`ts_rank_cd`/`websearch_to_tsquery`); scoring, tie-breaking, and every
metric run entirely in the Worker's own Python process on data already
fetched via the existing service_role RPC channel.
