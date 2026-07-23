# Worker Deployment

`apps/worker` is a FastAPI service, containerized (`apps/worker/Dockerfile`),
intended to run on a platform that supports long-lived containers (Fly.io,
Railway, Render, a VM, or similar) — not Vercel, which cannot run
long-running processes (ADR 0001).

## Status as of the Environment Variables session

Not deployed anywhere yet — Sprint 1 scope, once real PDF-processing logic
exists to justify standing up hosted infrastructure for it. This document
describes the configuration required whenever that happens.

## Required environment

See `apps/worker/.env.example` and `docs/operations/environment-variables.md`
for the full reference. Summary:

* `WORKER_INTERNAL_TOKEN` — **required**, no default. The process refuses
  to start without it (verified this session: a missing or <32-character
  value produces a `pydantic.ValidationError` at import time, not a
  runtime 500 on first request).
* `ALLOWED_ORIGINS` — comma-separated list, feeds the Worker's CORS
  middleware (`app/main.py`). Must include the Web app's real origin(s) in
  any hosted environment — defaults to `http://localhost:3000` for local
  dev only.
* Everything else (`SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`,
  `AI_GATEWAY_*`) is optional — declared for Sprint 1, unused today.

## Authentication

Every call to `POST /jobs` must carry:

```
Authorization: Bearer <WORKER_INTERNAL_TOKEN>
```

* Missing header → `401`
* Malformed header (not `Bearer <token>`) → `401`
* Wrong token → `403` (constant-time comparison via `secrets.compare_digest`
  — see `app/auth.py`)
* Error responses never echo or hint at the expected token — verified by
  `test_accept_job_error_does_not_reveal_expected_token`.

`/health` and `/ready` remain unauthenticated — standard practice so an
orchestrator's liveness/readiness probes don't need the secret.

**The Web app and the Worker must be configured with the exact same
`WORKER_INTERNAL_TOKEN` value.** There is no shared secret store between
them yet (Sprint 1 might introduce one) — until then, set it identically
in both hosting environments whenever it's generated or rotated.

## Local run

```bash
cd apps/worker
python -m venv .venv && .venv/bin/pip install -r requirements.txt   # or .venv\Scripts\pip on Windows
cp .env.example .env
# edit .env: set WORKER_INTERNAL_TOKEN (openssl rand -hex 32)
export $(cat .env | xargs)   # or use your shell's .env loading
uvicorn app.main:app --reload --port 8080
```

## Verification (reproducible)

```bash
python -m compileall apps/worker
cd apps/worker && pytest tests/ -v
```

`tests/conftest.py` sets a test-only `WORKER_INTERNAL_TOKEN` before any
test module imports `app.main` — no real secret is ever needed to run the
test suite.

## Docker

```bash
docker build -t noor-worker apps/worker
docker run -p 8080:8080 --env-file apps/worker/.env noor-worker
```

The `Dockerfile`'s `HEALTHCHECK` hits `/health` (unauthenticated, by
design — see above).

## Not yet done (Sprint 1)

* No actual hosting platform chosen or configured.
* No Supabase Queues consumer — `/jobs` validates and acknowledges a
  contract only, doesn't process anything.
* No real PDF parsing, chunking, or embedding logic.
