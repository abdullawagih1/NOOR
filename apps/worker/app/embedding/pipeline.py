"""
Ties job context, input validation, batching, provider invocation, vector
validation, and artifact construction/upload together for one
document_embedding job (mission §27, ADR 0016). Runs inside the existing
WorkerLoop's heartbeat-thread window exactly like
app/chunking/pipeline.py / app/retrieval/pipeline.py.
"""
from __future__ import annotations

from app.embedding.checksums import compute_text_checksum, compute_vector_checksum, compute_vector_norm
from app.embedding.config import EMBEDDING_MAX_BATCH_ITEMS, MAXIMUM_INPUT_TOKENS
from app.embedding.errors import EmbeddingError
from app.embedding.identity import compute_chunk_embedding_identity_sha256
from app.embedding.provider import EmbeddingInput, EmbeddingProvider
from app.pdf_extraction.artifact_storage import upload_and_verify_artifact
from app.pdf_extraction.errors import ExtractionError


class ChunkEmbeddingResult:
    def __init__(self, *, chunk_id: str, chunk_index: int, chunk_checksum: str, input_text_checksum: str, input_token_count: int, embedding_identity_sha256: str, values: tuple[float, ...], vector_checksum: str, vector_norm: float) -> None:
        self.chunk_id = chunk_id
        self.chunk_index = chunk_index
        self.chunk_checksum = chunk_checksum
        self.input_text_checksum = input_text_checksum
        self.input_token_count = input_token_count
        self.embedding_identity_sha256 = embedding_identity_sha256
        self.values = values
        self.vector_checksum = vector_checksum
        self.vector_norm = vector_norm


def validate_and_prepare_chunk(
    *,
    provider: EmbeddingProvider,
    organization_id: str,
    chunking_run_id: str,
    chunk_id: str,
    chunk_index: int,
    chunk_checksum: str,
    chunk_text: str,
) -> tuple[EmbeddingInput, str]:
    """Computes the input checksum/token count and the deterministic
    embedding identity for one chunk, failing loudly (never silently
    truncating, mission §4/§12) if the input exceeds the model's limit."""
    input_text_checksum = compute_text_checksum(chunk_text)
    token_count = provider.count_tokens(chunk_text, input_mode="passage")
    if token_count > MAXIMUM_INPUT_TOKENS:
        raise EmbeddingError(
            "embedding_input_exceeds_model_limit",
            f"chunk {chunk_index} has {token_count} tokens, exceeding the approved model's limit of {MAXIMUM_INPUT_TOKENS}",
        )

    identity = compute_chunk_embedding_identity_sha256(
        organization_id=organization_id,
        chunk_id=chunk_id,
        chunk_checksum=chunk_checksum,
        chunking_run_id=chunking_run_id,
        input_text_checksum=input_text_checksum,
        provider_version=provider.version,
    )
    embedding_input = EmbeddingInput(key=chunk_id, text=chunk_text, input_checksum=input_text_checksum, token_count=token_count, input_mode="passage")
    return embedding_input, identity


def embed_chunks_in_batches(provider: EmbeddingProvider, inputs: list[EmbeddingInput], *, heartbeat=None) -> dict[str, tuple[float, ...]]:
    """Batches by item count (mission §26), mapping results back by the
    stable `key` each input carries — never assumed response order."""
    values_by_key: dict[str, tuple[float, ...]] = {}
    for start in range(0, len(inputs), EMBEDDING_MAX_BATCH_ITEMS):
        batch = inputs[start : start + EMBEDDING_MAX_BATCH_ITEMS]
        vectors = provider.embed(batch)
        vectors_by_key = {v.key: v for v in vectors}
        for item in batch:
            vector = vectors_by_key.get(item.key)
            if vector is None:
                raise EmbeddingError("embedding_provider_response_incomplete", f"no vector returned for input key {item.key}")
            values_by_key[item.key] = vector.values
        if heartbeat is not None:
            heartbeat()
    return values_by_key


def finalize_chunk_result(embedding_input: EmbeddingInput, embedding_identity_sha256: str, values: tuple[float, ...], *, chunk_index: int, chunk_checksum: str) -> ChunkEmbeddingResult:
    norm = compute_vector_norm(values)
    if norm <= 0.0:
        raise EmbeddingError("embedding_vector_norm_invalid", f"chunk {chunk_index} produced a non-positive vector norm ({norm})")
    checksum = compute_vector_checksum(values)
    return ChunkEmbeddingResult(
        chunk_id=embedding_input.key,
        chunk_index=chunk_index,
        chunk_checksum=chunk_checksum,
        input_text_checksum=embedding_input.input_checksum,
        input_token_count=embedding_input.token_count,
        embedding_identity_sha256=embedding_identity_sha256,
        values=values,
        vector_checksum=checksum,
        vector_norm=norm,
    )


def build_embedding_artifact_storage_path(*, organization_id: str, source_document_id: str, configuration_key: str, artifact_sha256: str) -> str:
    return f"{organization_id}/document-embeddings/{source_document_id}/{configuration_key}/{artifact_sha256}.json"


def upload_embedding_artifact(*, supabase_url: str, service_role_key: str, storage_bucket: str, storage_path: str, artifact_bytes: bytes, media_type: str, http_client=None) -> None:
    try:
        upload_and_verify_artifact(
            supabase_url=supabase_url,
            service_role_key=service_role_key,
            storage_bucket=storage_bucket,
            storage_path=storage_path,
            content_bytes=artifact_bytes,
            media_type=media_type,
            http_client=http_client,
        )
    except ExtractionError as exc:
        code = "embedding_artifact_failed"
        raise EmbeddingError(code, exc.message_safe) from exc
