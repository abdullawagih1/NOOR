"""
The real chunk-embedding Processor (Sprint 1-E2, ADR 0016) — matches the
same `Processor` contract as every other processor in this Worker. One job
here is one whole accepted chunking run's chunks, embedded under the one
approved embedding configuration (mission §22).

`make_embedding_processor()` is a factory, not the processor itself, for
the same reason every other `make_*_processor()` in this Worker is: it
needs an `OrchestrationClient`, a real `EmbeddingProvider`, and pinned
configuration the bare `(job, heartbeat) -> ProcessingOutcome` signature
has no way to carry.
"""
from __future__ import annotations

import logging
import uuid
from typing import Callable

from app.embedding.artifact import build_canonical_embedding_artifact
from app.embedding.checksums import canonical_bytes, compute_artifact_checksum, vector_to_pgvector_literal
from app.embedding.config import ARTIFACT_MEDIA_TYPE, ARTIFACT_STORAGE_BUCKET, EMBEDDING_CONFIGURATION_KEY
from app.embedding.errors import EmbeddingError
from app.embedding.manifest import build_chunk_manifest, compute_chunk_manifest_sha256
from app.embedding.pipeline import (
    build_embedding_artifact_storage_path,
    embed_chunks_in_batches,
    finalize_chunk_result,
    upload_embedding_artifact,
    validate_and_prepare_chunk,
)
from app.embedding.provider import EmbeddingProvider
from app.orchestration_client import ClaimedJob, OrchestrationClient, OrchestrationError
from app.processing import Processor, ProcessingOutcome

logger = logging.getLogger("noor.worker.embedding")


def make_embedding_processor(
    client: OrchestrationClient,
    *,
    provider: EmbeddingProvider,
    worker_instance_id: str,
    supabase_url: str,
    service_role_key: str,
) -> Processor:
    def process(job: ClaimedJob, heartbeat: Callable[[], None]) -> ProcessingOutcome:
        try:
            context_rows = client.get_document_embedding_job_context(job.job_id, worker_instance_id, job.lease_token)
        except OrchestrationError as exc:
            message = str(exc).lower()
            if "not embedding-ready" in message or "embedding_configuration_not_approved" in message:
                return ProcessingOutcome(
                    kind="terminal_failure",
                    error_code="embedding_input_not_ready",
                    error_class="embedding_input_not_ready",
                    error_message_safe="this document is not embedding-ready",
                )
            return ProcessingOutcome(
                kind="retryable_failure",
                error_code="embedding_internal_error",
                error_class="embedding_internal_error",
                error_message_safe="this job's embedding context could not be read",
            )

        if not context_rows:
            return ProcessingOutcome(
                kind="terminal_failure",
                error_code="embedding_input_not_ready",
                error_class="embedding_input_not_ready",
                error_message_safe="this document has no chunks to embed",
            )

        first_row = context_rows[0]
        chunking_run_id = uuid.UUID(str(first_row["out_chunking_run_id"]))
        chunking_review_id = uuid.UUID(str(first_row["out_chunking_review_id"])) if first_row.get("out_chunking_review_id") else None
        embedding_configuration_id = uuid.UUID(str(first_row["out_embedding_configuration_id"]))
        configuration_key = first_row["out_configuration_key"]

        try:
            prepared = [
                validate_and_prepare_chunk(
                    provider=provider,
                    organization_id=str(job.organization_id),
                    chunking_run_id=str(chunking_run_id),
                    chunk_id=str(row["out_chunk_id"]),
                    chunk_index=int(row["out_chunk_index"]),
                    chunk_checksum=row["out_chunk_checksum"],
                    chunk_text=row["out_chunk_text"],
                )
                for row in context_rows
            ]
        except EmbeddingError as exc:
            return ProcessingOutcome(
                kind="terminal_failure",
                error_code=exc.error_code,
                error_class=exc.error_class,
                error_message_safe=exc.message_safe,
            )

        chunks_by_id = {str(row["out_chunk_id"]): row for row in context_rows}
        manifest = build_chunk_manifest(
            chunking_run_id=str(chunking_run_id),
            chunking_review_id=str(chunking_review_id) if chunking_review_id else None,
            configuration_key=configuration_key,
            provider_name=provider.name,
            model_identifier=provider.model_identifier,
            model_revision=provider.model_revision,
            embedding_dimension=provider.dimension,
            chunks=[
                {
                    "chunk_id": inp.key,
                    "chunk_index": int(chunks_by_id[inp.key]["out_chunk_index"]),
                    "chunk_checksum": chunks_by_id[inp.key]["out_chunk_checksum"],
                    "input_text_checksum": inp.input_checksum,
                    "input_token_count": inp.token_count,
                }
                for inp, _identity in prepared
            ],
        )
        manifest_sha256 = compute_chunk_manifest_sha256(manifest)

        try:
            run_row = client.create_document_embedding_run(
                job.job_id, worker_instance_id, job.lease_token,
                chunking_run_id, chunking_review_id, embedding_configuration_id,
                manifest, manifest_sha256, len(prepared),
                correlation_id=job.correlation_id,
            )
        except OrchestrationError:
            return ProcessingOutcome(
                kind="retryable_failure",
                error_code="database_finalization_failed",
                error_class="database_finalization_failed",
                error_message_safe="could not create the embedding run",
            )

        embedding_run_id = uuid.UUID(str(run_row["out_embedding_run_id"]))
        if run_row.get("out_reused"):
            logger.info("embedding identity already succeeded, reusing embedding_run_id=%s for job_id=%s", embedding_run_id, job.job_id)
            return ProcessingOutcome(
                kind="succeeded",
                result_summary={"processor": "noor-embedding-pipeline", "embedding_run_id": str(embedding_run_id), "reused": True},
            )

        heartbeat()

        try:
            values_by_key = embed_chunks_in_batches(provider, [inp for inp, _identity in prepared], heartbeat=heartbeat)
        except EmbeddingError as exc:
            return _fail(client, job, worker_instance_id, embedding_run_id, exc)

        artifact_items: list[dict] = []
        for embedding_input, identity in prepared:
            values = values_by_key[embedding_input.key]
            try:
                result = finalize_chunk_result(
                    embedding_input, identity, values,
                    chunk_index=int(chunks_by_id[embedding_input.key]["out_chunk_index"]),
                    chunk_checksum=chunks_by_id[embedding_input.key]["out_chunk_checksum"],
                )
            except EmbeddingError as exc:
                return _fail(client, job, worker_instance_id, embedding_run_id, exc)

            try:
                record_row = client.record_document_chunk_embedding(
                    job.job_id, worker_instance_id, job.lease_token, embedding_run_id,
                    uuid.UUID(result.chunk_id), result.embedding_identity_sha256,
                    result.input_text_checksum, result.input_token_count,
                    vector_to_pgvector_literal(result.values), result.vector_checksum, result.vector_norm,
                    correlation_id=job.correlation_id,
                )
            except OrchestrationError as exc:
                message = str(exc).lower()
                code = "embedding_dimension_mismatch" if "dimension" in message else "embedding_persistence_failed"
                return _fail(client, job, worker_instance_id, embedding_run_id, EmbeddingError(code, "could not persist a chunk embedding"))

            artifact_items.append(
                {
                    "chunk_index": result.chunk_index,
                    "chunk_checksum": result.chunk_checksum,
                    "input_text_checksum": result.input_text_checksum,
                    "embedding_identity_sha256": result.embedding_identity_sha256,
                    "vector_checksum": record_row.get("vector_checksum", result.vector_checksum),
                    "dimension": provider.dimension,
                    "norm": result.vector_norm,
                    "reused": False,
                }
            )
            heartbeat()

        try:
            artifact = build_canonical_embedding_artifact(
                run_identity_sha256=manifest_sha256,
                chunk_manifest_sha256=manifest_sha256,
                configuration_key=configuration_key,
                provider_name=provider.name,
                provider_version=provider.version,
                model_identifier=provider.model_identifier,
                model_revision=provider.model_revision,
                embedding_dimension=provider.dimension,
                distance_metric="cosine",
                items=artifact_items,
            )
            artifact_bytes = canonical_bytes(artifact)
            artifact_sha256 = compute_artifact_checksum(artifact)
            storage_path = build_embedding_artifact_storage_path(
                organization_id=str(job.organization_id),
                source_document_id=str(job.source_document_id),
                configuration_key=configuration_key,
                artifact_sha256=artifact_sha256,
            )
            upload_embedding_artifact(
                supabase_url=supabase_url, service_role_key=service_role_key,
                storage_bucket=ARTIFACT_STORAGE_BUCKET, storage_path=storage_path,
                artifact_bytes=artifact_bytes, media_type=ARTIFACT_MEDIA_TYPE,
            )
        except EmbeddingError as exc:
            return _fail(client, job, worker_instance_id, embedding_run_id, exc)

        try:
            finalize_row = client.finalize_document_embedding_run(
                job.job_id, worker_instance_id, job.lease_token, embedding_run_id,
                ARTIFACT_STORAGE_BUCKET, storage_path, artifact_sha256, len(artifact_bytes), ARTIFACT_MEDIA_TYPE,
                correlation_id=job.correlation_id,
            )
        except OrchestrationError:
            return _fail(client, job, worker_instance_id, embedding_run_id, EmbeddingError("database_finalization_failed", "could not finalize the embedding run"))

        return ProcessingOutcome(
            kind="succeeded",
            result_summary={
                "processor": "noor-embedding-pipeline",
                "configuration_key": configuration_key,
                "embedding_run_id": str(embedding_run_id),
                "succeeded_count": finalize_row.get("out_succeeded_count", len(artifact_items)),
                "artifact_sha256": artifact_sha256,
                "status": finalize_row.get("out_status", "succeeded"),
            },
        )

    return process


def _fail(client: OrchestrationClient, job: ClaimedJob, worker_instance_id: str, embedding_run_id: uuid.UUID, exc: EmbeddingError) -> ProcessingOutcome:
    logger.warning("embedding failed job_id=%s embedding_run_id=%s error_code=%s", job.job_id, embedding_run_id, exc.error_code)
    try:
        client.fail_document_embedding_run(
            job.job_id, worker_instance_id, job.lease_token, embedding_run_id,
            exc.error_code, exc.error_class or exc.error_code, exc.message_safe, job.correlation_id,
        )
    except OrchestrationError:
        logger.exception("failed to record embedding-run failure for job_id=%s (lease likely lost)", job.job_id)
    return ProcessingOutcome(
        kind="retryable_failure" if exc.retryable else "terminal_failure",
        error_code=exc.error_code,
        error_class=exc.error_class,
        error_message_safe=exc.message_safe,
    )
