export const PERMISSIONS = {
  WORKSPACE_CLINICIAN_ACCESS: "workspace.clinician.access",
  WORKSPACE_ADMIN_ACCESS: "workspace.admin.access",
  WORKSPACE_REVIEWER_ACCESS: "workspace.reviewer.access",
  WORKSPACE_QUALITY_ACCESS: "workspace.quality.access",
  ORGANIZATION_MEMBERS_READ: "organization.members.read",
  ORGANIZATION_MEMBERS_MANAGE: "organization.members.manage",
  AUDIT_READ: "audit.read",

  // Guideline registry (Sprint 1) — see docs/domain/guideline-lifecycle.md
  GUIDELINES_READ_ACTIVE: "guidelines.read_active",
  GUIDELINES_READ_ALL: "guidelines.read_all",
  GUIDELINES_CREATE: "guidelines.create",
  GUIDELINES_UPDATE_DRAFT: "guidelines.update_draft",
  GUIDELINES_SUBMIT_FOR_REVIEW: "guidelines.submit_for_review",
  GUIDELINES_REVIEW: "guidelines.review",
  GUIDELINES_APPROVE: "guidelines.approve",
  GUIDELINES_ACTIVATE: "guidelines.activate",
  GUIDELINES_SUPERSEDE: "guidelines.supersede",
  GUIDELINES_WITHDRAW: "guidelines.withdraw",
  GUIDELINE_AUTHORITIES_MANAGE: "guideline_authorities.manage",
  CLINICAL_DOMAINS_MANAGE: "clinical_domains.manage",

  // Secure document intake (Sprint 1.1) — see docs/domain/document-intake-lifecycle.md
  GUIDELINE_DOCUMENTS_READ: "guideline_documents.read",
  GUIDELINE_DOCUMENTS_UPLOAD: "guideline_documents.upload",
  GUIDELINE_DOCUMENTS_VERIFY: "guideline_documents.verify",
  GUIDELINE_DOCUMENTS_REJECT: "guideline_documents.reject",
  GUIDELINE_DOCUMENTS_REGISTER: "guideline_documents.register",
  GUIDELINE_PROCESSING_JOBS_READ: "guideline_processing_jobs.read",
  GUIDELINE_PROCESSING_JOBS_CREATE: "guideline_processing_jobs.create",
  GUIDELINE_PROCESSING_JOBS_CANCEL: "guideline_processing_jobs.cancel",
  GUIDELINE_EXTRACTIONS_READ: "guideline_extractions.read",
  GUIDELINE_EXTRACTIONS_READ_PAGES: "guideline_extractions.read_pages",
  GUIDELINE_EXTRACTIONS_READ_ARTIFACTS: "guideline_extractions.read_artifacts",
  GUIDELINE_EXTRACTIONS_INVALIDATE: "guideline_extractions.invalidate",
  GUIDELINE_EXTRACTIONS_RETRY: "guideline_extractions.retry",

  // Extraction review and technical quality gate (Sprint 1-D1) — see
  // docs/domain/extraction-review-lifecycle.md. Deliberately a separate
  // namespace from guideline_extractions.* above (execution/read-only) —
  // this permission model enforces the review/execution architecture
  // boundary from the outside too, not just inside the schema (ADR 0011).
  GUIDELINE_EXTRACTION_REVIEWS_READ: "guideline_extraction_reviews.read",
  GUIDELINE_EXTRACTION_REVIEWS_CREATE: "guideline_extraction_reviews.create",
  GUIDELINE_EXTRACTION_REVIEWS_ASSIGN: "guideline_extraction_reviews.assign",
  GUIDELINE_EXTRACTION_REVIEWS_REVIEW: "guideline_extraction_reviews.review",
  GUIDELINE_EXTRACTION_REVIEWS_SUBMIT: "guideline_extraction_reviews.submit",
  GUIDELINE_EXTRACTION_REVIEWS_REOPEN: "guideline_extraction_reviews.reopen",
  GUIDELINE_EXTRACTION_FINDINGS_CREATE: "guideline_extraction_findings.create",
  GUIDELINE_EXTRACTION_FINDINGS_RESOLVE: "guideline_extraction_findings.resolve",
  GUIDELINE_EXTRACTION_SOURCE_READ: "guideline_extraction_source.read",

  // Controlled page-scoped OCR (Sprint 1-D2) — see
  // docs/domain/ocr-eligibility-and-lifecycle.md. Again a deliberately
  // separate namespace, one layer deeper (ADR 0012).
  GUIDELINE_OCR_READ: "guideline_ocr.read",
  GUIDELINE_OCR_CREATE: "guideline_ocr.create",
  GUIDELINE_OCR_CANCEL: "guideline_ocr.cancel",
  GUIDELINE_OCR_REVIEW: "guideline_ocr.review",
  GUIDELINE_OCR_SUBMIT_REVIEW: "guideline_ocr.submit_review",
  GUIDELINE_OCR_REOPEN_REVIEW: "guideline_ocr.reopen_review",
  GUIDELINE_OCR_READ_ARTIFACTS: "guideline_ocr.read_artifacts",
  GUIDELINE_OCR_READ_SOURCE: "guideline_ocr.read_source",
  GUIDELINE_OCR_REPROCESS: "guideline_ocr.reprocess",

  // Deterministic page-aware chunking (Sprint 1-D3) — see
  // docs/domain/chunking-technical-review.md. Again a deliberately
  // separate namespace, one layer deeper (ADR 0014). No dedicated
  // "cancel" key — chunking jobs are cancelled through the existing
  // generic GUIDELINE_PROCESSING_JOBS_CANCEL permission (a documented
  // scope decision, migration 0012).
  GUIDELINE_CHUNKING_READ: "guideline_chunking.read",
  GUIDELINE_CHUNKING_CREATE: "guideline_chunking.create",
  GUIDELINE_CHUNKING_READ_ARTIFACTS: "guideline_chunking.read_artifacts",
  GUIDELINE_CHUNKING_REVIEW: "guideline_chunking.review",
  GUIDELINE_CHUNKING_SUBMIT_REVIEW: "guideline_chunking.submit_review",
  GUIDELINE_CHUNKING_REOPEN_REVIEW: "guideline_chunking.reopen_review",
  GUIDELINE_CHUNKING_INVALIDATE: "guideline_chunking.invalidate",
} as const;

export type PermissionKey = (typeof PERMISSIONS)[keyof typeof PERMISSIONS];
