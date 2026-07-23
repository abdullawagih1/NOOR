# Architecture Decisions Log

Full ADRs live in `docs/architecture/adr/`. This file is the running index.

| ADR | Title | Status |
|-----|-------|--------|
| [0001](adr/0001-platform-split.md) | Vercel / Supabase / External Worker responsibility split | Accepted |
| [0002](adr/0002-single-nextjs-app.md) | Single Next.js app with role-based workspaces (not 4 separate apps) | Accepted |
| [0003](adr/0003-rls-first-authorization.md) | RLS as the authoritative authorization layer, not the only layer | Accepted |
| [0004](adr/0004-postgres-for-local-rls-testing.md) | Plain Postgres (not full Supabase CLI) for Sprint 0 local RLS verification | Accepted, superseded by real local Supabase CLI verification (Sprint 0 remediation session) — plain-Postgres tests kept as the fast CI path, both now run |
| [0005](adr/0005-noor-design-system.md) | Noor Design System — composition and token architecture | Accepted |
| [0006](adr/0006-nextjs-security-version-strategy.md) | Next.js security-advisory version strategy (upgrade to 15.5.21) | Accepted |

## Source of truth

These decisions consolidate the three approved source documents:
`Noor_Onboarding_Architecture_Response.docx`, the Noor V1 Parallel Team
Execution Plan, and the Noor Vercel + Supabase Production Architecture
Report. Where those documents already made a decision, the ADR here records
it rather than re-deriving it — see each ADR's "Source" field.
