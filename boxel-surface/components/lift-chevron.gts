import Component from '@glimmer/component';
import { fn } from '@ember/helper';
import { on } from '@ember/modifier';

import type { LiftState } from '../lift-state.ts';
import type { Contract } from '../contracts.ts';

/**
 * `<LiftChevron>` — the small ▾ glyph that signals "this unit has
 * a lift behind it" and acts as the explicit edit-open gesture.
 *
 * Naming: NOT `<CellChevron>`. The chevron is host-agnostic — a
 * canvas node or kanban card that supports an edit lift gets the
 * same affordance. Lives in `boxel-surface` where the only allowed
 * concepts are surfaces, contracts, and intent declarations.
 *
 * THE PROBLEM
 * ===========
 *
 * Every host that wired the K.4 hover-to-Details + click-to-Edit
 * flow was hand-rolling the same ~30 lines of template + CSS for
 * the chevron affordance: an absolute-positioned button in the
 * unit's right edge, three opacity tiers (rest / unit-hover /
 * unit-focused / chevron-hover / lift-open), keyboard outline,
 * click handler that calls `state.openEdit(row, col)`. The
 * widget-lab template used `widget-lab__bx-cell-lift-btn`; the
 * future grid-demo, kanban host, calendar host would each
 * reinvent it.
 *
 * THIS COMPONENT
 * ==============
 *
 * Pure visual + click affordance. Reads `contract.lift[]` to
 * decide whether to render at all (units without `'edit'` in the
 * lift chain don't get a chevron — Pattern A/B widgets like
 * toggle / stars). Reads `state.isOpenFor(row, col)` so the
 * chevron stays lit while its lift is open (otherwise a hover-
 * bounce would re-fade it to 60%). On click, calls
 * `state.openEdit(row, col)` — same as the unit's dblclick / Enter
 * / F2 path, just with explicit pointer intent.
 *
 * VISUAL TIERS (from quietest to loudest)
 * =======================================
 *
 *   rest           opacity 0          (hidden — keep units clean)
 *   unit hover     opacity 0.35 gray  (discovery — provided by host
 *                                      CSS or Step E's cell-chrome
 *                                      stylesheet)
 *   unit focused   opacity 0.60 indigo (ready — same host source)
 *   chevron hover  opacity 1.0  indigo + bg (the click target)
 *   lift open      opacity 1.0  indigo + bg (commit signal)
 *
 * The component owns the FIRST and LAST TWO tiers (rest baseline
 * + chevron hover + lift open + focus-visible outline). The
 * unit-hover and unit-focused tiers come from a parent rule on
 * `.bx-cell` (or whatever the host calls its lift-target unit) —
 * the host (or Step E's shared `cell-chrome.css`) provides them
 * via descendant selectors. This split lets the chevron travel
 * without a CSS dependency: drop `<LiftChevron>` into any
 * container, the click + lift-open visibility works; pair with
 * `bx-cell` (or your own equivalent) to get the full five-tier
 * ladder.
 *
 * Splattributes are forwarded so consumers can add `data-*` test
 * hooks, additional classes, or override styles via `class=`.
 */
export interface LiftChevronSignature {
  Element: HTMLButtonElement;
  Args: {
    /** The shared lift state. The chevron clicks call
     *  `state.openEdit(row, col)`; reading `state.isOpenFor(row, col)`
     *  drives the lift-open tier. */
    state: LiftState;
    /** This unit's contract. The chevron renders only when
     *  `contract.lift.includes('edit')` — no chevron on Pattern
     *  A/B units without an edit lift. */
    contract: Contract;
    /** Unit coordinates. Threaded into `state.openEdit` and
     *  `state.isOpenFor`. */
    row: number;
    col: number;
    /** Override the button's `aria-label` and `title`. Default
     *  is `'Open editor'`. */
    label?: string;
  };
}

export default class LiftChevron extends Component<LiftChevronSignature> {
  /** Render gate. Units whose contract doesn't list `'edit'` in
   *  the lift chain (Pattern A/B widgets) don't get a chevron —
   *  there's nothing to escalate to. */
  get supportsEdit(): boolean {
    return this.args.contract.lift.includes('edit');
  }

  /** True when the lift is open AND points at THIS unit. Drives
   *  the loudest tier (full opacity + indigo + bg) so the
   *  chevron stays visible while the user is editing. */
  get isOpen(): boolean {
    return this.args.state.isOpenFor(this.args.row, this.args.col);
  }

  /** Accessible label. Override via `@label` for hosts that want
   *  a more specific verb (e.g., `'Pick a date'`, `'Choose tags'`). */
  get label(): string {
    return this.args.label ?? 'Open editor';
  }

  <template>
    {{#if this.supportsEdit}}
      <button
        type='button'
        class='bx-lift-chevron {{if this.isOpen "is-lift-open"}}'
        aria-label={{this.label}}
        title={{this.label}}
        {{on 'click' (fn @state.openEdit @row @col)}}
        ...attributes
      >▾</button>
    {{/if}}

    <style scoped>
      /* The chevron glyph. Positioned absolutely in the unit's
       * right edge, so the parent unit needs `position: relative`
       * (provided by `.bx-cell` in cell-chrome.css, or by the
       * host's own styles). 16x16 keeps it small enough to live
       * inside a row-height unit without crowding content. */
      .bx-lift-chevron {
        position: absolute;
        right: 4px;
        top: 50%;
        transform: translateY(-50%);
        width: 16px;
        height: 16px;
        padding: 0;
        border: none;
        border-radius: 3px;
        background: transparent;
        color: var(--bx-lift-chevron-color, #9ca3af);
        font-size: 11px;
        line-height: 1;
        cursor: pointer;
        display: flex;
        align-items: center;
        justify-content: center;
        opacity: 0;
        transition:
          opacity 80ms,
          background 80ms,
          color 80ms;
      }
      /* Lift-open + chevron-hover both promote to the loudest
       * tier — full opacity, indigo accent, soft bg. !important
       * so the unit-hover / unit-focused tiers (provided by a
       * parent rule) can't lower us back. */
      .bx-lift-chevron.is-lift-open,
      .bx-lift-chevron:hover {
        opacity: 1 !important;
        background: var(--bx-lift-chevron-hover-bg, rgba(99, 102, 241, 0.12));
        color: var(--bx-lift-chevron-hover-color, #4f46e5) !important;
      }
      /* Keyboard focus — visible outline so the affordance is
       * reachable + visible without a mouse. */
      .bx-lift-chevron:focus-visible {
        outline: 2px solid var(--bx-lift-chevron-hover-color, #4f46e5);
        outline-offset: 1px;
        opacity: 1;
      }
    </style>
  </template>
}
