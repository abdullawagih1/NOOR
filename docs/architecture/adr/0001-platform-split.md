# ADR 0001: Vercel / Supabase / External Worker responsibility split

**Status:** Accepted
**Source:** Noor — Vercel + Supabase Production Architecture Report §3–§6; Noor V1 Parallel Team Execution Plan §5–§6

## Decision

Vercel hosts the Next.js application and owns short-running, request-scoped
work only. Supabase is the system of record for identity, tenancy, RLS,
storage, vectors, and durable job state. A separate external Python worker
owns long-running or resource-intensive processing (PDF parsing, OCR,
chunking, embedding/reranking batches, evaluation runs). AI providers supply
only bounded, controlled capabilities behind a central AI Gateway.

## Rationale

Coupling heavy document/AI processing to a single web request risks timeouts,
loses retry/traceability, and blocks safe scaling of retrieval, model, and
worker capacity independently.

## Consequences

No PDF parsing, OCR, batch embedding, or long evaluation job may ever be
implemented inside a Vercel Route Handler or Server Action. Any code review
that finds this must block the merge (Architecture Agent veto, Council §3.4).
