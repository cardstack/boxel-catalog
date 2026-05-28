<div align="center">

# boxel-surface

**Headless interaction engine for typed-block UIs.**
A library of primitives — `Environment`, `Layout`, `Grid`, `Row`, `Cell`,
`Run`, `Unit`, `Canvas`, `Scene`, `Frame`, `Plane`, `Outline`, `Pane`,
`Scroll`, `Flow`, `Lift` — plus a runtime that
bakes the right keyboard, focus, selection, lifted-edit, and inspection
patterns into reusable contracts. Built on Glimmer / Ember.

> Surfaces is to UI semantics what react-aria is to accessibility.

</div>

```gts
import { Cell, Environment, Layout } from '../boxel-surface/src';

<template>
  <Environment @space={{@model}} @posture='use'>
    <Layout
      @preset='page'
      @key='launch-plan'
      @tag='article'
      @runtimePointer='preview-only'
    >
      <section class='plan-toolbar'>Q3 launch plan</section>

      <Cell @key='budget' @change={{true}}>
        {{@model.budget}}
      </Cell>
    </Layout>
  </Environment>
</template>
```

The engine handles traversal, browser focus, selection scoping, lift/input
ownership, dismissal on Esc / outside-click, ARIA roles, and projection-driven
adornments. Package bindings such as `surfaceGridBinding` and
`surfaceCanvasBinding` add sheet and canvas-specific gestures on top. The host
owns *what* a cell or object does on commit; the engine owns *how* it gets
there.

---

## Install

`boxel-surface` now lives inside the catalog realm at
`catalog/contents/boxel-surface/`. Consumers import it by relative path
from anywhere else in the same realm (e.g. `'../boxel-surface/src'`) — no
npm install step required.

`@cardstack/boxel-ui` is an optional peer for default thimble visuals.

## What you get

| Layer            | What's in it                                                                                                  |
|------------------|---------------------------------------------------------------------------------------------------------------|
| **Foundations**  | 14 surface kinds — `Environment`, `Layout`, `Pane`, `Frame`, `Plane`, `Canvas`, `Scene`, `Grid`, `Row`, `Cell`, `Run`, `Unit`, `Scroll`, `Flow`, `Outline` |
| **Lift**         | Anchored floating surface for focused interaction. Four kinds: `details`, `preview`, `edit`, `tools`.         |
| **Form**         | `Form`, `FormField`, `FormSection`, `FormTabs` / `FormTab`, `FormWizard` / `FormStep`, `FormAlert`, plus canonical cells `TextCell`, `EmailCell`, `NumberCell`, `SwitchCell`. Density / layout / columns cascade from `Form` to children. |
| **Cues**         | `CueLabel`, `CueDescription`, `CueStatus` — accessibility-wired support UI.                                   |
| **Engine**       | `SurfaceRuntime`, scoped subscriptions, viewport state, focus ladder compatibility, lift edges, contract negotiation, surface rules, projection-driven decals. |
| **Modifiers**    | `surfaceRoot`, `surfaceNode`, `surfaceGridBinding`, `surfaceCanvasBinding`, `surfaceSceneBinding`, `surfaceDecalLayer`, `surfaceInlineEdit`, `multiUnit`, `surfaceLiftBinding`, `portal`. |

## Current Runtime Shape

The maintained path is runtime-driven. `Environment` creates the runtime and
foundation/package surfaces register semantic participants. Package bindings own
normal interaction behavior:

- `Grid @preset="sheet"` owns cell selection, column/header projection, keyboard
  movement, edit handoff, and Escape cleanup.
- `surfaceCanvasBinding` owns object and edge selection, object move/resize,
  marquee, nudge, duplicate/delete, connection callbacks, snap, auto-pan, and
  transformed-canvas reveal hooks.
- `surfaceSceneBinding` is the scene-facing binding over the same object
  machinery; scene hosts still own camera/orbit behavior.
- `SurfaceRuntime` exposes scoped `subscribeSelection`, `subscribeTopology`,
  `subscribeInput`, and `subscribeViewport` channels. Use the broad
  `subscribe()` channel only for compatibility or whole-runtime diagnostics.

Structural page chrome should not become selected product state by accident. Use
`@posture` / `@inspect` for authoring posture, and use low-level runtime policy
overrides such as `@runtimePointer="preview-only"` only when a structural surface
needs to render context while leaving selection to descendants.

## Two dialects, one engine

**Portable** — expanded markup, explicit `@space` / `@coord` / `@schema`,
local CSS + tokens. Lossless and copy-pasteable.

**Adaptive** — concise, pattern-driven markup. The runtime fills in
defaults (traversal, ARIA, responsive, Cue decals, Place candidates)
from contracts and rules.

Both dialects resolve to the same surface tree.

## The workbench

Every primitive ships with a live exhibit that paints coordinate decals
over real surfaces, lets you walk the runtime projection with Tab, and
shows lift escalation chaining through `details` → `edit` → `tools`.
The workbench is maintained alongside the original surfaces source and
is not bundled into the catalog realm — open it from the upstream
surfaces development environment when you need it.

The workbench has six tiers:

| Tier         | What it is                                                                                          |
|--------------|------------------------------------------------------------------------------------------------------|
| **Showcase** | Same Cell, three hosts · Cross-host drag · Lift escalation · Agent dashboard                         |
| **Concepts** | One-page reference for each v3 word — Surface, Cue, Coordinate, Posture &amp; Inspect, Lift, Place, Adorn, Trail, Pattern, Traversal Set, Rule Matching |
| **Lessons**  | Mental model + the 10-lesson Build track                                                            |
| **Apps**     | Spreadsheet (boxel) · Document outline (notion) · Canvas board (figma) · Canvas flow (figma) · Space (3D) · Music library (spotify) · Storefront composer (shopify) · Form lab (form chrome) |
| **Reference**| Storybook-style component panels — args, schema, examples, code. Every entry is sourced from the live TypeScript signatures. |
| **Matrix**   | 14 × 14 pairwise composition catalog                                                                |

## Vocabulary, in one paragraph

A **Surface** is a meaningful unit of substance — a cell, a row, a run
of text, a framed image. A **Cue** is the support UI around it — a
label, a handle, a well, a popup. A **Coordinate** is a typed location
inside a parent **Coordinate Space**, not a DOM path. **Posture**
(`use` vs `compose`) and **Inspect** (overlay on / off) are independent
dials that cascade through the network. **Lift** shows a surface
elsewhere; **Place** moves one into another. The Concepts tier in the
workbench defines each in one screen.

> DOM and component renderers produce trees.
> *Surfaces produces a network over those trees.*

## Project layout

```
boxel-surface/
├── LICENSE
├── README.md
├── src/                  # Engine + foundation primitives
│   ├── index.ts            # Public surface — re-exports everything
│   ├── components/         # Glimmer/Ember bindings
│   │   ├── surface-component.gts   # Environment + 14 surface kinds
│   │   ├── lift.gts                # Lift component + chrome variants
│   │   ├── accessory.gts           # Accessory + CueLabel/Description/Status
│   │   ├── form*.gts               # Form, FormField, FormSection, …
│   │   └── (cell components, etc.)
│   ├── modifiers/          # grid/canvas/scene bindings, decals,
│   │                       #   root/node, inline edit, portal, lift binding
│   ├── contracts.ts        # ContractKey table, Contract / Capability types,
│   │                       #   negotiation, BASE_CONTRACTS for every pair
│   ├── focus-ladder.ts     # Focus/selection traversal compatibility bridge
│   ├── lift-edges.ts       # Declarative @lift edges + LiftManager
│   ├── lift-state.ts       # Lift state machine
│   ├── rules.ts            # CSS-selector pattern matching (adaptive dialect)
│   ├── canvas-dom.ts       # Canvas DOM registry
│   ├── grid-dom.ts         # Grid DOM registry
│   ├── dom-registry.ts     # Shared DOM registry primitives
│   ├── foci-*.ts           # Foci policy / projection / store
│   ├── surface-runtime.ts  # SurfaceRuntime + scoped subscriptions
│   ├── surface-contexts.ts # Provided contexts (Mode, Inspect, …)
│   ├── form-field-*.ts     # Form field context + resolution
│   ├── geometry-events.ts, keyboard.ts, layer-manager.ts,
│   ├── relative-scale.ts, resize-stability.ts, scope-relay.ts,
│   ├── template-helpers.ts, widget.ts
│   ├── icons/              # Inline SVG icon components
│   ├── styles/             # Shared CSS used by components
│   ├── themes/             # Theme tokens (boxel default theme)
│   └── thimble/            # Default thimble visuals (CSS + tokens)
└── packages/
    └── boxel-layout/       # Layout primitive (separate package boundary)
        ├── index.ts
        └── components/layout.gts
```

## Status

`0.10.0` — pre-release. The engine surface (foundations,
SurfaceRuntime, contracts, lift edges, rules, and package bindings) is
stable enough to build apps against. Default thimble implementations,
the rule library, and the Build track lessons are in active
development.


## License

[MIT](./LICENSE) © Cardstack