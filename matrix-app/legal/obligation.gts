import {
  CardDef,
  Component,
  FieldDef,
  StringField,
  contains,
  containsMany,
  field,
  linksTo,
  linksToMany,
} from '@cardstack/base/card-api';
import type { Hue } from './compact-card';
import NumberField from '@cardstack/base/number';
import DateField from '@cardstack/base/date';
import UrlField from '@cardstack/base/url';
import TextAreaField from '@cardstack/base/text-area';
import AmountWithCurrency from '@cardstack/base/amount-with-currency';
import enumField from '@cardstack/base/enum';
import RecurringPatternField from '@cardstack/catalog/fields/recurring-pattern/recurring-pattern';
import ClipboardCheckIcon from '@cardstack/boxel-icons/clipboard-check';

import { Contract } from './contract';
import { Employee } from '../hr/employee';
import { Token } from '@cardstack/pretui/components/token';
import {
  AtomLayout,
  EmbLayout,
  Facts,
  FitLayout,
  IsoLayout,
  LinkRow,
  Mark,
  Section,
  Text,
  stats,
  type Dot,
  type Fact,
} from './compact-card';
import {
  cap,
  dash,
  dayAndYear,
  formatDay,
  shortMoney,
  type Tone,
} from '../shared/compact-format';

/**
 * A promise a contract compels, with a date and an owner.
 *
 * WHY NOT `Task`. The catalog Task was considered and rejected: a task
 * is work somebody chose to do, an obligation is work a signed agreement
 * requires. Missing one is a breach, not a slipped sprint — so lateness here
 * carries a consequence sentence and an escalation, which a task has no place
 * for.
 *
 * WHAT IS CONSUMED. Recurrence is the catalog's `RecurringPatternField`
 * (@cardstack/catalog/fields/recurring-pattern) — a full pattern/interval/
 * end-condition rule that already ships with its own editor. Money is base
 * `AmountWithCurrency`. Neither is re-implemented here.
 *
 * WHAT IS DELIBERATELY NOT STORED. `status` and `nextDueDate` are computed. A
 * stored obligation status is the single most drift-prone value in a
 * compliance app: the dashboard buckets by date while the pill reads the
 * stored enum, and one contract shows "on track" inside the overdue column.
 */

export const OBLIGATION_TYPES = [
  'payment',
  'delivery',
  'notification',
  'compliance',
  'insurance',
  'audit',
];

export const OBLIGATION_TYPE_LABELS: Record<string, string> = {
  payment: 'Payment',
  delivery: 'Delivery',
  notification: 'Notification',
  compliance: 'Compliance',
  insurance: 'Insurance',
  audit: 'Audit',
};

export const ObligationTypeField = enumField(StringField, {
  options: OBLIGATION_TYPES.map((value) => ({
    value,
    label: OBLIGATION_TYPE_LABELS[value],
  })),
  displayName: 'Obligation Type',
  icon: ClipboardCheckIcon,
});

/**
 * Five states, none of them written by a human.
 *
 * There is deliberately no "in progress". Half-discharged is not a compliance
 * state — either the period's duty was met or it was not, and a partial credit
 * is how a 100% score comes to hide a breach.
 */
export const OBLIGATION_STATES = [
  'on_track',
  'due_soon',
  'due_today',
  'overdue',
  'closed',
];

export const OBLIGATION_STATE_LABELS: Record<string, string> = {
  on_track: 'On track',
  due_soon: 'Due soon',
  due_today: 'Due today',
  overdue: 'Overdue',
  closed: 'Closed',
};

export const OBLIGATION_STATE_HUE: Record<string, Hue> = {
  on_track: 'green',
  due_soon: 'amber',
  due_today: 'orange',
  overdue: 'red',
  closed: 'slate',
};

export function obligationStateLabel(value?: string | null): string {
  return OBLIGATION_STATE_LABELS[value ?? ''] ?? '—';
}

/** Days before the due date at which an obligation starts reading as urgent. */
export const DUE_SOON_DAYS = 7;

const MS_PER_DAY = 86_400_000;

function midnightOf(d: Date): number {
  return Date.UTC(d.getFullYear(), d.getMonth(), d.getDate());
}

function daysUntil(date?: Date | string | null): number | undefined {
  if (!date) return undefined;
  let t = new Date(date);
  if (!Number.isFinite(t.getTime())) return undefined;
  return Math.round((midnightOf(t) - midnightOf(new Date())) / MS_PER_DAY);
}

function calendarDay(d: Date): string {
  let m = `${d.getMonth() + 1}`.padStart(2, '0');
  let day = `${d.getDate()}`.padStart(2, '0');
  return `${d.getFullYear()}-${m}-${day}`;
}

/**
 * Advance a calendar date by `n` periods of the given pattern.
 *
 * Built from local year/month/day parts rather than millisecond arithmetic, so
 * a monthly obligation lands on the 5th of each month rather than drifting by
 * a day whenever a daylight-saving boundary falls inside the interval.
 */
function advance(
  start: Date,
  pattern: string | null | undefined,
  interval: number,
  n: number,
): Date {
  let step = Math.max(1, interval || 1) * n;
  let y = start.getFullYear();
  let m = start.getMonth();
  let d = start.getDate();
  switch (pattern) {
    case 'daily':
      return new Date(y, m, d + step);
    case 'weekly':
      return new Date(y, m, d + step * 7);
    case 'monthly':
      return new Date(y, m + step, d);
    case 'quarterly':
      return new Date(y, m + step * 3, d);
    case 'yearly':
      return new Date(y, m + step * 12, d);
    default:
      return new Date(y, m, d);
  }
}

/**
 * One discharged period, with the proof.
 *
 * Evidence lives here rather than on the obligation because the question an
 * auditor asks is "show me September", not "show me the contract". Without a
 * per-period artifact a completed obligation is a claim.
 */
export class ObligationCompletionField extends FieldDef {
  static displayName = 'Obligation Completion';

  /** Which occurrence this discharges, as a calendar day. */
  @field period = contains(StringField);
  @field completedAt = contains(DateField);
  @field completedBy = linksTo(() => Employee);
  /** Proof — a file in the realm, an invoice, a certificate URL. */
  @field evidenceUrl = contains(UrlField);
  @field note = contains(TextAreaField);

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='oc-row'>
        <Token class='oc-period' @value={{@model.period}} @size='xs' />
        {{#if @model.evidenceUrl}}
          <a
            class='oc-link'
            href={{@model.evidenceUrl}}
            target='_blank'
            rel='noopener noreferrer'
          >evidence</a>
        {{else}}
          <span class='oc-none'>no evidence</span>
        {{/if}}
      </div>
      <style scoped>
        .oc-row {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-2xs);
          font-size: var(--boxel-font-size-xs);
        }
        /* Doubled class so the flush margin outranks Token's own. */
        .oc-period.oc-period {
          margin-inline: 0;
        }
        .oc-none {
          color: var(--destructive-ink);
        }
      </style>
    </template>
  };
}

export class Obligation extends CardDef {
  static displayName = 'Obligation';
  static icon = ClipboardCheckIcon;

  @field contract = linksTo(() => Contract);
  @field obligationType = contains(ObligationTypeField);
  @field description = contains(StringField);
  /**
   * What breach costs, in one sentence.
   *
   * Rendered on the card wherever there is room, because a date alone does not
   * motivate anybody — "13 Aug" and "13 Aug, or it auto-renews at $612,400"
   * are read very differently.
   */
  @field consequence = contains(StringField);

  @field amount = contains(AmountWithCurrency);
  @field recurrence = contains(RecurringPatternField);
  @field firstDueDate = contains(DateField);
  @field completions = containsMany(ObligationCompletionField);

  @field owner = linksTo(() => Employee);
  /** Written once, when it first goes past the grace window. */
  @field escalatedTo = linksTo(() => Employee);

  /**
   * REMINDER LADDER — configured here, NOT YET FIRING.
   *
   * Nothing sends them: the platform has no card-reachable scheduler and no
   * notification identity to send as.
   *
   * The schema ships anyway, and the UI says plainly that it is not firing.
   * Leaving the fields out would mean editing every obligation once a
   * scheduler exists. The alternative that
   * would be worse still is wiring a UI that looks like it sends reminders and
   * does not, which on a compliance deadline is an actively dangerous lie.
   *
   * Days BEFORE the due date, e.g. [7, 3, 1] or the renewal ladder [90, 60, 30].
   */
  @field reminderDaysBefore = containsMany(NumberField);
  @field reminderRecipients = linksToMany(() => Employee);
  @field closedAt = contains(DateField);

  @field nextDueDate = contains(StringField, {
    computeVia: function (this: Obligation) {
      if (this.closedAt) return undefined;
      if (!this.firstDueDate) return undefined;
      let start = new Date(this.firstDueDate);
      if (!Number.isFinite(start.getTime())) return undefined;
      let done = (this.completions ?? []).filter(Boolean).length;
      let pattern = this.recurrence?.pattern;
      // A one-time obligation has exactly one occurrence: once it is
      // discharged there is no next date, and reporting one would invent work.
      if (!pattern || pattern === 'none') {
        return done > 0 ? undefined : calendarDay(start);
      }
      let occurrences = this.recurrence?.occurrences;
      if (typeof occurrences === 'number' && done >= occurrences) {
        return undefined;
      }
      let next = advance(start, pattern, this.recurrence?.interval ?? 1, done);
      let end = this.recurrence?.endDate
        ? new Date(this.recurrence.endDate)
        : undefined;
      if (end && Number.isFinite(end.getTime()) && next > end) return undefined;
      return calendarDay(next);
    },
  });

  @field daysUntilDue = contains(NumberField, {
    computeVia: function (this: Obligation) {
      return daysUntil(this.nextDueDate);
    },
  });

  @field status = contains(StringField, {
    computeVia: function (this: Obligation) {
      if (this.closedAt) return 'closed';
      let d = this.daysUntilDue;
      // No next date and not explicitly closed means the schedule ran out —
      // there is nothing left to discharge.
      if (typeof d !== 'number') return 'closed';
      if (d < 0) return 'overdue';
      if (d === 0) return 'due_today';
      if (d <= DUE_SOON_DAYS) return 'due_soon';
      return 'on_track';
    },
  });

  @field isOverdue = contains(NumberField, {
    computeVia: function (this: Obligation) {
      let d = this.daysUntilDue;
      return typeof d === 'number' && d < 0 ? Math.abs(d) : 0;
    },
  });

  @field cardTitle = contains(StringField, {
    computeVia: function (this: Obligation) {
      return this.description?.trim()?.length
        ? this.description
        : 'Untitled obligation';
    },
  });

  @field cardDescription = contains(StringField, {
    computeVia: function (this: Obligation) {
      return [
        OBLIGATION_TYPE_LABELS[this.obligationType ?? ''],
        obligationStateLabel(this.status),
      ]
        .filter(Boolean)
        .join(' · ');
    },
  });

  static isolated = class Isolated extends Component<typeof Obligation> {
    get v() {
      return obligationView(this.args.model);
    }
    <template>
      <IsoLayout
        @title={{this.v.title}}
        @subtitle={{this.v.subtitle}}
        @statuses={{this.v.statuses}}
        @stats={{this.v.stats}}
      >
        <:mark><Mark @text='Ob' @size='lg' /></:mark>
        <:main>
          <Section @title='Description'><Text
            >{{@model.description}}</Text></Section>
          {{#if @model.consequence}}
            <Section @title='Consequence'><Text
              >{{@model.consequence}}</Text></Section>
          {{/if}}
          <Section @title='Schedule'><Facts
              @items={{this.v.schedule}}
            /></Section>
        </:main>
        <:side>
          <Section @title='Linked'>
            <LinkRow @label='Contract'><@fields.contract
                @format='atom'
                @displayContainer={{false}}
              /></LinkRow>
            <LinkRow @label='Owner'><@fields.owner
                @format='atom'
                @displayContainer={{false}}
              /></LinkRow>
            {{#if @model.escalatedTo}}
              <LinkRow @label='Escalates to'><@fields.escalatedTo
                  @format='atom'
                  @displayContainer={{false}}
                /></LinkRow>
            {{/if}}
          </Section>
          <Section @title='Details'><Facts @items={{this.v.facts}} /></Section>
        </:side>
      </IsoLayout>
    </template>
  };

  static fitted = class Fitted extends Component<typeof Obligation> {
    get v() {
      return obligationView(this.args.model);
    }
    <template>
      <FitLayout
        @title={{this.v.title}}
        @subtitle={{this.v.subtitle}}
        @status={{this.v.state}}
        @fact={{this.v.fact}}
        @facts={{this.v.facts}}
        @stats={{this.v.fitStats}}
      >
        <:mark><Mark @text='Ob' /></:mark>
      </FitLayout>
    </template>
  };

  static atom = class Atom extends Component<typeof Obligation> {
    <template>
      <AtomLayout @title={{@model.cardTitle}}><:mark><Mark
            @text='Ob'
            @size='sm'
          /></:mark></AtomLayout>
    </template>
  };

  static embedded = class Embedded extends Component<typeof Obligation> {
    get v() {
      return obligationView(this.args.model);
    }
    <template>
      <EmbLayout
        @title={{this.v.title}}
        @subtitle={{this.v.subtitle}}
        @status={{this.v.state}}
        @fact={{this.v.fact}}
        @facts={{this.v.facts}}
      >
        <:mark><Mark @text='Ob' /></:mark>
        <:linked>
          <LinkRow @label='Owner'><@fields.owner
              @format='atom'
              @displayContainer={{false}}
            /></LinkRow>
        </:linked>
      </EmbLayout>
    </template>
  };
}

const OBLIGATION_TONE: Record<string, Tone> = {
  on_track: 'neutral',
  due_soon: 'warning',
  due_today: 'warning',
  overdue: 'danger',
  closed: 'success',
};

/** The strings every Obligation format shows, read once from the model. */
function obligationView(m?: Partial<Obligation>) {
  let type = OBLIGATION_TYPE_LABELS[m?.obligationType ?? ''] ?? '—';
  let status = m?.status ?? '';
  let d = m?.daysUntilDue;
  let pattern = m?.recurrence?.pattern;
  let repeats = Boolean(pattern) && pattern !== 'none';
  let contract = m?.contract?.cardTitle as string | undefined;
  let owner = m?.owner?.cardTitle as string | undefined;
  let done = (m?.completions ?? []).filter(Boolean).length;
  let due =
    status === 'closed'
      ? 'closed'
      : typeof d !== 'number'
        ? 'no schedule'
        : d < 0
          ? `${Math.abs(d)} days overdue`
          : d === 0
            ? 'due today'
            : `due in ${d} day${d === 1 ? '' : 's'}`;
  let state: Dot = { label: due, tone: OBLIGATION_TONE[status] };
  let [day, year] = dayAndYear(m?.nextDueDate);
  let amount = m?.amount?.amount;
  return {
    title: m?.cardTitle ?? 'Untitled obligation',
    subtitle: [contract, type.toLowerCase()].filter(Boolean).join(' · '),
    state,
    statuses: [state, { label: type.toLowerCase(), tone: 'info' }] as Dot[],
    fact: [
      m?.nextDueDate
        ? `Due ${formatDay(m.nextDueDate)}`
        : obligationStateLabel(status),
      repeats ? pattern : 'one-off',
    ].join(' · '),
    stats: stats([
      {
        label: 'Due',
        value: day,
        hint: [year, typeof d === 'number' ? `${d} days` : undefined]
          .filter(Boolean)
          .join(' · '),
      },
      {
        label: 'Type',
        value: type,
        hint: repeats ? `repeats ${pattern}` : 'one-off',
      },
      typeof amount === 'number'
        ? {
            label: 'Amount',
            value: shortMoney(amount, m?.amount?.currency?.code),
            hint: 'per occurrence',
          }
        : {
            label: 'Completions',
            value: String(done),
            hint: done ? 'on record' : 'none yet',
          },
    ]),
    fitStats: [
      { key: 'Due', value: day },
      { key: 'Type', value: type },
      { key: 'Days left', value: typeof d === 'number' ? String(d) : '—' },
    ],
    schedule: [
      { key: 'First due', value: formatDay(m?.firstDueDate), mono: true },
      { key: 'Next due', value: formatDay(m?.nextDueDate), mono: true },
      { key: 'Recurrence', value: repeats ? cap(pattern) : 'None' },
      { key: 'Completions', value: done ? String(done) : 'none yet' },
    ] as Fact[],
    facts: [
      { key: 'Due', value: formatDay(m?.nextDueDate), mono: true },
      {
        key: 'Days left',
        value: typeof d === 'number' ? String(d) : '—',
        mono: true,
      },
      { key: 'Type', value: type },
      { key: 'Repeats', value: repeats ? 'Yes' : 'No' },
      { key: 'Owner', value: dash(owner) },
      { key: 'Status', value: obligationStateLabel(status) },
    ] as Fact[],
  };
}

export default Obligation;
