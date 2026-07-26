import { requirePermission } from "@/lib/auth/context";
import { PERMISSIONS } from "@/lib/auth/permissions";
import { listClinicalDomains, listGuidelineAuthorities } from "@/lib/guidelines/queries";
import { createClinicalDomainAction, createGuidelineAuthorityAction, createGuidelineAction } from "@/lib/guidelines/actions";
import { PageHeader, Card, Section, TextInput, Select, Textarea, Button, Alert } from "@noor/ui";

export const dynamic = "force-dynamic";

export default async function NewGuidelinePage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const context = await requirePermission(PERMISSIONS.GUIDELINES_CREATE);
  const params = await searchParams;

  const [domains, authorities] = await Promise.all([
    listClinicalDomains(context.organizationId),
    listGuidelineAuthorities(context.organizationId),
  ]);

  return (
    <main className="flex flex-col gap-lg">
      <PageHeader
        eyebrow="Sprint 1 — Guideline Registry"
        title="New Guideline"
        description="Registers a new guideline identity and its first draft version. No file upload happens here — that is Sprint 1's next task."
      />

      {params.error ? <Alert tone="critical" title="Could not complete that action">{params.error}</Alert> : null}

      <div className="grid gap-lg lg:grid-cols-[2fr_1fr]">
        <Card>
          <Section title="Guideline identity">
            <form action={createGuidelineAction} className="flex flex-col gap-md">
              <div className="grid gap-md sm:grid-cols-2">
                <Select label="Clinical domain" name="clinicalDomainId" required defaultValue="">
                  <option value="" disabled>
                    Select a domain
                  </option>
                  {domains.map((d) => (
                    <option key={d.id} value={d.id}>
                      {d.name}
                    </option>
                  ))}
                </Select>
                <Select label="Guideline authority" name="authorityId" required defaultValue="">
                  <option value="" disabled>
                    Select an authority
                  </option>
                  {authorities.map((a) => (
                    <option key={a.id} value={a.id}>
                      {a.name} {a.is_verified ? "" : "(unverified)"}
                    </option>
                  ))}
                </Select>
              </div>

              <TextInput label="Internal code" name="internalCode" placeholder="e.g. HTN-001" required hint="Unique per organization." />
              <TextInput label="Canonical title" name="canonicalTitle" placeholder="e.g. Adult Hypertension Management" required />
              <div className="grid gap-md sm:grid-cols-2">
                <TextInput label="Short title" name="shortTitle" />
                <TextInput label="Jurisdiction" name="jurisdiction" placeholder="e.g. Global, Egypt, MENA" />
              </div>
              <Select label="Default language" name="defaultLanguage" defaultValue="en">
                <option value="en">English</option>
                <option value="ar">Arabic</option>
              </Select>
              <Textarea label="Description" name="description" />

              <div>
                <Button type="submit" disabled={domains.length === 0 || authorities.length === 0}>
                  Create guideline
                </Button>
                {domains.length === 0 || authorities.length === 0 ? (
                  <p className="mt-xs text-sm text-muted">
                    Create at least one clinical domain and one guideline authority first (right).
                  </p>
                ) : null}
              </div>
            </form>
          </Section>
        </Card>

        <div className="flex flex-col gap-lg">
          <Card>
            <Section title="New clinical domain" description="Pending clinical confirmation — see PROJECT_STATE.md gap G-03.">
              <form action={createClinicalDomainAction} className="flex flex-col gap-sm">
                <input type="hidden" name="returnTo" value="/knowledge/guidelines/new" />
                <TextInput label="Code" name="code" placeholder="e.g. hypertension" required />
                <TextInput label="Name" name="name" placeholder="e.g. Adult Hypertension" required />
                <Textarea label="Description" name="description" />
                <Button type="submit" variant="secondary" size="sm">
                  Add domain
                </Button>
              </form>
            </Section>
          </Card>

          <Card>
            <Section title="New guideline authority">
              <form action={createGuidelineAuthorityAction} className="flex flex-col gap-sm">
                <input type="hidden" name="returnTo" value="/knowledge/guidelines/new" />
                <TextInput label="Name" name="name" required />
                <TextInput label="Short name" name="shortName" />
                <TextInput label="Type" name="authorityType" placeholder="e.g. society, ministry" />
                <TextInput label="Country / region" name="countryOrRegion" />
                <TextInput label="Official website" name="officialWebsite" />
                <label className="flex items-center gap-xs text-sm text-body">
                  <input type="checkbox" name="isVerified" className="h-4 w-4" />
                  Verified — an explicit clinical-governance decision, never inferred from the URL alone
                </label>
                <Textarea label="Verification notes" name="verificationNotes" />
                <Button type="submit" variant="secondary" size="sm">
                  Add authority
                </Button>
              </form>
            </Section>
          </Card>
        </div>
      </div>
    </main>
  );
}
