# ADR 0003: RLS as the authoritative authorization layer, not the only layer

**Status:** Accepted
**Source:** Master Prompt §10; Architecture Report §24.2 — "RLS is essential
but not sufficient."

## Decision

Authorization is enforced in depth: permission-aware UI, Vercel server
authorization, Supabase RLS, database constraints, and audit logging. RLS is
never bypassed for convenience, and no query path may rely solely on the UI
hiding a button.

## Consequences

Every new tenant table must ship with RLS enabled and a cross-tenant denial
test in the same pull request (see `supabase/tests/rls/`), or the QA/
Security Agent veto blocks the merge.
