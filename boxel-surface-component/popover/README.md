# Popover

An anchored floating surface that hosts a focused interaction next to a source
element — it **raises** a focused something out of the source's small footprint
without taking the user away from the source.

This is a standalone, remixable extraction of the `boxel-surface` `Lift`
primitive, decoupled from the rest of the surface runtime so it can be dropped
into any realm on its own.

## Install / remix

No `npm install` step. The only npm import is `@floating-ui/dom`, which the
Boxel host shims as a global virtual module available to **every** realm card —
so a card that remixes this package works in any host-served realm out of the
box. Everything else (`@glimmer/*`, `@ember/*`, `ember-modifier`) is likewise
globally provided.

Import from the package index:

```js
import { Popover, type PopoverKind } from './popover/index.ts';
```

## The axes — orthogonal by design

Each dial does exactly one thing and reads only its own value (no dial silently
changes another), so you can mix any combination predictably:

| Axis | Values | Default | Controls |
| --- | --- | --- | --- |
| `kind` | `details` · `preview` · `edit` · `tools` | (required) | semantic + behavior (role, autofocus, focus-trap, keyboard) + which body the host yields |
| `anchoring` | `beside` · `overlay` · `center` | `beside` | **position only** — where it sits relative to the anchor |
| `size` | `compact` · `comfortable` · `spacious` · `auto` | `comfortable` | min/max width + height |
| `backdrop` | `none` · `tint` · `blur` · `dim` | `none` | the surface material (see below) |
| `elevation` | `flat` · `raised` · `elevated` · `floating` | `raised` | shadow depth + corner radius |

Plus `keyboardModel` (`pick` · `edit`) — doesn't
paint; it threads through to the body so inner picker primitives route keys.

**`kind` is a behavior preset, not a look.** It sets the ARIA role, whether the
popover autofocuses, whether it traps focus (`edit`), and how keys route — never
the visual dials. So changing `kind` won't move `size`/`backdrop`/`elevation`;
set those yourself when you want them.

**`backdrop` is the surface material** (the alpha is the difference):

- `none` — opaque solid card.
- `tint` — ~80% opaque, the page tints through.
- `blur` — ~55% opaque + `backdrop-filter` → frosted glass.
- `dim` — opaque card **plus** a full-page dim/blur overlay behind it (a separate
  element). Pair with `anchoring='center'` for a classic modal.

## Calling convention

The host owns **what** (open/close state, kind state, the body content); the
Popover owns **how** (positioning, dismissal on Esc / outside-click, focus
enter/restore, the per-kind chrome, the optional dim overlay).

```gjs
{{#if this.openKind}}
  <Popover
    @anchor='[data-popover-anchor=my-field]'
    @open={{true}}
    @kind={{this.openKind}}
    @canEscalateTo={{this.escalation}}
    @onEscalate={{this.escalate}}
    @onDismiss={{this.dismiss}}
    as |kind|
  >
    {{#if (eq kind 'details')}}
      …read-only content…
    {{else if (eq kind 'edit')}}
      …editor content…
    {{/if}}
  </Popover>
{{/if}}
```

`@anchor` is a CSS selector that resolves the source element. When
`@canEscalateTo` lists kinds other than the current `@kind`, a single compact
corner glyph appears (✎ / ⓘ / ⊡ / ⋯); clicking it fires `@onEscalate`. Single-
kind contracts get no chrome — the body is the whole popover.

See [`example/popover-playground-example.gts`](./example/popover-playground-example.gts)
for a runnable config explorer: every axis as a `BoxelSelect`, with a live
preview + generated code that reflect your selections.

## Recipes

`eq` is from `@cardstack/boxel-ui/helpers`.

### The four kinds

`@kind` drives behavior (role / autofocus / focus-trap / keyboard) and which body
the host yields — not the look.

```gjs
{{! details — passive read-only peek (role=tooltip, no autofocus) }}
<Popover @anchor='[data-anchor=a]' @open={{true}} @kind='details' @onDismiss={{this.close}}>
  <div class='pad'>Read-only summary…</div>
</Popover>

{{! preview — a richer read-only snapshot }}
<Popover @anchor='[data-anchor=a]' @open={{true}} @kind='preview' @onDismiss={{this.close}}>
  <img src={{this.thumb}} alt='' />
</Popover>

{{! edit — focus-trapped editor (modal by default, keyboard-delegated) }}
<Popover @anchor='[data-anchor=a]' @open={{true}} @kind='edit' @keyboardModel='edit' @onDismiss={{this.cancel}}>
  <input autofocus value={{this.value}} {{on 'input' this.update}} />
</Popover>

{{! tools — action menu (keyboard-delegated) }}
<Popover @anchor='[data-anchor=a]' @open={{true}} @kind='tools' @keyboardModel='pick' @onDismiss={{this.close}}>
  <ul role='menu'>
    <li><button {{on 'click' this.rename}}>Rename</button></li>
    <li><button {{on 'click' this.delete}}>Delete</button></li>
  </ul>
</Popover>
```

### Anchoring (position only)

```gjs
{{! beside (default) — floats next to the anchor; flips/shifts at viewport edges }}
<Popover @anchor='[data-anchor=a]' @open={{true}} @kind='edit'
  @anchoring='beside' @placement='top-end' as |kind|>…</Popover>

{{! overlay — sits on top of the anchor's own box ("the cell grew") }}
<Popover @anchor='[data-anchor=a]' @open={{true}} @kind='edit'
  @anchoring='overlay' @size='auto' as |kind|>…</Popover>

{{! center — centered in the viewport. Pair with backdrop='dim' for a modal }}
<Popover @anchor='[data-anchor=a]' @open={{true}} @kind='edit'
  @anchoring='center' @backdrop='dim' @onDismiss={{this.close}} as |kind|>
  <div class='pad'>A centered modal dialog…</div>
</Popover>
```

For `beside`, positioning is handled by [Floating UI](https://floating-ui.com)
and is robust out of the box — you only set the side, not the math:

- `@placement` — preferred side (any Floating UI `Placement`, default
  `'bottom-start'`).
- `@offset` — gap in px between anchor and popover (default `8`).

Automatic behavior (no config): **flip** to the opposite/perpendicular side when
the preferred side doesn't fit, **shift** back into view while staying tethered
to the anchor (`limitShift`), **size** down to the height actually available
(then scroll), and **hide** when the anchor is scrolled out of view. Position
follows the anchor on scroll, resize, and layout shifts.

### Visual dials (independent)

```gjs
<Popover
  @anchor='[data-anchor=a]'
  @open={{true}}
  @kind='edit'
  @size='spacious'
  @backdrop='blur'
  @elevation='elevated'
  @onDismiss={{this.close}}
  as |kind|
>
  <div class='formula-builder'>…</div>
</Popover>
```

- `@size` — `compact` · `comfortable` · `spacious` · `auto`
- `@backdrop` — `none` · `tint` · `blur` · `dim`
- `@elevation` — `flat` · `raised` · `elevated` · `floating`

### Accessibility

The popover root gets an ARIA `role` automatically: `details` → `tooltip`, every
other kind → `dialog`. The `edit` kind is **modal** — it traps focus and sets
`aria-modal="true"` (independent of position: a centered popover is not modal
unless its kind is `edit`).

- `@role` — override the role (e.g. `'menu'` for an action list).
- `@label` — accessible name (sets `aria-label`).
- `@labelledby` / `@describedby` — point at ids of a heading / description element
  in the body.

The host still owns the **trigger**'s ARIA (`aria-haspopup` / `aria-expanded` /
`aria-controls`) since the popover doesn't mutate the anchor element.

### Escalation chain (details → edit → tools)

List the kinds in `@canEscalateTo`; a single corner glyph appears for any kind
other than the current one, and clicking it fires `@onEscalate`.

```gjs
{{! this.kind is tracked ('details' | 'edit' | 'tools');
    setKind is (next) => (this.kind = next) }}
<Popover
  @anchor='[data-anchor=a]'
  @open={{true}}
  @kind={{this.kind}}
  @canEscalateTo={{array 'details' 'edit' 'tools'}}
  @onEscalate={{this.setKind}}
  @onDismiss={{this.close}}
  as |kind|
>
  {{#if (eq kind 'details')}}…{{else if (eq kind 'edit')}}…{{else}}…{{/if}}
</Popover>
```

### Gesture binding for grids/canvases

`PopoverState` (a hover-pause / dismiss-grace state machine) + the
`surfacePopoverBinding` modifier let many units share one popover: hover a unit
to peek `details`, dblclick to `edit`.

```gjs
import { Popover, createPopoverState, surfacePopoverBinding } from '../index.ts';

class GridIsolated extends Component<typeof Grid> {
  popovers = createPopoverState({
    anchorSelectorFor: (r, c) => `[data-row="${r}"][data-col="${c}"]`,
  });
  cellContract = { popover: ['details', 'edit'] };
  selectCell = (r, c) => {/* host focus model */};

  <template>
    {{#each this.rows as |row r|}}
      {{#each row as |cell c|}}
        <div data-row={{r}} data-col={{c}}
          {{surfacePopoverBinding state=this.popovers contract=this.cellContract
            row=r col=c onSelect=this.selectCell}}>
          {{cell.label}}
        </div>
      {{/each}}
    {{/each}}

    {{#if this.popovers.isOpen}}
      <Popover
        @anchor={{this.popovers.anchorSelector}}
        @open={{true}}
        @kind={{this.popovers.kind}}
        @onDismiss={{this.popovers.close}}
        {{on 'pointerenter' this.popovers.cancelDismiss}}
        {{on 'pointerleave' this.popovers.scheduleDismissDetails}}
        as |kind|
      >
        {{#if (eq kind 'details')}}…{{else if (eq kind 'edit')}}…{{/if}}
      </Popover>
    {{/if}}
  </template>
}
```

`PopoverState` cheatsheet: `openDetails(r,c)` · `openEdit(r,c)` · `openTools(r,c)`
· `openPopover(r,c,kind)` · `escalate(kind)` · `close()` · reactive getters
`isOpen` / `kind` / `anchorSelector` / `isOpenFor(r,c)`. Tune timing via
`createPopoverState({ hoverPauseMs, dismissGraceMs, dismissCooldownMs })`.

For a single trigger you don't need any of this — just wire `{{on 'mouseenter'}}`
/ `{{on 'click'}}` on your own element to toggle the `@open` boolean.

## What's in the package

| Path | Role |
| --- | --- |
| `components/popover.gts` | the `<Popover>` component + all chrome |
| `modifiers/popover-binding.ts` | `surfacePopoverBinding` — wires hover/click gestures to `PopoverState` |
| `utils/popover-state.ts` | `PopoverState` — per-host open/hover/dismiss state machine |
| `utils/layer-manager.ts` | dynamic z-index allocator for stacked surfaces |

To theme the popover, set the `--bx-popover-*` CSS custom properties
(`--bx-popover-accent`, `--bx-popover-bg`, `--bx-popover-shadow-*`, the
`--bx-popover-size-*` tokens, …) at `:root` or via a realm theme — that is the
Boxel-idiomatic extension point, and it works regardless of the `document.body`
portal.

## Relationship to boxel-surface

This package is a decoupled copy of `boxel-surface`'s `Lift`. The heavier
optional integration with the surface runtime (focus-ladder, surface-runtime,
declarative lift edges) is intentionally **not** included. If you need full
focus-ladder integration, consume `Lift` from `boxel-surface` directly instead.
