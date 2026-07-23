import { notFound } from "next/navigation";
import {
  spacing,
  radius,
  shadows,
  typeScale,
  semanticStates,
  Button,
  IconButton,
  TextInput,
  PasswordInput,
  Textarea,
  Select,
  Checkbox,
  Radio,
  Badge,
  SemanticStatusBadge,
  Alert,
  Card,
  Section,
  PageHeader,
  EmptyState,
  ErrorState,
  LoadingState,
  Skeleton,
  Tabs,
  Breadcrumb,
  Table,
  TableHead,
  TableBody,
  TableRow,
  TableHeaderCell,
  TableCell,
  Pagination,
  Tooltip,
  EvidenceCard,
  CitationCard,
  ProcessingTimeline,
  PermissionDeniedPanel,
  ClinicalQuestionBar,
  ClinicalWarningPanel,
  AIGeneratedLabel,
  HumanApprovedLabel,
  type SemanticStateKey,
} from "@noor/ui";

/**
 * Development-only showcase — see docs/design-system/NOOR_DESIGN_SYSTEM.md
 * §"Showcase route". Renders mocked data only; no live query, no auth
 * bypass, no secret ever touches this page. 404s outside development so it
 * is never reachable in a Preview/Production deployment.
 */
export default function DesignSystemPage() {
  if (process.env.NODE_ENV === "production") {
    notFound();
  }

  return (
    <main className="mx-auto flex max-w-4xl flex-col gap-xxl p-xl">
      <PageHeader
        eyebrow="Internal — development only"
        title="Noor Design System"
        description="Foundation tokens and components. This route 404s in production builds."
      />

      <Section title="Colors">
        <div className="grid grid-cols-2 gap-sm sm:grid-cols-4">
          {["primary", "primary-active", "primary-soft", "ink", "body", "muted", "muted-soft", "canvas", "surface-soft", "surface-strong", "border", "border-strong"].map((name) => (
            <div key={name} className="flex flex-col gap-xxs">
              <div className="h-12 rounded-md border border-border" style={{ backgroundColor: `var(--noor-color-${name})` }} />
              <span className="text-xs text-muted">{name}</span>
            </div>
          ))}
        </div>
      </Section>

      <Section title="Semantic states" description="Color is never the only signal — every state carries an icon and label too.">
        <div className="flex flex-wrap gap-sm">
          {(Object.keys(semanticStates) as SemanticStateKey[]).map((key) => (
            <SemanticStatusBadge key={key} state={key} />
          ))}
        </div>
      </Section>

      <Section title="Typography">
        <div className="flex flex-col gap-sm">
          {Object.entries(typeScale).map(([key, scale]) => (
            <p key={key} style={{ fontSize: scale.fontSize, lineHeight: scale.lineHeight, fontWeight: scale.fontWeight }}>
              {key} — Evidence-grounded clinical decision support
            </p>
          ))}
        </div>
      </Section>

      <Section title="Spacing">
        <div className="flex flex-wrap items-end gap-sm">
          {Object.entries(spacing).map(([key, value]) => (
            <div key={key} className="flex flex-col items-center gap-xxs">
              <div className="bg-primary-soft" style={{ width: value, height: value }} />
              <span className="text-xs text-muted">{key}</span>
            </div>
          ))}
        </div>
      </Section>

      <Section title="Radius">
        <div className="flex flex-wrap gap-sm">
          {Object.entries(radius).map(([key, value]) => (
            <div key={key} className="flex h-16 w-16 items-center justify-center border border-border-strong text-xs text-muted" style={{ borderRadius: value }}>
              {key}
            </div>
          ))}
        </div>
      </Section>

      <Section title="Shadows">
        <div className="flex flex-wrap gap-lg">
          {Object.entries(shadows).map(([key, value]) => (
            <div key={key} className="flex h-16 w-32 items-center justify-center rounded-md bg-canvas text-xs text-muted" style={{ boxShadow: value }}>
              {key}
            </div>
          ))}
        </div>
      </Section>

      <Section title="Buttons">
        <div className="flex flex-wrap items-center gap-sm">
          <Button variant="primary">Primary</Button>
          <Button variant="secondary">Secondary</Button>
          <Button variant="text">Text</Button>
          <Button variant="danger">Danger</Button>
          <Button variant="primary" disabled>Disabled</Button>
          <IconButton label="Notifications">🔔</IconButton>
        </div>
      </Section>

      <Section title="Form inputs">
        <div className="grid max-w-md gap-md">
          <TextInput label="Email" placeholder="you@organization.org" />
          <PasswordInput label="Password" placeholder="••••••••" />
          <Textarea label="Notes" placeholder="Optional context" />
          <Select label="Clinical domain">
            <option>Adult Hypertension</option>
          </Select>
          <Checkbox label="I have reviewed this extraction" />
          <Radio label="Approve" name="ds-radio" />
        </div>
      </Section>

      <Section title="Tags and alerts">
        <div className="flex flex-wrap gap-sm">
          <Badge>Draft</Badge>
          <Badge>Adult Hypertension</Badge>
        </div>
        <Alert tone="info" title="Informational">This is a neutral, informational message.</Alert>
        <Alert tone="warning" title="Warning">Some evidence is only partially supported.</Alert>
        <Alert tone="critical" title="Critical">A safety-relevant issue needs immediate attention.</Alert>
        <Alert tone="success" title="Verified">This record has been checked and confirmed.</Alert>
      </Section>

      <Section title="Empty / loading / error / skeleton states">
        <div className="grid gap-md sm:grid-cols-2">
          <EmptyState title="No guidelines yet" description="Nothing has been registered for this organization." />
          <ErrorState description="We couldn't load this page. Try again." />
          <LoadingState label="Fetching evidence…" />
          <div className="flex flex-col gap-xs">
            <Skeleton className="h-4 w-3/4" />
            <Skeleton className="h-4 w-1/2" />
            <Skeleton className="h-24 w-full" />
          </div>
        </div>
      </Section>

      <Section title="Navigation">
        <Breadcrumb items={[{ label: "Admin", href: "/admin" }, { label: "Members" }]} />
        <Tabs
          items={[
            { key: "one", label: "Overview", content: <p className="text-sm text-body">Overview content.</p> },
            { key: "two", label: "History", content: <p className="text-sm text-body">History content.</p> },
          ]}
        />
      </Section>

      <Section title="Table foundation">
        <Table>
          <TableHead>
            <TableRow>
              <TableHeaderCell>Guideline</TableHeaderCell>
              <TableHeaderCell>Status</TableHeaderCell>
            </TableRow>
          </TableHead>
          <TableBody>
            <TableRow>
              <TableCell>ACC/AHA Hypertension 2025</TableCell>
              <TableCell><SemanticStatusBadge state="verified" /></TableCell>
            </TableRow>
            <TableRow>
              <TableCell>Legacy Draft v1</TableCell>
              <TableCell><SemanticStatusBadge state="superseded" /></TableCell>
            </TableRow>
          </TableBody>
        </Table>
        <Pagination page={1} pageCount={3} onPageChange={() => undefined} />
      </Section>

      <Section title="Tooltip">
        <Tooltip label="Server-side permission check, not just a UI hint">
          <Button variant="secondary">Hover me</Button>
        </Tooltip>
      </Section>

      <Section title="Clinical components (mocked data only)">
        <ClinicalQuestionBar />
        <ClinicalWarningPanel title="Requires clinician review" severity="warning">
          This recommendation cites limited evidence and needs clinician sign-off before use.
        </ClinicalWarningPanel>
        <div className="flex gap-sm">
          <AIGeneratedLabel />
          <HumanApprovedLabel reviewerName="Dr. Amina R." />
        </div>
        <EvidenceCard
          status="evidencePartial"
          guidelineTitle="ACC/AHA Hypertension Guideline 2025"
          guidelineVersion="2.1"
          summary="Lifestyle modification is recommended as first-line therapy for Stage 1 hypertension without compelling indications."
        />
        <CitationCard
          sourceTitle="ACC/AHA Hypertension Guideline 2025"
          pageReference="Section 6.2, p. 34"
          excerpt="Non-pharmacological interventions should be attempted for at least 3 months prior to initiating pharmacotherapy in low-risk patients."
        />
        <ProcessingTimeline
          steps={[
            { label: "Document uploaded", state: "done", timestamp: "10:02" },
            { label: "Parsing", state: "done", timestamp: "10:03" },
            { label: "Chunking", state: "active" },
            { label: "Reviewer approval", state: "pending" },
          ]}
        />
        <PermissionDeniedPanel
          title="No active organization membership"
          description="Contact your organization administrator to request access."
        />
      </Section>

      <Section title="RTL / LTR" description="Arabic uses IBM Plex Sans Arabic via next/font; both directions share every token above.">
        <div className="grid gap-md sm:grid-cols-2">
          <div dir="ltr" className="rounded-md border border-border p-md">
            <p className="text-sm text-muted">English (LTR)</p>
            <p className="mt-xxs text-base text-ink">Noor retrieves and cites only approved guideline text.</p>
          </div>
          <div dir="rtl" lang="ar" className="rounded-md border border-border p-md font-arabic">
            <p className="text-sm text-muted">العربية (RTL)</p>
            <p className="mt-xxs text-base text-ink">نور يسترجع ويستشهد فقط بالنص المعتمد من الإرشادات السريرية.</p>
          </div>
        </div>
      </Section>
    </main>
  );
}
