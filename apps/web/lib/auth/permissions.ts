export const PERMISSIONS = {
  WORKSPACE_CLINICIAN_ACCESS: "workspace.clinician.access",
  WORKSPACE_ADMIN_ACCESS: "workspace.admin.access",
  WORKSPACE_REVIEWER_ACCESS: "workspace.reviewer.access",
  WORKSPACE_QUALITY_ACCESS: "workspace.quality.access",
  ORGANIZATION_MEMBERS_READ: "organization.members.read",
  ORGANIZATION_MEMBERS_MANAGE: "organization.members.manage",
  AUDIT_READ: "audit.read",
} as const;

export type PermissionKey = (typeof PERMISSIONS)[keyof typeof PERMISSIONS];
