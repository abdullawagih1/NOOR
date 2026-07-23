-- ============================================================================
-- Noor V1 — Migration 0003: Storage Foundation (Sprint 0 scope)
-- Council: Backend/Supabase Agent + Security Agent
-- ============================================================================
-- Creates the private buckets Sprint 1 document ingestion will write into,
-- and a baseline organization-scoped RLS policy on storage.objects. Upload
-- workflows, signed-URL issuance, and per-document-type policy refinement
-- are explicitly Sprint 1 scope (see MASTER_BACKLOG.md) — this migration
-- only establishes that nothing is public and nothing is readable/writable
-- outside the caller's own organization's path prefix.
--
-- Expected object path convention (documented, not yet enforced beyond the
-- first path segment being the caller's own organization_id):
--   /{organization_id}/{clinical_domain}/{document_id}/{version}/original.pdf
--
-- Guarded by an `information_schema.schemata` check because the `storage`
-- schema only exists against a real Supabase stack (local CLI or hosted
-- project), not the plain postgres:16 container CI uses for migration/RLS
-- testing. This block is a documented no-op there — see docs/database/schema.md.
-- ============================================================================

do $$
begin
  if exists (select 1 from information_schema.schemata where schema_name = 'storage') then

    insert into storage.buckets (id, name, public, file_size_limit)
    values
      ('guideline-originals', 'guideline-originals', false, 52428800),
      ('guideline-processed', 'guideline-processed', false, 52428800),
      ('evaluation-assets', 'evaluation-assets', false, 52428800),
      ('generated-reports', 'generated-reports', false, 52428800),
      ('temporary-uploads', 'temporary-uploads', false, 52428800)
    on conflict (id) do nothing;

    -- Baseline: an active member may read/write objects only under a path
    -- whose first segment is an organization_id they belong to. No anonymous
    -- access, no cross-tenant access, no service-role usage from the browser
    -- (service-role bypasses RLS entirely and must only be used server-side).
    execute $policy$
      create policy noor_buckets_select_own_org on storage.objects
        for select using (
          bucket_id in (
            'guideline-originals', 'guideline-processed', 'evaluation-assets',
            'generated-reports', 'temporary-uploads'
          )
          and (storage.foldername(name))[1]::uuid in (select current_active_organization_ids())
        )
    $policy$;

    execute $policy$
      create policy noor_buckets_insert_own_org on storage.objects
        for insert with check (
          bucket_id in (
            'guideline-originals', 'guideline-processed', 'evaluation-assets',
            'generated-reports', 'temporary-uploads'
          )
          and (storage.foldername(name))[1]::uuid in (select current_active_organization_ids())
        )
    $policy$;

  end if;
end
$$;

-- ============================================================================
-- End of migration 0003
-- ============================================================================
