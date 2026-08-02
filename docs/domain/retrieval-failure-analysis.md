# Retrieval Failure Analysis

Sprint 1-E1. See ADR 0015 and `apps/worker/app/retrieval/failure_analysis.py`
(the source of truth for the system-detection rules — this document
explains the design, not a substitute for reading the code).

## 17-category taxonomy, two sources

`retrieval_evaluation_failures.failure_category` is CHECK-constrained to
17 values; `source` is `system` (deterministic, Worker-computed) or
`human` (a reviewer's own annotation via `create_failure_annotation`).
Not every category can be mechanically detected — this is by design,
not an oversight:

| Category | Source |
|---|---|
| `missed_relevant_item` | system |
| `relevant_below_k` | system |
| `non_relevant_ranked_high` | system |
| `exact_phrase_failure` | system |
| `arabic_normalization_failure` | system |
| `mixed_language_failure` | system |
| `numeric_match_failure` | system |
| `abbreviation_failure` | system |
| `query_too_broad` | system |
| `query_too_narrow` | system |
| `insufficient_lexical_overlap` | system |
| `negative_control_false_positive` | system |
| `tokenization_failure` | human only |
| `tie_break_failure` | human only |
| `judgment_gap` | human only |
| `corpus_gap` | human only |
| `other` | human only |

The four human-only categories require judgment a mechanical rule
cannot make safely: whether a tokenization quirk actually caused the
miss, whether a tie-break outcome was actually wrong, whether the
dataset's judgments themselves have a gap, or whether the corpus itself
is missing content — all of these require a person to look at the
actual chunk text and query intent.

## System detection rules (`detect_failures`, one category per query, priority order)

Checked in this order — the first matching rule wins, so a query never
gets double-counted across overlapping symptoms:

1. **`negative_control_false_positive`** — a negative-control query
   returned any candidate at all (it should ideally return none).
2. **`query_too_narrow`** — a non-negative-control query returned no
   candidates at all.
3. **`missed_relevant_item`** — at least one judged-relevant item
   (`grade >= threshold`) exists for this query but never appears
   anywhere in the ranked candidate list.
4. **`relevant_below_k`** — a relevant item was retrieved, but only
   past rank 10 (beyond every K this sprint evaluates).
5. **`exact_phrase_failure`** — an `exact_phrase`/`english_exact`/
   `arabic_exact` category query misses at rank 1.
6. **`arabic_normalization_failure`** — an Arabic-language query has no
   hit anywhere in the top 10.
7. **`mixed_language_failure`** — a `mixed_language` category query has
   no hit in the top 10.
8. **`numeric_match_failure`** — a `numeric_lookup` category query has
   no hit in the top 10.
9. **`abbreviation_failure`** — an `abbreviation` category query has no
   hit in the top 10.
10. **`non_relevant_ranked_high`** — a relevant item WAS retrieved
    within the top 10, but is outranked by a non-relevant item at
    rank 1 (distinct from 3/4 above, where nothing relevant is found
    within K at all).
11. **`query_too_broad`** — rank 1 IS relevant, but precision over the
    top 10 is still low (many irrelevant results crowding the rest of
    the list).
12. **`insufficient_lexical_overlap`** — a fallback: no hit at all, and
    none of the more specific category-based rules above applied.

A query that hits cleanly (a relevant item at or near rank 1, no
negative-control false positive) raises no failure at all — the
detectors only fire on an actual, specific symptom.

## Human annotation

`create_failure_annotation`/`update_failure_annotation` (client-facing,
`retrieval_evaluation.annotate_failures`) let a reviewer add a failure
row with any of the 17 categories (typically one of the four
system-detectors cannot reach), or update an existing row's `status`
(`open`/`acknowledged`/`resolved`), `reviewer_note`, and
`recommended_experiment`. The failure's core content
(`failure_category`, `query_id`, `source`) is immutable once created —
only the review-workflow fields above can change afterward
(`prevent_failure_content_mutation` trigger).

## What this sprint explicitly does not do

No automated remediation, no automatic retrieval-configuration changes
in response to a detected failure, and no claim that a clean run (zero
detected failures) proves the lexical baseline is "good" in any
absolute sense — it only proves this specific frozen dataset produced
no *detectable* symptom against this specific deterministic baseline.
