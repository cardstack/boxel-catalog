import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { htmlSafe } from '@ember/template';

export type TimelineMarkKind = 'release' | 'due' | 'live' | 'quiz';

export interface TimelineMark {
  kind: TimelineMarkKind;
  label: string;
  date: Date;
  /** For releases: has it actually happened yet? Drawn hollow until it has. */
  done?: boolean;
}

export interface TimelineWeek {
  index: number;
  start: Date;
  end: Date;
  label: string;
  marks: TimelineMark[];
}

interface Signature {
  Args: {
    weeks: TimelineWeek[];
    /** Index of the week containing today; omit when the cohort is not running. */
    todayIndex?: number;
    /** 0–1 position of today inside its week. */
    todayFraction?: number;
    onSelectWeek?: (week: TimelineWeek) => void;
    selectedIndex?: number;
    /** One-row strip for lists and fitted cards; no labels under marks. */
    compact?: boolean;
    ariaLabel?: string;
  };
  Element: HTMLElement;
}

const KIND_LABEL: Record<TimelineMarkKind, string> = {
  release: 'Module release',
  due: 'Assignment due',
  live: 'Live lesson',
  quiz: 'Quiz',
};

/**
 * The cohort timeline rail: one column per week, release marks on top, due
 * marks below, live lessons as dots on the line, and a "today" needle. It is
 * the one visual that says "we run cohorts, not courses", so it is reused at
 * three densities — full on the Cohort page, one row per cohort on Home, and
 * as the Cohort's fitted card — from one component, one data shape.
 *
 * Renders resolved weeks (`buildCohortWeeks` in cohort.gts builds them); no
 * fetching, no card knowledge. Colours are the realm's state hues.
 */
export class CohortTimeline extends GlimmerComponent<Signature> {
  get weeks() {
    return this.args.weeks ?? [];
  }

  get hasToday() {
    return (
      this.args.todayIndex != null &&
      this.args.todayIndex >= 0 &&
      this.args.todayIndex < this.weeks.length
    );
  }

  get todayStyle() {
    if (!this.hasToday) return htmlSafe('');
    let n = this.weeks.length || 1;
    let frac = Math.min(1, Math.max(0, this.args.todayFraction ?? 0.5));
    let left = ((this.args.todayIndex! + frac) / n) * 100;
    return htmlSafe(`left: ${left.toFixed(2)}%;`);
  }

  isSelected = (w: TimelineWeek) => this.args.selectedIndex === w.index;
  isPast = (w: TimelineWeek) =>
    this.hasToday && w.index < this.args.todayIndex!;
  isCurrent = (w: TimelineWeek) =>
    this.hasToday && w.index === this.args.todayIndex;

  top = (w: TimelineWeek) => w.marks.filter((m) => m.kind === 'release');
  line = (w: TimelineWeek) => w.marks.filter((m) => m.kind === 'live');
  bottom = (w: TimelineWeek) =>
    w.marks.filter((m) => m.kind === 'due' || m.kind === 'quiz');

  title = (m: TimelineMark) =>
    `${KIND_LABEL[m.kind]}: ${m.label} — ${m.date.toLocaleDateString(undefined, { weekday: 'short', month: 'short', day: 'numeric' })}`;

  select = (w: TimelineWeek) => {
    this.args.onSelectWeek?.(w);
  };

  <template>
    <div
      class='rail {{if @compact "compact"}} {{if @onSelectWeek "interactive"}}'
      role={{if @onSelectWeek 'listbox' 'img'}}
      aria-label={{if @ariaLabel @ariaLabel 'Cohort timeline'}}
      ...attributes
    >
      {{#if this.weeks.length}}
        <div class='weeks' style={{htmlSafe (gridCols this.weeks.length)}}>
          {{#each this.weeks as |w|}}
            {{#if @onSelectWeek}}
              <button
                type='button'
                class='week
                  {{if (this.isPast w) "past"}}
                  {{if (this.isCurrent w) "current"}}
                  {{if (this.isSelected w) "selected"}}'
                aria-pressed={{if (this.isSelected w) 'true' 'false'}}
                aria-label='Week {{w.index}}: {{w.label}}, {{w.marks.length}} events'
                {{on 'click' (fn this.select w)}}
              >
                <span class='top'>{{#each (this.top w) as |m|}}<span
                      class='mark rel {{if m.done "done"}}'
                      title={{this.title m}}
                    ></span>{{/each}}</span>
                <span class='line'>{{#each (this.line w) as |m|}}<span
                      class='dot'
                      title={{this.title m}}
                    ></span>{{/each}}</span>
                <span class='bottom'>{{#each (this.bottom w) as |m|}}<span
                      class='mark {{m.kind}}'
                      title={{this.title m}}
                    ></span>{{/each}}</span>
                {{#unless @compact}}<span
                    class='wk'
                  >W{{w.index}}</span>{{/unless}}
              </button>
            {{else}}
              <div
                class='week
                  {{if (this.isPast w) "past"}}
                  {{if (this.isCurrent w) "current"}}'
                aria-hidden='true'
              >
                <span class='top'>{{#each (this.top w) as |m|}}<span
                      class='mark rel {{if m.done "done"}}'
                      title={{this.title m}}
                    ></span>{{/each}}</span>
                <span class='line'>{{#each (this.line w) as |m|}}<span
                      class='dot'
                      title={{this.title m}}
                    ></span>{{/each}}</span>
                <span class='bottom'>{{#each (this.bottom w) as |m|}}<span
                      class='mark {{m.kind}}'
                      title={{this.title m}}
                    ></span>{{/each}}</span>
                {{#unless @compact}}<span
                    class='wk'
                  >W{{w.index}}</span>{{/unless}}
              </div>
            {{/if}}
          {{/each}}
          {{#if this.hasToday}}
            <span
              class='today'
              style={{this.todayStyle}}
              aria-hidden='true'
            ><span class='today-tag'>today</span></span>
          {{/if}}
        </div>
        {{#unless @compact}}
          <div class='legend' aria-hidden='true'>
            <span><i class='mark rel done'></i>release</span>
            <span><i class='dot'></i>live</span>
            <span><i class='mark due'></i>due</span>
            <span><i class='mark quiz'></i>quiz</span>
          </div>
        {{/unless}}
      {{else}}
        <p class='empty'>No term set. Give the cohort a start and end date to
          draw its weeks.</p>
      {{/if}}
    </div>
    <style scoped>
      .rail {
        --tl-line: var(--border);
        --tl-release: var(--primary);
        --tl-due: var(--warning);
        --tl-quiz: var(--chart-4);
        --tl-live: var(--chart-2);
        --tl-today: var(--destructive);
        --tl-h: 4.25rem;
        color: var(--foreground);
        position: relative;
      }
      .rail.compact {
        --tl-h: 2rem;
      }
      @media (prefers-reduced-motion: no-preference) {
        .today-tag {
          animation: tl-breathe 2.8s ease-in-out infinite;
        }
        .interactive .week {
          transition: background 140ms ease;
        }
        .mark,
        .dot {
          transition: transform 160ms cubic-bezier(0.2, 0.8, 0.2, 1);
        }
        .interactive .week:hover .mark,
        .interactive .week:hover .dot {
          transform: scale(1.35);
        }
        .interactive .week:hover .mark.rel {
          transform: rotate(45deg) scale(1.35);
        }
      }
      @keyframes tl-breathe {
        0%,
        100% {
          opacity: 1;
        }
        50% {
          opacity: 0.45;
        }
      }
      .weeks {
        position: relative;
        display: grid;
        gap: 0.125rem;
        height: var(--tl-h);
      }
      .rail:not(.compact) .weeks {
        height: calc(var(--tl-h) + 1.1rem);
      }
      .week {
        position: relative;
        display: grid;
        grid-template-rows: 1fr auto 1fr auto;
        align-items: center;
        justify-items: center;
        padding: 0;
        border: 0;
        border-radius: var(--boxel-border-radius-sm);
        background: transparent;
        color: inherit;
        font: inherit;
        min-width: 0;
      }
      .interactive .week {
        cursor: pointer;
      }
      .interactive .week:hover {
        background: var(--muted);
      }
      .week:focus-visible {
        outline: 2px solid var(--ring);
        outline-offset: 1px;
      }
      .week.selected {
        background: color-mix(in oklab, var(--tl-release) 10%, transparent);
      }
      .week.past {
        opacity: 0.6;
      }
      .week.current .line {
        background: color-mix(in oklab, var(--tl-release) 70%, var(--tl-line));
      }
      .top,
      .bottom {
        display: flex;
        gap: 0.125rem;
        align-items: center;
        min-height: 0.5rem;
      }
      .line {
        width: 100%;
        height: 2px;
        background: var(--tl-line);
        display: flex;
        justify-content: center;
        gap: 0.1875rem;
        align-items: center;
      }
      .mark {
        display: inline-block;
        width: 0.5rem;
        height: 0.5rem;
        border-radius: 2px;
      }
      .mark.rel {
        border: 1.5px solid var(--tl-release);
        transform: rotate(45deg);
        background: transparent;
      }
      .mark.rel.done {
        background: var(--tl-release);
      }
      .mark.due {
        background: var(--tl-due);
      }
      .mark.quiz {
        background: var(--tl-quiz);
        border-radius: 50%;
      }
      .dot {
        display: inline-block;
        width: 0.45rem;
        height: 0.45rem;
        border-radius: 50%;
        background: var(--tl-live);
        box-shadow: 0 0 0 2px var(--card);
      }
      .compact .mark,
      .compact .dot {
        width: 0.35rem;
        height: 0.35rem;
      }
      .wk {
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
        font-variant-numeric: tabular-nums;
      }
      .today {
        position: absolute;
        top: 0;
        bottom: 1.1rem;
        width: 0;
        border-left: 2px solid var(--tl-today);
        pointer-events: none;
      }
      .compact .today {
        bottom: 0;
      }
      .today-tag {
        position: absolute;
        top: -0.1rem;
        left: 0.1875rem;
        font-size: var(--boxel-font-size-2xs);
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.06em;
        color: var(--tl-today);
      }
      .compact .today-tag {
        display: none;
      }
      .legend {
        margin-top: var(--boxel-sp-4xs);
        display: flex;
        gap: var(--boxel-sp-sm);
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
      }
      .legend span {
        display: inline-flex;
        gap: 0.25rem;
        align-items: center;
      }
      .legend i {
        display: inline-block;
      }
      .empty {
        margin: 0;
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground);
        font-style: italic;
      }
    </style>
  </template>
}

function gridCols(n: number) {
  return `grid-template-columns: repeat(${n}, minmax(0, 1fr));`;
}

export default CohortTimeline;
