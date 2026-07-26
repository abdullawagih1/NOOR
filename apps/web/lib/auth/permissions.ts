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
} as const;

export type PermissionKey = (typeof PERMISSIONS)[keyof typeof PERMISSIONS];
