import {
  CardDef,
  FieldDef,
  Component,
  field,
  contains,
  containsMany,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import DateTimeField from '@cardstack/base/datetime';
import NumberField from '@cardstack/base/number';
import TimerIcon from '@cardstack/boxel-icons/timer';
import { SlaPolicy } from './sla-policy';
import { SlaTimerField } from './sla-timer-field';
import { SlaWindowField } from '@cardstack/catalog/fields/sla-window/sla-window-field';
import { timerSnapshot, sortByUrgency } from './utils/sla';
import { relativeStamp } from '@cardstack/catalog/fields/created-at/created-at';
import { eq } from '@cardstack/boxel-ui/helpers';
import type { PretuiToneArg } from '@cardstack/pretui/pretui-primitives';
import { Chip } from '@cardstack/pretui/components/chip';
import { FitTile } from '../shared/fit-tile';
import {
  KeyValue,
  type KeyValueItem,
} from '@cardstack/pretui/components/key-value';
import { Panel } from '@cardstack/pretui/components/panel';
import { Stat } from '@cardstack/pretui/components/stat';
import { FittedExtras, type FittedStat } from '../procurement/vendor';

/**
 * A pause on the clock, as an EVENT — never a boolean. While the ball is with
 * the customer, elapsed time stops; the interval is stored so "paused 17h"
 * is answerable, and fairness of the metric is auditable.
 */
export class PauseIntervalField extends FieldDef {
  static displayName = 'Pause Interval';

  @field pausedAt = contains(DateTimeField);
  @field resumedAt = contains(DateTimeField);
  @field reason = contains(StringField, {
    description: 'e.g. waiting-on-customer.',
  });

  @field title = contains(StringField, {
    computeVia: function (this: PauseIntervalField) {
      let from = relativeStamp(this.pausedAt ?? undefined);
      return this.resumedAt
        ? `Paused ${from ?? ''} → resumed`
        : `Paused ${from ?? ''}`;
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <span class='pause'>⏸
        {{@model.title}}{{#if @model.reason}} · {{@model.reason}}{{/if}}</span>
      <style scoped>
        .pause {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };
}

/**
 * The APPLIED SLA: one promise (a reused SLA Policy) attached to one subject,
 * with the clocks running against it.
 *
 * Composition, not reinvention: the clocks are the ServiceDesk's own
 * `SlaTimerField` (deadlineAt already business-hours-adjusted, written only
 * by commands); the window is frozen onto this record at apply time
 * (`SlaWindowField`) so a later edit to the shared Schedule cannot rewrite
 * history; the countdown/urgency maths is `utils/sla.ts` — one source, so the
 * card, the queue sort and any dashboard can never disagree.
 *
 * `subject` is `linksTo(CardDef)` — NEVER a domain type, so an SLA
 * applies to any card and the clock still renders.
 */
const STATE_TONES: Record<string, PretuiToneArg> = {
  met: 'success',
  paused: 'neutral',
  healthy: 'primary',
  warning: 'warning',
  urgent: 'warning',
  breached: 'danger',
};
const SEVERITY_TONES: Record<string, PretuiToneArg> = {
  low: 'neutral',
  medium: 'neutral',
  high: 'warning',
  critical: 'danger',
};
const DAYS = [
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
];
const MINUTE_MS = 60_000;

function sentence(value?: string | null) {
  return value ? value[0]!.toUpperCase() + value.slice(1) : '';
}
const STAMP = new Intl.DateTimeFormat('en-US', {
  month: 'short',
  day: 'numeric',
  hour: '2-digit',
  minute: '2-digit',
  hour12: false,
});
const STAMP_Y = new Intl.DateTimeFormat('en-US', {
  month: 'short',
  day: 'numeric',
  year: 'numeric',
  hour: '2-digit',
  minute: '2-digit',
  hour12: false,
});
const DATE_Y = new Intl.DateTimeFormat('en-US', {
  month: 'short',
  day: 'numeric',
  year: 'numeric',
  timeZone: 'UTC',
});
const TIME = new Intl.DateTimeFormat('en-US', {
  hour: '2-digit',
  minute: '2-digit',
  hour12: false,
});
function stamp(v?: Date | null, year = false) {
  return v ? (year ? STAMP_Y : STAMP).format(new Date(v)) : undefined;
}
function minutes(n: number) {
  if (n >= 60 && n % 60 === 0) return `${n / 60} h`;
  return `${n} min`;
}
/** "Mon-Fri 09:00-18:00" when every window shares the same hours. */
function hoursLabel(m: Partial<Sla> | undefined) {
  let w = (m?.window?.windows ?? []).filter(Boolean) as any[];
  if (!w.length) return 'Always on';
  let open = w[0].opensAt?.value;
  let close = w[0].closesAt?.value;
  let same = w.every(
    (x) => x.opensAt?.value === open && x.closesAt?.value === close,
  );
  let idx = w.map((x) => DAYS.indexOf(x.day)).filter((i) => i >= 0);
  let days =
    w.length === 5 && idx.join() === '1,2,3,4,5'
      ? 'Mon\u2013Fri'
      : w.map((x) => String(x.day).slice(0, 3)).join(', ');
  return same ? `${days} ${open}\u2013${close}` : days;
}
function zoneAbbr(tz?: string | null) {
  if (!tz) return '';
  try {
    return (
      new Intl.DateTimeFormat('en-US', { timeZone: tz, timeZoneName: 'short' })
        .formatToParts(new Date())
        .find((p) => p.type === 'timeZoneName')?.value ?? ''
    );
  } catch {
    return '';
  }
}

/** The strings every SupportSla format shows, read once from the model. */
function slaView(m: Partial<Sla> | undefined) {
  let timers = (m?.timers ?? []).filter(Boolean) as any[];
  let first = timers.find((t) => /first/i.test(t.kind ?? ''));
  let res = timers.find((t) => /resol/i.test(t.kind ?? ''));
  let policyName = (m?.policy as any)?.name as string | undefined;
  let tz = m?.window?.timeZone;
  let hours = hoursLabel(m);
  let abbr = zoneAbbr(tz);
  let schedule = [hours, abbr].filter(Boolean).join(' ');
  let state = m?.state ?? 'pending';
  let firstMin =
    first?.satisfiedAt && first?.startedAt
      ? Math.round(
          (new Date(first.satisfiedAt).getTime() -
            new Date(first.startedAt).getTime()) /
            MINUTE_MS,
        )
      : undefined;
  let pauses = (m?.pauses ?? []).filter(Boolean) as any[];
  let holiday = ((m?.window?.holidays ?? []).filter(Boolean) as any[])[0];
  let firstText = first
    ? first.satisfiedAt
      ? `met in ${firstMin} min`
      : `due ${stamp(first.deadlineAt) ?? '—'}`
    : '—';
  let resText = res
    ? res.satisfiedAt
      ? 'met'
      : `due ${stamp(res.deadlineAt) ?? '—'}`
    : '—';
  let pauseText = pauses.length
    ? `${pauses.length} \u00b7 ${pauses[0].reason ?? 'paused'}`
    : '0';
  let fact = res
    ? `Resolution due ${stamp(res.deadlineAt) ?? '—'}${res.targetMinutes ? ` \u00b7 ${Math.round(res.targetMinutes / 60)} business h target` : ''}`
    : undefined;
  let facts: KeyValueItem[] = [
    { key: 'First response', value: firstText },
    { key: 'Resolution', value: resText },
    { key: 'Started', value: stamp(m?.startedAt, true) ?? '—' },
    { key: 'Pauses', value: pauseText },
    { key: 'Time zone', value: tz ?? '—' },
    { key: 'Hours', value: hours },
    ...(holiday
      ? [{ key: 'Holiday', value: DATE_Y.format(new Date(holiday)) }]
      : []),
    { key: 'Policy', value: policyName ?? '—' },
  ];
  let subj = m?.subject as any;
  return {
    title: m?.subjectTitle ? `SLA \u00b7 ${m.subjectTitle}` : 'SLA',
    shortTitle: 'SLA',
    subline: [policyName, schedule].filter(Boolean).join(' \u00b7 '),
    stateLabel:
      state === 'pending'
        ? 'Pending'
        : sentence(state === 'healthy' ? 'running' : state),
    stateTone: STATE_TONES[state] ?? 'neutral',
    firstChip: first?.satisfiedAt ? 'First Response Met' : undefined,
    fact,
    facts,
    fitFacts: [
      facts[0]!,
      facts[1]!,
      facts[2]!,
      facts[3]!,
      ...facts.slice(4),
    ] as KeyValueItem[],
    firstStat: firstMin !== undefined ? `${firstMin} min` : '—',
    firstHint: first
      ? `target ${minutes(first.targetMinutes ?? 0)}${first.satisfiedAt ? ' \u00b7 met' : ''}`
      : undefined,
    resStat: res?.targetMinutes
      ? minutes(Math.round(res.targetMinutes / 60) * 60)
      : '—',
    resHint: res ? `due ${stamp(res.deadlineAt) ?? '—'}` : undefined,
    pauseStat: String(pauses.length),
    pauseHint: pauses[0]?.reason
      ? `${pauses[0].reason} on customer`
      : undefined,
    progress:
      firstMin !== undefined && first?.targetMinutes
        ? {
            label: 'First response',
            value: Math.min(
              100,
              Math.round((firstMin / first.targetMinutes) * 100),
            ),
            valueText: `${firstMin} of ${first.targetMinutes} min`,
          }
        : undefined,
    stats: [
      {
        key: 'First response',
        value: firstMin !== undefined ? `${firstMin} min` : '—',
      },
      {
        key: 'Resolution',
        value: res?.targetMinutes
          ? minutes(Math.round(res.targetMinutes / 60) * 60)
          : '—',
      },
      { key: 'Pauses', value: String(pauses.length) },
    ] as FittedStat[],
    timers: timers.map((t) => ({
      title: `${t.kind ?? 'Timer'}${t.targetMinutes ? ` \u00b7 ${t.targetMinutes} min` : ''}`,
      detail: [
        t.startedAt ? `started ${stamp(t.startedAt)}` : undefined,
        t.satisfiedAt
          ? `satisfied ${TIME.format(new Date(t.satisfiedAt))}`
          : t.deadlineAt
            ? `deadline ${stamp(t.deadlineAt)}`
            : undefined,
      ]
        .filter(Boolean)
        .join(' \u00b7 '),
      label: t.satisfiedAt
        ? 'Met'
        : t.breachedAt
          ? 'Breached'
          : t.pausedSince
            ? 'Paused'
            : 'Running',
      tone: (t.satisfiedAt
        ? 'success'
        : t.breachedAt
          ? 'danger'
          : t.pausedSince
            ? 'neutral'
            : 'primary') as PretuiToneArg,
    })),
    pauses: pauses.map((p) => ({
      title: sentence(p.reason ?? 'paused'),
      detail: `${stamp(p.pausedAt) ?? '—'} \u2192 ${stamp(p.resumedAt) ?? 'now'}`,
      label: p.resumedAt ? 'Resumed' : 'Paused',
    })),
    windowFacts: [
      { key: 'Time zone', value: tz ?? '—' },
      { key: 'Hours', value: hours },
      ...(holiday
        ? [{ key: 'Holiday', value: DATE_Y.format(new Date(holiday)) }]
        : []),
    ] as KeyValueItem[],
    subject: subj
      ? {
          title: m?.subjectTitle,
          severity: sentence(subj.severity),
          tone: SEVERITY_TONES[subj.severity ?? 'low'] ?? 'neutral',
        }
      : undefined,
    policy: policyName,
  };
}

export class Sla extends CardDef {
  static displayName = 'SLA';
  static icon = TimerIcon;

  @field subject = linksTo(CardDef, {
    description: 'The record under this promise. Any card type.',
  });
  @field policy = linksTo(() => SlaPolicy);
  /** Denormalised link facts: consumers join on these instead of touching
      `subject` (a lazy linksTo that would load mid-render). */
  @field subjectId = contains(StringField, {
    computeVia: function (this: Sla) {
      return this.subject?.id;
    },
  });
  @field subjectTitle = contains(StringField, {
    computeVia: function (this: Sla) {
      return (this.subject as any)?.cardTitle ?? (this.subject as any)?.title;
    },
  });
  @field window = contains(SlaWindowField);
  @field timers = containsMany(SlaTimerField);
  @field pauses = containsMany(PauseIntervalField);
  @field startedAt = contains(DateTimeField);

  /**
   * Snapshot state across all timers: the WORST clock speaks for the record.
   * Stale between writes by design (see SlaTimerField) — live surfaces use
   * the badge, which recomputes.
   */
  @field state = contains(StringField, {
    computeVia: function (this: Sla) {
      let timers = this.timers ?? [];
      if (!timers.length) return 'pending';
      let worst = sortByUrgency(timers)[0];
      return timerSnapshot(worst!).state;
    },
  });

  @field nearestLabel = contains(StringField, {
    computeVia: function (this: Sla) {
      let timers = this.timers ?? [];
      if (!timers.length) return 'No clocks';
      let worst = sortByUrgency(timers)[0];
      let snap = timerSnapshot(worst!);
      return `${worst!.kind ?? 'SLA'}: ${snap.shortLabel}`;
    },
  });

  @field pausedMinutesTotal = contains(NumberField, {
    computeVia: function (this: Sla) {
      let total = 0;
      for (let p of this.pauses ?? []) {
        let from = p.pausedAt
          ? new Date(p.pausedAt as unknown as string)
          : null;
        let to = p.resumedAt
          ? new Date(p.resumedAt as unknown as string)
          : null;
        if (from && to)
          total += Math.round((to.getTime() - from.getTime()) / 60000);
      }
      return total;
    },
  });

  @field title = contains(StringField, {
    computeVia: function (this: Sla) {
      let policy = this.policy?.name;
      return policy ? `SLA · ${policy}` : 'SLA';
    },
  });

  static fitted = class Fitted extends Component<typeof this> {
    get v() {
      return slaView(this.args.model);
    }
    get relations() {
      return [
        ...(this.v.subject ? ['Subject'] : []),
        ...(this.v.policy ? ['Policy'] : []),
      ];
    }
    <template>
      <FittedExtras
        @facts={{this.v.fitFacts}}
        @stats={{this.v.stats}}
        @progress={{this.v.progress}}
        @relations={{this.relations}}
      >
        <:default>
          <FitTile>
            <:avatar><span class='mark' aria-hidden='true'>SL</span></:avatar>
            <:title><span
                class='fit-title'
                role='heading'
                aria-level='3'
              >{{this.v.title}}</span></:title>
            <:subtitle>{{this.v.subline}}</:subtitle>
            <:status><Chip
                @tone={{this.v.stateTone}}
                @appearance='soft'
                @dot={{false}}
              >{{this.v.stateLabel}}</Chip>
              {{#if this.v.firstChip}}<Chip
                  @tone='success'
                  @appearance='soft'
                  @dot={{false}}
                >{{this.v.firstChip}}</Chip>{{/if}}</:status>
            <:fact>{{this.v.fact}}</:fact>
          </FitTile>
        </:default>
        <:relation as |label|>
          {{#if (eq label 'Subject')}}<span class='subj'><span
                class='subj-mark'
                aria-hidden='true'
              >Cs</span><span
                class='subj-title'
              >{{this.v.subject.title}}</span>{{#if
                this.v.subject.severity
              }}<span class='subj-sev'><Chip
                    @tone={{this.v.subject.tone}}
                    @appearance='soft'
                    @dot={{false}}
                  >{{this.v.subject.severity}}</Chip></span>{{/if}}</span>{{else}}<span
              class='subj'
            ><span class='subj-mark' aria-hidden='true'>Po</span><span
                class='subj-title'
              >{{this.v.policy}}</span></span>{{/if}}
        </:relation>
      </FittedExtras>
      <style scoped>
        @layer PretComponent {
          .fit-title {
            display: block;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
          }
          .subj {
            display: inline-flex;
            align-items: center;
            gap: var(--boxel-sp-xs);
            min-width: 0;
          }
          .subj-mark {
            display: inline-grid;
            place-items: center;
            flex: none;
            inline-size: 1.5rem;
            block-size: 1.5rem;
            border: 1px solid var(--border);
            border-radius: var(--radius);
            background: var(--muted);
            color: var(--primary);
            font-size: var(--boxel-font-size-xs);
            font-weight: 600;
          }
          @container fitted-card (max-width: 24rem) {
            .subj-sev {
              display: none;
            }
          }
          .subj-title {
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
            font-weight: 600;
          }
          .mark {
            display: inline-grid;
            place-items: center;
            inline-size: 2rem;
            block-size: 2rem;
            border: 1px solid var(--border);
            border-radius: var(--radius);
            background: var(--muted);
            color: var(--primary);
            font-size: var(--boxel-font-size-xs);
            font-weight: 600;
          }
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    get v() {
      return slaView(this.args.model);
    }
    <template>
      <article class='emb'>
        <header class='emb-head'>
          <span class='mark' aria-hidden='true'>SL</span>
          <div class='emb-id'>
            <h3 class='emb-title'>{{this.v.title}}</h3>
            <p class='emb-sub'>{{this.v.subline}}</p>
          </div>
          <span class='emb-chips'><Chip
              @tone={{this.v.stateTone}}
              @appearance='soft'
              @dot={{false}}
            >{{this.v.stateLabel}}</Chip>
            {{#if this.v.firstChip}}<Chip
                @tone='success'
                @appearance='soft'
                @dot={{false}}
              >{{this.v.firstChip}}</Chip>{{/if}}</span>
        </header>
        <p class='emb-fact'>{{this.v.fact}}</p>
        <dl class='emb-facts'>
          {{#each this.v.facts as |item|}}
            <div class='emb-item'><dt>{{item.key}}</dt><dd
              >{{item.value}}</dd></div>
          {{/each}}
        </dl>
        <div class='emb-rels'>
          {{#if this.v.subject}}<p class='emb-rel'><span
                class='emb-rel-k'
              >Subject</span><span class='subj'><span
                  class='subj-mark'
                  aria-hidden='true'
                >Cs</span><span
                  class='subj-title'
                >{{this.v.subject.title}}</span>{{#if
                  this.v.subject.severity
                }}<span class='subj-sev'><Chip
                      @tone={{this.v.subject.tone}}
                      @appearance='soft'
                      @dot={{false}}
                    >{{this.v.subject.severity}}</Chip></span>{{/if}}</span></p>{{/if}}
          {{#if this.v.policy}}<p class='emb-rel'><span
                class='emb-rel-k'
              >Policy</span><span class='subj'><span
                  class='subj-mark'
                  aria-hidden='true'
                >Po</span><span
                  class='subj-title'
                >{{this.v.policy}}</span></span></p>{{/if}}
        </div>
      </article>
      <style scoped>
        @layer PretComponent {
          .emb {
            container-type: inline-size;
            display: grid;
            gap: var(--boxel-sp-sm);
            padding: var(--boxel-sp);
          }
          .emb-head {
            display: grid;
            grid-template-columns: auto minmax(0, 1fr) auto;
            align-items: center;
            gap: var(--boxel-sp-xs);
          }
          .emb-id {
            min-width: 0;
          }
          .emb-title {
            margin: 0;
            font-size: var(--boxel-font-size);
            font-weight: 600;
          }
          .emb-sub,
          .emb-fact {
            margin: 0;
            font-size: var(--boxel-font-size-sm);
            color: var(--muted-foreground);
          }
          .emb-chips {
            display: inline-flex;
            flex-wrap: wrap;
            gap: var(--boxel-sp-4xs);
          }
          .emb-facts {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(9rem, 1fr));
            gap: var(--boxel-sp-xs) var(--boxel-sp-sm);
            margin: 0;
            padding-top: var(--boxel-sp-sm);
            border-top: 1px solid var(--border);
          }
          .emb-item {
            min-width: 0;
          }
          .emb-item dt {
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          .emb-item dd {
            margin: 0;
            font-size: var(--boxel-font-size-sm);
            font-weight: 600;
          }
          .emb-rels {
            display: flex;
            flex-wrap: wrap;
            gap: var(--boxel-sp-sm);
          }
          .emb-rel {
            display: flex;
            flex-wrap: wrap;
            align-items: center;
            gap: var(--boxel-sp-xs);
            margin: 0;
          }
          .emb-rel-k {
            flex: none;
            white-space: nowrap;
            color: var(--muted-foreground);
          }
          @container (max-width: 25rem) {
            .emb-head {
              grid-template-columns: auto minmax(0, 1fr);
            }
            .emb-chips {
              grid-column: 1 / -1;
            }
          }
          .subj {
            display: inline-flex;
            align-items: center;
            gap: var(--boxel-sp-xs);
            min-width: 0;
          }
          .subj-mark {
            display: inline-grid;
            place-items: center;
            flex: none;
            inline-size: 1.5rem;
            block-size: 1.5rem;
            border: 1px solid var(--border);
            border-radius: var(--radius);
            background: var(--muted);
            color: var(--primary);
            font-size: var(--boxel-font-size-xs);
            font-weight: 600;
          }
          @container fitted-card (max-width: 24rem) {
            .subj-sev {
              display: none;
            }
          }
          .subj-title {
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
            font-weight: 600;
          }
          .mark {
            display: inline-grid;
            place-items: center;
            inline-size: 2rem;
            block-size: 2rem;
            border: 1px solid var(--border);
            border-radius: var(--radius);
            background: var(--muted);
            color: var(--primary);
            font-size: var(--boxel-font-size-xs);
            font-weight: 600;
          }
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    get v() {
      return slaView(this.args.model);
    }
    <template>
      <span class='atom'>
        <span class='atom-mark' aria-hidden='true'>SL</span>
        <span class='atom-name'>{{this.v.title}}</span>
        <Chip
          @tone={{this.v.stateTone}}
          @appearance='soft'
          @dot={{false}}
        >{{this.v.stateLabel}}</Chip>
      </span>
      <style scoped>
        @layer PretComponent {
          .atom {
            display: inline-flex;
            align-items: center;
            gap: var(--boxel-sp-4xs);
            max-width: 100%;
            font-size: var(--boxel-font-size-sm);
          }
          .atom-mark {
            display: inline-grid;
            place-items: center;
            inline-size: 1.25rem;
            block-size: 1.25rem;
            border: 1px solid var(--border);
            border-radius: var(--radius);
            background: var(--muted);
            color: var(--primary);
            font-size: var(--boxel-font-size-xs);
            font-weight: 600;
          }
          .atom-name {
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
            font-weight: 600;
          }
        }
      </style>
    </template>
  };

  static isolated = class Isolated extends Component<typeof this> {
    get v() {
      return slaView(this.args.model);
    }
    <template>
      <article class='iso'>
        <header class='iso-head'>
          <span class='mark' aria-hidden='true'>SL</span>
          <div class='iso-id'>
            <h1 class='iso-title'>{{this.v.title}}</h1>
            <p class='iso-sub'>{{this.v.subline}}</p>
          </div>
          <span class='iso-chips'><Chip
              @tone={{this.v.stateTone}}
              @appearance='soft'
              @dot={{false}}
            >{{this.v.stateLabel}}</Chip>
            {{#if this.v.firstChip}}<Chip
                @tone='success'
                @appearance='soft'
                @dot={{false}}
              >{{this.v.firstChip}}</Chip>{{/if}}</span>
        </header>
        <div class='iso-stats'>
          <Panel><Stat
              @label='First response'
              @value={{this.v.firstStat}}
              @hint={{this.v.firstHint}}
              @roll={{false}}
            /></Panel>
          <Panel><Stat
              @label='Resolution'
              @value={{this.v.resStat}}
              @hint={{this.v.resHint}}
              @roll={{false}}
            /></Panel>
          <Panel><Stat
              @label='Pauses'
              @value={{this.v.pauseStat}}
              @hint={{this.v.pauseHint}}
              @roll={{false}}
            /></Panel>
        </div>
        <div class='iso-grid'>
          <div class='iso-col'>
            {{#if this.v.timers.length}}
              <Panel @title='Timers'>
                <ul class='iso-list'>
                  {{#each this.v.timers as |t|}}
                    <li class='iso-row'>
                      <span class='iso-row-body'><strong
                        >{{t.title}}</strong><span
                          class='iso-row-detail'
                        >{{t.detail}}</span></span>
                      <Chip
                        @tone={{t.tone}}
                        @appearance='soft'
                        @dot={{false}}
                      >{{t.label}}</Chip>
                    </li>
                  {{/each}}
                </ul>
              </Panel>
            {{/if}}
            {{#if this.v.pauses.length}}
              <Panel @title='Pauses'>
                <ul class='iso-list'>
                  {{#each this.v.pauses as |p|}}
                    <li class='iso-row'>
                      <span class='iso-row-body'><strong
                        >{{p.title}}</strong><span
                          class='iso-row-detail'
                        >{{p.detail}}</span></span>
                      <Chip
                        @tone='neutral'
                        @appearance='soft'
                        @dot={{false}}
                      >{{p.label}}</Chip>
                    </li>
                  {{/each}}
                </ul>
              </Panel>
            {{/if}}
            <Panel @title='Business hours'><KeyValue
                @items={{this.v.windowFacts}}
                @divided={{true}}
              /></Panel>
          </div>
          <div class='iso-col'>
            <Panel @title='Linked'>
              <div class='iso-links'>
                {{#if this.v.subject}}<p class='iso-link'><span
                      class='iso-link-k'
                    >Subject</span><span class='subj'><span
                        class='subj-mark'
                        aria-hidden='true'
                      >Cs</span><span
                        class='subj-title'
                      >{{this.v.subject.title}}</span>{{#if
                        this.v.subject.severity
                      }}<span class='subj-sev'><Chip
                            @tone={{this.v.subject.tone}}
                            @appearance='soft'
                            @dot={{false}}
                          >{{this.v.subject.severity}}</Chip></span>{{/if}}</span></p>{{/if}}
                {{#if this.v.policy}}<p class='iso-link'><span
                      class='iso-link-k'
                    >Policy</span><span class='subj'><span
                        class='subj-mark'
                        aria-hidden='true'
                      >Po</span><span
                        class='subj-title'
                      >{{this.v.policy}}</span></span></p>{{/if}}
              </div>
            </Panel>
            <Panel @title='Details'><KeyValue
                @items={{this.v.facts}}
                @divided={{true}}
              /></Panel>
          </div>
        </div>
      </article>
      <style scoped>
        @layer PretComponent {
          .iso {
            container-type: inline-size;
            min-height: 100%;
            background: var(--canvas);
            display: grid;
            gap: var(--boxel-sp);
            padding: var(--boxel-sp-lg);
          }
          .iso-head {
            display: grid;
            grid-template-columns: auto minmax(0, 1fr) auto;
            align-items: center;
            gap: var(--boxel-sp-sm);
          }
          .iso-title {
            margin: 0;
            font-size: 1.5rem;
            font-weight: 600;
            line-height: 1.25;
            color: var(--primary-ink);
          }
          .iso-sub {
            margin: 0;
            color: var(--muted-foreground);
          }
          .iso-chips {
            display: inline-flex;
            flex-wrap: wrap;
            gap: var(--boxel-sp-4xs);
          }
          .iso-stats {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(10rem, 1fr));
            gap: var(--boxel-sp);
          }
          .iso-grid {
            display: grid;
            grid-template-columns: minmax(0, 2fr) minmax(0, 1fr);
            gap: var(--boxel-sp);
            align-items: start;
          }
          .iso-col {
            display: grid;
            gap: var(--boxel-sp);
            min-width: 0;
          }
          .iso-list {
            list-style: none;
            margin: 0;
            padding: 0;
            display: grid;
            gap: var(--boxel-sp-sm);
          }
          .iso-row {
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: var(--boxel-sp-sm);
            padding-bottom: var(--boxel-sp-sm);
            border-bottom: 1px solid var(--border);
          }
          .iso-row:last-child {
            border-bottom: 0;
            padding-bottom: 0;
          }
          .iso-row-body {
            display: grid;
          }
          .iso-row-detail {
            color: var(--muted-foreground);
            font-size: var(--boxel-font-size-sm);
          }
          .iso-links {
            display: grid;
            gap: var(--boxel-sp-xs);
          }
          .iso-link {
            display: flex;
            flex-wrap: wrap;
            align-items: center;
            justify-content: space-between;
            gap: var(--boxel-sp-xs);
            margin: 0;
            padding-bottom: var(--boxel-sp-xs);
            border-bottom: 1px solid var(--border);
          }
          .iso-link-k {
            flex: none;
            white-space: nowrap;
            color: var(--muted-foreground);
          }
          @container (max-width: 40rem) {
            .iso-head {
              grid-template-columns: auto minmax(0, 1fr);
            }
            .iso-chips {
              grid-column: 1 / -1;
            }
            .iso-grid {
              grid-template-columns: minmax(0, 1fr);
            }
          }
          .subj {
            display: inline-flex;
            align-items: center;
            gap: var(--boxel-sp-xs);
            min-width: 0;
          }
          .subj-mark {
            display: inline-grid;
            place-items: center;
            flex: none;
            inline-size: 1.5rem;
            block-size: 1.5rem;
            border: 1px solid var(--border);
            border-radius: var(--radius);
            background: var(--muted);
            color: var(--primary);
            font-size: var(--boxel-font-size-xs);
            font-weight: 600;
          }
          @container fitted-card (max-width: 24rem) {
            .subj-sev {
              display: none;
            }
          }
          .subj-title {
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
            font-weight: 600;
          }
          .mark {
            display: inline-grid;
            place-items: center;
            inline-size: 2.5rem;
            block-size: 2.5rem;
            border: 1px solid var(--border);
            border-radius: var(--radius);
            background: var(--muted);
            color: var(--primary);
            font-size: var(--boxel-font-size-xs);
            font-weight: 600;
          }
        }
      </style>
    </template>
  };
}

export default Sla;
