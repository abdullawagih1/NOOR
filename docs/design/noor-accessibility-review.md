# NOOR Accessibility Review (UX-1)

Scope: the brand-color refresh's impact on accessibility. This is a
targeted review of what UX-1 changed, not a full first-time audit of
the whole application — see Known Limitations below for what remains
unverified.

## Contrast — every fg/bg pairing UX-1 introduced or changed

Computed with the WCAG 2.2 relative-luminance formula
(`(L1+0.05)/(L2+0.05)`), not eyeballed. Full derivation in
`docs/design/noor-color-system.md`.

| Pairing | Ratio | WCAG AA (text, 4.5:1) | WCAG AA (non-text, 3:1) |
|---|---|---|---|
| `primary` (Clinical Blue `#045092`) on white | 8.18:1 | Pass | Pass |
| White on `primary` | 8.18:1 | Pass | Pass |
| `primary-active` (`#05447B`) on white | 9.91:1 | Pass | Pass |
| `ink` (Deep Navy `#032855`) on white | 14.60:1 | Pass | Pass |
| `accent` (Primary Teal `#078A88`) on white | 4.20:1 | **Fail — never used as text on white** | Pass |
| `accent-active` (teal-700 `#085D5E`) on white | 7.67:1 | Pass | Pass |
| `verified`/`humanApproved` fg (emerald-700/800) on their bg | 5.21–7.49:1 | Pass | Pass |
| `informational`/`processing`/`underReview` fg (blue-700) on their bg | 11.95:1 | Pass | Pass |
| `queued` fg/bg | 6.59:1 | Pass | Pass |
| `retryScheduled` fg/bg | 5.98:1 | Pass | Pass |
| `ocrRequired` fg/bg | 8.07:1 | Pass | Pass |
| `reprocessingRequired` fg/bg | 7.78:1 | Pass | Pass |
| `deadLettered` fg/bg | 11.23:1 | Pass | Pass |

**The one real constraint this enforces**: Primary Teal's 500 anchor
(`#078A88`) fails the 4.5:1 text threshold on white (it clears only the
3:1 non-text threshold), so it is used only for borders, icons, and the
focus-visible outline — never as the color of text sitting directly on
a white/light surface. Anywhere teal needs to be legible as text (e.g.
`WorkspaceNav`'s active item label), the darker `accent-active`
(`#085D5E`, 7.67:1) is used instead. This was verified by grep: no
component sets `text-accent` (only `border-accent`/`outline-accent`/
`bg-accent`); the active-nav label specifically uses `text-accent-active`.

## Color is never the only signal

Unchanged principle, still true after the refresh: every
`SemanticStatusBadge` (including all five new states) renders an icon
and a text label alongside its color, and exposes
`accessibleDescription` via `aria-label` regardless of any
`labelOverride` — verified by reading `packages/ui/components/Badge.tsx`
and every status-mapping file, not assumed.

## Keyboard and focus

- Every interactive shared component (`Button`, `IconButton`,
  `Checkbox`, `Radio`, `Select`, `TextInput`, `Textarea`) has a visible
  `focus-visible`/`focus` outline using the new `accent` (teal) color —
  a single consistent focus color across the whole app, which is itself
  an accessibility improvement over the prior state (focus rings
  previously reused `primary`, the same color as ordinary buttons,
  making "this is focused" and "this is a primary action" harder to
  tell apart at a glance).
- No new custom keyboard trap or custom focus-management code was
  introduced — the shell/logo/badge changes are presentational only.

## Labels and descriptions

- The `noor-logo-navigation.png`/`noor-logo-primary.png`/`noor-symbol*`
  images all carry a real `alt` text ("Noor — Clinical Intelligence" /
  "Noor navigation lockup" / "Noor symbol"), not an empty string, since
  each is the primary way a screen-reader user identifies the product
  on that page.
- The login page regained an explicit `<h1>Sign in</h1>` after the logo
  was added (removing the old `PageHeader` would otherwise have deleted
  the page's only heading — caught by review, not by automated tooling).

## Reduced motion

No new animation was introduced. The one pre-existing motion pattern
(`SemanticStatusBadge`'s spin on the `loader` icon) is already gated by
`motion-safe:` and untouched by this sprint.

## RTL

No RTL-specific class or layout changed in this sprint — the brand
refresh is a color/asset change, not a layout change. The existing
`dir="rtl"` / `font-arabic` mechanism (`app/design-system/page.tsx`'s
"RTL / LTR" section) is unmodified and continues to apply the same
token set in both directions, since the tokens are direction-agnostic
CSS custom properties.

## Known limitations (honest account)

- **No automated accessibility tooling (axe, Lighthouse CI, or
  equivalent) is wired into this repository** — every contrast ratio
  above was computed programmatically from the actual hex values
  (not guessed), but no automated DOM-level a11y scan of the rendered
  pages was run, consistent with `KNOWN_LIMITATIONS.md`'s existing,
  broader gap (item 24: no Playwright/browser-driven E2E exists in this
  repository at all).
- Favicon/app-icon legibility at 16–32px is genuinely poor for the
  network-graphic detail (expected — see
  `docs/brand/noor-logo-usage.md`'s favicon note). This is a fidelity
  trade-off (never redraw the mark) that was explicitly accepted, not
  missed.
- No screen-reader was actually run against the changed pages in this
  session — the `aria-label`/`alt` text claims above were verified by
  reading the rendered markup/props, not by listening to NVDA/VoiceOver
  output.
