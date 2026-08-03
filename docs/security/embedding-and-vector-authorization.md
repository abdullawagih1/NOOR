# Embedding and Vector Authorization

Sprint 1-E2. Mirrors `docs/security/retrieval-evaluation-authorization.md`
one layer over.

## Two trust boundaries, never conflated

1. **Client-facing functions** (`get_approved_embedding_configuration`,
   `create_document_embedding_job`, `cancel_document_embedding_run`,
   `create_query_embeddings_for_dataset`, `create_vector_evaluation_run`)
   — authenticated via `auth.uid()`, gated by
   `assert_permission(organization_id, '<permission>')`. Granted to
   `authenticated`, revoked from `anon`.
2. **Worker-only functions** (`get_document_embedding_job_context`,
   `create_document_embedding_run`, `record_document_chunk_embedding`,
   `finalize_document_embedding_run`, `fail_document_embedding_run`,
   `get_query_embedding_job_context`, `record_query_embedding`,
   `get_vector_search_candidates`) — authenticated via
   `assert_lease_owner()` against a claimed `document_processing_jobs`
   lease, **never** via organization permissions. Explicitly revoked
   from both `authenticated` and `anon`, guarded against hosted
   Supabase's default-privilege behavior the same way every prior
   Worker-only function in this codebase already is (migration 0007's
   documented `alter default privileges` fact).

## Permission model

| Permission | Who (default role mapping) |
|---|---|
| `embedding_configurations.read` | organization_admin, quality_manager, safety_officer, auditor |
| `document_embeddings.read` | organization_admin, quality_manager, safety_officer, auditor |
| `document_embeddings.create` | quality_manager |
| `document_embeddings.cancel` | quality_manager |
| `document_embeddings.read_artifacts` | quality_manager |

No clinician mapping exists for any of these five keys — clinicians
never see raw vectors, embedding artifacts, or embedding-run internals
(a hard requirement, not an oversight). Vector-evaluation runs reuse
S1-E1's existing `retrieval_evaluation.run`/`.cancel_run`/
`.read_results`/`.read_artifacts` permissions unchanged — no new
permission was needed for the vector retriever itself, since the run it
produces lives in the exact same table gated the exact same way.

## Vectors never reach the browser

`document_chunk_embeddings.vector_value` and
`retrieval_evaluation_query_embeddings.vector_value` are never selected
by any web-application query (`apps/web/lib/embeddings/queries.ts`,
`apps/web/lib/retrieval-evaluation/queries.ts`) — only checksums,
norms, dimensions, and status are read. RLS additionally permits only
`SELECT`, and every mutating path is a `security definer` function, so
even a client with `document_embeddings.read` could not write a raw
vector through PostgREST directly.

## No client-supplied vectors, ever

The browser can never submit a chunk vector, a query vector, a
dimension, a similarity expression, a distance metric, an index
parameter, a provider model name, or provider credentials. Every vector
passed into `record_document_chunk_embedding`/`record_query_embedding`
originates from the Worker's own `EmbeddingProvider.embed()` call
(`service_role`-authenticated, `assert_lease_owner`-gated) — there is no
code path from an `authenticated` JWT to either function.

## Provider secrets

`SentenceTransformerProvider` (ADR 0016) is fully self-hosted — there is
no provider API key, bearer token, or credential of any kind to leak, by
construction. The model weights themselves are a public Hugging Face
Hub download (MIT-licensed, revision-pinned), not a secret. If a future
sprint adds an external API provider, its credentials must follow the
same Worker-only, environment-managed, never-logged discipline this
codebase already applies to Supabase's own `SUPABASE_SERVICE_ROLE_KEY`
and `WORKER_INTERNAL_TOKEN`.

## Cross-tenant isolation

`get_vector_search_candidates` restricts candidates to
`retrieval_evaluation_corpus_items` rows for the requested
`dataset_id` **and** `organization_id = <the claiming job's own
organization>` — a cross-tenant scan is structurally impossible, not
merely discouraged, since the join itself is scoped by both columns
together. `document_chunk_embeddings`/`retrieval_evaluation_query_embeddings`
RLS SELECT policies gate on `organization_id` exactly like every other
tenant-scoped table in this codebase.

## Tests

`supabase/tests/rls/014_embedding_and_vector_evaluation.sql` proves:
clinician denied on every new table and Worker-only function;
quality_manager permitted; a wrong-dimension vector rejected; a
succeeded chunk embedding immutable; the approved-configuration lookup
resolves correctly under permission; and both exact and indexed vector
search return the semantically closer synthetic chunk first, proving
tenant/dataset scoping and cosine-distance ordering both work correctly
end to end.
