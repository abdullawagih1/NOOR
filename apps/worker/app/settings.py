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
"""
from __future__ import annotations

from functools import lru_cache

from pydantic import AnyHttpUrl, SecretStr, field_validator
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

    @field_validator("worker_internal_token")
    @classmethod
    def token_must_be_long_enough(cls, value: SecretStr) -> SecretStr:
        if len(value.get_secret_value()) < 32:
            raise ValueError(
                "WORKER_INTERNAL_TOKEN must be at least 32 characters "
                "(generate with: openssl rand -hex 32)"
            )
        return value

    @property
    def allowed_origins_list(self) -> list[str]:
        return [origin.strip() for origin in self.allowed_origins.split(",") if origin.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()  # type: ignore[call-arg]  # pydantic-settings reads from env/`.env`
