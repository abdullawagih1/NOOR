import { PageHeader, Badge, ClinicalQuestionBar, EmptyState } from "@noor/ui";

export default function ClinicianPage() {
  return (
    <main className="flex flex-col gap-lg">
      <PageHeader
        eyebrow="Sprint 0.5 — content stub, real auth"
        title="Clinician Workspace"
        description="Submit clinical questions within the approved domain and review evidence-grounded, cited answers."
        actions={<Badge>Requires workspace.clinician.access</Badge>}
      />
      <ClinicalQuestionBar disabled placeholder="Ask a clinical question — not wired to retrieval yet" />
      <EmptyState
        title="No answers yet"
        description="Session resolution, active-membership checks, and permission enforcement are real — you could not have reached this page without them. Retrieval and generation are Sprint 1+ scope. Granted to clinician, clinical_pharmacist."
      />
    </main>
  );
}
