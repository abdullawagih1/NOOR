"""
Centralized, validated Worker configuration (Security Agent requirement —
Sprint 0.5 Environment Variables mission). Nothing else in this codebase
should read `os.environ`/`os.getenv` directly; import `get_settings()`.

`worker_internal_token` is the only field required with no default: it
protects the one endpoint (`POST /jobs`) this service exposes today, so it
must fail loudly at startup rather than silently accept unauthenticated
requests. Supabase and AI Gateway fields stay optional — nothing in this
service calls either yet (Sprint 1 scope), so requiring them now would just
be friction with no corresponding behavior to protect.

`worker_processing_mode` defaults to "disabled" so every existing
deployment and test run is unaffected until an operator explicitly opts in
(Sprint 1.2A). "noop" runs the durable-orchestration claim/heartbeat/
complete loop against a controlled no-op processor only — see ADR 0009 and
`app/processing.py`. "extraction" (Sprint 1.2B) runs the same loop against
the real, deterministic PyPdfExtractor-backed processor — see ADR 0010 and
`app/pdf_extraction/processor.py`. There is deliberately no mode that
selects a test failure-injection processor: those exist only as direct
Python function parameters inside pytest, never as a runtime-selectable
value.

`worker_enabled_job_types` reuses the existing `document_parsing` job_type
value from migration 0006 rather than the mission's suggested
`document_extraction` string — that job_type has meant "this job's payload
is a PDF that needs its text extracted" since Sprint 1.1; Sprint 1.2B is
what actually implements it for real, not a new job kind. See
docs/domain/document-extraction-lifecycle.md for the naming
reconciliation.
"""
from __future__ import annotations

import secrets
from functools import lru_cache

from pydantic import AnyHttpUrl, SecretStr, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    worker_env: str = "development"
    log_level: str = "INFO"
    host: str = "0.0.0.0"
    port: int = 8080

    supabase_url: AnyHttpUrl | None = None
    supabase_service_role_key: SecretStr | None = None

    worker_internal_token: SecretStr

    web_app_url: AnyHttpUrl | None = None
    allowed_origins: str = "http://localhost:3000"

    ai_gateway_provider: str | None = None
    ai_gateway_api_key: SecretStr | None = None

    # --- Durable processing orchestration (Sprint 1.2A) --------------------
    worker_instance_id: str | None = None
    worker_poll_interval_seconds: int = 5
    worker_lease_duration_seconds: int = 90
    worker_heartbeat_interval_seconds: int = 30
    worker_max_concurrent_jobs: int = 1
    worker_processing_mode: str = "disabled"  # "disabled" | "noop" | "extraction"

    # --- Deterministic PDF extraction (Sprint 1.2B) -------------------------
    worker_enabled_job_types: str = "document_parsing"
    extraction_pipeline_version: str | None = None  # None -> use the pinned default in app/pdf_extraction/config.py
    extraction_configuration_version: str | None = None
    extraction_max_seconds: float = 300.0
    extraction_temp_directory: str | None = None  # None -> OS default (tempfile.mkdtemp())

    @field_validator("worker_internal_token")
    @classmethod
    def token_must_be_long_enough(cls, value: SecretStr) -> SecretStr:
        if len(value.get_secret_value()) < 32:
            raise ValueError(
                "WORKER_INTERNAL_TOKEN must be at least 32 characters "
                "(generate with: openssl rand -hex 32)"
            )
        return value

    @field_validator("worker_processing_mode")
    @classmethod
    def processing_mode_must_be_known(cls, value: str) -> str:
        if value not in ("disabled", "noop", "extraction"):
            raise ValueError('WORKER_PROCESSING_MODE must be "disabled", "noop", or "extraction"')
        return value

    @property
    def worker_enabled_job_types_list(self) -> list[str]:
        return [t.strip() for t in self.worker_enabled_job_types.split(",") if t.strip()]

    @model_validator(mode="after")
    def _assign_stable_worker_instance_id(self) -> "Settings":
        # Generated once per process lifetime (Settings is a process-wide
        # singleton via get_settings()'s lru_cache) unless the operator
        # pinned one explicitly — never regenerated mid-process, so a
        # claimed lease's owner name never changes underneath it.
        if not self.worker_instance_id or not self.worker_instance_id.strip():
            self.worker_instance_id = f"noor-worker-{self.worker_env}-{secrets.token_hex(3)}"
        return self

    @model_validator(mode="after")
    def _heartbeat_must_be_well_inside_the_lease(self) -> "Settings":
        if self.worker_heartbeat_interval_seconds >= self.worker_lease_duration_seconds:
            raise ValueError(
                "WORKER_HEARTBEAT_INTERVAL_SECONDS must be less than "
                "WORKER_LEASE_DURATION_SECONDS, or the lease can expire "
                "between heartbeats"
            )
        return self

    @property
    def allowed_origins_list(self) -> list[str]:
        return [origin.strip() for origin in self.allowed_origins.split(",") if origin.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()  # type: ignore[call-arg]  # pydantic-settings reads from env/`.env`
