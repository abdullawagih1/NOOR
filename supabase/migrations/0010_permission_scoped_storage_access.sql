-- ============================================================================
-- Noor V1 — Migration 0010: Permission-Scoped Storage Access
-- Council: Storage Agent + Security Agent
-- ============================================================================
-- Sprint 1-D2, mandatory first task. Sprint 1-D1 documented a residual risk
-- (docs/security/extraction-review-authorization.md): migration 0003's
-- storage.objects policies authorize any active organization member to
-- read/write any object under their own org's path prefix — organization
-- membership alone, not a specific permission. Before adding OCR artifacts
-- (which must be at least as protected as extraction artifacts), this
-- migration closes that gap for the two buckets actually in use:
-- `guideline-originals` (source PDFs) and `guideline-processed` (extraction
-- + OCR artifacts).
--
-- `evaluation-assets`/`generated-reports`/`temporary-uploads` are not used
-- by any real code path yet — left on the original org-scoped policy,
-- documented as an explicit, deliberate scope decision, not an oversight.
--
-- Guarded by the same `information_schema.schemata` check as migration
-- 0003 — the `storage` schema only exists against a real Supabase stack
-- (local CLI or hosted), not the plain postgres:16 container CI uses, so
-- this entire migration is a documented no-op there (storage.objects RLS
-- can only be verified against a real Supabase stack — see
-- docs/security/ocr-and-storage-authorization.md).
-- ============================================================================

do $$
begin
  if exists (select 1 from information_schema.schemata where schema_name = 'storage') then

    drop policy if exists noor_buckets_select_own_org on storage.objects;
    drop policy if exists noor_buckets_insert_own_org on storage.objects;

    -- ------------------------------------------------------------------------
    -- guideline-originals: original source PDFs. Read requires
    -- guideline_documents.read (already held by every role that needs to see
    -- a source document, including the uploader re-verifying their own
    -- upload — see docs/domain/document-intake-lifecycle.md — and every
    -- extraction/OCR reviewer role, since all of them already hold
    -- guideline_documents.read per migrations 0006/0008/0009). Clinicians do
    -- not hold this permission and are correctly denied. Write (insert)
    -- requires guideline_documents.upload, matching the existing
    -- create_guideline_upload_session()/complete_guideline_upload() trust
    -- boundary — this is enforcement of the SAME permission at the Storage
    -- layer, not a new one.
    -- ------------------------------------------------------------------------
    execute $policy$
      create policy storage_guideline_originals_select on storage.objects
        for select using (
          bucket_id = 'guideline-originals'
          and (storage.foldername(name))[1]::uuid in (select current_active_organization_ids())
          and has_permission_in_organization((storage.foldername(name))[1]::uuid, 'guideline_documents.read')
        )
    $policy$;

    execute $policy$
      create policy storage_guideline_originals_insert on storage.objects
        for insert with check (
          bucket_id = 'guideline-originals'
          and (storage.foldername(name))[1]::uuid in (select current_active_organization_ids())
          and has_permission_in_organization((storage.foldername(name))[1]::uuid, 'guideline_documents.upload')
        )
    $policy$;

    -- ------------------------------------------------------------------------
    -- guideline-processed: extraction artifacts (Sprint 1.2B) and, from this
    -- sprint, OCR artifacts — both server/Worker-generated, both read-only
    -- from the browser's perspective. Read requires
    -- guideline_extractions.read_artifacts OR guideline_ocr.read_artifacts
    -- (the latter permission is inserted by migration 0011; a nonexistent
    -- permission key simply never matches any role, which is safe — see
    -- has_permission_in_organization). No authenticated INSERT policy exists
    -- for this bucket at all: only the Worker (service_role, which bypasses
    -- RLS entirely) ever writes here, exactly as already established for
    -- extraction artifacts — this migration does not change that, it simply
    -- never grants `authenticated` write access it never had.
    -- ------------------------------------------------------------------------
    execute $policy$
      create policy storage_guideline_processed_select on storage.objects
        for select using (
          bucket_id = 'guideline-processed'
          and (storage.foldername(name))[1]::uuid in (select current_active_organization_ids())
          and (
            has_permission_in_organization((storage.foldername(name))[1]::uuid, 'guideline_extractions.read_artifacts')
            or has_permission_in_organization((storage.foldername(name))[1]::uuid, 'guideline_ocr.read_artifacts')
          )
        )
    $policy$;

    -- ------------------------------------------------------------------------
    -- Remaining buckets: unchanged org-scoped-only behavior (not used by any
    -- real flow yet — deliberately not tightened this sprint, see
    -- docs/security/ocr-and-storage-authorization.md for the explicit scope
    -- note).
    -- ------------------------------------------------------------------------
    execute $policy$
      create policy storage_other_buckets_select_own_org on storage.objects
        for select using (
          bucket_id in ('evaluation-assets', 'generated-reports', 'temporary-uploads')
          and (storage.foldername(name))[1]::uuid in (select current_active_organization_ids())
        )
    $policy$;

    execute $policy$
      create policy storage_other_buckets_insert_own_org on storage.objects
        for insert with check (
          bucket_id in ('evaluation-assets', 'generated-reports', 'temporary-uploads')
          and (storage.foldername(name))[1]::uuid in (select current_active_organization_ids())
        )
    $policy$;

  end if;
end
$$;

-- ============================================================================
-- End of migration 0010
-- ============================================================================
