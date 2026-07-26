import Link from "next/link";
import { PageHeader, Badge, ClinicalQuestionBar, EmptyState, Button } from "@noor/ui";

export default function ClinicianPage() {
  return (
    <main className="flex flex-col gap-lg">
      <PageHeader
        eyebrow="Sprint 1 — Guideline Registry"
        title="Clinician Workspace"
        description="Submit clinical questions within the approved domain and review evidence-grounded, cited answers."
        actions={<Badge>Requires workspace.clinician.access</Badge>}
      />
      <ClinicalQuestionBar disabled placeholder="Ask a clinical question — not wired to retrieval yet" />
      <EmptyState
        title="No answers yet"
        description="Retrieval and generation are still Sprint 1+ scope. The registry of active, approved guidance now exists and is real — see Active Clinical Knowledge. Granted to clinician, clinical_pharmacist."
        action={
          <Link href="/clinician/knowledge">
            <Button variant="secondary">View Active Clinical Knowledge</Button>
          </Link>
        }
      />
    </main>
  );
}
