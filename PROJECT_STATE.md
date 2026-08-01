# PROJECT_STATE.md

**Last updated:** Sprint 1-D3 — Deterministic Page-Aware Chunking session
(Claude Code, this environment)
**Updated by:** Noor Delivery Council (Claude Code)

---

## -12. This session: Sprint 1-D3 — Deterministic Page-Aware Chunking

Implemented workstream `S1-D3`: turns canonical, accepted per-page text
(`get_document_page_text_readiness()`, migration 0011) into
deterministic, page-aware chunks with exact provenance, immutable chunk
records, a private canonical JSON artifact, human technical chunk
review, and a derived `eligible_for_embedding` boolean — no embeddings,
no vector storage, no retrieval, no LLM calls anywhere in this sprint
(ADR 0014). UX-1.1 was accepted before this sprint began: the mission
brief for this sprint itself records "UX-1.1 — Public Surface Redesign,
Complete and Visually Accepted," which is treated as the user's
acceptance signal (delivered by proceeding to the next mission with that
status stated). `docs/verification/ux-1-1-visual-acceptance.md`'s final
status line was updated accordingly.

**Repository audit before writing any code, per the mission's own
instruction not to trust prior-report claims blindly:** confirmed via
`ls docs/architecture/adr/` that ADR number `0013` (the mission's own
suggested number) was already used by UX-1
(`0013-noor-brand-and-design-system-alignment.md`) — used **0014**
instead, documented in the ADR's own opening line. Confirmed via `ls
supabase/migrations/` that 0011 was the latest migration, so 0012/0013
were free (matching the mission's own suggested numbers exactly there).

**Schema (migrations 0012 + 0013, ADR 0014):** `document_chunking_runs`/
`document_chunks`/`document_chunk_source_spans` (execution — identity-
based idempotent reuse, a hard `page_end = page_start` database
constraint enforcing the V1 hard-page-boundary policy, full immutability
triggers, the mandatory 100%-coverage/0%-duplication gate enforced at
finalization); `document_chunking_reviews`/`document_chunk_reviews`/
`document_chunk_findings`/`document_chunking_review_events` (chunk
technical review — the same execution/review architectural boundary as
ADR 0011/0012, one layer deeper); `get_document_embedding_readiness()`
as the canonical, live-recomputed (never stored) truth table. Seven new
`guideline_chunking.*` permissions — deliberately no `.cancel` (reuses
the existing generic `guideline_processing_jobs.cancel` instead, a
documented scope decision).

**A real, structural bug found and fixed through careful review before
any test was even run:** `get_document_extraction_review_eligibility()`
and `get_document_page_text_readiness()` (migrations 0009/0011) both
call `assert_permission()`, which checks `auth.uid()` — always `NULL`
for the Worker's `service_role` RPC calls (no `sub` claim in that JWT),
so calling either from a Worker-only function would unconditionally
raise "permission denied." The original draft of
`create_document_chunking_run` did exactly this. Fixed by adding a new
Worker-only function, `get_document_chunking_job_context`, that
re-derives the identical readiness logic directly against the tables
(extended to also return each page's actual text), authenticating via
lease ownership like every other Worker-only function in this codebase
— documented in-line and in
`docs/database/deterministic-chunking-schema.md` as a permanent lesson.

**A second real bug, caught only by actually running the local RLS
suite, not by re-reading the SQL:** migration 0013's `CREATE OR REPLACE`
of `reopen_extraction_review` was drafted from migration 0009's
*original* function body — but migration 0011 had already overridden
that same function to add an OCR-request invalidation cascade. Building
0013's version from the older base would have silently reverted 0011's
cascade. Caught by TEST 21 of `011_controlled_ocr.sql` failing on a
full, fresh-container run of the *entire* 001–013 suite (not just the
new 012 file in isolation) — fixed by rebuilding 0013's version as a
true superset of 0011's, verified by re-running the full suite green
afterward. This is exactly the kind of regression that only a full
cumulative-suite run against a genuinely fresh database can catch,
consistent with this codebase's established verification discipline.

**A third real bug, a Postgres API mistake:** both new migrations used
`information_schema.roles` (which does not behave as a simple
`rolname`-keyed lookup on plain Postgres) for the guarded-grant pattern
instead of the established, correct `pg_roles` — caught immediately by
the first migration-apply attempt against a fresh container, fixed with
a global find/replace across both files.

**A fourth, quieter design bug found while writing the Python client
wrapper, before ever touching a database:** `create_document_chunking_run`'s
`p_ocr_request_id`/`p_ocr_review_id` parameters had no SQL default, but
`OrchestrationClient._rpc()` strips `None` values from every RPC payload
(the established pattern every other optional-Worker-parameter relies
on) — for a native-only chunking run (no OCR involved), PostgREST would
have been unable to resolve the function call at all. Fixed by moving
both parameters to the end of the signature with `default null`
(Postgres requires defaulted parameters last).

**Worker implementation** (`apps/worker/app/chunking/*`):
`noor-simple-tokenizer` v1 — a deterministic, dependency-free technical
size proxy (regex word/punctuation counting over NFC-normalized text),
chosen over tiktoken specifically to avoid Arabic-fragmentation bias and
the risk of its count being mistaken for a real embedding model's token
count (ADR 0014's comparison table). Deterministic, non-semantic block
segmentation (blank-line/list/heading-candidate/table-like heuristics,
always tiling a page's full text with zero gaps); a strict
sentence→line→punctuation→tokenizer-window oversized-block fallback
cascade, guaranteed to terminate. Two more real bugs were found and
fixed by the Worker's own unit tests, not assumed correct from code
review alone: an inter-block boundary-tiling bug (each side of a
boundary was computed independently instead of in one forward pass,
producing overlapping spans across absorbed blank-line gaps) and a
chunk-grouping bug (oversized-block fallback fragments were forced into
their own standalone chunk regardless of size, which would have
shattered a single large paragraph with no natural breaks into hundreds
of below-minimum-token chunks instead of being sensibly re-packed toward
the target size).

**Web application layer** (`apps/web/lib/chunking/{queries,schemas,
errors,actions,ui}.ts(x)`, mirroring `apps/web/lib/ocr/*` one layer
deeper): a chunking review queue (`/reviewer/chunking`), a chunk-by-chunk
review workspace (`/reviewer/chunking/[chunkingReviewId]` — chunk text,
provenance/boundary metadata, findings, and the submit-decision form),
and a "Chunking:" status row wired into the guideline detail page's
extraction summary card (start chunking → open chunking review), all on
the accepted NOOR light design system with no new hardcoded colors.

**Verification, real not assumed:** local — the full 001–012 (0013's
tests live in the same `012_deterministic_chunking.sql` file, matching
the precedent that not every migration needs its own dedicated test
file) RLS suite run against a genuinely fresh `postgres:16` container,
**202/202 assertions passed**, including 17 new chunking-specific
assertions (job creation/idempotency/eligibility gating, the Worker
context read, the coverage gate rejecting a bad payload, chunk/span
immutability, the hard-page-boundary constraint, identity-based reuse
from a genuinely fresh job attempt, the Worker-only trust boundary, RLS,
the full chunk review lifecycle including `rechunk_required`'s
evidence requirement, and the extraction-review-reopen cascade). Worker
— a new 35-assertion pytest suite (tokenizer determinism, Arabic/Latin
tokenizer parity, block-tiling invariants on English/Arabic/table-like
content, the full oversized-block fallback cascade, full-document
coverage/duplication/determinism/provenance proofs) on top of the
pre-existing 79-assertion suite (114 total, zero regressions). Web —
`tsc --noEmit` clean across the whole app, `next lint` clean, a clean
production build (0 warnings, both new `/reviewer/chunking` routes in
the route table), and all 17 test files (including the two new
chunking-schemas/chunking-errors files, 34 new assertions) independently
confirmed passing. `packages/ui`/`packages/clinical-schemas` unaffected
and clean. Hosted Development verification: 30/30 real end-to-end
checks against the actual unmodified Worker code (real GoTrue JWTs, a
real extraction, a real chunking run with 100% coverage/0% duplication,
a real chunk review lifecycle, real `get_document_embedding_readiness`
truth-table confirmation), all synthetic data cleaned up and confirmed
zero-residual. Full record:
`docs/verification/sprint-1-d3-chunking-verification.md`.

---

## -11. Prior session: UX-1.1 — Visual Acceptance and Public Surface Redesign

A corrective workstream: UX-1's brand tokens and shared components were
real and working, but the actual rendered public/auth pages still
failed visual acceptance when checked against real screenshots — the
root landing page still showed the Sprint 0.5 placeholder, and the
login page rendered with a full dark background despite UX-1's light
theme having been implemented.

**Root cause found by reading the code, not guessed:**
`apps/web/app/layout.tsx`'s `<html>` element carried no `data-theme`
attribute, so `packages/ui/tokens/index.ts`'s
`@media (prefers-color-scheme: dark)` CSS rule silently applied the
dark palette (dark navy canvas, lighter/lower-contrast button colors)
to every page for any visitor whose OS prefers dark mode — which is
common. There is no user-facing theme toggle anywhere in the product;
this was an unintended side effect of pre-existing (ADR 0005) dark-mode
token infrastructure, not a deliberate feature. Fixed by pinning
`data-theme="light"` on `<html>`, consistent with the mission's own
rule that dark mode is out of scope unless it already exists as a
fully functional user-selectable mode.

**The lower-left black "N" artifact was investigated, not assumed:**
confirmed to be Next.js's own built-in development-mode indicator (no
`devIndicators` config existed; no matching third-party dependency; not
an application component) — it never renders in production or a
deployed Vercel Preview. Disabled locally via the documented
`devIndicators: false` flag.

**Rebuilt:** the root landing page (real header/hero/capability-cards/
workflow/trust/footer, accurate current-capability copy, protected
workspace routes no longer exposed as raw public links); the login page
(two-column `AuthSplitShell` — white brand panel with a fully legible
logo, soft-cyan form panel); `/forgot-password`/`/update-password`
(moved onto a shared `AuthCardShell`); `/403`/`/access-denied` (same
shell, gained a real recovery action); `/not-found.tsx`/`/error.tsx`
(created — neither existed before, Next.js was serving unstyled
defaults). A real RTL bug was found and fixed in the same pass: the new
footer's `sm:text-left` did not flip under `dir="rtl"` — corrected to
the logical `sm:text-start`.

**Verification, real not assumed:** `apps/web` — `tsc --noEmit` clean,
`next lint` clean, `next build` clean (0 warnings, 23 routes), all 15
unit-test files pass individually including a new
`public-pages-content.test.ts` (bans the retired Sprint 0.5 phrases,
enforces exactly one `<h1>` on `/` and `/login`, guards the
`data-theme="light"` fix against regression). `packages/ui` typecheck
clean. `packages/clinical-schemas` typecheck + 6/6 tests pass.
`apps/worker`'s full 79-assertion pytest suite unchanged — confirms
zero backend regression from a frontend-only corrective mission.
**22 real Playwright/Chromium screenshots** were captured against the
actual running `next dev` server — desktop/tablet/mobile for `/` and
`/login`, desktop+mobile for `/forgot-password`/`/403`/`/access-denied`,
plus 3 RTL-simulated captures (forcing `dir="rtl"` on the live DOM,
since Noor has no routed Arabic locale yet) — proving the two-column
login layout mirrors correctly, the logo is never mirrored, and the RTL
footer bug above is fixed. Full record, including the screenshot table:
`docs/verification/ux-1-1-visual-acceptance.md`.

**UX-1.1: Implementation Complete, Pending User Visual Acceptance.**
This status is deliberate — the mission's own governing rule is that
visual acceptance is the user's call, not a self-declared outcome of a
passing build.

---

## -10. Prior session: UX-1 — NOOR Brand and Design System Alignment

Implemented workstream `UX-1`: the user's approved NOOR logo (a
stylized "N" — navy/blue network graphic on the left stroke, teal/
emerald medical cross on the right, "NOOR / CLINICAL INTELLIGENCE"
wordmark) became the single source of truth for Noor's visual identity.
Before this sprint, `apps/web/public/` was completely empty — no
favicon, logo, or app icons existed anywhere.

**The existing design-system architecture needed no rewrite.**
`packages/ui/tokens/*` already separated raw brand colors from semantic
component slots consumed by every shared component via Tailwind
utilities backed by CSS custom properties (ADR 0005). Re-branding the
whole application was almost entirely a token-*value* change: verified
by grep that zero feature pages hardcode a hex color or a Tailwind
default-palette utility anywhere in `apps/web/app`/`apps/web/lib`.

**Logo handling:** the supplied `logo.jpeg` was archived byte-for-byte
(`apps/web/public/brand/source/noor-logo-original.jpeg`, sha256
`183cb203...`) before any processing. Every derived asset (primary
lockup, navigation lockup, symbol, favicon, social preview) was
produced by cropping this file's own pixels at boundaries measured by a
row/column content scan, not eyeballed — never redrawn.

**Color anchors:** independently pixel-sampled from the real artwork
(dominant-color binning), then validated against — and found to closely
match — the mission's own supplied reference anchors (Deep Navy
`#032855`, Clinical Blue `#045092`, Primary Teal `#078A88`, Emerald
`#09B993`), which were adopted as final rather than the raw samples
(which carried JPEG chroma-subsampling artifacts). Four full 50–950
brand scales were generated by linear-RGB blending toward white/near-
black — an HSL-lightness approach was tried first and rejected for
producing implausible "neon" mid-tones on these highly saturated teal/
emerald hues.

**A real, concrete gap was found and fixed, not just described:**
`ocr_required` and `reprocessing_required` extraction/OCR review
statuses were visually identical before this sprint (same `underReview`
color and icon, differing only in label text). Five new semantic status
states were added (`queued`/`retryScheduled`/`ocrRequired`/
`reprocessingRequired`/`deadLettered`), each with a distinct icon,
closing this and four analogous gaps in the processing-job status
mapping. Clinical safety semantics (danger/warning/critical)
deliberately kept their pre-existing red/amber — the brand refresh
never touches a safety-relevant hue.

**Application shell:** the mission's brief described a sidebar-based
shell redesign. The actual app has no sidebar — a single shared
horizontal top nav (`apps/web/app/WorkspaceHeader.tsx`) is rendered by
all five workspace layouts. The logo and a new teal `accent` (split out
from `primary`, which stays blue) were added there instead of inventing
sidebar architecture that doesn't exist — real architectural scope
discipline, not a shortcut.

**A real accessibility regression was caught and fixed in the same
edit that introduced it:** removing the login page's old `PageHeader`
(to make room for the logo) would have deleted the page's only `<h1>` —
caught by review, an explicit heading was added back before it shipped.

**Verification, real not assumed:** `apps/web` — `tsc --noEmit` clean,
`next lint` clean ("No ESLint warnings or errors"), `next build`
clean (0 warnings after fixing a real `metadataBase` build warning; all
22 routes present including both OCR review routes), all 14 unit-test
files pass individually. `packages/ui` — `tsc --noEmit` clean.
`packages/clinical-schemas` — typecheck + all 6 tests pass.
`apps/worker` — the full 79-assertion pytest suite still passes
unchanged, confirming a frontend-only sprint introduced zero backend
regression.

**A real environmental issue was hit and surfaced, not hidden:**
mid-session this machine's `C:` drive was found at 99% capacity (0
bytes free at one measurement), making Docker unresponsive. This was
reported to the user immediately, who freed some space; work resumed
once confirmed. Full account, including what still could not be
verified as a result (a real Vercel Preview deployment/browser check):
`docs/verification/ux-1-brand-alignment-verification.md`.

**UX-1 (NOOR Brand and Design System Alignment): locally complete and
verified; Vercel Preview deployment remains outstanding.**

---

## -9. Prior session: Sprint 1-D2 — Controlled Page-Scoped OCR

Implemented workstream `S1-D2`: permission-scoped Storage hardening
(migration `0010_permission_scoped_storage_access.sql`, closing the
residual risk S1-D1 documented — `storage.objects` RLS for the two
guideline-content buckets now requires an explicit permission, not mere
organization membership) and a controlled, page-scoped OCR pipeline
(migration `0011_controlled_page_scoped_ocr.sql`, ADR 0012): OCR
eligibility derived exclusively from explicit `ocr_candidate` review
evidence, one durable processing job per eligible page, self-hosted
Tesseract via `pypdfium2` rendering, a fully pinned OCR identity with
idempotent reuse, OCR technical review structurally separate from
execution status, and `get_document_page_text_readiness()` as the single
canonical-representation derivation point for a future chunking
pipeline.

**This session began by auditing in-progress, uncommitted work from an
earlier session, not by trusting it.** A prior Claude Code session had
already written most of migrations 0010/0011 and the
`apps/worker/app/ocr/*` module but left it uncommitted, undocumented, and
— the audit found — **not actually functional**: `app/ocr/processor.py`
called a function (`run_ocr_pipeline`) that does not exist in
`pipeline.py`, an `ImportError` at module load time found by actually
trying to import the module inside a built Docker image. Four more real
bugs were found and fixed while making the module real
(`docs/verification/sprint-1-d2-controlled-ocr-verification.md` has the
full account): the OCR-run identity was being recorded with a
permanently empty image checksum (Worker called `create_ocr_run` before
rendering); `create_document_ocr_run`'s reused branch never marked its
request page terminal, which would have permanently blocked
`create_document_ocr_review` for any reused identity; missing
`pytesseract`/`pypdfium2` in `requirements.txt` and a missing
`tesseract-ocr` apt install / tessdata fetch in the Dockerfile; and a
Windows-specific path-portability bug in Tesseract's config-string
parsing (fixed via `TESSDATA_PREFIX`, confirmed identical behavior on
Linux afterward). Two schema-level gaps against the mission's own
invalidation rules and established self-review policy were also found by
reading migration 0011 against the mission text directly: reopening the
extraction review never cascaded into an already-created OCR request,
and `start_document_ocr_review` had no self-review block (unlike its
extraction-review analogue). Both fixed inside migration 0011 (still
uncommitted, so edited directly rather than requiring a new migration
file).

**Verification, real not assumed:** local — the full 001–011 RLS suite
(25 new OCR assertions) run against **three genuinely fresh
`postgres:16` containers**, 100% green; a real ordering bug in the new
test file itself (leftover throwaway jobs from a uniqueness test being
claimed ahead of the jobs a later test depended on) was found by the
first fresh-container run and fixed. Worker — 79/79 pytest assertions,
including a new `test_ocr_processor.py` (Worker orchestration against a
fake client, with `render_source_page`/`recognize_and_build_artifact`
monkeypatched) and a new `test_ocr_renderer_and_provider.py` (**real,
non-mocked** `pypdfium2` rendering and **real Tesseract recognition**
against the synthetic English/Arabic/mixed-language fixtures — real
mixed Arabic/English recognition confirmed, not assumed). A real
Docker-image build-and-run smoke test confirmed the exact pinned
`tesseract-ocr` apt version (`5.5.0-1+b1`) matches `app/ocr/config.py`'s
constant on the actual base image (checked via `apt-cache policy`, not
assumed), and confirmed real render+OCR end-to-end inside the built
image. The web application UI was then built:
`apps/web/lib/ocr/{config,queries,schemas,errors,actions,ui}.ts(x)` (the
application layer, mirroring `apps/web/lib/extraction-review/*` one
layer deeper — pinned OCR identity constants, explicit-column queries,
Zod validation, safe error mapping, a Server Action per RPC including a
dedicated signed-source-access action gated by the new
`guideline_ocr.read_source` permission), an OCR review queue
(`/reviewer/ocr`), a side-by-side review workspace
(`/reviewer/ocr/[ocrReviewId]` — original page, native extraction, and
OCR result shown together), and an OCR section on the guideline detail
page's extraction summary card. A real TypeScript bug (accessing a
column directly on a non-literal `.select()` result, which Supabase's
generated types cannot infer) was found by `tsc --noEmit` and fixed by
following the existing `(row as unknown as RowType).field` cast
convention already established in `extraction-review/queries.ts`.
`npm run typecheck`/`lint`/`build` all ran clean (the two new routes
compile and appear in the production route table), and all 14
`apps/web` test files (136 assertions total, 33 new — `ocr-schemas.test.ts`/
`ocr-errors.test.ts`) pass, including `permissions.test.ts` confirming
the 9 new `GUIDELINE_OCR_*` permission constants match migration 0011's
real grants.

**Hosted Development verification was completed in a later continuation
of this same session**, once a Supabase Personal Access Token for the
"Noor Development" project was provided: migrations 0010/0011 applied
cleanly; a full real end-to-end run (real GoTrue JWTs, real upload, the
actual unmodified Worker code for both extraction and OCR, real
Tesseract/pypdfium2 execution, real downstream chunking-eligibility
flip) succeeded; permission-scoped Storage RLS was proven against real
JWTs (clinician denied, permitted roles allowed); all synthetic hosted
data was deleted and verified back to zero. A real, hosted-only permission-model fact was surfaced only by actually
running the flow (not a defect): `assign_ocr_reviewer` requires the
caller, not just the assignee, to hold `guideline_ocr.review` —
`organization_admin` deliberately does not hold it, so a reviewer must
self-assign, which is not a self-review violation since that block is
keyed on the source document's uploader, not the assigner. Full record:
`docs/verification/sprint-1-d2-controlled-ocr-verification.md`.
The Vercel Preview redeploy is tracked separately below.

**Sprint 1-D2 (Controlled Page-Scoped OCR): complete and verified,
locally, on hosted Development, and on a real Vercel Preview deployment
(build `Ready`, CI green on `main`). The one open item is a real
browser-rendered check of the Preview URL, blocked by this Vercel
team's own SSO Deployment Protection.**

---

## -8. Prior session: Sprint 1-D1 — Extraction Review and Technical Quality Gate

Implemented workstream `S1-D1`: a technical quality gate over Sprint
1.2B's deterministic extraction, structurally separate from execution
status (ADR 0011). Migration `0009_extraction_review_quality_gate.sql`
adds review rounds, a controlled 23-value/4-severity finding taxonomy,
explicit per-page review coverage, a single transactional
`submit_document_extraction_review()` function enforcing all five
terminal decision rules under lock, server-derived downstream eligibility
(`eligible_for_ocr`/`eligible_for_chunking`/`eligible_for_retrieval`),
database-level self-review blocking, and a new, deliberately separate
permission namespace (`guideline_extraction_reviews.*`/
`guideline_extraction_findings.*`/`guideline_extraction_source.*`).

**Repository audit before writing any code** (full table in ADR 0011):
`guideline_reviews`' submission-function skeleton and self-review trigger
were reused; its unlimited-accumulation review model was **not** — this
sprint needed reviewer assignment and one active round per run instead.
`document_extraction_runs`/`document_extraction_pages` (migration 0008)
remain untouched and exactly as immutable as before; every new table only
ever reads them. No existing signed-download pattern existed anywhere in
the codebase (only signed-*upload* did) — built fresh, following the
established "session-bound client, RLS is the real gate, no service-role
key" principle.

**Applying Sprint 1.2B's real CI-only lesson from the start, not
rediscovering it:** the prior sprint found — via an actual CI failure on
a genuinely fresh Postgres container, not by reading the SQL — that a
migration's own guarded `grant ... to authenticated` block is a
documented no-op at CI's migration-apply time, and that the RLS test file
itself must issue its own explicit grant. `009_extraction_review.sql`'s
grants were written at the very top of the file from the start, and the
full suite was verified against **multiple genuinely fresh
`postgres:16` containers** (not the same reused container across
iterations) before being trusted — no repeat of that bug this sprint.

**Verification, real not assumed:** local — the full cumulative RLS suite
(001–009) was run against several fresh Docker containers, 100% green,
including a new 39-assertion review lifecycle/eligibility/RLS suite
(`supabase/tests/rls/009_extraction_review.sql`) covering every legal and
illegal review-state transition, all 5 terminal decision rules (each with
both a rejection case and a success case), self-review blocking, reopen/
invalidate semantics, findings CRUD/immutability, append-only events, and
RLS/trust-boundary denial (clinician, cross-tenant); Web —
lint/typecheck/build all clean, including the new review-queue and
side-by-side review workspace routes, plus 27 new unit assertions
(`extraction-review-schemas.test.ts`, `extraction-review-errors.test.ts`,
and an extended `permissions.test.ts` check); Worker/`clinical-schemas`/
`ui` re-verified unaffected.

**Hosted Development — verified.** Migration 0009 applied
(`local==remote` confirmed). The full 007+008+009 SQL suite (63
assertions) ran clean against real hosted Postgres 17, run as three
separate requests after finding a real test-execution quirk (concatenating
multiple files into one batched submission collides on temp-table names —
fixed by submitting each file as its own session). A real end-to-end flow
built on the **actual unmodified Worker code**: a real GoTrue user
uploaded a real PDF, the real Worker claimed and extracted it
(`succeeded`, 1 page), and three more real GoTrue users (clinical_reviewer,
quality_manager, clinician) exercised the full review lifecycle through
real PostgREST RPC calls — create, assign, start, mark-page-reviewed,
submit `accepted`, real-RPC eligibility (chunking eligible/OCR
ineligible), reopen by quality_manager, and eligibility correctly
reverting to ineligible afterward. The signed-source-PDF-access mechanism
was verified directly against real Storage (sign + download, `200`,
`application/pdf`). A real bug was found and fixed while cleaning up:
`prevent_extraction_finding_delete()` had no maintenance-override escape
hatch (inconsistent with every other append-only table in this codebase),
making synthetic findings permanently undeletable — hotfixed on hosted,
corrected in the migration, re-verified locally. All synthetic hosted
data (4 real GoTrue users, seed.sql's 5 placeholders, all DB rows, both
Storage objects) was cleaned up and confirmed zero-residual. Vercel
Preview redeployed, `Ready`, the new review-queue and side-by-side
review workspace routes present in the build, Deployment Protection
intact. Full record:
`docs/verification/sprint-1-d1-extraction-review-verification.md`.

**Sprint 1-D1 (Extraction Review and Technical Quality Gate): Complete
and Hosted-Verified.**

---

## -7. Prior session: Sprint 1.2B — Deterministic PDF Page and Text Extraction

Implemented workstream `S1-C2`: the Worker's controlled no-op processor
(Sprint 1.2A) is replaced with a real, deterministic PDF extraction
pipeline — source integrity revalidated twice independently, page-level
text extraction and normalization, page/artifact checksums, technical
quality metrics, conservative suspected-scanned detection, a canonical
JSON artifact uploaded privately and independently re-verified, and
atomic finalization with idempotent identity-based reuse. Migration
`0008_deterministic_pdf_extraction.sql`.

**Mandatory first review completed**: re-verified the Sprint 1.2A
hosted-only security fix (schema `CREATE` privileges, narrow
`search_path`, `authenticated`/`anon` EXECUTE grants) and turned it into
a **permanent regression suite**
(`supabase/tests/rls/007_security_hardening_review.sql`) rather than
leaving it as a one-off verification script — the exact class of bug
found in Sprint 1.2A can now never silently regress unnoticed.

**Extractor decision (ADR 0010):** `pypdf` (BSD-3-Clause), selected over
the mission's own suggested default, `PyMuPDF` — which moved to AGPL-3.0
licensing at v1.24.1, a real, unresolved legal exposure for a commercial
clinical SaaS platform (the AGPL network-use clause). This is exactly the
kind of blind-default risk the mission's own instruction ("do not select
it blindly") anticipated; the ADR documents the full comparison against
`pdfminer.six`/`pdfplumber` too.

**Two real concurrency bugs found and fixed by actually racing two
independent processes at the same extraction identity, not by reading the
SQL:**

1. `finalize_document_extraction_run()` raised a raw `unique_violation`
   when two genuinely simultaneous extraction attempts at the same
   identity both tried to mark themselves `succeeded` — the row-level
   lock inside `create_document_extraction_run()` only locks an
   *existing* row, so two callers can legitimately both create fresh
   `running` rows the first time they race in. Fixed with an exception
   handler that gracefully adopts the winning run instead of surfacing a
   raw constraint-violation error to the Worker.
2. A second, related race surfaced immediately after fixing the first:
   the claim → create → insert-pages → finalize sequence is several
   separate auto-committed statements, not one spanning transaction — a
   job's own `document_extraction_runs` row can be superseded by a
   *different* job's attempt at the same identity after the first job
   already committed its `create` call but before it reached `finalize`.
   That raised a raw "not running" error too. Fixed by explicitly
   detecting the supersession case: adopt an already-succeeded winner if
   one exists, otherwise raise a clear, named, retryable error — exactly
   what a real Worker's error-classification layer expects, never a raw,
   unclassified exception. Both fixes re-verified together: 5 consecutive
   runs of the new dual-OS-process concurrency script
   (`supabase/tests/concurrency/verify_concurrent_extraction_identity.sh`),
   all 4 possible race outcomes observed naturally, zero unexpected
   errors across all five. See
   `docs/database/deterministic-pdf-extraction-schema.md`.

**Verification, real not assumed:** local — a fresh `postgres:16` Docker
container had all 8 migrations + seed + the full RLS suite (001–008) run
against it, 100% green (117/117 cumulative assertions), including the
pre-existing 001–007 suites unmodified on top of migration 0008's schema;
two genuine dual-OS-process concurrency proofs (the unchanged Sprint 1.2A
claim-race script, and the new extraction-identity-race script); Worker —
91/91 pytest assertions (59 pre-existing + 32 new covering fixture
behavior against 11 synthetic PDFs, determinism, source-integrity
revalidation, and end-to-end processor orchestration),
`python -m compileall` clean; Web — lint/typecheck/build/test all clean,
the new extraction UI route compiles in the production build.

**Hosted Development — verified.** Migration 0008 applied (`local==remote`
confirmed). The corrected 007+008 SQL suite (24 assertions) ran clean
against real hosted Postgres 17. A real end-to-end flow exercised the
**unmodified production Worker code** against real infrastructure: a real
GoTrue user/JWT, a real RLS-authorized Storage upload, the real
`WorkerLoop`/extraction pipeline claiming and processing a real job with
`service_role` credentials — 5/5 pages extracted from a real multi-page
PDF, artifact uploaded to private Storage and independently re-downloaded
and re-hashed (checksum match confirmed), idempotent reprocessing proven
(a second real job at the same identity reused the same extraction run,
no duplicate), the `authenticated` trust boundary denied for both an
org_admin JWT and a clinician JWT, RLS confirmed permissive for org_admin
and zero-row for clinician, and a genuine `source_object_missing` failure
correctly classified (not crashed) when the Worker drained an unrelated
fixture job with no real Storage object. One real, non-product finding
along the way: the Supabase Management API's SQL query endpoint batches
an entire multi-statement submission differently than `psql -f`'s
per-statement autocommit, which made an unrelated `begin/rollback` test
pattern (008's original TEST 15/15b) unsafe under that execution model —
fixed in the committed test file itself (switched to the same bare-`DO`-
block role-switch pattern already proven safe by TEST 16), re-verified
locally with no regression. All synthetic hosted data (2 real GoTrue
users, seed.sql's 5 placeholder users, all DB rows, both Storage objects)
was cleaned up and confirmed zero-residual. Vercel Preview redeployed,
`Ready`, the new extraction page-detail route present in the build,
Deployment Protection intact. Full record:
`docs/verification/sprint-1.2b-pdf-extraction-verification.md`.

**A third real bug, found by CI itself, not locally:** the first push
failed the `database` job — CI always starts a genuinely fresh Postgres
container per run, and `008_pdf_extraction.sql` was missing its own
explicit `grant select on document_extraction_runs,
document_extraction_pages to authenticated` (the `authenticated` role
doesn't exist until the RLS suite's first file creates it, so migration
0008's own guarded grant is a no-op there — exactly the same constraint
migrations 0005/0006 already solved in their own test files, which 008
never copied). A reused local Docker container had been silently masking
this the whole time. Fixed, re-verified against multiple genuinely fresh
`postgres:16` containers, re-pushed — CI confirmed green
(`4514f20`, run `30249901666`).

**Sprint 1.2B (Deterministic PDF Page and Text Extraction): Complete and
Hosted-Verified.**

---

## -6. Prior session: Sprint 1.2A — Durable Processing Orchestration

Implemented workstream `S1-C1`: a reliable execution control plane for
the `document_processing_jobs` rows Sprint 1.1 creates `queued` —
atomic Worker claim, hashed-lease ownership with heartbeat renewal,
exponential-backoff retry, max-attempt dead-lettering, lease-expiry crash
recovery, and queued/retry-scheduled cancellation — proven end-to-end
with a **controlled no-op processor**, deliberately not real PDF
extraction (that's Sprint 1.2B, `S1-C2`). Migration
`0007_durable_processing_orchestration.sql`.

**Mandatory review completed first:** Sprint 1.1's
`completeGuidelineUploadAction` fully buffered the uploaded file into
memory (`.download().arrayBuffer()`) before computing size/PDF-signature/
SHA-256. Refactored to genuine incremental streaming
(`apps/web/lib/documents/streamVerification.ts`) — same trust model, same
50 MB limit, provably early-aborts on an oversized stream.

**Architecture (ADR 0009):** the database remains the durable
orchestration source of truth; a queue message, if one is ever
introduced, would only be a wake-up mechanism, never authoritative. Mode
A (Worker polling loop) was chosen over introducing Supabase Queues this
sprint — correctness doesn't depend on it, proven under real dual-process
concurrency. A hashed lease token (never the plaintext) is the ownership
mechanism; the six new orchestration functions are structurally
uncallable by `authenticated` (see below for why that claim required a
real fix, not just a design intention).

**Two real, hosted-only bugs found and fixed** — neither reproducible
against local plain Postgres, both found only by actually running
verification against real hosted Supabase infrastructure:

1. `gen_random_bytes()`/`digest()` (pgcrypto) resolved fine locally
   (installed directly into `public` by a fresh `postgres:16` container)
   but not on hosted, where Supabase pre-installs pgcrypto in an
   `extensions` schema — the first real hosted claim call failed with
   `function gen_random_bytes(integer) does not exist`. Fixed by adding
   `extensions` to the two affected functions' `search_path` (safe on
   both environments: a nonexistent schema in `search_path` is silently
   skipped).
2. **The migration's core trust-boundary claim — "these six functions are
   never granted to `authenticated`" — was false on hosted** until this
   was found. `revoke all on function ... from public` does not undo
   Supabase's project-level `ALTER DEFAULT PRIVILEGES ... GRANT EXECUTE
   ON FUNCTIONS TO anon, authenticated, service_role`, which grants
   EXECUTE directly to those named roles at function creation time. A
   real authenticated-JWT call to `claim_next_document_processing_job`
   returned `200` before the fix — an ordinary signed-in
   `organization_admin` could genuinely claim and manipulate processing
   jobs. Fixed with an explicit, guarded `revoke execute ... from
   authenticated` / `from anon` on every function in this migration;
   re-verified the grant is now limited to `postgres`/`service_role` only,
   and the same call now correctly returns `403`/`404`. See ADR 0009's
   addendum and the verification record for the full account — this is
   now a documented lesson for every future Worker-only function.

**Verification, real not assumed:** local — web lint/typecheck/build
clean, all test assertions passing (9 suites, 2 new this sprint); a real
`postgres:16` Docker container had migrations 0001-0007 + seed + the full
RLS/orchestration suite (7+4+26+4+17+**27** = 85 assertions) run against
it, 100% passed; a genuine dual-OS-process concurrency proof (80 real
jobs, two independent `psql` connections racing) — zero double-claims,
zero lost jobs; Worker — 27/27 pytest assertions, `compileall` clean.
Hosted — migration applied and confirmed (`local==remote`), **30/30 real
assertions** including the security trust-boundary proof, a full
claim/lease/heartbeat/retry/dead-letter/recovery/cancel lifecycle, RLS
read-restriction, and a 20-parallel-request real HTTP concurrency race
(zero duplicate claims) — all with real GoTrue JWTs and real
`service_role` credential usage, synthetic data cleaned up and confirmed
zero-residue. Vercel Preview redeployed, healthy, Deployment Protection
unchanged and correctly enforced. Full record:
`docs/verification/sprint-1.2a-processing-orchestration-verification.md`.

**Sprint 1.2A (Durable Processing Orchestration): Complete and
Hosted-Verified.**

---

## -5. Prior session: Sprint 1.1 — Secure Guideline Source Document Intake

Implemented workstream `S1-B`: a trusted, tenant-safe, auditable path from
an approved guideline version to a verified private source document and a
durable, idempotently-created processing job (`queued` only — no claim or
execution). Migration `0006_secure_guideline_document_intake.sql`.

**Two mandatory corrections completed first, per the mission:**

1. **G-12 closed** — the one gap the prior Sprint 1 report left open
   (self-approval by a creator who *also* holds `guidelines.approve` was
   blocked by code but never exercised by a live test, since no seeded
   role combined both). A dedicated regression test
   (`supabase/tests/rls/004_g12_self_approval_regression.sql`) creates a
   synthetic role holding `guidelines.create` + `guidelines.approve` on
   one user, has that user author and submit a version, gets a genuine
   recommending review from a different user, then attempts self-approval
   — denied, with confirmed-unchanged lifecycle status, no approval
   lifecycle event, and no falsely-claiming audit event. Passed against
   plain Postgres 16 **and** hosted Development with a real GoTrue JWT
   (the synthetic role was cleaned up on hosted afterward).
2. **Backlog reconciled** — the prior report undercounted what the S1-A
   vertical slice actually delivered (application layer, UI, hosted
   verification, not just schema). `MASTER_BACKLOG.md` restructured from
   the original flat `S1-NN` guess into coherent workstreams: `S1-A`
   (Guideline Registry, done), `S1-B` (this sprint's Secure Document
   Intake, now also done), `S1-C`/`S1-D`/`S1-E` (future — processing,
   extraction, retrieval).

**Architecture (ADR 0008):** three state machines kept deliberately
separate — clinical publication (unchanged), upload session (`created →
authorized → completed/expired/rejected/cancelled`), and processing job
(`queued` only this sprint). A second, load-bearing decision: unlike
Sprint 1's guideline registry, this migration cannot keep 100% of its
logic in SQL — Postgres cannot read Storage object bytes. File facts
(size, PDF signature, SHA-256) are computed by the Next.js server, which
independently re-downloads the uploaded object using the same RLS-scoped
session that uploaded it (no service-role key anywhere in this flow), and
passes those computed facts as *inputs* to `complete_guideline_upload()` —
the browser is trusted for nothing beyond "which file did the user pick."

**A real, two-part bug found by actually running the migration**, not by
reading the SQL: both `create_guideline_upload_session()` and
`complete_guideline_upload()` use `RETURNS TABLE`, which creates an
implicit PL/pgSQL variable per output column; two of those names (`status`,
`source_document_id`) collided with real table columns queried later in
the same function body, producing `column reference "..." is ambiguous"`
only when actually executed against Postgres 16 — not at migration-apply
time. Fixed by table-qualifying both references. See
`docs/database/secure-document-intake-schema.md`.

**Verification, real not assumed:** local — web lint/typecheck/build
clean, 63/63 `npm run test --workspace=apps/web` assertions (3 new
suites); a real `postgres:16` Docker container had migrations 0001-0006 +
seed + the full RLS suite (7+4+26+4+**19** = 60 assertions) run against it,
60/60 passed. Hosted — migration applied and confirmed
(`local==remote`), **16/16 real assertions including actual Supabase
Storage upload/download I/O** (a synthetic `%PDF-`-signed fixture file
really uploaded, really re-downloaded, really hashed) plus the hosted G-12
run, all synthetic data and both Storage objects cleaned up and confirmed
deleted. Vercel Preview redeployed, healthy, Deployment Protection
unchanged and correctly enforced. Full record:
`docs/verification/sprint-1.1-document-intake-verification.md`.

**Sprint 1.1 (Secure Guideline Source Document Intake): Complete and
Hosted-Verified.**

---

## -4. Prior session: Sprint 1 — Guideline Registry Schema and Lifecycle

Implemented the first Sprint 1 vertical slice: an organization-scoped
controlled registry for clinical guidelines (Clinical Domain → Guideline
Authority → Guideline → Guideline Version → Clinical Review → Approval →
Activation → Supersession → Withdrawal), deliberately stopping short of any
PDF ingestion, embeddings, or retrieval/generation work.

**Schema and lifecycle engine** (`supabase/migrations/0005_guideline_registry_and_lifecycle.sql`):
6 new tables (`clinical_domains`, `guideline_authorities`, `guidelines`,
`guideline_versions`, `guideline_reviews`, `guideline_lifecycle_events`),
12 new permissions, 10 SECURITY DEFINER functions (every create/update/
review/lifecycle-transition mutation goes through one, atomically pairing
the write with an `audit_events` row — no table has an INSERT/UPDATE/DELETE
RLS policy for `authenticated` at all), tenant integrity via composite
foreign keys rather than triggers wherever declaratively possible, a
partial unique index guaranteeing one active version per guideline, and
append-only enforcement on review/lifecycle-history tables mirroring
migration 0002's `audit_events` pattern. Full design rationale:
`docs/database/guideline-registry-schema.md`,
`docs/domain/guideline-lifecycle.md`. ADR 0007 records the decision to keep
the clinical-publication lifecycle and the (not-yet-built)
document-processing lifecycle as two separate state machines.

**A real architecture correction made mid-session:** the Admin Guideline
Registry pages were initially built under `/admin/knowledge/guidelines/*`,
matching the mission's suggested routes literally — but `quality_manager`
(who holds `guidelines.approve`/`activate`/`supersede`/`withdraw`) only has
`workspace.quality.access`, not `workspace.admin.access`, so nesting under
`/admin/*` would have made the entire approval/activation workflow
unreachable by the one role meant to perform it. Moved to a neutral
`/knowledge/guidelines/*` route, gated per-page by the specific
`guidelines.*` permission rather than a workspace shell — reachable by
`organization_admin`, `knowledge_manager`, `quality_manager`,
`safety_officer`, `clinical_reviewer`, and `auditor` as their individual
permissions warrant.

**Application layer and UI:** `apps/web/lib/guidelines/{schemas,actions,
queries,errors,ui}.ts` — Zod validation authoritative at the server
boundary, Server Actions wrapping every RPC with `requirePermission` +
correlation IDs + safe typed error mapping, RLS-trusting read queries.
Minimal UI: Admin Guideline Registry (list/filter, new-guideline form with
inline domain/authority quick-add, detail page with permission-aware
lifecycle action buttons and inline review/status history), Reviewer Queue
(`/reviewer/guidelines`), and a read-only Clinician Active Knowledge view
(`/clinician/knowledge`) that can structurally only ever display `active`
versions (RLS-enforced, not UI-filtered).

**Verification, real not assumed:** web lint/typecheck/build all clean;
34/34 `npm run test --workspace=apps/web` assertions (2 new suites this
session: schema validation, error-code mapping); a real `postgres:16`
Docker container (matching CI's `database` job exactly) had all 5
migrations + seed + the full RLS suite (11 + 4 + **26** new guideline
registry assertions) run against it — 41/41 passed. **A real bug was found
and fixed by actually running the test file**: psql's `:'var'` fixture
substitution silently fails to interpolate inside dollar-quoted `DO $$...$$`
blocks (where nearly every assertion lives), producing a bare syntax error
on first run; fixed by threading fixture IDs through a temp table + two
`SECURITY DEFINER` helper functions instead. Full record:
`docs/verification/sprint-1-guideline-registry-verification.md`.

**Hosted Development verification, real not assumed:** migration 0005
applied to the hosted "Noor Development" project
(`supabase db push --linked`, confirmed `local==remote` before/after).
Schema landed correctly (6 tables/RLS enabled, 12 permissions, 24 role
mappings, all functions, the one-active-version index — verified via direct
Management API queries). **18/18 real GoTrue-JWT hosted assertions
passed**: 4 synthetic users (admin/clinician/reviewer/quality) created via
the Auth Admin API, signed in for real access tokens, and exercised
entirely over HTTP (`/rest/v1/rpc/*`) — domain/authority/guideline/version
creation, clinician denied draft access, illegal transition rejected,
approval-without-review rejected, self-approval blocked, non-creator
approve+activate succeeds, clinician then sees the active version, raw
PATCH against an active version rejected, withdrawal-without-reason
rejected, withdrawal-with-reason succeeds and clears
`current_active_version_id`, audit events recorded, cross-tenant creation
denied. All synthetic test data (2 orgs, 4 users) deleted and confirmed via
a zero-count query. Vercel Preview redeployed with the new code
(`target: preview`, `status: Ready`), stable alias re-pointed, Deployment
Protection re-confirmed enabled and correctly enforced (unprotected smoke
test correctly detects and reports the protection wall, not a false pass —
unchanged from Sprint 0.5, since no protection config changed this
session). Full record:
`docs/verification/sprint-1-guideline-registry-verification.md`.

**Sprint 1 (Guideline Registry Schema and Lifecycle): Complete and
Hosted-Verified.**

---

## -3. Prior session: Sprint 0.5 final closure

The one remaining gap from the prior session — Vercel's "Protection Bypass
for Automation" secret, which required a dashboard action no CLI/API path
could perform — was configured by the user. The user then ran the
protected Preview HTTP smoke test themselves (`node
scripts/smoke-test-web.mjs` with `BYPASS_TOKEN` set locally) and reported
the result: **10/10 checks passed**, including all 6 body-content checks
(`/login`, `/forgot-password`, `/403`, `/access-denied`, `/`,
`/design-system`) that previously, without the bypass token, correctly
failed with "blocked by Vercel Deployment Protection" rather than
false-passing.

**Why this result is trustworthy and not a status-code-only pass:**
`scripts/smoke-test-web.mjs` inspects the response `Location` header for
every check and explicitly sets `isVercelSso = true` whenever it points at
`vercel.com/sso-api`, throwing a labeled failure in that case rather than
returning a bare boolean. A body-content check can only report `PASS` by
reaching the `assert(status === 200, ...)` line *after* the `isVercelSso`
branch has already returned false for that response, which happens only
when Vercel's edge actually let the request reach the Next.js app instead
of redirecting to its own SSO interstitial. A structural pass therefore
proves real Noor content was served, not Vercel's protection page — this
is the same script, unmodified, that correctly caught and reported the
protection wall as a failure in the prior session before the bypass was
configured.

**What this session did *not* do:** run the smoke test itself (the bypass
token was configured and used entirely on the user's machine, then removed
from their shell after — correct handling, since this session never had
and does not need that value), and did not perform any browser-driven
form-submission E2E — the smoke test is still an HTTP-level check only,
not a Playwright browser interaction. That remains a documented pre-
Controlled-Beta requirement (§5), not a Sprint 0.5 blocker.

**Sprint 0.5 status: Complete and Hosted-Verified.**

---

## -2. Prior session: Hosted Supabase Development Setup & Sprint 0.5 Closure (partial)

The user provided a Supabase personal access token mid-session (held only
as an in-memory `SUPABASE_ACCESS_TOKEN` for this session — never printed,
never committed). A hosted **"Noor Development"** project already existed
(`quohfsaqeqzbbvmrhmbr`, `eu-west-3`, Postgres 17, created between
sessions) — linked directly rather than creating a new one. All 3 existing
migrations applied cleanly to a genuinely green-field remote (confirmed via
`supabase migration list --linked` showing empty `remote` before, matching
`local` after).

**Real hosted verification, not assumed:** 26 Auth/RLS/Authorization/
Feature-flag/Audit assertions and 8 Storage assertions, all executed with
real GoTrue-issued JWTs against `/rest/v1` and `/storage/v1` — every
single one passed. Full command-by-command record:
`docs/verification/sprint-0.5-hosted-verification.md`.

**One real, previously-unknown finding, fixed and re-verified on the spot:**
hosted verification surfaced that `anon` held full CRUD grants on every
public table (a legacy Supabase project-creation default this specific
project inherited) — RLS already blocked practical access, but this was a
real defense-in-depth gap. Wrote and applied migration
`0004_revoke_anon_table_grants.sql`, re-verified locally (plain Postgres,
guarded no-op there) and on the hosted project (grants now `0`, anon
`SELECT` now genuinely `401`, was `200 []` before).

**A second finding investigated, not just observed:** a password-reset
status-code difference (429 vs 200) turned out to be GoTrue's own default
email-send rate limit (no custom SMTP on this Development project) — root-
caused with a clean two-fresh-address test, confirmed Noor's own UI never
branches on it, documented honestly rather than either hidden or
overclaimed as a bug.

**A genuine, unplanned proof of a Sprint 0 control**: cleaning up the test
audit-event row was *rejected* by the append-only trigger on the hosted
project — cleanup only succeeded after using the documented
`noor.allow_audit_maintenance` override, proving the control (and its
escape hatch) work identically on hosted, not just locally.

Vercel: Preview environment configured with the hosted Development values
(6 vars, Preview-scoped, encrypted), redeployed, confirmed `target:
preview`/`status: Ready`. A stable alias (`noor-preview-dev.vercel.app`)
was created since Vercel's per-deployment URLs are ephemeral and Supabase's
Auth redirect allowlist needs a fixed target. Supabase Auth URLs configured
against that stable alias, no wildcards. Deployment Protection was **kept
enabled** (not disabled) per explicit mission policy; the one remaining
step — "Protection Bypass for Automation" — is dashboard-only (confirmed:
no CLI command, REST API returns 400/404 for the plausible field names/
endpoints) and is documented as the single remaining manual action.

All synthetic hosted test data (2 orgs, 8 users) was created for
verification and fully deleted afterward — confirmed via a zero-count query
across every affected table.

---

## 0. Current phase

**Sprint 1 — workstream S1-D3, Deterministic Page-Aware Chunking,
Complete and Hosted-Verified** (this session). See §-12 above for the
full account. Sprint 0.5 (hosted infrastructure & design system) is
**Complete and Hosted-Verified** — see §-3/§1 for that history; it is
not reopened here. See `MASTER_BACKLOG.md` for the reconciled Sprint 1
workstream breakdown (S1-A/S1-B/S1-C1/S1-C2/S1-D1/S1-D2/S1-D3/S1-E) —
Sprint 1 is no longer tracked as a single flat task list.

**S1-A (Guideline Registry Schema and Lifecycle) — Complete and
Hosted-Verified** (prior session): schema, lifecycle engine, RLS,
permissions, application layer, minimal UI — 41/41 Postgres 16 assertions,
18/18 hosted real-JWT assertions.

**S1-B (Secure Guideline Source Document Intake) — Complete and
Hosted-Verified** (prior session): upload sessions, server-verified object
intake (size/PDF-signature/SHA-256), duplicate detection, idempotent
registration and job creation — 60/60 Postgres 16 assertions (cumulative,
all suites), 16/16 hosted assertions including real Supabase Storage
upload/download I/O. **G-12 also closed** that session, on both
environments. Full record:
`docs/verification/sprint-1.1-document-intake-verification.md`.

**S1-C1 (Durable Processing Orchestration) — Complete and
Hosted-Verified** (prior session): atomic Worker claim, hashed-lease
ownership with heartbeat renewal, exponential-backoff retry, dead-letter
on exhaustion, lease-expiry crash recovery, queued/retry-scheduled
cancellation, all proven with a controlled no-op processor — 85/85
Postgres 16 assertions (cumulative, all suites), a genuine dual-OS-process
concurrency proof (80 jobs, zero double-claims), 30/30 hosted assertions
including a 20-parallel-request real HTTP concurrency race. **Two real,
hosted-only bugs found and fixed that session** — a pgcrypto
`search_path` gap and a default-privileges gap that had silently made the
migration's core trust-boundary claim false (see §-6 above for the full
account). Full record:
`docs/verification/sprint-1.2a-processing-orchestration-verification.md`.

**S1-C2 (Deterministic PDF Page and Text Extraction) — Complete and
Hosted-Verified** (prior session): the Worker's controlled no-op
processor is replaced with a real, deterministic `pypdf`-based extraction
pipeline (ADR 0010) — source integrity revalidated twice independently,
page-level text extraction/normalization, page/artifact checksums,
technical metrics, conservative suspected-scanned detection, a canonical
JSON artifact independently re-verified after upload, atomic finalization
with idempotent identity-based reuse. Full 001–008 Postgres 16 suite
green; two genuine dual-OS-process concurrency proofs; 91/91 Worker
pytest assertions; a real hosted end-to-end flow (real GoTrue JWT, real
Storage, the actual unmodified Worker code). **Two real concurrency bugs
and a real CI-only grant-timing bug found and fixed that session** — see
§-7 for the full account. Full record: §-7 and
`docs/verification/sprint-1.2b-pdf-extraction-verification.md`.

**S1-D1 (Extraction Review and Technical Quality Gate) — locally
complete, hosted verification in progress** (this session): a technical
quality gate structurally separate from S1-C2's execution status (ADR
0011) — review rounds, page/document-level findings against a controlled
23-value taxonomy, explicit per-page review coverage, all 5 terminal
decisions enforced inside one transactional function under lock,
server-derived downstream OCR/chunking eligibility, database-level
self-review blocking, and a deliberately separate permission namespace.
Full 001–009 Postgres 16 suite green across multiple genuinely fresh
containers (applying S1-C2's real CI-only grant-timing lesson from the
start); 39/39 new review-lifecycle/eligibility/RLS assertions; Web
lint/typecheck/build/test all clean including the new review-queue and
side-by-side review workspace routes. See §-8 above for the full account
and `docs/verification/sprint-1-d1-extraction-review-verification.md`
(hosted section pending as of this writing).

---

## 1. History: Sprint 0 and its remediation (prior session, condensed)

A previous sandbox delivery had never actually been a git repository, had a
pass-through auth middleware, an unseeded permissions table, and RLS
verified only against plain PostgreSQL. A remediation session reproduced
every finding, then: initialized real git, built real Supabase SSR auth
(clients, session refresh, login/logout, permission-gated routes),
authored migrations 0002 (permission seeding + auth-hardening triggers) and
0003 (storage foundation), and verified all of it against **both** plain
Postgres and a real local Supabase CLI stack — including a genuine
GoTrue-user → JWT → PostgREST round trip proving RLS enforcement over
actual HTTP. Full detail of that session is preserved in git history
(commits `559aa5d`..`fdfb16b`) and is not repeated here.

---

## 2. Repository statistics (generated, not asserted)

Command: `git ls-files | wc -l` after this session's additions:

* **~115** tracked files (up from 73 at end of Sprint 0 — see `git log
  --stat` for the exact diff per commit)
* **3** SQL migrations, **2** RLS test files (11 assertions), unchanged
  from Sprint 0
* **3** apps/packages became **4**: `apps/web`, `apps/worker`,
  `packages/clinical-schemas`, **`packages/ui`** (new — the design system)
* **32** design-system components (22 generic + 10 clinical), all in
  `packages/ui/components/`

## 3. Git / GitHub status (real, this session)

* Branch: `main`. Remote `https://github.com/abdullawagih1/NOOR.git` —
  **pushed for real this session** (confirmed empty beforehand via
  `git ls-remote`; a stored git credential for github.com was already
  present in Windows Credential Manager, used with the user's explicit
  go-ahead).
* Commits pushed this session (in order): `559aa5d`, `fdfb16b` (prior
  session, pushed now for the first time), `e13d468` (design system +
  password reset), `b1c21e5` (Next.js 15 upgrade), `e635adb` (design-system
  docs). Run `git log --oneline` for the current, authoritative list —
  this document does not repeat commit hashes for anything after this
  point to avoid the exact mistake Sprint 0's remediation was created to
  fix.
* **CI has actually run and passed on GitHub Actions twice** (not just
  YAML-validated): runs `29998063629` (commit `e13d4682`) and
  `30000512766` (commit `e635adbc`, includes the Next.js 15 upgrade),
  5/5 jobs each: Web, Clinical schemas, Worker, Supabase (migrations+RLS),
  Secret scan. See `docs/operations/github-ci.md`.
* CI's push trigger and a `gitleaks` secret-scan job were both added this
  session (`.github/workflows/pr.yml`).

## 4. This session's verification evidence

### Local re-verification (before any change, and again after)

All of Sprint 0's local checks were re-run from clean state before
changing anything, and again after the Next.js 15 upgrade:

```
$ npm ci && npm run lint/typecheck/test/build --workspace=apps/web   → all green, both times
$ npm run typecheck/test --workspace=packages/clinical-schemas       → 6/6, both times
$ npm run typecheck --workspace=packages/ui                          → clean (new package)
$ python -m compileall apps/worker && pytest apps/worker              → 5/5, both times
$ (docker) apply 0001-0003 + seed + both RLS test files against
  plain Postgres 16                                                   → 11/11, both times
```

### Design System (packages/ui) — implemented and verified

* Canonical tokens (`packages/ui/tokens/*.ts`): colors (brand + 16
  semantic states, light+dark), typography, spacing, radius, shadows.
  Consumed by Tailwind (`apps/web/tailwind.config.ts`) and by a runtime
  CSS-variable injector (`TokensStyleTag`) — one source, zero duplication.
* 22 generic primitives + 10 Noor clinical components, all typechecked,
  all rendered on `/design-system` with mocked data.
* `/design-system` calls `notFound()` when `NODE_ENV==="production"` —
  verified via a real production build + `next start`: returns 404 there,
  reachable only in `next dev`.
* Every pre-existing route (login, 403, access-denied, 4 workspaces) was
  restyled onto the new components in the same session.
* Real WCAG contrast was computed (not asserted) for every token pairing —
  see `docs/design-system/ACCESSIBILITY.md`. One real, documented exception
  found: `muted-soft` on `canvas` (3.02:1, fails AA-normal) — scoped to
  placeholder-only text with an always-visible label alongside it, not
  silently ignored.
* ADR 0005 records the composition decision (50% Better / 25% NHS / 15%
  Carbon / 10% DESIGN.md warmth) and what was deliberately *not* carried
  from DESIGN.md (Airbnb brand color, terminology, typefaces).

### Auth: password reset — implemented and verified (build-level)

`/forgot-password` → `resetPasswordForEmail` (generic success message,
no account-enumeration oracle) → email link → `/auth/callback` (code
exchange, pre-existing route) → `/update-password` →
`supabase.auth.updateUser`. Public signup remains disabled — documented as
an intentional V1 Controlled Beta policy (invite-only), not an oversight,
on the login page itself and in `KNOWN_LIMITATIONS.md`.

### Real HTTP smoke test (local `next start` + real local Supabase)

```
$ npx supabase start                                    → real GoTrue/PostgREST/Postgres stack
$ npm run build --workspace=apps/web  (real Supabase env vars, not placeholders)
$ NODE_ENV=production npx next start -p 3000
$ node scripts/smoke-test-web.mjs
→ 10/10 PASS: unauthenticated redirects to /login on all 4 workspace routes,
  /login /forgot-password /403 /access-denied /  all 200,
  /design-system 404s in production
```

This is real evidence against a real running server — not a unit test.
`docker rm -f` / `supabase stop` afterward; no stray containers left running.

### Next.js 14.2.35 → 15.5.21 upgrade — spiked, then applied

`npm audit` on 14.2.35: ~19 advisories, several genuinely reachable through
Noor's actual Server Action / Middleware usage (not just theoretical). No
non-breaking fix exists within the 14.x line (14.2.35 is the newest stable
14.x release). Spiked the 15.x upgrade in an isolated `git worktree`
first — hit Next 15's "Async Request APIs" breaking change immediately
(`cookies()` and `searchParams` are now Promises), fixed 7 files, re-ran
lint/typecheck/test/build clean in the spike, then ported the identical fix
to `main` and re-verified there too. `next` no longer appears in
`npm audit` afterward. Full advisory list, exposure analysis, and decision
in `docs/architecture/adr/0006-nextjs-security-version-strategy.md`.

### Vercel — deployment pipeline verified; HTTP verification blocked

Vercel CLI was already authenticated on this machine. First `vercel link`
(run from `apps/web`) created a project scoped to *only* that directory —
the build failed trying to fetch `@noor/ui` from the public npm registry,
since it never saw the workspace root. Fixed via the Vercel REST API
(`rootDirectory: "apps/web"`, `framework: "nextjs"` — no CLI subcommand
exists for this), re-linked from the repo root, and the build succeeded
(2.2MB uploaded — the whole repo, correctly this time).

The **first** deployment landed as `target: production` despite `--yes`
(empirically confirmed: a project's first-ever deployment is always
Production, regardless of flags — no working Supabase credentials are
wired to it, so nothing sensitive is actually live). A second deploy with
`--target=preview` correctly returned `target: preview`
(`vercel inspect` confirmed).

**HTTP-level verification against that live Preview URL is blocked**: every
route, including `/login`, redirects to `vercel.com/sso-api` — this team's
default "Vercel Authentication" Deployment Protection, which runs in front
of the Next.js app entirely. A first pass at smoke-testing this URL
produced false-positive "200 OK" results because `fetch()` auto-follows
that redirect to Vercel's *own* SSO page (which also returns 200) — caught
by inspecting the response body, not trusted at face value. See
`docs/operations/vercel-preview-deployment.md` for the full account and the
two remediation options (disable protection, or configure a Protection
Bypass for Automation secret) — both are project-setting decisions for the
owner, not something applied unilaterally here.

### Not run (and why)

| Check | Reason not run |
|---|---|
| RLS suite against a **hosted** Supabase project | No hosted project — blocked on credentials (G-01) |
| Full HTTP smoke test against deployed Vercel Preview | Blocked by Vercel Deployment Protection (G-08) |
| Browser-driven (Playwright) E2E of the login/reset forms | Not installed this session; Next's Server Action wire protocol isn't a stable plain-`fetch` target — documented Sprint 1 gap, not faked |
| Load / penetration tests | No deployed target with real data |

---

## 5. Gap report

| Gap | Impact | Dependency | Risk | Owner | Next task |
|---|---|---|---|---|---|
| G-03: Clinical domain not confirmed | No default clinical domain is seeded anywhere (deliberately — migration 0005 seeds none); blocks choosing *which* guideline content to actually register first | Clinical partner decision | Medium | Product/Clinical | Confirm a domain (e.g. hypertension) or another starting scope |
| G-04: No AI provider selected | Blocks generation-side work | Provider spike | Medium | AI/RAG | Sprint 1 (S1-07) |
| G-07: Auth covers session/permission layer, not full account lifecycle | No signup, no admin member-management screen | None — incremental | Low | Frontend/Backend | Sprint 1 |
| G-09: No Playwright/browser E2E | Login/reset form submission unverified end-to-end via a real browser (the HTTP smoke test proves route protection and page delivery, not form interaction) | None — can start anytime | Low | Frontend/QA | **Pre-Controlled-Beta requirement, not a Sprint 1 blocker** |
| G-10: No custom SMTP on hosted Development project | Default GoTrue email-send rate limit is low; can affect real password-reset email volume | Configure custom SMTP in Supabase dashboard | Low | DevOps | Before Controlled Beta, not blocking Sprint 1 |

**Closed this session:** G-13 (no processing-worker claim/retry
implementation — the orchestration control plane is now real: atomic
claim, hashed-lease ownership, heartbeat renewal, exponential-backoff
retry, dead-lettering, crash recovery, and cancellation all exist and are
hosted-verified, proven with a controlled no-op processor). The Durable
Processing Orchestration workstream (S1-C1) itself is Complete and
Hosted-Verified.

**Closed this session:** G-14 — the Worker's controlled no-op processor is
replaced with a real, deterministic PDF page/text extractor (`pypdf`, ADR
0010). Source integrity is revalidated twice independently before any
extraction; a canonical JSON artifact (proven byte-identical across
repeated runs) is uploaded privately and independently re-verified;
finalization is atomic with idempotent identity-based reuse. Two real
concurrency bugs were found and fixed by actually racing two independent
processes at the same extraction identity — see §-7 for the full account.
Verified both locally (001–008 RLS suite, two genuine dual-process
concurrency proofs, 91/91 Worker pytest assertions, full web
build/lint/test) and against the real hosted Development project (real
GoTrue JWT, real Storage upload/download, the actual unmodified Worker
code claiming and extracting a real PDF, idempotent reprocessing, trust
boundary, RLS) — see §-7 and
`docs/verification/sprint-1.2b-pdf-extraction-verification.md`. The
Deterministic PDF Extraction workstream (S1-C2) itself is Complete and
Hosted-Verified.

**Closed this session:** the extraction-review hosted-verification gap —
migration 0009 applied, the full 007+008+009 SQL suite (63 assertions)
and a real end-to-end GoTrue-JWT flow (including the real, unmodified
Worker code producing the underlying extraction, then real review
lifecycle RPC calls) both verified against real hosted Postgres 17. See
§-8 for the full account.

**Closed prior sessions:** G-01 (hosted Supabase), G-08 (Vercel Protection
Bypass), G-11/G-12 (Sprint 1.1 items), G-02/G-05/G-06 (Sprint 0 items) —
see git history for the session-by-session record; not repeated here.

None of the remaining gaps (G-03, G-04, G-07, G-09, G-10) block starting
Sprint 1-D2 — each is either a product/clinical decision, later Sprint 1
work explicitly out of scope (AI provider selection), or a documented
pre-Controlled-Beta requirement.

---

## 6. Recommended next task

Workstream S1-D3 (Deterministic Page-Aware Chunking) is complete and
hosted-verified: migrations 0012/0013 (chunking runs/chunks/spans,
chunk technical review, embedding readiness), the Worker chunking
pipeline (`noor-simple-tokenizer` v1, deterministic segmentation, the
oversized-block fallback cascade, coverage/duplication verification),
and the web application UI (`/reviewer/chunking` queue and workspace)
are all implemented and verified against plain Postgres 16 (202/202
cumulative RLS assertions), the Worker test suite (114/114, including 35
new chunking assertions), the Web test suite (17/17 files, including 34
new chunking assertions) plus a clean lint/typecheck/production build,
and real hosted Development infrastructure (30/30 end-to-end checks
using the actual unmodified Worker code, all synthetic data cleaned up
and confirmed zero-residual). See §-12 for the full account, including
six real bugs found and fixed, and
`docs/verification/sprint-1-d3-chunking-verification.md` for the
complete verification record.

**Recommended next step**:

```text
Begin S1-E — Retrieval Preparation and Evaluation Foundation
(MASTER_BACKLOG.md): AI provider spike/selection (embedding/reranker/
LLM, data-residency constraints in scope), adapter interfaces, pgvector
indexing, and a hybrid retrieval foundation over the now-eligible
(eligible_for_embedding) chunks this sprint produced.
```

G-03 (clinical domain confirmation) should ideally be resolved before or
alongside real content work. Playwright browser-driven E2E (G-09) stays
a documented pre-Controlled-Beta requirement, not a blocker.
