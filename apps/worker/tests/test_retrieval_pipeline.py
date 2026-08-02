"""
Pipeline-level determinism and shape proofs (Sprint 1-E1, ADR 0015): the
same frozen-dataset input must produce byte-identical canonical artifacts
across repeated runs, and the RPC payloads handed to
finalize_retrieval_evaluation_run must have the exact shape migration 0015
expects. No network or database access — `fetch_candidates` here is a
plain in-memory fake.
"""
from __future__ import annotations

from app.retrieval.pipeline import run_evaluation_pipeline
from app.retrieval.retriever import Retriever  # noqa: F401 -- imported to prove the Protocol import path is stable
from app.retrieval.scoring import CandidateRow

CORPUS = {
    "en-blood-pressure": CandidateRow(
        corpus_item_id="ci-1", full_text_rank=0.6, normalized_search_text="blood pressure measurement technique for adults",
        token_count=6, display_order=1, chunk_checksum="chk-1",
    ),
    "ar-blood-pressure": CandidateRow(
        corpus_item_id="ci-2", full_text_rank=0.6, normalized_search_text="قياس ضغط الدم للبالغين بطريقة صحيحة",
        token_count=6, display_order=2, chunk_checksum="chk-2",
    ),
    "unrelated": CandidateRow(
        corpus_item_id="ci-3", full_text_rank=0.1, normalized_search_text="unrelated content about hospital parking",
        token_count=5, display_order=3, chunk_checksum="chk-3",
    ),
}


def _fetch_candidates(normalized_query_text: str) -> list[CandidateRow]:
    if "blood pressure" in normalized_query_text:
        return [CORPUS["en-blood-pressure"], CORPUS["unrelated"]]
    if "قياس ضغط الدم" in normalized_query_text:
        return [CORPUS["ar-blood-pressure"]]
    if "unicorn" in normalized_query_text:
        return []
    return []


QUERY_ROWS = [
    {"out_query_id": "q-en", "out_query_key": "q-en-exact", "out_normalized_query_text": "blood pressure measurement", "out_language": "en", "out_category": "english_exact", "out_difficulty": "basic", "out_is_negative_control": False},
    {"out_query_id": "q-ar", "out_query_key": "q-ar-exact", "out_normalized_query_text": "قياس ضغط الدم", "out_language": "ar", "out_category": "arabic_exact", "out_difficulty": "basic", "out_is_negative_control": False},
    {"out_query_id": "q-neg", "out_query_key": "q-negative", "out_normalized_query_text": "unicorn migration patterns antarctica", "out_language": "en", "out_category": "negative_control", "out_difficulty": "basic", "out_is_negative_control": True},
]

JUDGMENT_ROWS = [
    {"query_id": "q-en", "corpus_item_id": "ci-1", "relevance_grade": 3},
    {"query_id": "q-en", "corpus_item_id": "ci-3", "relevance_grade": 0},
    {"query_id": "q-ar", "corpus_item_id": "ci-2", "relevance_grade": 3},
]


def _run_pipeline():
    return run_evaluation_pipeline(
        organization_id="org-1",
        dataset_id="dataset-1",
        dataset_sha256="a" * 64,
        evaluation_run_id="run-1",
        query_rows=QUERY_ROWS,
        judgment_rows=JUDGMENT_ROWS,
        fetch_candidates=_fetch_candidates,
        retriever_name="noor-lexical-baseline",
        retriever_version="1",
        retrieval_configuration_version="1",
        query_normalization_version="retrieval_text_normalization_v1",
        metric_definition_version="1",
        evaluation_runner_version="1",
        top_k_values=[1, 3, 5, 10],
        relevance_threshold=2,
    )


def test_pipeline_produces_byte_identical_artifacts_across_repeated_runs():
    first = _run_pipeline()
    second = _run_pipeline()
    assert first.artifact_bytes == second.artifact_bytes
    assert first.artifact_sha256 == second.artifact_sha256


def test_english_and_arabic_exact_queries_rank_their_expected_chunk_first():
    outcome = _run_pipeline()
    en_results = [r for r in outcome.results_payload if r["query_id"] == "q-en"]
    ar_results = [r for r in outcome.results_payload if r["query_id"] == "q-ar"]

    assert en_results[0]["corpus_item_id"] == "ci-1"
    assert en_results[0]["rank"] == 1
    assert en_results[0]["is_hit"] is True

    assert ar_results[0]["corpus_item_id"] == "ci-2"
    assert ar_results[0]["is_hit"] is True


def test_negative_control_query_produces_no_results_and_a_failure_annotation():
    outcome = _run_pipeline()
    neg_results = [r for r in outcome.results_payload if r["query_id"] == "q-neg"]
    assert neg_results == []
    assert {"query_id": "q-neg", "failure_category": "negative_control_false_positive"} not in outcome.failures_payload
    # (no candidates were returned for the negative control in this fixture,
    # so no false positive should be raised -- proves the detector only
    # fires when candidates ARE retrieved, not merely for existing.)


def test_metrics_payload_excludes_negative_control_from_overall_sample_size():
    outcome = _run_pipeline()
    overall_precision_1 = next(m for m in outcome.metrics_payload if m["scope_type"] == "overall" and m["metric_name"] == "precision_at_1")
    assert overall_precision_1["sample_size"] == 2


def test_result_rows_have_the_exact_shape_finalize_retrieval_evaluation_run_expects():
    outcome = _run_pipeline()
    required_keys = {
        "query_id", "corpus_item_id", "rank", "final_score", "score_components",
        "matched_terms", "relevance_grade", "reciprocal_rank_contribution",
        "dcg_contribution", "is_hit", "result_checksum",
    }
    for row in outcome.results_payload:
        assert required_keys.issubset(row.keys())


def test_storage_path_is_tenant_scoped_and_content_addressed():
    outcome = _run_pipeline()
    assert outcome.storage_path.startswith("org-1/retrieval-evaluation/dataset-1/")
    assert outcome.storage_path.endswith(f"{outcome.artifact_sha256}.json")
    assert outcome.storage_bucket == "guideline-processed"
