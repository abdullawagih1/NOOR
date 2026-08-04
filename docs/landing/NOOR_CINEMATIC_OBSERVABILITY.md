# NOOR Cinematic Landing — Observability

Status: **LX-1.2 — Gap documented, no new vendor introduced, per mission §31.**

## What exists today

Nothing. Confirmed directly this mission (grep across `apps/web` for `web-vitals`, `reportWebVitals`, `analytics`, `telemetry`): there is no first-party Web Vitals pipeline, no analytics vendor, no session-replay tool, and no error-tracking service anywhere in this codebase, on any route, predating this mission.

## What this mission did NOT do, deliberately

Per mission §31's own instruction ("If no approved observability exists: Document the gap. Do not introduce a new vendor in this mission"), no telemetry code was added — not a first-party `useReportWebVitals` hook, not a lightweight custom beacon, nothing. Adding instrumentation with no approved backend to receive it would itself be "introducing a new vendor/mechanism," which the mission explicitly rules out, even for well-intentioned first-party code.

## What was measured instead (local/CI, not production telemetry)

Every performance number in this mission's verification report (`docs/verification/lx-1-2-production-integration.md`) and `NOOR_CINEMATIC_PERFORMANCE_BUDGET.md` was captured via one-off Lighthouse/Playwright runs against a real local production build — not via any persistent monitoring pipeline. These numbers describe the build at the moment they were captured; they are not continuously tracked.

## What a real pipeline would need, if approved in a future mission

If NOOR later adopts a first-party Web Vitals pipeline, the natural integration points already exist without new instrumentation:

- `window.__noorCinematicDiagnostics` (LX-1.2, `EvidenceCoreScene.getDiagnostics()`) already exposes real-time renderer counters (draw calls, triangles, active particles) — harmless aggregate numbers, no user data, already used by this mission's own verification scripts. A future pipeline could read this the same way.
- `window.__noorCinematicTimeline` (LX-1.1.1) already exposes scene/progress state.
- Landing experience variant (`legacy`/`cinematic`) and quality tier (`high`/`balanced`/`static`) are both already resolvable synchronously from existing module exports (`getPublicLandingExperience()`, `useQualityTier`'s tier state) — no new resolution logic would be needed to tag a future metric with either dimension.

None of this is wired to any destination today — it is only read by this mission's own temporary verification scripts, which were not committed to the repository.

## What must never be sent, if a pipeline is ever added

Per mission §31: no user content, no clinical content, no full URLs containing sensitive query parameters, no device fingerprint, no GPU model as user-identifying telemetry, no session replay. The existing `useInitialQualityTier()` hook (LX-1.1.1) already avoids fingerprinting by design (coarse viewport/hardwareConcurrency/deviceMemory checks only, never transmitted anywhere) — a future pipeline should preserve that constraint, not just avoid violating it by omission.
