"""
Internal-token authentication for server-to-server calls from the Web app.

Sent as `Authorization: Bearer <token>`, never in a URL or query string
(Environment Variables mission §10). Comparison uses `secrets.compare_digest`
to avoid timing side-channels; the failure responses never echo or hint at
the expected token.
"""
from __future__ import annotations

import secrets

from fastapi import Header, HTTPException, status

from app.settings import get_settings


def verify_internal_token(authorization: str | None = Header(default=None)) -> None:
    if authorization is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing Authorization header")

    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid Authorization header")

    expected = get_settings().worker_internal_token.get_secret_value()
    if not secrets.compare_digest(token, expected):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Invalid token")
