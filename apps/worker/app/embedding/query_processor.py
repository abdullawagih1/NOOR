"""
The query-embedding-generation Processor (Sprint 1-E2, ADR 0016) — its own
controlled path, not folded into the vector-evaluation job (ADR 0016:
query embeddings are generated once per dataset/configuration and reused
across every evaluation run at that configuration). One job here embeds
every active query in one frozen dataset.

Unlike every other processor in this Worker, completion is reported
directly via `complete_document_processing_job` (already Worker-only,
migration 0007) rather than a dedicated `finalize_*` function — there is no
separate "query embedding run" entity to finalize (mission's own economy
principle: query-embedding completion is fully determined by whether every
active query now has a succeeded `retrieval_evaluation_query_embeddings`
row, which `record_query_embedding` already establishes per query).
"""
from __future__ import annotations

import logging
import uuid
from typing import Callable

from app.embedding.checksums import compute_text_checksum, compute_vector_checksum, compute_vector_norm, vector_to_pgvector_literal
from app.embedding.config import MAXIMUM_INPUT_TOKENS
from app.embedding.errors import EmbeddingError
from app.embedding.identity import compute_query_embedding_identity_sha256
from app.embedding.pipeline import embed_chunks_in_batches
from app.embedding.provider import EmbeddingInput, EmbeddingProvider
from app.orchestration_client import ClaimedJob, OrchestrationClient, OrchestrationError
from app.processing import Processor, ProcessingOutcome

logger = logging.getLogger("noor.worker.query_embedding")


def make_query_embedding_processor(
    client: OrchestrationClient,
    *,
    provider: EmbeddingProvider,
    worker_instance_id: str,
) -> Processor:
    def process(job: ClaimedJob, heartbeat: Callable[[], None]) -> ProcessingOutcome:
        try:
            context_rows = client.get_query_embedding_job_context(job.job_id, worker_instance_id, job.lease_token)
        except OrchestrationError as exc:
            message = str(exc).lower()
            if "not_frozen" in message or "embedding_configuration_not_approved" in message:
                return ProcessingOutcome(
                    kind="terminal_failure",
                    error_code="query_embedding_dataset_not_frozen",
                    error_class="query_embedding_dataset_not_frozen",
                    error_message_safe="the evaluation dataset is no longer frozen",
                )
            return ProcessingOutcome(
                kind="retryable_failure",
                error_code="embedding_internal_error",
                error_class="embedding_internal_error",
                error_message_safe="this job's query-embedding context could not be read",
            )

        if not context_rows:
            return ProcessingOutcome(
                kind="terminal_failure",
                error_code="query_embedding_dataset_not_frozen",
                error_class="query_embedding_dataset_not_frozen",
                error_message_safe="this dataset has no active queries to embed",
            )

        first_row = context_rows[0]
        dataset_id = uuid.UUID(str(first_row["out_dataset_id"]))
        dataset_sha256 = first_row["out_dataset_sha256"]
        embedding_configuration_id = uuid.UUID(str(first_row["out_embedding_configuration_id"]))

        prepared: list[tuple[EmbeddingInput, str, uuid.UUID]] = []
        for row in context_rows:
            query_id = uuid.UUID(str(row["out_query_id"]))
            query_text = row["out_query_text"]
            query_checksum = row["out_query_checksum"]

            token_count = provider.count_tokens(query_text, input_mode="query")
            if token_count > MAXIMUM_INPUT_TOKENS:
                return ProcessingOutcome(
                    kind="terminal_failure",
                    error_code="embedding_input_exceeds_model_limit",
                    error_class="embedding_input_exceeds_model_limit",
                    error_message_safe=f"query {row['out_query_key']} exceeds the approved model's input limit",
                )

            input_checksum = compute_text_checksum(query_text)
            identity = compute_query_embedding_identity_sha256(
                organization_id=str(job.organization_id),
                evaluation_dataset_id=str(dataset_id),
                dataset_sha256=dataset_sha256,
                query_id=str(query_id),
                query_checksum=query_checksum,
                provider_version=provider.version,
            )
            prepared.append((EmbeddingInput(key=str(query_id), text=query_text, input_checksum=input_checksum, token_count=token_count, input_mode="query"), identity, query_id))

        heartbeat()

        try:
            values_by_key = embed_chunks_in_batches(provider, [inp for inp, _identity, _qid in prepared], heartbeat=heartbeat)
        except EmbeddingError as exc:
            return _terminal_or_retryable(exc)

        succeeded_count = 0
        for embedding_input, identity, query_id in prepared:
            values = values_by_key[embedding_input.key]
            norm = compute_vector_norm(values)
            if norm <= 0.0:
                return ProcessingOutcome(
                    kind="retryable_failure",
                    error_code="embedding_vector_norm_invalid",
                    error_class="embedding_vector_norm_invalid",
                    error_message_safe="a query produced a non-positive vector norm",
                )
            checksum = compute_vector_checksum(values)

            try:
                client.record_query_embedding(
                    job.job_id, worker_instance_id, job.lease_token, dataset_id, query_id,
                    embedding_configuration_id, identity, embedding_input.input_checksum, embedding_input.token_count,
                    vector_to_pgvector_literal(values), checksum, norm,
                    correlation_id=job.correlation_id,
                )
            except OrchestrationError:
                return ProcessingOutcome(
                    kind="retryable_failure",
                    error_code="database_finalization_failed",
                    error_class="database_finalization_failed",
                    error_message_safe="could not persist a query embedding",
                )
            succeeded_count += 1
            heartbeat()

        try:
            client.complete_job(
                job.job_id, worker_instance_id, job.lease_token,
                {"query_count": succeeded_count}, correlation_id=job.correlation_id,
            )
        except OrchestrationError:
            return ProcessingOutcome(
                kind="retryable_failure",
                error_code="database_finalization_failed",
                error_class="database_finalization_failed",
                error_message_safe="could not complete the query-embedding job",
            )

        return ProcessingOutcome(
            kind="succeeded",
            result_summary={"processor": "noor-query-embedding-pipeline", "dataset_id": str(dataset_id), "query_count": succeeded_count},
        )

    return process


def _terminal_or_retryable(exc: EmbeddingError) -> ProcessingOutcome:
    logger.warning("query embedding failed error_code=%s", exc.error_code)
    return ProcessingOutcome(
        kind="retryable_failure" if exc.retryable else "terminal_failure",
        error_code=exc.error_code,
        error_class=exc.error_class,
        error_message_safe=exc.message_safe,
    )
