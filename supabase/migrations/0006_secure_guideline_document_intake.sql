-- ============================================================================
-- Noor V1 — Migration 0006: Secure Guideline Source Document Intake
-- Council: Storage/Supabase Agent + Database Agent + Security Agent
-- ============================================================================
-- Sprint 1.1. Establishes a trusted, tenant-safe, auditable path from an
-- approved guideline version to a verified private source document and a
-- durable, idempotently-created processing job:
--
--   Guideline Version -> Authorized Upload Session -> Private Object Upload
--   -> Object Verification -> Source Document Registration
--   -> Idempotent Processing Job Creation ('queued' only)
--
-- Does NOT implement parsing/OCR/chunking/embeddings/retrieval/generation.
-- See ADR 0008 for two design decisions this migration depends on:
--
--   1. Three separate state machines (clinical publication / upload session
--      / processing job) — never merged, mirroring ADR 0007's reasoning one
--      level deeper.
--   2. Postgres cannot read Storage object bytes, so file facts (size,
--      PDF signature, SHA-256) are COMPUTED by the Next.js server (which
--      independently re-fetches the object via the caller's own RLS-scoped
--      session, never trusting the browser) and passed as INPUT parameters
--      to complete_guideline_upload() — a deliberate shape difference from
--      migration 0005's functions, which computed everything from
--      database-visible state alone.
--
-- Reuses migration 0005's patterns throughout: every write is mediated by a
-- SECURITY DEFINER function (assert_permission/record_audit_event reused
-- directly, not redefined); tenant/parent integrity via composite foreign
-- keys wherever declarative; append-only history via the same
-- prevent_guideline_registry_history_mutation() trigger function and
-- noor.allow_audit_maintenance override, reused directly rather than
-- duplicated a third time.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. GUIDELINE SOURCE DOCUMENTS
-- ----------------------------------------------------------------------------

create table if not exists guideline_source_documents (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  guideline_version_id uuid not null,

  document_role text not null default 'primary_guideline'
    check (document_role in ('primary_guideline', 'appendix', 'supplement', 'correction', 'supporting_material')),
  original_filename text not null,
  normalized_filename text not null,
  declared_media_type text not null,
  detected_media_type text,
  file_extension text not null,
  size_bytes bigint,
  sha256 text,

  storage_bucket text not null default 'guideline-originals',
  storage_path text not null,

  -- Collapses the mission's suggested "registration_status" +
  -- "verification_status" into one column (see ADR 0008) — registered is
  -- always downstream of verified in this slice, not an independently
  -- varying dimension.
  status text not null default 'pending_upload'
    check (status in ('pending_upload', 'uploaded', 'verified', 'registered', 'rejected', 'quarantined')),
  rejection_reason text,

  is_primary_source boolean not null default true,
  source_url text,
  external_identifier text,

  uploaded_by uuid references auth.users(id),
  uploaded_at timestamptz,
  verified_by uuid references auth.users(id),
  verified_at timestamptz,
  registered_by uuid references auth.users(id),
  registered_at timestamptz,

  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id),

  unique (organization_id, id),
  unique (storage_bucket, storage_path),
  foreign key (organization_id, guideline_version_id) references guideline_versions (organization_id, id),
  check (size_bytes is null or size_bytes > 0),
  check (status <> 'rejected' or rejection_reason is not null),
  check (status <> 'quarantined' or rejection_reason is not null)
);

-- Exactly one non-rejected/non-quarantined primary source per version —
-- released-version immutability (Sprint 1.1 mission §8/§9.1) is enforced
-- by this index plus the eligibility check inside
-- create_guideline_upload_session(), not by application code alone.
create unique index if not exists guideline_source_documents_one_primary_per_version
  on guideline_source_documents (guideline_version_id)
  where document_role = 'primary_guideline' and status not in ('rejected', 'quarantined');

create index if not exists idx_source_documents_org_version on guideline_source_documents (organization_id, guideline_version_id);
create index if not exists idx_source_documents_sha256 on guideline_source_documents (organization_id, sha256) where sha256 is not null;

-- Immutability: once a document has been verified/registered, its file
-- identity (checksum, storage location, detected type) can never change —
-- a corrected source means a new guideline version, never an in-place edit.
-- Fires regardless of caller/role (BEFORE UPDATE trigger keyed on OLD.status,
-- not on who is asking) — the same immutability guarantee style as
-- guideline_versions in migration 0005, applied here via trigger because,
-- unlike guideline_versions, this table DOES need in-place UPDATEs for the
-- pending_upload -> verified/rejected transition itself.
create or replace function prevent_verified_source_document_mutation()
returns trigger
language plpgsql
as $$
begin
  if old.status in ('verified', 'registered') then
    if new.sha256 is distinct from old.sha256
       or new.storage_path is distinct from old.storage_path
       or new.storage_bucket is distinct from old.storage_bucket
       or new.detected_media_type is distinct from old.detected_media_type then
      raise exception 'a verified or registered source document''s file identity cannot be changed; create a new guideline version instead'
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prevent_verified_source_document_mutation on guideline_source_documents;
create trigger trg_prevent_verified_source_document_mutation
  before update on guideline_source_documents
  for each row execute function prevent_verified_source_document_mutation();

-- ----------------------------------------------------------------------------
-- 2. UPLOAD SESSIONS
-- ----------------------------------------------------------------------------
-- Session states are deliberately fewer than the mission's suggested
-- 8-state list (created/authorized/uploaded/verified/completed/expired/
-- rejected/cancelled) — "uploaded" and "verified" are tracked on the
-- DOCUMENT instead (guideline_source_documents.status), since verification
-- is a fact about the file, not the authorization. See ADR 0008.

create table if not exists document_upload_sessions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  guideline_version_id uuid not null,
  source_document_id uuid not null,

  requested_filename text not null,
  expected_media_type text not null,
  expected_size_bytes bigint,
  expected_sha256 text,

  storage_bucket text not null,
  storage_path text not null,

  status text not null default 'created'
    check (status in ('created', 'authorized', 'completed', 'expired', 'rejected', 'cancelled')),
  expires_at timestamptz not null,
  completed_at timestamptz,
  rejected_at timestamptz,
  rejection_reason text,

  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  correlation_id uuid not null,
  idempotency_key text,

  unique (organization_id, id),
  unique (organization_id, idempotency_key),
  foreign key (organization_id, guideline_version_id) references guideline_versions (organization_id, id),
  foreign key (organization_id, source_document_id) references guideline_source_documents (organization_id, id)
);

create index if not exists idx_upload_sessions_org_version on document_upload_sessions (organization_id, guideline_version_id);
create index if not exists idx_upload_sessions_document on document_upload_sessions (source_document_id);

-- ----------------------------------------------------------------------------
-- 3. PROCESSING JOBS
-- ----------------------------------------------------------------------------
-- job_type = 'document_parsing' reuses the Worker's EXISTING JobOperation
-- literal (apps/worker/app/main.py) rather than the mission's suggested
-- 'document_extraction' name — see ADR 0008. Single-value CHECK is
-- deliberate: only this one job type is ever created in this migration;
-- widen the CHECK in a future migration alongside whatever job type it adds.

create table if not exists document_processing_jobs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  source_document_id uuid not null,

  job_type text not null default 'document_parsing'
    check (job_type in ('document_parsing')),
  pipeline_version text not null default 'v1',
  status text not null default 'queued'
    check (status in ('queued', 'claimed', 'processing', 'succeeded', 'failed', 'cancelled', 'dead_lettered')),
  priority int not null default 100,

  idempotency_key text,
  queue_message_id text,

  requested_by uuid references auth.users(id),
  requested_at timestamptz not null default now(),

  -- Workers are not Supabase Auth users — a free-form identifier, not a FK.
  claimed_by text,
  claimed_at timestamptz,
  heartbeat_at timestamptz,

  started_at timestamptz,
  completed_at timestamptz,
  failed_at timestamptz,
  cancelled_at timestamptz,

  attempt_count int not null default 0,
  max_attempts int not null default 3,

  error_code text,
  error_message_safe text,
  error_metadata jsonb not null default '{}'::jsonb,

  correlation_id uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id, id),
  unique (organization_id, idempotency_key),
  foreign key (organization_id, source_document_id) references guideline_source_documents (organization_id, id)
);

-- No two simultaneously active jobs for the same document+type — a database
-- guarantee (Sprint 1.1 mission §16/§21), not an application check.
create unique index if not exists document_processing_jobs_one_active_per_document_type
  on document_processing_jobs (source_document_id, job_type)
  where status in ('queued', 'claimed', 'processing');

create index if not exists idx_processing_jobs_org_status on document_processing_jobs (organization_id, status);

-- ----------------------------------------------------------------------------
-- 4. PROCESSING ATTEMPTS (foundation only — stays empty this migration)
-- ----------------------------------------------------------------------------

create table if not exists document_processing_attempts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  processing_job_id uuid not null,
  attempt_number int not null,
  worker_id text,
  status text not null check (status in ('started', 'succeeded', 'failed')),
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  error_code text,
  error_message_safe text,
  metrics jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),

  unique (organization_id, id),
  unique (processing_job_id, attempt_number),
  foreign key (organization_id, processing_job_id) references document_processing_jobs (organization_id, id)
);

-- ----------------------------------------------------------------------------
-- 5. DOCUMENT INTAKE EVENTS (append-only; integrates with audit_events)
-- ----------------------------------------------------------------------------

create table if not exists document_intake_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  source_document_id uuid,
  upload_session_id uuid,
  processing_job_id uuid,
  event_type text not null,
  actor_id uuid references auth.users(id),
  correlation_id uuid not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),

  foreign key (organization_id, source_document_id) references guideline_source_documents (organization_id, id),
  foreign key (organization_id, upload_session_id) references document_upload_sessions (organization_id, id),
  foreign key (organization_id, processing_job_id) references document_processing_jobs (organization_id, id)
);

create index if not exists idx_intake_events_document on document_intake_events (source_document_id, created_at desc);
create index if not exists idx_intake_events_correlation on document_intake_events (correlation_id);

-- Reuses migration 0005's generic append-only trigger function directly
-- (it keys off TG_TABLE_NAME, not a table-specific assumption) rather than
-- defining a third copy of the same override procedure.
revoke update, delete on document_intake_events from public;

drop trigger if exists trg_document_intake_events_no_update on document_intake_events;
create trigger trg_document_intake_events_no_update
  before update on document_intake_events
  for each row execute function prevent_guideline_registry_history_mutation();

drop trigger if exists trg_document_intake_events_no_delete on document_intake_events;
create trigger trg_document_intake_events_no_delete
  before delete on document_intake_events
  for each row execute function prevent_guideline_registry_history_mutation();

-- ============================================================================
-- 6. PERMISSIONS
-- ============================================================================

insert into permissions (key, description) values
  ('guideline_documents.read', 'Read guideline source document records and their status'),
  ('guideline_documents.upload', 'Create upload sessions and complete guideline source-document uploads'),
  ('guideline_documents.verify', 'Reserved for a future manual re-verification workflow'),
  ('guideline_documents.reject', 'Quarantine a registered guideline source document'),
  ('guideline_documents.register', 'Reserved — registration currently happens automatically on verified upload, gated by guideline_documents.upload'),
  ('guideline_processing_jobs.read', 'Read document processing job status'),
  ('guideline_processing_jobs.create', 'Reserved — job creation currently happens automatically on verified upload, gated by guideline_documents.upload'),
  ('guideline_processing_jobs.cancel', 'Cancel a queued document processing job')
on conflict (key) do nothing;

-- clinician: no document-intake permissions at all (mission §19) — they
-- never receive a private Storage path. safety_officer additionally gets
-- guideline_documents.reject, consistent with the same "can withdraw/
-- quarantine to contain a discovered problem" extension migration 0005
-- gave it for guidelines.withdraw.
insert into role_permissions (role_id, permission_id)
select r.id, p.id
from (values
  ('knowledge_manager', 'guideline_documents.read'),
  ('knowledge_manager', 'guideline_documents.upload'),
  ('knowledge_manager', 'guideline_documents.register'),
  ('knowledge_manager', 'guideline_processing_jobs.read'),
  ('knowledge_manager', 'guideline_processing_jobs.create'),
  ('organization_admin', 'guideline_documents.read'),
  ('organization_admin', 'guideline_documents.upload'),
  ('organization_admin', 'guideline_documents.register'),
  ('organization_admin', 'guideline_processing_jobs.read'),
  ('organization_admin', 'guideline_processing_jobs.create'),
  ('clinical_reviewer', 'guideline_documents.read'),
  ('clinical_reviewer', 'guideline_processing_jobs.read'),
  ('quality_manager', 'guideline_documents.read'),
  ('quality_manager', 'guideline_documents.verify'),
  ('quality_manager', 'guideline_documents.reject'),
  ('quality_manager', 'guideline_processing_jobs.read'),
  ('quality_manager', 'guideline_processing_jobs.cancel'),
  ('safety_officer', 'guideline_documents.read'),
  ('safety_officer', 'guideline_documents.reject'),
  ('auditor', 'guideline_documents.read'),
  ('auditor', 'guideline_processing_jobs.read')
) as mapping(role_key, permission_key)
join roles r on r.key = mapping.role_key
join permissions p on p.key = mapping.permission_key
on conflict (role_id, permission_id) do nothing;

-- ============================================================================
-- 7. RLS
-- ============================================================================

alter table guideline_source_documents enable row level security;
alter table document_upload_sessions enable row level security;
alter table document_processing_jobs enable row level security;
alter table document_processing_attempts enable row level security;
alter table document_intake_events enable row level security;

-- Read-only for authenticated. Every write is mediated by a SECURITY
-- DEFINER function (section 9) — no INSERT/UPDATE/DELETE RLS policy exists
-- on any of these five tables, matching migration 0005's write model
-- exactly. Clinicians hold no guideline_documents.* / guideline_processing_jobs.*
-- permission at all, so they match none of these policies — they see
-- nothing here, structurally, not by UI omission.

create policy guideline_source_documents_select on guideline_source_documents
  for select using (has_permission_in_organization(organization_id, 'guideline_documents.read'));

create policy document_upload_sessions_select on document_upload_sessions
  for select using (has_permission_in_organization(organization_id, 'guideline_documents.read'));

create policy document_processing_jobs_select on document_processing_jobs
  for select using (has_permission_in_organization(organization_id, 'guideline_processing_jobs.read'));

create policy document_processing_attempts_select on document_processing_attempts
  for select using (has_permission_in_organization(organization_id, 'guideline_processing_jobs.read'));

create policy document_intake_events_select on document_intake_events
  for select using (
    has_permission_in_organization(organization_id, 'guideline_documents.read')
    or has_permission_in_organization(organization_id, 'audit.read')
  );

-- ============================================================================
-- 8. GRANTS — guarded exactly like migration 0005 section 9 (no-op at
-- CI plain-Postgres migration-apply time; real on hosted).
-- ============================================================================

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant select on guideline_source_documents, document_upload_sessions,
      document_processing_jobs, document_processing_attempts, document_intake_events
      to authenticated;
    revoke insert, update, delete on guideline_source_documents, document_upload_sessions,
      document_processing_jobs, document_processing_attempts, document_intake_events
      from authenticated;
  end if;
end
$$;

-- ============================================================================
-- 9. FUNCTIONS
-- ============================================================================
-- Reuses assert_permission() and record_audit_event() from migration 0005
-- directly — not redefined. Every function here follows the same
-- `revoke all from public` + consolidated guarded `grant execute to
-- authenticated` pattern as 0005 section 10.

-- ----------------------------------------------------------------------------
-- 9.1 createGuidelineUploadSession
-- ----------------------------------------------------------------------------

create or replace function create_guideline_upload_session(
  p_guideline_version_id uuid,
  p_filename text,
  p_declared_media_type text,
  p_expected_size_bytes bigint default null,
  p_expected_sha256 text default null,
  p_idempotency_key text default null,
  p_correlation_id uuid default gen_random_uuid()
) returns table (
  upload_session_id uuid,
  source_document_id uuid,
  storage_bucket text,
  storage_path text,
  expires_at timestamptz,
  status text
)
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_version guideline_versions%rowtype;
  v_org uuid;
  v_existing_session document_upload_sessions%rowtype;
  v_existing_primary_count int;
  v_document_id uuid;
  v_session_id uuid;
  v_safe_filename text;
  v_extension text;
  v_path text;
  v_expires_at timestamptz;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select * into v_version from guideline_versions where id = p_guideline_version_id;
  if not found then
    raise exception 'guideline version not found: %', p_guideline_version_id;
  end if;
  v_org := v_version.organization_id;

  perform assert_permission(v_org, 'guideline_documents.upload');

  -- Idempotency: a replayed request with the same key returns the existing
  -- session untouched, no new document/session created.
  if p_idempotency_key is not null then
    select * into v_existing_session from document_upload_sessions
      where organization_id = v_org and idempotency_key = p_idempotency_key;
    if found then
      return query select v_existing_session.id, v_existing_session.source_document_id,
        v_existing_session.storage_bucket, v_existing_session.storage_path,
        v_existing_session.expires_at, v_existing_session.status;
      return;
    end if;
  end if;

  -- Eligibility (Sprint 1.1 mission §8): only draft/ready_for_review/
  -- approved versions may receive a NEW primary source. active/superseded/
  -- withdrawn never can — released versions are immutable; a different
  -- source means a new guideline version.
  if v_version.lifecycle_status not in ('draft', 'ready_for_review', 'approved') then
    raise exception 'guideline version status % is not eligible for a new source document upload', v_version.lifecycle_status;
  end if;

  -- Table-qualified: this function's RETURNS TABLE includes an OUT
  -- parameter also named `status`, which PL/pgSQL would otherwise treat as
  -- ambiguous against the table column of the same name.
  select count(*) into v_existing_primary_count from guideline_source_documents
    where guideline_version_id = p_guideline_version_id
      and document_role = 'primary_guideline'
      and guideline_source_documents.status not in ('rejected', 'quarantined');
  if v_existing_primary_count > 0 then
    raise exception 'this guideline version already has an active primary source document; it cannot be replaced — create a new guideline version instead';
  end if;

  if p_filename is null or btrim(p_filename) = '' then
    raise exception 'filename is required';
  end if;
  v_extension := lower(substring(p_filename from '\.([^.]+)$'));
  -- Canonical size limit (50 MB / 52428800 bytes) — MUST be kept in sync
  -- with MAX_UPLOAD_SIZE_BYTES in apps/web/lib/documents/config.ts; a test
  -- asserts they match (apps/web/tests/documents-config.test.ts).
  if v_extension is distinct from 'pdf' or p_declared_media_type <> 'application/pdf' then
    raise exception 'only application/pdf (.pdf) is supported in this release';
  end if;
  if p_expected_size_bytes is not null and (p_expected_size_bytes <= 0 or p_expected_size_bytes > 52428800) then
    raise exception 'expected_size_bytes must be between 1 and 52428800 (50 MB)';
  end if;

  v_safe_filename := regexp_replace(p_filename, '[^A-Za-z0-9._-]', '_', 'g');
  v_document_id := gen_random_uuid();
  v_session_id := gen_random_uuid();
  v_expires_at := now() + interval '30 minutes';
  v_path := v_org::text || '/guidelines/' || v_version.guideline_id::text || '/versions/' ||
    p_guideline_version_id::text || '/documents/' || v_document_id::text || '/original/' || v_safe_filename;

  insert into guideline_source_documents (
    id, organization_id, guideline_version_id, document_role, original_filename, normalized_filename,
    declared_media_type, file_extension, storage_bucket, storage_path, status,
    created_by, updated_by
  ) values (
    v_document_id, v_org, p_guideline_version_id, 'primary_guideline', p_filename, v_safe_filename,
    p_declared_media_type, v_extension, 'guideline-originals', v_path, 'pending_upload',
    v_actor, v_actor
  );

  insert into document_upload_sessions (
    id, organization_id, guideline_version_id, source_document_id, requested_filename,
    expected_media_type, expected_size_bytes, expected_sha256, storage_bucket, storage_path,
    status, expires_at, created_by, correlation_id, idempotency_key
  ) values (
    v_session_id, v_org, p_guideline_version_id, v_document_id, p_filename,
    p_declared_media_type, p_expected_size_bytes, p_expected_sha256, 'guideline-originals', v_path,
    'authorized', v_expires_at, v_actor, p_correlation_id, p_idempotency_key
  );

  insert into document_intake_events (organization_id, source_document_id, upload_session_id, event_type, actor_id, correlation_id, metadata)
  values (v_org, v_document_id, v_session_id, 'guideline_document.upload_session_created', v_actor, p_correlation_id,
    jsonb_build_object('guideline_version_id', p_guideline_version_id));
  perform record_audit_event(v_org, 'guideline_document.upload_session_created', 'guideline_source_document', v_document_id, p_correlation_id,
    jsonb_build_object('guideline_version_id', p_guideline_version_id, 'declared_media_type', p_declared_media_type));

  insert into document_intake_events (organization_id, source_document_id, upload_session_id, event_type, actor_id, correlation_id, metadata)
  values (v_org, v_document_id, v_session_id, 'guideline_document.upload_authorized', v_actor, p_correlation_id, '{}'::jsonb);
  perform record_audit_event(v_org, 'guideline_document.upload_authorized', 'guideline_source_document', v_document_id, p_correlation_id, '{}'::jsonb);

  return query select v_session_id, v_document_id, 'guideline-originals'::text, v_path, v_expires_at, 'authorized'::text;
end;
$$;

revoke all on function create_guideline_upload_session(uuid, text, text, bigint, text, text, uuid) from public;

-- ----------------------------------------------------------------------------
-- 9.2 completeGuidelineUpload
-- ----------------------------------------------------------------------------
-- p_detected_media_type / p_size_bytes / p_sha256 are INPUTS, computed by
-- the calling Next.js server after independently re-fetching the object
-- from Storage — see ADR 0008 for why this function cannot compute them
-- itself. p_rejection_reason non-null short-circuits straight to a
-- rejection (used when the server's own signature/size check already
-- failed before this call).

create or replace function complete_guideline_upload(
  p_upload_session_id uuid,
  p_detected_media_type text,
  p_size_bytes bigint,
  p_sha256 text,
  p_rejection_reason text default null,
  p_correlation_id uuid default gen_random_uuid()
) returns table (
  source_document_id uuid,
  document_status text,
  session_status text,
  processing_job_id uuid,
  duplicate_of_document_id uuid
)
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_session document_upload_sessions%rowtype;
  v_document guideline_source_documents%rowtype;
  v_org uuid;
  v_final_rejection text := p_rejection_reason;
  v_duplicate_id uuid;
  v_job_id uuid;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select * into v_session from document_upload_sessions where id = p_upload_session_id for update;
  if not found then
    raise exception 'upload session not found: %', p_upload_session_id;
  end if;
  v_org := v_session.organization_id;

  perform assert_permission(v_org, 'guideline_documents.upload');

  -- Idempotent replay: a session already in a terminal state returns its
  -- existing outcome rather than re-processing (mission §16).
  if v_session.status in ('completed', 'rejected', 'expired', 'cancelled') then
    select * into v_document from guideline_source_documents where id = v_session.source_document_id;
    -- Table-qualified: this function's RETURNS TABLE includes an OUT
    -- parameter also named `source_document_id`, otherwise ambiguous
    -- against the table column of the same name (same class of bug as
    -- create_guideline_upload_session's `status` shadowing above).
    select id into v_job_id from document_processing_jobs
      where document_processing_jobs.source_document_id = v_session.source_document_id
        and status in ('queued', 'claimed', 'processing', 'succeeded')
      order by created_at desc limit 1;
    return query select v_document.id, v_document.status, v_session.status, v_job_id, null::uuid;
    return;
  end if;

  select * into v_document from guideline_source_documents where id = v_session.source_document_id for update;

  if v_session.expires_at < now() then
    update document_upload_sessions set status = 'expired', updated_at = now() where id = p_upload_session_id;
    update guideline_source_documents set status = 'rejected', rejection_reason = 'upload session expired', updated_at = now(), updated_by = v_actor
      where id = v_document.id;
    insert into document_intake_events (organization_id, source_document_id, upload_session_id, event_type, actor_id, correlation_id, metadata)
      values (v_org, v_document.id, p_upload_session_id, 'guideline_document.rejected', v_actor, p_correlation_id, jsonb_build_object('reason', 'expired'));
    perform record_audit_event(v_org, 'guideline_document.rejected', 'guideline_source_document', v_document.id, p_correlation_id, jsonb_build_object('reason', 'expired'));
    return query select v_document.id, 'rejected'::text, 'expired'::text, null::uuid, null::uuid;
    return;
  end if;

  insert into document_intake_events (organization_id, source_document_id, upload_session_id, event_type, actor_id, correlation_id, metadata)
    values (v_org, v_document.id, p_upload_session_id, 'guideline_document.verification_started', v_actor, p_correlation_id, '{}'::jsonb);

  -- Duplicate within the same guideline version: reject (mission §15).
  if v_final_rejection is null then
    select id into v_duplicate_id from guideline_source_documents
      where guideline_version_id = v_document.guideline_version_id
        and id <> v_document.id
        and sha256 = p_sha256
        and status not in ('rejected', 'quarantined')
      limit 1;
    if v_duplicate_id is not null then
      v_final_rejection := 'duplicate of an existing source document for this guideline version';
    end if;
  end if;

  -- Duplicate across versions in the SAME organization: allowed, but
  -- explicitly recorded, never blocking. Cross-organization duplicates are
  -- structurally invisible to this query (scoped to v_org) — no
  -- information side channel is possible (mission §15).
  if v_final_rejection is null then
    if exists (
      select 1 from guideline_source_documents
      where organization_id = v_org and guideline_version_id <> v_document.guideline_version_id
        and sha256 = p_sha256 and status not in ('rejected', 'quarantined')
    ) then
      insert into document_intake_events (organization_id, source_document_id, upload_session_id, event_type, actor_id, correlation_id, metadata)
        values (v_org, v_document.id, p_upload_session_id, 'guideline_document.duplicate_detected', v_actor, p_correlation_id,
          jsonb_build_object('scope', 'same_organization_other_version'));
      perform record_audit_event(v_org, 'guideline_document.duplicate_detected', 'guideline_source_document', v_document.id, p_correlation_id,
        jsonb_build_object('scope', 'same_organization_other_version'));
    end if;
  end if;

  if v_final_rejection is not null then
    update guideline_source_documents set
      status = 'rejected', rejection_reason = v_final_rejection,
      detected_media_type = p_detected_media_type, size_bytes = p_size_bytes, sha256 = p_sha256,
      uploaded_by = v_actor, uploaded_at = now(), updated_at = now(), updated_by = v_actor
      where id = v_document.id;
    update document_upload_sessions set status = 'rejected', rejected_at = now(), rejection_reason = v_final_rejection, updated_at = now()
      where id = p_upload_session_id;

    insert into document_intake_events (organization_id, source_document_id, upload_session_id, event_type, actor_id, correlation_id, metadata)
      values (v_org, v_document.id, p_upload_session_id, 'guideline_document.rejected', v_actor, p_correlation_id, jsonb_build_object('reason', v_final_rejection));
    perform record_audit_event(v_org, 'guideline_document.rejected', 'guideline_source_document', v_document.id, p_correlation_id, jsonb_build_object('reason', v_final_rejection));

    return query select v_document.id, 'rejected'::text, 'rejected'::text, null::uuid, v_duplicate_id;
    return;
  end if;

  -- Accepted: verify, register, and queue processing atomically.
  update guideline_source_documents set
    status = 'registered',
    detected_media_type = p_detected_media_type, size_bytes = p_size_bytes, sha256 = p_sha256,
    uploaded_by = v_actor, uploaded_at = now(),
    verified_by = v_actor, verified_at = now(),
    registered_by = v_actor, registered_at = now(),
    updated_at = now(), updated_by = v_actor
    where id = v_document.id;

  update document_upload_sessions set status = 'completed', completed_at = now(), updated_at = now()
    where id = p_upload_session_id;

  insert into document_processing_jobs (
    organization_id, source_document_id, job_type, status, requested_by, correlation_id, idempotency_key
  ) values (
    v_org, v_document.id, 'document_parsing', 'queued', v_actor, p_correlation_id, 'intake:' || v_document.id::text
  )
  on conflict (organization_id, idempotency_key) do update set updated_at = now()
  returning id into v_job_id;

  insert into document_intake_events (organization_id, source_document_id, upload_session_id, processing_job_id, event_type, actor_id, correlation_id, metadata)
    values (v_org, v_document.id, p_upload_session_id, v_job_id, 'guideline_document.verified', v_actor, p_correlation_id,
      jsonb_build_object('sha256_prefix', left(p_sha256, 12), 'size_bytes', p_size_bytes));
  perform record_audit_event(v_org, 'guideline_document.verified', 'guideline_source_document', v_document.id, p_correlation_id,
    jsonb_build_object('sha256_prefix', left(p_sha256, 12), 'size_bytes', p_size_bytes, 'media_type', p_detected_media_type));

  insert into document_intake_events (organization_id, source_document_id, upload_session_id, processing_job_id, event_type, actor_id, correlation_id, metadata)
    values (v_org, v_document.id, p_upload_session_id, v_job_id, 'guideline_document.registered', v_actor, p_correlation_id, '{}'::jsonb);
  perform record_audit_event(v_org, 'guideline_document.registered', 'guideline_source_document', v_document.id, p_correlation_id, '{}'::jsonb);

  insert into document_intake_events (organization_id, source_document_id, processing_job_id, event_type, actor_id, correlation_id, metadata)
    values (v_org, v_document.id, v_job_id, 'document_processing_job.created', v_actor, p_correlation_id, jsonb_build_object('job_type', 'document_parsing'));
  perform record_audit_event(v_org, 'document_processing_job.created', 'document_processing_job', v_job_id, p_correlation_id, jsonb_build_object('job_type', 'document_parsing'));

  return query select v_document.id, 'registered'::text, 'completed'::text, v_job_id, null::uuid;
end;
$$;

revoke all on function complete_guideline_upload(uuid, text, bigint, text, text, uuid) from public;

-- ----------------------------------------------------------------------------
-- 9.3 cancelUploadSession
-- ----------------------------------------------------------------------------

create or replace function cancel_upload_session(
  p_upload_session_id uuid,
  p_reason text default null,
  p_correlation_id uuid default gen_random_uuid()
) returns document_upload_sessions
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_session document_upload_sessions%rowtype;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select * into v_session from document_upload_sessions where id = p_upload_session_id for update;
  if not found then
    raise exception 'upload session not found: %', p_upload_session_id;
  end if;

  perform assert_permission(v_session.organization_id, 'guideline_documents.upload');

  if v_session.status not in ('created', 'authorized') then
    raise exception 'only a created/authorized session can be cancelled (current status: %)', v_session.status;
  end if;

  update document_upload_sessions set
    status = 'cancelled', rejected_at = now(), rejection_reason = coalesce(p_reason, 'cancelled by user'), updated_at = now()
    where id = p_upload_session_id
    returning * into v_session;

  update guideline_source_documents set
    status = 'rejected', rejection_reason = coalesce(p_reason, 'upload cancelled'), updated_at = now(), updated_by = v_actor
    where id = v_session.source_document_id and status = 'pending_upload';

  insert into document_intake_events (organization_id, source_document_id, upload_session_id, event_type, actor_id, correlation_id, metadata)
    values (v_session.organization_id, v_session.source_document_id, p_upload_session_id, 'guideline_document.rejected', v_actor, p_correlation_id, jsonb_build_object('reason', 'cancelled'));
  perform record_audit_event(v_session.organization_id, 'guideline_document.rejected', 'guideline_source_document', v_session.source_document_id, p_correlation_id, jsonb_build_object('reason', 'cancelled'));

  return v_session;
end;
$$;

revoke all on function cancel_upload_session(uuid, text, uuid) from public;

-- ----------------------------------------------------------------------------
-- 9.4 quarantineGuidelineSourceDocument (manual QA override)
-- ----------------------------------------------------------------------------

create or replace function quarantine_guideline_source_document(
  p_source_document_id uuid,
  p_reason text,
  p_correlation_id uuid default gen_random_uuid()
) returns guideline_source_documents
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_document guideline_source_documents%rowtype;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if p_reason is null or btrim(p_reason) = '' then
    raise exception 'a reason is required to quarantine a source document';
  end if;

  select * into v_document from guideline_source_documents where id = p_source_document_id for update;
  if not found then
    raise exception 'source document not found: %', p_source_document_id;
  end if;

  perform assert_permission(v_document.organization_id, 'guideline_documents.reject');

  update guideline_source_documents set status = 'quarantined', rejection_reason = p_reason, updated_at = now(), updated_by = v_actor
    where id = p_source_document_id
    returning * into v_document;

  update document_processing_jobs set status = 'cancelled', cancelled_at = now(), updated_at = now()
    where source_document_id = p_source_document_id and status in ('queued', 'claimed', 'processing');

  insert into document_intake_events (organization_id, source_document_id, event_type, actor_id, correlation_id, metadata)
    values (v_document.organization_id, p_source_document_id, 'guideline_document.rejected', v_actor, p_correlation_id, jsonb_build_object('reason', p_reason, 'action', 'quarantine'));
  perform record_audit_event(v_document.organization_id, 'guideline_document.rejected', 'guideline_source_document', p_source_document_id, p_correlation_id, jsonb_build_object('reason', p_reason, 'action', 'quarantine'));

  return v_document;
end;
$$;

revoke all on function quarantine_guideline_source_document(uuid, text, uuid) from public;

-- ----------------------------------------------------------------------------
-- 9.5 cancelQueuedProcessingJob
-- ----------------------------------------------------------------------------

create or replace function cancel_processing_job(
  p_processing_job_id uuid,
  p_reason text default null,
  p_correlation_id uuid default gen_random_uuid()
) returns document_processing_jobs
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_job document_processing_jobs%rowtype;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select * into v_job from document_processing_jobs where id = p_processing_job_id for update;
  if not found then
    raise exception 'processing job not found: %', p_processing_job_id;
  end if;

  perform assert_permission(v_job.organization_id, 'guideline_processing_jobs.cancel');

  if v_job.status <> 'queued' then
    raise exception 'only a queued job can be cancelled (current status: %)', v_job.status;
  end if;

  update document_processing_jobs set status = 'cancelled', cancelled_at = now(), updated_at = now()
    where id = p_processing_job_id
    returning * into v_job;

  insert into document_intake_events (organization_id, processing_job_id, event_type, actor_id, correlation_id, metadata)
    values (v_job.organization_id, p_processing_job_id, 'document_processing_job.cancelled', v_actor, p_correlation_id, jsonb_build_object('reason', p_reason));
  perform record_audit_event(v_job.organization_id, 'document_processing_job.cancelled', 'document_processing_job', p_processing_job_id, p_correlation_id, jsonb_build_object('reason', p_reason));

  return v_job;
end;
$$;

revoke all on function cancel_processing_job(uuid, text, uuid) from public;

-- ----------------------------------------------------------------------------
-- 9.6 Consolidated EXECUTE grants (guarded — see the note at the top of
-- migration 0005 section 10 for why this cannot be inline per-function).
-- ----------------------------------------------------------------------------

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function
      create_guideline_upload_session(uuid, text, text, bigint, text, text, uuid),
      complete_guideline_upload(uuid, text, bigint, text, text, uuid),
      cancel_upload_session(uuid, text, uuid),
      quarantine_guideline_source_document(uuid, text, uuid),
      cancel_processing_job(uuid, text, uuid)
      to authenticated;
  end if;
end
$$;

-- ============================================================================
-- End of migration 0006
-- ============================================================================
