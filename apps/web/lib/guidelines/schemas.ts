import { z } from "zod";

/**
 * Validation schemas for the guideline registry (Sprint 1). These are the
 * authoritative validation layer — every Server Action in
 * lib/guidelines/actions.ts parses FormData/input through one of these
 * before calling the corresponding database RPC, so HTML form validation
 * (or its absence) never determines correctness.
 *
 * Enum values here must stay in lockstep with the check constraints in
 * supabase/migrations/0005_guideline_registry_and_lifecycle.sql — that
 * migration is the source of truth; these mirror it for early client/server
 * feedback, not as a replacement for the database constraint.
 */

export const LIFECYCLE_STATUSES = [
  "draft",
  "ready_for_review",
  "approved",
  "active",
  "superseded",
  "withdrawn",
] as const;
export type LifecycleStatus = (typeof LIFECYCLE_STATUSES)[number];

export const REVIEW_STATUSES = [
  "pending",
  "changes_requested",
  "recommended_for_approval",
  "rejected",
] as const;
export type ReviewStatus = (typeof REVIEW_STATUSES)[number];

const nonEmptyText = (label: string) => z.string().trim().min(1, `${label} is required`);
const optionalText = z
  .string()
  .trim()
  .transform((v) => (v.length === 0 ? undefined : v))
  .optional();
const optionalDate = z
  .string()
  .trim()
  .transform((v) => (v.length === 0 ? undefined : v))
  .refine((v) => v === undefined || !Number.isNaN(Date.parse(v)), "Invalid date")
  .optional();

export const clinicalDomainCreateSchema = z.object({
  organizationId: z.string().uuid(),
  code: nonEmptyText("Domain code").max(64),
  name: nonEmptyText("Domain name").max(200),
  description: optionalText,
});
export type ClinicalDomainCreateInput = z.infer<typeof clinicalDomainCreateSchema>;

export const clinicalDomainUpdateSchema = z.object({
  id: z.string().uuid(),
  name: optionalText,
  description: optionalText,
  isActive: z.boolean().optional(),
});
export type ClinicalDomainUpdateInput = z.infer<typeof clinicalDomainUpdateSchema>;

export const guidelineAuthorityCreateSchema = z.object({
  organizationId: z.string().uuid(),
  name: nonEmptyText("Authority name").max(200),
  shortName: optionalText,
  authorityType: optionalText,
  countryOrRegion: optionalText,
  officialWebsite: optionalText,
  isVerified: z.boolean().default(false),
  verificationNotes: optionalText,
});
export type GuidelineAuthorityCreateInput = z.infer<typeof guidelineAuthorityCreateSchema>;

export const guidelineAuthorityUpdateSchema = guidelineAuthorityCreateSchema
  .omit({ organizationId: true })
  .partial()
  .extend({ id: z.string().uuid() });
export type GuidelineAuthorityUpdateInput = z.infer<typeof guidelineAuthorityUpdateSchema>;

export const guidelineCreateSchema = z.object({
  organizationId: z.string().uuid(),
  clinicalDomainId: z.string().uuid(),
  authorityId: z.string().uuid(),
  internalCode: nonEmptyText("Internal code").max(64),
  canonicalTitle: nonEmptyText("Canonical title").max(300),
  shortTitle: optionalText,
  jurisdiction: optionalText,
  defaultLanguage: z.enum(["en", "ar"]).default("en"),
  description: optionalText,
});
export type GuidelineCreateInput = z.infer<typeof guidelineCreateSchema>;

export const guidelineUpdateSchema = z.object({
  id: z.string().uuid(),
  canonicalTitle: optionalText,
  shortTitle: optionalText,
  jurisdiction: optionalText,
  description: optionalText,
});
export type GuidelineUpdateInput = z.infer<typeof guidelineUpdateSchema>;

const guidelineVersionSharedFields = {
  edition: optionalText,
  publicationDate: optionalDate,
  effectiveDate: optionalDate,
  reviewDueDate: optionalDate,
  expiryDate: optionalDate,
  sourceUrl: optionalText,
  externalIdentifier: optionalText,
  evidenceScope: optionalText,
  targetPopulation: optionalText,
  excludedPopulation: optionalText,
  methodologySummary: optionalText,
  notes: optionalText,
};

export const guidelineVersionCreateSchema = z
  .object({
    guidelineId: z.string().uuid(),
    versionLabel: nonEmptyText("Version label").max(64),
    language: z.enum(["en", "ar"]).default("en"),
    ...guidelineVersionSharedFields,
  })
  .refine(
    (v) => !v.publicationDate || !v.effectiveDate || v.effectiveDate >= v.publicationDate,
    { message: "Effective date cannot be before publication date", path: ["effectiveDate"] }
  )
  .refine(
    (v) => !v.effectiveDate || !v.expiryDate || v.expiryDate > v.effectiveDate,
    { message: "Expiry date must be after effective date", path: ["expiryDate"] }
  );
export type GuidelineVersionCreateInput = z.infer<typeof guidelineVersionCreateSchema>;

export const guidelineVersionUpdateSchema = z.object({
  id: z.string().uuid(),
  ...guidelineVersionSharedFields,
});
export type GuidelineVersionUpdateInput = z.infer<typeof guidelineVersionUpdateSchema>;

export const guidelineReviewSubmitSchema = z.object({
  guidelineVersionId: z.string().uuid(),
  reviewStatus: z.enum(REVIEW_STATUSES),
  clinicalComments: optionalText,
  safetyConcerns: optionalText,
  requestedChanges: optionalText,
});
export type GuidelineReviewSubmitInput = z.infer<typeof guidelineReviewSubmitSchema>;

/**
 * A reason is optional at the schema layer for transitions where the
 * database allows it (e.g. draft -> ready_for_review) and required for
 * others (ready_for_review -> draft, approved -> draft, *-> withdrawn) —
 * the database is the authoritative enforcement point (see migration
 * 0005's transition_guideline_version), this only gives early UI feedback
 * for the reason-required cases via lifecycleTransitionSchema.refine below.
 */
const REASON_REQUIRED_TARGETS: ReadonlySet<LifecycleStatus> = new Set(["withdrawn"]);

export const lifecycleTransitionSchema = z
  .object({
    versionId: z.string().uuid(),
    targetStatus: z.enum(LIFECYCLE_STATUSES),
    reason: optionalText,
  })
  .refine(
    (v) => !REASON_REQUIRED_TARGETS.has(v.targetStatus) || (v.reason && v.reason.length > 0),
    { message: "A reason is required for this transition", path: ["reason"] }
  );
export type LifecycleTransitionInput = z.infer<typeof lifecycleTransitionSchema>;

export const guidelineQueryFiltersSchema = z.object({
  search: optionalText,
  clinicalDomainId: z.string().uuid().optional(),
  authorityId: z.string().uuid().optional(),
  lifecycleStatus: z.enum(LIFECYCLE_STATUSES).optional(),
});
export type GuidelineQueryFilters = z.infer<typeof guidelineQueryFiltersSchema>;
