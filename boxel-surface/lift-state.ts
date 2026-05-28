// `LiftState` — the per-host state machine that owns the
// currently-open lift's `(row, col, kind)` plus the hover-pause and
// dismiss-grace timers.
//
// THE PROBLEM
// ===========
//
// Every host that wants the K.4 hover-to-Details + click-to-Edit +
// escalation flow was reinventing the same ~150 lines of state in
// its component class:
//
//   - `@tracked liftTarget` — open-cell + kind
//   - `private hoverTimer` / `dismissTimer` — pending opens / dismisses
//   - `handleCellHoverEnter / Leave` — schedule open / dismiss
//   - `handleLiftHoverEnter / Leave` — cancel / schedule dismiss
//   - `openEditLift` / `cancelEdit` / `escalate` — explicit transitions
//   - `cancelHoverTimer` / `cancelDismissTimer` / `scheduleDismiss`
//
// All of it driven by the same desktop gesture model (hover ~500ms
// pauses → details opens; pointer leaves source + lift → 200ms
// grace; pointer enters lift → grace canceled; click → edit opens;
// escalate transitions kind without unmounting). Different hosts
// kept getting the timing slightly wrong.
//
// THIS FILE
// =========
//
// Lifts that out into one class. The host owns ONE instance per
// surface root (one open lift at a time, just like a spreadsheet's
// CellPopover), passes it to the `surfaceLiftBinding` modifier on each
// hover-target element (cell / node / frame / unit — any unit the
// host wants to be lift-able), and reads `state.target / state.kind
// / state.anchorSelector` to drive the `<Lift>` mount.
//
// Naming: NOT `CellLiftState`. The state machine is host-agnostic —
// canvas nodes and kanban cards lift the same way grid cells do.
// "Cell" is grid vocabulary; this file lives in `boxel-surface`
// where the only allowed concepts are surfaces, contracts, and
// intent declarations.
//
// Pure logic. No DOM, no Glimmer, no Ember resources. The companion
// `surfaceLiftBinding` modifier (in `modifiers/lift-binding.ts`) translates
// DOM events to method calls; the host's `<Lift>` template reads
// tracked properties for reactive opens / closes.
//
// LIFETIME
// ========
//
// One per surface root. Hosts construct it in their component
// constructor (or as a class field via `createLiftState({...})`)
// and call `destroy()` in `willDestroy()` if they want to be tidy
// about leftover timers. Leaking timers is bounded (200-500ms) and
// harmless — they fire into a stale `@tracked` setter — but the
// destroy hook is there for fastidious hosts and tests.

import { tracked } from '@glimmer/tracking';

import type { LiftKind, Contract } from './contracts.ts';

/** What the host needs to know about the open lift. Three fields:
 *  WHICH unit (row, col coordinates), WHICH kind, and the implicit
 *  "is anything open" derived from `target !== null`.
 *
 *  `row` / `col` are intentionally generic: a grid uses (rowIdx,
 *  colIdx); a canvas uses (nodeRow, nodeField); a kanban could use
 *  (laneIdx, cardIdx). The state doesn't care what they mean — only
 *  that the pair uniquely identifies the unit so the
 *  `anchorSelectorFor` callback can resolve a DOM element. */
export interface LiftTarget {
  row: number;
  col: number;
  kind: LiftKind;
}

export interface LiftStateOptions {
  /** Build the velcro anchor selector for the unit at (row, col).
   *  Defaults to `[data-row="${row}"][data-col="${col}"]` —
   *  override when the host scopes by id (e.g.,
   *  `[data-bx-grid="t1"] [data-row=...]`) or uses different
   *  attribute names. The selector must match exactly one element;
   *  velcro picks the first match if multiple match. */
  anchorSelectorFor?: (row: number, col: number) => string;

  /** Hover pause before opening the details lift. Filters out
   *  cursor flyovers (cursors that pass through a unit on the way
   *  to somewhere else). Tuned so deliberate hovers feel responsive
   *  but accidental ones don't trigger. ms. Default 500. */
  hoverPauseMs?: number;

  /** Grace window after `pointerleave` before dismissing the
   *  details lift. Lets the cursor travel from the source unit to
   *  the floating Lift element without losing it (the Lift cancels
   *  the dismiss on its own `pointerenter`). ms. Default 200. */
  dismissGraceMs?: number;

  /** After an explicit close (commit / cancel / outside-click),
   *  how long to suppress hover-opens in `scheduleHoverDetails`.
   *  Without this, closing an EDIT lift leaves the cursor over the
   *  source cell — the cell's pointerenter re-fires, schedules
   *  details, and a tooltip pops the user didn't ask for. The
   *  cooldown bridges the gap between the explicit close and the
   *  next intentional hover. ms. Default 600. */
  dismissCooldownMs?: number;
}

/** The open-lift state machine. See module docstring. */
export class LiftState {
  /** The currently-open lift's `(row, col, kind)`, or null when no
   *  lift is open. Tracked so templates re-render on transitions
   *  (open → close, kind change, target change). */
  @tracked target: LiftTarget | null = null;

  private hoverTimer: ReturnType<typeof setTimeout> | null = null;
  private dismissTimer: ReturnType<typeof setTimeout> | null = null;
  /** Timestamp of the most-recent explicit close (commit / cancel /
   *  dismiss). `scheduleHoverDetails` checks this against `dismissCooldownMs`
   *  to suppress immediate re-opens. Without this, closing an EDIT lift
   *  (the cursor is still over the source cell because the lift was
   *  covering it) would trigger pointerenter on the cell underneath
   *  → schedule hover details → 500ms later a details lift pops open
   *  the user didn't ask for. */
  private lastClosedAt = 0;

  private opts: Required<LiftStateOptions>;

  constructor(opts: LiftStateOptions = {}) {
    this.opts = {
      anchorSelectorFor: opts.anchorSelectorFor ?? defaultAnchorSelectorFor,
      hoverPauseMs: opts.hoverPauseMs ?? 500,
      dismissGraceMs: opts.dismissGraceMs ?? 200,
      dismissCooldownMs: opts.dismissCooldownMs ?? 600,
    };
  }

  // ─── reactive queries (host reads these from templates) ──────────

  /** True when any lift is open (any unit, any kind). */
  get isOpen(): boolean {
    return this.target !== null;
  }

  /** The open lift's kind, or null if nothing is open. Templates
   *  use this to switch between Details and Edit content. */
  get kind(): LiftKind | null {
    return this.target?.kind ?? null;
  }

  /** Velcro anchor selector for the open lift, or `''` if nothing
   *  is open. Pass directly to
   *  `<Lift @anchor={{state.anchorSelector}}>`. */
  get anchorSelector(): string {
    if (!this.target) return '';
    return this.opts.anchorSelectorFor(this.target.row, this.target.col);
  }

  /** True if the lift is open AND it points at this exact unit.
   *  Used by per-unit chrome (e.g., `<LiftChevron>`) that needs to
   *  know "is the lift open on ME, specifically." */
  isOpenFor(row: number, col: number): boolean {
    return (
      this.target !== null && this.target.row === row && this.target.col === col
    );
  }

  // ─── transitions (modifier + host call these) ────────────────────

  /** Open the details lift on (row, col). Cancels any pending
   *  hover-open or dismiss timers. Idempotent — calling on the
   *  already-open unit is a no-op. */
  openDetails = (row: number, col: number): void => {
    this.cancelHoverTimer();
    this.cancelDismissTimer();
    this.target = { row, col, kind: 'details' };
  };

  /** Open the edit lift on (row, col). Cancels any pending hover /
   *  dismiss timers. The host typically calls this from explicit
   *  edit gestures (chevron click, dblclick, Enter, F2). Idempotent. */
  openEdit = (row: number, col: number): void => {
    this.openLift(row, col, 'edit');
  };

  /** Open the tools lift on (row, col). Tools lifts host action
   *  menus / command palettes — see the `actions` widget. Same
   *  dispatch shape as openEdit; the host picks which to call based
   *  on the unit's negotiated `contract.lift` (tools-only widgets
   *  go through this path). */
  openTools = (row: number, col: number): void => {
    this.openLift(row, col, 'tools');
  };

  /** Generic open-by-kind. Hosts that want to dispatch dynamically
   *  from `contract.lift` (e.g. "open whichever kind the widget
   *  declared most-escalated") call this directly:
   *
   *    const kind = contract.lift[contract.lift.length - 1];
   *    if (kind) this.liftState.openLift(rowIdx, colIdx, kind);
   *
   *  Adding a new lift kind to the system becomes a one-line change
   *  on the widget side (declare the cap), the contract side (cap →
   *  lift kind in the negotiator), and the lift CSS side (a
   *  `.bx-lift--<kind>` rule). No new method to wire on LiftState,
   *  no new dispatch branch in the host. `openEdit` / `openTools` /
   *  `openDetails` stay as named conveniences for callers that
   *  always know the kind statically. */
  openLift = (row: number, col: number, kind: LiftKind): void => {
    this.cancelHoverTimer();
    this.cancelDismissTimer();
    this.target = { row, col, kind };
  };

  /** Schedule details to open on (row, col) after the hover pause.
   *  Bails out if the unit's contract doesn't list `'details'` in
   *  `lift[]`, or if an edit lift is already open (the user is
   *  committed to editing — no peeks). The companion modifier
   *  calls this on `pointerenter`. */
  scheduleHoverDetails = (
    row: number,
    col: number,
    contract: Contract,
  ): void => {
    if (!contract.lift.includes('details')) return;
    // If edit is already open (any unit), don't peek — the user is
    // committed to editing.
    if (this.target?.kind === 'edit') return;
    // Dismiss-cooldown: after an explicit close (commit / cancel /
    // outside-click), suppress hover-opens for a brief window. Without
    // this, closing an EDIT lift leaves the cursor over the source
    // cell (the lift was covering it); the cell's pointerenter would
    // re-fire → schedule details → ~500ms later a tooltip pops the
    // user didn't ask for. The cooldown bridges the close → next
    // intentional hover gap.
    if (
      this.lastClosedAt > 0 &&
      Date.now() - this.lastClosedAt < this.opts.dismissCooldownMs
    ) {
      return;
    }
    this.cancelHoverTimer();
    this.cancelDismissTimer();
    this.hoverTimer = setTimeout(() => {
      this.hoverTimer = null;
      // Re-check after the wait — the user may have clicked, opened
      // edit, or moved focus mid-pause.
      if (this.target?.kind === 'edit') return;
      this.target = { row, col, kind: 'details' };
    }, this.opts.hoverPauseMs);
  };

  /** Cancel a pending hover-to-details timer; if a details lift IS
   *  open, schedule a dismiss after the grace window. Used by both
   *  source-pointerleave and lift-pointerleave — the dismiss only
   *  fires if neither the source nor the lift cancels it via
   *  `cancelDismiss()` first. */
  scheduleDismissDetails = (): void => {
    this.cancelHoverTimer();
    if (this.target?.kind !== 'details') return;
    this.cancelDismissTimer();
    this.dismissTimer = setTimeout(() => {
      this.dismissTimer = null;
      if (this.target?.kind === 'details') this.target = null;
    }, this.opts.dismissGraceMs);
  };

  /** Cancel a pending dismiss — pointer entered the lift element
   *  before the grace expired, so the user is reading the details. */
  cancelDismiss = (): void => {
    this.cancelDismissTimer();
  };

  /** Switch the open lift's kind without closing it. Same anchor,
   *  different content — the `<Lift>` re-renders its body without
   *  unmounting. Used for details ↔ edit escalation from inside
   *  the lift body or its toolbar. No-op if no lift is open. */
  escalate = (kind: LiftKind): void => {
    if (!this.target) return;
    this.target = { ...this.target, kind };
  };

  /** Close the lift. Cancels all pending timers. Used for explicit
   *  dismissals (Esc, click-out, commit, cancel). Stamps `lastClosedAt`
   *  so `scheduleHoverDetails` can suppress immediate hover re-opens
   *  (the cursor is still over the source cell because the lift was
   *  covering it; the unmount triggers a synthetic pointerenter). */
  close = (): void => {
    this.cancelHoverTimer();
    this.cancelDismissTimer();
    this.target = null;
    this.lastClosedAt = Date.now();
  };

  // ─── teardown ────────────────────────────────────────────────────

  /** Cancel any pending timers. Hosts call this from `willDestroy()`
   *  to keep teardown tidy. Safe to call multiple times. */
  destroy(): void {
    this.cancelHoverTimer();
    this.cancelDismissTimer();
  }

  // ─── internals ───────────────────────────────────────────────────

  private cancelHoverTimer(): void {
    if (this.hoverTimer != null) {
      clearTimeout(this.hoverTimer);
      this.hoverTimer = null;
    }
  }

  private cancelDismissTimer(): void {
    if (this.dismissTimer != null) {
      clearTimeout(this.dismissTimer);
      this.dismissTimer = null;
    }
  }
}

/** Default anchor selector — every host's body unit stamps
 *  `data-row="N"` and `data-col="N"`. Override via
 *  `LiftStateOptions.anchorSelectorFor` when the host scopes by id
 *  (multiple grids on one page, multiple canvases stacked) or uses
 *  a different attribute scheme. */
function defaultAnchorSelectorFor(row: number, col: number): string {
  return `[data-row="${row}"][data-col="${col}"]`;
}

/** Factory — mirrors `createFocusLadder()`. Use as a class field
 *  in your host component:
 *
 *    liftState = createLiftState({
 *      anchorSelectorFor: (r, c) =>
 *        `[data-bx-grid="t1"] [data-row="${r}"][data-col="${c}"]`,
 *    });
 *
 *  The instance is reactive — templates that read `state.target /
 *  kind / isOpen / anchorSelector` re-render on transitions. */
export function createLiftState(opts: LiftStateOptions = {}): LiftState {
  return new LiftState(opts);
}
