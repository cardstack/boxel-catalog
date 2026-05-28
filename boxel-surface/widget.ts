import type { ComponentLike } from '@glint/template';
import type { Capability } from './contracts.ts';

/**
 * Widget — the bundle of components that can render a typed value
 * across multiple **surfaces** (where it lives) and **intents**
 * (preview vs editor).
 *
 * See `WIDGET-NOMENCLATURE.md` for the full grammar. Quick recap:
 *
 *   surfaces:  prose · cell · layout · popover
 *   intents:   preview · editor
 *
 * Each `(surface, intent)` cell of the matrix is independently
 * optional. Most widgets fill 2–4 cells; pure read-only ones fill
 * just `cell.preview`; rich widgets like a date picker fill all
 * four corners (cell preview + cell editor + popover preview +
 * popover editor).
 *
 * Address pattern in code:
 *
 *   widget.cell.preview         → CellPreview component
 *   widget.cell.editor          → in-cell typing editor
 *   widget.pane.editor       → lifted full editor
 *   widget.run.preview        → inline chip / link
 *
 * Widgets are keyed by **presentation choice**, not by data type.
 * `widgets.checkbox` and `widgets.toggle` both serve `boolean`;
 * `widgets.text` and `widgets.statusPill` both serve `string`.
 * Multiple widgets per data type is the expected case.
 */
export interface Widget<TValue> {
  run?: Variants<TValue>;
  /** Single-value rendering — the most common case. The widget
   *  renders ONE value as one component (a toggle, a pill, a stars
   *  rating, a date). Used when the surface contract resolves to
   *  a `unit` child. The unit IS the focusable + selectable control.
   *  See `Surface` in this file for the unit-vs-cell topology
   *  rules. */
  unit?: Variants<TValue>;
  /** Multi-unit grouping container — only used when the widget
   *  declares the `multi-unit` capability. The cell slot renders the
   *  OUTER wrapper (flex layout, "+" add button, comma separators)
   *  around descendants marked with `data-unit-key`. Single-unit
   *  widgets do not need this slot — their topology collapses to
   *  `unit`. */
  cell?: Variants<TValue>;
  layout?: Variants<TValue>;
  pane?: Variants<TValue>;

  /** Capability hints this widget declares — small, English-readable
   *  facts about the widget's nature ('text-input', 'popover',
   *  'live-write', etc.). The host passes them to
   *  `negotiateForWidget()` to refine the surface contract for this
   *  widget × surface pair. See `surface-contracts.ts` for the full
   *  vocabulary. Optional — widgets without this get the parent's
   *  default contract (still functional, just less tailored). */
  capabilities?: Capability[];
}

/**
 * The two-intent record for one surface. Both `preview` and `editor`
 * are optional — a widget may have either, both, or neither at any
 * given surface.
 *
 * `placement` and `placementFallbacks` are positioning hints for the
 * pane surface specifically. A consumer that mounts the pane in a
 * popover (e.g., the grid host's CellPopover) should honor these so
 * widgets that need lots of vertical space (image with crop, calendar
 * grid, multi-select picker) can declare `'right-start'` or whatever
 * fits their shape, instead of defaulting to `'bottom-start'` which
 * may flip awkwardly. For non-popover mounts (sidebar, full screen),
 * the host can ignore these hints.
 *
 * Examples (text widget):
 *   widget.cell    = { preview: TextCellPreview, editor: TextCellEditor }
 *   widget.pane    = { editor: TextPaneEditor }
 *
 * Examples (statusPill widget):
 *   widget.cell    = { preview: StatusPillCellPreview }
 *                       (no cell.editor — typing makes no sense for a status)
 *   widget.pane    = { editor: StatusDropdown }
 *
 * Examples (image widget — large pane):
 *   widget.cell    = { preview: ImageView }
 *   widget.pane    = { editor: ImageView, placement: 'right-start',
 *                       placementFallbacks: ['left-start','bottom-start'] }
 *
 * Examples (checkbox widget — Pattern B, atom-as-editor):
 *   widget.cell    = { preview: CheckboxLive }
 *                       (preview takes optional onCommit and IS the editor)
 */
export interface Variants<TValue> {
  preview?: ComponentLike<{
    Args: PreviewArgs<TValue>;
    Element: HTMLElement;
  }>;
  editor?: ComponentLike<{
    Args: EditorArgs<TValue>;
    Element: HTMLElement;
  }>;
  /** Escape-hatch editor — a less-strict variant the strict `editor`
   *  can hand off to (via `args.onEscalate?.()`). Same lift LEVEL —
   *  the host swaps the inner editor in place; the surrounding
   *  cell-lift / popover-lift surface stays mounted.
   *
   *  Use case: toggle's strict picker (true / false buttons) hands
   *  off to a raw `<input type=text>` that accepts ANY string —
   *  even invalid for the column's expected type. The cell stores
   *  the string verbatim; downstream consumers can flag the
   *  mismatch (Excel-style "value of wrong type" warning) without
   *  preventing entry.
   *
   *  Paired with the `escape-to-raw` trait — without that trait in
   *  the negotiated set, the host won't expose `onEscalate` and
   *  this slot is dormant. */
  rawEditor?: ComponentLike<{
    Args: EditorArgs<unknown>;
    Element: HTMLElement;
  }>;
  /** Floating-UI placement hint, used when this surface is mounted
   *  as a popover. Mirrors `@floating-ui/dom`'s `Placement` type:
   *  `'top'` / `'bottom'` / `'left'` / `'right'` plus optional
   *  `-start` / `-end` alignment suffix. Default `'bottom-start'`. */
  placement?: PanePlacement;
  /** Fallback placements to try when the preferred one overflows the
   *  viewport (passed to the `flip` middleware). Default lets
   *  floating-ui pick. */
  placementFallbacks?: PanePlacement[];
  /** Minimum pixel width the editor needs to render comfortably.
   *  Paired with the `expand-cell-to-fit` trait — when that trait is
   *  active and the cell's actual width is less than this hint, the
   *  host lifts the cell to this width by floating an editor shell
   *  over the cell + neighboring columns (z-index above; cell stays
   *  in its grid track). When the trait is forbidden by the surface
   *  OR the cell already meets the min, this is ignored.
   *
   *  Distinct from the popover-lift surface (`pane.editor`): cell-lift
   *  has no chrome, is anchored at the cell's own bounding box, and
   *  is the same TYPE of editor — just bigger. Use for widgets whose
   *  inline editor needs more room than dense columns provide
   *  (slider + number + stepper, color swatch + hex, etc.). */
  minEditorWidth?: number;

  /** Preferred pixel width when this surface mounts as a popover.
   *  Static counterpart to the dynamic `requestPopoverSize` channel
   *  on `EditorArgs`. Read by hosts at popover open time; widgets
   *  that need a different width MID-EDIT use `requestPopoverSize`
   *  instead.
   *
   *  Use case: toggle's strict picker (true / false / "abc" custom)
   *  reads comfortably at ~200px. The cell itself may be 80-100px,
   *  but the popover lifts free of the cell's track so it can size
   *  to the widget's preference. */
  preferredPopoverWidth?: number;
}

/**
 * Subset of `@floating-ui/dom`'s `Placement` type — inlined here to
 * avoid a hard dependency from the widgets package on the positioning
 * library. Hosts that use a different positioning library can map these
 * strings to their own equivalents.
 */
export type PanePlacement =
  | 'top'
  | 'top-start'
  | 'top-end'
  | 'bottom'
  | 'bottom-start'
  | 'bottom-end'
  | 'left'
  | 'left-start'
  | 'left-end'
  | 'right'
  | 'right-start'
  | 'right-end';

/**
 * The standard contract for any preview component.
 *
 * `value` is the read-only display value.
 *
 * `onCommit` is OPTIONAL — most preview components are pure display
 * and ignore it. Pattern B widgets (checkbox, toggle, slider) take
 * `onCommit` and ARE their own editor: clicking the atom toggles
 * the value with no separate edit mode. The bundle expresses this
 * by providing only `widget.cell.preview` (no `editor` slot) — the
 * dispatcher renders the preview and the consumer wires `onCommit`.
 *
 * `intent` is OPTIONAL — present when the same component is shared
 * across preview AND editor slots (Pattern D, e.g., an image-with-
 * crop component). The component reads `intent` to switch internal
 * mode.
 */
export interface PreviewArgs<TValue> {
  value: TValue;
  onCommit?: (next: TValue) => void;
  intent?: 'preview';
}

/**
 * The standard contract for any editor component.
 *
 * `value` is the current value.
 *
 * `initialValue` is the seed for "type-to-edit" (when the user
 * starts editing by pressing a printable key, the keystroke is
 * passed through as the initial input) or for "Backspace-to-clear"
 * (initial value is empty string). When absent, the editor seeds
 * itself from `value`.
 *
 * `onCommit` writes the new value. The optional second arg
 * `advance` is a focus-direction hint for grid hosts — Enter →
 * 'down', Tab → 'right', Shift+Tab → 'left'. Form hosts ignore it.
 *
 * `onCancel` discards any in-progress edit and exits edit mode.
 *
 * `intent` is OPTIONAL — same Pattern D rationale as PreviewArgs.
 */
export interface EditorArgs<TValue> {
  value: TValue;
  initialValue?: string;
  onCommit: (next: TValue, advance?: EditAdvance) => void;
  onCancel: () => void;
  intent?: 'editor';

  /** Optional escalation handle — supplied by the host when the
   *  widget declared the `escape-to-raw` trait AND the surface
   *  permits it. The (strict) editor calls this when the user
   *  triggers the escape gesture (e.g., clicks an "abc" / "Raw…"
   *  link inside the editor). The host swaps the inner editor for
   *  the widget's `cell.rawEditor` (or equivalent) — same lift
   *  surface, less-strict variant. The widget doesn't need to know
   *  whether the host honored the request; it's fire-and-forget. */
  onEscalate?: () => void;

  /** Optional preview channel — supplied by the host when the cell
   *  preview should mirror in-flight editor state. The widget calls
   *  this with the value the user is currently CONSIDERING (not
   *  committed yet) so the source cell can show a transparent /
   *  semi-opaque preview. Pass `null` to clear the preview.
   *
   *  Use case: pill's keyboard cursor on `idle` → calls
   *  `onPreviewChange?.('idle')` so the cell renders a faded `idle`
   *  pill before the user commits. Esc clears (no commit); Enter
   *  commits and the cell snaps to full opacity. */
  onPreviewChange?: (next: TValue | null) => void;

  /** Optional dynamic-resize channel — supplied by the host when the
   *  surface mount supports runtime resizing (e.g., a popover
   *  surface mounted via floating-ui). The widget calls this when
   *  its INTERNAL state changes shape and the host should re-size
   *  the surface to match. Pass `null` to revert to the static
   *  `preferredPopoverWidth` (or natural sizing).
   *
   *  Use case: calendar's strict editor wants ~320px (full month
   *  grid), but its raw editor (mm/dd/yyyy text) wants ~240px. On
   *  escalation strict→raw, calendar calls
   *  `requestPopoverSize?.({ width: 240 })` so the popover snaps
   *  smaller. On demote raw→strict, it calls back with `null` (or
   *  320) to grow again.
   *
   *  Distinct from `preferredPopoverWidth` (static, declared on
   *  `Variants` at module-init). This is for dynamic
   *  intra-editor changes. */
  requestPopoverSize?: (
    size: { width?: number; height?: number } | null,
  ) => void;
}

/**
 * Direction the focused cell should advance after a commit. Editors
 * MAY pass this; hosts MAY use it. Spreadsheet idiom — Enter advances
 * down, Tab advances right, Shift+Tab advances left, Esc cancels
 * (no commit, so no advance), 'stay' means the editor committed
 * without an opinion on focus direction (e.g., committed via
 * click-out).
 *
 * Form hosts that don't care about cursor direction ignore this.
 */
export type EditAdvance = 'up' | 'down' | 'left' | 'right' | 'stay';

/** Every kind of rendering context that participates in surface
 *  contract negotiation. The union groups two layers:
 *
 *    WIDGET-OWNED slots (where a Widget declares variants):
 *      'run'    — inline prose token (chip in flowing text)
 *      'unit'   — single-value unit inside a slot. The DEFAULT for
 *                 most widgets — one toggle, one pill, one stars.
 *                 The unit IS the focusable + selectable thing;
 *                 the slot it lives in has no separate identity.
 *                 (Named to avoid collision with Boxel's
 *                 "atom format" card-render concept.)
 *      'cell'   — multi-unit container (tag list, mention list,
 *                 image with annotation pins). Only present when
 *                 the widget declares `multi-unit`. A cell
 *                 wraps many units; otherwise the layer collapses
 *                 and the widget renders directly as `unit`.
 *      'layout' — form / card-edit context (multi-field arrangement)
 *      'pane'   — contained editor (popover, sheet, side panel)
 *
 *    HOST-LEVEL contexts (where a Widget DOESN'T declare variants
 *    but contracts ARE negotiated for parent/child pairs):
 *      'grid'   — spreadsheet / data table
 *      'scroll' — bounded scrolling region
 *      'flow'   — ordered stream / process / conversation
 *      'outline' — hierarchical navigation or document outline
 *      'canvas' — infinite canvas (xyflow / Figma-style)
 *      'scene'  — 3D scene host (Lume-backed or equivalent)
 *      'frame'  — measured container (Boxel fitted card)
 *      'plane'  — full-viewport modal
 *
 *  UNIT vs CELL — when does each appear?
 *  =====================================
 *  Single-unit widget (everything default): topology collapses the
 *  cell layer. `frame > layout > unit`, `grid > unit`. The unit is
 *  the unit of focus / selection / keyboard.
 *
 *  Multi-unit widget (declares `multi-unit`): cell wraps the group
 *  of units. `frame > layout > cell > unit`. The cell is the outer
 *  group; inner units are accessed via descend.
 *
 *  `Widget<T>` only declares slots for the WIDGET-OWNED tier
 *  (`run`, `unit`, `cell`, `layout`, `pane`) — those are the
 *  surfaces where component code lives. HOST-LEVEL surfaces are
 *  pure contract endpoints: a `grid` parent looks up its
 *  `grid>unit` contract and routes the unit content to the widget.
 *
 *  This split is why the contract lookup tables can have keys like
 *  `'grid>unit'` even though no widget declares a `grid` slot. */
export type Surface =
  // Primary surfaces (organize content)
  | 'space'
  | 'canvas'
  | 'scene'
  | 'grid'
  | 'row'
  | 'layout'
  | 'scroll'
  | 'flow'
  | 'outline'
  | 'connection'
  // Control surfaces (operate things)
  | 'frame'
  | 'pane'
  | 'plane'
  | 'cell'
  | 'run'
  | 'unit';

/** The two intents. Same notes as `Surface`. */
export type WidgetIntent = 'preview' | 'editor';
