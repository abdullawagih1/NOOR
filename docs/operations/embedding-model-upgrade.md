# Embedding Model/Provider Upgrade Procedure (Sprint 1-E2)

Every component of the embedding identity (ADR 0016) is pinned as an
explicit constant in `apps/worker/app/embedding/config.py`, never
inferred from whatever happens to be installed or cached. Bumping any of
them is a deliberate, reviewed action — never an incidental side effect
of an unrelated dependency update.

## What is pinned, and where

| Constant | Current value | Source of truth |
|---|---|---|
| `PROVIDER_NAME` / `PROVIDER_TYPE` | `sentence-transformers` / `self_hosted` | `apps/worker/requirements.txt` pin. |
| `MODEL_IDENTIFIER` / `MODEL_REVISION` | `intfloat/multilingual-e5-base` / `d128750597153bb5987e10b1c3493a34e5a4502a` | Confirmed live against the Hugging Face Hub API (`GET /api/models/<id>`, `sha` field) at approval time — never assumed from the README; verified at provider construction by `assert_pinned_embedding_model()`. |
| `EMBEDDING_DIMENSION` | `768` | Confirmed live via `model.get_embedding_dimension()`; `SentenceTransformerProvider.__init__` raises `embedding_dimension_mismatch` if the loaded model's own reported dimension ever disagrees. |
| `PASSAGE_INPUT_TEMPLATE_VERSION` / `QUERY_INPUT_TEMPLATE_VERSION` | `"1"` / `"1"` | Bumped whenever the `"passage: "`/`"query: "` prefix convention changes. |
| `OUTPUT_NORMALIZATION` / `DISTANCE_METRIC` | `l2_normalized` / `cosine` | The model card's own documented recommendation; pins the pgvector operator class (`vector_cosine_ops`) end to end. |
| `EMBEDDING_CONFIGURATION_VERSION` | `"1"` | Must match the seeded `embedding_configurations.configuration_version` row exactly (migration 0016) — bump both together. |

## Upgrading the model revision (same model family)

1. Confirm the new revision's exact commit SHA against the live Hugging
   Face Hub API — never trust a branch name or "latest."
2. Update `MODEL_REVISION` in `app/embedding/config.py` to match exactly.
3. Delete any locally cached snapshot of the old revision if disk space
   is a concern (`huggingface-cli delete-cache` or remove the specific
   revision under `~/.cache/huggingface/hub/`), then let
   `sentence-transformers` re-download the new one on next use.
4. `assert_pinned_embedding_model()` will crash the process at startup
   if the loaded model's resolved identifier/revision ever disagrees
   with these constants again.
5. Re-run `pytest apps/worker/tests/test_embedding_provider_real_model.py`
   locally to confirm the new revision loads and produces sane,
   sensibly-ranked vectors before deploying.
6. A revision change is, by construction, already a different embedding
   identity (`model_revision` is part of the identity tuple) — existing
   vectors under the old revision remain valid and queryable; nothing
   needs to be re-embedded unless you choose to.

## Switching to a different model entirely (e.g. a larger e5 variant, or an external API)

This is a bigger, riskier change than a revision bump — treat it as a
new ADR, not a config edit:

1. Re-run the provider/model evaluation spike (ADR 0016's own
   methodology: license, dimension, max input length, Arabic/mixed-
   language evidence, resource footprint, data-residency if external) —
   never switch models "because it's popular" or "because credentials
   already exist."
2. If the new model has a different embedding dimension, this requires
   a **new** `document_chunk_embeddings`-shaped table/column generation
   (the fixed `vector(768)` column cannot silently accept a different
   dimension) — see ADR 0016's "fixed-dimension column" decision and its
   documented tradeoff.
3. Insert a **new** `embedding_configurations` row (never mutate the
   existing approved row in place) with `approval_status = 'draft'`,
   go through explicit approval, and only then flip it to `'approved'`
   (which automatically un-approves the prior row, since at most one may
   be `approved` at a time).
4. Existing vectors under the retired configuration are never deleted —
   they remain historically valid for reproducing past evaluation
   artifacts, but new work resolves against the newly approved
   configuration.
5. Re-run the full vector-evaluation comparison (exact-vs-indexed,
   lexical-vs-vector) under the new configuration before considering it
   operationally trusted.

## Supply-chain discipline

- Never load a model from `main`/`latest` — always an explicit,
  API-confirmed commit SHA.
- Never allow a browser-supplied provider/model/dimension argument —
  every identity component is either a server-pinned constant or a
  value already stored on an immutable, server-created row, never
  client input.
- `assert_pinned_embedding_model()` fails closed: a resolved
  identifier/revision mismatch crashes the Worker at startup rather than
  silently proceeding with the wrong model.
- If a future provider is external (an API rather than self-hosted),
  its credentials must be Worker-only, environment-managed, and never
  logged — the same discipline already applied to every other secret in
  this codebase (`WORKER_INTERNAL_TOKEN`, `SUPABASE_SERVICE_ROLE_KEY`).
