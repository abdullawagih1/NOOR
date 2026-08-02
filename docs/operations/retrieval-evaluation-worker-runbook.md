# Retrieval Evaluation Worker Runbook

Sprint 1-E1. Mirrors `docs/operations/chunking-worker-runbook.md`'s
structure, applied to a dataset-scoped job rather than a document-scoped
one.

## Enabling the retrieval-evaluation processor

Set `WORKER_PROCESSING_MODE=retrieval_evaluation` and include
`retrieval_evaluation` in `WORKER_ENABLED_JOB_TYPES`. No new credential
is required beyond `SUPABASE_URL`/`SUPABASE_SERVICE_ROLE_KEY` —
candidate recall happens via PostgreSQL full-text search over
already-frozen data; nothing is downloaded or re-parsed.

Optional overrides (default to the pinned constants in
`apps/worker/app/retrieval/config.py` when unset):

- `RETRIEVAL_RETRIEVER_VERSION`
- `RETRIEVAL_CONFIGURATION_VERSION`

There is no metric-definition-version override — the metric formulas
(`apps/worker/app/retrieval/metrics.py`) are a fixed, in-repo constant;
changing their behavior is a code change and a version bump together,
never an environment-variable toggle.

## What one evaluation-run job does

1. Claim a `retrieval_evaluation` job
   (`claim_next_document_processing_job`) — this is the first job type
   in this codebase claimed by dataset rather than by document; the
   claim function's eligibility check requires the linked dataset to be
   `frozen`.
2. Read the run's pinned identity/config and every active query for the
   dataset via the Worker-only `get_retrieval_evaluation_job_context`
   RPC.
3. Read every relevance judgment for the dataset
   (`get_relevance_judgments` — a plain trusted table read; service_role
   bypasses RLS, and no mutation is involved so no dedicated RPC exists
   for it).
4. For each active query: fetch lexical candidates via the Worker-only
   `get_retrieval_candidates` RPC (real PostgreSQL FTS — `ts_rank_cd`
   against the frozen `retrieval_evaluation_search_documents` rows),
   then score, rank, and tie-break entirely in Python
   (`app/retrieval/scoring.py`, `app/retrieval/retriever.py`) — no
   further database round-trip per query beyond that one candidate
   fetch.
5. Compute every metric (`app/retrieval/metrics.py`) and run
   deterministic failure detection (`app/retrieval/failure_analysis.py`),
   both pure Python, no network/database access.
6. Build the canonical JSON artifact, upload it to the
   `guideline-processed` bucket (same "processed artifact" model as
   chunking, under a `retrieval-evaluation/<dataset_id>/...` path), and
   call `finalize_retrieval_evaluation_run` with every result, metric,
   and detected failure in one atomic call.
7. On any failure, call `fail_retrieval_evaluation_run` with a safe
   error code/message before letting the job fail.

## Failure modes and retry behavior

See `apps/worker/app/retrieval/errors.py` for the authoritative
retryable/non-retryable classification:

- **Non-retryable**: `evaluation_job_context_not_found` (the job/lease
  itself is missing — structural, not transient), `dataset_not_frozen`
  (the dataset was archived or otherwise changed status mid-flight).
- **Retryable**: `candidate_fetch_failed`, `artifact_serialization_failed`,
  `artifact_upload_failed`, `artifact_checksum_mismatch`,
  `database_finalization_failed`, `evaluation_internal_error`.

A `dataset_not_frozen` failure most commonly means the dataset was
archived between `create_retrieval_evaluation_run` being called and the
Worker claiming the job — this is expected under concurrent operator
action, not a bug; do not retry without re-checking the dataset's
status first.

## Observability

Every RPC call carries a `correlation_id`. `retrieval_evaluation_runs`
records `query_count`/`result_count`/artifact fields queryable directly
from the database. `record_audit_event` is called on every state
transition (`retrieval_evaluation_run.created`, `.succeeded`,
`.failed`, `.cancelled`), visible in the existing audit log.

## Determinism note for operators

Because scoring/ranking/metrics are pure Python taking already-fetched
candidate rows as plain data, this processor has **zero** external
network dependency beyond the Supabase REST endpoint itself — no
embedding-provider API, no reranker service, nothing that could
introduce non-determinism between two runs at the same identity. If two
runs at the identical identity ever produce different results, that is
a real bug (a non-deterministic sort, an unstable candidate-fetch
order, or a clock/locale dependency slipping into scoring) — see
`apps/worker/tests/test_retrieval_pipeline.py`'s byte-identical-artifact
test, which exists specifically to catch this class of regression.
