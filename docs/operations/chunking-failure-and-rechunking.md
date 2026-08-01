# Chunking Failure Recovery and Rechunking

Sprint 1-D3. Mirrors `docs/operations/ocr-failure-recovery.md`'s
structure one layer deeper.

## When a chunking run fails

`fail_document_chunking_run` marks the run `failed` and the underlying
job retry-eligible (via the generic `fail_document_processing_job`,
migration 0007). A retried job attempt claims a fresh lease and calls
`create_document_chunking_run` again — since the run's identity depends
on the input manifest, source checksum, and pinned versions (all
unchanged unless something upstream changed), a retry after a purely
transient failure (upload error, network blip) will naturally attempt
the *same* identity and succeed cleanly. Nothing about a prior failed
attempt blocks this — failed runs do not appear in the partial unique
index (`where status = 'succeeded'`).

## When a chunk review round rejects or requires a rechunk

`rechunk_required` and `rejected` are terminal review decisions that
leave the underlying `document_chunking_runs` row **untouched** — the
run stays `succeeded`, since it did produce a coverage-complete,
non-duplicated set of chunks; the review round is what says those
chunks are not good enough. To actually get different chunks:

1. A quality/admin role can request a **new chunking run** with a
   deliberately different identity — in practice this means a
   `CHUNKING_CONFIGURATION_VERSION` bump (e.g. adjusting
   `TARGET_CHUNK_TOKENS`/`HARD_MAXIMUM_CHUNK_TOKENS` or a segmentation
   heuristic), since the same input manifest and versions would just
   reuse the existing (rejected) run's identity.
2. `create_document_chunking_job` is called again; the Worker builds a
   fresh run under the new configuration identity, which does not
   collide with the old one in the partial unique index.
3. A new chunk technical review is opened against the new run.

There is deliberately no automated "rechunk" trigger in V1 — a
`rechunk_required`/`rejected` decision is a signal for a human to decide
what configuration change is warranted, not something the system
retries blindly (unlike a transient pipeline failure).

## Invalidating a succeeded run directly

`invalidate_document_chunking_run` (permission:
`guideline_chunking.invalidate`) lets a quality/admin role directly mark
a `succeeded`/`reused` run `invalidated` with a reason — for example, if
a downstream problem is discovered that the review process itself did
not catch. This is the same direct-invalidation escape hatch
`invalidate_ocr_review` provides one layer up, applied to the run
itself rather than only the review.

## The upstream cascade

If the extraction review a chunking run depends on is reopened or
invalidated, the dependent chunking run is **automatically** invalidated
(migration 0013's extension of `reopen_extraction_review`/
`invalidate_extraction_review`) — an operator does not need to remember
to do this manually. `get_document_embedding_readiness` reflects this
immediately (`eligible_for_embedding: false`, since it re-checks live
upstream eligibility on every call, not a stored flag). Historical rows
are never deleted — only their `status` transitions to `invalidated`
with a recorded reason.

## Diagnosing a stuck chunking job

Same generic tooling as every other job type in this codebase: query
`document_processing_jobs` for `job_type = 'document_chunking'` and
inspect `status`/`lease_expires_at`/`attempt_count`.
`recover_expired_document_processing_jobs()` (migration 0007, unchanged)
reclaims a lease-expired job automatically on the next Worker poll cycle
— no chunking-specific recovery logic exists or is needed, since
chunking reuses the fully generic orchestration layer with zero
modifications.
