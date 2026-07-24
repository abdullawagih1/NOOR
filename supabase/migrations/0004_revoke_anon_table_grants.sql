-- ============================================================================
-- Noor V1 — Migration 0004: Revoke unnecessary anon table grants
-- Council: Security Agent
-- ============================================================================
-- Discovered during Sprint 0.5 hosted verification: the hosted "Noor
-- Development" project was provisioned with Supabase's legacy
-- auto_expose_new_tables default (see supabase/config.toml's own comment on
-- this — the always-revoked behavior only became the default going
-- forward, existing/newly-created projects can still inherit the old one).
-- Concretely: `anon` held DELETE/INSERT/REFERENCES/SELECT/TRIGGER/
-- TRUNCATE/UPDATE on every public table, via a project-wide `ALTER DEFAULT
-- PRIVILEGES ... GRANT ALL ON TABLES TO anon` applied at project creation.
--
-- RLS already made this a non-issue in practice — every policy requires
-- auth.uid() to resolve to an active membership, which is never true for
-- the anon role, so verified hosted testing confirmed zero rows/zero
-- mutations were ever actually reachable. But relying on RLS alone when a
-- grant-layer backstop costs nothing is unnecessary defense-in-depth
-- degradation, and mirrors the same reasoning 0001/0002 already applied to
-- audit_events (REVOKE + trigger, not RLS alone). Noor has no anonymous
-- read or write use case anywhere in its design — every real access path
-- requires a signed-in `authenticated` session.
--
-- Only `anon` is touched here. `authenticated` keeps its grants — that is
-- the standard, intended Supabase model (broad table-level grants,
-- RLS policies doing the actual row-level restriction).
-- ============================================================================

-- Guarded: the plain Postgres container CI's `database` job uses (see
-- .github/workflows/pr.yml) has no `anon` role at all — only real Supabase
-- (local CLI stack or hosted) provisions one. A documented no-op there,
-- same pattern as 0001's auth.uid() shim and 0003's storage-schema guard.
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    declare
      r record;
    begin
      for r in
        select table_name from information_schema.tables
        where table_schema = 'public' and table_type = 'BASE TABLE'
      loop
        execute format('revoke all on table public.%I from anon', r.table_name);
      end loop;
    end;

    -- Close the door for any future table created without an explicit
    -- migration-level grant, for default privileges owned by the role this
    -- migration runs as. (A separate project-bootstrap-owned default ACL
    -- entry may still exist and is outside a migration's reach — see
    -- docs/operations/hosted-supabase-setup.md for how to verify/close it
    -- via the Supabase dashboard if a future table is found to inherit
    -- anon access again.)
    execute 'alter default privileges in schema public revoke all on tables from anon';
  end if;
end
$$;

-- ============================================================================
-- End of migration 0004
-- ============================================================================
