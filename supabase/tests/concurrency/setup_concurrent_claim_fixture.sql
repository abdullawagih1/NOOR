-- ============================================================================
-- Concurrency fixture: one guideline version with N registered source
-- documents, each with exactly one queued document_parsing job. Written as
-- direct inserts (not via the create_guideline_* functions) because this
-- harness exists purely to prove claim_next_document_processing_job()
-- cannot double-claim under real concurrency — it intentionally does not
-- exercise the intake business rules, which are already covered by
-- 005_document_intake.sql. Run against a database that already has
-- migrations 0001-0007 and seed.sql applied.
--
-- Usage: psql -v jobs=100 -f setup_concurrent_claim_fixture.sql
-- (defaults to 100 jobs if -v jobs=... is not passed)
--
-- The job count is passed as a plain function argument rather than
-- interpolated as :jobs inside the DO block body — psql does not perform
-- :variable substitution inside dollar-quoted ($$...$$) regions, so
-- `v_job_count int := :jobs;` inside a `do $$ ... $$` block silently fails
-- with a syntax error. Substitution works fine outside dollar-quoting, so
-- :jobs is only ever referenced in the plain top-level SELECT call below.
-- ============================================================================

\set ON_ERROR_STOP on
\if :{?jobs}
\else
  \set jobs 100
\endif

create or replace function _setup_concurrency_fixture(p_job_count int) returns void
language plpgsql as $$
declare
  v_org_id uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  v_domain_id uuid;
  v_authority_id uuid;
  v_guideline_id uuid := gen_random_uuid();
  v_version_id uuid;
  v_doc_id uuid;
  i int;
begin
  select id into v_domain_id from clinical_domains where organization_id = v_org_id limit 1;
  if v_domain_id is null then
    insert into clinical_domains (id, organization_id, code, name)
    values (gen_random_uuid(), v_org_id, 'concurrency-fixture-domain', 'Concurrency Fixture Domain')
    returning id into v_domain_id;
  end if;

  select id into v_authority_id from guideline_authorities where organization_id = v_org_id limit 1;
  if v_authority_id is null then
    insert into guideline_authorities (id, organization_id, name)
    values (gen_random_uuid(), v_org_id, 'Concurrency Fixture Authority')
    returning id into v_authority_id;
  end if;

  insert into guidelines (id, organization_id, clinical_domain_id, authority_id, internal_code, canonical_title)
  values (v_guideline_id, v_org_id, v_domain_id, v_authority_id, 'CONCUR-' || substr(v_guideline_id::text, 1, 8), 'Concurrency Fixture Guideline');

  -- One document_processing_job per source document, and the
  -- "one primary source per version" constraint means one document per
  -- version — so each job needs its own dedicated version, not a shared one.
  for i in 1..p_job_count loop
    v_version_id := gen_random_uuid();
    insert into guideline_versions (id, organization_id, guideline_id, version_label, lifecycle_status)
    values (v_version_id, v_org_id, v_guideline_id, 'concur-v' || i, 'draft');

    v_doc_id := gen_random_uuid();
    insert into guideline_source_documents (
      id, organization_id, guideline_version_id, original_filename, normalized_filename,
      declared_media_type, detected_media_type, file_extension, size_bytes, sha256,
      storage_path, status
    ) values (
      v_doc_id, v_org_id, v_version_id, 'concur-' || i || '.pdf', 'concur-' || i || '.pdf',
      'application/pdf', 'application/pdf', 'pdf', 1000, encode(digest('concur-' || i || v_version_id::text, 'sha256'), 'hex'),
      'concurrency-fixture/' || v_doc_id::text || '.pdf', 'registered'
    );

    insert into document_processing_jobs (
      id, organization_id, source_document_id, job_type, status, correlation_id
    ) values (
      gen_random_uuid(), v_org_id, v_doc_id, 'document_parsing', 'queued', gen_random_uuid()
    );
  end loop;

  raise notice 'CONCURRENCY FIXTURE READY: % queued document_parsing jobs', p_job_count;
end
$$;

select _setup_concurrency_fixture(:jobs);

drop function _setup_concurrency_fixture(int);
