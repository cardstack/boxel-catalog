import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { htmlSafe } from '@ember/template';
import { eq, gt } from '@cardstack/boxel-ui/helpers';
import { StatePill } from '@cardstack/catalog/components/state-pill';

import type { Asset } from '../asset';
import type { WorkOrder } from '../work-order';
import type { MaintenancePlan } from '../maintenance-plan';
import type { Location } from '@cardstack/catalog/cards/events/location';
import type { SparePart } from '../spare-part';
import type { Meter } from '../meter';
import { WO_STATUS_HUE, WO_TERMINAL } from '../maintenance-vocabulary';
import { stateColor, type Hue } from '@cardstack/catalog/components/state-pill';
import {
  isPlanOccurrenceRaised,
  raisedPlanOccurrences,
} from '../utils/maintenance';
import { relativeStamp } from '../utils/relative-time';

/*
  A maintenance plant is governed by time, so the page is a time axis:
  overdue work left of a hard NOW rule, the next fourteen days right of it.
  Marks stack up from a baseline, height = priority, colour = status. Beneath,
  a detail column against a narrow numeric margin whose status counts are the
  filter controls.
*/

const MS_PER_DAY = 86_400_000;
const HORIZON_DAYS = 14;
/** Mark height encodes priority; colour is already spent on status. */
const PRIORITY_WEIGHT: Record<string, number> = {
  P1: 1,
  P2: 0.76,
  P3: 0.56,
  P4: 0.4,
};
/** Floor so a single P4 on a quiet day is still a visible block. */
const MARK_MIN_PX = 14;
/** Marks drawn per column before the rest collapse into a "+n". */
const STACK_CAP = 4;

interface Mark {
  id: string;
  card: unknown;
  title: string;
  tag: string;
  assetName: string;
  status: string;
  hue: Hue;
  priority: string;
  date: Date;
  daysOut: number;
  overdue: boolean;
  /** A plan's computed next-due date, or a meter's projected crossing —
      expected, not booked. Drawn as an outline rather than a solid. */
  planned: boolean;
}

/** A condition that is true NOW and carries no date — it cannot sit on a time
    axis without inventing one, so it gets its own strip. */
interface Alert {
  id: string;
  card: unknown;
  label: string;
  detail: string;
  hue: Hue;
}

interface Column {
  key: string;
  zone: 'late' | 'ahead';
  daysOut: number;
  /** Sparse axis label; blank on the days between the labelled ones. */
  tick: string;
  heading: string;
  marks: Mark[];
  shown: Mark[];
  hidden: number;
  a11y: string;
  /** Summed priority weight — the column's load, and the axis's y value. */
  weight: number;
  /** Non-working day — shaded, so an empty stretch still reads as structure. */
  weekend: boolean;
  /** First column of a new week; carries the ruler's week division. */
  weekStart: boolean;
}

interface Signature {
  Args: {
    assets: Asset[];
    workOrders: WorkOrder[];
    plans: MaintenancePlan[];
    parts?: SparePart[];
    meters?: Meter[];
    teams?: string[];
    locations: Location[];
    onOpen?: (card: unknown) => void;
    onFilter?: (status: string) => void;
  };
  Element: HTMLElement;
}

const startOfDay = (d: Date): number => {
  let x = new Date(d);
  x.setHours(0, 0, 0, 0);
  return x.getTime();
};

const PRIORITY_RANK: Record<string, number> = { P1: 0, P2: 1, P3: 2, P4: 3 };

/**
 * The maintenance landing page, as a time axis. Every open work order and every
 * active plan's next due date is a mark placed against NOW — so "four days of
 * work piled up behind us" is read as mass before it is read as a number.
 */
export class MaintenanceHome extends GlimmerComponent<Signature> {
  /** Which axis column the detail list is showing; null means "overdue + today". */
  @tracked selectedKey: string | null = null;
  /** Status narrowing from the margin index; null means every status. */
  @tracked statusFilter: string | null = null;

  get workOrders(): WorkOrder[] {
    return (this.args.workOrders ?? []).filter(Boolean);
  }

  get openWorkOrders(): WorkOrder[] {
    return this.workOrders.filter((wo) => !WO_TERMINAL.has(wo.status ?? ''));
  }

  hueFor = (status: string): Hue => WO_STATUS_HUE[status] ?? 'slate';

  private get today(): number {
    return startOfDay(new Date());
  }

  /**
   * Both sources land in one mark vocabulary: a scheduled/due work order is
   * booked work, an active plan's `nextDueAt` is expected work. The plan
   * already computed that date with its own lead window — no maths repeated
   * here — so the axis inherits the domain's notion of "due" rather than
   * inventing a second one.
   */
  get marks(): Mark[] {
    let out: Mark[] = [];
    let today = this.today;

    for (let wo of this.openWorkOrders) {
      let raw = wo.dueBy ?? wo.scheduledFor;
      if (!raw) continue;
      let date = new Date(raw);
      out.push({
        id: wo.id,
        card: wo,
        title: wo.title ?? wo.identifier?.value ?? 'Work order',
        tag: wo.assetTag ?? '',
        assetName: wo.assetName ?? '',
        status: wo.status ?? 'requested',
        hue: this.hueFor(wo.status ?? ''),
        priority: wo.priority ?? 'P4',
        date,
        daysOut: Math.round((startOfDay(date) - today) / MS_PER_DAY),
        overdue: Boolean(wo.isOverdue),
        planned: false,
      });
    }

    // A forecast the generator has already turned into a work order is that
    // work order, not a second job — it must not be drawn twice on a surface
    // whose whole purpose is reading load.
    let raised = raisedPlanOccurrences(this.workOrders);
    for (let plan of (this.args.plans ?? []).filter(Boolean)) {
      if (!plan.active || !plan.nextDueAt) continue;
      if (isPlanOccurrenceRaised(raised, plan.id, plan.nextDueAt)) continue;
      let date = new Date(plan.nextDueAt);
      let daysOut = Math.round((startOfDay(date) - today) / MS_PER_DAY);
      out.push({
        id: plan.id,
        card: plan,
        title: plan.name ?? 'Maintenance plan',
        tag: plan.assetTag ?? '',
        assetName: plan.assetName ?? '',
        status: 'planned',
        hue: 'slate',
        priority: plan.priority ?? 'P4',
        date,
        daysOut,
        overdue: daysOut < 0,
        planned: true,
      });
    }

    /*
      A cumulative meter climbing toward its warn threshold has a real,
      derivable arrival date: the plan already computes `averagePerWeek` from
      the last eight readings, so the crossing is arithmetic on stored data,
      not a guess. Gauge meters return no average by construction and are
      excluded — inventing a rate for them would be fabricating evidence.
    */
    for (let meter of (this.args.meters ?? []).filter(Boolean)) {
      let rate = meter.averagePerWeek;
      let current = meter.current;
      let limit = meter.warnAbove as number | undefined;
      if (!rate || rate <= 0 || current == null || limit == null) continue;
      if (current >= limit) continue; // already over: an alert, not a forecast
      let daysOut = Math.round(((limit - current) / rate) * 7);
      if (daysOut < 0 || daysOut > HORIZON_DAYS * 3) continue;
      let date = new Date(today + daysOut * MS_PER_DAY);
      out.push({
        id: meter.id,
        card: meter,
        title: `${meter.name ?? 'Meter'} reaches ${limit}${meter.unit ? ` ${meter.unit}` : ''}`,
        tag: meter.assetTag ?? '',
        assetName: meter.assetName ?? '',
        status: 'meter',
        hue: 'purple',
        priority: 'P3',
        date,
        daysOut,
        overdue: false,
        planned: true,
      });
    }
    return out;
  }

  /**
   * The dateless half of "what needs me now": conditions that are already
   * true and have no arrival time. A spare part carries no consumption rate
   * anywhere in the schema, so it can never be projected onto the axis — the
   * honest move is a standing alert, not a fabricated date.
   */
  get alerts(): Alert[] {
    let out: Alert[] = [];
    for (let part of (this.args.parts ?? []).filter(Boolean)) {
      if (!part.belowReorderPoint) continue;
      out.push({
        id: part.id,
        card: part,
        label: part.name ?? 'Spare part',
        detail: `${part.onHand ?? 0} on hand · reorder at ${part.reorderPoint ?? 0}`,
        hue: 'orange',
      });
    }
    for (let meter of (this.args.meters ?? []).filter(Boolean)) {
      if (!meter.isWarning) continue;
      out.push({
        id: meter.id,
        card: meter,
        label: `${meter.assetName ?? 'Asset'} · ${meter.name ?? 'meter'}`,
        detail: `${meter.currentLabel ?? meter.current} — ${meter.isWarning} threshold`,
        hue: 'red',
      });
    }
    for (let asset of (this.args.assets ?? []).filter(Boolean)) {
      if (asset.status !== 'down') continue;
      out.push({
        id: asset.id,
        card: asset,
        label: asset.cardTitle ?? 'Asset',
        detail: 'down',
        hue: 'red',
      });
    }
    return out;
  }

  private orderMarks(list: Mark[]): Mark[] {
    return [...list].sort((a, b) => {
      let p =
        (PRIORITY_RANK[a.priority] ?? 4) - (PRIORITY_RANK[b.priority] ?? 4);
      if (p !== 0) return p;
      return a.date.getTime() - b.date.getTime();
    });
  }

  private buildColumn(
    key: string,
    zone: 'late' | 'ahead',
    daysOut: number,
    tick: string,
    heading: string,
    marks: Mark[],
    opts: { weekend?: boolean; weekStart?: boolean } = {},
  ): Column {
    let ordered = this.orderMarks(marks);
    let n = ordered.length;
    return {
      key,
      zone,
      daysOut,
      tick,
      heading,
      marks: ordered,
      shown: ordered.slice(0, STACK_CAP),
      hidden: Math.max(0, n - STACK_CAP),
      a11y: `${heading}, ${n} ${n === 1 ? 'item' : 'items'}`,
      weight: ordered
        .slice(0, STACK_CAP)
        .reduce((sum, m) => sum + (PRIORITY_WEIGHT[m.priority] ?? 0.4), 0),
      weekend: Boolean(opts.weekend),
      weekStart: Boolean(opts.weekStart),
    };
  }

  /**
   * Overdue gets one column per distinct day that actually has work, oldest
   * first — so a single item three months late does not stretch an empty
   * hundred-day ruler across the left of the page. Order stays true; only the
   * empty gaps are spent.
   */
  get lateColumns(): Column[] {
    let byDay = new Map<number, Mark[]>();
    for (let m of this.marks) {
      if (m.daysOut >= 0) continue;
      let list = byDay.get(m.daysOut) ?? [];
      list.push(m);
      byDay.set(m.daysOut, list);
    }
    let days = [...byDay.keys()].sort((a, b) => a - b);
    return days.map((daysOut, i) => {
      let late = Math.abs(daysOut);
      // Late columns sit shoulder to shoulder, so a tick under every one runs
      // the labels together ("14d13d9d"). Only the two that bound the range
      // are labelled; the rest are read by position between them.
      let labelled = i === 0 || i === days.length - 1;
      return this.buildColumn(
        `late:${daysOut}`,
        'late',
        daysOut,
        labelled ? `${late}d` : '',
        late === 1 ? '1 day late' : `${late} days late`,
        byDay.get(daysOut)!,
      );
    });
  }

  get aheadColumns(): Column[] {
    let cols: Column[] = [];
    for (let d = 0; d <= HORIZON_DAYS; d += 1) {
      let marks = this.marks.filter((m) => m.daysOut === d);
      let heading =
        d === 0 ? 'Due today' : d === 1 ? 'Due tomorrow' : `Due in ${d} days`;
      // Label only the anchors; a tick under every day is noise at this scale.
      let tick = d === 0 ? 'today' : d % 7 === 0 ? `+${d}d` : '';
      let day = new Date(this.today + d * MS_PER_DAY).getDay();
      cols.push(
        this.buildColumn(`ahead:${d}`, 'ahead', d, tick, heading, marks, {
          weekend: day === 0 || day === 6,
          weekStart: d > 0 && day === 1,
        }),
      );
    }
    let beyond = this.marks.filter((m) => m.daysOut > HORIZON_DAYS);
    if (beyond.length) {
      cols.push(
        this.buildColumn(
          'ahead:later',
          'ahead',
          HORIZON_DAYS + 1,
          'later',
          'Due later',
          beyond,
        ),
      );
    }
    return cols;
  }

  get hasMarks(): boolean {
    return this.marks.length > 0;
  }

  get lateCount(): number {
    return this.marks.filter((m) => m.daysOut < 0).length;
  }

  select = (key: string) => {
    this.selectedKey = this.selectedKey === key ? null : key;
  };

  get selectedColumn(): Column | undefined {
    if (!this.selectedKey) return undefined;
    return [...this.lateColumns, ...this.aheadColumns].find(
      (c) => c.key === this.selectedKey,
    );
  }

  /** Default view: everything already late, plus everything due today. */
  get detailMarks(): Mark[] {
    let col = this.selectedColumn;
    let base = col
      ? col.marks
      : this.orderMarks(this.marks.filter((m) => m.daysOut <= 0));
    if (!this.statusFilter) return base;
    return base.filter((m) => m.status === this.statusFilter);
  }

  get detailHeading(): string {
    let col = this.selectedColumn;
    if (col) return col.heading;
    return this.lateCount ? 'Late and due today' : 'Due today';
  }

  get hasFilter(): boolean {
    return Boolean(this.selectedKey || this.statusFilter);
  }

  get detailEmpty(): string {
    if (this.statusFilter) {
      return `Nothing ${this.statusFilter} here. Clear the filter to see the rest.`;
    }
    return this.selectedColumn
      ? 'Nothing on this day.'
      : 'Nothing late, nothing due today.';
  }

  clearFilters = () => {
    this.selectedKey = null;
    this.statusFilter = null;
  };

  /**
   * The pipeline, flattened into the page's numeric margin. These were the
   * donut's segments; as plain counts they stay clickable (the same
   * `onFilter` contract) and cost the page no chart.
   */
  get statusIndex(): { status: string; count: number; hue: Hue }[] {
    let counts = new Map<string, number>();
    for (let wo of this.openWorkOrders) {
      let s = wo.status ?? 'requested';
      counts.set(s, (counts.get(s) ?? 0) + 1);
    }
    return [...counts.entries()]
      .sort((a, b) => b[1] - a[1])
      .map(([status, count]) => ({ status, count, hue: this.hueFor(status) }));
  }

  get openCount(): number {
    return this.openWorkOrders.length;
  }

  /**
   * The busiest column in view sets the top of the band, so the axis has a
   * real load scale instead of fixed-height blocks floating in a tall empty
   * box. Every other column is read against it.
   */
  get peakWeight(): number {
    let cols = [...this.lateColumns, ...this.aheadColumns];
    return Math.max(1, ...cols.map((c) => c.weight));
  }

  markStyle = (m: Mark) => {
    // Scaled against the band's own height token rather than a percentage:
    // the stack sits in a `1fr` grid row whose height is not definite at
    // layout time, so percentage heights collapse to the floor.
    let share = (PRIORITY_WEIGHT[m.priority] ?? 0.4) / this.peakWeight;
    let h = `max(${MARK_MIN_PX}px, calc(var(--home-band) * ${(share * 0.92).toFixed(3)}))`;
    let { ring } = stateColor(m.hue);
    // `ring` is the undiluted hue. Safe here and only here: a mark carries no
    // text, so it is hue-as-data exactly as the theming contract allows.
    return htmlSafe(
      m.planned
        ? `height:${h};border:1px dashed ${ring};`
        : `height:${h};background:${ring};`,
    );
  };

  dotStyle = (hue: Hue) => htmlSafe(`background:${stateColor(hue).ring};`);

  dueLabel = (m: Mark) => relativeStamp(m.date) ?? '—';

  open = (card: unknown) => this.args.onOpen?.(card);

  /**
   * The margin index narrows this page's list in place, and still forwards
   * `onFilter` for a host that supplies one.
   */
  filterByStatus = (status: string) => {
    this.statusFilter = this.statusFilter === status ? null : status;
    this.args.onFilter?.(status);
  };

  <template>
    <div class='home' ...attributes>
      <section class='axis' aria-label='Maintenance load over time'>
        <div class='axis-head'>
          <h2 class='axis-h {{if this.lateCount "hot"}}'>
            {{#if this.lateCount}}{{this.lateCount}} late{{else}}Nothing late{{/if}}
          </h2>
          <h2 class='axis-h axis-h-ahead'>Next {{HORIZON_DAYS}} days</h2>
        </div>

        <div class='band'>
          <div class='zone zone-late'>
            {{#each this.lateColumns key='key' as |col|}}
              <button
                type='button'
                class='col {{if (eq col.key this.selectedKey) "on"}}'
                aria-pressed={{if (eq col.key this.selectedKey) 'true' 'false'}}
                aria-label={{col.a11y}}
                {{on 'click' (fn this.select col.key)}}
              >
                <span class='stack'>
                  {{#each col.shown key='id' as |m|}}
                    <span
                      class='mark {{if m.planned "planned"}}'
                      style={{this.markStyle m}}
                    ></span>
                  {{/each}}
                  {{#if (gt col.hidden 0)}}
                    <span class='more'>+{{col.hidden}}</span>
                  {{/if}}
                </span>
                <span class='tick'>{{col.tick}}</span>
              </button>
            {{else}}
              <p class='zone-quiet'>Nothing behind</p>
            {{/each}}
          </div>

          <div class='now' aria-hidden='true'><span
              class='now-label'
            >NOW</span></div>

          <div class='zone zone-ahead'>
            {{#each this.aheadColumns key='key' as |col|}}
              <button
                type='button'
                class='col
                  {{if (eq col.key this.selectedKey) "on"}}
                  {{if col.weekend "weekend"}}
                  {{if col.weekStart "week-start"}}'
                aria-pressed={{if (eq col.key this.selectedKey) 'true' 'false'}}
                aria-label={{col.a11y}}
                {{on 'click' (fn this.select col.key)}}
              >
                <span class='stack'>
                  {{#each col.shown key='id' as |m|}}
                    <span
                      class='mark {{if m.planned "planned"}}'
                      style={{this.markStyle m}}
                    ></span>
                  {{/each}}
                  {{#if (gt col.hidden 0)}}
                    <span class='more'>+{{col.hidden}}</span>
                  {{/if}}
                </span>
                <span class='tick'>{{col.tick}}</span>
              </button>
            {{/each}}
          </div>
        </div>

        {{#unless this.hasMarks}}
          <p class='band-empty'>
            No open work is scheduled in this window. The next
            {{HORIZON_DAYS}}
            days are clear.
          </p>
        {{/unless}}
      </section>

      {{#if this.alerts.length}}
        <section class='alerts' aria-label='Needs attention now'>
          <h2 class='alerts-h'>Needs attention now</h2>
          <ul class='alert-list'>
            {{#each this.alerts key='id' as |a|}}
              <li>
                <button
                  type='button'
                  class='alert'
                  {{on 'click' (fn this.open a.card)}}
                >
                  <span class='alert-dot' style={{this.dotStyle a.hue}}></span>
                  <span class='alert-label'>{{a.label}}</span>
                  <span class='alert-detail'>{{a.detail}}</span>
                </button>
              </li>
            {{/each}}
          </ul>
        </section>
      {{/if}}

      <div class='below'>
        <section class='detail'>
          <h2 class='detail-h'>
            {{this.detailHeading}}
            {{#if this.statusFilter}}
              <span class='detail-qualifier'>· {{this.statusFilter}}</span>
            {{/if}}
            {{#if this.hasFilter}}
              <button
                type='button'
                class='clear'
                {{on 'click' this.clearFilters}}
              >
                Clear filter
              </button>
            {{/if}}
          </h2>
          <ul class='rows'>
            {{#each this.detailMarks key='id' as |m|}}
              <li>
                <button
                  type='button'
                  class='row'
                  {{on 'click' (fn this.open m.card)}}
                >
                  <code class='row-tag'>{{m.tag}}</code>
                  <span class='row-title'>{{m.title}}</span>
                  <span class='row-asset'>{{m.assetName}}</span>
                  <StatePill @label={{m.status}} @hue={{m.hue}} @dot={{true}} />
                  <span class='row-due {{if m.overdue "late"}}'>{{this.dueLabel
                      m
                    }}</span>
                </button>
              </li>
            {{else}}
              <li class='rows-empty'>{{this.detailEmpty}}</li>
            {{/each}}
          </ul>
        </section>

        <aside class='index' aria-label='Open work by status'>
          <h2 class='index-h'>Open work</h2>
          <p class='index-total'>{{this.openCount}}</p>
          <ul class='index-list'>
            {{#each this.statusIndex key='status' as |s|}}
              <li>
                <button
                  type='button'
                  class='index-row {{if (eq s.status this.statusFilter) "on"}}'
                  aria-pressed={{if
                    (eq s.status this.statusFilter)
                    'true'
                    'false'
                  }}
                  {{on 'click' (fn this.filterByStatus s.status)}}
                >
                  <span class='index-dot' style={{this.dotStyle s.hue}}></span>
                  <span class='index-label'>{{s.status}}</span>
                  <span class='index-n'>{{s.count}}</span>
                </button>
              </li>
            {{/each}}
          </ul>
        </aside>
      </div>
    </div>

    <style scoped>
      /* One ground, no panels. Every boundary on this page is a hairline rule
         or plain space — no section owns a border box or a background. */
      .home {
        container-type: inline-size;
        container-name: home;
        display: grid;
        /* Apple's 4pt base unit, at the page's largest step. */
        gap: 1.5rem;
        min-width: 0;
        color: var(--foreground);
        /* The grouped canvas bleeds past the tab body's own inset and pays it
           back inside, so the gray reaches the edges the way a Settings pane
           does rather than sitting in a white letterbox. */
        margin: calc(-1 * var(--boxel-sp));
        padding: 1.5rem var(--boxel-sp);
        background: var(--hig-canvas);
        /* --- Apple HIG layer -------------------------------------------
           Clarity, deference, depth. The page is a grouped canvas; content
           sits on ONE level of borderless, continuous-corner surface. Colours
           stay on the theme tokens (a linked theme must still carry this);
           only the geometry, elevation and timing are Apple's literal values,
           because no token exists for those. */
        --hig-radius: 1.25rem;
        --hig-radius-sm: 0.75rem;
        --hig-hairline: 0.5px;
        --hig-shadow: var(--shadow-sm);
        --hig-shadow-md: var(--shadow-md);
        /* Grouped background: the canvas is a step darker than the surface,
           which is what lets a borderless panel read as raised. */
        --hig-canvas: color-mix(in oklab, var(--foreground) 5%, var(--card));
        --hig-surface: var(--card);
        --hig-spring: cubic-bezier(0.25, 0.1, 0.25, 1);
        --hig-spring-bounce: cubic-bezier(0.175, 0.885, 0.32, 1.275);
        font-family:
          -apple-system, BlinkMacSystemFont, 'SF Pro Display', 'SF Pro Text',
          system-ui, sans-serif;
        letter-spacing: -0.01em;

        --home-rule: color-mix(in oklab, var(--foreground) 12%, transparent);
        --home-gutter: var(--boxel-sp);
        /* The axis's load scale. Marks are sized against this, so the busiest
           column reaches the top of the band and every other day is read
           against it. */
        --home-band: clamp(9rem, 24vh, 14rem);
      }
      .home ::selection {
        background: color-mix(in oklab, var(--primary) 24%, var(--card));
        color: var(--foreground);
      }
      /* Apple's focus ring: thick, soft, offset — a halo, not a hairline box. */
      .home :focus-visible {
        outline: 0.25rem solid
          color-mix(in oklab, var(--primary) 60%, transparent);
        outline-offset: 1px;
        border-radius: var(--hig-radius-sm);
      }

      /* ---- the axis ---------------------------------------------------- */
      /* Full-bleed: cancels the tab body's own inset so the band reaches both
         edges, then re-pays it inside. The axis owning the full width is the
         thesis — boxed, it would read as one more widget. */
      .axis {
        /* The hero widget: one continuous-corner surface on the canvas, no
           border, depth carried by a soft low-opacity shadow the way a macOS
           panel does it. */
        border-radius: var(--hig-radius);
        box-shadow: var(--hig-shadow-md);
        padding: 1.25rem 1.5rem 0.75rem;
        display: grid;
        gap: 1rem;
        /* An instrument field, not a panel: full-bleed, no border, no radius.
           Derived from --foreground rather than a literal, so a linked theme
           carries it. The dark ground is what makes a saturated status mark
           read as a lit signal instead of a pastel sticker on paper. */
        --axis-ground: color-mix(in oklab, var(--foreground) 93%, var(--card));
        --axis-ink: color-mix(in oklab, var(--card) 94%, var(--foreground));
        --axis-ink-dim: color-mix(
          in oklab,
          var(--card) 62%,
          var(--axis-ground)
        );
        --axis-rule: color-mix(in oklab, var(--card) 26%, var(--axis-ground));
        background: var(--axis-ground);
        color: var(--axis-ink);
      }
      .axis ::selection {
        background: color-mix(in oklab, var(--primary) 40%, var(--axis-ground));
        color: var(--axis-ink);
      }
      .axis-head {
        display: grid;
        grid-template-columns: auto 1fr;
        align-items: baseline;
        gap: var(--boxel-sp);
      }
      /* The page's scale contrast lives here. The count is set INSIDE the
         heading, directly above the pile it counts — typography doing the
         work, not a metric tile parked next to a chart. */
      .axis-h {
        margin: 0;
        font-size: clamp(1.75rem, 3.4vw, 2.75rem);
        font-weight: 700;
        line-height: 1;
        letter-spacing: -0.03em;
        font-variant-numeric: tabular-nums;
        color: var(--axis-ink);
        white-space: nowrap;
      }
      /* The destructive token is tuned for a light ground; on the dark field
         it is lifted toward the ink until it reads as a warning light. */
      .axis-h.hot {
        color: color-mix(in oklab, var(--destructive) 62%, var(--axis-ink));
      }
      .axis-h-ahead {
        justify-self: start;
        font-size: clamp(0.9rem, 1.5vw, 1.125rem);
        font-weight: 600;
        letter-spacing: 0;
        color: var(--axis-ink-dim);
        align-self: end;
        padding-bottom: 0.15em;
      }
      /* The axis is the dominant object on the page, not a strip above it. */
      .band {
        display: grid;
        grid-template-columns: auto auto 1fr;
        align-items: end;
        min-height: var(--home-band);
        border-bottom: 2px solid var(--axis-rule);
      }
      .zone {
        display: flex;
        align-items: flex-end;
        gap: 2px;
        min-width: 0;
      }
      .zone-late {
        justify-content: flex-end;
      }
      /* Late work carries the page. Give its columns real width so the pile
         behind NOW has mass, instead of hairlines beside a wide open future. */
      .zone-late .col {
        flex: 0 0 auto;
        min-width: 2.75rem;
      }
      .zone-ahead {
        flex: 1;
      }
      /* The one horizontal scroller on the page, and only when the fifteen
         day columns can no longer hold a 1.5rem target. The page body itself
         never scrolls sideways. */
      @container home (width < 34rem) {
        .zone-ahead {
          overflow-x: auto;
          scrollbar-width: thin;
          scrollbar-color: var(--home-rule) transparent;
        }
        .zone-ahead .col {
          flex: 0 0 1.75rem;
        }
      }
      .zone-quiet {
        margin: 0 var(--boxel-sp-xs) var(--boxel-sp-xs) 0;
        font-size: var(--boxel-font-size-xs);
        color: var(--axis-ink-dim);
        white-space: nowrap;
      }

      /* The focal moment: a hard rule the eye reads before any number. */
      .now {
        position: relative;
        align-self: stretch;
        width: 0.1875rem;
        margin-inline: var(--boxel-sp-sm);
        background: var(--axis-ink);
      }
      .now-label {
        position: absolute;
        top: 0;
        left: 50%;
        transform: translateX(-50%);
        font-size: 0.6875rem;
        font-weight: 700;
        letter-spacing: 0.14em;
        color: var(--axis-ground);
        background: var(--axis-ink);
        padding: 0.15rem 0.35rem;
        border-radius: 2px;
      }

      .col {
        flex: 1 1 0;
        min-width: 0;
        align-self: stretch;
        display: grid;
        grid-template-rows: 1fr auto;
        justify-items: center;
        gap: var(--boxel-sp-5xs);
        padding: 0;
        border: none;
        background: transparent;
        color: inherit;
        font: inherit;
        cursor: pointer;
        border-radius: var(--boxel-border-radius-sm);
        transition: background-color 140ms ease-out;
      }
      /* An empty day still draws: the weekend shade and the week division are
         the ruler. Without them a sparse fortnight reads as a blank field
         rather than as a calendar with nothing booked on it. */
      /* On the dark field the weekend reads as a LIFT, not a shade. Kept faint
         on purpose: any stronger and a full-height tint becomes a bar that
         competes with the marks. */
      .col.weekend {
        background: color-mix(in oklab, var(--axis-ink) 3.5%, transparent);
      }
      .col.week-start {
        box-shadow: inset 1px 0 0 var(--axis-rule);
      }
      .col:hover {
        background: color-mix(in oklab, var(--primary) 22%, transparent);
      }
      .col.on {
        background: color-mix(in oklab, var(--primary) 32%, transparent);
      }
      .stack {
        display: flex;
        flex-direction: column-reverse;
        align-items: stretch;
        justify-content: flex-start;
        gap: 2px;
        height: 100%;
        width: 100%;
        /* Wide enough that a column of marks reads as mass rather than as a
           row of dots; the day's load is the thing the eye should get first. */
        max-width: 3.25rem;
        padding-inline: 0.1875rem;
      }
      .zone-late .stack {
        max-width: 2.5rem;
      }
      .mark {
        display: block;
        flex: 0 0 auto;
        width: 100%;
        border-radius: 2px;
        transform-origin: bottom;
      }
      /* Late work is the thing the page is about — it gets the extra weight,
         so the pile behind NOW reads heavier than the same count ahead of it. */
      .zone-late .mark {
        border-radius: 2px 2px 0 0;
        box-shadow: inset 0 0 0 1px
          color-mix(in oklab, var(--axis-ink) 30%, transparent);
      }
      .mark.planned {
        background: transparent;
      }
      .more {
        font-size: 0.5625rem;
        line-height: 1.1;
        color: var(--axis-ink-dim);
        font-variant-numeric: tabular-nums;
        text-align: center;
      }
      .tick {
        font-size: 0.625rem;
        line-height: 1;
        padding-top: var(--boxel-sp-5xs);
        color: var(--axis-ink-dim);
        font-variant-numeric: tabular-nums;
        white-space: nowrap;
        min-height: 0.75rem;
      }
      .band-empty {
        margin: 0;
        max-width: 34rem;
        color: var(--axis-ink-dim);
        font-size: var(--boxel-font-size-sm);
      }
      .axis :focus-visible {
        outline-color: var(--axis-ink);
      }
      @container home (width < 34rem) {
        .zone-ahead {
          scrollbar-color: var(--axis-rule) transparent;
        }
      }

      /* ---- detail + numeric margin ------------------------------------- */
      .below {
        display: grid;
        grid-template-columns: minmax(0, 1fr) minmax(9rem, 15rem);
        gap: 1.25rem;
        align-items: start;
      }
      @container home (width < 46rem) {
        .below {
          grid-template-columns: minmax(0, 1fr);
          gap: 1.25rem;
        }
      }
      /* The second and last surface level. Borderless, continuous corners,
         the same elevation vocabulary as the axis — never a box inside a box. */
      .detail,
      .index,
      .alerts {
        background: var(--hig-surface);
        border-radius: var(--hig-radius);
        box-shadow: var(--hig-shadow);
        padding: 1.25rem;
      }
      .alerts-h {
        margin: 0 0 0.75rem;
        font-size: 1.25rem;
        line-height: 1.5625rem;
        font-weight: 600;
        letter-spacing: -0.022em;
      }
      .alert-list {
        list-style: none;
        margin: 0;
        padding: 0;
        display: flex;
        flex-wrap: wrap;
        gap: 0.5rem;
      }
      /* Dateless conditions read as a row of chips, deliberately unlike the
         time-axis marks — nothing here has a "when", and the form should not
         imply one. */
      .alert {
        display: inline-flex;
        align-items: center;
        gap: 0.5rem;
        min-height: 2.75rem;
        padding: 0 0.875rem;
        border: none;
        border-radius: 999px;
        background: color-mix(in oklab, var(--foreground) 5%, transparent);
        color: inherit;
        font: inherit;
        font-size: 0.9375rem;
        letter-spacing: -0.01em;
        cursor: pointer;
        transition:
          background-color 200ms var(--hig-spring),
          transform 350ms var(--hig-spring);
      }
      .alert:hover {
        background: color-mix(in oklab, var(--foreground) 10%, transparent);
      }
      .alert:active {
        transform: scale(0.97);
        transition-duration: 120ms;
      }
      .alert-dot {
        width: 0.5rem;
        height: 0.5rem;
        border-radius: 50%;
        flex: none;
      }
      .alert-label {
        font-weight: 600;
      }
      .alert-detail {
        color: var(--muted-foreground);
        font-size: 0.8125rem;
      }
      /* Apple Title 3: 1.25rem / 1.5625rem leading / -0.45 tracking. */
      .detail-h,
      .index-h {
        margin: 0 0 0.75rem;
        font-size: 1.25rem;
        line-height: 1.5625rem;
        font-weight: 600;
        letter-spacing: -0.022em;
        display: flex;
        align-items: baseline;
        gap: 0.75rem;
        flex-wrap: wrap;
      }
      .detail-qualifier {
        font-weight: 500;
        color: var(--muted-foreground);
        text-transform: capitalize;
      }
      /* A filled system button, scaled down — Apple has no ghost-link control
         at this weight, and a bare underlined word reads as web furniture. */
      .clear {
        border: none;
        border-radius: 999px;
        background: color-mix(in oklab, var(--foreground) 7%, transparent);
        min-height: 1.75rem;
        padding: 0 0.75rem;
        font: inherit;
        font-size: 0.8125rem;
        font-weight: 500;
        letter-spacing: -0.008em;
        color: var(--foreground);
        cursor: pointer;
        transition:
          background-color 200ms var(--hig-spring),
          transform 350ms var(--hig-spring);
      }
      .clear:hover {
        background: color-mix(in oklab, var(--foreground) 12%, transparent);
      }
      .clear:active {
        transform: scale(0.97);
        transition-duration: 120ms;
      }
      .rows,
      .index-list {
        list-style: none;
        margin: 0;
        padding: 0;
      }
      /* A divider between rows, not a box around each. */
      /* Hairline, not a 1px rule. At 0.5px the separator recedes to a division
         of space instead of reading as drawn furniture — the single most
         felt difference between a system-grade list and a web table. */
      .rows > li + li,
      .index-list > li + li {
        border-top: var(--hig-hairline) solid var(--home-rule);
      }
      .row {
        display: grid;
        grid-template-columns: 6.5rem minmax(0, 1fr) auto auto;
        align-items: center;
        gap: var(--boxel-sp-xs) var(--boxel-sp-sm);
        /* The hover ground bleeds a little past the text on both sides, so the
           row reads as a target without drawing a box around itself. */
        width: calc(100% + var(--boxel-sp));
        margin-inline: calc(-1 * var(--boxel-sp-xs));
        min-height: 2.75rem;
        padding: var(--boxel-sp-xs);
        border: none;
        border-radius: var(--hig-radius-sm);
        background: transparent;
        color: inherit;
        font: inherit;
        font-size: 0.9375rem;
        letter-spacing: -0.01em;
        text-align: left;
        cursor: pointer;
        transition:
          background-color 200ms var(--hig-spring),
          transform 350ms var(--hig-spring);
      }
      .row:hover {
        background: color-mix(in oklab, var(--foreground) 4%, transparent);
      }
      /* Press-and-spring-back, not a colour flash. */
      .row:active,
      .index-row:active,
      .col:active {
        transform: scale(0.97);
        transition-duration: 120ms;
      }
      .row-tag {
        font-family: var(
          --boxel-monospace-font-family,
          ui-monospace,
          monospace
        );
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
        white-space: nowrap;
        font-variant-numeric: tabular-nums;
      }
      .row-title {
        min-width: 0;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        font-weight: 600;
      }
      .row-asset {
        display: none;
      }
      @container home (width >= 52rem) {
        .row {
          grid-template-columns:
            6.5rem minmax(0, 1fr) minmax(0, 11rem)
            auto auto;
        }
        .row-asset {
          display: block;
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
        }
      }
      .row-due {
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground);
        white-space: nowrap;
        font-variant-numeric: tabular-nums;
        justify-self: end;
      }
      .row-due.late {
        color: var(--destructive-ink);
        font-weight: 600;
      }
      .rows-empty {
        padding: var(--boxel-sp-sm) 0;
        color: var(--muted-foreground);
        font-size: var(--boxel-font-size-sm);
      }

      @container home (width < 46rem) {
        .index {
          padding-top: 1.25rem;
        }
      }
      .index-total {
        margin: 0 0 var(--boxel-sp-xs);
        font-size: 2.5rem;
        font-weight: 700;
        line-height: 1;
        letter-spacing: -0.03em;
        font-variant-numeric: tabular-nums;
      }
      .index-row {
        display: grid;
        grid-template-columns: 0.5rem minmax(0, 1fr) auto;
        align-items: center;
        gap: var(--boxel-sp-xs);
        width: 100%;
        min-height: 2.75rem;
        padding: 0;
        border: none;
        background: transparent;
        color: inherit;
        font: inherit;
        text-align: left;
        cursor: pointer;
      }
      .index-row:hover .index-label,
      .index-row.on .index-label {
        color: var(--foreground);
      }
      .index-row.on .index-label {
        font-weight: 600;
      }
      /* The selected status is marked on the row itself, so the margin index
         reads as the filter control it now actually is. */
      .index-row.on .index-dot {
        box-shadow: 0 0 0 0.1875rem
          color-mix(in oklab, var(--primary) 40%, transparent);
      }
      .index-dot {
        width: 0.5rem;
        height: 0.5rem;
        border-radius: 50%;
      }
      .index-label {
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground);
        text-transform: capitalize;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        transition: color 140ms ease-out;
      }
      .index-n {
        font-size: var(--boxel-font-size-sm);
        font-weight: 600;
        font-variant-numeric: tabular-nums;
      }

      /* ---- motion: one authored moment --------------------------------- */
      /* The marks grow out of the baseline, left to right, so the page is
         first understood as accumulation against NOW. Nothing else animates
         on arrival; this is the only entrance the page gets. */
      @keyframes mark-rise {
        from {
          transform: scaleY(0.02);
          opacity: 0;
        }
        to {
          transform: scaleY(1);
          opacity: 1;
        }
      }
      /* Spring physics, in Apple's 250–500ms band, transform+opacity only. */
      .mark {
        animation: mark-rise 480ms var(--hig-spring-bounce) backwards;
      }
      .zone-late .col:nth-child(1) .mark {
        animation-delay: 20ms;
      }
      .zone-late .col:nth-child(2) .mark {
        animation-delay: 45ms;
      }
      .zone-late .col:nth-child(n + 3) .mark {
        animation-delay: 70ms;
      }
      .zone-ahead .col:nth-child(1) .mark {
        animation-delay: 110ms;
      }
      .zone-ahead .col:nth-child(2) .mark {
        animation-delay: 130ms;
      }
      .zone-ahead .col:nth-child(3) .mark {
        animation-delay: 150ms;
      }
      .zone-ahead .col:nth-child(4) .mark {
        animation-delay: 170ms;
      }
      .zone-ahead .col:nth-child(5) .mark {
        animation-delay: 190ms;
      }
      .zone-ahead .col:nth-child(6) .mark {
        animation-delay: 210ms;
      }
      .zone-ahead .col:nth-child(7) .mark {
        animation-delay: 230ms;
      }
      .zone-ahead .col:nth-child(n + 8) .mark {
        animation-delay: 250ms;
      }
      @media (prefers-reduced-motion: reduce) {
        .mark {
          animation: none;
        }
        .col,
        .row,
        .index-label {
          transition: none;
        }
      }
    </style>
  </template>
}

export default MaintenanceHome;
