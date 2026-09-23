import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { htmlSafe } from '@ember/template';
import { eq, gt } from '@cardstack/boxel-ui/helpers';

import {
  monthGrid,
  monthTitle,
  sameDay,
  type CalendarDay,
} from '../utils/month-grid';
import {
  stateColorOf,
  type StateColor,
} from '@cardstack/catalog/components/state-pill';

export interface CalendarEvent {
  id?: string;
  title: string;
  date: Date;
  kind?: string;
  // Explicit position within the day, when the host persists one. Events
  // without a `seq` sort after those that have one, keeping their incoming
  // order — so a calendar whose host has no ordering concept is unchanged.
  seq?: number;
}

interface CalendarSignature {
  Args: {
    events: CalendarEvent[];
    // kind → color pair for the event chips. The map lives with the module
    // that owns the kind enum (meeting.gts exports MEETING_TYPE_COLORS), not
    // here — the calendar has no opinion on any domain's vocabulary.
    kindColors?: Record<string, StateColor>;
    onSelectEvent?: (event: CalendarEvent) => void;
    onRescheduleEvent?: (event: CalendarEvent, newDate: Date) => void;
    // A chip dropped ON another chip: place `event` immediately before
    // `before`, on `before`'s day. This is the within-day reorder the plain
    // day-cell drop cannot express — dropping on the cell background still
    // means "this day, at the end". Supplying it is what makes chips
    // draggable even when nothing can be rescheduled across days.
    onReorderEvent?: (
      event: CalendarEvent,
      before: CalendarEvent,
      date: Date,
    ) => void;
    onAddEvent?: (date: Date) => void;
    // A drop that did not start on a chip in this calendar — an unscheduled
    // item dragged in from a backlog elsewhere on the page. The host reads the
    // payload off the DragEvent, since only it knows what it put there.
    onExternalDrop?: (event: DragEvent, date: Date) => void;
    // The day currently being created, if any. Drives the spinner and the
    // disabled state on that day's + button, so a slow create cannot be
    // clicked three more times — which is exactly how a calendar ends up with
    // four cards all called "New Meeting".
    addingDate?: Date;
    // Which month to open on. Defaults to today; a consumer whose events
    // live in the future (a fixture list) opens on the next one instead.
    initialDate?: Date;
    // Events that are PROJECTED, not yet real — a maintenance plan's next due
    // dates before the generator has raised the work orders. Rendered as
    // dashed, non-draggable chips so the eye reads "expected", not "booked".
    projected?: CalendarEvent[];
    // Days that cannot receive a drop (weekends, holidays from a Schedule).
    // The host decides; the calendar refuses the drop and greys the cell.
    isDisabledDate?: (date: Date) => boolean;
    // Tint each day by how much is on it, so the month's shape reads as load.
    density?: boolean;
  };
  Blocks: {
    /** Replace the chip's content while keeping the chip chrome. */
    chip?: [CalendarEvent];
  };
  Element: HTMLElement;
}

const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MAX_CHIPS = 3;

// Month-grid scheduling calendar. Hand-rolled because npm calendar libraries
// are not loadable from realm modules.
export class Calendar extends GlimmerComponent<CalendarSignature> {
  weekdays = WEEKDAYS;

  @tracked cursor = this.args.initialDate ?? new Date();
  @tracked isTransitioning = false;
  @tracked draggingEvent: CalendarEvent | undefined;
  @tracked dragOverKey: string | undefined;
  // The chip the insertion line is currently drawn above.
  @tracked dropBeforeId: string | undefined;
  @tracked expandedDayKey: string | undefined;

  get weeks(): CalendarDay[][] {
    return monthGrid(this.cursor);
  }

  get monthTitle(): string {
    return monthTitle(this.cursor);
  }

  // A day reads top-to-bottom as its run order: an explicit `seq` first (what
  // a drag writes), then chronology, then the incoming order. `sort` is
  // stable, so events that tie on both keys never shuffle between renders.
  eventsOn = (day: CalendarDay): CalendarEvent[] => {
    return (this.args.events ?? [])
      .filter((event) => event.date && sameDay(new Date(event.date), day.date))
      .sort((a, b) => {
        let seqA = a.seq ?? Number.POSITIVE_INFINITY;
        let seqB = b.seq ?? Number.POSITIVE_INFINITY;
        if (seqA !== seqB) return seqA - seqB;
        return new Date(a.date).getTime() - new Date(b.date).getTime();
      });
  };

  chipsFor = (day: CalendarDay): CalendarEvent[] => {
    let events = this.eventsOn(day);
    if (this.dayKey(day) === this.expandedDayKey) {
      return events;
    }
    return events.slice(0, MAX_CHIPS);
  };

  overflowCount = (day: CalendarDay): number => {
    if (this.dayKey(day) === this.expandedDayKey) {
      return 0;
    }
    return Math.max(0, this.eventsOn(day).length - MAX_CHIPS);
  };

  isExpanded = (day: CalendarDay): boolean => {
    return this.dayKey(day) === this.expandedDayKey;
  };

  toggleExpand = (day: CalendarDay) => {
    let key = this.dayKey(day);
    this.expandedDayKey = this.expandedDayKey === key ? undefined : key;
  };

  projectedOn = (day: CalendarDay): CalendarEvent[] => {
    return (this.args.projected ?? []).filter(
      (event) => event.date && sameDay(new Date(event.date), day.date),
    );
  };

  isDisabled = (day: CalendarDay): boolean => {
    return this.args.isDisabledDate?.(day.date) ?? false;
  };

  densityClass = (day: CalendarDay): string => {
    if (!this.args.density) {
      return '';
    }
    let n = this.eventsOn(day).length + this.projectedOn(day).length;
    if (n === 0) return '';
    if (n <= 1) return 'density-1';
    if (n <= 3) return 'density-2';
    return 'density-3';
  };

  chipStyle = (event: CalendarEvent) => {
    let color = stateColorOf(this.args.kindColors ?? {}, event.kind);
    return htmlSafe(`background: ${color.bg}; color: ${color.fg};`);
  };

  get isDraggable(): string {
    return this.args.onRescheduleEvent || this.args.onReorderEvent
      ? 'true'
      : 'false';
  }

  private animateTransition() {
    this.isTransitioning = true;
    setTimeout(() => {
      this.isTransitioning = false;
    }, 200);
  }

  shiftMonth = (delta: number) => {
    this.animateTransition();
    this.cursor = new Date(
      this.cursor.getFullYear(),
      this.cursor.getMonth() + delta,
      1,
    );
  };

  goToday = () => {
    this.animateTransition();
    this.cursor = new Date();
  };

  selectEvent = (event: CalendarEvent) => {
    this.args.onSelectEvent?.(event);
  };

  dayKey = (day: CalendarDay): string => day.date.toDateString();

  startDrag = (event: CalendarEvent, e: DragEvent) => {
    this.draggingEvent = event;
    e.dataTransfer?.setData('text/plain', event.id ?? '');
    if (e.dataTransfer) {
      e.dataTransfer.effectAllowed = 'move';
    }
  };

  endDrag = () => {
    this.draggingEvent = undefined;
    this.dragOverKey = undefined;
    this.dropBeforeId = undefined;
  };

  dragEnterDay = (day: CalendarDay, e: DragEvent) => {
    e.preventDefault();
    if (this.draggingEvent || this.args.onExternalDrop) {
      this.dragOverKey = this.dayKey(day);
    }
  };

  dragOverDay = (e: DragEvent) => {
    e.preventDefault();
  };

  // --- chip-level targets: the within-day reorder -------------------------
  // A chip is a drop target only for another chip, and only when the host
  // supplied `onReorderEvent`. Dropping a chip on itself is a no-op, and the
  // handler stops propagation so the day cell underneath does not also treat
  // it as a plain "move to this day" drop.
  canDropOnChip = (target: CalendarEvent): boolean => {
    return Boolean(
      this.args.onReorderEvent &&
      this.draggingEvent &&
      this.draggingEvent.id !== target.id,
    );
  };

  dragOverChip = (target: CalendarEvent, e: DragEvent) => {
    if (!this.canDropOnChip(target)) {
      return;
    }
    e.preventDefault();
    e.stopPropagation();
    this.dropBeforeId = target.id;
  };

  dragLeaveChip = (target: CalendarEvent) => {
    if (this.dropBeforeId === target.id) {
      this.dropBeforeId = undefined;
    }
  };

  isDropBefore = (event: CalendarEvent): boolean => {
    return Boolean(event.id) && this.dropBeforeId === event.id;
  };

  dropOnChip = (day: CalendarDay, target: CalendarEvent, e: DragEvent) => {
    if (!this.canDropOnChip(target)) {
      return;
    }
    e.preventDefault();
    e.stopPropagation();
    let dragged = this.draggingEvent!;
    this.endDrag();
    if (this.isDisabled(day)) {
      return;
    }
    this.args.onReorderEvent?.(dragged, target, day.date);
  };

  dropOnDay = (day: CalendarDay, e: DragEvent) => {
    e.preventDefault();
    let event = this.draggingEvent;
    this.draggingEvent = undefined;
    this.dragOverKey = undefined;
    this.dropBeforeId = undefined;
    if (this.isDisabled(day)) {
      // Refused: a non-working day. The chip snaps back; nothing is written.
      return;
    }
    if (!event) {
      this.args.onExternalDrop?.(e, day.date);
      return;
    }
    this.args.onRescheduleEvent?.(event, day.date);
  };

  addEventOn = (day: CalendarDay) => {
    if (this.args.addingDate) {
      return;
    }
    this.args.onAddEvent?.(day.date);
  };

  isAdding = (day: CalendarDay) => {
    return sameDay(this.args.addingDate, day.date);
  };

  <template>
    <div class='calendar' ...attributes>
      <header class='calendar-toolbar'>
        <h3 class='calendar-title'>{{this.monthTitle}}</h3>
        <div class='calendar-nav'>
          <button
            type='button'
            aria-label='Previous month'
            {{on 'click' (fn this.shiftMonth -1)}}
          >‹</button>
          <button type='button' {{on 'click' this.goToday}}>Today</button>
          <button
            type='button'
            aria-label='Next month'
            {{on 'click' (fn this.shiftMonth 1)}}
          >›</button>
        </div>
      </header>
      <table class='calendar-grid {{if this.isTransitioning "fading"}}'>
        <thead>
          <tr>
            {{#each this.weekdays as |day|}}
              <th scope='col'>{{day}}</th>
            {{/each}}
          </tr>
        </thead>
        <tbody>
          {{#each this.weeks as |week|}}
            <tr>
              {{#each week as |day|}}
                <td
                  class='day
                    {{unless day.inMonth "out-month"}}
                    {{if day.isToday "today"}}
                    {{if (eq (this.dayKey day) this.dragOverKey) "drag-over"}}
                    {{if (this.isDisabled day) "disabled-day"}}
                    {{this.densityClass day}}'
                  {{on 'dragenter' (fn this.dragEnterDay day)}}
                  {{on 'dragover' this.dragOverDay}}
                  {{on 'drop' (fn this.dropOnDay day)}}
                >
                  <div class='day-head'>
                    <span class='day-number'>{{day.dayNumber}}</span>
                    {{#if @onAddEvent}}
                      <button
                        type='button'
                        class='add-meeting'
                        aria-label='Add event'
                        title='Add event'
                        {{on 'click' (fn this.addEventOn day)}}
                      >+</button>
                    {{/if}}
                  </div>
                  <div class='day-events'>
                    {{! Keyed by id — chipsFor/eventsOn mint a brand-new
                      array of new object literals on every call, so without
                      a stable key Glimmer tears down and rebuilds every chip
                      on any unrelated re-render. That kills the hovered DOM
                      node mid-hover, which is why the native title tooltip
                      was flickering. }}
                    {{#each (this.chipsFor day) key='id' as |event|}}
                      <button
                        type='button'
                        class='event-chip
                          {{if (this.isDropBefore event) "drop-before"}}'
                        style={{this.chipStyle event}}
                        title={{event.title}}
                        draggable={{this.isDraggable}}
                        data-cal-event={{event.id}}
                        data-bx-popover-anchor
                        {{on 'click' (fn this.selectEvent event)}}
                        {{on 'dragstart' (fn this.startDrag event)}}
                        {{on 'dragend' this.endDrag}}
                        {{on 'dragover' (fn this.dragOverChip event)}}
                        {{on 'dragleave' (fn this.dragLeaveChip event)}}
                        {{on 'drop' (fn this.dropOnChip day event)}}
                      >{{#if (has-block 'chip')}}{{yield
                            event
                            to='chip'
                          }}{{else}}{{event.title}}{{/if}}</button>
                    {{/each}}
                    {{#each (this.projectedOn day) key='id' as |event|}}
                      <button
                        type='button'
                        class='event-chip projected-chip'
                        style={{this.chipStyle event}}
                        title='{{event.title}} (projected)'
                        data-cal-event={{event.id}}
                        data-bx-popover-anchor
                        {{on 'click' (fn this.selectEvent event)}}
                      >{{#if (has-block 'chip')}}{{yield
                            event
                            to='chip'
                          }}{{else}}{{event.title}}{{/if}}</button>
                    {{/each}}
                    {{#if (gt (this.overflowCount day) 0)}}
                      <button
                        type='button'
                        class='overflow'
                        {{on 'click' (fn this.toggleExpand day)}}
                      >+{{this.overflowCount day}}
                        more</button>
                    {{else if (this.isExpanded day)}}
                      <button
                        type='button'
                        class='overflow'
                        {{on 'click' (fn this.toggleExpand day)}}
                      >show less</button>
                    {{/if}}
                  </div>
                </td>
              {{/each}}
            </tr>
          {{/each}}
        </tbody>
      </table>
    </div>
    <style scoped>
      .calendar {
        /* Brand colour darkened until it is legible as a glyph. --primary is a
           SURFACE: on a light ground the app default computes 1.31:1, so it can
           fill and it can mark, but it can never be text. Mixing toward
           --foreground keeps this legible in BOTH themes, because --foreground
           flips and drags the mix with it. 38% is the highest hue share that
           still clears 4.5:1 for the palest hues boxel ships. */
        --cal-brand-text: color-mix(
          in oklch,
          var(--primary, var(--boxel-highlight)) 38%,
          var(--foreground, var(--boxel-dark))
        );
        background: var(--background, var(--boxel-light));
        color: var(--foreground, var(--boxel-dark));
        font-family: var(--font-sans, var(--boxel-font-family));
        border: 1px solid var(--border, var(--boxel-200));
        border-radius: var(--boxel-border-radius);
        overflow: hidden;
      }
      .calendar-toolbar {
        display: flex;
        align-items: center;
        justify-content: space-between;
        padding: var(--boxel-sp-xs) var(--boxel-sp);
        border-bottom: 1px solid var(--border, var(--boxel-200));
      }
      .calendar-title {
        margin: 0;
        font-size: var(--boxel-font-size);
      }
      .calendar-nav {
        display: flex;
        gap: var(--boxel-sp-4xs);
      }
      .calendar-nav button {
        border: 1px solid var(--border, var(--boxel-200));
        background: var(--background, var(--boxel-light));
        color: var(--foreground, var(--boxel-dark));
        border-radius: var(--boxel-border-radius-sm);
        padding: var(--boxel-sp-5xs) var(--boxel-sp-xs);
        cursor: pointer;
        font-size: var(--boxel-font-size-sm);
        transition: background-color 0.15s ease-out;
      }
      .calendar-nav button:hover {
        background: var(--muted, var(--boxel-100));
      }
      .calendar-grid {
        width: 100%;
        table-layout: fixed;
        border-collapse: collapse;
        transition: opacity 0.2s ease-out;
      }
      .calendar-grid.fading {
        opacity: 0.3;
      }
      @media (prefers-reduced-motion: reduce) {
        .calendar-grid {
          transition: none;
        }
        .calendar-grid.fading {
          opacity: 1;
        }
      }
      th {
        font-size: var(--boxel-font-size-xs);
        text-transform: uppercase;
        letter-spacing: 0.05em;
        color: var(--muted-foreground, var(--boxel-450));
        padding: var(--boxel-sp-4xs);
        border-bottom: 1px solid var(--border, var(--boxel-200));
      }
      .day {
        vertical-align: top;
        height: 5.75rem;
        padding: var(--boxel-sp-5xs);
        border: 1px solid var(--border, var(--boxel-100));
        transition: background-color 0.15s ease-out;
      }
      .day:hover {
        background: var(--muted, var(--boxel-100));
      }
      .day:hover .add-meeting {
        opacity: 1;
      }
      .day.drag-over {
        background: color-mix(
          in oklch,
          var(--primary, var(--boxel-highlight)) 12%,
          var(--background, var(--boxel-light))
        );
        box-shadow: inset 0 0 0 0.09375rem
          var(--primary, var(--boxel-highlight));
      }
      .day-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: var(--boxel-sp-4xs);
      }
      .day-number {
        font-size: var(--boxel-font-size-xs);
        font-weight: 600;
      }
      .add-meeting {
        border: none;
        background: none;
        color: var(--muted-foreground, var(--boxel-450));
        font-size: var(--boxel-font-size-sm);
        line-height: 1;
        padding: 0 var(--boxel-sp-5xs);
        cursor: pointer;
        opacity: 0;
        transition:
          opacity 0.15s ease-out,
          color 0.15s ease-out;
      }
      .add-meeting:hover {
        color: var(--cal-brand-text);
      }
      /* Spinner rather than a text swap: the + occupies a fixed 1rem box, so
         swapping in a glyph would jitter the day cell. */
      .spinner {
        display: block;
        width: 0.7rem;
        height: 0.7rem;
        border-radius: 50%;
        border: 2px solid currentColor;
        border-top-color: transparent;
        animation: cal-spin 0.6s linear infinite;
      }
      @keyframes cal-spin {
        to {
          transform: rotate(360deg);
        }
      }
      .add-meeting.is-adding {
        opacity: 1;
        cursor: progress;
      }
      .add-meeting:disabled {
        pointer-events: none;
      }
      @media (prefers-reduced-motion: reduce) {
        .spinner {
          animation-duration: 2s;
        }
        .add-meeting {
          transition: none;
        }
      }
      .out-month .day-number {
        color: var(--muted-foreground, var(--boxel-300));
        font-weight: 400;
      }
      .today {
        /* Fill, ring and number all derive from --cal-brand-text, so the three
           cannot drift apart and the ring stays visible: a raw --primary ring
           computes 1.31:1 against a light cell, which fails even the 3:1 floor
           for a non-text mark that carries meaning. */
        background: color-mix(
          in oklch,
          var(--cal-brand-text) 10%,
          var(--background, var(--boxel-light))
        );
        box-shadow: inset 0 0 0 0.09375rem var(--cal-brand-text);
      }
      .today:hover {
        background: color-mix(
          in oklch,
          var(--primary, var(--boxel-highlight)) 14%,
          var(--background, var(--boxel-light))
        );
      }
      .today .day-number {
        color: var(--cal-brand-text);
      }
      .day-events {
        display: flex;
        flex-direction: column;
        gap: 0.125rem;
        margin-top: 0.125rem;
      }
      .event-chip {
        position: relative;
        display: block;
        width: 100%;
        border: none;
        text-align: left;
        font-size: var(--boxel-font-size-xs);
        line-height: 1.3;
        padding: 1px var(--boxel-sp-5xs);
        border-radius: var(--boxel-border-radius-sm);
        cursor: grab;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
        transition: filter 0.15s ease-out;
      }
      .event-chip:hover {
        filter: brightness(0.95);
      }
      .event-chip:active {
        cursor: grabbing;
      }
      /* The insertion line: the dragged chip lands ABOVE the chip wearing it.
         Drawn as a ::before so it costs no layout — a real element here would
         reflow the cell mid-drag and make the target jump away from the
         cursor. `bottom: 100%` puts it in the gap, not over the chip's text. */
      .event-chip.drop-before::before {
        content: '';
        position: absolute;
        left: 0;
        right: 0;
        bottom: 100%;
        height: 2px;
        border-radius: 2px;
        background: var(--primary, var(--boxel-highlight));
      }
      /* projected / disabled / density */
      .projected-chip {
        background: transparent !important;
        border: 1px dashed currentColor;
        opacity: 0.75;
        cursor: default;
      }
      .disabled-day {
        background: repeating-linear-gradient(
          -45deg,
          transparent 0 6px,
          var(--muted, var(--boxel-100)) 6px 7px
        );
      }
      .disabled-day .day-number {
        color: var(--muted-foreground, var(--boxel-450));
      }
      .density-1 {
        box-shadow: inset 0 0 0 999px
          color-mix(
            in oklab,
            var(--primary, var(--boxel-highlight)) 6%,
            transparent
          );
      }
      .density-2 {
        box-shadow: inset 0 0 0 999px
          color-mix(
            in oklab,
            var(--primary, var(--boxel-highlight)) 12%,
            transparent
          );
      }
      .density-3 {
        box-shadow: inset 0 0 0 999px
          color-mix(
            in oklab,
            var(--primary, var(--boxel-highlight)) 20%,
            transparent
          );
      }
      .overflow {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground, var(--boxel-450));
        background: none;
        border: none;
        padding: 0;
        text-align: left;
        cursor: pointer;
        font-family: inherit;
      }
      .overflow:hover {
        text-decoration: underline;
      }
    </style>
  </template>
}
