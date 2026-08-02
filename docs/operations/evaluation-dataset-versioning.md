# Evaluation Dataset Versioning

Sprint 1-E1. Operational guidance for when and how to version a
retrieval evaluation dataset. See
`docs/domain/retrieval-evaluation-dataset-lifecycle.md` for the
underlying state machine this document assumes.

## The rule: frozen datasets never return to draft

Once `freeze_retrieval_evaluation_dataset` succeeds, the corpus, query
set, judgments, and their manifests are permanently immutable — enforced
by database triggers, not merely a UI restriction. There is **no**
function anywhere in this schema that mutates a frozen dataset's
content or moves it back to `draft`. This is deliberate: any evaluation
run's results must always be traceable to one exact, never-since-altered
input. If a correction were allowed to mutate frozen content, a
previously-reported metric could silently stop meaning what it said it
meant.

## When you find a mistake in a frozen dataset

Create a **new dataset version**, never edit the frozen one:

1. `create_retrieval_evaluation_dataset` with the same `logical_name`
   but `version = <previous version> + 1`
   (`unique(organization_id, logical_name, version)` enforces this is a
   genuinely new row, not a silent overwrite).
2. Optionally set `parent_dataset_id` to the prior version, so the
   correction's lineage is queryable.
3. Re-add corpus items (they may be identical to the prior version, or
   corrected), re-author queries and judgments as needed, and go through
   the same draft → ready_for_review → frozen lifecycle again,
   including a fresh two-person review.
4. Any evaluation run against the new version gets its own
   `run_identity_sha256` (it depends on `dataset_sha256`, which will
   differ from the prior version's) — there is no ambiguity about which
   frozen input produced which numbers.

## Archiving vs. correcting

`archive_retrieval_evaluation_dataset` (`frozen` → `archived`) is for
retiring a dataset version that is no longer the "current" one to run
against — typically once a corrected version has been frozen. Archiving
does **not** invalidate past evaluation runs or their results/metrics;
those remain queryable exactly as they were computed, tied to the
archived dataset's `dataset_sha256`. Archive a version to signal "stop
running new evaluations against this one," not to retroactively hide
what was already measured.

## Naming convention

`logical_name` should describe the dataset's scope, not its version
(e.g. `noor-retrieval-eval-foundation`, not
`noor-retrieval-eval-foundation-v2`) — the `version` integer column
already carries that information and is what the uniqueness constraint
and lineage (`parent_dataset_id`) key off. Keep `logical_name` stable
across a version's entire correction history so the lineage chain stays
easy to follow.

## What this sprint explicitly does not do

No automatic dataset versioning triggered by upstream changes (e.g. a
source chunk being invalidated does not automatically spin up a new
dataset version) — freeze-time re-validation
(`get_document_embedding_readiness` re-checked live) will simply cause
the *next* freeze attempt on a still-`draft`/`ready_for_review` dataset
to fail loudly if a corpus item's provenance is no longer trustworthy,
surfacing the problem for a human to resolve rather than silently
auto-correcting it.
