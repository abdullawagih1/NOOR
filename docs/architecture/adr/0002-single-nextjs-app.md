# ADR 0002: Single Next.js app with role-based workspaces

**Status:** Accepted
**Source:** Architecture Report §5.1 — "The initial implementation may use one
Next.js application with role-based workspaces. Separate deployments can be
introduced later when independent release cycles, stronger isolation, or
different operational ownership justify the change."

## Decision

Sprint 0 implements `apps/web` as one Next.js application with routes
`/clinician`, `/admin`, `/reviewer`, `/quality`, gated by session + role
rather than four separate deployments.

## Rationale

Four separate apps duplicate auth wiring, design system setup, and CI/CD
before there is any evidence that independent release cycles are needed.

## Consequences

Splitting later is a routing/deployment change, not a data-model change,
because authorization is already enforced server-side and via RLS rather
than by which app happens to be running.
