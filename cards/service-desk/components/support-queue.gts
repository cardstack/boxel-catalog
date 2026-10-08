import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { Button } from '@cardstack/boxel-ui/components';
import ChevronRight from '@cardstack/boxel-icons/chevron-right';

import { BreachRing } from './breach-ring';
import { LiveClock } from './live-clock';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import {
  timerSnapshot,
  sortByUrgency,
} from '@cardstack/catalog/cards/service-desk/utils/sla';
import { type Hue } from '@cardstack/catalog/components/state-pill';

export interface QueueRow {
  card: any;
  label?: string;
  /** The row's most urgent timer facts (SlaTimerField-shaped), if any. */
  timerFacts?: any;
  /** Chip label + hue, e.g. severity or priority. */
  chipLabel?: string;
  chipHue?: Hue;
  ownerName?: string;
}

interface Signature {
  Args: {
    rows: QueueRow[];
    /** Open the row's card (a real open — a new stack item). */
    onOpen: (card: any) => void;
    /** Claim an unassigned row (Assign Owner, how: claimed). */
    onClaim?: (card: any) => void;
    /** The multi-select feeds Batch Transform: (operation, cards). */
    onBatch?: (operation: string, cards: any[]) => void;
    batchOperations?: { id: string; label: string }[];
  };
  Element: HTMLElement;
}

/**
 * Support Queue — the OPS layer the agent-side `queue-view`
 * deliberately lacks: nearest-breach sort, a breach ring per row, and a
 * multi-select whose bulk bar feeds Batch Transform (per-item results,
 * refusals reported).
 *
 * BUILDS ON, never forks: sorting is `utils/sla.urgencyRank` — the same
 * function the ServiceDesk queue console uses — so the two surfaces can
 * never rank a ticket differently. Rows arrive prepared by the caller
 * (`QueueRow`), so the component stays domain-neutral: a case, an invoice, a
 * demo card all queue alike.
 */
export class SupportQueue extends GlimmerComponent<Signature> {
  rowStyle = (i: number) => `--i: ${i};`;

  @tracked selectedIds: Set<string> = new Set();

  get rows() {
    return sortByUrgency(this.args.rows ?? [], (r) => r.timerFacts);
  }

  get selectedRows() {
    return this.rows.filter((r) => this.selectedIds.has(r.card?.id));
  }

  get operations() {
    return (
      this.args.batchOperations ?? [
        { id: 'assign-owner', label: 'Reassign' },
        { id: 'run-workflow', label: 'Move state' },
        { id: 'archive', label: 'Archive' },
      ]
    );
  }

  countdown = (row: QueueRow) => timerSnapshot(row.timerFacts ?? {}).shortLabel;
  countdownState = (row: QueueRow) => timerSnapshot(row.timerFacts ?? {}).state;

  toggle = (row: QueueRow, ev: Event) => {
    ev.stopPropagation();
    let next = new Set(this.selectedIds);
    let id = row.card?.id;
    if (next.has(id)) next.delete(id);
    else next.add(id);
    this.selectedIds = next;
  };

  isSelected = (row: QueueRow) => this.selectedIds.has(row.card?.id);

  open = (row: QueueRow) => this.args.onOpen?.(row.card);
  claim = (row: QueueRow, ev: Event) => {
    ev.stopPropagation();
    this.args.onClaim?.(row.card);
  };
  batch = (opId: string) => {
    this.args.onBatch?.(
      opId,
      this.selectedRows.map((r) => r.card),
    );
    this.selectedIds = new Set();
  };

  <template>
    <div class='queue' ...attributes>
      {{#if this.selectedRows.length}}
        <div class='bulkbar'>
          <b class='bulk-count'>{{this.selectedRows.length}} selected</b>
          <span class='bulk-spacer'></span>
          {{#each this.operations as |op|}}
            <Button
              @size='small'
              {{on 'click' (fn this.batch op.id)}}
            >{{op.label}}</Button>
          {{/each}}
          <span class='bulk-note'>→ Batch Transform · per-item results, refusals
            reported</span>
        </div>
      {{/if}}
      {{#each this.rows as |row idx|}}
        <div class='qrow-wrap' style={{this.rowStyle idx}}>
          {{#if @onBatch}}
            <input
              type='checkbox'
              class='qrow-cb'
              checked={{this.isSelected row}}
              aria-label='Select {{if row.label row.label row.card.title}}'
              {{on 'change' (fn this.toggle row)}}
            />
          {{/if}}
          <button type='button' class='qrow' {{on 'click' (fn this.open row)}}>
            {{#if row.timerFacts}}
              <BreachRing @facts={{row.timerFacts}} @size={{22}} />
            {{/if}}
            <span class='qrow-title'>{{if
                row.label
                row.label
                row.card.title
              }}</span>
            {{#if row.chipLabel}}
              <StatePill @label={{row.chipLabel}} @hue={{row.chipHue}} />
            {{/if}}
            <span class='qrow-owner {{unless row.ownerName "qrow-unowned"}}'>
              {{if row.ownerName row.ownerName 'unassigned'}}
            </span>
            {{#if row.timerFacts}}
              <LiveClock @facts={{row.timerFacts}} class='qrow-clock' />
            {{else}}
              <span class='qrow-clock qrow-clock-none'>—</span>
            {{/if}}
            {{#if @onClaim}}
              {{#unless row.ownerName}}
                <Button
                  @size='extra-small'
                  class='hit-ext'
                  {{on 'click' (fn this.claim row)}}
                >Claim</Button>
              {{/unless}}
            {{/if}}
            <ChevronRight
              class='qrow-cue'
              role='presentation'
              width='14'
              height='14'
            />
          </button>
        </div>
      {{else}}
        <p class='queue-clear'>✓ Queue clear — no breach risk.</p>
      {{/each}}
    </div>
    <style scoped>
      /* WCAG 2.5.8: the drawn control stays compact, the hit area is ~44px tall. */
      .hit-ext {
        position: relative;
      }
      .hit-ext::after {
        content: '';
        position: absolute;
        inset: -0.625rem 0;
      }
      .queue {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-4xs);
      }
      .bulkbar {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        flex-wrap: wrap;
        border: 1px solid var(--primary, var(--boxel-highlight));
        border-radius: var(--boxel-border-radius);
        background: color-mix(
          in oklab,
          var(--primary, var(--boxel-highlight)) 8%,
          var(--card, var(--boxel-light))
        );
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
      }
      .bulk-count {
        font-variant-numeric: tabular-nums;
      }
      .bulk-spacer {
        flex: 1;
      }
      .bulk-note {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground, var(--boxel-450));
      }
      .qrow-wrap {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-4xs);
      }
      .qrow-cb {
        flex: none;
        width: 0.9375rem;
        height: 0.9375rem;
        accent-color: var(--primary, var(--boxel-highlight));
        cursor: pointer;
      }
      .qrow-wrap {
        animation: qrow-in 420ms cubic-bezier(0.22, 1, 0.36, 1) both;
        animation-delay: calc(var(--i, 0) * 45ms);
      }
      .qrow {
        flex: 1;
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        min-width: 0;
        text-align: left;
        border: 1px solid transparent;
        border-radius: var(--boxel-border-radius);
        background: var(--card, var(--boxel-light));
        color: var(--card-foreground, var(--boxel-dark));
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        cursor: pointer;
        box-shadow: 0 1px 0
          color-mix(
            in oklab,
            var(--foreground, var(--boxel-dark)) 5%,
            transparent
          );
        transition:
          transform 160ms cubic-bezier(0.22, 1, 0.36, 1),
          border-color 160ms ease-out,
          box-shadow 160ms ease-out;
        font: inherit;
      }
      .qrow:hover,
      .qrow:focus-visible {
        transform: translateY(-1px);
        border-color: color-mix(
          in oklab,
          var(--primary, var(--boxel-highlight)) 40%,
          transparent
        );
        box-shadow: 0 6px 18px -10px
          color-mix(
            in oklab,
            var(--foreground, var(--boxel-dark)) 40%,
            transparent
          );
      }
      @keyframes qrow-in {
        from {
          opacity: 0;
          transform: translateY(8px);
        }
        to {
          opacity: 1;
          transform: none;
        }
      }
      .qrow:focus-visible {
        outline: 2px solid var(--ring, var(--boxel-highlight));
        outline-offset: 2px;
      }
      .qrow:hover .qrow-cue,
      .qrow:focus-visible .qrow-cue {
        transform: translateX(2px);
      }
      .qrow-title {
        font-weight: 500;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        flex: 1;
        min-width: 0;
      }
      .qrow-owner {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground, var(--boxel-450));
        white-space: nowrap;
      }
      .qrow-unowned {
        color: var(--boxel-warning);
        font-style: italic;
      }
      .qrow-clock {
        font-size: var(--boxel-font-size-sm);
        min-width: 4.5rem;
        text-align: right;
      }
      .qrow-clock-none {
        font-family: var(--font-mono, var(--boxel-monospace-font-family));
        color: var(--muted-foreground, var(--boxel-450));
      }
      .qrow-cue {
        flex: none;
        color: var(--muted-foreground, var(--boxel-450));
        transition: transform 120ms ease-out;
      }
      .queue-clear {
        margin: 0;
        padding: var(--boxel-sp-sm);
        border: 1px solid var(--boxel-success);
        border-radius: var(--boxel-border-radius);
        color: var(--boxel-success);
        background: color-mix(
          in oklab,
          var(--boxel-success) 10%,
          var(--card, var(--boxel-light))
        );
        font-size: var(--boxel-font-size-sm);
      }
      @media (prefers-reduced-motion: reduce) {
        .qrow-wrap {
          animation: none;
        }
        .qrow,
        .qrow-cue {
          transition: none;
        }
        .qrow:hover .qrow-cue {
          transform: none;
        }
      }
    </style>
  </template>
}

export default SupportQueue;
