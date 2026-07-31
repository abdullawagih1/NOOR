import Link from "next/link";
import { PublicShell } from "./PublicShell";
import { Button } from "@noor/ui";

const CAPABILITIES = [
  {
    title: "Guideline Governance",
    description: "Controlled versions, review, approval, activation, supersession, and withdrawal.",
  },
  {
    title: "Secure Document Intake",
    description: "Private, checksum-verified source registration with tenant-safe access.",
  },
  {
    title: "Deterministic Extraction",
    description: "Reproducible page-level text and immutable artifacts.",
  },
  {
    title: "Technical Quality Review",
    description: "Human review, findings, and downstream eligibility decisions.",
  },
  {
    title: "Controlled OCR",
    description: "Page-scoped OCR only where explicitly approved by reviewers.",
  },
  {
    title: "Auditable Processing",
    description: "Durable jobs, attempts, retries, recovery, and traceable provenance.",
  },
] as const;

const WORKFLOW = [
  "Guideline",
  "Verified Source",
  "Extraction",
  "Technical Review",
  "Controlled OCR",
  "Future Knowledge Preparation",
] as const;

export default function HomePage() {
  return (
    <PublicShell>
      {/* Hero */}
      <section className="bg-surface-soft">
        <div className="mx-auto grid max-w-6xl gap-xl px-lg py-xxl lg:grid-cols-2 lg:items-center">
          <div className="flex flex-col gap-lg">
            <div className="h-1 w-16 rounded-pill bg-brand-gradient" aria-hidden="true" />
            <h1 className="text-3xl font-semibold text-ink sm:text-4xl">NOOR — Clinical Intelligence OS</h1>
            <p className="text-lg text-body">Evidence-governed knowledge operations for clinical teams.</p>
            <p className="text-sm text-muted">
              Manage trusted clinical guidelines, verify source documents, extract page-level content
              deterministically, and review technical quality through a controlled and auditable
              workflow.
            </p>
            <div className="flex flex-wrap items-center gap-md">
              <Link href="/login">
                <Button variant="primary">Sign in to NOOR</Button>
              </Link>
              <a href="#how-it-works" className="text-sm font-medium text-primary hover:underline">
                Learn how NOOR works
              </a>
            </div>
          </div>
          <div className="flex flex-col gap-sm rounded-lg border border-border bg-canvas p-lg shadow-card">
            <span className="text-xs font-semibold uppercase tracking-wide text-muted">Controlled workflow</span>
            <ol className="flex flex-col gap-xs">
              {WORKFLOW.map((step, index) => (
                <li key={step} className="flex items-center gap-sm rounded-md border border-border bg-surface-soft px-md py-sm">
                  <span className="flex h-6 w-6 flex-none items-center justify-center rounded-pill bg-primary text-xs font-semibold text-on-primary">
                    {index + 1}
                  </span>
                  <span className="text-sm text-ink">{step}</span>
                </li>
              ))}
            </ol>
            <p className="text-xs text-muted">
              Retrieval and clinical answer generation are future work, not yet available.
            </p>
          </div>
        </div>
      </section>

      {/* Capabilities */}
      <section id="how-it-works" className="mx-auto max-w-6xl px-lg py-xxl">
        <div className="flex flex-col gap-xxs text-center">
          <h2 className="text-2xl font-semibold text-ink">What NOOR does today</h2>
          <p className="mx-auto max-w-2xl text-sm text-muted">
            A controlled foundation for clinical guideline knowledge — built on explicit human review
            and auditable provenance at every stage.
          </p>
        </div>
        <div className="mt-xl grid gap-lg sm:grid-cols-2 lg:grid-cols-3">
          {CAPABILITIES.map((capability) => (
            <div key={capability.title} className="flex flex-col gap-xs rounded-lg border border-border bg-canvas p-lg shadow-card">
              <span className="h-1.5 w-8 rounded-pill bg-accent" aria-hidden="true" />
              <h3 className="text-base font-semibold text-ink">{capability.title}</h3>
              <p className="text-sm text-muted">{capability.description}</p>
            </div>
          ))}
        </div>
      </section>

      {/* Trust / safety */}
      <section className="border-t border-border bg-surface-soft">
        <div className="mx-auto max-w-3xl px-lg py-xxl text-center">
          <h2 className="text-2xl font-semibold text-ink">Built on controlled evidence</h2>
          <p className="mt-sm text-sm text-muted">
            Every stage is built around controlled evidence, explicit human review, tenant isolation,
            immutable provenance, and auditable lifecycle decisions.
          </p>
        </div>
      </section>
    </PublicShell>
  );
}
