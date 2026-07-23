# ADR 0004: Plain Postgres for Sprint 0 local RLS verification

**Status:** Accepted, superseded in Sprint 1
**Source:** Sprint 0 tooling constraint — this delivery environment has no
Docker daemon available, so the Supabase CLI (which orchestrates Postgres,
GoTrue, PostgREST, etc. via Docker) cannot run here.

## Decision

Migration `0001_identity_and_rls.sql` creates a Supabase-compatible
`auth.uid()` function (reading `request.jwt.claim.sub` from the session, the
same convention Supabase uses) only when a real `auth.uid()` is not already
present. This makes the migration a no-op against a real Supabase project
while allowing full RLS verification against plain local Postgres in Sprint
0 and in CI (see `.github/workflows/pr.yml`, job `database`).

## Consequences

Sprint 1 must re-run the same RLS test suite against an actual Supabase
local/staging project (via `supabase db test` or equivalent) before any
production release. The plain-Postgres suite is real, passing verification
of the RLS *logic* — it is not a substitute for exercising Supabase Auth,
PostgREST, or Storage integration.
