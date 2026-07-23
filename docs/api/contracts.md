# API Contracts — Sprint 0

## Worker: `POST /jobs`

Validates and acknowledges a job message. Does not yet execute processing.

Request body — see `packages/clinical-schemas` equivalent job types (TS) and
`apps/worker/app/main.py::JobMessage` (Python) for the canonical shape:

```json
{
  "job_id": "uuid",
  "organization_id": "uuid",
  "document_id": "uuid | null",
  "operation": "document_ingestion | document_parsing | document_ocr | chunk_generation | embedding_generation | index_update | evaluation_run | notification_delivery",
  "requested_by": "uuid",
  "correlation_id": "uuid",
  "idempotency_key": "string (1-200 chars)",
  "attempt": "integer >= 1, default 1"
}
```

Response `200`:

```json
{ "job_id": "uuid", "correlation_id": "uuid", "status": "accepted" }
```

Response `422`: schema validation failure (unknown `operation`, missing
`idempotency_key`, etc.) — verified in `apps/worker/tests/test_main.py`.

## Worker: `GET /health`, `GET /ready`

Liveness/readiness probes for the DevOps/SRE Agent's deployment and
monitoring requirements. `ready` currently mirrors `health` because no
external dependency (Supabase, model provider) is wired yet — see
`KNOWN_LIMITATIONS.md`.

## Structured clinical answer contract

Canonical definition: `packages/clinical-schemas/src/structuredAnswer.ts`.
This is the only shape the AI Gateway may return to the application layer
once generation exists (Sprint 2+). Enforced invariants, verified by
`packages/clinical-schemas/src/structuredAnswer.test.ts`:

1. `evidence_status: "insufficient"` → `recommendations` must be empty.
2. `scope_status: "out_of_scope"` → `recommendations` must be empty.
3. Every `evidence_id` referenced by a recommendation must have a matching
   `citations[].evidence_id`.
4. `requires_clinician_review` must be the literal `true` — not a boolean
   the model can set to `false`.

Any violation throws; callers must fail closed (refuse to display), never
attempt a partial render.

## Not yet implemented (Sprint 1+)

Vercel Route Handlers for auth callbacks, upload-session creation, guideline
registration, clinical query submission/streaming, and the Supabase RPCs
(`match_approved_chunks`, `hybrid_search_chunks`,
`retrieve_recommendation_exceptions`, `retrieve_guideline_conflicts`) are
designed in the Architecture Report §11 but not yet built — see
MASTER_BACKLOG.md epics E-04, E-11, E-14, E-16.
