"use server";

import { randomUUID } from "node:crypto";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { requirePermission } from "@/lib/auth/context";
import { PERMISSIONS } from "@/lib/auth/permissions";
import { toGuidelineRegistryError } from "@/lib/guidelines/errors";
import {
  clinicalDomainCreateSchema,
  guidelineAuthorityCreateSchema,
  guidelineCreateSchema,
  guidelineUpdateSchema,
  guidelineVersionCreateSchema,
  guidelineVersionUpdateSchema,
  guidelineReviewSubmitSchema,
  lifecycleTransitionSchema,
  type LifecycleStatus,
} from "@/lib/guidelines/schemas";

function text(formData: FormData, key: string): string {
  return String(formData.get(key) ?? "").trim();
}
function optionalText(formData: FormData, key: string): string {
  return text(formData, key);
}
function checkbox(formData: FormData, key: string): boolean {
  return formData.get(key) === "on" || formData.get(key) === "true";
}

function withError(path: string, message: string): never {
  redirect(`${path}?error=${encodeURIComponent(message)}`);
}

// ---------------------------------------------------------------------------
// Clinical domains
// ---------------------------------------------------------------------------

export async function createClinicalDomainAction(formData: FormData): Promise<void> {
  const context = await requirePermission(PERMISSIONS.CLINICAL_DOMAINS_MANAGE);
  const returnTo = optionalText(formData, "returnTo") || "/knowledge/guidelines/new";

  const parsed = clinicalDomainCreateSchema.safeParse({
    organizationId: context.organizationId,
    code: text(formData, "code"),
    name: text(formData, "name"),
    description: optionalText(formData, "description"),
  });
  if (!parsed.success) {
    withError(returnTo, parsed.error.issues[0]?.message ?? "Invalid clinical domain.");
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("create_clinical_domain", {
    p_organization_id: parsed.data.organizationId,
    p_code: parsed.data.code,
    p_name: parsed.data.name,
    p_description: parsed.data.description ?? null,
  });
  if (error) withError(returnTo, toGuidelineRegistryError(error).message);

  revalidatePath("/knowledge/guidelines/new");
  redirect(returnTo);
}

// ---------------------------------------------------------------------------
// Guideline authorities
// ---------------------------------------------------------------------------

export async function createGuidelineAuthorityAction(formData: FormData): Promise<void> {
  const context = await requirePermission(PERMISSIONS.GUIDELINE_AUTHORITIES_MANAGE);
  const returnTo = optionalText(formData, "returnTo") || "/knowledge/guidelines/new";

  const parsed = guidelineAuthorityCreateSchema.safeParse({
    organizationId: context.organizationId,
    name: text(formData, "name"),
    shortName: optionalText(formData, "shortName"),
    authorityType: optionalText(formData, "authorityType"),
    countryOrRegion: optionalText(formData, "countryOrRegion"),
    officialWebsite: optionalText(formData, "officialWebsite"),
    isVerified: checkbox(formData, "isVerified"),
    verificationNotes: optionalText(formData, "verificationNotes"),
  });
  if (!parsed.success) {
    withError(returnTo, parsed.error.issues[0]?.message ?? "Invalid guideline authority.");
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("create_guideline_authority", {
    p_organization_id: parsed.data.organizationId,
    p_name: parsed.data.name,
    p_short_name: parsed.data.shortName ?? null,
    p_authority_type: parsed.data.authorityType ?? null,
    p_country_or_region: parsed.data.countryOrRegion ?? null,
    p_official_website: parsed.data.officialWebsite ?? null,
    p_is_verified: parsed.data.isVerified,
    p_verification_notes: parsed.data.verificationNotes ?? null,
  });
  if (error) withError(returnTo, toGuidelineRegistryError(error).message);

  revalidatePath("/knowledge/guidelines/new");
  redirect(returnTo);
}

// ---------------------------------------------------------------------------
// Guidelines
// ---------------------------------------------------------------------------

export async function createGuidelineAction(formData: FormData): Promise<void> {
  const context = await requirePermission(PERMISSIONS.GUIDELINES_CREATE);

  const parsed = guidelineCreateSchema.safeParse({
    organizationId: context.organizationId,
    clinicalDomainId: text(formData, "clinicalDomainId"),
    authorityId: text(formData, "authorityId"),
    internalCode: text(formData, "internalCode"),
    canonicalTitle: text(formData, "canonicalTitle"),
    shortTitle: optionalText(formData, "shortTitle"),
    jurisdiction: optionalText(formData, "jurisdiction"),
    defaultLanguage: (optionalText(formData, "defaultLanguage") || "en") as "en" | "ar",
    description: optionalText(formData, "description"),
  });
  if (!parsed.success) {
    withError("/knowledge/guidelines/new", parsed.error.issues[0]?.message ?? "Invalid guideline.");
  }

  const supabase = await createClient();
  const { data, error } = await supabase
    .rpc("create_guideline", {
      p_organization_id: parsed.data.organizationId,
      p_clinical_domain_id: parsed.data.clinicalDomainId,
      p_authority_id: parsed.data.authorityId,
      p_internal_code: parsed.data.internalCode,
      p_canonical_title: parsed.data.canonicalTitle,
      p_short_title: parsed.data.shortTitle ?? null,
      p_jurisdiction: parsed.data.jurisdiction ?? null,
      p_default_language: parsed.data.defaultLanguage,
      p_description: parsed.data.description ?? null,
    })
    .single();
  if (error) withError("/knowledge/guidelines/new", toGuidelineRegistryError(error).message);

  revalidatePath("/knowledge/guidelines");
  redirect(`/knowledge/guidelines/${(data as { id: string }).id}`);
}

export async function updateGuidelineDraftAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.GUIDELINES_UPDATE_DRAFT);
  const id = text(formData, "id");
  const returnTo = `/knowledge/guidelines/${id}`;

  const parsed = guidelineUpdateSchema.safeParse({
    id,
    canonicalTitle: optionalText(formData, "canonicalTitle"),
    shortTitle: optionalText(formData, "shortTitle"),
    jurisdiction: optionalText(formData, "jurisdiction"),
    description: optionalText(formData, "description"),
  });
  if (!parsed.success) {
    withError(returnTo, parsed.error.issues[0]?.message ?? "Invalid update.");
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("update_guideline_draft", {
    p_id: parsed.data.id,
    p_canonical_title: parsed.data.canonicalTitle ?? null,
    p_short_title: parsed.data.shortTitle ?? null,
    p_jurisdiction: parsed.data.jurisdiction ?? null,
    p_description: parsed.data.description ?? null,
  });
  if (error) withError(returnTo, toGuidelineRegistryError(error).message);

  revalidatePath(returnTo);
  redirect(returnTo);
}

// ---------------------------------------------------------------------------
// Guideline versions
// ---------------------------------------------------------------------------

export async function createGuidelineVersionAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.GUIDELINES_CREATE);
  const guidelineId = text(formData, "guidelineId");
  const returnTo = `/knowledge/guidelines/${guidelineId}`;

  const parsed = guidelineVersionCreateSchema.safeParse({
    guidelineId,
    versionLabel: text(formData, "versionLabel"),
    language: (optionalText(formData, "language") || "en") as "en" | "ar",
    edition: optionalText(formData, "edition"),
    publicationDate: optionalText(formData, "publicationDate"),
    effectiveDate: optionalText(formData, "effectiveDate"),
    reviewDueDate: optionalText(formData, "reviewDueDate"),
    expiryDate: optionalText(formData, "expiryDate"),
    sourceUrl: optionalText(formData, "sourceUrl"),
    externalIdentifier: optionalText(formData, "externalIdentifier"),
    evidenceScope: optionalText(formData, "evidenceScope"),
    targetPopulation: optionalText(formData, "targetPopulation"),
    excludedPopulation: optionalText(formData, "excludedPopulation"),
    methodologySummary: optionalText(formData, "methodologySummary"),
    notes: optionalText(formData, "notes"),
  });
  if (!parsed.success) {
    withError(returnTo, parsed.error.issues[0]?.message ?? "Invalid guideline version.");
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("create_guideline_version", {
    p_guideline_id: parsed.data.guidelineId,
    p_version_label: parsed.data.versionLabel,
    p_edition: parsed.data.edition ?? null,
    p_publication_date: parsed.data.publicationDate ?? null,
    p_effective_date: parsed.data.effectiveDate ?? null,
    p_review_due_date: parsed.data.reviewDueDate ?? null,
    p_expiry_date: parsed.data.expiryDate ?? null,
    p_language: parsed.data.language,
    p_source_url: parsed.data.sourceUrl ?? null,
    p_external_identifier: parsed.data.externalIdentifier ?? null,
    p_evidence_scope: parsed.data.evidenceScope ?? null,
    p_target_population: parsed.data.targetPopulation ?? null,
    p_excluded_population: parsed.data.excludedPopulation ?? null,
    p_methodology_summary: parsed.data.methodologySummary ?? null,
    p_notes: parsed.data.notes ?? null,
  });
  if (error) withError(returnTo, toGuidelineRegistryError(error).message);

  revalidatePath(returnTo);
  redirect(returnTo);
}

export async function updateGuidelineVersionDraftAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.GUIDELINES_UPDATE_DRAFT);
  const id = text(formData, "id");
  const guidelineId = text(formData, "guidelineId");
  const returnTo = `/knowledge/guidelines/${guidelineId}`;

  const parsed = guidelineVersionUpdateSchema.safeParse({
    id,
    edition: optionalText(formData, "edition"),
    publicationDate: optionalText(formData, "publicationDate"),
    effectiveDate: optionalText(formData, "effectiveDate"),
    reviewDueDate: optionalText(formData, "reviewDueDate"),
    expiryDate: optionalText(formData, "expiryDate"),
    sourceUrl: optionalText(formData, "sourceUrl"),
    externalIdentifier: optionalText(formData, "externalIdentifier"),
    evidenceScope: optionalText(formData, "evidenceScope"),
    targetPopulation: optionalText(formData, "targetPopulation"),
    excludedPopulation: optionalText(formData, "excludedPopulation"),
    methodologySummary: optionalText(formData, "methodologySummary"),
    notes: optionalText(formData, "notes"),
  });
  if (!parsed.success) {
    withError(returnTo, parsed.error.issues[0]?.message ?? "Invalid update.");
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("update_guideline_version_draft", {
    p_id: parsed.data.id,
    p_edition: parsed.data.edition ?? null,
    p_publication_date: parsed.data.publicationDate ?? null,
    p_effective_date: parsed.data.effectiveDate ?? null,
    p_review_due_date: parsed.data.reviewDueDate ?? null,
    p_expiry_date: parsed.data.expiryDate ?? null,
    p_source_url: parsed.data.sourceUrl ?? null,
    p_external_identifier: parsed.data.externalIdentifier ?? null,
    p_evidence_scope: parsed.data.evidenceScope ?? null,
    p_target_population: parsed.data.targetPopulation ?? null,
    p_excluded_population: parsed.data.excludedPopulation ?? null,
    p_methodology_summary: parsed.data.methodologySummary ?? null,
    p_notes: parsed.data.notes ?? null,
  });
  if (error) withError(returnTo, toGuidelineRegistryError(error).message);

  revalidatePath(returnTo);
  redirect(returnTo);
}

// ---------------------------------------------------------------------------
// Clinical review
// ---------------------------------------------------------------------------

export async function submitGuidelineReviewAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.GUIDELINES_REVIEW);
  const guidelineVersionId = text(formData, "guidelineVersionId");
  const returnTo = "/reviewer/guidelines";

  const parsed = guidelineReviewSubmitSchema.safeParse({
    guidelineVersionId,
    reviewStatus: text(formData, "reviewStatus"),
    clinicalComments: optionalText(formData, "clinicalComments"),
    safetyConcerns: optionalText(formData, "safetyConcerns"),
    requestedChanges: optionalText(formData, "requestedChanges"),
  });
  if (!parsed.success) {
    withError(returnTo, parsed.error.issues[0]?.message ?? "Invalid review.");
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("submit_guideline_review", {
    p_guideline_version_id: parsed.data.guidelineVersionId,
    p_review_status: parsed.data.reviewStatus,
    p_clinical_comments: parsed.data.clinicalComments ?? null,
    p_safety_concerns: parsed.data.safetyConcerns ?? null,
    p_requested_changes: parsed.data.requestedChanges ?? null,
    p_correlation_id: randomUUID(),
  });
  if (error) withError(returnTo, toGuidelineRegistryError(error).message);

  revalidatePath(returnTo);
  redirect(returnTo);
}

// ---------------------------------------------------------------------------
// Lifecycle transitions — one shared implementation, one permission per
// target status, matching migration 0005's transition_guideline_version.
// ---------------------------------------------------------------------------

async function runTransition(
  formData: FormData,
  targetStatus: LifecycleStatus,
  permission: (typeof PERMISSIONS)[keyof typeof PERMISSIONS]
): Promise<void> {
  await requirePermission(permission);
  const versionId = text(formData, "versionId");
  const guidelineId = text(formData, "guidelineId");
  const returnTo = `/knowledge/guidelines/${guidelineId}`;

  const parsed = lifecycleTransitionSchema.safeParse({
    versionId,
    targetStatus,
    reason: optionalText(formData, "reason"),
  });
  if (!parsed.success) {
    withError(returnTo, parsed.error.issues[0]?.message ?? "Invalid transition.");
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("transition_guideline_version", {
    p_version_id: parsed.data.versionId,
    p_target_status: parsed.data.targetStatus,
    p_reason: parsed.data.reason ?? null,
    p_correlation_id: randomUUID(),
  });
  if (error) withError(returnTo, toGuidelineRegistryError(error).message);

  revalidatePath(returnTo);
  redirect(returnTo);
}

export async function submitGuidelineForReviewAction(formData: FormData): Promise<void> {
  return runTransition(formData, "ready_for_review", PERMISSIONS.GUIDELINES_SUBMIT_FOR_REVIEW);
}

export async function returnGuidelineVersionToDraftAction(formData: FormData): Promise<void> {
  // Permission is actually either guidelines.review or
  // guidelines.submit_for_review (approved -> draft additionally accepts
  // guidelines.approve) — the database is authoritative; the app-layer
  // gate here uses the broadest of the three so legitimate callers are not
  // redirected to /403 before the database even evaluates the specific
  // transition. See migration 0005, transition_guideline_version.
  await requirePermission(PERMISSIONS.GUIDELINES_REVIEW);
  const versionId = text(formData, "versionId");
  const guidelineId = text(formData, "guidelineId");
  const returnTo = `/knowledge/guidelines/${guidelineId}`;

  const parsed = lifecycleTransitionSchema.safeParse({
    versionId,
    targetStatus: "draft",
    reason: optionalText(formData, "reason"),
  });
  if (!parsed.success || !parsed.data.reason) {
    withError(returnTo, "A reason is required to return this version to draft.");
    return;
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("transition_guideline_version", {
    p_version_id: parsed.data.versionId,
    p_target_status: "draft",
    p_reason: parsed.data.reason,
    p_correlation_id: randomUUID(),
  });
  if (error) withError(returnTo, toGuidelineRegistryError(error).message);

  revalidatePath(returnTo);
  redirect(returnTo);
}

export async function approveGuidelineVersionAction(formData: FormData): Promise<void> {
  return runTransition(formData, "approved", PERMISSIONS.GUIDELINES_APPROVE);
}

export async function activateGuidelineVersionAction(formData: FormData): Promise<void> {
  return runTransition(formData, "active", PERMISSIONS.GUIDELINES_ACTIVATE);
}

export async function supersedeGuidelineVersionAction(formData: FormData): Promise<void> {
  return runTransition(formData, "superseded", PERMISSIONS.GUIDELINES_SUPERSEDE);
}

export async function withdrawGuidelineVersionAction(formData: FormData): Promise<void> {
  return runTransition(formData, "withdrawn", PERMISSIONS.GUIDELINES_WITHDRAW);
}
