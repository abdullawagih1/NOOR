# NOOR Landing Capability Truth Matrix

Status: **LX-1.0 — In Progress**

**LX-1.3 addendum:** re-audited a second time as part of launch-readiness
hardening (mission §43). No row's status changed. Retrieval, vector
evaluation, hybrid retrieval, reranking, and clinical-answer-generation
claims were specifically re-checked and remain correctly labeled
`Internal evaluation foundation`/`Future vision` — none of these are
presented as clinician-facing in either landing variant. Every visible
demonstration remains synthetic, non-patient, non-prescriptive,
non-diagnostic — confirmed by direct scene-copy review, unchanged from
LX-1.1.1.

**LX-1.2 addendum:** every claim on both the legacy and cinematic
landing variants was re-audited against this matrix as part of
production integration (mission §12). No row's status changed — no
repository evidence discovered this mission promotes any capability
from `In development`/`Future vision` to `Available`. The cinematic
Product Vision scene's "Synthetic demonstration — not clinical
guidance" label and every retrieval/embedding-related status chip
remain unchanged from LX-1.1.1's own truthful labeling.

Every public claim in the future landing narrative must trace to a row
in this table. If a claim has no row, it does not go on the landing
page. This matrix was built by reading the actual migrations, RLS
tests, Worker code, and verification reports for each workstream —
not by trusting sprint titles.

Status legend: `Available` (hosted-verified, shipped) · `In development`
(schema/code exists, explicitly scoped as evaluation-only or not yet
extended to production use) · `Future vision` (no code exists yet) ·
`Not planned` (explicitly out of scope by governing rule) · `Unknown`.

## Available (hosted-verified, shipped)

| Capability | Repository Evidence | Current Status | Allowed Public Claim | Prohibited Claim | Landing Section |
| --- | --- | --- | --- | --- | --- |
| Guideline registry & clinical lifecycle | Migrations for `guidelines`/`guideline_versions`, review/approval/activation/supersession/withdrawal states (S1-A); RLS-tested | Available | "Guidelines move through a controlled lifecycle: drafted, reviewed, approved, and versioned." | "AI-approved guidelines" / any claim of automated clinical approval | 2, 9 |
| Secure, tenant-isolated document intake | `document_intake_events`, checksum/SHA-256 verification, private Storage upload, RLS-tested cross-tenant denial (S1-B) | Available | "Every source file is checksum-verified and registered inside a tenant-isolated boundary before processing begins." | "Files are scanned for clinical accuracy" | 3 |
| Durable processing orchestration | `document_processing_jobs`, claim/lease/heartbeat/retry/dead-letter (S1-C1), hosted-verified | Available | "Processing is durable — jobs resume safely, nothing silently disappears." | "Real-time processing" (jobs are asynchronous, not instant) | 3, 9 |
| Deterministic PDF extraction | `document_extraction_pages`, reproducible page-level text + immutable artifacts (S1-C2) | Available | "Extraction is deterministic — the same source produces the same result every time." | "Extraction understands clinical meaning" (it produces text, not interpretation) | 4, 5 |
| Human extraction review & technical quality gate | `document_extraction_reviews`, reviewer accept/reject with recorded findings, downstream eligibility gated on acceptance (S1-D1) | Available | "A human reviewer decides when an extracted page is technically ready — nothing downstream proceeds without that decision." | "Automated quality assurance" (the gate is a human decision, not an algorithmic pass) | 4 |
| Controlled, page-scoped OCR | `document_ocr_runs`/reviews, OCR only on reviewer-flagged pages, second human OCR review (S1-D2) | Available | "OCR is applied only to the specific pages a reviewer flags — never automatically to a whole document." | "Automatic OCR for all documents" | 4 |
| Deterministic, page-aware chunking | `document_chunks`, exact source spans, checksum-bound, provenance-linked to accepted pages (S1-D3) | Available | "Accepted pages are broken into structured chunks that keep an exact, checksum-verified link back to their source page." | "AI-powered chunking" (chunking is deterministic and rule-based, not model-driven) | 5 |
| Retrieval evaluation foundation | `retrieval_evaluation_datasets/queries/judgments/runs/metrics/failures`, frozen datasets, two-person human relevance judgments, deterministic lexical baseline retriever `noor-lexical-baseline` (S1-E1), hosted-verified | Available (as an **internal evaluation framework**, not a clinician-facing search feature) | "Retrieval quality is measured against frozen, human-judged evaluation sets before any retrieval method is trusted." | "NOOR has search" / "clinicians can search guidelines today" (no clinician-facing retrieval UI exists) | 6 |
| Self-hosted embeddings & vector index | `document_chunk_embeddings` (pgvector, HNSW), approved config `noor-multilingual-e5-base-v1` (`intfloat/multilingual-e5-base`), exact-vs-indexed correctness validation, vector baseline evaluated against the same frozen judgments and honestly compared to lexical (S1-E2), hosted-verified | Available (as an **internal evaluation framework**, not a clinician-facing feature) | "A semantic (vector) retrieval method has been built and evaluated — self-hosted, so no source text ever leaves NOOR's infrastructure." | "Semantic search is live for clinicians" / "AI understands your questions" | 6 |
| Official brand & design system | `packages/ui/tokens/*`, `/design-system` route, WCAG 2.2 AA contrast-checked (UX-1) | Available | (Used implicitly — the landing simply *is* the brand, no claim needed) | — | All |
| Public surface visual acceptance | Current `/` page, `PublicShell`, light clinical theme (UX-1.1) | Available | (Baseline for this mission — see §5 of `LX-1-0_BASELINE.md`) | — | — |

## In development

| Capability | Repository Evidence | Current Status | Allowed Public Claim | Prohibited Claim | Landing Section |
| --- | --- | --- | --- | --- | --- |
| Hybrid (lexical + vector) retrieval | Explicitly out of scope through S1-E2; `MASTER_BACKLOG.md` lists S1-E3 — Hybrid Retrieval as "Future" | In development | "We're building toward combining lexical and semantic retrieval." | Any claim that hybrid retrieval exists or is measured today | 6, 7 |
| Reranking / cross-encoders | No code anywhere in the repository; explicitly named as out-of-scope in every retrieval-sprint mission to date | In development (label used loosely — more precisely "designed for, not started") | "Future retrieval stages are designed to add a ranking-refinement step." | Any claim reranking runs today | 7 |

## Future vision (no code exists)

| Capability | Repository Evidence | Current Status | Allowed Public Claim | Prohibited Claim | Landing Section |
| --- | --- | --- | --- | --- | --- |
| Evidence-grounded clinical intelligence / RAG | No LLM integration, no generation pipeline, no prompt code anywhere in `apps/worker` or `apps/web` | Future vision | "NOOR is building toward clinical intelligence that stays connected to the evidence behind it." | Any implication this exists, is in beta, or can be tried | 7, 8 |
| Claim-level citations from generated answers | Depends entirely on the unbuilt generation pipeline above; `CitationCard`/`EvidenceCard` components exist in `packages/ui` as **presentation primitives only**, with no live generated-answer data source | Future vision | "Designed so every generated statement can point back to its exact source span." | "NOOR shows citations today" | 8 |
| Clinical decision-support interfaces | No such route or component exists | Future vision | "Product vision: a workspace where a clinical question and its supporting evidence stay side by side." | Any implied availability | 7 |
| Patient-specific decision support | No patient data model exists anywhere in the schema | Not planned for the foreseeable roadmap; treat as future vision at most, never implied as near-term | (No landing claim — do not raise this topic unprompted) | Any claim of patient-specific advice, dosage, or diagnosis | — |

## Not planned / explicitly out of scope by governing rule

| Capability | Repository Evidence | Current Status | Allowed Public Claim | Prohibited Claim | Landing Section |
| --- | --- | --- | --- | --- | --- |
| EHR integration | No integration code, no roadmap entry in `MASTER_BACKLOG.md` | Not planned (no evidence either way beyond absence) | (No landing claim) | Any claim of integration | — |
| Regulatory / medical-device approval | No certification documents in the repository; `SECURITY.md`/`KNOWN_LIMITATIONS.md` never claim this | Not planned / not held | (No landing claim; if governance section needs a line, use: "NOOR does not claim regulatory or medical-device certification.") | Any claim of FDA/CE/other regulatory clearance | 9 |
| Autonomous clinical decision-making replacing clinicians | Governing principle across every sprint's mission text ("no model may be declared superior… clinician authority") | Not planned by design | "Clinicians retain authority over every clinical decision NOOR supports." | "Replaces clinicians," "autonomous doctor," any diminishment of clinician authority | 9 |

## Claims this matrix explicitly forbids anywhere on the landing page

- "AI-generated clinical answers" as a present-tense product feature.
- "Zero hallucinations" / "guaranteed accuracy" / "perfect safety."
- Any customer logo, testimonial, hospital-partnership claim, or usage statistic — none exist and none may be fabricated (§12 of the mission, reaffirmed here).
- Any claim that vector or lexical retrieval is clinician-facing today — both are internal evaluation frameworks, verified in `docs/verification/sprint-1-e1-retrieval-evaluation-verification.md` and `docs/verification/sprint-1-e2-embedding-and-vector-verification.md` as such.
- Any regulatory, compliance-certification, or medical-device claim.

## Traceability

This matrix is the single source of truth the Content System
(`NOOR_LANDING_CONTENT_SYSTEM.md`) and every prototype's copy must cite
before writing a headline, proof point, or status label. Any future
change to a capability's real status (e.g., S1-E3 shipping hybrid
retrieval) requires updating this matrix **before** updating any
landing copy that depends on it.
