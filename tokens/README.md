# Clearsky tokens

The UI Kit says: *nothing may use a colour, size, radius, shadow or duration absent from it.*

Before this folder existed, that rule was unenforceable. The Kit is a specimen book — a document
*about* the design system. Nothing in the product could import it, so every value was a hard-coded
literal at every call site: **239 distinct hex colours across twelve pages, zero `var()` usages.**
That is why the `#8FA2BD` sweep silently failed in the app prototype: with no token, changing one
colour meant forty-five find-and-replaces across two syntaxes, and the JS-rendered screens were missed.

This folder is the machine-readable form of the rule.

## The files

| File | What it is |
|---|---|
| `clearsky.tokens.json` | **The source of truth.** Hand-edit only this. |
| `clearsky.tokens.css` | Generated. Custom properties + type helpers. Never hand-edit. |
| `build.mjs` | Generates the CSS from the JSON. |
| `check.mjs` | Enforces the rule against every page. |
| `check.baseline.json` | Accepted debt, so the check is adoptable rather than ignored. |

Values were extracted from `10 UI Kit.dc.html` §06 Colour system, §07 Type scale and
§08 Foundation tokens — 60 ramp steps, 17 semantic colours, 18 type tokens, 9 spacing steps,
10 radii, 7 elevations, 7 motion tokens, 8 z-layers, 5 breakpoints.

## Using it

```bash
node tokens/build.mjs     # regenerate the CSS after editing the JSON
node tokens/check.mjs     # fail on NEW violations only  (what CI runs)
node tokens/check.mjs --report    # full breakdown, never fails — use this to plan a burn-down
node tokens/check.mjs --strict    # fail on every violation — the end state
node tokens/check.mjs --baseline  # re-record accepted debt after a burn-down batch
```

In a page:

```html
<link rel="stylesheet" href="tokens/clearsky.tokens.css">
```

```css
.triage-card {
  background: var(--surface);
  border: 1px solid var(--line-2);
  border-radius: var(--radius-triage);
  box-shadow: var(--elev-e4);
  transition: transform var(--motion-calm) var(--ease-calm);
}
```

Prefer a semantic token (`--ink-2`) over a raw ramp step (`--ink-800`). The ramp is the palette;
the semantic layer is the decision. When a screen needs a colour the semantic layer does not name,
that is a signal the semantic layer is missing a token — add it to the JSON rather than reaching
past it into the ramp.

## The retirement that wasn't

The UI Kit retired `#8FA2BD` as type "at any size" on one measurement: 2.58:1 on white. The
measurement is right; the conclusion was not. That value was simultaneously **the system's only
on-dark ink**, and the Kit has no reversed token to sweep toward. A blanket sweep therefore
regressed **31 passing texts to failing** across three files:

| File | Regressions | Was | Became |
|---|---:|---|---|
| `11 Illustration Index.dc.html` | 27 | 5.40–7.08:1 | 2.75–3.61:1 |
| `08 M06 Private By Design.dc.html` | 3 | 4.71–7.08:1 | 2.40–3.61:1 |
| `02 App Prototype.dc.html` | 1 | 7.08:1 | 3.61:1 |

All 31 reverted. The value is now named for the job it was already doing — `--ink-on-dark` — with
its constraint written down: never on light, correct on dark, and `--ink-3` is wrong there.

**The lesson is about the tool, not the colour.** A checker that reads values and never the ground
behind them cannot catch this class of error. `contrast.mjs` measures instead — but read its header
before trusting a number: it resolves ancestry by indentation, not a DOM, so it informs and does
not gate.

## Two kinds of failure

**Baselined — burn down deliberately.** Everything. The baseline currently records **1541**
accepted violations:

| Kind | Occurrences | Distinct |
|---|---:|---:|
| colour | 961 | 184 |
| radius | 421 | 14 |
| shadow | 130 | 63 |
| duration | 29 | 18 |

CI fails on anything *new*. The existing debt is tracked, visible, and shrinks on purpose.

## What the debt actually looks like

Most of it is near-miss drift, not deliberate divergence — which is exactly what a token layer
prevents:

| Value in use | Times | The token it nearly is |
|---|---:|---|
| `#EEF4FB` | 122 | `--ink-200` `#EEF4FA` — one digit out |
| `#E3EDF8` | 87 | `--line-2` `#E0EBF7` |
| `radius: 99px` | 44 | `--radius-pill` `999px` |
| `radius: 6px` | 99 | not on the scale at all |
| `radius: 10px` | 92 | not on the scale at all |

## Burning it down

Order matters — do the cheap, high-count wins first so the number moves visibly:

1. **Near-miss colours.** The top ~10 values cover a large share of the 961. Each is a one-line
   change in the JSON's favour, not a design decision.
2. **Radii.** 421 occurrences over only 14 distinct values. Map each to the nearest scale step;
   `99px` → `999px` alone clears 44.
3. **Shadows.** 63 distinct for 7 defined elevations. This one needs a designer's eye — several are
   probably genuinely new elevations that belong in the JSON.
4. **Durations.** 18 distinct, 29 occurrences. Smallest job, do it last.

Re-run `--baseline` after each batch and commit the shrinking number.

## The end state

When the baseline reaches zero, delete `check.baseline.json` and switch CI to `--strict`. From then
on the rule in the UI Kit and the behaviour of the codebase cannot drift apart, because the same
file states both.
