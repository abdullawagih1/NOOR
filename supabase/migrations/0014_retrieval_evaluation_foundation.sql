-- ============================================================================
-- Noor V1 — Migration 0014: Retrieval Evaluation Foundation (dataset lifecycle)
-- Council: Retrieval Evaluation Agent + Database Agent + Security Agent + Quality Agent
-- ============================================================================
-- Sprint 1-E1. Frozen evaluation corpora, versioned queries, graded relevance
-- judgments, and a deterministic dataset-freeze operation — the reproducible
-- foundation every future retrieval approach (lexical, embedding, hybrid,
-- reranked) will be measured against. See ADR 0015.
--
-- This migration covers the dataset lifecycle (draft -> ready_for_review ->
-- frozen -> archived) and its four content tables plus the frozen search
-- representation. Evaluation runs, ranked results, metrics, and failure
-- analysis are migration 0015 — the same execution/content split every
-- prior sprint in this codebase has used one layer further downstream.
--
-- No embeddings, no vector columns, no pgvector, no external AI calls, no
-- production search exposure anywhere in this migration.
-- ============================================================================

-- ============================================================================
-- 1. normalize_retrieval_text — the single source of truth for
--    retrieval_text_normalization_v1 (ADR 0015). Used by both query
--    authoring and dataset freezing; the Worker never re-implements this —
--    it only ever reads the already-normalized columns this function
--    populates.
-- ============================================================================

create or replace function normalize_retrieval_text(p_text text)
returns text
language plpgsql immutable as $$
declare
  v_text text := coalesce(p_text, '');
begin
  -- Step 1: Unicode NFC normalization (built into Postgres 13+).
  v_text := normalize(v_text, nfc);
  -- Step 2: Latin case-folding — no effect on Arabic, which has no case.
  v_text := lower(v_text);
  -- Step 3: Arabic diacritics (harakat: fathatan, dammatan, kasratan,
  -- fatha, damma, kasra, shadda, sukun, superscript alef) and tatweel
  -- removal — a technical search-indexing normalization, never applied
  -- to canonical chunk text.
  v_text := regexp_replace(v_text, '[ًٌٍَُِّْٰـ]', '', 'g');
  -- Step 4: Arabic-Indic numerals -> ASCII digits, so "١٢٣" and "123"
  -- match identically for lexical search purposes.
  v_text := translate(v_text, '٠١٢٣٤٥٦٧٨٩', '0123456789');
  -- Step 5: punctuation separated to whitespace for consistent tokenization.
  v_text := regexp_replace(v_text, '[[:punct:]]', ' ', 'g');
  -- Step 6: whitespace collapse + trim.
  v_text := trim(regexp_replace(v_text, '\s+', ' ', 'g'));
  return v_text;
end;
$$;

comment on function normalize_retrieval_text(text) is
  'retrieval_text_normalization_v1 (ADR 0015). NFC, Latin case-fold, Arabic '
  'diacritic/tatweel removal, Arabic-Indic numeral mapping, punctuation '
  'separation, whitespace collapse. Never mutates canonical chunk text.';

-- ============================================================================
-- 2. retrieval_evaluation_datasets — the dataset lifecycle
-- ============================================================================

create table if not exists retrieval_evaluation_datasets (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,

  logical_name text not null,
  version int not null check (version >= 1),
  title text not null,
  description text,
  domain_scope text,
  language_scope text[] not null default '{}'::text[],
  purpose text,

  status text not null default 'draft'
    check (status in ('draft', 'ready_for_review', 'frozen', 'archived')),
  parent_dataset_id uuid references retrieval_evaluation_datasets(id),

  dataset_schema_version text not null default '1',
  normalization_version text not null default 'retrieval_text_normalization_v1',
  no_clinical_use_notice text not null default 'Synthetic evaluation content — not for clinical use',

  corpus_manifest_sha256 text,
  query_manifest_sha256 text,
  judgment_manifest_sha256 text,
  dataset_sha256 text,

  created_by uuid references auth.users(id),
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  return_to_draft_reason text,
  frozen_by uuid references auth.users(id),
  frozen_at timestamptz,
  archived_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id, id),
  unique (organization_id, logical_name, version)
);

create index if not exists idx_retrieval_datasets_org_status
  on retrieval_evaluation_datasets (organization_id, status);

-- Freezes provenance/manifest columns once a dataset reaches a terminal
-- state, with the one legal frozen -> archived transition and the
-- explicit ready_for_review -> draft return path (mission §9). Mirrors
-- the same conditional-freeze shape as document_chunking_runs' own
-- trigger (migration 0012), one layer up the pipeline.
create or replace function prevent_terminal_dataset_mutation()
returns trigger language plpgsql as $$
begin
  if old.status = 'frozen' then
    if new.status = 'archived' then
      new.archived_at := coalesce(new.archived_at, now());
      -- Only the archival transition may change on an otherwise-frozen row.
      if new.corpus_manifest_sha256 is distinct from old.corpus_manifest_sha256
        or new.query_manifest_sha256 is distinct from old.query_manifest_sha256
        or new.judgment_manifest_sha256 is distinct from old.judgment_manifest_sha256
        or new.dataset_sha256 is distinct from old.dataset_sha256
        or new.logical_name is distinct from old.logical_name
        or new.version is distinct from old.version
      then
        raise exception 'a frozen dataset may only transition to archived, with no other field changed';
      end if;
      new.updated_at := now();
      return new;
    end if;
    if new.status = 'frozen' then
      -- No-op update (e.g. touching updated_at) is fine; content fields must be unchanged.
      if new.corpus_manifest_sha256 is distinct from old.corpus_manifest_sha256
        or new.query_manifest_sha256 is distinct from old.query_manifest_sha256
        or new.judgment_manifest_sha256 is distinct from old.judgment_manifest_sha256
        or new.dataset_sha256 is distinct from old.dataset_sha256
      then
        raise exception 'frozen dataset content is immutable';
      end if;
      new.updated_at := now();
      return new;
    end if;
    raise exception 'a frozen dataset cannot return to % — corrections require a new dataset version', new.status;
  end if;
  if old.status = 'archived' then
    raise exception 'an archived dataset is immutable';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prevent_terminal_dataset_mutation on retrieval_evaluation_datasets;
create trigger trg_prevent_terminal_dataset_mutation
  before update on retrieval_evaluation_datasets
  for each row execute function prevent_terminal_dataset_mutation();

alter table retrieval_evaluation_datasets enable row level security;

-- ============================================================================
-- 3. retrieval_evaluation_corpus_items — exact accepted-chunk references
-- ============================================================================

create table if not exists retrieval_evaluation_corpus_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  dataset_id uuid not null,

  chunk_id uuid not null,
  chunking_run_id uuid not null,
  chunking_review_id uuid,
  guideline_id uuid not null,
  guideline_version_id uuid not null,
  source_document_id uuid not null,

  chunk_index int not null,
  chunk_checksum text not null,
  page_number int not null,
  representation_type text not null check (representation_type in ('native', 'ocr', 'unknown')),
  contains_native_text boolean not null default false,
  contains_ocr_text boolean not null default false,
  warning_state boolean not null default false,
  embedding_ready_at_snapshot boolean not null,

  display_order int not null,
  -- Populated only at freeze time (mission §11) — a draft corpus item's
  -- checksum is meaningless while items can still be added/removed/reordered.
  corpus_item_sha256 text,

  added_by uuid references auth.users(id),
  created_at timestamptz not null default now(),

  unique (organization_id, id),
  unique (dataset_id, chunk_id),
  unique (dataset_id, display_order)
);

alter table retrieval_evaluation_corpus_items
  add constraint retrieval_evaluation_corpus_items_dataset_id_fkey
  foreign key (organization_id, dataset_id) references retrieval_evaluation_datasets(organization_id, id);

alter table retrieval_evaluation_corpus_items
  add constraint retrieval_evaluation_corpus_items_chunk_id_fkey
  foreign key (organization_id, chunk_id) references document_chunks(organization_id, id);

alter table retrieval_evaluation_corpus_items
  add constraint retrieval_evaluation_corpus_items_chunking_run_id_fkey
  foreign key (organization_id, chunking_run_id) references document_chunking_runs(organization_id, id);

create index if not exists idx_retrieval_corpus_items_dataset
  on retrieval_evaluation_corpus_items (organization_id, dataset_id, display_order);

-- Immutable once the parent dataset is frozen — enforced by checking the
-- parent's live status (the same pattern document_chunk_reviews uses for
-- its own parent-scoped freeze, migration 0013), not a copy of the status
-- onto this table.
create or replace function prevent_corpus_item_mutation_after_freeze()
returns trigger language plpgsql as $$
declare
  v_status text;
begin
  select status into v_status from retrieval_evaluation_datasets where id = coalesce(new.dataset_id, old.dataset_id);
  if v_status in ('frozen', 'archived') then
    raise exception 'corpus items are immutable once the dataset is frozen';
  end if;
  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_prevent_corpus_item_update_after_freeze on retrieval_evaluation_corpus_items;
create trigger trg_prevent_corpus_item_update_after_freeze
  before update on retrieval_evaluation_corpus_items
  for each row execute function prevent_corpus_item_mutation_after_freeze();

drop trigger if exists trg_prevent_corpus_item_delete_after_freeze on retrieval_evaluation_corpus_items;
create trigger trg_prevent_corpus_item_delete_after_freeze
  before delete on retrieval_evaluation_corpus_items
  for each row execute function prevent_corpus_item_mutation_after_freeze();

alter table retrieval_evaluation_corpus_items enable row level security;

-- ============================================================================
-- 4. retrieval_evaluation_queries — versioned, categorized evaluation queries
-- ============================================================================

create table if not exists retrieval_evaluation_queries (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  dataset_id uuid not null,

  query_key text not null,
  query_text text not null,
  normalized_query_text text not null,
  language text not null check (language in ('en', 'ar', 'mixed')),
  category text not null check (category in (
    'exact_phrase', 'keyword_lookup', 'fact_location', 'definition', 'procedure_step',
    'numeric_lookup', 'abbreviation', 'heading_lookup', 'cross_paragraph',
    'arabic_exact', 'arabic_keyword', 'english_exact', 'english_keyword',
    'mixed_language', 'negative_control', 'ambiguous', 'hard_lexical'
  )),
  difficulty text not null check (difficulty in ('basic', 'moderate', 'challenging')),
  intent_note text,
  expected_source_scope text,
  is_negative_control boolean not null default false,
  synthetic_declaration text not null default 'Synthetic evaluation content — not for clinical use',

  display_order int not null,
  active boolean not null default true,
  query_sha256 text,

  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id, id),
  unique (dataset_id, query_key),
  unique (dataset_id, display_order),
  check (category <> 'negative_control' or is_negative_control),
  check (not is_negative_control or category = 'negative_control')
);

alter table retrieval_evaluation_queries
  add constraint retrieval_evaluation_queries_dataset_id_fkey
  foreign key (organization_id, dataset_id) references retrieval_evaluation_datasets(organization_id, id);

create index if not exists idx_retrieval_queries_dataset
  on retrieval_evaluation_queries (organization_id, dataset_id, display_order);

create or replace function prevent_query_mutation_after_freeze()
returns trigger language plpgsql as $$
declare
  v_status text;
begin
  select status into v_status from retrieval_evaluation_datasets where id = coalesce(new.dataset_id, old.dataset_id);
  if v_status in ('frozen', 'archived') then
    raise exception 'queries are immutable once the dataset is frozen';
  end if;
  if new is not null then
    new.updated_at := now();
  end if;
  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_prevent_query_update_after_freeze on retrieval_evaluation_queries;
create trigger trg_prevent_query_update_after_freeze
  before update on retrieval_evaluation_queries
  for each row execute function prevent_query_mutation_after_freeze();

drop trigger if exists trg_prevent_query_delete_after_freeze on retrieval_evaluation_queries;
create trigger trg_prevent_query_delete_after_freeze
  before delete on retrieval_evaluation_queries
  for each row execute function prevent_query_mutation_after_freeze();

alter table retrieval_evaluation_queries enable row level security;

-- ============================================================================
-- 5. retrieval_relevance_judgments — graded, human-authored relevance
-- ============================================================================

create table if not exists retrieval_relevance_judgments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  dataset_id uuid not null,
  query_id uuid not null,
  corpus_item_id uuid not null,

  relevance_grade int not null check (relevance_grade in (0, 1, 2, 3)),
  rationale text,
  review_status text not null default 'pending_review' check (review_status in ('pending_review', 'confirmed')),

  judged_by uuid references auth.users(id),
  judged_at timestamptz not null default now(),
  judgment_sha256 text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id, id),
  unique (dataset_id, query_id, corpus_item_id)
);

alter table retrieval_relevance_judgments
  add constraint retrieval_relevance_judgments_dataset_id_fkey
  foreign key (organization_id, dataset_id) references retrieval_evaluation_datasets(organization_id, id);

alter table retrieval_relevance_judgments
  add constraint retrieval_relevance_judgments_query_id_fkey
  foreign key (organization_id, query_id) references retrieval_evaluation_queries(organization_id, id);

alter table retrieval_relevance_judgments
  add constraint retrieval_relevance_judgments_corpus_item_id_fkey
  foreign key (organization_id, corpus_item_id) references retrieval_evaluation_corpus_items(organization_id, id);

create index if not exists idx_retrieval_judgments_dataset
  on retrieval_relevance_judgments (organization_id, dataset_id, query_id);

create or replace function prevent_judgment_mutation_after_freeze()
returns trigger language plpgsql as $$
declare
  v_status text;
begin
  select status into v_status from retrieval_evaluation_datasets where id = coalesce(new.dataset_id, old.dataset_id);
  if v_status in ('frozen', 'archived') then
    raise exception 'relevance judgments are immutable once the dataset is frozen';
  end if;
  if new is not null then
    new.updated_at := now();
  end if;
  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_prevent_judgment_update_after_freeze on retrieval_relevance_judgments;
create trigger trg_prevent_judgment_update_after_freeze
  before update on retrieval_relevance_judgments
  for each row execute function prevent_judgment_mutation_after_freeze();

drop trigger if exists trg_prevent_judgment_delete_after_freeze on retrieval_relevance_judgments;
create trigger trg_prevent_judgment_delete_after_freeze
  before delete on retrieval_relevance_judgments
  for each row execute function prevent_judgment_mutation_after_freeze();

alter table retrieval_relevance_judgments enable row level security;

-- ============================================================================
-- 6. retrieval_evaluation_search_documents — frozen search representation.
--    Created only at freeze time (by freeze_retrieval_evaluation_dataset
--    below); fully immutable; never editable by browser clients.
-- ============================================================================

create table if not exists retrieval_evaluation_search_documents (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  dataset_id uuid not null,
  corpus_item_id uuid not null,

  normalized_search_text text not null,
  normalized_text_checksum text not null,
  search_vector tsvector not null,
  token_count int not null,
  language text not null,
  normalization_version text not null default 'retrieval_text_normalization_v1',

  created_at timestamptz not null default now(),

  unique (organization_id, id),
  unique (dataset_id, corpus_item_id)
);

alter table retrieval_evaluation_search_documents
  add constraint retrieval_evaluation_search_documents_dataset_id_fkey
  foreign key (organization_id, dataset_id) references retrieval_evaluation_datasets(organization_id, id);

alter table retrieval_evaluation_search_documents
  add constraint retrieval_evaluation_search_documents_corpus_item_id_fkey
  foreign key (organization_id, corpus_item_id) references retrieval_evaluation_corpus_items(organization_id, id);

create index if not exists idx_retrieval_search_documents_vector
  on retrieval_evaluation_search_documents using gin (search_vector);

create or replace function prevent_search_document_mutation()
returns trigger language plpgsql as $$
begin
  raise exception 'search representation % is immutable once created', old.id;
end;
$$;

drop trigger if exists trg_prevent_search_document_mutation on retrieval_evaluation_search_documents;
create trigger trg_prevent_search_document_mutation
  before update on retrieval_evaluation_search_documents
  for each row execute function prevent_search_document_mutation();

drop trigger if exists trg_prevent_search_document_delete on retrieval_evaluation_search_documents;
create trigger trg_prevent_search_document_delete
  before delete on retrieval_evaluation_search_documents
  for each row execute function prevent_search_document_mutation();

alter table retrieval_evaluation_search_documents enable row level security;

-- ============================================================================
-- 7. Permissions
-- ============================================================================

insert into permissions (key, description) values
  ('retrieval_evaluation.read', 'Read evaluation datasets, corpus items, queries, and judgments'),
  ('retrieval_evaluation.create_dataset', 'Create a new evaluation dataset'),
  ('retrieval_evaluation.edit_dataset', 'Edit a draft dataset (corpus items, queries, judgments)'),
  ('retrieval_evaluation.review_dataset', 'Confirm a dataset is ready for freezing'),
  ('retrieval_evaluation.freeze_dataset', 'Freeze a dataset, making it immutable'),
  ('retrieval_evaluation.archive_dataset', 'Archive a frozen dataset'),
  ('retrieval_evaluation.run', 'Create a retrieval evaluation run against a frozen dataset'),
  ('retrieval_evaluation.cancel_run', 'Cancel a queued or processing evaluation run'),
  ('retrieval_evaluation.read_results', 'Read ranked results and metrics'),
  ('retrieval_evaluation.read_artifacts', 'Read evaluation artifact checksum/path metadata'),
  ('retrieval_evaluation.annotate_failures', 'Create and update failure-analysis annotations')
on conflict (key) do nothing;

insert into role_permissions (role_id, permission_id)
select r.id, p.id from roles r, permissions p
where (r.key, p.key) in (
  ('organization_admin', 'retrieval_evaluation.read'),
  ('organization_admin', 'retrieval_evaluation.create_dataset'),

  ('quality_manager', 'retrieval_evaluation.read'),
  ('quality_manager', 'retrieval_evaluation.create_dataset'),
  ('quality_manager', 'retrieval_evaluation.edit_dataset'),
  ('quality_manager', 'retrieval_evaluation.review_dataset'),
  ('quality_manager', 'retrieval_evaluation.freeze_dataset'),
  ('quality_manager', 'retrieval_evaluation.archive_dataset'),
  ('quality_manager', 'retrieval_evaluation.run'),
  ('quality_manager', 'retrieval_evaluation.cancel_run'),
  ('quality_manager', 'retrieval_evaluation.read_results'),
  ('quality_manager', 'retrieval_evaluation.read_artifacts'),
  ('quality_manager', 'retrieval_evaluation.annotate_failures'),

  ('clinical_reviewer', 'retrieval_evaluation.read'),
  ('clinical_reviewer', 'retrieval_evaluation.edit_dataset'),
  ('clinical_reviewer', 'retrieval_evaluation.review_dataset'),
  ('clinical_reviewer', 'retrieval_evaluation.read_results'),

  ('safety_officer', 'retrieval_evaluation.read'),
  ('auditor', 'retrieval_evaluation.read')
)
on conflict do nothing;

-- Deliberately no clinician mapping — no access to raw evaluation corpora,
-- ranked results, artifacts, or failure analysis by default (mission §36).

-- ============================================================================
-- 8. RLS — SELECT-only; every write goes through a security definer function
-- ============================================================================

drop policy if exists retrieval_evaluation_datasets_select on retrieval_evaluation_datasets;
create policy retrieval_evaluation_datasets_select on retrieval_evaluation_datasets
  for select using (has_permission_in_organization(organization_id, 'retrieval_evaluation.read'));

drop policy if exists retrieval_evaluation_corpus_items_select on retrieval_evaluation_corpus_items;
create policy retrieval_evaluation_corpus_items_select on retrieval_evaluation_corpus_items
  for select using (has_permission_in_organization(organization_id, 'retrieval_evaluation.read'));

drop policy if exists retrieval_evaluation_queries_select on retrieval_evaluation_queries;
create policy retrieval_evaluation_queries_select on retrieval_evaluation_queries
  for select using (has_permission_in_organization(organization_id, 'retrieval_evaluation.read'));

drop policy if exists retrieval_relevance_judgments_select on retrieval_relevance_judgments;
create policy retrieval_relevance_judgments_select on retrieval_relevance_judgments
  for select using (has_permission_in_organization(organization_id, 'retrieval_evaluation.read'));

drop policy if exists retrieval_evaluation_search_documents_select on retrieval_evaluation_search_documents;
create policy retrieval_evaluation_search_documents_select on retrieval_evaluation_search_documents
  for select using (has_permission_in_organization(organization_id, 'retrieval_evaluation.read'));

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant select on retrieval_evaluation_datasets, retrieval_evaluation_corpus_items,
      retrieval_evaluation_queries, retrieval_relevance_judgments, retrieval_evaluation_search_documents
      to authenticated;
  end if;
end
$$;

-- ============================================================================
-- 9. Dataset lifecycle functions (client-facing)
-- ============================================================================

create or replace function create_retrieval_evaluation_dataset(
  p_organization_id uuid,
  p_logical_name text,
  p_version int,
  p_title text,
  p_description text default null,
  p_domain_scope text default null,
  p_language_scope text[] default '{}'::text[],
  p_purpose text default null,
  p_parent_dataset_id uuid default null,
  p_correlation_id uuid default gen_random_uuid()
) returns retrieval_evaluation_datasets
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_row retrieval_evaluation_datasets%rowtype;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  perform assert_permission(p_organization_id, 'retrieval_evaluation.create_dataset');

  if p_logical_name is null or length(trim(p_logical_name)) = 0 then
    raise exception 'logical_name is required';
  end if;
  if p_title is null or length(trim(p_title)) = 0 then
    raise exception 'title is required';
  end if;

  insert into retrieval_evaluation_datasets (
    organization_id, logical_name, version, title, description,
    domain_scope, language_scope, purpose, parent_dataset_id, created_by
  ) values (
    p_organization_id, p_logical_name, p_version, p_title, p_description,
    p_domain_scope, coalesce(p_language_scope, '{}'::text[]), p_purpose, p_parent_dataset_id, v_actor
  )
  returning * into v_row;

  perform record_audit_event(p_organization_id, 'retrieval_evaluation_dataset.created', 'retrieval_evaluation_dataset', v_row.id, p_correlation_id,
    jsonb_build_object('logical_name', p_logical_name, 'version', p_version));

  return v_row;
end;
$$;

revoke all on function create_retrieval_evaluation_dataset(uuid, text, int, text, text, text, text[], text, uuid, uuid) from public;

create or replace function update_retrieval_evaluation_dataset(
  p_dataset_id uuid,
  p_title text default null,
  p_description text default null,
  p_domain_scope text default null,
  p_language_scope text[] default null,
  p_purpose text default null,
  p_correlation_id uuid default gen_random_uuid()
) returns retrieval_evaluation_datasets
language plpgsql security definer set search_path = public as $$
declare
  v_dataset retrieval_evaluation_datasets%rowtype;
begin
  select * into v_dataset from retrieval_evaluation_datasets where id = p_dataset_id for update;
  if not found then
    raise exception 'dataset not found: %', p_dataset_id;
  end if;
  perform assert_permission(v_dataset.organization_id, 'retrieval_evaluation.edit_dataset');
  if v_dataset.status <> 'draft' then
    raise exception 'a dataset can only be edited while draft (current status: %)', v_dataset.status;
  end if;

  update retrieval_evaluation_datasets set
    title = coalesce(p_title, title),
    description = coalesce(p_description, description),
    domain_scope = coalesce(p_domain_scope, domain_scope),
    language_scope = coalesce(p_language_scope, language_scope),
    purpose = coalesce(p_purpose, purpose),
    updated_at = now()
    where id = p_dataset_id
    returning * into v_dataset;

  perform record_audit_event(v_dataset.organization_id, 'retrieval_evaluation_dataset.updated', 'retrieval_evaluation_dataset', v_dataset.id, p_correlation_id, '{}'::jsonb);

  return v_dataset;
end;
$$;

revoke all on function update_retrieval_evaluation_dataset(uuid, text, text, text, text[], text, uuid) from public;

create or replace function submit_evaluation_dataset_for_review(
  p_dataset_id uuid,
  p_correlation_id uuid default gen_random_uuid()
) returns retrieval_evaluation_datasets
language plpgsql security definer set search_path = public as $$
declare
  v_dataset retrieval_evaluation_datasets%rowtype;
begin
  select * into v_dataset from retrieval_evaluation_datasets where id = p_dataset_id for update;
  if not found then
    raise exception 'dataset not found: %', p_dataset_id;
  end if;
  perform assert_permission(v_dataset.organization_id, 'retrieval_evaluation.edit_dataset');
  if v_dataset.status <> 'draft' then
    raise exception 'only a draft dataset can be submitted for review (current status: %)', v_dataset.status;
  end if;
  if not exists (select 1 from retrieval_evaluation_corpus_items where dataset_id = p_dataset_id) then
    raise exception 'a dataset needs at least one corpus item before review';
  end if;
  if not exists (select 1 from retrieval_evaluation_queries where dataset_id = p_dataset_id and active) then
    raise exception 'a dataset needs at least one active query before review';
  end if;

  update retrieval_evaluation_datasets set status = 'ready_for_review', updated_at = now()
    where id = p_dataset_id
    returning * into v_dataset;

  perform record_audit_event(v_dataset.organization_id, 'retrieval_evaluation_dataset.ready_for_review', 'retrieval_evaluation_dataset', v_dataset.id, p_correlation_id, '{}'::jsonb);

  return v_dataset;
end;
$$;

revoke all on function submit_evaluation_dataset_for_review(uuid, uuid) from public;

create or replace function return_evaluation_dataset_to_draft(
  p_dataset_id uuid,
  p_reason text,
  p_correlation_id uuid default gen_random_uuid()
) returns retrieval_evaluation_datasets
language plpgsql security definer set search_path = public as $$
declare
  v_dataset retrieval_evaluation_datasets%rowtype;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'returning a dataset to draft requires a reason';
  end if;
  select * into v_dataset from retrieval_evaluation_datasets where id = p_dataset_id for update;
  if not found then
    raise exception 'dataset not found: %', p_dataset_id;
  end if;
  perform assert_permission(v_dataset.organization_id, 'retrieval_evaluation.review_dataset');
  if v_dataset.status <> 'ready_for_review' then
    raise exception 'only a ready_for_review dataset can return to draft (current status: %)', v_dataset.status;
  end if;

  update retrieval_evaluation_datasets set
    status = 'draft', return_to_draft_reason = p_reason, reviewed_by = null, reviewed_at = null, updated_at = now()
    where id = p_dataset_id
    returning * into v_dataset;

  perform record_audit_event(v_dataset.organization_id, 'retrieval_evaluation_dataset.returned_to_draft', 'retrieval_evaluation_dataset', v_dataset.id, p_correlation_id,
    jsonb_build_object('reason', p_reason));

  return v_dataset;
end;
$$;

revoke all on function return_evaluation_dataset_to_draft(uuid, text, uuid) from public;

-- Two-person separation (ADR 0015): a reviewer who is not the dataset's
-- own creator confirms readiness before it can be frozen — mirrors the
-- self-review blocks already established for extraction/OCR/chunking
-- technical review, applied here to dataset authorship vs. freeze review.
create or replace function mark_evaluation_dataset_reviewed(
  p_dataset_id uuid,
  p_correlation_id uuid default gen_random_uuid()
) returns retrieval_evaluation_datasets
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_dataset retrieval_evaluation_datasets%rowtype;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  select * into v_dataset from retrieval_evaluation_datasets where id = p_dataset_id for update;
  if not found then
    raise exception 'dataset not found: %', p_dataset_id;
  end if;
  perform assert_permission(v_dataset.organization_id, 'retrieval_evaluation.review_dataset');
  if v_dataset.status <> 'ready_for_review' then
    raise exception 'only a ready_for_review dataset can be marked reviewed (current status: %)', v_dataset.status;
  end if;
  if v_actor = v_dataset.created_by then
    raise exception 'a dataset creator cannot review their own dataset for freezing' using errcode = '42501';
  end if;

  update retrieval_evaluation_datasets set reviewed_by = v_actor, reviewed_at = now(), updated_at = now()
    where id = p_dataset_id
    returning * into v_dataset;

  perform record_audit_event(v_dataset.organization_id, 'retrieval_evaluation_dataset.reviewed', 'retrieval_evaluation_dataset', v_dataset.id, p_correlation_id, '{}'::jsonb);

  return v_dataset;
end;
$$;

revoke all on function mark_evaluation_dataset_reviewed(uuid, uuid) from public;

-- ============================================================================
-- 10. Corpus item functions
-- ============================================================================

create or replace function add_evaluation_corpus_item(
  p_dataset_id uuid,
  p_chunk_id uuid,
  p_correlation_id uuid default gen_random_uuid()
) returns retrieval_evaluation_corpus_items
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_dataset retrieval_evaluation_datasets%rowtype;
  v_chunk document_chunks%rowtype;
  v_run document_chunking_runs%rowtype;
  v_review_id uuid;
  v_readiness record;
  v_next_order int;
  v_row retrieval_evaluation_corpus_items%rowtype;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select * into v_dataset from retrieval_evaluation_datasets where id = p_dataset_id for update;
  if not found then
    raise exception 'dataset not found: %', p_dataset_id;
  end if;
  perform assert_permission(v_dataset.organization_id, 'retrieval_evaluation.edit_dataset');
  if v_dataset.status <> 'draft' then
    raise exception 'corpus items can only be added while the dataset is draft (current status: %)', v_dataset.status;
  end if;

  select * into v_chunk from document_chunks where organization_id = v_dataset.organization_id and id = p_chunk_id;
  if not found then
    raise exception 'chunk not found in this organization: %', p_chunk_id;
  end if;

  select * into v_run from document_chunking_runs where organization_id = v_dataset.organization_id and id = v_chunk.chunking_run_id;

  select * into v_readiness from get_document_embedding_readiness(v_run.source_document_id);
  if not v_readiness.out_eligible_for_embedding then
    raise exception 'chunk % is not currently embedding-ready (status: %)', p_chunk_id, coalesce(v_readiness.out_reason, v_readiness.out_review_status)
      using errcode = 'P0001';
  end if;

  select id into v_review_id from document_chunking_reviews
    where organization_id = v_dataset.organization_id and chunking_run_id = v_chunk.chunking_run_id
    order by review_round desc limit 1;

  select coalesce(max(display_order), 0) + 1 into v_next_order from retrieval_evaluation_corpus_items where dataset_id = p_dataset_id;

  insert into retrieval_evaluation_corpus_items (
    organization_id, dataset_id, chunk_id, chunking_run_id, chunking_review_id,
    guideline_id, guideline_version_id, source_document_id,
    chunk_index, chunk_checksum, page_number, representation_type,
    contains_native_text, contains_ocr_text, warning_state,
    embedding_ready_at_snapshot, display_order, added_by
  ) values (
    v_dataset.organization_id, p_dataset_id, p_chunk_id, v_chunk.chunking_run_id, v_review_id,
    v_run.guideline_id, v_run.guideline_version_id, v_run.source_document_id,
    v_chunk.chunk_index, v_chunk.chunk_checksum, v_chunk.page_start,
    case when v_chunk.contains_native_text then 'native' when v_chunk.contains_ocr_text then 'ocr' else 'unknown' end,
    v_chunk.contains_native_text, v_chunk.contains_ocr_text, v_chunk.warning_state,
    true, v_next_order, v_actor
  )
  returning * into v_row;

  perform record_audit_event(v_dataset.organization_id, 'retrieval_evaluation_dataset.corpus_item_added', 'retrieval_evaluation_dataset', v_dataset.id, p_correlation_id,
    jsonb_build_object('chunk_id', p_chunk_id));

  return v_row;
end;
$$;

revoke all on function add_evaluation_corpus_item(uuid, uuid, uuid) from public;

create or replace function remove_evaluation_corpus_item(
  p_corpus_item_id uuid,
  p_correlation_id uuid default gen_random_uuid()
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_item retrieval_evaluation_corpus_items%rowtype;
  v_dataset retrieval_evaluation_datasets%rowtype;
begin
  select * into v_item from retrieval_evaluation_corpus_items where id = p_corpus_item_id;
  if not found then
    raise exception 'corpus item not found: %', p_corpus_item_id;
  end if;
  select * into v_dataset from retrieval_evaluation_datasets where id = v_item.dataset_id for update;
  perform assert_permission(v_dataset.organization_id, 'retrieval_evaluation.edit_dataset');
  if v_dataset.status <> 'draft' then
    raise exception 'corpus items can only be removed while the dataset is draft (current status: %)', v_dataset.status;
  end if;

  delete from retrieval_relevance_judgments where corpus_item_id = p_corpus_item_id;
  delete from retrieval_evaluation_corpus_items where id = p_corpus_item_id;

  perform record_audit_event(v_dataset.organization_id, 'retrieval_evaluation_dataset.corpus_item_removed', 'retrieval_evaluation_dataset', v_dataset.id, p_correlation_id,
    jsonb_build_object('corpus_item_id', p_corpus_item_id));
end;
$$;

revoke all on function remove_evaluation_corpus_item(uuid, uuid) from public;

-- ============================================================================
-- 11. Query functions
-- ============================================================================

create or replace function create_evaluation_query(
  p_dataset_id uuid,
  p_query_key text,
  p_query_text text,
  p_language text,
  p_category text,
  p_difficulty text,
  p_is_negative_control boolean default false,
  p_intent_note text default null,
  p_expected_source_scope text default null,
  p_correlation_id uuid default gen_random_uuid()
) returns retrieval_evaluation_queries
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_dataset retrieval_evaluation_datasets%rowtype;
  v_next_order int;
  v_row retrieval_evaluation_queries%rowtype;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  select * into v_dataset from retrieval_evaluation_datasets where id = p_dataset_id for update;
  if not found then
    raise exception 'dataset not found: %', p_dataset_id;
  end if;
  perform assert_permission(v_dataset.organization_id, 'retrieval_evaluation.edit_dataset');
  if v_dataset.status <> 'draft' then
    raise exception 'queries can only be added while the dataset is draft (current status: %)', v_dataset.status;
  end if;
  if p_query_text is null or length(trim(p_query_text)) = 0 then
    raise exception 'query_text is required';
  end if;

  select coalesce(max(display_order), 0) + 1 into v_next_order from retrieval_evaluation_queries where dataset_id = p_dataset_id;

  insert into retrieval_evaluation_queries (
    organization_id, dataset_id, query_key, query_text, normalized_query_text,
    language, category, difficulty, is_negative_control, intent_note, expected_source_scope,
    display_order, created_by
  ) values (
    v_dataset.organization_id, p_dataset_id, p_query_key, p_query_text, normalize_retrieval_text(p_query_text),
    p_language, p_category, p_difficulty, p_is_negative_control, p_intent_note, p_expected_source_scope,
    v_next_order, v_actor
  )
  returning * into v_row;

  perform record_audit_event(v_dataset.organization_id, 'retrieval_evaluation_dataset.query_created', 'retrieval_evaluation_dataset', v_dataset.id, p_correlation_id,
    jsonb_build_object('query_key', p_query_key));

  return v_row;
end;
$$;

revoke all on function create_evaluation_query(uuid, text, text, text, text, text, boolean, text, text, uuid) from public;

create or replace function update_evaluation_query(
  p_query_id uuid,
  p_query_text text default null,
  p_category text default null,
  p_difficulty text default null,
  p_intent_note text default null,
  p_expected_source_scope text default null,
  p_active boolean default null,
  p_correlation_id uuid default gen_random_uuid()
) returns retrieval_evaluation_queries
language plpgsql security definer set search_path = public as $$
declare
  v_query retrieval_evaluation_queries%rowtype;
  v_dataset retrieval_evaluation_datasets%rowtype;
begin
  select * into v_query from retrieval_evaluation_queries where id = p_query_id;
  if not found then
    raise exception 'query not found: %', p_query_id;
  end if;
  select * into v_dataset from retrieval_evaluation_datasets where id = v_query.dataset_id for update;
  perform assert_permission(v_dataset.organization_id, 'retrieval_evaluation.edit_dataset');
  if v_dataset.status <> 'draft' then
    raise exception 'queries can only be edited while the dataset is draft (current status: %)', v_dataset.status;
  end if;

  update retrieval_evaluation_queries set
    query_text = coalesce(p_query_text, query_text),
    normalized_query_text = case when p_query_text is not null then normalize_retrieval_text(p_query_text) else normalized_query_text end,
    category = coalesce(p_category, category),
    difficulty = coalesce(p_difficulty, difficulty),
    intent_note = coalesce(p_intent_note, intent_note),
    expected_source_scope = coalesce(p_expected_source_scope, expected_source_scope),
    active = coalesce(p_active, active)
    where id = p_query_id
    returning * into v_query;

  perform record_audit_event(v_dataset.organization_id, 'retrieval_evaluation_dataset.query_updated', 'retrieval_evaluation_dataset', v_dataset.id, p_correlation_id,
    jsonb_build_object('query_id', p_query_id));

  return v_query;
end;
$$;

revoke all on function update_evaluation_query(uuid, text, text, text, text, text, boolean, uuid) from public;

-- ============================================================================
-- 12. Relevance judgment functions
-- ============================================================================

create or replace function create_relevance_judgment(
  p_query_id uuid,
  p_corpus_item_id uuid,
  p_relevance_grade int,
  p_rationale text default null,
  p_correlation_id uuid default gen_random_uuid()
) returns retrieval_relevance_judgments
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_query retrieval_evaluation_queries%rowtype;
  v_item retrieval_evaluation_corpus_items%rowtype;
  v_dataset retrieval_evaluation_datasets%rowtype;
  v_row retrieval_relevance_judgments%rowtype;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  select * into v_query from retrieval_evaluation_queries where id = p_query_id;
  if not found then
    raise exception 'query not found: %', p_query_id;
  end if;
  select * into v_item from retrieval_evaluation_corpus_items where id = p_corpus_item_id;
  if not found then
    raise exception 'corpus item not found: %', p_corpus_item_id;
  end if;
  if v_item.dataset_id <> v_query.dataset_id then
    raise exception 'query and corpus item belong to different datasets';
  end if;

  select * into v_dataset from retrieval_evaluation_datasets where id = v_query.dataset_id for update;
  perform assert_permission(v_dataset.organization_id, 'retrieval_evaluation.edit_dataset');
  if v_dataset.status <> 'draft' then
    raise exception 'judgments can only be added while the dataset is draft (current status: %)', v_dataset.status;
  end if;
  if p_relevance_grade not in (0, 1, 2, 3) then
    raise exception 'relevance_grade must be 0, 1, 2, or 3';
  end if;

  insert into retrieval_relevance_judgments (
    organization_id, dataset_id, query_id, corpus_item_id, relevance_grade, rationale, judged_by
  ) values (
    v_dataset.organization_id, v_query.dataset_id, p_query_id, p_corpus_item_id, p_relevance_grade, p_rationale, v_actor
  )
  returning * into v_row;

  perform record_audit_event(v_dataset.organization_id, 'retrieval_evaluation_dataset.judgment_created', 'retrieval_evaluation_dataset', v_dataset.id, p_correlation_id,
    jsonb_build_object('query_id', p_query_id, 'corpus_item_id', p_corpus_item_id, 'relevance_grade', p_relevance_grade));

  return v_row;
end;
$$;

revoke all on function create_relevance_judgment(uuid, uuid, int, text, uuid) from public;

create or replace function update_relevance_judgment(
  p_judgment_id uuid,
  p_relevance_grade int default null,
  p_rationale text default null,
  p_review_status text default null,
  p_correlation_id uuid default gen_random_uuid()
) returns retrieval_relevance_judgments
language plpgsql security definer set search_path = public as $$
declare
  v_judgment retrieval_relevance_judgments%rowtype;
  v_dataset retrieval_evaluation_datasets%rowtype;
begin
  select * into v_judgment from retrieval_relevance_judgments where id = p_judgment_id;
  if not found then
    raise exception 'judgment not found: %', p_judgment_id;
  end if;
  select * into v_dataset from retrieval_evaluation_datasets where id = v_judgment.dataset_id for update;
  perform assert_permission(v_dataset.organization_id, 'retrieval_evaluation.edit_dataset');
  if v_dataset.status <> 'draft' then
    raise exception 'judgments can only be edited while the dataset is draft (current status: %)', v_dataset.status;
  end if;
  if p_relevance_grade is not null and p_relevance_grade not in (0, 1, 2, 3) then
    raise exception 'relevance_grade must be 0, 1, 2, or 3';
  end if;
  if p_review_status is not null and p_review_status not in ('pending_review', 'confirmed') then
    raise exception 'invalid review_status: %', p_review_status;
  end if;

  update retrieval_relevance_judgments set
    relevance_grade = coalesce(p_relevance_grade, relevance_grade),
    rationale = coalesce(p_rationale, rationale),
    review_status = coalesce(p_review_status, review_status)
    where id = p_judgment_id
    returning * into v_judgment;

  perform record_audit_event(v_dataset.organization_id, 'retrieval_evaluation_dataset.judgment_updated', 'retrieval_evaluation_dataset', v_dataset.id, p_correlation_id,
    jsonb_build_object('judgment_id', p_judgment_id));

  return v_judgment;
end;
$$;

revoke all on function update_relevance_judgment(uuid, int, text, text, uuid) from public;

-- ============================================================================
-- 13. freeze_retrieval_evaluation_dataset — the controlled freeze operation
-- ============================================================================

create or replace function freeze_retrieval_evaluation_dataset(
  p_dataset_id uuid,
  p_idempotency_key text default null,
  p_correlation_id uuid default gen_random_uuid()
) returns retrieval_evaluation_datasets
-- search_path includes `extensions` — this function calls digest()
-- directly to compute every manifest/corpus-item/dataset checksum; on
-- hosted Supabase pgcrypto lives in the `extensions` schema, not
-- `public` (see assert_lease_owner's own comment in migration 0007 for
-- the same fact) — invisible on local plain Postgres, where pgcrypto
-- was installed directly into `public` by migration 0001.
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_actor uuid := auth.uid();
  v_dataset retrieval_evaluation_datasets%rowtype;
  v_item record;
  v_query record;
  v_readiness record;
  v_corpus_manifest jsonb;
  v_query_manifest jsonb;
  v_judgment_manifest jsonb;
  v_dataset_identity jsonb;
  v_non_negative_unjudged text;
  v_negative_false_positive text;
  v_missing_judgment_ref text;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select * into v_dataset from retrieval_evaluation_datasets where id = p_dataset_id for update;
  if not found then
    raise exception 'dataset not found: %', p_dataset_id;
  end if;
  perform assert_permission(v_dataset.organization_id, 'retrieval_evaluation.freeze_dataset');

  if v_dataset.status = 'frozen' then
    -- Idempotent replay: already frozen, return as-is.
    return v_dataset;
  end if;
  if v_dataset.status <> 'ready_for_review' then
    raise exception 'a dataset can only be frozen from ready_for_review (current status: %)', v_dataset.status;
  end if;
  if v_dataset.reviewed_by is null or v_dataset.reviewed_by = v_dataset.created_by then
    raise exception 'a dataset must be reviewed by someone other than its creator before freezing'
      using errcode = 'P0001';
  end if;

  -- Re-confirm every corpus item is still embedding-ready.
  for v_item in select * from retrieval_evaluation_corpus_items where dataset_id = p_dataset_id order by display_order loop
    select * into v_readiness from get_document_embedding_readiness(v_item.source_document_id);
    if not v_readiness.out_eligible_for_embedding then
      raise exception 'corpus item % (chunk %) is no longer embedding-ready (status: %) — remove it before freezing',
        v_item.id, v_item.chunk_id, coalesce(v_readiness.out_reason, v_readiness.out_review_status)
        using errcode = 'P0001';
    end if;
  end loop;

  -- Judgment coverage: every active, non-negative-control query needs at
  -- least one judgment with grade >= 2 (mission §15/§16).
  select string_agg(q.query_key, ', ') into v_non_negative_unjudged
    from retrieval_evaluation_queries q
    where q.dataset_id = p_dataset_id and q.active and not q.is_negative_control
      and not exists (
        select 1 from retrieval_relevance_judgments j
        where j.query_id = q.id and j.relevance_grade >= 2
      );
  if v_non_negative_unjudged is not null then
    raise exception 'the following queries have no relevant (grade >= 2) judgment: %', v_non_negative_unjudged
      using errcode = 'P0001';
  end if;

  -- Negative controls must have no positive relevance judgment.
  select string_agg(q.query_key, ', ') into v_negative_false_positive
    from retrieval_evaluation_queries q
    where q.dataset_id = p_dataset_id and q.active and q.is_negative_control
      and exists (
        select 1 from retrieval_relevance_judgments j
        where j.query_id = q.id and j.relevance_grade >= 2
      );
  if v_negative_false_positive is not null then
    raise exception 'the following negative-control queries have a positive relevance judgment: %', v_negative_false_positive
      using errcode = 'P0001';
  end if;

  -- No judgment may reference a corpus item or query from another dataset
  -- (structurally impossible via the FK + dataset_id check already enforced
  -- at judgment-creation time, re-verified here defensively).
  select string_agg(j.id::text, ', ') into v_missing_judgment_ref
    from retrieval_relevance_judgments j
    where j.dataset_id = p_dataset_id
      and (
        not exists (select 1 from retrieval_evaluation_queries q where q.id = j.query_id and q.dataset_id = p_dataset_id)
        or not exists (select 1 from retrieval_evaluation_corpus_items c where c.id = j.corpus_item_id and c.dataset_id = p_dataset_id)
      );
  if v_missing_judgment_ref is not null then
    raise exception 'judgment(s) reference a query or corpus item outside this dataset: %', v_missing_judgment_ref
      using errcode = 'P0001';
  end if;

  -- Build canonical corpus manifest (jsonb array serialization preserves
  -- the ORDER BY sequence; jsonb object key order is canonicalized on
  -- storage regardless of build order — see ADR 0015).
  select coalesce(jsonb_agg(jsonb_build_object(
      'corpus_item_id', c.id,
      'chunk_id', c.chunk_id,
      'chunk_checksum', c.chunk_checksum,
      'chunking_run_id', c.chunking_run_id,
      'guideline_id', c.guideline_id,
      'guideline_version_id', c.guideline_version_id,
      'source_document_id', c.source_document_id,
      'chunk_index', c.chunk_index,
      'page_number', c.page_number,
      'representation_type', c.representation_type,
      'display_order', c.display_order
    ) order by c.display_order, c.id), '[]'::jsonb)
    into v_corpus_manifest
    from retrieval_evaluation_corpus_items c where c.dataset_id = p_dataset_id;

  select coalesce(jsonb_agg(jsonb_build_object(
      'query_id', q.id,
      'query_key', q.query_key,
      'query_checksum', encode(digest(convert_to(q.query_text, 'utf8'), 'sha256'), 'hex'),
      'normalized_query_text', q.normalized_query_text,
      'language', q.language,
      'category', q.category,
      'difficulty', q.difficulty,
      'is_negative_control', q.is_negative_control,
      'active', q.active,
      'display_order', q.display_order
    ) order by q.display_order, q.id), '[]'::jsonb)
    into v_query_manifest
    from retrieval_evaluation_queries q where q.dataset_id = p_dataset_id;

  select coalesce(jsonb_agg(jsonb_build_object(
      'query_id', j.query_id,
      'corpus_item_id', j.corpus_item_id,
      'relevance_grade', j.relevance_grade
    ) order by j.query_id, j.corpus_item_id), '[]'::jsonb)
    into v_judgment_manifest
    from retrieval_relevance_judgments j where j.dataset_id = p_dataset_id;

  -- Populate each corpus item's own snapshot checksum now that the dataset
  -- is about to freeze (mission §11 — computed at freeze time, not add time).
  update retrieval_evaluation_corpus_items c set
    corpus_item_sha256 = encode(digest(convert_to(jsonb_build_object(
      'chunk_id', c.chunk_id, 'chunk_checksum', c.chunk_checksum, 'chunking_run_id', c.chunking_run_id,
      'source_document_id', c.source_document_id, 'chunk_index', c.chunk_index, 'display_order', c.display_order
    )::text, 'utf8'), 'sha256'), 'hex')
    where c.dataset_id = p_dataset_id;

  v_dataset_identity := jsonb_build_object(
    'organization_id', v_dataset.organization_id,
    'logical_name', v_dataset.logical_name,
    'version', v_dataset.version,
    'corpus_manifest_sha256', encode(digest(convert_to(v_corpus_manifest::text, 'utf8'), 'sha256'), 'hex'),
    'query_manifest_sha256', encode(digest(convert_to(v_query_manifest::text, 'utf8'), 'sha256'), 'hex'),
    'judgment_manifest_sha256', encode(digest(convert_to(v_judgment_manifest::text, 'utf8'), 'sha256'), 'hex'),
    'normalization_version', v_dataset.normalization_version,
    'dataset_schema_version', v_dataset.dataset_schema_version
  );

  -- Create the frozen search representation, one row per corpus item.
  insert into retrieval_evaluation_search_documents (
    organization_id, dataset_id, corpus_item_id, normalized_search_text,
    normalized_text_checksum, search_vector, token_count, language, normalization_version
  )
  select
    v_dataset.organization_id, p_dataset_id, c.id,
    normalize_retrieval_text(ch.chunk_text),
    encode(digest(convert_to(normalize_retrieval_text(ch.chunk_text), 'utf8'), 'sha256'), 'hex'),
    to_tsvector('simple', normalize_retrieval_text(ch.chunk_text)),
    array_length(regexp_split_to_array(trim(normalize_retrieval_text(ch.chunk_text)), '\s+'), 1),
    case when c.representation_type = 'ocr' then 'mixed' else 'mixed' end,
    'retrieval_text_normalization_v1'
  from retrieval_evaluation_corpus_items c
  join document_chunks ch on ch.organization_id = c.organization_id and ch.id = c.chunk_id
  where c.dataset_id = p_dataset_id
  on conflict (dataset_id, corpus_item_id) do nothing;

  update retrieval_evaluation_datasets set
    status = 'frozen',
    corpus_manifest_sha256 = v_dataset_identity ->> 'corpus_manifest_sha256',
    query_manifest_sha256 = v_dataset_identity ->> 'query_manifest_sha256',
    judgment_manifest_sha256 = v_dataset_identity ->> 'judgment_manifest_sha256',
    dataset_sha256 = encode(digest(convert_to(v_dataset_identity::text, 'utf8'), 'sha256'), 'hex'),
    frozen_by = v_actor,
    frozen_at = now(),
    updated_at = now()
    where id = p_dataset_id
    returning * into v_dataset;

  perform record_audit_event(v_dataset.organization_id, 'retrieval_evaluation_dataset.frozen', 'retrieval_evaluation_dataset', v_dataset.id, p_correlation_id,
    jsonb_build_object('dataset_sha256', v_dataset.dataset_sha256));

  return v_dataset;
end;
$$;

revoke all on function freeze_retrieval_evaluation_dataset(uuid, text, uuid) from public;

create or replace function archive_retrieval_evaluation_dataset(
  p_dataset_id uuid,
  p_correlation_id uuid default gen_random_uuid()
) returns retrieval_evaluation_datasets
language plpgsql security definer set search_path = public as $$
declare
  v_dataset retrieval_evaluation_datasets%rowtype;
begin
  select * into v_dataset from retrieval_evaluation_datasets where id = p_dataset_id for update;
  if not found then
    raise exception 'dataset not found: %', p_dataset_id;
  end if;
  perform assert_permission(v_dataset.organization_id, 'retrieval_evaluation.archive_dataset');
  if v_dataset.status <> 'frozen' then
    raise exception 'only a frozen dataset can be archived (current status: %)', v_dataset.status;
  end if;

  update retrieval_evaluation_datasets set status = 'archived', archived_at = now(), updated_at = now()
    where id = p_dataset_id
    returning * into v_dataset;

  perform record_audit_event(v_dataset.organization_id, 'retrieval_evaluation_dataset.archived', 'retrieval_evaluation_dataset', v_dataset.id, p_correlation_id, '{}'::jsonb);

  return v_dataset;
end;
$$;

revoke all on function archive_retrieval_evaluation_dataset(uuid, uuid) from public;

-- ============================================================================
-- 14. GRANTS — client-facing functions only
-- ============================================================================

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function
      create_retrieval_evaluation_dataset(uuid, text, int, text, text, text, text[], text, uuid, uuid),
      update_retrieval_evaluation_dataset(uuid, text, text, text, text[], text, uuid),
      submit_evaluation_dataset_for_review(uuid, uuid),
      return_evaluation_dataset_to_draft(uuid, text, uuid),
      mark_evaluation_dataset_reviewed(uuid, uuid),
      add_evaluation_corpus_item(uuid, uuid, uuid),
      remove_evaluation_corpus_item(uuid, uuid),
      create_evaluation_query(uuid, text, text, text, text, text, boolean, text, text, uuid),
      update_evaluation_query(uuid, text, text, text, text, text, boolean, uuid),
      create_relevance_judgment(uuid, uuid, int, text, uuid),
      update_relevance_judgment(uuid, int, text, text, uuid),
      freeze_retrieval_evaluation_dataset(uuid, text, uuid),
      archive_retrieval_evaluation_dataset(uuid, uuid)
      to authenticated;
  end if;
end
$$;

-- ============================================================================
-- End of migration 0014
-- ============================================================================
