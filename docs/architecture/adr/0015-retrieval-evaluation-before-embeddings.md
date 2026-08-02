# ADR 0015: Retrieval Evaluation Before Embedding Selection

Status: Accepted
Sprint: S1-E1

## Context

Sprint 1-D3 produced `eligible_for_embedding` chunks with exact
provenance, but nothing in this codebase yet proves what "good
retrieval" means for Noor's actual content (Arabic/English/mixed-
language clinical-guideline-shaped text). The mission's governing
principle: NOOR must not select an embedding model, vector index,
fusion strategy, or reranker without a reproducible evaluation
foundation first. The sequence is corpus → queries → judgments →
lexical baseline → metrics → failure analysis → *then* embedding
comparison — never the reverse ("choose popular embedding model → create
vectors → assume retrieval is good").

This sprint builds that foundation and stops at a deterministic lexical
baseline. It adds zero embeddings, zero vector storage, zero external AI
calls, and zero production search exposure.

## Why the first baseline is lexical, not an embedding model

A lexical baseline requires no provider selection, no API key, no
data-residency review, and no model-quality assumption — it is
computable entirely from already-accepted chunk text using only
PostgreSQL's built-in full-text search. Every future embedding/hybrid/
reranking approach can be measured against the *same* frozen datasets
and metric definitions this sprint establishes, giving a real
comparison baseline instead of a subjective "this looks better" judgment
call when Sprint 1-E2 eventually selects an embedding provider.

## Worker architecture constraint: no direct Postgres driver

Every existing Worker feature (extraction, OCR, chunking) talks to
Postgres exclusively through PostgREST RPC calls via `httpx`
(`OrchestrationClient`) — there is no `psycopg2`/`asyncpg` dependency,
no `libpq-dev` in the Docker image, confirmed by inspection. Introducing
a direct DB driver just for retrieval evaluation would be a real,
avoidable architecture change. Instead:

- **Candidate recall** (which corpus items even match a query) uses a
  Worker-only RPC (`get_retrieval_candidates`) that runs the actual
  PostgreSQL full-text search (`tsvector`/`websearch_to_tsquery`,
  `simple` configuration — built into core Postgres, no new extension)
  and returns each candidate's `ts_rank_cd` value as one score input.
- **Final scoring, tie-breaking, and every metric** are pure Python
  (`apps/worker/app/retrieval/*`), taking already-fetched candidate rows
  as plain data. This is also why the `Retriever` Protocol's
  `LexicalRetriever` implementation accepts an injected candidate-fetch
  dependency rather than hard-coding an httpx call: unit tests inject a
  fake in-memory fetcher, so the entire scoring/tie-break/metrics
  pipeline is testable with zero network or database access — matching
  CI's `Worker` job, which has no Postgres service at all (only the
  separate `Supabase` job does).

## `simple` text-search configuration, not `english`/`arabic`

PostgreSQL ships no built-in Arabic text-search configuration, and the
`english` configuration's stemming would silently favor English content
and make cross-language metric comparison unfair. `simple` (tokenize +
lowercase, no stemming, no stop-word removal) is used for both
languages identically — this is a real capability limitation
(no stemming, no root-based Arabic matching), documented honestly in
`docs/domain/retrieval-metrics.md` and `KNOWN_LIMITATIONS.md`, not hidden
behind an unqualified "full-text search" claim.

## Deterministic normalization lives in exactly one place: SQL

`retrieval_text_normalization_v1` is a **separate, additional**
normalization layer from chunking's own `normalization_version` (NFC
only) — it never mutates canonical chunk text, only a retrieval-specific
representation. Rules: NFC, Latin case-folding, whitespace collapse,
Arabic tatweel (U+0640) removal, Arabic diacritics (harakat,
U+064B–U+0652, U+0670) removal, Arabic-Indic numeral → ASCII digit
mapping, and punctuation-to-whitespace separation for consistent
tokenization.

Query authoring is a client-facing (web app) operation; dataset freezing
is a database-consistency operation (see below) — neither is Worker-
driven. Rather than implementing these rules twice (once for queries in
SQL, once for documents in Python, risking silent drift between the two
that would make matching systematically broken), normalization is
implemented **exactly once**, as a single SQL function
(`normalize_retrieval_text()`, migration 0014), called by both
`create_evaluation_query`/`update_evaluation_query` (computes and stores
`normalized_query_text`) and the freeze operation (computes and stores
each corpus item's `normalized_search_text`). The Worker never
re-normalizes anything — it only ever reads these two already-normalized
columns back from the database. Its own `app/retrieval/` module
(`tokenizer.py`, `scoring.py`, `metrics.py`) operates purely on strings
it is handed, with no Unicode-normalization rules of its own to keep in
sync. Every SQL normalization rule is tested against real Arabic,
English, mixed, and numeral fixtures in the local RLS suite.

## Ranking formula: versioned, explicit, not "relevance probability"

```
final_score = w_full_text * full_text_rank
             + w_coverage * token_coverage
             + (exact_phrase_bonus if exact_phrase_match else 0)
```

`retrieval_configuration_version = "1"` pins `w_full_text`, `w_coverage`,
and `exact_phrase_bonus` as explicit, tested constants
(`apps/worker/app/retrieval/config.py`). `full_text_rank` comes from
Postgres `ts_rank_cd`; `token_coverage` is the fraction of normalized
query tokens present in the normalized document text (pure Python);
`exact_phrase_match` is a literal substring check on normalized text.
Never called "relevance probability" anywhere in code, UI, or docs — it
is a technical lexical-overlap score.

## Deterministic tie-breaking, never insertion order

Ties break on: score descending → matched-token count descending →
corpus display order ascending → chunk checksum ascending. Never
database row-insertion order, which Postgres does not guarantee stable
across query plans.

## Dataset freeze computed in SQL, not by the Worker

Unlike chunking's input manifest (Worker-computed, because it depends on
external file rendering/parsing), dataset freezing
(`freeze_retrieval_evaluation_dataset`) is a pure database-consistency
operation over already-stored rows (corpus items, queries, judgments) —
no external file, no rendering, no parsing. It is implemented entirely
in SQL, using `pgcrypto`'s `digest()` (already installed since
migration 0001) for checksums. This is safe and genuinely deterministic
because PostgreSQL's `jsonb` type canonicalizes object key order on
storage — `jsonb_value::text` is guaranteed stable regardless of
insertion order — while `jsonb_agg(... order by <stable column>)`
preserves the specified *array* order (arrays are never reordered, only
object keys are canonicalized). Manifests are built as
`jsonb_agg(jsonb_build_object(...) order by display_order, id)`, so
identical dataset content always produces identical checksums.

## Document-scoped orchestration extended for dataset-scoped jobs

`document_processing_jobs.source_document_id` has been `not null` since
migration 0006 — every existing job type (parsing, OCR, chunking) is
scoped to exactly one document. A `retrieval_evaluation` job is scoped
to a *dataset*, which spans arbitrarily many documents/chunks. Rather
than inventing a parallel orchestration table (explicitly forbidden by
this sprint's mission), migration 0015 makes `source_document_id`
nullable, adds a nullable `dataset_id` column, and adds a check
constraint requiring exactly one of the two to be set based on
`job_type` — the existing claim/lease/heartbeat/retry/dead-letter
machinery (migration 0007) needs zero changes.

## Storage bucket: `guideline-processed`, not `evaluation-assets`

`evaluation-assets` is a bucket provisioned in migration 0003 but never
used by any feature to date — no code, no RLS customization. The
`guideline-processed` bucket is the established "processed artifact"
convention (extraction, OCR, and chunking artifacts all live there,
each under their own path segment) — reused here for consistency rather
than introducing a second artifact bucket with its own policy surface
for no functional benefit. `evaluation-assets` remains unclaimed; a
future sprint may still adopt it if a genuinely different artifact
shape warrants a separate bucket.

## Fewer tables than suggested: no dedicated dataset-events table

The mission's own suggested schema lists a `retrieval_evaluation_dataset
_events` table (§29.10) but explicitly permits "use the existing domain-
event system where possible instead of creating an unnecessary parallel
table." Precedent confirms this is genuinely optional: migrations 0007,
0008, and 0011 (durable orchestration, extraction, OCR) never added a
dedicated events table, relying solely on the generic, universal
`record_audit_event()` call every mutating function in this codebase
already makes. This sprint follows that majority precedent — every
dataset/run/judgment mutation calls `record_audit_event()`, and no new
dedicated events table exists. Revisit only if the Quality UI later
needs a richer typed timeline view than `audit_events.metadata jsonb`
conveniently provides.

## Two-person dataset review, matching established self-review blocks

`freeze_retrieval_evaluation_dataset` requires `reviewed_by` to be set
and to differ from `created_by` — a new `mark_evaluation_dataset_reviewed`
function records that confirmation. This mirrors the self-review blocks
already established for extraction/OCR/chunking technical review (a
reviewer cannot be the same person who introduced the content being
reviewed), applied here to dataset authorship vs. freeze-readiness
review, rather than falling back to "document as a limitation" where a
real, cheap enforcement was available.

## Boundaries (unchanged from every prior sprint's own discipline)

- **Embedding boundary**: no embedding computation, no embedding-provider
  selection, no vector column, no pgvector extension anywhere in this
  sprint.
- **Retrieval-production boundary**: this retrieval is an internal
  evaluation baseline only — never exposed as a clinician-facing search
  endpoint, never used for clinical decision support.
- **Reranking/LLM/RAG boundary**: none exist after this sprint. No
  cross-encoder, no reciprocal-rank fusion, no query rewriting, no LLM
  call, no generated answer, no citation generation.
- **Synthetic-content boundary**: every corpus/query fixture is
  synthetic, clearly labeled "Synthetic evaluation content — not for
  clinical use," never real patient data or real clinical documents.
