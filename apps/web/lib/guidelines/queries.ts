import { createClient } from "@/lib/supabase/server";
import type { LifecycleStatus, ReviewStatus } from "@/lib/guidelines/schemas";

export interface ClinicalDomainRow {
  id: string;
  code: string;
  name: string;
  description: string | null;
  is_active: boolean;
}

export interface GuidelineAuthorityRow {
  id: string;
  name: string;
  short_name: string | null;
  authority_type: string | null;
  country_or_region: string | null;
  official_website: string | null;
  is_verified: boolean;
  verification_notes: string | null;
}

export interface GuidelineVersionRow {
  id: string;
  guideline_id: string;
  version_label: string;
  edition: string | null;
  publication_date: string | null;
  effective_date: string | null;
  review_due_date: string | null;
  expiry_date: string | null;
  language: string;
  lifecycle_status: LifecycleStatus;
  supersedes_version_id: string | null;
  evidence_scope: string | null;
  target_population: string | null;
  excluded_population: string | null;
  methodology_summary: string | null;
  notes: string | null;
  approved_at: string | null;
  activated_at: string | null;
  superseded_at: string | null;
  withdrawn_at: string | null;
  withdrawal_reason: string | null;
  created_at: string;
  created_by: string | null;
  updated_at: string;
}

export interface GuidelineRow {
  id: string;
  organization_id: string;
  clinical_domain_id: string;
  authority_id: string;
  internal_code: string;
  canonical_title: string;
  short_title: string | null;
  jurisdiction: string | null;
  default_language: string;
  description: string | null;
  current_active_version_id: string | null;
  created_at: string;
  updated_at: string;
}

export interface GuidelineWithRelations extends GuidelineRow {
  domain: { id: string; name: string } | null;
  authority: { id: string; name: string; is_verified: boolean } | null;
  currentActiveVersion: Pick<GuidelineVersionRow, "id" | "version_label" | "effective_date"> | null;
}

export interface GuidelineReviewRow {
  id: string;
  guideline_version_id: string;
  reviewer_id: string;
  review_status: ReviewStatus;
  clinical_comments: string | null;
  safety_concerns: string | null;
  requested_changes: string | null;
  reviewed_at: string | null;
  created_at: string;
}

export interface GuidelineLifecycleEventRow {
  id: string;
  guideline_version_id: string;
  from_status: string | null;
  to_status: string;
  reason: string | null;
  actor_id: string | null;
  created_at: string;
}

export async function listClinicalDomains(organizationId: string): Promise<ClinicalDomainRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("clinical_domains")
    .select("id, code, name, description, is_active")
    .eq("organization_id", organizationId)
    .order("name", { ascending: true });
  if (error) throw error;
  return data ?? [];
}

export async function listGuidelineAuthorities(organizationId: string): Promise<GuidelineAuthorityRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("guideline_authorities")
    .select("id, name, short_name, authority_type, country_or_region, official_website, is_verified, verification_notes")
    .eq("organization_id", organizationId)
    .order("name", { ascending: true });
  if (error) throw error;
  return data ?? [];
}

export interface GuidelineListFilters {
  search?: string;
  clinicalDomainId?: string;
  authorityId?: string;
  lifecycleStatus?: LifecycleStatus;
}

/**
 * Lists guidelines for the Admin Registry. Domain/authority are fetched via
 * a single-relationship embed (unambiguous — each guideline has exactly one
 * clinical_domain_id / authority_id). The current active version is fetched
 * in a second, batched query rather than an embed, to avoid depending on
 * PostgREST's auto-generated foreign-key constraint name for
 * guideline_versions' two distinct relationships to guidelines.
 */
export async function listGuidelines(
  organizationId: string,
  filters: GuidelineListFilters = {}
): Promise<GuidelineWithRelations[]> {
  const supabase = await createClient();

  let query = supabase
    .from("guidelines")
    .select(
      "*, domain:clinical_domains(id, name), authority:guideline_authorities(id, name, is_verified)"
    )
    .eq("organization_id", organizationId)
    .order("canonical_title", { ascending: true });

  if (filters.clinicalDomainId) query = query.eq("clinical_domain_id", filters.clinicalDomainId);
  if (filters.authorityId) query = query.eq("authority_id", filters.authorityId);
  if (filters.search) query = query.ilike("canonical_title", `%${filters.search}%`);

  const { data: guidelines, error } = await query;
  if (error) throw error;

  const rows = (guidelines ?? []) as unknown as (GuidelineRow & {
    domain: { id: string; name: string } | null;
    authority: { id: string; name: string; is_verified: boolean } | null;
  })[];

  const activeVersionIds = rows.map((g) => g.current_active_version_id).filter((id): id is string => !!id);

  let activeVersionsById = new Map<string, Pick<GuidelineVersionRow, "id" | "version_label" | "effective_date">>();
  if (activeVersionIds.length > 0) {
    const { data: versions, error: versionsError } = await supabase
      .from("guideline_versions")
      .select("id, version_label, effective_date")
      .in("id", activeVersionIds);
    if (versionsError) throw versionsError;
    activeVersionsById = new Map((versions ?? []).map((v) => [v.id, v]));
  }

  let result: GuidelineWithRelations[] = rows.map((g) => ({
    ...g,
    currentActiveVersion: g.current_active_version_id ? activeVersionsById.get(g.current_active_version_id) ?? null : null,
  }));

  if (filters.lifecycleStatus) {
    if (filters.lifecycleStatus === "active") {
      result = result.filter((g) => g.currentActiveVersion !== null);
    } else {
      // Filtering by a non-active status requires checking each guideline's
      // versions directly (not just the current_active_version_id pointer).
      const { data: matchingVersions } = await supabase
        .from("guideline_versions")
        .select("guideline_id")
        .eq("lifecycle_status", filters.lifecycleStatus)
        .eq("organization_id", organizationId);
      const matchingGuidelineIds = new Set((matchingVersions ?? []).map((v) => v.guideline_id));
      result = result.filter((g) => matchingGuidelineIds.has(g.id));
    }
  }

  return result;
}

export async function getGuideline(id: string): Promise<{
  guideline: GuidelineWithRelations | null;
  versions: GuidelineVersionRow[];
}> {
  const supabase = await createClient();

  const { data: guideline, error } = await supabase
    .from("guidelines")
    .select("*, domain:clinical_domains(id, name), authority:guideline_authorities(id, name, is_verified)")
    .eq("id", id)
    .maybeSingle();
  if (error) throw error;
  if (!guideline) return { guideline: null, versions: [] };

  const typedGuideline = guideline as unknown as GuidelineRow & {
    domain: { id: string; name: string } | null;
    authority: { id: string; name: string; is_verified: boolean } | null;
  };

  const { data: versions, error: versionsError } = await supabase
    .from("guideline_versions")
    .select("*")
    .eq("guideline_id", id)
    .order("created_at", { ascending: false });
  if (versionsError) throw versionsError;

  const currentActiveVersion = typedGuideline.current_active_version_id
    ? (versions ?? []).find((v) => v.id === typedGuideline.current_active_version_id) ?? null
    : null;

  return {
    guideline: { ...typedGuideline, currentActiveVersion },
    versions: versions ?? [],
  };
}

export async function listGuidelineVersionReviews(guidelineVersionId: string): Promise<GuidelineReviewRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("guideline_reviews")
    .select("*")
    .eq("guideline_version_id", guidelineVersionId)
    .order("created_at", { ascending: false });
  if (error) throw error;
  return data ?? [];
}

export async function listGuidelineVersionLifecycleEvents(guidelineVersionId: string): Promise<GuidelineLifecycleEventRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("guideline_lifecycle_events")
    .select("*")
    .eq("guideline_version_id", guidelineVersionId)
    .order("created_at", { ascending: false });
  if (error) throw error;
  return data ?? [];
}

/** Versions currently ready_for_review, for the Reviewer Queue. */
export async function listReviewQueue(organizationId: string): Promise<(GuidelineVersionRow & { guidelineTitle: string })[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("guideline_versions")
    .select("*, guidelines(canonical_title)")
    .eq("organization_id", organizationId)
    .eq("lifecycle_status", "ready_for_review")
    .order("updated_at", { ascending: true });
  if (error) throw error;
  return (data ?? []).map((row) => {
    const { guidelines, ...rest } = row as unknown as GuidelineVersionRow & { guidelines: { canonical_title: string } | null };
    return { ...rest, guidelineTitle: guidelines?.canonical_title ?? "Untitled guideline" };
  });
}

/** Active guidelines only, for the read-only Clinician knowledge view. */
export async function listActiveGuidelinesForClinician(organizationId: string): Promise<GuidelineWithRelations[]> {
  const all = await listGuidelines(organizationId);
  return all.filter((g) => g.currentActiveVersion !== null);
}
