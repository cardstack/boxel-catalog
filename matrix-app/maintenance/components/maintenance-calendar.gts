import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { Button } from '@cardstack/pretui/components/button';
import { Popover } from '@cardstack/pretui/components/popover';
import ChevronLeftIcon from '@cardstack/boxel-icons/chevron-left';
import ChevronRightIcon from '@cardstack/boxel-icons/chevron-right';

import type { WorkOrder } from '../work-order';
import type { MaintenancePlan } from '../maintenance-plan';
import {
  checklistStats,
  isPlanOccurrenceRaised,
  raisedPlanOccurrences,
} from '../utils/maintenance';
import { dayKey } from '../utils/recurrence';
import { woDot, woLabel } from './status-dot';

interface Signature {
  Args: {
    workOrders: WorkOrder[];
    plans: MaintenancePlan[];
    /** 'isolated' opens the full record, 'edit' the card's edit format; both open the real Work Order in the stack. */
    onOpenWorkOrder?: (
      workOrder: WorkOrder,
      format?: 'isolated' | 'edit',
    ) => void;
    onSelectDay?: (date: Date) => void;
    /** Called after a drag reschedule or reorder, so the host can save. */
    onChange?: (workOrder: WorkOrder) => void;
    /** The day currently minting a new Work Order. */
    addingDate?: Date;
    /** Work order kind to show, or 'all'. The desk's toolbar owns the filter. */
    kind?: string;
  };
  Element: HTMLElement;
}

interface Entry {
  id: string;
  kind: string;
  ref: string;
  title: string;
  wo?: WorkOrder;
}

interface Day {
  date: Date;
  key: string;
  outside: boolean;
  today: boolean;
  entries: Entry[];
}

const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

/**
 * The Work tab's month grid. Scheduled or due Work Orders are solid chips
 * with a status dot; an active plan's unraised next occurrence is a hollow
 * "Planned" chip, so booked and expected work read apart. A Work Order chip
 * opens a Pret UI Popover with its details and two hand-offs to the real
 * card. Chips drag onto a day (reschedule) or onto another chip (run order).
 */
export class MaintenanceCalendar extends GlimmerComponent<Signature> {
  @tracked cursor = startOfMonth(new Date());
  @tracked dragId: string | null = null;
  weekdays = WEEKDAYS;

  get kindFilter(): string {
    return this.args.kind ?? 'all';
  }

  get workOrders(): WorkOrder[] {
    let list = (this.args.workOrders ?? []).filter(Boolean);
    if (this.kindFilter === 'all') return list;
    return list.filter((wo) => wo.kind === this.kindFilter);
  }

  get monthLabel(): string {
    return this.cursor.toLocaleDateString('en-US', {
      month: 'long',
      year: 'numeric',
    });
  }

  get days(): Day[] {
    let byDay = new Map<string, Entry[]>();
    let push = (date: Date, e: Entry) => {
      let k = dayKey(date);
      byDay.set(k, [...(byDay.get(k) ?? []), e]);
    };
    for (let wo of this.workOrders) {
      let d = wo.scheduledFor ?? wo.dueBy;
      if (!d) continue;
      push(new Date(d), {
        id: wo.id,
        kind: (wo.kind ?? 'WO').toUpperCase(),
        ref: wo.identifier?.value ?? '',
        title: wo.assetName ?? wo.title ?? '',
        wo,
      });
    }
    // Only unraised occurrences are forecasts: once a plan's work order
    // exists, its solid chip is that occurrence.
    let raised = raisedPlanOccurrences(this.args.workOrders ?? []);
    for (let p of this.args.plans ?? []) {
      if (!p?.active || !p.nextDueAt) continue;
      if (isPlanOccurrenceRaised(raised, p.id, p.nextDueAt)) continue;
      push(new Date(p.nextDueAt), {
        id: p.id,
        kind: 'Planned',
        ref: '',
        title: `${p.assetName ?? p.assetTag ?? ''} ${p.name ?? ''}`.trim(),
      });
    }
    for (let list of byDay.values()) {
      list.sort(
        (a, b) =>
          (a.wo?.daySequence ?? Infinity) - (b.wo?.daySequence ?? Infinity),
      );
    }
    let first = new Date(this.cursor);
    first.setDate(1 - first.getDay());
    let todayKey = dayKey(new Date());
    let out: Day[] = [];
    for (let i = 0; i < 42; i++) {
      let date = new Date(first);
      date.setDate(first.getDate() + i);
      if (i === 35 && date.getMonth() !== this.cursor.getMonth()) break;
      let key = dayKey(date);
      out.push({
        date,
        key,
        outside: date.getMonth() !== this.cursor.getMonth(),
        today: key === todayKey,
        entries: byDay.get(key) ?? [],
      });
    }
    return out;
  }

  shift = (months: number) => {
    let d = new Date(this.cursor);
    d.setMonth(d.getMonth() + months);
    this.cursor = d;
  };
  goToday = () => (this.cursor = startOfMonth(new Date()));

  checklist = (wo: WorkOrder) => checklistStats(wo.checklist?.items ?? []);
  scheduledLabel = (wo: WorkOrder) =>
    wo.scheduledFor ? dayKey(new Date(wo.scheduledFor)) : '';

  open = (wo: WorkOrder, format: 'isolated' | 'edit', close: () => void) => {
    close();
    this.args.onOpenWorkOrder?.(wo, format);
  };

  // --- drag to schedule, drag to sequence ---------------------------------
  // Two drops, two meanings. Onto a day cell: "this day, last in the run".
  // Onto another chip: "immediately before that one". Both write through
  // `onChange`, which is the host's ordinary work-order save — no new
  // persistence path, and a refused save simply leaves the old order.
  //
  // `scheduledFor` is a DateField with no time of day, so the run order has
  // to live in its own `daySequence`. Every reorder renumbers the whole day
  // 0..n-1 rather than nudging one value: gaps and ties are what make a
  // hand-maintained sequence drift, and a day holds a handful of chips, so
  // the cost is nil.
  private sameDayAs(wo: WorkOrder, date: Date): boolean {
    let d = wo.scheduledFor ?? wo.dueBy;
    if (!d) return false;
    let a = new Date(d);
    return (
      a.getFullYear() === date.getFullYear() &&
      a.getMonth() === date.getMonth() &&
      a.getDate() === date.getDate()
    );
  }

  // Deliberately the UNfiltered list: a kind filter hides chips but must not
  // renumber the day around them, or filtering then dragging would silently
  // reshuffle the work that was out of view.
  private orderedOn(date: Date): WorkOrder[] {
    return (this.args.workOrders ?? [])
      .filter(Boolean)
      .filter((wo) => this.sameDayAs(wo, date))
      .sort((a, b) => {
        let seqA = a.daySequence ?? Number.POSITIVE_INFINITY;
        let seqB = b.daySequence ?? Number.POSITIVE_INFINITY;
        if (seqA !== seqB) return seqA - seqB;
        let dateA = new Date(a.scheduledFor ?? a.dueBy!).getTime();
        let dateB = new Date(b.scheduledFor ?? b.dueBy!).getTime();
        return dateA - dateB;
      });
  }

  /**
   * Renumber `list` 1..n, saving only the rows whose number actually moved.
   * One-based on purpose: a `daySequence` of 0 does not survive the round trip
   * to the realm (it serialises away with the other empty values), so the
   * first chip in a day would silently lose its position on reload.
   */
  private commitOrder(list: WorkOrder[]) {
    list.forEach((wo, i) => {
      if (wo.daySequence !== i + 1) {
        wo.daySequence = i + 1;
        this.args.onChange?.(wo);
      }
    });
  }

  private place(dragged: WorkOrder, date: Date, beforeId: string | undefined) {
    let movedDay = !this.sameDayAs(dragged, date);
    let day = this.orderedOn(date).filter((wo) => wo.id !== dragged.id);
    let at = beforeId ? day.findIndex((wo) => wo.id === beforeId) : -1;
    day.splice(at === -1 ? day.length : at, 0, dragged);
    if (movedDay) {
      dragged.scheduledFor = new Date(date);
      // A sentinel no real position can equal (they start at 1), so
      // `commitOrder` is guaranteed to save this row — the date changed even
      // if its position number did not. The day it left keeps a gap in its
      // numbering; only relative order is ever read, so closing the gap would
      // be writes for nothing.
      dragged.daySequence = -1;
    }
    this.commitOrder(day);
  }

  dragStart = (id: string, e: Event) => {
    this.dragId = id;
    (e as DragEvent).dataTransfer?.setData('text/plain', id);
  };
  allowDrop = (e: Event) => {
    if (this.dragId) e.preventDefault();
  };
  drop = (date: Date, beforeId: string | undefined, e: Event) => {
    e.preventDefault();
    e.stopPropagation();
    let wo = this.workOrders.find((w) => w.id === this.dragId);
    this.dragId = null;
    if (wo && wo.id !== beforeId) this.place(wo, date, beforeId);
  };

  <template>
    <section class='mcal' aria-label='Work calendar' ...attributes>
      <header class='mcal-head'>
        <h3>{{this.monthLabel}}</h3>
        <div class='mcal-nav'>
          <Button
            @size='s'
            @appearance='outlined'
            @icon={{ChevronLeftIcon}}
            aria-label='Previous month'
            {{on 'click' (fn this.shift -1)}}
          />
          <Button
            @size='s'
            @appearance='outlined'
            {{on 'click' this.goToday}}
          >Today</Button>
          <Button
            @size='s'
            @appearance='outlined'
            @icon={{ChevronRightIcon}}
            aria-label='Next month'
            {{on 'click' (fn this.shift 1)}}
          />
        </div>
      </header>
      <ol class='grid'>
        {{#each this.weekdays as |w|}}
          <li class='wd' aria-hidden='true'>{{w}}</li>
        {{/each}}
        {{#each this.days key='key' as |d|}}
          <li
            class='day'
            data-outside={{d.outside}}
            data-today={{d.today}}
            {{on 'dragover' this.allowDrop}}
            {{on 'drop' (fn this.drop d.date undefined)}}
          >
            <button
              type='button'
              class='num'
              aria-label='Add work order on {{d.key}}'
              {{on 'click' (fn (optional @onSelectDay) d.date)}}
            >{{d.date.getDate}}</button>
            {{#each d.entries key='id' as |e|}}
              {{#if e.wo}}
                <Popover @label={{e.wo.title}}>
                  <:trigger as |_open toggle|>
                    <button
                      type='button'
                      class='chip'
                      draggable='true'
                      style={{woDot e.wo.status}}
                      {{on 'click' toggle}}
                      {{on 'dragstart' (fn this.dragStart e.id)}}
                      {{on 'dragover' this.allowDrop}}
                      {{on 'drop' (fn this.drop d.date e.id)}}
                    >
                      <span class='ref'><span class='dot'></span>{{e.kind}}
                        ·
                        {{e.ref}}</span>
                      <span class='ttl'>{{e.title}}</span>
                    </button>
                  </:trigger>
                  <:default as |close|>
                    <div class='pop' style={{woDot e.wo.status}}>
                      <p class='ref'><span class='dot'></span>{{e.ref}}
                        ·
                        {{woLabel e.wo.status}}</p>
                      <p class='pop-title'>{{e.wo.title}}</p>
                      <p class='muted'>{{e.wo.assetTag}} {{e.wo.assetName}}</p>
                      <p class='muted'>
                        {{e.wo.priority}}
                        {{#if e.wo.scheduledFor}}· scheduled
                          {{this.scheduledLabel e.wo}}{{/if}}
                      </p>
                      <div class='pop-actions'>
                        <Button
                          @appearance='outlined'
                          @size='s'
                          {{on 'click' (fn this.open e.wo 'edit' close)}}
                        >Quick edit</Button>
                        <Button
                          @tone='primary'
                          @appearance='accent'
                          @size='s'
                          {{on 'click' (fn this.open e.wo 'isolated' close)}}
                        >Open full record</Button>
                      </div>
                    </div>
                  </:default>
                </Popover>
              {{else}}
                <p class='chip planned'>
                  <span class='ref'><span class='dot'></span>{{e.kind}}</span>
                  <span class='ttl'>{{e.title}}</span>
                </p>
              {{/if}}
            {{/each}}
          </li>
        {{/each}}
      </ol>
    </section>
    <style scoped>
      .mcal {
        display: grid;
        gap: var(--boxel-sp-xs);
        min-width: 0;
        color: var(--card-foreground);
      }
      .mcal-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: var(--boxel-sp-xs);
      }
      .mcal-head h3 {
        margin: 0;
        font-size: var(--boxel-font-size-sm);
        font-weight: 600;
      }
      .mcal-nav {
        display: flex;
        gap: var(--boxel-sp-4xs);
      }
      .grid {
        list-style: none;
        margin: 0;
        padding: 0;
        display: grid;
        grid-template-columns: repeat(7, minmax(0, 1fr));
        border-block-start: 1px solid var(--border);
        border-inline-start: 1px solid var(--border);
      }
      .wd,
      .day {
        border-inline-end: 1px solid var(--border);
        border-block-end: 1px solid var(--border);
        padding: var(--boxel-sp-4xs) var(--boxel-sp-xs);
        min-width: 0;
      }
      .wd {
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-xs);
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .day {
        display: grid;
        align-content: start;
        gap: var(--boxel-sp-4xs);
        min-block-size: 5.5rem;
      }
      .day[data-outside='true'] .num {
        color: var(--muted-foreground);
      }
      .num {
        justify-self: start;
        border: 0;
        background: none;
        padding: 0;
        font: inherit;
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-xs);
        color: var(--card-foreground);
        cursor: pointer;
      }
      .day[data-today='true'] .num {
        background: var(--foreground);
        color: var(--background);
        padding-inline: var(--boxel-sp-5xs);
        border-radius: var(--radius);
      }
      .chip {
        display: grid;
        margin: 0;
        padding: 0;
        border: 0;
        background: none;
        text-align: start;
        font: inherit;
        color: inherit;
        min-width: 0;
        cursor: pointer;
      }
      .chip.planned {
        cursor: default;
      }
      .ref {
        display: inline-flex;
        align-items: center;
        gap: var(--boxel-sp-5xs);
        margin: 0;
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-xs);
        font-weight: 600;
      }
      .dot {
        inline-size: 0.375rem;
        block-size: 0.375rem;
        border-radius: 50%;
        background: var(--dot);
        flex: none;
      }
      .planned .dot {
        background: none;
        border: 1px solid var(--muted-foreground);
      }
      .ttl {
        font-size: var(--boxel-font-size-xs);
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .pop {
        display: grid;
        gap: var(--boxel-sp-4xs);
        padding: var(--boxel-sp-sm);
      }
      .pop p {
        margin: 0;
      }
      .pop-title {
        font-weight: 600;
      }
      .muted {
        color: var(--muted-foreground);
        font-size: var(--boxel-font-size-xs);
      }
      .pop-actions {
        display: flex;
        gap: var(--boxel-sp-xs);
      }
    </style>
  </template>
}

function startOfMonth(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), 1);
}

function optional(f?: (d: Date) => void) {
  return f ?? (() => {});
}

export default MaintenanceCalendar;
