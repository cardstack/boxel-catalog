// Surface contracts — the second-generation interaction-policy model.
//
// THE PROBLEM WE'RE SOLVING
// =========================
//
// The first system (`traits.ts`) had widgets declare a flat list of
// 20+ trait booleans (`'click-to-focus'`, `'popover-editor'`,
// `'commit-on-close'`, etc.) and surfaces declare permits/forbids
// over the same flat union. `negotiateTraits()` returned an effective
// `Trait[]` — useful for showing chrome pills, but the host still had
// to map the resulting set back to "should arrow keys nav the grid
// or move my caret? does Esc close the cell editor or just demote
// rung? does this popover portal out of grid clip?" by hand.
//
// The trait list is the WRONG abstraction for those questions
// because the answer depends on which two surfaces are nested.
// `canvas → grid → cell → pane` is not "a pile of traits" — it's
// three contracts (canvas/grid, grid/cell, cell/pane) whose policy
// composition is mostly mechanical given a base lookup table.
//
// THIS FILE
// =========
//
// Defines a `Contract` — a 10-dimension typed object that
// answers the actual run-time questions:
//
//   focus       who owns the focus root?
//   selection   who owns the selection model?
//   pointer     who owns mouse-down?
//   keyboard    who owns arrow keys / typing?
//   commit      when does an edit become permanent?
//   sizing      who decides the editor's box size?
//   overflow    are popups portaled past clipping?
//   popup       does the editor inline, popover, pane, or plane?
//   layer       which z-tier?
//   adornment   what selection chrome wraps the surface?
//
// Plus a `negotiateContract()` function that produces one
// from (parentSurface, childSurface, capabilities, parentPolicy,
// instanceOverrides). The function is deterministic and table-driven
// — no runtime reasoning, just a base lookup followed by ordered
// refinement passes.
//
// SHARDED LOOKUP TABLES
// =====================
//
// Base contracts (for the ambient surfaces every package shares —
// run, layout, pane, plane) live HERE. Grid-specific contracts
// (`grid → cell`, `cell → pane` for cell-popover lift, `cell →
// plane` for modal lift, `layout → grid`) live in
// `boxel-grid/src/grid-surface-contracts.ts`. The grid imports
// the types and the base table from this package and SHARDS its
// own pairs into a sibling table. Resolution at runtime checks the
// grid-shard first, then the base table, then the safety default.
//
// This shape lets each package own the contracts whose SURFACES it
// owns. It also keeps boxel-widgets innocent of grid-specific
// keyboard idioms.
//
// SEE ALSO
// ========
//
//   - The Surface Matrix in the workbench (test-app) — every host >
//     guest pair with its negotiated contract. The visible spec for
//     what BASE_CONTRACTS encodes.
//   - `docs/contracts.md` — design notes on contract negotiation
//     (handcrafted-example validation, global rules, iteration log).

import type { Surface } from './widget.ts';

// ─── core types ───────────────────────────────────────────────────

/**
 * A `Surface` names a kind of rendering context with its own
 * authority over focus, selection, and gesture. The list is
 * deliberately small.
 *
 * Re-exported from `widget.ts` so consumers can import from a
 * single module:
 *   `import type { Surface } from '@cardstack/boxel-surface'`
 */
export type { Surface };

/**
 * What the SURFACE is being rendered FOR. Same as the legacy
 * `Intent` (`'preview' | 'editor'`) but extended with the higher-
 * level intents the contract negotiation needs to distinguish —
 * a "picker" pane behaves differently from an "editor" pane,
 * for example.
 *
 * For now the spreadsheet only uses `'preview'` and `'editor'`;
 * the rest are reserved for the broader Boxel use cases the design
 * memo describes.
 */
export type Intent =
  | 'preview'
  | 'editor'
  | 'adornment'
  | 'picker'
  | 'navigation';

/**
 * Capability HINTS the widget gives the negotiator. Smaller and
 * less prescriptive than the legacy `Trait` union — these answer
 * questions like "is this widget a text input?" or "is committing
 * on every keystroke safe?", not "should it use a popover?". The
 * contract dimensions decide the latter.
 *
 * Names are deliberately verb-y / property-y so they read as
 * statements about the widget's NATURE, not about UI choices.
 */
export type Capability =
  /** Widget consumes text input — implies the host should suspend
   *  parent shortcuts (Backspace, Space, etc.) while the widget
   *  has focus. Pairs with rule "active text editing captures
   *  keyboard". */
  | 'text-input'
  /** Widget supports a DETAILS lift — has a preview component
   *  suitable for tooltip-light read-only inspection on hover.
   *  Host opens this kind on hover-with-pause. K.5: replaces the
   *  legacy 'popover'/'pane'/'plane' capability hints, which
   *  conflated mechanism (CSS shell) with intent (what the lift
   *  is FOR). */
  | 'lift-details'
  /** Widget supports an EDIT lift — has a pane.editor (or
   *  unit.editor) suitable for focused mutation in an attached
   *  surface. Host opens this kind on click chevron / Enter / F2 /
   *  dblclick. */
  | 'lift-edit'
  /** Widget supports a PREVIEW lift — has a richer card-style
   *  preview component (e.g., a card-mention shows the full card
   *  body). Heavier than details, lighter than edit. */
  | 'lift-preview'
  /** Widget supports a TOOLS lift — has a list of actions / commands
   *  the user can run on the source. Context-menu / command-palette
   *  style. */
  | 'lift-tools'
  /** Widget defaults to a PLANE-sized lift (full-viewport modal)
   *  for its edit kind, instead of the default attached/anchored
   *  popover-style placement. Used by widgets whose editors need
   *  more room than a popover can give (e.g., rich text, image
   *  crop, formula builder). */
  | 'plane-default'
  /** Widget defaults to SHADOW-placed lift for its edit kind.
   *  The lift overlays the source cell at the same top-left
   *  position, usually wider — visually the cell appears to
   *  "grow" while editing. Used by widgets whose editor needs
   *  more horizontal room than a narrow column allows but still
   *  benefits from the in-place feel (slider, narrow pickers,
   *  formula expression builders). Pairs with `lift-edit`;
   *  ignored if no edit lift is declared. */
  | 'shadow-default'
  /** Widget commits cleanly on EVERY user gesture — safe to wire
   *  `commit: 'live'` without losing data or confusing the user.
   *  Pattern-B atoms (toggle, slider drag, stars click) declare
   *  this. */
  | 'live-write'
  /** Widget buffers an internal draft and commits explicitly —
   *  pairs with `commit: 'draft'` or `'on-close'`. Calendar's
   *  modal mode and chips' multi-select picker declare this. */
  | 'draft-commit'
  /** Widget has a "close = commit" semantic of its own. Pairs
   *  with `commit: 'on-close'` for popups; the host can dismiss
   *  the surface without an explicit Save button. */
  | 'commit-on-close'
  /** Widget has its own escape-hatch editor variant (escape-to-raw
   *  pattern: strict picker hands off to a less-strict text input
   *  inside the same lift surface). Host wires the escalation
   *  callback when this is present. */
  | 'escape-to-raw'
  /** Widget renders adornments on hover (faded preview, reveal
   *  affordances). Host should set `adornment: 'hover'`. */
  | 'hover-reveal'
  /** Widget supports keyboard arrow nudge on its value (slider,
   *  number input, stars). Host should NOT consume arrow keys
   *  while the widget has focus. */
  | 'arrow-nudge'
  /** Widget participates in container-query / measured layouts
   *  (e.g., a fitted card frame). Host should set `sizing:
   *  'measured'`. */
  | 'cq-size'
  /** Widget is interactive HTML and should not be treated as a
   *  static rendered preview (Boxel embedded card use case). */
  | 'interactive-html'
  /** Widget can be resized by the user. Host should set
   *  `sizing: 'resizable'` and render resize handles. */
  | 'resizable'
  /** Widget renders MULTIPLE units inside one cell (chips, tags,
   *  mention list, image with annotations). Hosts that detect this
   *  capability:
   *    - register the cell as `surface: 'cell'` (not the default
   *      single-value 'unit')
   *    - scan the rendered DOM for `[data-unit-key]` elements
   *    - register each as a `surface: 'unit'` child of the cell
   *  Selection then works at unit granularity inside the cell:
   *  clicking a tag selects that tag; arrows cycle tags. The
   *  surrounding cell still selects as one unit when the user
   *  hasn't descended into it. See SKILL.md §1 for the
   *  unit-vs-cell topology rule. */
  | 'multi-unit';

/**
 * The kinds of lift a cell can offer. K.5 introduces this enum as
 * a first-class contract dimension, replacing the legacy
 * `contract.popup` field which named the CSS mechanism rather than
 * the user intent.
 *
 *   details   Hover-triggered tooltip-light read-only inspection.
 *   preview   Anchored card-style summary, sticky.
 *   edit      Focused mutation surface (picker, calendar, formula).
 *   tools     Action palette / command list.
 *
 * See `src/components/lift.gts` for the Lift shell that
 * renders each kind.
 */
export type LiftKind = 'details' | 'preview' | 'edit' | 'tools';

/**
 * A `Contract` is the FULL run-time policy for a child
 * surface mounted inside a parent surface. Every dimension is
 * non-optional and resolves to a concrete enum value — the host
 * never has to ask "what if focus is undefined?".
 *
 * 10 dimensions, ordered roughly from most-defining to least:
 *
 *   focus       Who owns the focus root?
 *   selection   Who owns the selection model?
 *   pointer     Who handles mouse-down?
 *   keyboard    Who handles arrow keys / typing?
 *   commit      When does an edit become permanent?
 *   sizing      Who decides the editor's box size?
 *   overflow    Are popups portaled past clipping?
 *   popup       What lift surface does the editor open in?
 *   layer       Which z-tier does the lift live on?
 *   adornment   What chrome wraps the surface?
 *
 * Each enum value is intentionally short and English-readable so
 * the contract dump is self-documenting in dev tools.
 */
export interface Contract {
  /** Who owns the focus root inside this child surface?
   *  - 'parent'    parent keeps focus, child is decorative
   *  - 'child'     child takes focus on activation
   *  - 'delegated' shared — child gets focus on direct interaction,
   *                parent keeps it otherwise (grid-cell idiom)
   *  - 'contained' focus is trapped INSIDE this child until close
   *                (popover / pane editors)
   *  - 'trapped'   focus is locked inside; parent is also blocked
   *                (modal plane) */
  focus: 'parent' | 'child' | 'delegated' | 'contained' | 'trapped';

  /** Who owns the selection model?
   *  - 'parent'  parent's selection is the only selection
   *  - 'child'   child manages its own selection (e.g., a text
   *              input's text selection)
   *  - 'shared'  both — child selection is scoped, parent retains
   *              outer selection
   *  - 'range'   parent selection is a 1D/2D range (grid)
   *  - 'object'  parent selection is per-object (canvas nodes)
   *  - 'none'    no selection model (display-only) */
  selection: 'parent' | 'child' | 'shared' | 'range' | 'object' | 'none';

  /** Who handles mouse-down (and downstream pointer events)?
   *  - 'parent-gesture'    parent's drag/select wins
   *  - 'child-interaction' child's click/drag wins
   *  - 'gesture-split'     hover/click split — preview goes to
   *                        parent, active editing goes to child
   *  - 'captured'          one side captures pointer (canvas tool)
   *  - 'blocked'           pointer events do not reach lower
   *                        layers (modal plane) */
  pointer:
    | 'parent-gesture'
    | 'child-interaction'
    | 'gesture-split'
    | 'captured'
    | 'blocked';

  /** Who handles keyboard (arrow keys, typing, shortcuts)?
   *  - 'parent-shortcuts'  parent's key bindings win
   *  - 'child-text'        child is a text input — parent
   *                        shortcuts suspended
   *  - 'grid-navigation'   parent is a grid — arrows nav cells,
   *                        Enter/Tab activate
   *  - 'canvas-tool'       parent is a canvas — tool keys win
   *  - 'modal'             modal — only Esc/close routes to
   *                        parent */
  keyboard:
    | 'parent-shortcuts'
    | 'child-text'
    | 'grid-navigation'
    | 'canvas-tool'
    | 'modal';

  /** When does an in-progress edit become permanent?
   *  - 'preview-only' display only — there is no edit
   *  - 'live'         every interaction commits (atom-as-editor)
   *  - 'draft'        local draft until explicit commit
   *  - 'on-blur'      commits when focus leaves
   *  - 'on-close'     commits when the lift surface closes
   *  - 'explicit'     commits only on a Save button */
  commit:
    | 'preview-only'
    | 'live'
    | 'draft'
    | 'on-blur'
    | 'on-close'
    | 'explicit';

  /** Who decides the editor's box size?
   *  - 'intrinsic' content-driven (CSS min/max-content)
   *  - 'fill'      fills the parent's available box
   *  - 'measured'  measured by parent (frame, container queries)
   *  - 'clamped'   declared min/max width, clamps to viewport
   *  - 'resizable' user-resizable handles */
  sizing: 'intrinsic' | 'fill' | 'measured' | 'clamped' | 'resizable';

  /** What does the lift surface do about its parent's clipping?
   *  - 'visible' no clipping concern (no lift)
   *  - 'clip'    surface respects parent clip (inline)
   *  - 'scroll'  surface scrolls inside its own bounds (pane)
   *  - 'portal'  surface lifts to a new stacking context that
   *              ignores parent clip (popover, plane) */
  overflow: 'visible' | 'clip' | 'scroll' | 'portal';

  /** Which LIFT KINDS this cell supports. Empty array = no lift
   *  (Pattern A/B widgets like toggle, stars, slider — they're
   *  their own preview AND their own editor, no separate lift
   *  surface needed). Order encodes the ESCALATION CHAIN: the
   *  first kind is the default on hover (typically `'details'`);
   *  the last is the most-escalated (typically `'edit'`).
   *
   *  K.5 vocabulary shift: replaces the legacy `popup` field. The
   *  old field named a MECHANISM (popover/pane/plane = CSS shell
   *  type); the new field names INTENTS (details/preview/edit/
   *  tools). The `<Lift>` shell renders different chrome per kind;
   *  hosts dispatch the right kind from the right gesture (hover
   *  → details, click chevron → edit). */
  lift: LiftKind[];

  /** Where lifts mount geometrically:
   *   - 'attached' anchored popover-style next to the source (default).
   *                Lift floats alongside the source, doesn't overlap.
   *   - 'shadow'   overlays directly ON TOP of the source at the same
   *                position, in the same shape (usually wider). The
   *                lift looks like the source grew. Used when the
   *                editor is bigger than the source cell can hold but
   *                you want the in-place feel — e.g., a wide pill
   *                picker over a narrow status cell.
   *   - 'plane'    full-viewport modal on the curtain plane (rich
   *                text, image crop, formula builder). Takes over.
   *
   *  Independent from `lift` (intent). A widget can declare
   *  `lift: ['details', 'edit']` AND `liftPlacement: 'plane'` —
   *  details renders attached (it's lightweight by nature), edit
   *  renders as a plane (it needs the room). The Lift component
   *  uses this hint to pick its size class. */
  liftPlacement: 'attached' | 'shadow' | 'plane';

  /** How DOM focus moves between the source surface and an opened
   *  lift surface.
   *   - 'auto'   On open, the lift moves DOM focus to its first
   *              focusable child (input, button, contenteditable,
   *              [tabindex]). On close (Esc, commit, dismiss), the
   *              lift restores DOM focus to the source anchor so the
   *              host's keyboard nav resumes (Enter to reopen, arrows
   *              to move). Pickers, number-with-stepper editors, and
   *              calendar lifts default to this — without it the user
   *              dblclicks open and then has to mouse-click into the
   *              lift to type. K.5: this is the default for `'edit'`
   *              kind lifts.
   *   - 'manual' Lift does NOT move focus. Host owns it (e.g., a
   *              hover-triggered details lift shouldn't steal focus).
   *
   *  Hover-opened `'details'` lifts default to 'manual'. Click-opened
   *  `'edit'` / `'tools'` lifts default to 'auto'. The negotiator
   *  picks based on lift kind unless a capability overrides. */
  liftFocus: 'auto' | 'manual';

  /** Geometric size class for the lift panel. Drives min/max
   *  width + height defaults baked into the Lift component, so
   *  widgets stop declaring their own `minEditorWidth`. Per-token
   *  defaults (subject to host CSS overrides):
   *    - 'compact'     min 200x40,   max 280x320
   *    - 'comfortable' min 280x60,   max 380x440  (default for edit)
   *    - 'spacious'    min 380x80,   max 540x600
   *    - 'auto'        no defaults — content drives
   *  Hosts override via `--bx-lift-size-{token}-{min|max}-{w|h}` CSS
   *  custom properties. */
  liftSize: 'compact' | 'comfortable' | 'spacious' | 'auto';

  /** Visual separation behind the lift.
   *    - 'none'   transparent backdrop — body shows through
   *    - 'tint'   soft white wash (98% opaque) — details lift
   *    - 'blur'   6px backdrop-filter blur — focused edit chrome
   *    - 'scrim'  full-viewport dim 40% black — plane modal
   *  Scrim is rendered as a sibling fixed-position div by the Lift
   *  component itself; hosts don't have to mount their own. */
  liftBackdrop: 'none' | 'tint' | 'blur' | 'scrim';

  /** Elevation tier — drives shadow depth + accent ring. Distinct
   *  from `layer` (logical z-tier); elevation is the visible-depth
   *  chrome. Tokens map to CSS vars `--bx-lift-shadow-{token}` and
   *  `--bx-lift-ring-{token}`:
   *    - 'flat'      `0 1px 2px rgba(0,0,0,.06)`,        no ring
   *    - 'raised'    `0 2px 6px -1px rgba(0,0,0,.08)`,   no ring
   *    - 'elevated'  `0 8px 16px -4px rgba(0,0,0,.12)`,  1.5px accent
   *    - 'modal'     `0 24px 48px -12px rgba(0,0,0,.20)`, 4px accent6%
   *  Hosts override either var per host. */
  liftElevation: 'flat' | 'raised' | 'elevated' | 'modal';

  /** Keyboard activation model for the lift surface. Drives whether
   *  arrows navigate options vs move caret, whether Enter commits
   *  highlight vs save draft, what typing does (filter search vs
   *  replace value vs nudge nothing).
   *    - 'pick'         Spotlight idiom — arrows nav listbox, Enter
   *                     commits highlighted, letters/digits route to
   *                     search input + type, Space toggles (multi-
   *                     select). Default for `edit` lifts on widgets
   *                     without numeric editors.
   *    - 'edit-number'  Excel L1 — arrows nudge value (±1, shift ±10),
   *                     letters/digits replace selection, Enter
   *                     commits + advance. Slider, number-input.
   *    - 'edit-text'    Native text input — arrows = caret, typing
   *                     inserts, Enter commits + advance. Text-area.
   *    - 'compose'      Lift doesn't intercept — keystrokes route
   *                     to the editor's own root. Calendar, formula,
   *                     rich text. */
  liftKeyboardModel: 'pick' | 'edit-number' | 'edit-text' | 'compose';

  /** Whether the cell participates in RANGE SELECTION (Shift-click,
   *  Shift-arrow, drag-fill). Spreadsheet cells are usually true;
   *  multi-unit cells (chips) are usually false (range-overwriting
   *  a tag list doesn't make sense). Future host primitives
   *  (RangeSelection service) read this to decide whether to
   *  include the cell in a range expansion. */
  rangeable: boolean;

  /** What happens to focus AFTER an edit commits via Enter:
   *   - 'down'  move focus to next row, same column (spreadsheet)
   *   - 'right' move to next column, same row (form / wizard)
   *   - 'stay'  keep focus on the same cell (live-write atoms,
   *             commits without changing context)
   *
   *  Shift-Enter inverts (down → up, right → left). Tab always
   *  goes right; Shift-Tab always goes left, regardless of this
   *  dim. */
  advanceOnCommit: 'down' | 'right' | 'stay';

  /** Which z-tier does the lift surface live on? Maps to the
   *  grid's `LiftTier` LayerManager allocation.
   *  - 'base'      no lift (default flow)
   *  - 'adornment' selection rings, focus halos
   *  - 'cell-lift' in-place expanded cell editor
   *  - 'popover'   anchored popover above grid
   *  - 'modal'     full-viewport modal (browser top layer) */
  layer: 'base' | 'adornment' | 'cell-lift' | 'popover' | 'modal';

  /** What chrome wraps this surface?
   *  - 'none'     no chrome
   *  - 'hover'    chrome reveals on hover (preview affordances)
   *  - 'selected' chrome shows when selected (selection ring)
   *  - 'active'   chrome shows during active interaction
   *  - 'always'   chrome always visible (resize grips) */
  adornment: 'none' | 'hover' | 'selected' | 'active' | 'always';
}

/**
 * The shape a SURFACE declares about itself: which capability hints
 * it accepts, which contract dimensions it permits / forbids /
 * defaults. Shipping policies (`GRID_CELL_POLICY`, etc.) live with
 * the surface owner — for grid, in `boxel-grid`.
 *
 * Policies REFINE base contracts. They do NOT replace the lookup —
 * the negotiator always starts from the base table.
 */
export interface Policy {
  /** Capability hints the surface honors. Hints outside this set
   *  are silently ignored (the negotiator falls back to whatever
   *  the base contract said for that dimension). */
  permits?: Capability[];
  /** Capability hints the surface explicitly disables. Even when
   *  a widget declares the hint AND the base contract would
   *  honor it, the surface's `forbids` strips it. */
  forbids?: Capability[];
  /** Dimensions this surface OVERRIDES on every contract it hosts —
   *  e.g., a spreadsheet surface always wants `adornment: 'active'`
   *  for selection rings regardless of what the base table says. */
  overrides?: Partial<Contract>;
}

/**
 * Per-instance overrides. The most-specific layer of refinement —
 * a single column, a single tile, a single embed says "for this
 * one, override these dimensions." Subject to safety rules: the
 * negotiator will not honor an override that would unlock focus
 * for a `'plane'`-level surface, for example.
 */
export type InstanceContractOverrides = Partial<Contract>;

// ─── inputs / output of negotiation ───────────────────────────────

export interface ContractNegotiationInput {
  parentSurface: Surface;
  parentIntent: Intent;
  childSurface: Surface;
  childIntent: Intent;
  capabilities: Capability[];
  parentPolicy?: Policy;
  instanceOverrides?: InstanceContractOverrides;
}

// ─── safety / fallback contract ───────────────────────────────────

/**
 * The "if everything else returns nothing, you get this" contract.
 * Equivalent to a static read-only display: parent owns everything,
 * child has no authority, no editor mounts. Safe to render anywhere.
 */
export const FALLBACK_CONTRACT: Contract = {
  focus: 'parent',
  selection: 'parent',
  pointer: 'parent-gesture',
  keyboard: 'parent-shortcuts',
  commit: 'preview-only',
  sizing: 'intrinsic',
  overflow: 'visible',
  lift: [],
  liftPlacement: 'attached',
  liftFocus: 'auto',
  liftSize: 'comfortable',
  liftBackdrop: 'tint',
  liftElevation: 'raised',
  liftKeyboardModel: 'compose',
  rangeable: false,
  advanceOnCommit: 'stay',
  layer: 'base',
  adornment: 'none',
};

// ─── base lookup table ────────────────────────────────────────────
//
// Indexed by `'parent>child'` strings. Pairs that are valid but
// not listed fall through to FALLBACK_CONTRACT and then get refined
// by capability + policy passes.
//
// THIS TABLE OWNS BASE PAIRS — pairs that span every package. Pairs
// where one surface is grid-specific (grid>cell, layout>grid) live
// in `boxel-grid/src/grid-surface-contracts.ts`. Resolver merges
// the two.
//
// Each row matches a row in the design memo's "Base Lookup Table"
// section. Comments explain why each dimension picks the value it
// does.

type ContractKey = `${Surface}>${Surface}`;

export const BASE_CONTRACTS: Partial<Record<ContractKey, Contract>> = {
  // ─── layout > run ─────────────────────────────────
  // Run = inline prose token (mention chip, status pill in markdown).
  // No editing by default; click may open a popover at the host's
  // discretion.
  'layout>run': {
    focus: 'parent',
    selection: 'none',
    pointer: 'parent-gesture',
    keyboard: 'parent-shortcuts',
    commit: 'preview-only',
    sizing: 'intrinsic',
    overflow: 'visible',
    lift: [],
    liftPlacement: 'attached',
    liftFocus: 'auto',
    liftSize: 'comfortable',
    liftBackdrop: 'tint',
    liftElevation: 'raised',
    liftKeyboardModel: 'compose',
    rangeable: false,
    advanceOnCommit: 'stay',
    layer: 'base',
    adornment: 'none',
  },

  // ─── layout > cell ────────────────────────────────
  // Cell-as-form-field: a card edit form embedding a tabular row
  // with each field as a cell. Focus delegated, edits commit on
  // blur, popovers allowed for rich pickers.
  //
  // In the new unit-centric topology, this entry serves the
  // MULTI-UNIT case (a tag list inside a form field — cell groups
  // many units). Single-value widgets bypass this and use
  // `layout > unit` directly; the cell layer collapses entirely.
  'layout>cell': {
    focus: 'delegated',
    selection: 'child',
    pointer: 'child-interaction',
    keyboard: 'child-text',
    commit: 'on-blur',
    sizing: 'fill',
    overflow: 'clip',
    // Multi-unit cells offer details (hover-tooltip) + edit (the
    // multi-select picker). No range selection by default —
    // overwriting a tag set with a range fill doesn't compose.
    lift: ['details', 'edit'],
    liftPlacement: 'attached',
    liftFocus: 'auto',
    liftSize: 'comfortable',
    liftBackdrop: 'tint',
    liftElevation: 'raised',
    liftKeyboardModel: 'compose',
    rangeable: false,
    advanceOnCommit: 'down',
    layer: 'popover',
    adornment: 'hover',
  },

  // ─── layout > unit ────────────────────────────────
  // Single-value field inside a layout (form / row card). Same
  // semantics as `layout > cell` minus the multi-atom container
  // overhead — the unit IS the field's value, and the cell layer
  // collapses entirely. The DEFAULT for almost every widget today
  // (toggle, pill, stars, calendar, text).
  'layout>unit': {
    focus: 'delegated',
    selection: 'child',
    pointer: 'child-interaction',
    keyboard: 'child-text',
    commit: 'on-blur',
    sizing: 'fill',
    overflow: 'clip',
    // Single-value units typically offer details + edit. Widgets
    // that don't have an editor (read-only Pattern A) override
    // `lift: []` via capabilities.
    lift: ['details', 'edit'],
    liftPlacement: 'attached',
    liftFocus: 'auto',
    liftSize: 'comfortable',
    liftBackdrop: 'tint',
    liftElevation: 'raised',
    liftKeyboardModel: 'compose',
    rangeable: true,
    advanceOnCommit: 'down',
    layer: 'popover',
    adornment: 'hover',
  },

  // ─── cell > unit ──────────────────────────────────
  // Unit inside a multi-unit cell (one tag in a tag list, one pin
  // on an annotated image). The cell wraps focus + selection at
  // its level (a range of units can be selected as a unit); the
  // unit owns its inline edit. Used only when the widget declares
  // `multi-unit` — single-value widgets skip this layer.
  'cell>unit': {
    focus: 'delegated',
    selection: 'child',
    pointer: 'child-interaction',
    keyboard: 'child-text',
    commit: 'on-blur',
    sizing: 'intrinsic',
    overflow: 'visible',
    // Sub-units of a multi-unit cell typically don't offer their
    // own lifts — the cell wrapper holds the edit picker that
    // toggles them. A unit can opt-in via per-unit capability
    // overrides if it wants its own per-unit editor (e.g., a
    // mention chip with its own card preview).
    lift: [],
    liftPlacement: 'attached',
    liftFocus: 'auto',
    liftSize: 'comfortable',
    liftBackdrop: 'tint',
    liftElevation: 'raised',
    liftKeyboardModel: 'compose',
    rangeable: false,
    advanceOnCommit: 'stay',
    layer: 'popover',
    adornment: 'hover',
  },

  // ─── layout > layout ──────────────────────────────
  // Card embedded inside a card. Both have authority; commits draft
  // until explicit save.
  'layout>layout': {
    focus: 'delegated',
    selection: 'shared',
    pointer: 'gesture-split',
    keyboard: 'parent-shortcuts',
    commit: 'draft',
    sizing: 'intrinsic',
    overflow: 'visible',
    // Embedded card → preview (peek the whole card) + edit (open
    // the card's pane editor). Plane placement since cards usually
    // need more room than an attached popover gives.
    lift: ['details', 'preview', 'edit'],
    liftPlacement: 'plane',
    liftFocus: 'auto',
    liftSize: 'comfortable',
    liftBackdrop: 'tint',
    liftElevation: 'raised',
    liftKeyboardModel: 'compose',
    rangeable: false,
    advanceOnCommit: 'stay',
    layer: 'base',
    adornment: 'hover',
  },

  // ─── layout > pane ────────────────────────────────
  // Form opens a pane editor (color picker, rich text, relationship
  // picker). Pane traps focus; commits on close.
  'layout>pane': {
    focus: 'contained',
    selection: 'child',
    pointer: 'child-interaction',
    keyboard: 'child-text',
    commit: 'on-close',
    sizing: 'fill',
    overflow: 'scroll',
    lift: ['edit'],
    liftPlacement: 'attached',
    liftFocus: 'auto',
    liftSize: 'comfortable',
    liftBackdrop: 'tint',
    liftElevation: 'raised',
    liftKeyboardModel: 'compose',
    rangeable: false,
    advanceOnCommit: 'stay',
    layer: 'popover',
    adornment: 'none',
  },

  // ─── any > plane ──────────────────────────────────
  // Modal full-viewport editor. Always traps; always explicit. The
  // grid's `cell>plane` and `canvas>plane` pairs in the grid-shard
  // table reuse these defaults.
  'layout>plane': {
    focus: 'trapped',
    selection: 'child',
    pointer: 'blocked',
    keyboard: 'modal',
    commit: 'explicit',
    sizing: 'fill',
    overflow: 'scroll',
    lift: ['edit'],
    liftPlacement: 'plane',
    liftFocus: 'auto',
    liftSize: 'comfortable',
    liftBackdrop: 'tint',
    liftElevation: 'raised',
    liftKeyboardModel: 'compose',
    rangeable: false,
    advanceOnCommit: 'stay',
    layer: 'modal',
    adornment: 'none',
  },

  // ─── pane > layout ────────────────────────────────
  // Inspector pane editing a card. Pane owns scroll + keyboard;
  // child fields own their inputs.
  'pane>layout': {
    focus: 'contained',
    selection: 'child',
    pointer: 'child-interaction',
    keyboard: 'child-text',
    commit: 'draft',
    sizing: 'fill',
    overflow: 'scroll',
    lift: ['edit'],
    liftPlacement: 'attached',
    liftFocus: 'auto',
    liftSize: 'comfortable',
    liftBackdrop: 'tint',
    liftElevation: 'raised',
    liftKeyboardModel: 'compose',
    rangeable: false,
    advanceOnCommit: 'stay',
    layer: 'popover',
    adornment: 'none',
  },

  // ─── pane > plane ─────────────────────────────────
  // Pane escalates a field editor to a modal plane (e.g., rich text
  // editor maximize). Plane wins everything.
  'pane>plane': {
    focus: 'trapped',
    selection: 'child',
    pointer: 'blocked',
    keyboard: 'modal',
    commit: 'explicit',
    sizing: 'fill',
    overflow: 'scroll',
    lift: ['edit'],
    liftPlacement: 'plane',
    liftFocus: 'auto',
    liftSize: 'comfortable',
    liftBackdrop: 'tint',
    liftElevation: 'raised',
    liftKeyboardModel: 'compose',
    rangeable: false,
    advanceOnCommit: 'stay',
    layer: 'modal',
    adornment: 'none',
  },
};

// ─── shared resolver registry ─────────────────────────────────────
//
// Each consuming package (boxel-grid, future boxel-canvas,
// boxel-card-host) registers its own contract shard. The registry
// composes them at lookup time so callers never have to import
// from N tables.
//
// `boxel-surface` registers `BASE_CONTRACTS` automatically below.
// Other packages call `registerContractTable(NAME, table)` from
// their own module init.

export type ContractTable = Partial<Record<ContractKey, Contract>>;

const CONTRACT_TABLES = new Map<string, ContractTable>();
CONTRACT_TABLES.set('base', BASE_CONTRACTS);

export function registerContractTable(
  name: string,
  table: ContractTable,
): void {
  CONTRACT_TABLES.set(name, table);
}

/**
 * Look up the base contract for a (parent, child) pair across all
 * registered shards. Search order: most-recently-registered wins
 * (so package shards override base if there's a conflict — the
 * package owns the surface, it knows best).
 */
export function lookupBaseContract(parent: Surface, child: Surface): Contract {
  const key: ContractKey = `${parent}>${child}`;
  // Iterate in REVERSE insertion order — last shard registered wins.
  // (Map iteration order is insertion order; we walk it backwards.)
  const tables = [...CONTRACT_TABLES.values()].reverse();
  for (const table of tables) {
    const hit = table[key];
    if (hit) return { ...hit };
  }
  return { ...FALLBACK_CONTRACT };
}

// ─── refinement passes ────────────────────────────────────────────
//
// Each pass takes (current contract, input) and returns a new
// contract. Order matters; see the `negotiateContract`
// pipeline below.

/** Pass 1: intent refinement.
 *  Preview vs editor changes commit + adornment + lift availability. */
function applyIntent(
  contract: Contract,
  input: ContractNegotiationInput,
): Contract {
  if (input.childIntent === 'preview') {
    return {
      ...contract,
      commit: 'preview-only',
      // Preview cells don't offer lifts — only editor cells do.
      // (Future: a `details`-only lift might still apply for
      // hover-inspection of preview cells. Re-add when needed.)
      lift: [],
      layer: 'base',
    };
  }
  if (input.childIntent === 'editor') {
    // Editor inherits from base. If commit was preview-only, bump
    // to draft (defensive — base tables shouldn't say preview-only
    // for editor pairs, but a fallback might).
    if (contract.commit === 'preview-only') {
      return { ...contract, commit: 'draft' };
    }
  }
  return contract;
}

/** Pass 2: capability refinement.
 *  Each capability hint may upgrade specific dimensions. */
function applyCapabilities(contract: Contract, caps: Capability[]): Contract {
  let c = { ...contract };
  const has = (cap: Capability): boolean => caps.includes(cap);

  // Text input → child owns keyboard.
  if (has('text-input')) {
    c.keyboard = 'child-text';
    c.pointer = 'child-interaction';
  }

  // Live-write → commit becomes live (Pattern B atoms).
  if (has('live-write')) {
    c.commit = 'live';
  }

  // Draft-commit → commit becomes draft (modal flows that buffer).
  if (has('draft-commit') && c.commit !== 'live') {
    c.commit = 'draft';
  }

  // ─── LIFT KINDS ───────────────────────────────────────────
  //
  // Capabilities declare which lift INTENTS the widget supports;
  // the negotiator collects them into `contract.lift`, preserving
  // the canonical escalation order:
  //
  //     details  →  preview  →  edit  →  tools
  //
  // Order in the array IS the escalation chain — hosts read it
  // and use the FIRST element as the default-on-hover kind, the
  // LAST as the default-on-edit-gesture kind.
  //
  // K.5 vocabulary shift: the legacy `popover` / `pane` / `plane`
  // capabilities (which named CSS shells) are gone. Widgets now
  // declare INTENTS (`lift-details`, `lift-edit`, etc.) and a
  // separate `plane-default` cap if they need plane placement.
  //
  // The base contract may already specify `lift` for the surface
  // pair (e.g., `layout>unit` defaults to `['details', 'edit']`);
  // capability filtering REFINES it: kinds the widget doesn't
  // declare get DROPPED so a Pattern A/B widget (toggle, stars)
  // ends up with `lift: []`.
  //
  // ─────────────────────────────────────────────────────────────

  const declaredLifts = new Set<LiftKind>();
  if (has('lift-details')) declaredLifts.add('details');
  if (has('lift-preview')) declaredLifts.add('preview');
  if (has('lift-edit')) declaredLifts.add('edit');
  if (has('lift-tools')) declaredLifts.add('tools');

  if (declaredLifts.size === 0) {
    // Widget didn't declare any lift caps — Pattern A/B (read-only
    // or atom-as-editor). Drop whatever the base contract said.
    c.lift = [];
  } else {
    // Refine the base contract's lift list to the intersection
    // with what the widget supports, preserving canonical order.
    const canonical: LiftKind[] = ['details', 'preview', 'edit', 'tools'];
    c.lift = canonical.filter((k) => declaredLifts.has(k));
  }

  // Plane placement: widget hint that its edit lift wants the
  // bigger surface (rich text, image crop, formula builder). Only
  // applies when the cell actually has lifts — otherwise no-op.
  if (has('plane-default') && c.lift.length > 0) {
    c.liftPlacement = 'plane';
    c.layer = 'modal';
    c.overflow = 'portal';
  } else if (has('shadow-default') && c.lift.length > 0) {
    // Shadow placement: lift overlays source at the same position,
    // usually wider. The cell appears to grow. Used for narrow-
    // column widgets that need editor room without a separate
    // popover anchored next to them. Stays in cell-lift layer
    // (above selection chrome, below modals) and portals out of
    // clip ancestors so the wider geometry isn't trimmed by the
    // grid's overflow:hidden.
    c.liftPlacement = 'shadow';
    c.layer = 'cell-lift';
    c.overflow = 'portal';
  } else if (c.lift.length > 0 && c.liftPlacement === 'attached') {
    // Attached lifts portal out of clip ancestors (popover-style).
    c.overflow = 'portal';
  }

  // ─── lift kind → 4-tuple defaults ─────────────────────────────
  //
  // Pick size / backdrop / elevation / keyboardModel from the most-
  // escalated lift kind the contract supports. Hosts read the
  // contract dims and the Lift component applies them; this keeps
  // widgets out of the chrome decision (they declare WHAT the lift
  // is for, the surface decides HOW it looks + behaves).
  //
  // Rules:
  //   - 'details' kind alone        → tiny tooltip-light (compact + tint + raised + compose)
  //   - 'edit' kind (no shadow)     → comfortable + blur + elevated + pick
  //   - 'edit' kind + shadow        → auto + none + elevated + (numeric-aware)
  //   - 'edit' kind + plane         → spacious + scrim + modal + compose
  //   - 'tools' kind                → compact + none + raised + pick
  //
  // The widget can override per-keystroke-model by capability
  // (`text-input` + `arrow-nudge` → 'edit-number'; `text-input`
  // alone → 'edit-text'). Otherwise the default per kind wins.
  if (c.lift.length > 0) {
    const mostEscalated = c.lift[c.lift.length - 1];
    // Defaults per most-escalated kind. Refined by placement + caps.
    if (mostEscalated === 'edit') {
      if (c.liftPlacement === 'plane') {
        c.liftSize = 'spacious';
        c.liftBackdrop = 'scrim';
        c.liftElevation = 'modal';
      } else if (c.liftPlacement === 'shadow') {
        c.liftSize = 'auto';
        c.liftBackdrop = 'none';
        c.liftElevation = 'elevated';
      } else {
        c.liftSize = 'comfortable';
        c.liftBackdrop = 'blur';
        c.liftElevation = 'elevated';
      }
      // Keyboard model: numeric editor (slider, number-input) vs
      // text editor vs picker. Caps decide.
      if (has('arrow-nudge') && has('text-input')) {
        c.liftKeyboardModel = 'edit-number';
      } else if (has('text-input') && !has('lift-edit')) {
        c.liftKeyboardModel = 'edit-text';
      } else if (
        has('text-input') &&
        has('lift-edit') &&
        !c.lift.includes('details')
      ) {
        // Bare text-input edit lift (no picker) — text editor.
        c.liftKeyboardModel = 'edit-text';
      } else {
        // Default for edit lifts: picker model (status, chips, etc.)
        c.liftKeyboardModel = 'pick';
      }
    } else if (mostEscalated === 'tools') {
      c.liftSize = 'compact';
      c.liftBackdrop = 'none';
      c.liftElevation = 'raised';
      c.liftKeyboardModel = 'pick';
    } else {
      // details / preview only — tooltip-light
      c.liftSize = 'compact';
      c.liftBackdrop = 'tint';
      c.liftElevation = 'raised';
      c.liftKeyboardModel = 'compose';
    }
  }

  // Commit-on-close — runs AFTER lift is determined so it can see
  // the actual lift surface. Only honored when there IS a lift to
  // close (otherwise "on-close" has no semantic anchor).
  if (has('commit-on-close') && c.lift.length > 0 && c.commit !== 'live') {
    c.commit = 'on-close';
  }

  // Hover-reveal sets the adornment.
  if (has('hover-reveal') && c.adornment === 'none') {
    c.adornment = 'hover';
  }

  // Resizable widget → resizable sizing.
  if (has('resizable')) {
    c.sizing = 'resizable';
  }

  // CQ-size widget → measured sizing (frame-style).
  if (has('cq-size')) {
    c.sizing = 'measured';
  }

  // No legacy expand-cell-to-fit shim — that capability was removed
  // in K.5 Phase 4. Wide-editor widgets now declare `lift-edit` and
  // the host picks `liftPlacement: 'shadow'` so the editor opens at
  // expanded width on the drop plane (visually overlapping the
  // source). Geometry is the host's call; the widget just declares
  // that it has an editor.

  return c;
}

/** Pass 3: parent surface policy.
 *  Apply the surface's overrides + drop forbidden capabilities
 *  retroactively (a widget that asked for `popover` but the
 *  surface forbids `popover` should fall back to inline). */
function applyParentPolicy(
  contract: Contract,
  caps: Capability[],
  policy: Policy | undefined,
): { contract: Contract; caps: Capability[] } {
  if (!policy) return { contract, caps };

  let nextCaps = caps;
  if (policy.permits || policy.forbids) {
    const permits = policy.permits ? new Set(policy.permits) : null;
    const forbids = new Set(policy.forbids ?? []);
    nextCaps = caps.filter((c) => {
      if (forbids.has(c)) return false;
      if (permits && !permits.has(c)) return false;
      return true;
    });
  }

  let nextContract = contract;
  if (policy.overrides) {
    nextContract = { ...contract, ...policy.overrides };
  }
  return { contract: nextContract, caps: nextCaps };
}

/** Pass 4: safety escalations.
 *  Hard rules that no override or policy can bypass.
 *
 *  - A modal plane MUST trap focus, block pointer, and route
 *    keyboard to modal.
 *  - A child with `text-input` MUST give the child keyboard. */
function applySafetyEscalations(
  contract: Contract,
  input: ContractNegotiationInput,
): Contract {
  let c = { ...contract };

  // Plane-placed lifts (and surfaces that ARE planes) trap focus,
  // block pointer, and route keyboard to modal. Same hard rule the
  // legacy `popup === 'plane'` check enforced — now driven by the
  // new `liftPlacement` field + the surface itself.
  const isPlane =
    (c.lift.length > 0 && c.liftPlacement === 'plane') ||
    input.childSurface === 'plane';
  if (isPlane) {
    c.focus = 'trapped';
    c.pointer = 'blocked';
    c.keyboard = 'modal';
    c.layer = 'modal';
    c.commit = c.commit === 'live' ? 'live' : 'explicit';
  }

  if (input.capabilities.includes('text-input')) {
    if (c.keyboard !== 'modal') c.keyboard = 'child-text';
  }

  return c;
}

/** Pass 5: instance overrides.
 *  Applied LAST so a single column / tile can refine a final
 *  dimension. Subject to safety: overrides cannot reverse a
 *  safety escalation (the safety pass runs BEFORE overrides
 *  conceptually but we re-apply safety after to make it true). */
function applyInstanceOverrides(
  contract: Contract,
  overrides: InstanceContractOverrides | undefined,
  input: ContractNegotiationInput,
): Contract {
  if (!overrides) return contract;
  const merged = { ...contract, ...overrides };
  // Re-run safety so an override can't unlock a plane.
  return applySafetyEscalations(merged, input);
}

// ─── public API: negotiate ────────────────────────────────────────

/**
 * The main entry point. Pure function; same input → same output.
 *
 * Pipeline:
 *   1. Look up base contract for (parent, child) — sharded across
 *      all registered tables, last-registered wins.
 *   2. Apply intent refinement (preview vs editor).
 *   3. Apply capability hints (widget shape).
 *   4. Apply parent surface policy (permits / forbids / overrides).
 *   5. Apply safety escalations (modal / text-input).
 *   6. Apply instance overrides + re-run safety.
 *
 * Stable shape — returns a NEW object every call (no aliasing).
 */
export function negotiateContract(input: ContractNegotiationInput): Contract {
  let contract = lookupBaseContract(input.parentSurface, input.childSurface);

  contract = applyIntent(contract, input);
  contract = applyCapabilities(contract, input.capabilities);
  const policyApplied = applyParentPolicy(
    contract,
    input.capabilities,
    input.parentPolicy,
  );
  contract = policyApplied.contract;
  // Capabilities may have been filtered by the policy — re-derive
  // from the filtered set so safety + overrides see the truth.
  const filteredCaps = policyApplied.caps;
  contract = applySafetyEscalations(contract, {
    ...input,
    capabilities: filteredCaps,
  });
  contract = applyInstanceOverrides(contract, input.instanceOverrides, {
    ...input,
    capabilities: filteredCaps,
  });

  return contract;
}

/**
 * Convenience entry point. Take a widget's `capabilities` array
 * (the new shape — `Capability[]`) and the surface pair,
 * negotiate the contract. Most callers use this rather than
 * `negotiateContract` directly because the parent/child
 * intent + capability propagation is the boilerplate.
 */
export function negotiateForWidget(args: {
  parentSurface: Surface;
  childSurface: Surface;
  parentIntent?: Intent;
  childIntent: Intent;
  widgetCapabilities: Capability[] | undefined;
  parentPolicy?: Policy;
  instanceOverrides?: InstanceContractOverrides;
}): Contract {
  return negotiateContract({
    parentSurface: args.parentSurface,
    parentIntent: args.parentIntent ?? 'editor',
    childSurface: args.childSurface,
    childIntent: args.childIntent,
    capabilities: args.widgetCapabilities ?? [],
    parentPolicy: args.parentPolicy,
    instanceOverrides: args.instanceOverrides,
  });
}
