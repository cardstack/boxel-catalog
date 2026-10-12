import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Button } from '@cardstack/boxel-ui/components';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import Popover from '@cardstack/catalog/46f065-popover/popover';

import {
  Calendar,
  type CalendarEvent,
} from '@cardstack/catalog/components/calendar';
import type { WorkOrder } from '../work-order';
import type { MaintenancePlan } from '../maintenance-plan';
import {
  WO_STATUS_HUE,
  WO_KIND_LABEL,
  WORK_ORDER_KINDS,
} from '../maintenance-vocabulary';
import {
  stateColor,
  type StateColor,
} from '@cardstack/catalog/components/state-pill';
import {
  checklistStats,
  isPlanOccurrenceRaised,
  raisedPlanOccurrences,
} from '../utils/maintenance';

interface Signature {
  Args: {
    workOrders: WorkOrder[];
    plans: MaintenancePlan[];
    /** format: 'isolated' for "Open full record", 'edit' for "Quick edit" — both open the real Work Order card in the stack. */
    onOpenWorkOrder?: (
      workOrder: WorkOrder,
      format?: 'isolated' | 'edit',
    ) => void;
    onSelectDay?: (date: Date) => void;
    /** Called after an in-popover quick edit, so the host can save. */
    onChange?: (workOrder: WorkOrder) => void;
    /** The day currently minting a new Work Order — drives the calendar's own add-event spinner. */
    addingDate?: Date;
  };
  Element: HTMLElement;
}

/**
 * Wraps the generic Calendar with the desk's own vocabulary: scheduled/due
 * Work Orders become solid, draggable chips coloured by status; each active
 * Maintenance Plan's `nextDueAt` (already computed on the plan — no maths
 * repeated here) becomes a dashed PROJECTED chip so the eye can tell "booked"
 * from "expected" at a glance. A kind/status filter row sits above.
 *
 * Clicking a chip opens the shared catalog Popover beside it with a compact
 * `:details` read — title, status, priority, checklist progress. Both of
 * its actions hand off to the real card via `onOpenWorkOrder(wo, format)`
 * (a top-level `viewCard` call, never `context.actions`, which silently
 * no-ops): "Open full record" opens it `isolated` (the full technician
 * workbench, since WorkOrder's own isolated view embeds Work Order
 * Workbench), "Quick edit" opens the same card `edit` (every field,
 * grouped). The popover never edits in place — no compact mini-form.
 */
export class MaintenanceCalendar extends GlimmerComponent<Signature> {
  @tracked kindFilter = 'all';
  @tracked showProjected = true;
  @tracked selectedId: string | null = null;

  setKind = (id: string) => (this.kindFilter = id);
  toggleProjected = () => (this.showProjected = !this.showProjected);

  get workOrders(): WorkOrder[] {
    let list = (this.args.workOrders ?? []).filter(Boolean);
    if (this.kindFilter === 'all') return list;
    return list.filter((wo) => wo.kind === this.kindFilter);
  }

  get events(): CalendarEvent[] {
    return this.workOrders
      .filter((wo) => wo.dueBy || wo.scheduledFor)
      .map((wo) => ({
        id: wo.id,
        title:
          `${wo.assetTag ?? wo.assetName ?? 'Work order'} · ${wo.title ?? wo.identifier?.value ?? ''}`.trim(),
        date: new Date(wo.scheduledFor ?? wo.dueBy!),
        kind: wo.status ?? undefined,
        seq: wo.daySequence ?? undefined,
      }));
  }

  get projected(): CalendarEvent[] {
    if (!this.showProjected) return [];
    // Only genuinely unraised occurrences are forecasts. Once the generator
    // has minted the work order for a plan's due day, the solid chip IS that
    // occurrence — drawing the dashed one beside it showed one job as two and
    // inflated every day's apparent load.
    let raised = raisedPlanOccurrences(this.args.workOrders ?? []);
    return (this.args.plans ?? [])
      .filter((p) => p && p.active && p.nextDueAt)
      .filter((p) => !isPlanOccurrenceRaised(raised, p.id, p.nextDueAt))
      .map((p) => ({
        id: p.id,
        title: `${p.assetTag ?? p.assetName ?? p.name} · ${p.name}`,
        date: new Date(p.nextDueAt!),
        kind: 'projected',
      }));
  }

  get kindColors(): Record<string, StateColor> {
    let out: Record<string, StateColor> = {};
    for (let [status, hue] of Object.entries(WO_STATUS_HUE))
      out[status] = stateColor(hue);
    out.projected = stateColor('slate');
    return out;
  }

  // The popover only shows real Work Orders — a projected chip is a plan's
  // computed forecast, not a record with fields to view or edit, so it
  // keeps its plain title tooltip instead (Calendar's existing behaviour).
  get selectedWorkOrder(): WorkOrder | undefined {
    if (!this.selectedId) return undefined;
    return this.workOrders.find((w) => w.id === this.selectedId);
  }

  get popoverOpen(): boolean {
    return this.selectedWorkOrder != null;
  }

  get anchorSelector(): string {
    return `[data-cal-event='${this.selectedId}']`;
  }

  get checklist() {
    let stats = checklistStats(this.selectedWorkOrder?.checklist?.items ?? []);
    return stats;
  }

  hueFor = (status: string) => WO_STATUS_HUE[status] ?? 'slate';

  selectEvent = (event: CalendarEvent) => {
    let wo = this.workOrders.find((w) => w.id === event.id);
    if (!wo) return;
    this.selectedId = event.id ?? null;
  };

  closePopover = () => {
    this.selectedId = null;
  };

  // Both actions open the real Work Order card in the right stack — never
  // inline at the bottom of the page, never a bespoke compact form. "Open
  // full record" opens it read/act (isolated, which is the full technician
  // workbench per work-order.gts); "Quick edit" opens the same card's real
  // edit format (SectionedEdit, every field grouped) instead of a two-field
  // popover mini-form that only ever covered priority and schedule.
  openFullRecord = () => {
    let wo = this.selectedWorkOrder;
    this.closePopover();
    if (wo) this.args.onOpenWorkOrder?.(wo, 'isolated');
  };

  quickEdit = () => {
    let wo = this.selectedWorkOrder;
    this.closePopover();
    if (wo) this.args.onOpenWorkOrder?.(wo, 'edit');
  };

  get scheduledForValue(): string {
    let d = this.selectedWorkOrder?.scheduledFor;
    if (!d) return '';
    let date = new Date(d);
    return date.toISOString().slice(0, 10);
  }

  // --- drag to schedule, drag to sequence ---------------------------------
  // Two drops, two meanings. Onto a day cell: "this day, last in the run".
  // Onto another chip: "immediately before that one". Both write through
  // `onChange`, which is the desk's ordinary work-order save — no new
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

  rescheduleEvent = (event: CalendarEvent, newDate: Date) => {
    let wo = this.workOrders.find((w) => w.id === event.id);
    if (!wo) return;
    this.place(wo, newDate, undefined);
  };

  reorderEvent = (event: CalendarEvent, before: CalendarEvent, date: Date) => {
    let wo = this.workOrders.find((w) => w.id === event.id);
    if (!wo) return;
    this.place(wo, date, before.id);
  };

  kindItems = ['all', ...WORK_ORDER_KINDS];
  kindLabel = (id: string) =>
    id === 'all' ? 'All kinds' : (WO_KIND_LABEL[id] ?? id);

  <template>
    <div class='mcal' ...attributes>
      <div class='mcal-filters'>
        <div class='kinds' role='group' aria-label='Filter by kind'>
          {{#each this.kindItems as |k|}}
            <button
              type='button'
              class='kind-pill {{if (eq this.kindFilter k) "on"}}'
              {{on 'click' (fn this.setKind k)}}
            >{{this.kindLabel k}}</button>
          {{/each}}
        </div>
        <label class='proj-toggle'>
          <input
            type='checkbox'
            checked={{this.showProjected}}
            {{on 'change' this.toggleProjected}}
          />
          Show projected plan dates
        </label>
      </div>
      <Calendar
        @events={{this.events}}
        @projected={{this.projected}}
        @kindColors={{this.kindColors}}
        @onSelectEvent={{this.selectEvent}}
        @onRescheduleEvent={{this.rescheduleEvent}}
        @onReorderEvent={{this.reorderEvent}}
        @onAddEvent={{@onSelectDay}}
        @addingDate={{@addingDate}}
        @density={{true}}
      />

      {{#if this.selectedWorkOrder}}
        <Popover
          @anchor={{this.anchorSelector}}
          @open={{this.popoverOpen}}
          @kind='details'
          @anchoring='beside'
          @size='compact'
          @onDismiss={{this.closePopover}}
          @label={{this.selectedWorkOrder.title}}
          @arrow={{true}}
        >
          <:details>
            <div class='pop-details'>
              <div class='pop-head'>
                <code
                  class='pop-tag'
                >{{this.selectedWorkOrder.identifier.value}}</code>
                <StatePill
                  @label={{this.selectedWorkOrder.status}}
                  @hue={{this.hueFor this.selectedWorkOrder.status}}
                  @dot={{true}}
                />
              </div>
              <p class='pop-title'>{{this.selectedWorkOrder.title}}</p>
              <p class='pop-sub'>
                {{this.selectedWorkOrder.assetTag}}
                {{this.selectedWorkOrder.assetName}}
              </p>
              <div class='pop-facts'>
                <span>{{this.selectedWorkOrder.priority}}</span>
                {{#if this.selectedWorkOrder.scheduledFor}}
                  <span>scheduled {{this.scheduledForValue}}</span>
                {{/if}}
                {{#if this.checklist.total}}
                  <span>{{this.checklist.done}}/{{this.checklist.total}}
                    checklist</span>
                {{/if}}
              </div>
              <div class='pop-actions'>
                <Button
                  @kind='secondary'
                  @size='small'
                  {{on 'click' this.quickEdit}}
                >Quick edit</Button>
                <Button
                  @kind='primary'
                  @size='small'
                  {{on 'click' this.openFullRecord}}
                >Open full record</Button>
              </div>
            </div>
          </:details>
        </Popover>
      {{/if}}
    </div>
    <style scoped>
      .mcal {
        container-type: inline-size;
        display: grid;
        gap: var(--boxel-sp-sm);
        min-width: 0;
        color: var(--foreground);
      }
      .mcal-filters {
        display: flex;
        align-items: center;
        justify-content: space-between;
        flex-wrap: wrap;
        gap: var(--boxel-sp-sm);
      }
      .kinds {
        display: flex;
        gap: var(--boxel-sp-4xs);
        flex-wrap: wrap;
      }
      .kind-pill {
        border: 1px solid var(--border);
        border-radius: 999px;
        background: var(--card);
        color: var(--muted-foreground);
        font-size: var(--boxel-font-size-xs);
        min-height: 2.75rem;
        padding: 0 var(--boxel-sp);
        display: inline-flex;
        align-items: center;
        cursor: pointer;
        text-transform: capitalize;
        transition:
          background-color 120ms ease-out,
          border-color 120ms ease-out,
          transform 120ms ease-out;
      }
      .kind-pill:focus-visible {
        outline: 2px solid var(--primary);
        outline-offset: 2px;
      }
      .kind-pill:active {
        transform: scale(0.95);
      }
      .kind-pill.on {
        background: color-mix(in oklab, var(--primary) 14%, var(--card));
        color: var(--foreground);
        border-color: var(--primary);
      }
      .proj-toggle {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-4xs);
        min-height: 2.75rem;
        padding: var(--boxel-sp-xs) 0;
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground);
        cursor: pointer;
      }
      .proj-toggle input {
        width: 1.1rem;
        height: 1.1rem;
        cursor: pointer;
      }
      .pop-details,
      .pop-edit {
        display: grid;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp-sm);
        min-width: 15rem;
        color: var(--foreground);
      }
      .pop-head {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
      }
      .pop-tag {
        font-family: var(
          --boxel-monospace-font-family,
          ui-monospace,
          monospace
        );
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
      .pop-title {
        margin: 0;
        font-weight: 600;
      }
      .pop-sub {
        margin: 0;
        color: var(--muted-foreground);
        font-size: var(--boxel-font-size-sm);
      }
      .pop-facts {
        display: flex;
        gap: var(--boxel-sp-xs);
        flex-wrap: wrap;
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
      .pop-actions {
        display: flex;
        gap: var(--boxel-sp-xs);
        margin-top: var(--boxel-sp-4xs);
      }
      .pop-field {
        display: grid;
        gap: var(--boxel-sp-5xs);
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground);
      }
      .pop-select,
      .pop-input {
        min-height: 32px;
        border: 1px solid var(--border);
        border-radius: var(--boxel-border-radius-sm);
        background: var(--card);
        color: var(--foreground);
        padding: 0 var(--boxel-sp-xs);
      }
    </style>
  </template>
}

export default MaintenanceCalendar;
