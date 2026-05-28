# Planned `@cardstack/surfaces/thimble`

Design note for default ("thimble") implementations of headless surface primitives, built on
[`@cardstack/boxel-ui`](https://github.com/cardstack/boxel) plus
surfaces-native components for anything boxel-ui doesn't cover.

This entrypoint is not exported by the current package yet. Import production
code from `@cardstack/surfaces` until the thimble package exists.

## What "thimble" means here

A thimble is a thin, opinionated cap over a headless primitive — the smallest
amount of styled UI you'd put on top of a surface to make it usable as-is
without authoring your own. React-aria → react-spectrum is the same split:
react-aria gives you headless logic, react-spectrum gives you Adobe's themed
implementation.

## Dependency direction

Surfaces declares boxel-ui as an **optional peer dependency**. Apps that don't
use the thimble pay nothing — boxel-ui isn't pulled into their bundle. Apps
that use the future thimble would import from `@cardstack/surfaces/thimble`.

```ts
// Headless only, no boxel-ui needed:
import { Environment, Layout, Grid } from '@cardstack/surfaces';

// Proposed thimble entrypoint: pre-themed, boxel-ui-backed:
import { Environment, Layout, Grid } from '@cardstack/surfaces/thimble';
```

## Roster

Two-tier: **wrapped boxel-ui primitives** + **net-new components**.

### Wrapped boxel-ui (where it fits)

| Surface primitive | boxel-ui underneath |
|---|---|
| `Cell` (text edit) | `Input` |
| `Cell` (select) | `Select`, `Dropdown` |
| `Cell` (boolean) | `Switch`, `Checkbox` |
| `Cell` (date) | `DateRangePicker` |
| `Cell` (color) | `ColorPicker` |
| `Pane` | `Container`, `CardContainer` |
| `Lift` (modal) | `Modal` |
| `Lift` (tooltip) | `Tooltip` |
| `Outline` accordion | `Accordion` |
| `Cue` chips | `Pill`, `Tag` |
| `Cue` status | `Alert`, `Message` |

### Net-new (boxel-ui doesn't cover, build here)

- Grid sortable/filterable header chrome (uses `SortDropdown` + `FilterList`)
- Canvas frame chrome with multi-select handles
- Plane annotation pins
- Lift escalation toolbar (details → edit → tools)
- Outline document blocks (heading / list / quote / code)
- Multi-unit cell chrome (chip composer, mention picker)
- Coordinate-debugger inspector panel chrome

## Theming

Theme = a CSS custom-property bundle. Default thimble CSS reads
`--foreground`, `--primary`, `--accent`, `--surface`, etc. — falling back to
boxel-ui's `--boxel-*` tokens.

Note: per project guidance, **default `--primary` to `--foreground`** (boxel
dark) rather than boxel's `--boxel-teal`, which is too light for surfaces
chrome at small sizes.

Themes ship in `src/themes/`:
- `boxel.css` — default
- `linear.css`
- `notion.css`
- `figma.css`
- `spotify.css`

Apply per-page by attaching `data-surfaces-theme="spotify"` to any ancestor.
