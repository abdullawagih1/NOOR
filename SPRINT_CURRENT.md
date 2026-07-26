# Sprint Current: Sprint 1 — Guideline Registry Schema and Lifecycle

**Status:** Complete and Hosted-Verified. See `PROJECT_STATE.md` §-4/§0 and
`docs/verification/sprint-1-guideline-registry-verification.md`.

## Objectives

- [x] Domain model: clinical domains, guideline authorities, guidelines,
      guideline versions, clinical reviews, lifecycle events
      (`supabase/migrations/0005_guideline_registry_and_lifecycle.sql`)
- [x] Clinical publication lifecycle, database-enforced: draft →
      ready_for_review → approved → active → superseded → withdrawn, one
      canonical `transition_guideline_version()` function, one active
      version per guideline (partial unique index), review required before
      approval, self-approval and self-review blocked, released-version
      content immutable
- [x] ADR 0007 — clinical-publication and document-processing lifecycles
      kept as two separate state machines
- [x] Permission model — 12 new permissions, mapped across 6 roles
      (clinician/clinical_pharmacist read-only-active; clinical_reviewer
      reviews; knowledge_manager/organization_admin author; quality_manager
      approves/activates/supersedes/withdraws; safety_officer can also
      withdraw; auditor reads all)
- [x] RLS on all 6 new tables — clinicians see only `active` versions;
      every write mediated by a SECURITY DEFINER function, not a table
      grant (no INSERT/UPDATE/DELETE RLS policy exists for `authenticated`
      on any of the 6 tables)
- [x] Application layer — `apps/web/lib/guidelines/{schemas,actions,
      queries,errors,ui}.ts`, Zod-validated, `requirePermission`-gated,
      correlation IDs, safe typed error mapping
- [x] Minimal UI — Admin Guideline Registry (list/new/detail) at
      `/knowledge/guidelines/*` (moved off `/admin/*` mid-session — see
      PROJECT_STATE.md §-4 for why), Reviewer Queue at
      `/reviewer/guidelines`, read-only Clinician Active Knowledge at
      `/clinician/knowledge`
- [x] Tests — 41/41 real database assertions (plain Postgres 16, Docker),
      34/34 web test assertions (2 new suites: schema validation,
      error-code mapping)
- [x] Hosted Development verification — migration applied, schema
      confirmed, **18/18 real GoTrue-JWT assertions passed**, synthetic
      test data cleaned up and confirmed deleted
- [x] Vercel Preview redeployed with the new code, healthy, Deployment
      Protection confirmed still correctly enforced

## Explicitly out of scope this task (per the mission)

PDF upload, storage upload UI, processing jobs, OCR, parsing, chunking,
embeddings, vector search, LLM generation, citation rendering — see
`docs/architecture/adr/0007-separate-clinical-and-processing-lifecycles.md`.

## Next sprint

```text
Begin Sprint 1 — Secure Guideline Upload and Processing Job Foundation
```

See `MASTER_BACKLOG.md` (S1-02/S1-03). Clinical domain confirmation (G-03)
should ideally land before or alongside that task. Playwright
browser-driven E2E (G-09) stays a documented pre-Controlled-Beta
requirement, not a blocker.
