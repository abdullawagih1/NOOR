-- ============================================================================
-- Fixture for the concurrent extraction-identity proof (mission §35):
-- two DIFFERENT source documents that happen to share the same byte
-- content (same sha256/size — a real, plausible scenario: the same PDF
-- uploaded against two different guideline versions), each with its own
-- claimed-and-started processing job. Two independent OS processes then
-- race to create/finalize an extraction run at the SAME deterministic
-- identity (same source_sha256 + pipeline/config/extractor versions).
-- ============================================================================

\set ON_ERROR_STOP on

create or replace function _setup_concurrent_extraction_fixture(
  out job1_id uuid, out job2_id uuid, out lease1_token text, out lease2_token text, out shared_sha256 text
)
language plpgsql as $$
declare
  v_org_id uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  v_domain_id uuid;
  v_authority_id uuid;
  v_guideline_id uuid := gen_random_uuid();
  v_version1_id uuid := gen_random_uuid();
  v_version2_id uuid := gen_random_uuid();
  v_doc1_id uuid := gen_random_uuid();
  v_doc2_id uuid := gen_random_uuid();
  v_token1 text := encode(gen_random_bytes(32), 'hex');
  v_token2 text := encode(gen_random_bytes(32), 'hex');
  v_sha256 text := encode(digest('shared-concurrent-extraction-fixture-content', 'sha256'), 'hex');
begin
  select id into v_domain_id from clinical_domains where organization_id = v_org_id limit 1;
  if v_domain_id is null then
    insert into clinical_domains (id, organization_id, code, name)
    values (gen_random_uuid(), v_org_id, 'concurrent-extraction-fixture-domain', 'Concurrent Extraction Fixture Domain')
    returning id into v_domain_id;
  end if;

  select id into v_authority_id from guideline_authorities where organization_id = v_org_id limit 1;
  if v_authority_id is null then
    insert into guideline_authorities (id, organization_id, name)
    values (gen_random_uuid(), v_org_id, 'Concurrent Extraction Fixture Authority')
    returning id into v_authority_id;
  end if;

  insert into guidelines (id, organization_id, clinical_domain_id, authority_id, internal_code, canonical_title)
  values (v_guideline_id, v_org_id, v_domain_id, v_authority_id, 'CONCUR-EXTRACT-' || substr(v_guideline_id::text, 1, 8), 'Concurrent Extraction Fixture Guideline');

  insert into guideline_versions (id, organization_id, guideline_id, version_label, lifecycle_status)
  values (v_version1_id, v_org_id, v_guideline_id, 'v1.0', 'draft'), (v_version2_id, v_org_id, v_guideline_id, 'v2.0', 'draft');

  insert into guideline_source_documents (
    id, organization_id, guideline_version_id, original_filename, normalized_filename,
    declared_media_type, detected_media_type, file_extension, size_bytes, sha256,
    storage_path, status
  ) values
    (v_doc1_id, v_org_id, v_version1_id, 'shared-content-1.pdf', 'shared-content-1.pdf', 'application/pdf', 'application/pdf', 'pdf', 1000, v_sha256, 'concur-extract/' || v_doc1_id::text || '.pdf', 'registered'),
    (v_doc2_id, v_org_id, v_version2_id, 'shared-content-2.pdf', 'shared-content-2.pdf', 'application/pdf', 'application/pdf', 'pdf', 1000, v_sha256, 'concur-extract/' || v_doc2_id::text || '.pdf', 'registered');

  insert into document_processing_jobs (id, organization_id, source_document_id, job_type, status, correlation_id, claimed_by, claimed_at, heartbeat_at, lease_token_hash, lease_acquired_at, lease_expires_at, attempt_count)
  values
    (gen_random_uuid(), v_org_id, v_doc1_id, 'document_parsing', 'claimed', gen_random_uuid(), 'concur-worker-1', now(), now(), encode(digest(v_token1, 'sha256'), 'hex'), now(), now() + interval '90 seconds', 1)
    returning id into job1_id;
  insert into document_processing_jobs (id, organization_id, source_document_id, job_type, status, correlation_id, claimed_by, claimed_at, heartbeat_at, lease_token_hash, lease_acquired_at, lease_expires_at, attempt_count)
  values
    (gen_random_uuid(), v_org_id, v_doc2_id, 'document_parsing', 'claimed', gen_random_uuid(), 'concur-worker-2', now(), now(), encode(digest(v_token2, 'sha256'), 'hex'), now(), now() + interval '90 seconds', 1)
    returning id into job2_id;

  insert into document_processing_attempts (organization_id, processing_job_id, attempt_number, worker_id, status)
  values (v_org_id, job1_id, 1, 'concur-worker-1', 'started'), (v_org_id, job2_id, 1, 'concur-worker-2', 'started');

  perform start_document_processing_job(job1_id, 'concur-worker-1', v_token1);
  perform start_document_processing_job(job2_id, 'concur-worker-2', v_token2);

  lease1_token := v_token1;
  lease2_token := v_token2;
  shared_sha256 := v_sha256;

  raise notice 'CONCURRENT EXTRACTION FIXTURE READY: job1=%, job2=%, shared_sha256=%, token1=%, token2=%', job1_id, job2_id, v_sha256, v_token1, v_token2;
end;
$$;

select * from _setup_concurrent_extraction_fixture();

drop function _setup_concurrent_extraction_fixture();
