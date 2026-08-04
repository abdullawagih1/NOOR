# Sprint LX-1.1 — High-Fidelity Cinematic Prototype Verification

Status: **LX-1.1 — High-Fidelity Cinematic Prototype Complete, Pending User Visual and Motion Approval**

This report records what was actually built, broken, root-caused, and
fixed — real command output and real browser evidence throughout,
including a genuine upstream library incompatibility that forced a
mid-mission architecture change.

## 1. Why LX-1.0's prototype was insufficient (starting state)

The user's own words: *"Card → Play button → Step changes → Static or
barely perceptible state transition."* LX-1.0's gallery
(`/design/landing-experience`) was accurate to that description — 6
technically-correct, independently-triggered demos, never one
continuous world. This mission's approved direction required the
opposite: one fixed 3D object, present throughout, driven by the
page's own scroll — confirmed as the concrete gap by directly
re-reading the LX-1.0 code before writing anything new.

## 2. The real blocker: React Three Fiber does not work in this stack

`@react-three/fiber@8.18.0` + `@react-three/drei@9.122.0` were
installed and fully integrated exactly per the mission's plan. Every
mount crashed:

```
TypeError: Cannot read properties of undefined (reading 'ReactCurrentOwner')
  at react-reconciler's createRenderer call
```

Root-caused in order (not guessed around):

1. Ruled out duplicate `react` copies (`npm ls react` — single deduped 18.3.1).
2. Bumped `react-reconciler` to `0.29.2` (the exact version whose own `peerDependencies` names `react: ^18.3.1`) — identical crash.
3. Webpack `resolve.alias` forcing a single `react`/`react-dom` instance — first attempt broke `react/jsx-runtime` resolution; the corrected (directory-based) alias then broke **every server-rendered page** (`(0, _react.cache) is not a function`) because it also touched Next's server compilation, which needs Next's own `react-server`-condition build. Scoping to `!isServer` fixed the server breakage; the canvas crash was unchanged.
4. `transpilePackages: ["three", "@react-three/fiber", "@react-three/drei"]` (the R3F docs' own official Next.js guidance) — no change.
5. Removed the `next/dynamic` boundary (static import) to rule out the async-chunk boundary itself — same crash.
6. `WebSearch`/`WebFetch` research (not guessing) found `vercel/next.js#71836`, `#66468`, and `pmndrs/react-three-fiber#3417`/`#3440`/`#3446` — multiple independent reports of the **exact same crash on the exact same React 18.3.1 + Next.js 15.0–15.6 + fiber 8.17–8.18 combination this repository uses**. The library maintainer's own reply: *"react-three-fiber v8 does not support React 19. We have a v9 release candidate which does."* — but the only fix path (React 19) is a whole-app major version upgrade, unacceptable risk for one prototype route.

**Resolution:** `@react-three/fiber` and `@react-three/drei` were
uninstalled. `three` was kept. The Evidence Core is built and animated
with plain, imperative Three.js (`EvidenceCoreScene.ts`, a class with
`update()`/`dispose()` methods, no React renderer involved at all) —
zero dependency on `react-reconciler`, so this entire bug class cannot
occur. Full account: `docs/landing/NOOR_CINEMATIC_TECHNICAL_ARCHITECTURE.md`
§"Why raw Three.js, not React Three Fiber"; decision record updated in
`docs/landing/NOOR_LANDING_THREEJS_DECISION.md` §"LX-1.1 Amendment".

After the pivot, the canvas was confirmed genuinely rendering — not
just present in the DOM — via a direct `gl.readPixels()` check and,
more conclusively, visual screenshot inspection at every scene (§6).

## 3. Real bugs found and fixed (beyond the R3F pivot)

1. **Hydration mismatch #1** (`CinematicNav.tsx`): the "Reduce motion" checkbox's visibility depended on `useReducedMotion()`, a client-only media-query read that differs between SSR (always "no preference") and a client whose OS actually requests reduced motion. Caught via Next's dev overlay + a real hydration error, not inspection. Fixed with a `mounted`-gated render, deferring the conditional until after hydration.
2. **Hydration mismatch #2** (`CinematicExperience.tsx`): the same pattern, this time deciding the canvas-vs-static-poster branch — server rendered the canvas branch, a reduced-motion client's first paint rendered the static branch. Same `mounted`-gate fix.
3. **Hydration mismatch #3** (`SceneSectionReveal.tsx`, used by all 7 scenes): the same pattern again, this time an attribute mismatch (`opacity`/`transform` inline styles) rather than a structural one. Same fix, applied identically across all 7 sections since they share the one component.
4. **LCP image missing `priority`**: a real, correctly-flagged Next.js warning — the nav logo is the LCP element; fixed by setting `priority` instead of the placeholder `priority={false}`.

All three hydration fixes follow the same root cause: `useReducedMotion()` resolves synchronously on the very first client render (before any effect fires), while SSR has no way to know the real preference. This is a systemic pattern worth checking across the rest of `apps/web` in a future sprint — noted in `KNOWN_LIMITATIONS.md`, not silently left for someone else to rediscover.

## 4. Verification commands run

```
npm run typecheck --workspace=apps/web   → clean
npm run lint --workspace=apps/web        → clean (0 warnings, 0 errors)
npm run build --workspace=apps/web       → clean; route sizes in §7
npx tsc --noEmit (packages/ui)           → clean
npx tsc --noEmit && npx tsx src/structuredAnswer.test.ts (packages/clinical-schemas) → clean, 6/6
```

**apps/web test suite** — all 21 test files, run directly (bypassing
`npm-cli.js`, the same Windows-only wrapper hang documented in
Sprint LX-1.0's own verification report), exit code 0, all pass —
including `public-pages-content.test.ts`'s production-route regression
guards (12/12 assertions: single CTA, no retrieval/AI-answer claims,
`data-theme="light"` pin, etc.).

`apps/worker` was not modified this mission (no backend scope) and was
not re-run, matching LX-1.0's own precedent.

## 5. Production route protection (real server, not inferred)

```
next build && next start -p 4540
curl /                          → 200
curl /design/cinematic-landing  → 404
```

`git diff --stat -- apps/web/app/page.tsx apps/web/app/PublicShell.tsx
apps/web/app/layout.tsx` returned empty — production landing page,
shell, and root layout are byte-for-byte unchanged. `apps/web/next.config.mjs`
is also byte-identical to its pre-mission state (`git diff` empty) —
none of the webpack/transpilePackages workarounds attempted during
root-causing were needed once the raw-Three.js pivot was made, so none
were left behind.

## 6. Browser evidence

All captured with real headless Chromium (`playwright-core`) against
the real dev server — the route intentionally 404s in production
(§5), so pre-launch evidence can only come from development mode; this
is stated plainly, not hidden.

### Screenshots (`docs/verification/screenshots/lx-1-1/`)

Motion-state checkpoints were **calibrated, not approximated**: an
initial pass targeting scroll percentage via `document.body.scrollHeight`
drifted up to 16 percentage points from the real `ScrollTrigger`
progress (the fixed nav/canvas layers make body height an unreliable
proxy). Replaced with a binary-search helper (`scrollToExactProgress`)
that scrolls until the app's own debug-overlay-reported progress
matches the target within 0.005 tolerance — every checkpoint below is
verified against the *real* reported scene/progress, not assumed from
scroll position.

| File | Target | Real scene/progress reported |
| --- | --- | --- |
| `scene1-start-desktop.png` | 0% | scene 1, progress 0.004 |
| `scene1-end-desktop.png` | 13% | scene 1, progress 0.133 |
| `scene2-verified-desktop.png` | 20% | scene 2, progress 0.203 |
| `scene3-locked-desktop.png` | 35% | scene 3, progress 0.352 (before the 0.388 accept threshold — lock still closed) |
| `scene3-accepted-desktop.png` | 41% | scene 3, progress 0.406 (past the accept threshold — lock open, emerald pulse) |
| `scene4-chunks-formed-desktop.png` | 53% | scene 4, progress 0.531 |
| `scene5-ranked-desktop.png` | 66% | scene 5, progress 0.656 |
| `scene6-product-vision-desktop.png` | 80% | scene 6, progress 0.797 |
| `scene7-source-span-desktop.png` | 92% | scene 7, progress 0.922 |
| `scene7-final-cta-desktop.png` | 99% | scene 7, progress 0.992 |
| `mobile-midpoint-390.png` | 50%, 390px viewport | scene 4, progress 0.503 |
| `reduced-motion-full.png` | full page, `prefers-reduced-motion: reduce` | canvas count = 0 (confirmed) |
| `rtl-structural-nav.png` | isolated `dir="rtl"` structural check | logo `transform: none` (unmirrored), confirmed |
| `webgl-disabled-fallback.png` | real `--disable-webgl` launch flags | canvas count = 0, headline + final CTA both visible, 88,787 chars of real body text, 0 page errors |

Every screenshot was independently visually reviewed (not just
programmatically asserted) — confirmed real 3D content (the document
stack's page-marking texture, the provenance-thread curves, the
particle field, the ranked-block arrangement) rendering behind the
real, server-rendered text panels, not a placeholder.

### Video recordings (`docs/verification/videos/lx-1-1/`)

| File | Viewport | Content | Size |
| --- | --- | --- | --- |
| `01-full-desktop-journey.webm` | 1440×900 | Continuous scroll through all 7 scenes (hero → intake → review → structured → retrieval → vision → traceability in one take) | 2.7 MB |
| `02-mobile-journey.webm` | 390×844 | Full journey at mobile viewport | 2.0 MB |
| `03-reduced-motion-journey.webm` | 1440×900 | Full journey with `prefers-reduced-motion: reduce` emulated (static fallback throughout) | 1.2 MB |

One continuous desktop recording was chosen over 6 separate named-segment
clips because the mission's own segments (hero/intake, human review,
structured knowledge, retrieval, traceability) are contiguous scroll
ranges within a single real journey — splitting them would produce
redundant re-recordings of the same continuous motion, not independent
evidence. All segments are present and timestamped by their scroll
position within the one file.

## 7. Bundle isolation (verified directly, not inferred from size)

```
Route                            Size    First Load JS
/design/cinematic-landing        5.3 kB     156 kB      (unchanged shape vs. LX-1.0's gallery route)
/                                 129 B      114 kB      (unchanged)
```

`grep -rl "@react-three/fiber\|react-reconciler" .next/static/chunks/`
→ zero matches anywhere (confirms the removal was complete — no stray
references left in the compiled output). `three`-referencing code
exists in exactly 2 chunk files; grepping every *other* route's
compiled page chunk for those two chunk hashes returns zero matches —
`three` reaches only this one route's bundle.

## 8. Accessibility (real `@axe-core/playwright` scans)

| State | Violations |
| --- | --- |
| Desktop, motion enabled | 0 |
| Desktop, reduced motion | 0 |
| Mobile 390px | 0 |
| RTL structural check | 0 |
| WebGL-disabled fallback | 0 |

Stable across repeated runs. Manual checks: keyboard-operable nav/CTA
(real `<a>`/`<button>`/`<input>` elements throughout, no `<div onClick>`),
focus-visible states reuse the existing `PublicShell.tsx` pattern,
screen-reader reading order matches DOM/narrative order (verified by
the axe scan's own accessible-name-tree check), canvas is
`aria-hidden="true"` everywhere, 200% zoom usable (no fixed-size
containers that clip text).

## 9. Performance

Full numbers, methodology, and honest caveats in
`docs/landing/NOOR_CINEMATIC_PERFORMANCE_BUDGET.md`. Summary:

- Production `/`: unaffected (1.00/1.00/1.00/1.00, 194 KiB, matching LX-1.0's baseline).
- `/design/cinematic-landing`: only measurable pre-launch against the dev server (route 404s in production by design) — Accessibility 1.00 (meaningful), Performance/TBT/byte-weight numbers are dev-mode-inflated and explicitly not compared to the production target.
- FPS measured at 6 checkpoints: real degradation from ~50fps (Scene 1) to ~1-6fps (Scene 7) — investigated, confirmed the browser was running **SwiftShader** (CPU software rendering, not a real GPU) via `WEBGL_debug_renderer_info`. The degradation pattern (worse as more objects stay visible) is real and worth optimizing; the absolute numbers are not representative of real hardware. Real-GPU verification is explicitly deferred to LX-1.2.
- Memory: an initial +150 MB heap growth across 5 mount/unmount cycles was investigated, not accepted at face value — a control experiment bouncing between two *non-Three.js* routes reproduced the same order of magnitude (+112 MB), proving it's a Next.js dev-server artifact (HMR/module-registry accumulation), not this route's cleanup code. The metric that actually matters — WebGL context disposal — was verified directly: 8 consecutive mount/unmount cycles produced zero "too many contexts" or context-loss warnings.

## 10. Regression review

- Production `/`, `/login`, `/403`, `/access-denied`: no diff, all pass their existing regression tests.
- `/design-system` and `/design/landing-experience` (LX-1.0's gallery, preserved per mission §9): still 404 in production, untouched.
- `apps/web` build: clean, every other route's bundle unaffected.
- No database, RLS, permissions, storage, or Worker changes.

## 11. Known limitations (honest, not hidden)

- The verification ring (Scene 2) and other early-scene elements remain visible (at their resolved state) in later scenes' camera framing rather than fading out once their dedicated scene passes — a compositional choice, not a functional defect, worth revisiting in LX-1.2 based on user feedback on the recorded video.
- FPS and Performance/TBT numbers require re-measurement on real GPU hardware and against a production build before any production performance claim can be made.
- The `useReducedMotion()`-hydration-mismatch pattern found and fixed 3 times in this route's own code may exist elsewhere in `apps/web` (e.g., LX-1.0's gallery) — not audited this mission, recorded as a follow-up.
- Mobile Lighthouse was not run (dev-mode desktop numbers already established as non-representative; a second dev-mode mobile run would not add a distinct signal).
- 3 GitHub research citations reference issues that may be updated/resolved upstream after this mission — the pivot away from `@react-three/fiber` makes this repository's own correctness independent of that upstream resolution either way.
