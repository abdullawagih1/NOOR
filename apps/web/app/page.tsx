import { PageHeader, Card } from "@noor/ui";

export default function HomePage() {
  return (
    <main className="mx-auto flex max-w-2xl flex-col gap-lg p-xl">
      <PageHeader eyebrow="Noor V1 — Sprint 0.5" title="Noor — Clinical Intelligence OS" />
      <p className="text-base text-body">
        Evidence-grounded clinical evidence assistant. This build establishes the
        application shell, real authentication, and the Noor design-system
        foundation; no clinical data or generation pipeline is wired yet.
      </p>
      <Card>
        <strong className="text-sm font-semibold text-ink">Workspaces (content stubs, real auth)</strong>
        <ul className="mt-sm flex flex-col gap-xs text-sm">
          <li>
            <a href="/clinician" className="text-primary hover:underline">Clinician Workspace</a>
          </li>
          <li>
            <a href="/admin" className="text-primary hover:underline">Admin Workspace</a>
          </li>
          <li>
            <a href="/reviewer" className="text-primary hover:underline">Clinical Reviewer Workspace</a>
          </li>
          <li>
            <a href="/quality" className="text-primary hover:underline">Quality &amp; Safety Workspace</a>
          </li>
        </ul>
      </Card>
      <a href="/login" className="text-sm text-primary hover:underline">Sign in →</a>
    </main>
  );
}
