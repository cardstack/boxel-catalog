# Popover

An anchored floating surface that hosts a focused interaction next to a source
element — it **raises** a focused something out of the source's small footprint
without taking the user away from the source.

This is a standalone, remixable extraction of the `boxel-surface` `Lift`
primitive, decoupled from the rest of the surface runtime so it can be dropped
into any realm on its own.

> Want to feel the API before reading it? Open
> [`example/popover-playground-example.gts`](./example/popover-playground-example.gts) —
> a runnable config explorer that exposes every arg as a control, with a live
> preview and a generated invocation that update together. The sections of this
> README mirror the sections of that playground.

## Install / remix

No `npm install` step. The only npm import is `@floating-ui/dom`, which the
Boxel host shims as a global virtual module available to **every** realm card —
so a card that remixes this package works in any host-served realm out of the
box. Everything else (`@glimmer/*`, `@ember/*`, `ember-modifier`) is likewise
globally provided.

```js
import Popover from './popover/popover.gts';
import type { PopoverKind } from './popover/utils/popover-types.ts';
```

## Calling convention

The host owns **what** (open/close state, which `kind` is showing, the body
content). The Popover owns **how** (positioning, dismissal on Esc /
outside-click, focus enter/restore, the per-kind chrome, the optional dim
overlay).

The default block yields the resolved `kind`, so you render the right body for
whichever kind is open:

```gjs
import Popover from './popover/popover.gts';
import { eq } from '@cardstack/boxel-ui/helpers';

{{#if this.open}}
  <Popover
    @anchor='[data-anchor=priority-cell]'
    @open={{true}}
    @kind={{this.kind}}
    @onDismiss={{this.close}}
    as |kind|
  >
    {{#if (eq kind 'edit')}}
      …editor body…
    {{else if (eq kind 'tools')}}
      …action menu…
    {{else}}
      …read-only details…
    {{/if}}
  </Popover>
{{/if}}
```

`@anchor` is a CSS selector that resolves the source element; the popover reads
its bounding box to position itself. `@open` mounts/unmounts the popover — the
host flips it. The popover never closes itself: on Esc / outside-click it calls
`@onDismiss`, and the host sets `@open={{false}}`.

## Appearance

Five orthogonal dials. Each reads only its own arg and paints exactly one thing,
so any combination is predictable — set one and nothing else moves.

| Arg | Values | Default | Controls |
| --- | --- | --- | --- |
| `@kind` | `details` · `edit` · `tools` | **required** | ARIA role + autofocus default + CSS theme |
| `@anchoring` | `beside` · `overlay` · `center` | `beside` | **position only** — where it sits vs the anchor |
| `@size` | `compact` · `comfortable` · `spacious` · `auto` | `compact` | min/max width + height |
| `@backdrop` | `none` · `tint` · `blur` · `dim` | `none` | the surface material |
| `@elevation` | `flat` · `raised` · `elevated` · `floating` | `raised` | shadow depth + corner radius |

**`@kind` sets semantics + theme, not layout or keyboard.** It only drives the
ARIA role, the autofocus default, and the CSS colour theme — `details` is a
muted tooltip, `edit` is the yellow editor surface, `tools` is the dark action
menu. It never touches `size` / `backdrop` / `elevation` / keyboard behaviour.

**`@backdrop` is the surface material** (the alpha is the difference):

- `none` — opaque solid card.
- `tint` — ~80% opaque, the page tints through.
- `blur` — ~55% opaque + `backdrop-filter` → frosted glass.
- `dim` — opaque card **plus** a full-page dim/blur overlay behind it (a separate
  element). Pair with `@anchoring='center'` for a classic modal.

## Positioning & behavior

These apply to **`beside`** anchoring only (positioned by
[Floating UI](https://floating-ui.com) — you set the side, not the math):

| Arg | Default | Controls |
| --- | --- | --- |
| `@placement` | `bottom` | preferred side + alignment (any Floating UI `Placement`, e.g. `top-end`) |
| `@offset` | `8` | gap in px between the anchor edge and the popover |
| `@arrow` | `false` | show a small caret pointing back at the anchor |

Automatic, no config: **flip** to the opposite side when the preferred one
doesn't fit, **shift** back into view while staying tethered to the anchor,
**size** down to the height actually available (then scroll), and **hide** when
the anchor scrolls out of view. Position follows the anchor on scroll, resize,
and surrounding layout shifts.

`@anchoring` chooses the mounting strategy:

- `beside` — floats next to the anchor (the args above apply).
- `overlay` — sits on top of the anchor's own box ("the cell grew"); pair with
  `@size='auto'` to inherit the anchor width.
- `center` — centered in the viewport; pair with `@backdrop='dim'` for a modal.

## Focus, keyboard & ARIA

| Arg | Default | Controls |
| --- | --- | --- |
| `@autoFocus` | _omit_ → per-kind | move DOM focus into the popover on open |
| `@keyboardModel` | _omit_ | delegate keys into the body: `'pick'` or `'edit'` |
| `@trapFocus` | `false` | trap Tab inside the popover (`aria-modal`) |
| `@focusToken` | _omit_ | stable per-open key so autofocus fires once, not on every re-render |
| `@role` / `@label` / `@labelledby` / `@describedby` | derived / _omit_ | ARIA overrides |

**`@autoFocus` has three states — omitting it is NOT the same as `false`:**

- **omit** → the component decides by kind: `edit` / `tools` focus on open,
  `details` does not.
- **`true`** → always focus on open.
- **`false`** → never focus on open.

So pass `@autoFocus` only when you want to override the per-kind default. (The
playground models this with a `default / on / off` control rather than a boolean
toggle, for exactly this reason.)

**`@keyboardModel` decides the focus target + reroutes keystrokes.** It does not
focus on open by itself (that's `@autoFocus`); it (1) chooses which element is
the focus target — `'pick'` → a `[role=listbox]`, `'edit'` → the editor input —
and (2) while focus is still on the host, the first relevant keystroke is
delegated into that target. Omit it to leave key handling entirely to the host.

**`@trapFocus` is independent of `kind`.** Turn it on for editor popovers that
should own the full Tab cycle; it also sets `aria-modal="true"`. A centered
popover is **not** automatically modal — modality follows `@trapFocus`, not
position or kind.

ARIA role is derived automatically (`details` → `tooltip`, every other kind →
`dialog`); override with `@role` (e.g. `'menu'`). The host still owns the
**trigger**'s ARIA (`aria-haspopup` / `aria-expanded` / `aria-controls`), since
the popover doesn't mutate the anchor element.

## Escalation

List the kinds a user may switch to in `@canEscalateTo` and wire `@onEscalate`.
A single compact glyph appears in the top-right corner; clicking it fires
`@onEscalate(nextKind)` and the host updates `@kind`. Single-kind contracts get
no chrome — the body is the whole popover.

**The glyph always depicts the _destination_ kind**, so it never lies about what
the click does:

| Glyph | Destination |
| --- | --- |
| `✎` | `edit` |
| `ⓘ` | `details` |
| `⋯` | `tools` |

When more than one kind is offered, the highest-priority one wins —
`edit` › `tools` › `details` (lifting a passive surface to an editor is the most
common escalation). Because `edit` is filtered out when you're already in the
edit view, the pencil never shows there. Glyph, aria-label, and click action all
derive from one resolver, so they can never disagree.

```gjs
{{! this.kind is tracked; setKind = (next) => (this.kind = next) }}
<Popover
  @anchor='[data-anchor=a]'
  @open={{true}}
  @kind={{this.kind}}
  @canEscalateTo={{array 'details' 'edit' 'tools'}}
  @onEscalate={{this.setKind}}
  @onDismiss={{this.close}}
  as |kind|
>
  {{#if (eq kind 'edit')}}…{{else if (eq kind 'tools')}}…{{else}}…{{/if}}
</Popover>
```

The glyph/label mapping and the resolver are exported, so a host or playground
never re-decides which icon means what:

```js
import {
  POPOVER_KIND_GLYPHS,           // { details: 'ⓘ', edit: '✎', tools: '⋯' }
  POPOVER_KIND_LABELS,           // { details: 'Details', … }
  POPOVER_ESCALATION_PRIORITY,   // ['edit', 'tools', 'details']
  resolvePopoverEscalationTarget,// (targets) => the destination kind
} from './popover/utils/popover-types.ts';
```

## The three kinds in practice

`@kind` is a theme + role, but it's also the natural seam for the body content.
The playground crafts one view per kind — a useful template:

```gjs
{{#if (eq kind 'details')}}
  {{! passive, read-only info — role=tooltip, muted text, no edit field }}
  <dl class='detail'>
    <div><dt>Status</dt><dd>{{this.status}}</dd></div>
  </dl>
{{else if (eq kind 'edit')}}
  {{! the yellow editor surface — real form controls }}
  <BoxelSelect @options={{this.options}} @selected={{this.value}} @onChange={{this.set}} as |o|>{{o}}</BoxelSelect>
  <input value={{this.note}} {{on 'input' this.setNote}} />
{{else if (eq kind 'tools')}}
  {{! the dark action menu }}
  <ul role='menu'>
    <li><button {{on 'click' this.rename}}>Rename</button></li>
    <li><button {{on 'click' this.delete}}>Delete</button></li>
  </ul>
{{/if}}
```

For an `edit` body that owns its keyboard, add `@keyboardModel='edit'
@trapFocus={{true}}`; for a `tools` menu navigated by arrow keys, add
`@keyboardModel='pick'` and give the list `role='listbox'`.

## Gesture binding for grids / canvases

`PopoverState` (a hover-pause / dismiss-grace state machine) + the
`surfacePopoverBinding` modifier let many units share one popover: hover a unit
to peek `details`, click/dblclick to `edit`.

```gjs
import Popover from '../popover.gts';
import { createPopoverState } from '../utils/popover-state.ts';
import surfacePopoverBinding from '../modifiers/popover-binding.ts';

class GridIsolated extends Component<typeof Grid> {
  popovers = createPopoverState({
    anchorSelectorFor: (r, c) => `[data-row="${r}"][data-col="${c}"]`,
  });
  cellContract = { popover: ['details', 'edit'] };

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

For a single trigger you don't need any of this — wire `{{on 'mouseenter'}}` /
`{{on 'click'}}` on your own element to toggle the `@open` boolean.

## Theming

Set the `--bx-popover-*` CSS custom properties (`--bx-popover-accent`,
`--bx-popover-bg`, `--bx-popover-fg`, the `--bx-popover-size-*` tokens, …) at
`:root` or via a realm theme. That is the Boxel-idiomatic extension point, and
it works regardless of the `document.body` portal.

## What's in the package

| Path | Role |
| --- | --- |
| `popover.gts` | the `<Popover>` component + all chrome; exports `PopoverSignature` |
| `utils/popover-types.ts` | the shared type vocabulary (kind/anchoring/size/…) + the kind→glyph/label maps + escalation resolver |
| `utils/popover-state.ts` | `PopoverState` — per-host open/hover/dismiss state machine |
| `modifiers/popover-binding.ts` | `surfacePopoverBinding` — wires hover/click gestures to `PopoverState` |
| `utils/layer-manager.ts` | dynamic z-index allocator for stacked surfaces |
| `example/popover-playground-example.gts` | the runnable config explorer |

## Relationship to boxel-surface

This package is a decoupled copy of `boxel-surface`'s `Lift`. The heavier
optional integration with the surface runtime (focus-ladder, surface-runtime,
declarative lift edges) is intentionally **not** included. If you need full
focus-ladder integration, consume `Lift` from `boxel-surface` directly instead.
