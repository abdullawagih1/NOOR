# Accessibility

## Contrast — computed, not asserted

Ratios below were computed directly from the hex values in
`packages/ui/tokens/colors.ts` using the standard WCAG relative-luminance
formula (not eyeballed, not assumed). Recompute with the same formula if any
token value changes — see the note at the bottom.

| Pair | Ratio | AA normal text (4.5:1) | AA large text (3:1) |
|---|---|---|---|
| `ink` on `canvas` (body text) | 16.46:1 | PASS | PASS |
| `body` on `canvas` | 10.36:1 | PASS | PASS |
| `muted` on `canvas` | 4.81:1 | PASS | PASS |
| `primary` on `canvas` (links) | 4.89:1 | PASS | PASS |
| `on-primary` on `primary` (button text) | 4.89:1 | PASS | PASS |
| `primary-active` on `canvas` | 6.66:1 | PASS | PASS |
| `primary-active` on `primary-soft` (active nav item) | 5.80:1 | PASS | PASS |
| **`muted-soft` on `canvas`** | **3.02:1** | **FAIL** | PASS |
| `evidenceInsufficient` fg on bg | 7.02:1 | PASS | PASS |
| `critical` fg on bg | 8.02:1 | PASS | PASS |
| `warning` / `evidencePartial` fg on bg | 6.37:1 | PASS | PASS |
| `aiGenerated` fg on bg | 7.53:1 | PASS | PASS |
| `humanApproved` fg on bg | 8.74:1 | PASS | PASS |
| `informational` / `processing` / `underReview` fg on bg | 7.03:1 | PASS | PASS |

### The one known exception: `muted-soft`

`muted-soft` fails AA-normal-text contrast (3.02:1) against `canvas`. It has
exactly one call site in the codebase today:
`placeholder:text-muted-soft` on `TextInput`/`PasswordInput`/
`ClinicalQuestionBar` — i.e., input placeholder text only, never a label,
never body copy, never a button. Every field using it also renders a real,
always-visible `<label>` (see `TextInput.tsx`), so the placeholder is
supplementary hint text, not the field's only accessible name. This is a
deliberate, scoped exception, not an oversight — but it's still worth
tightening in a future pass if `muted-soft` ever gets a second call site
with actual content (at which point it must not be used, or the token value
needs to move).

## Color is never the only signal

Every `SemanticStatusBadge` renders an icon (`lucide-react`) **and** a text
label **and** an `aria-label` carrying the fuller
`accessibleDescription` — see `docs/design-system/SEMANTIC_STATES.md`. This
was a hard requirement from the Clinical Safety Agent, not a nice-to-have:
a colorblind clinician or a screen-reader user must get the same
"evidence insufficient" signal as anyone else.

## Keyboard and screen-reader specifics

* All interactive primitives (`Button`, `TextInput`, `Select`, `Checkbox`,
  `Radio`, `Tabs`, `Modal`) are native HTML elements or use the correct
  ARIA role (`role="dialog"` + `aria-modal` on `Modal`, `role="tablist"`/
  `"tab"`/`"tabpanel"` on `Tabs`, `role="alert"` on error-toned `Alert`s,
  `role="status"` on info/success ones and `LoadingState`).
* `Modal` closes on `Escape`. Full focus-trap (returning focus to the
  trigger element, cycling Tab within the dialog) is **not** implemented —
  documented gap, Sprint 1 polish.
* Every form field pairs an `<input>`/`<select>`/`<textarea>` with a
  `<label htmlFor>` and, where present, `aria-describedby` pointing at hint
  and error text (`TextInput`, `Textarea`, `Select`).
* Icon-only controls (`IconButton`, `Modal`'s close button, password
  show/hide toggle) always carry `aria-label`.

## RTL

`dir="rtl"` + `lang="ar"` is demonstrated on `/design-system`. The
`font-arabic` Tailwind utility (IBM Plex Sans Arabic via `next/font`) is the
intended stack for Arabic content; no component hardcodes `text-align` or
`margin-left`/`margin-right` in a way that would break under `dir="rtl"` —
Tailwind's logical-property utilities were used where directionality
matters (`gap-*`, flexbox) rather than physical left/right ones. Full RTL
QA of every workspace screen is Sprint 1 scope once real content exists to
lay out.

## How to recompute contrast

```python
def hex_to_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))

def luminance(rgb):
    def channel(c):
        c = c / 255
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = rgb
    return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)

def contrast(hex1, hex2):
    l1, l2 = luminance(hex_to_rgb(hex1)), luminance(hex_to_rgb(hex2))
    lighter, darker = max(l1, l2), min(l1, l2)
    return (lighter + 0.05) / (darker + 0.05)
```
