# Database Schema — Guideline Registry (Sprint 1)

Source: `supabase/migrations/0005_guideline_registry_and_lifecycle.sql`.
Updated in the same PR as any change to this migration.

## Tables

| Table | Purpose | RLS |
|---|---|---|
| `clinical_domains` | Organization-scoped clinical categories | Enabled — member read; write only via `create_clinical_domain`/`update_clinical_domain` |
| `guideline_authorities` | Guideline-producing bodies | Enabled — member read; write only via `create_guideline_authority`/`update_guideline_authority` |
| `guidelines` | Logical publication identity, spans versions | Enabled — member read; write only via `create_guideline`/`update_guideline_draft` |
| `guideline_versions` | The clinical publication lifecycle unit | Enabled — `active` versions readable by any member, all states readable with `guidelines.read_all`; write **only** via the SECURITY DEFINER functions below (no RLS write policy exists at all) |
| `guideline_reviews` | Append-only clinical review decisions | Enabled — readable by reviewer/`read_all`/own reviews; write only via `submit_guideline_review`; UPDATE/DELETE revoked + trigger-blocked |
| `guideline_lifecycle_events` | Append-only transition history | Enabled — readable by `read_all`/`audit.read`; write only via `transition_guideline_version`; UPDATE/DELETE revoked + trigger-blocked |

## Design decision: every write goes through a SECURITY DEFINER function

Every mutation — creating a domain, an authority, a guideline, a version,
submitting a review, or transitioning lifecycle status — is a narrow
Postgres function that: resolves `auth.uid()`, checks an organization-scoped
permission (`has_permission_in_organization`), performs the write(s), and
records an `audit_events` row, **atomically in one Postgres call**.

This generalizes the mission's transactional requirement for lifecycle
transitions (§9: "never perform activation using multiple unrelated
client-side writes") to every mutation that needs a paired audit record,
and avoids a real consistency gap an alternative design would have: a
client-side RLS-gated `INSERT`/`UPDATE` followed by a *separate*
service-role audit write are two different PostgREST HTTP requests with no
shared transaction — a crash or network failure between them would produce
an unaudited mutation. A single SECURITY DEFINER function call cannot have
that gap.

Consequence: **none of the six tables above has an INSERT/UPDATE/DELETE RLS
policy for `authenticated`**, and table-level INSERT/UPDATE/DELETE grants
are explicitly revoked from `authenticated` too (Supabase's platform
default privileges would otherwise grant them — see migration 0004's same
finding for `anon`). Every write not going through one of the ten
functions is rejected before it reaches a row, whether attempted via RLS
bypass, direct table grant, or malformed client code.

## Design decision: tenant integrity via composite foreign keys, not triggers

Wherever a composite foreign key can declaratively express "this reference
must belong to the same organization" (or "the same guideline"), that's
what's used, rather than a trigger re-implementing the same check
procedurally:

* `guidelines(organization_id, clinical_domain_id) → clinical_domains(organization_id, id)`
  and `→ guideline_authorities(organization_id, id)` — a guideline's domain
  and authority must be in its own organization.
* `guideline_versions(organization_id, guideline_id) → guidelines(organization_id, id)`
  — a version's organization must match its guideline's.
* `guideline_versions(guideline_id, supersedes_version_id) → guideline_versions(guideline_id, id)`
  — a version can only supersede another version **of the same guideline**.
  Organization equality follows transitively (both versions' own
  `(organization_id, guideline_id)` FK ties them to the same organization
  via the same `guideline_id`), so cross-tenant supersession is
  structurally impossible without a second explicit check.
* `guidelines(id, current_active_version_id) → guideline_versions(guideline_id, id)`
  — the guideline's pointer to its active version must actually be a
  version *of that guideline* (added via `ALTER TABLE` after
  `guideline_versions` exists, closing the circular reference).

Where a composite FK cannot express the rule, a trigger does:

* `prevent_self_review()` — a version's own creator can never submit a
  review of it, checked on every `INSERT` into `guideline_reviews`
  regardless of how the insert is attempted.
* `prevent_guideline_registry_history_mutation()` — append-only enforcement
  for `guideline_reviews` and `guideline_lifecycle_events`, for **every**
  runtime role including the table owner/`service_role` (a `REVOKE` alone
  only stops normal grant-respecting roles) — reuses the same
  `noor.allow_audit_maintenance` session GUC and documented override
  procedure `audit_events` already established in migration 0002, rather
  than inventing a second maintenance mechanism.

## Design decision: one active version per guideline is a database guarantee

```sql
create unique index guideline_versions_one_active_per_guideline
  on guideline_versions (guideline_id)
  where lifecycle_status = 'active';
```

A partial unique index, not an application check — even a direct,
privileged SQL session cannot create two simultaneously `active` versions
of the same guideline.

## Migration safety

Guarded exactly like migration 0004's `anon`-grant hardening: table/function
grants to `authenticated` are wrapped in
`if exists (select 1 from pg_roles where rolname = 'authenticated')`,
making them a documented no-op when applied to the CI plain-Postgres
container (where `authenticated` doesn't exist until the RLS test suite
creates it) and real on the hosted project (where Supabase always
provisions it). Verified for real: all statements in this migration were
applied to a fresh Postgres 16 container with zero errors, immediately
followed by the full RLS/lifecycle test suite (41 assertions, all real) —
see `docs/verification/sprint-1-guideline-registry-verification.md`.
