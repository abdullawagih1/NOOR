# ADR 0016: Embedding and Vector Index Foundation

Status: Accepted
Sprint: S1-E2

## Context

Sprint 1-E1 built a frozen evaluation-dataset lifecycle, a deterministic
lexical baseline, versioned metrics, and provider-independent `Retriever`
contracts — but zero embeddings. This sprint implements the second
`Retriever`: a real vector-embedding pipeline, evaluated against the
exact same frozen datasets and metric definitions S1-E1 established, so
the comparison is apples-to-apples rather than a subjective "this looks
better" judgment call.

## Embedding-model evaluation and selection

A background research pass (grounded, cited, see the commit history for
the full comparison) evaluated three self-hosted MIT-licensed multilingual
candidates and one external managed API:

| Candidate | License | Dim | Max tokens | Arabic evidence | Footprint |
|---|---|---|---|---|---|
| `intfloat/multilingual-e5-small` | MIT | 384 | 512 | Weak — no isolated first-party Arabic number | Smallest |
| `intfloat/multilingual-e5-base` | MIT | 768 | 512 | **Strongest** — vendor model card publishes Mr. TyDi Arabic MRR@10 = 72.3 | Moderate |
| `BAAI/bge-m3` | MIT | 1024 | 8192 | Single non-vendor academic paper only (arXiv:2506.06339); no first-party Arabic number | Largest (2.27GB weights, sparse+ColBERT multi-output we don't need) |
| OpenAI `text-embedding-3-small` | Proprietary API | 1536 (reducible) | 8191 | No Arabic-specific number published — only an aggregate multilingual MIRACL score | N/A (external call) |

### Decision: `intfloat/multilingual-e5-base`, self-hosted

Selected because:

- **Best-documented Arabic evidence of any candidate** — a directly
  vendor-published Mr. TyDi Arabic MRR@10 score (72.3), not an inferred
  aggregate or a single third-party paper.
- **MIT license** — no commercial-use restriction, confirmed directly
  against the Hugging Face model API (`license:mit` tag), not just the
  README prose.
- **Single dense-vector output** — unlike `bge-m3`, which also emits
  sparse-lexical and ColBERT-style multi-vector representations we have
  no use for here (added complexity with no benefit for this sprint's
  scope).
- **8192-token capacity is irrelevant** for our short-paragraph chunks
  (Sprint 1-D3's chunks target ~400 tokens, hard-capped at 800) —
  `bge-m3`'s extra capacity is not a real advantage for this corpus.
- **No data ever leaves Noor's own infrastructure** — matching the same
  "self-hosted over external API" reasoning ADR 0012 already applied to
  OCR (Tesseract over a cloud OCR API).
- Matches the mission's own explicit preference: "prefer a self-hosted,
  pinned model when it can run reliably in the actual Worker environment
  ... licensing is compatible."

`multilingual-e5-small` was rejected specifically for weaker,
less-confirmed Arabic evidence despite its smaller footprint —
Arabic/mixed-language quality is a first-order requirement for a Gulf/
MENA clinical product, not a secondary one. `bge-m3` was rejected for
unneeded complexity and weaker (single-paper) Arabic citation strength
relative to its much larger resource cost. OpenAI's API was rejected as
the *default* configuration because it publishes no Arabic-specific
quality evidence at all, and because using it would require an
organization-level decision this sprint cannot make unilaterally
(signing a Data Processing Addendum, deciding whether Zero Data
Retention is worth the enterprise-sales engagement) — the
provider-independent `EmbeddingProvider` interface (below) means this
remains a contained future swap, not a rewrite, if self-hosted CPU
latency ever proves operationally unacceptable at real production scale.

### Environmental note: a real disk-space blocker, resolved with the user

Before writing any embedding code, a repository-environment check found
the development machine's `C:` drive at 476GB/476GB used (≈800MB free) —
installing PyTorch (CPU wheel, ~122MB) plus the model weights (~1.1GB fp32)
would very likely have failed or made the environment worse. Rather than
silently picking a different provider to dodge the problem, or silently
attempting risky disk operations (e.g. compacting Docker Desktop's WSL2
virtual disk) without asking, this was surfaced directly to the user with
the concrete tradeoff (self-hosted needs disk headroom; an external API
needs an API key and sends data out). The user freed disk space
themselves; the session confirmed ~19GB free before proceeding. This is
documented here as a real example of the "no silent workarounds" and
"ask when the blocker affects the user's own machine" discipline this
project's sessions have followed throughout.

## Model revision pinning

Exact revision confirmed live against the Hugging Face Hub API (not
assumed from the README), matching this codebase's existing
`assert_pinned_extractor_version()`/`assert_pinned_renderer_version()`/
`assert_pinned_provider_version()` pattern (`app/pdf_extraction/config.py`,
`app/ocr/config.py`):

```
EMBEDDING_MODEL_IDENTIFIER = "intfloat/multilingual-e5-base"
EMBEDDING_MODEL_REVISION   = "d128750597153bb5987e10b1c3493a34e5a4502a"
```

`assert_pinned_embedding_model()` (new, `app/embedding/config.py`) fails
closed at Worker startup if the locally-cached model snapshot's resolved
revision does not match this constant — the same "never whatever the
model host happens to serve today" discipline OCR's tessdata pinning
already established.

## Input contract: `query: ` / `passage: ` prefixes, exact chunk text otherwise

`multilingual-e5-base`'s own model card requires literal role prefixes on
every input, for every language including Arabic:

```
passage_input = "passage: " + <exact accepted chunk text, unmodified>
query_input   = "query: "   + <exact authored query text, unmodified>
```

No guideline title, page number, organization name, or synthetic heading
is ever prepended beyond this required prefix — the model does not
document needing more, and adding more would be an unversioned,
undocumented deviation from the input contract this ADR is trying to pin
down. `passage_input_template_version` / `query_input_template_version`
are both `"1"`; changing the prefix convention is a version bump, never
silent.

## Output normalization and distance metric

`multilingual-e5-base`'s own documentation recommends L2-normalizing
output embeddings and comparing with cosine similarity (equivalent to
inner product on normalized vectors). This ADR pins:

```
output_normalization = "l2_normalized"
distance_metric       = "cosine"
```

implemented via pgvector's `vector_cosine_ops` operator class end to end
(both the exact-search reference path and the one approved index
strategy) — never mixed with a different metric for one path only.

## Embedding dimension: fixed-column, not generic

`vector_value vector(768)` — a fixed-dimension column, not a generic
`vector` column with runtime dimension checks. This strongly enforces
the single approved configuration at the schema level (a row simply
cannot exist with the wrong dimension) and keeps the index design
trivial. Supporting multiple simultaneous dimensions is explicitly not a
goal this sprint — a future model swap is a new migration adding a new
column/table generation, not a schema that silently tolerates drift.

## Vector index strategy: HNSW

Evaluated against current pgvector/Supabase guidance: `HNSW` over
`IVFFlat` for this sprint's synthetic evaluation-scale corpora, because
HNSW requires no training step proportional to corpus size (IVFFlat's
list count must be tuned to row count, which is awkward for a corpus
that starts near-empty and grows per dataset), and HNSW's own recall/
latency tradeoff is controlled by two versioned, documented parameters
(`m`, `ef_construction`) plus a versioned search-time parameter
(`ef_search`) — all pinned under `vector_index_configuration_v1`
(migration 0017). The exact sequential-scan path (no index) remains the
permanent correctness reference every indexed result is validated
against (§36 of the mission) — HNSW is *never* trusted un-verified.

## Chunk-embedding identity vs. query-embedding identity

Two distinct identity tuples (mirroring chunking's own execution-identity
discipline, ADR 0014), both SHA-256 hashed:

- **Chunk embedding**: `organization_id + chunk_id + chunk_checksum +
  chunking_run_id + input_text_checksum + passage_input_template_version
  + provider_name + provider_version + model_identifier + model_revision
  + embedding_dimension + output_normalization + distance_metric +
  embedding_configuration_version`.
- **Query embedding**: `organization_id + evaluation_dataset_id +
  dataset_sha256 + query_id + query_checksum + query_input_template_version
  + <same provider/model/dimension/normalization/metric/configuration
  fields>`.

A changed chunk checksum, model revision, input template, or dimension
always produces a new identity — never a silent reuse of a
now-semantically-different vector.

## Durable job granularity: one job per (chunking run, embedding configuration)

Matching chunking's own document-scoped granularity one layer over: one
`document_embedding` job embeds every currently-eligible chunk from one
accepted chunking run under one approved configuration, with per-chunk
progress rows enabling safe partial-resume after a retry — never one
durable database job per individual vector (unnecessary orchestration
overhead at this corpus scale) and never a whole-organization job
(violates the same "one document, one job" scoping every prior pipeline
stage in this codebase uses).

## Query-embedding generation: its own controlled path, not folded into the vector-evaluation job

Query embeddings for a frozen dataset are generated by a dedicated
client-facing function (`create_query_embeddings_for_dataset`, migration
0017) called once per (dataset, configuration) — not implicitly inside
`create_vector_evaluation_run`. This mirrors chunk embeddings' own
"generate once, evaluate many times" shape: the same frozen dataset's
query embeddings are reused across every vector evaluation run at that
configuration, rather than regenerated (and re-billed, if this were ever
swapped to an external provider) on every run.

## Boundaries (unchanged discipline from every prior sprint)

No hybrid retrieval, no reciprocal-rank fusion, no reranking, no
cross-encoders, no LLM calls, no query rewriting/expansion, no
generative answer, no clinician-facing search, no production exposure of
any kind. The vector baseline is evaluated honestly against the S1-E1
lexical baseline using identical frozen datasets and metric definitions
— a regression in some category is reported, never hidden, and the
vector model is never declared "better" from an overall average alone.
