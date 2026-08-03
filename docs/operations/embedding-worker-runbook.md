# Embedding Worker Runbook

Sprint 1-E2. Mirrors `docs/operations/retrieval-evaluation-worker-runbook.md`'s
structure, applied to the two new job types this sprint adds.

## A real dependency-footprint change

Every prior Worker feature (extraction, OCR, chunking, lexical
retrieval evaluation) added zero or trivially small dependencies. This
sprint adds `torch` (CPU-only wheel, ~122MB) and `sentence-transformers`
(~1.1GB model weights downloaded once, cached locally) — a genuine,
deliberate departure from this Worker's historically minimal footprint,
documented here rather than left implicit. See ADR 0016 for the
provider-selection reasoning and the disk-space constraint that was
resolved before this work began.

Install with the CPU-only PyTorch index (already encoded in
`apps/worker/requirements.txt`'s `--extra-index-url` line — a plain
`pip install -r requirements.txt` picks it up automatically):

```bash
pip install -r requirements.txt
```

The model itself (`intfloat/multilingual-e5-base`, revision
`d128750597153bb5987e10b1c3493a34e5a4502a`) downloads from the Hugging
Face Hub on first use and is cached under the Hugging Face cache
directory (`~/.cache/huggingface` by default) — subsequent starts do not
re-download it. There is no `fetch_tessdata_models.py`-style pre-fetch
script this sprint; the model snapshot is fetched lazily by
`sentence-transformers` itself, checksum-pinned by revision rather than
a separate manual SHA-256 verification step (Hugging Face's own
revision-pinning already guarantees byte-identical weights for a given
commit SHA).

## Enabling the chunk-embedding processor

Set `WORKER_PROCESSING_MODE=document_embedding` and include
`document_embedding` in `WORKER_ENABLED_JOB_TYPES`. Requires
`SUPABASE_URL`/`SUPABASE_SERVICE_ROLE_KEY` as usual — no additional
credential, since the provider is fully self-hosted.

## Enabling the query-embedding processor

Set `WORKER_PROCESSING_MODE=query_embedding_generation` and include
`query_embedding_generation` in `WORKER_ENABLED_JOB_TYPES`. Typically run
as a separate Worker instance/mode from `document_embedding`, matching
this codebase's "one mode per deployed Worker process" convention — see
`app/main.py`'s `lifespan()` dispatch.

## What one `document_embedding` job does

1. Claim the job (`claim_next_document_processing_job`).
2. Read every embedding-ready chunk plus the approved configuration via
   the Worker-only `get_document_embedding_job_context` RPC (this
   function re-derives embedding-readiness itself rather than calling
   the permission-gated `get_document_embedding_readiness` — the same
   "Worker-only functions never call permission-gated functions"
   discipline this codebase has already had to fix twice before, see
   `docs/database/embedding-and-vector-schema.md`).
3. For each chunk: compute the input checksum and token count with the
   model's own tokenizer, and fail closed
   (`embedding_input_exceeds_model_limit`) — never truncate — if it
   exceeds 512 tokens.
4. Build the deterministic chunk manifest and its checksum, then create
   (or idempotently reuse) the `document_embedding_runs` row via the
   Worker-only `create_document_embedding_run` RPC.
5. Batch the pending chunks (`EMBEDDING_MAX_BATCH_ITEMS = 16` per
   provider call) and embed them, mapping results back by the chunk's
   own stable key — never assumed response order.
6. Validate each vector (dimension, finiteness, non-zero norm), compute
   its checksum, and persist it via the Worker-only, per-chunk,
   idempotent `record_document_chunk_embedding` RPC — a retry after a
   partial batch failure only re-embeds chunks that don't already have
   a succeeded row.
7. Build and upload the canonical embedding artifact (checksums and
   metadata only — never full vector arrays) to the `guideline-processed`
   bucket, independently re-downloaded and re-hashed before trusting the
   upload succeeded (the same discipline `app/pdf_extraction/artifact_storage.py`
   already established).
8. Finalize the run (`finalize_document_embedding_run`) — this
   re-verifies 100% chunk coverage before marking the run succeeded; a
   partial run can never silently succeed.

## What one `query_embedding_generation` job does

1. Claim the job, read every active query in the (already-frozen)
   dataset via `get_query_embedding_job_context`.
2. Reject any oversize query the same way (`embedding_input_exceeds_model_limit`).
3. Embed with the `"query: "` prefix (never the `"passage: "` one used
   for chunks — the model treats these as distinct input modes).
4. Persist each via `record_query_embedding`, then complete the job
   directly via the existing (migration 0007) Worker-only
   `complete_document_processing_job` — there is no dedicated
   `finalize_query_embedding_*` function, since completion is fully
   determined by every active query now having a succeeded
   `retrieval_evaluation_query_embeddings` row.

## Failure handling

Every failure path raises a typed `EmbeddingError`
(`app/embedding/errors.py`) with an explicit `retryable` classification
— e.g. `embedding_provider_unavailable`/`embedding_provider_timeout` are
retryable, `embedding_input_exceeds_model_limit`/
`embedding_configuration_not_approved` are not. A lease lost mid-batch
is never reported through `fail_document_embedding_run` — the durable
orchestration layer (migration 0007) reclaims it exactly like every
other job type.

## Verifying a real model run locally

`apps/worker/tests/test_embedding_provider_real_model.py` actually loads
and runs the pinned model (skipped cleanly, not failed, if
torch/sentence-transformers isn't installed or the model snapshot isn't
already cached — mirrors `test_ocr_renderer_and_provider.py`'s
`requires_ocr_engine` precedent). Run it directly to confirm a real
model executes correctly in your environment:

```bash
pytest apps/worker/tests/test_embedding_provider_real_model.py -v
```

The first run downloads the model (~1.1GB); subsequent runs use the
local cache and complete in well under two minutes.
