# boxel-surface

Surface layer primitives used by the catalog demo cards.
Import from `../boxel-surface/index` (relative path — no `@cardstack` prefix).

```ts
import { Environment, Layout, Grid, Row, Cell, Run, Unit, Pane } from '../boxel-surface/index';
```

---

## Layer overview

| Layer | Components | Job |
|---|---|---|
| **Structure** | `Environment` `Layout` `Pane` | Nesting context, page container, side panel |
| **Data** | `Grid` `Row` `Cell` `Run` `Unit` | Tabular data with focus/selection |
| **Form** | `Form` `FormSection` `FormField` | Structured editing chrome |
| **Typed cells** | `TextCell` `EmailCell` `NumberCell` `SwitchCell` | Editable value slots |
| **Lift** | `Lift` `LiftChevron` | Floating overlays anchored to a cell |
| **Modifier** | `multiUnit` | Per-chip selection inside one cell |
| **Focus** | `FocusLadder` `createFocusLadder` | Who has attention right now |

---

## Structure layer

### `Environment`

Root context provider. Nothing works without it.
<!-- Without Environment
Environment does three things on mount:

Creates the SurfaceRuntime and FocusLadder
Provides them to all descendants via Glimmer context (@provide)
Installs the surfaceRoot modifier on its host element (keyboard routing, background-click-clear, tabindex)
Without it, every child component (Grid, Row, Cell, etc.) calls @consume(LadderContextName) and gets back undefined. Looking at the surfaceNode modifier:


const owningLadder = ladder ?? ladderForSurfaceElement(element);
if (!owningLadder || !opts.id || !opts.surface) return false;  // ← silently bails
It just returns false — no registration happens, no error thrown. The component renders its DOM fine, but:

No surface node is registered in the ladder
No keyboard navigation (Tab/Arrow keys do nothing)
No click-to-select
No focus path tracking
No @posture cascade
Lift will fail to find an anchor since the DOM root isn't marked -->


| Arg | Type | Notes |
|---|---|---|
| `@space` | `string \| object` | Identity anchor. Pass `@model` from a CardDef so each card instance is independent. |
| `@posture` | `'use' \| 'compose'` | Cascade signal broadcast to all children. `use` = interacting, `compose` = editing the layout. |
| `@ladder` | `FocusLadder` | Bring your own ladder (needed when subscribing externally). |
| `@keyboard` | `boolean \| 'surface-tree' \| 'manual' \| 'none'` | Keyboard navigation model. |

### `Layout`

Page container inside an Environment. Handles outer chrome (padding, border-radius, overflow).
No notable args beyond standard HTML attributes.

### `Pane`

Independent side-panel region inside a Layout. Floats alongside Grid content without joining the column structure.
No notable args beyond standard HTML attributes.

---

## Data layer

### `Grid`

Tabular host — gives rows and cells keyboard/selection semantics.
No notable args beyond standard HTML attributes + `role`.

### `Row`

One record in a Grid.

| Arg | Type | Notes |
|---|---|---|
| `@space` | `string` | Stable identity across re-sorts. Pass the record's id. |

### `Cell`

One value slot inside a Row.

| Arg | Type | Notes |
|---|---|---|
| `@key` | `string` | Column identity — required for correct focus tracking. |
| `@surface` | `'form' \| 'grid' \| 'canvas' \| 'scene'` | Override chrome skin (usually auto-detected). |
| `@state` | `'none' \| 'valid' \| 'invalid' \| 'loading' \| 'initial'` | Validation ring colour. |
| `@readonly` | `boolean` | Blocks edit interactions. |
| `@disabled` | `boolean` | Blocks + grays out. |
| `@chained` | `boolean` | Drops the outer border so adjacent cells visually merge. |

### `Run`

Inline prose / text value inside a Cell. Use for labels, names, any string that reads as content.

| Arg | Type | Notes |
|---|---|---|
| `@key` | `string` | Optional stable identity when multiple Runs share a Cell. |

### `Unit`

Typed leaf value inside a Cell — for non-prose data: a status dot, a checkbox, a badge.
Semantically "this is a value, not prose".

| Arg | Type | Notes |
|---|---|---|
| `@key` | `string` | Optional stable identity. |

---

## Form layer

### `Form`

Wraps a set of fields. `@mode` broadcasts read-only vs editable to all children.

| Arg | Type | Notes |
|---|---|---|
| `@mode` | `'edit' \| 'view' \| 'create'` | Default `'edit'`. All child cells switch accordingly. |
| `@layout` | `'vertical' \| 'horizontal'` | Label above or beside the field. |
| `@density` | `'comfortable' \| 'compact'` | Field spacing. |
| `@variant` | `'standalone' \| 'embedded'` | `standalone` → `<form>` tag; `embedded` → `<fieldset>`. |
| `@columns` | `1 \| 2 \| 3` | Field grid column count. |

### `FormSection`

Collapsible group of fields with a heading.

| Arg | Type | Notes |
|---|---|---|
| `@heading` | `string` | Section title. Required. |
| `@collapsible` | `boolean` | Shows a collapse toggle. |
| `@defaultOpen` | `boolean` | Initial open state when collapsible. Default `true`. |

### `FormField`

Label + value slot pair. Put a typed cell in the default block.

| Arg | Type | Notes |
|---|---|---|
| `@label` | `string` | Required. |
| `@state` | `'none' \| 'valid' \| 'invalid' \| 'loading' \| 'initial'` | Validation ring. |
| `@readonly` | `boolean` | Switches label chrome to read-only style. |
| `@required` | `boolean` | Adds required indicator. |
| `@helperText` | `string` | Small hint below the field. |
| `@errorMessage` | `string` | Shown when `@state='invalid'`. |

---

## Typed cells

### `TextCell`

| Arg | Type |
|---|---|
| `@value` | `string` |
| `@readonly` | `boolean` |
| `@disabled` | `boolean` |
| `@placeholder` | `string` |
| `@type` | `'text' \| 'tel' \| 'url' \| 'search'` |
| `@multiline` | `boolean` |
| `@prefix` / `@suffix` | `string` |
| `@onInput` | `(value: string) => void` |

### `EmailCell`

| Arg | Type |
|---|---|
| `@value` | `string` |
| `@readonly` | `boolean` |
| `@disabled` | `boolean` |
| `@placeholder` | `string` |
| `@onInput` | `(value: string) => void` |

### `NumberCell`

| Arg | Type |
|---|---|
| `@value` | `number \| string` |
| `@readonly` | `boolean` |
| `@disabled` | `boolean` |
| `@placeholder` | `string` |
| `@min` / `@max` | `number` |
| `@step` | `number \| string` |
| `@prefix` / `@suffix` | `string` |
| `@onInput` | `(value: string) => void` |

### `SwitchCell`

| Arg | Type |
|---|---|
| `@label` | `string` (required) |
| `@value` | `boolean` |
| `@disabled` | `boolean` |
| `@description` | `string` |
| `@onChange` | `(value: boolean) => void` |

---

## Lift layer

### `Lift`

Floating surface anchored to a source element via CSS selector. Yields `kind` to the block — switch on it to render different bodies.

```hbs
<Lift
  @anchor='[data-lift-anchor=my-cell]'
  @open={{this.isOpen}}
  @kind={{this.kind}}
  @canEscalateTo={{this.allKinds}}
  @onEscalate={{this.escalate}}
  @onDismiss={{this.dismiss}}
  as |kind|
>
  {{#if (eq kind 'details')}}…{{/if}}
  {{#if (eq kind 'edit')}}…{{/if}}
</Lift>
```

| Arg | Type | Notes |
|---|---|---|
| `@anchor` | `string` (CSS selector) | Target element. Use a unique `data-lift-anchor` attribute. Required. |
| `@open` | `boolean` | Mount / unmount. Required. |
| `@kind` | `'details' \| 'preview' \| 'edit' \| 'tools'` | Chrome variant. Yielded back to block. Required. |
| `@canEscalateTo` | `LiftKind[]` | Kinds shown in the escalation toolbar. Empty = no toolbar. |
| `@onEscalate` | `(next: LiftKind) => void` | User clicked an escalation chip. |
| `@onDismiss` | `() => void` | Esc or outside-click. Set `@open=false` here. |
| `@placementMode` | `'attached' \| 'shadow' \| 'plane'` | Geometric strategy. Default `'attached'`. |
| `@size` | `'compact' \| 'comfortable' \| 'spacious' \| 'auto'` | Width/height preset. |
| `@backdrop` | `'none' \| 'tint' \| 'blur' \| 'scrim'` | Background treatment. |
| `@elevation` | `'flat' \| 'raised' \| 'elevated' \| 'modal'` | Shadow / z-index tier. |
| `@autoFocus` | `boolean` | Move DOM focus into lift on open. Default `true` except `details`. |

**Four kinds:**

| Kind | Opens on | Closes on | Use for |
|---|---|---|---|
| `details` | hover | cursor leave | Read-only peek, full value + context |
| `preview` | click / pin | click outside | Richer read view, stays open |
| `edit` | click | Enter / Esc | In-place editing, focus-trapped |
| `tools` | click | action runs / click outside | Full action menu (5+ actions) |

### `LiftChevron`

Small ▾ affordance placed inside a Cell. Signals "this cell has a lift" and serves as the click target.

---

## Modifier layer

### `multiUnit`

Put on a Cell that contains several chips/values. Scans for `[data-unit-key]` children and registers each as an individually focusable unit.

```hbs
<Cell
  @key='tags'
  data-ladder-id={{this.cellId}}
  {{multiUnit this.ladder this.cellId}}
>
  {{#each this.tags as |tag|}}
    <span class='chip' data-unit-key={{tag}}>{{tag}}</span>
  {{/each}}
</Cell>
```

- Click a chip → selects that chip
- Click between chips → selects the whole cell (the group)
- Re-renders with stable `data-unit-key` values preserve selection

---

## Focus layer

### `createFocusLadder` / `FocusLadder`

```ts
ladder = createFocusLadder();

// subscribe to focus/selection changes
this.unsub = this.ladder.subscribe(() => {
  this.focused  = this.ladder.focusedId;
  const path = this.ladder.focusPath;
  const last = path[path.length - 1];
  this.selected = last && this.ladder.isSelected(last) ? last : null;
});
```

Pass the ladder to `Environment` via `@ladder` and to `multiUnit` as the first argument.

---

## Demo cards

| Card | File | Surfaces demonstrated |
|---|---|---|
| Team Roster | `../team-roster/team-roster.gts` | `Environment` `Layout` `Grid` `Row` `Cell` `Run` `Unit` `Pane` |
| Employee Profile | `../employee-profile/employee-profile.gts` | `Form` `FormSection` `FormField` `TextCell` `EmailCell` `SwitchCell` |
| Todo List | `../todo-list/todo-list.gts` | Inline edit pattern — `Unit` checkbox, `Run` double-click edit |
| Budget Metrics | `../budget-metrics/budget-metrics.gts` | `Lift` — hover for `details`, click for `edit` |
| People Tags | `../people-tags/people-tags.gts` | `multiUnit` — per-chip selection, add/remove chips |
