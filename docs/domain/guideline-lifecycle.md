# Guideline Lifecycle — State Machine and Permission Matrix

Source: `supabase/migrations/0005_guideline_registry_and_lifecycle.sql`,
function `transition_guideline_version`. This is the **only** place
`guideline_versions.lifecycle_status` can change — enforced at the database
layer (see `docs/database/guideline-registry-schema.md`), not merely by
convention.

## States

```
draft → ready_for_review → approved → active → superseded → withdrawn
```

Six states total. `guideline_reviews.review_status` (`pending`,
`changes_requested`, `recommended_for_approval`, `rejected`) is a
**separate** concept — a review is feedback attached to a version while
it's `ready_for_review`; it never changes the version's own
`lifecycle_status` directly (see "Review vs. transition" below).

## Allowed transitions

| From | To | Permission required | Extra preconditions |
|---|---|---|---|
| `draft` | `ready_for_review` | `guidelines.submit_for_review` | — |
| `ready_for_review` | `draft` | `guidelines.review` **or** `guidelines.submit_for_review` | Reason required |
| `ready_for_review` | `approved` | `guidelines.approve` | At least one `guideline_reviews` row with `review_status = 'recommended_for_approval'`; approver ≠ version's `created_by` (self-approval blocked) |
| `approved` | `draft` | `guidelines.approve` | Reason required (explicit revocation — see below) |
| `approved` | `active` | `guidelines.activate` | — |
| `active` | `superseded` | `guidelines.supersede` | — |
| `active` | `withdrawn` | `guidelines.withdraw` | Reason required |
| `superseded` | `withdrawn` | `guidelines.withdraw` | Reason required |

**Every other (from, to) pair is illegal**, including `draft → active`,
`ready_for_review → active`, `withdrawn → active`, `superseded → active`,
and any jump that skips review or approval. `transition_guideline_version`
raises `illegal lifecycle transition: <from> -> <to>` for all of them —
verified directly in `supabase/tests/rls/003_guideline_registry.sql`
(TEST 6).

## Design decision: approved → draft (revocation) is allowed

The mission asked us to decide explicitly whether an approved version may
return to draft, rather than only ever forward through the pipeline.
**Decision: yes, through the same permissioned, reasoned transition path**
(`guidelines.approve`, mandatory reason) — functionally a "recall before
activation." Rationale: an approval can be found to be wrong (a reviewer
surfaces a concern after the fact, an authority issues a correction) before
the version ever went live; forcing a brand-new version for a
pre-activation correction would be needless churn. Once a version reaches
`active`, correcting it always means a **new version**, never mutating
released content — `active`, `superseded`, and `withdrawn` versions are
immutable (no RLS write path exists at all for those, or any, states — see
the security doc).

## Design decision: manual supersession without a replacement

`active → superseded` is reachable directly (`guidelines.supersede`), not
only as a side effect of activating a replacement version. This covers a
real scenario: an authority retracts guidance before Noor has a new,
reviewed version ready. Manual supersession clears
`guidelines.current_active_version_id` (no replacement is implied) and does
not require a `supersedes_version_id` reference. Activation-driven
supersession (below) is the more common path and does establish that
lineage automatically.

## Activation is transactional and supersedes automatically

Activating version B of a guideline that currently has version A active:

1. Locks both the version and guideline rows (`SELECT ... FOR UPDATE`).
2. Transitions A: `active → superseded`, writes a lifecycle event + audit
   event for A.
3. Transitions B: `approved → active`, sets `B.supersedes_version_id =
   coalesce(B.supersedes_version_id, A.id)` if not already set.
4. Updates `guidelines.current_active_version_id = B.id`.
5. Writes B's own lifecycle event + audit event.

All in one Postgres function call — no window where both A and B are
simultaneously active, or neither is, is ever observable. A partial unique
index (`guideline_versions_one_active_per_guideline`) enforces "at most one
active version per guideline" as a database guarantee independent of this
function's correctness. Verified end-to-end in
`supabase/tests/rls/003_guideline_registry.sql` TEST 15.

## Review vs. transition — why they're separate actions

A `guideline_reviews` row is a reviewer's recorded opinion; a lifecycle
transition is a status change. They are deliberately not coupled 1:1:
submitting a `changes_requested` or `rejected` review does **not**
automatically move the version back to `draft`. A second, explicit,
permissioned, reasoned transition does that. This keeps "what a reviewer
said" (append-only, never mutated) cleanly separate from "what actually
happened to the version's status" (also append-only, in
`guideline_lifecycle_events`, but a distinct event stream) — mirroring the
same clinical-vs-processing separation principle ADR 0007 applies at the
document level, applied here internally between review feedback and status
control.

## Permission matrix

| Permission | Grants ability to | Roles |
|---|---|---|
| `guidelines.read_active` | Read only `active` versions | `clinician`, `clinical_pharmacist` |
| `guidelines.read_all` | Read every lifecycle state | `clinical_reviewer`, `knowledge_manager`, `quality_manager`, `safety_officer`, `organization_admin`, `auditor` |
| `guidelines.create` | Create guidelines and new draft versions | `knowledge_manager`, `organization_admin` |
| `guidelines.update_draft` | Edit guideline/version metadata while `draft` | `knowledge_manager`, `organization_admin` |
| `guidelines.submit_for_review` | `draft → ready_for_review`; also `ready_for_review → draft` | `knowledge_manager`, `organization_admin` |
| `guidelines.review` | Submit a review; also `ready_for_review → draft` | `clinical_reviewer` |
| `guidelines.approve` | `ready_for_review → approved`; `approved → draft` (revocation) | `quality_manager` |
| `guidelines.activate` | `approved → active` | `quality_manager` |
| `guidelines.supersede` | `active → superseded` | `quality_manager` |
| `guidelines.withdraw` | `active/superseded → withdrawn` | `quality_manager`, `safety_officer` |
| `guideline_authorities.manage` | Create/update authorities | `knowledge_manager`, `organization_admin` |
| `clinical_domains.manage` | Create/update domains | `knowledge_manager`, `organization_admin` |

Two deviations from the mission's literal suggested table, both recorded
here for transparency (Clinical Safety Agent decisions):

* **`knowledge_manager`** (an existing Sprint 0 role — "registers and
  manages guideline documents," per migration 0001) was given the
  create/update-draft/authorities/domains permissions **in addition to**
  `organization_admin`, rather than routing all authoring through
  `organization_admin` alone. `organization_admin` retains the same set as
  an administrative override.
* **`safety_officer`** additionally received `guidelines.withdraw` (the
  mission's table only lists it for `quality_manager`) — consistent with
  the role's documented purpose, "owns incident response and emergency
  shutdown": if a live guideline is later found unsafe, safety officer can
  force-withdraw it without waiting on the quality workflow.

Review and approval/activation are held by different roles
(`clinical_reviewer` vs. `quality_manager`) by design — separable duties,
per the mission's requirement.

## Clinician visibility

A clinician (or anyone without `guidelines.read_all`) can query
`guideline_versions` and will only ever see rows where `lifecycle_status =
'active'` — enforced by RLS policy `guideline_versions_select_active_for_members`,
not by UI filtering. Drafts, pending reviews, approved-but-not-yet-active,
superseded, and withdrawn versions are invisible to that caller at the
database layer regardless of what the application code does or doesn't
filter client-side. See `docs/security/guideline-registry-authorization.md`.
