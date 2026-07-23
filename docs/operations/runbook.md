# Operations Runbook — Sprint 0

Sprint 0 has no deployed environment yet (no live Vercel project, no live
Supabase project, no live worker deployment). This runbook documents what
exists to run **locally** and what Sprint 1 must stand up before any of the
"Production Release Phases" in the Architecture Report apply.

## Running the stack locally

1. **Database:** `createdb noor_test && psql -d noor_test -f
   supabase/migrations/0001_identity_and_rls.sql && psql -d noor_test -f
   supabase/seed.sql`
2. **Worker:** `cd apps/worker && pip install -r requirements.txt && uvicorn
   app.main:app --reload --port 8080`
3. **Web:** `cd apps/web && npm install && npm run dev`

## Health checks

* Worker liveness: `GET http://localhost:8080/health`
* Worker readiness: `GET http://localhost:8080/ready`
* Web: no health route yet — Sprint 1 (E-27 follow-up).

## Rollback

No release exists to roll back. Sprint 1 must define: Vercel deployment
rollback (redeploy previous build), Supabase migration rollback strategy
(forward-only migrations with compensating migrations, per Architecture
Report §21), and worker image rollback (previous tagged Docker image).

## Backups

Not applicable yet — no production database exists. Tracked as a Sprint 3
("Production Hardening") requirement per the Architecture Report's release
phases.

## Incident response

Not yet defined. Sprint 1 backlog includes standing up
`clinical/risk-management/` incident intake once the Quality & Safety
workspace (epic E-21) exists to surface incidents to.
