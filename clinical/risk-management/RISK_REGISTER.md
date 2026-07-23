# Noor V1 — Initial Risk Register (Draft)

Status: Sprint 0 draft. Owners and residual-risk sign-off pending clinical
and security partner review. Update via pull request; do not edit silently.

| ID | Risk | Category | Likelihood | Impact | Primary Control(s) | Status |
|----|------|----------|-----------|--------|--------------------|--------|
| R-01 | Outdated or withdrawn guideline remains retrievable | Clinical safety | Low | High | Knowledge lifecycle state machine; retrieval filters exclude non-`active` documents | Control designed, not yet implemented |
| R-02 | Hallucinated or unsupported clinical claim | Clinical safety | Medium | High | Context-only generation, structured-output schema, claim/citation verification, fail-closed on invalid output | Schema + safety invariants implemented (`packages/clinical-schemas`); generation pipeline not yet built |
| R-03 | Cross-tenant data access | Security | Low | Critical | RLS on every tenant table; cross-tenant test suite | Implemented and verified for identity/tenancy tables (`supabase/tests/rls`) |
| R-04 | Service-role key exposed to browser | Security | Low | Critical | Server-only config accessor (`lib/supabase/server.ts`); convention + Sprint 1 eslint boundary rule | Convention in place; automated enforcement pending |
| R-05 | Prompt injection via uploaded guideline content | Security / AI safety | Medium | High | Treat documents as untrusted data; retrieved text cannot alter system instructions | Not yet implemented — no ingestion pipeline exists yet |
| R-06 | Missing exception/contraindication in retrieved evidence | Clinical safety | Medium | High | Dedicated exception/conflict retrieval step in query pipeline | Designed (Execution Plan §11 step 14), not yet implemented |
| R-07 | Reviewer bottleneck stalls knowledge activation | Operational | Medium | Medium | Single-domain scope in V1; reviewer SLA tracked as an operational metric | Not yet instrumented |
| R-08 | Queue/worker failure silently loses a processing job | Operational | Low | Medium | Idempotent jobs, retry/backoff, dead-letter queue, manual replay | Job contract validated (`apps/worker`); queue integration not yet built |
| R-09 | Scope creep into V2–V5 capabilities during V1 | Product / governance | Medium | Medium | Explicit out-of-scope list (Execution Plan §6); Product Agent veto authority | Actively enforced in backlog scoping |
| R-10 | Provider/data-residency constraint discovered late | Operational / compliance | Medium | Medium | Sprint 0 provider spike before any generation code is written | Spike scheduled, not yet executed — no provider selected |

## Review cadence

This register must be reviewed at the end of every sprint and before any
knowledge release is activated. New risks discovered during red-team
exercises (Council §3.13) are appended, never silently absorbed into an
existing row.
