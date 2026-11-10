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
import type { PretuiToneArg } from '@cardstack/pretui/pretui-primitives';
import { FitTile } from '../shared/fit-tile';
import { type KeyValueItem } from '@cardstack/pretui/components/key-value';
import { Stat } from '@cardstack/pretui/components/stat';
import { Chip } from '@cardstack/pretui/components/chip';

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

/** "Monday – Friday" when the windows run Mon–Fri, else the day list. */
function daysLabel(m: Partial<Sla> | undefined) {
  let w = (m?.window?.windows ?? []).filter(Boolean) as any[];
  if (!w.length) return 'Every day';
  let idx = w.map((x) => DAYS.indexOf(x.day)).filter((i) => i >= 0);
  return w.length === 5 && idx.join() === '1,2,3,4,5'
    ? 'Monday – Friday'
    : w.map((x) => String(x.day)).join(', ');
}
function openHours(m: Partial<Sla> | undefined) {
  let w = ((m?.window?.windows ?? []).filter(Boolean) as any[])[0];
  return w ? `${w.opensAt?.value ?? '—'} – ${w.closesAt?.value ?? '—'}` : '—';
}
function shortHours(hours: string) {
  // "Mon–Fri 09:00–18:00" reads as "Mon–Fri 09–18" in a fitted row
  return hours.replace(/(\d\d):00/g, '$1');
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
  let holidayText = holiday ? DATE_Y.format(new Date(holiday)) : undefined;
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
    ? `${pauses.length} · ${pauses[0].reason ?? 'paused'}`
    : '0';
  let started = stamp(m?.startedAt, true) ?? '—';
  let core: KeyValueItem[] = [
    { key: 'First response', value: firstText },
    { key: 'Resolution', value: resText },
    { key: 'Started', value: started },
    { key: 'Pauses', value: pauseText },
    { key: 'Time zone', value: tz ?? '—' },
    { key: 'Hours', value: hours },
  ];
  return {
    title: m?.subjectTitle ? `SLA · ${m.subjectTitle}` : 'SLA',
    subline: [policyName, schedule].filter(Boolean).join(' · '),
    stateLabel:
      state === 'healthy' ? 'running' : state === 'pending' ? 'pending' : state,
    stateTone: STATE_TONES[state] ?? 'neutral',
    firstMet: Boolean(first?.satisfiedAt),
    resDue: res && !res.satisfiedAt ? stamp(res.deadlineAt) : undefined,
    resTarget: res?.targetMinutes
      ? `${Math.round(res.targetMinutes / 60)} business h target`
      : undefined,
    core,
    facts: [
      ...core,
      ...(holidayText ? [{ key: 'Holiday', value: holidayText }] : []),
      { key: 'Policy', value: policyName ?? '—' },
    ] as KeyValueItem[],
    // fitted ranks the clocks first, then when and where
    fitTop: [core[0]!, core[1]!, core[3]!],
    fitRest: [
      { key: 'Started', value: stamp(m?.startedAt) ?? '—' },
      { key: 'Time zone', value: tz ?? '—' },
      { key: 'Hours', value: shortHours(hours) },
    ] as KeyValueItem[],
    firstStat: firstMin !== undefined ? `${firstMin} min` : '—',
    firstHint: first
      ? `target ${minutes(first.targetMinutes ?? 0)}${first.satisfiedAt ? ' · met' : ''}`
      : 'no first-response clock',
    firstTone: (first?.satisfiedAt ? 'success' : 'neutral') as PretuiToneArg,
    resStat: res?.targetMinutes
      ? minutes(Math.round(res.targetMinutes / 60) * 60)
      : '—',
    resHint: res ? resText : 'no resolution clock',
    pauseStat: String(pauses.length),
    pauseHint: pauses[0]?.reason
      ? `${pauses[0].reason} on customer`
      : 'never paused',
    timers: timers.map((t) => ({
      title: `${sentence(t.kind ?? 'timer')}${t.targetMinutes ? ` · ${t.targetMinutes} min` : ''}`,
      detail: [
        t.startedAt ? `started ${stamp(t.startedAt)}` : undefined,
        t.satisfiedAt
          ? `satisfied ${TIME.format(new Date(t.satisfiedAt))}`
          : t.deadlineAt
            ? `deadline ${stamp(t.deadlineAt)}`
            : undefined,
      ]
        .filter(Boolean)
        .join(' · '),
      label: t.satisfiedAt
        ? 'met'
        : t.breachedAt
          ? 'breached'
          : t.pausedSince
            ? 'paused'
            : 'running',
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
      detail: `${stamp(p.pausedAt) ?? '—'} → ${stamp(p.resumedAt) ?? 'now'}`,
      label: p.resumedAt ? 'resumed' : 'paused',
      tone: (p.resumedAt ? 'success' : 'warning') as PretuiToneArg,
    })),
    windowFacts: [
      { key: 'Time zone', value: tz ?? '—' },
      { key: 'Days', value: daysLabel(m) },
      { key: 'Hours', value: openHours(m) },
      ...(holidayText ? [{ key: 'Holidays', value: holidayText }] : []),
    ] as KeyValueItem[],
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

  static embedded = class Embedded extends Component<typeof this> {
    get v() {
      return slaView(this.args.model);
    }
    <template>
      <article class='emb'>
        <header class='eh'>
          <span class='mark' aria-hidden='true'>SL</span>
          <div class='t'>
            <h3 class='name'>{{this.v.title}}</h3>
            <p class='meta'>{{this.v.subline}}</p>
          </div>
        </header>
        {{#if this.v.resDue}}<p class='fact'>Resolution due
            <b>{{this.v.resDue}}</b>{{#if this.v.resTarget}}
              ·
              {{this.v.resTarget}}{{/if}}</p>{{/if}}
        <dl class='kv'>
          {{#each this.v.core as |f|}}
            <div class='kv-r'><dt class='cap'>{{f.key}}</dt><dd
              >{{f.value}}</dd></div>
          {{/each}}
          {{#if @model.subject}}
            <div class='kv-r'><dt class='cap'>Subject</dt><dd><@fields.subject
                  @format='atom'
                  @displayContainer={{false}}
                /></dd></div>
          {{/if}}
          {{#if @model.policy}}
            <div class='kv-r'><dt class='cap'>Policy</dt><dd><@fields.policy
                  @format='atom'
                  @displayContainer={{false}}
                /></dd></div>
          {{/if}}
        </dl>
      </article>
      <style scoped>
        .emb {
          container-type: inline-size;
          background: var(--card);
          color: var(--card-foreground);
          font-family: var(--font-sans);
          font-size: var(--boxel-font-size-xs);
          line-height: 1.4;
        }
        .eh {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-2xs);
          padding: var(--boxel-sp-3xs) var(--boxel-sp-xs);
        }
        .t {
          display: grid;
          flex: 1;
          min-width: 0;
        }
        .name {
          margin: 0;
          font-family: var(--font-sans);
          font-size: var(--boxel-font-size-xs);
          font-weight: 700;
        }
        .name,
        .meta {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .meta,
        .fact {
          margin: 0;
          font-size: var(--boxel-font-size-2xs);
          color: var(--muted-foreground);
        }
        .fact {
          padding: var(--boxel-sp-3xs) var(--boxel-sp-xs);
          border-top: 1px solid var(--border);
        }
        .fact b {
          font-weight: 700;
        }
        .kv {
          margin: 0;
          padding: 0 var(--boxel-sp-xs);
        }
        .kv-r {
          display: grid;
          grid-template-columns: 6.25rem minmax(0, 1fr);
          column-gap: var(--boxel-sp-xs);
          align-items: center;
          min-block-size: 1.75rem;
          border-top: 1px solid var(--border);
        }
        .kv-r dd {
          margin: 0;
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .cap {
          font-family: var(--font-mono);
          font-size: 0.5625rem; /* ladder 9px label: no Boxel token below 11px */
          font-weight: 600;
          letter-spacing: 0.13em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .mark {
          display: inline-grid;
          place-items: center;
          flex: none;
          inline-size: 1.375rem;
          block-size: 1.375rem;
          border-radius: calc(var(--radius) / 2);
          background: var(--muted);
          color: var(--card-foreground);
          font-family: var(--font-mono);
          font-size: 0.5625rem; /* ladder 9px label: no Boxel token below 11px */
          font-weight: 700;
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
        <span class='mark' aria-hidden='true'>SL</span>
        <span class='name'>{{this.v.title}}</span>
      </span>
      <style scoped>
        .atom {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-4xs);
          min-width: 0;
          max-width: 100%;
          vertical-align: middle;
          font-family: var(--font-sans);
          font-size: var(--boxel-font-size-2xs);
          font-weight: 600;
          color: var(--card-foreground);
        }
        .mark {
          display: inline-grid;
          place-items: center;
          flex: none;
          inline-size: 1.125rem;
          block-size: 1.125rem;
          border-radius: calc(var(--radius) / 2);
          background: var(--muted);
          font-family: var(--font-mono);
          font-size: 0.5625rem; /* ladder 9px label: no Boxel token below 11px */
          font-weight: 700;
        }
        .name {
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
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
        <header class='ih'>
          <span class='mark' aria-hidden='true'>SL</span>
          <div class='t'>
            <h1 class='name'>{{this.v.title}}</h1>
            <p class='meta'>{{this.v.subline}}</p>
          </div>
          <span class='sts'>
            <Chip
              @label={{this.v.stateLabel}}
              @tone={{this.v.stateTone}}
              @appearance='plain'
            />
            {{#if this.v.firstMet}}<Chip
                @label='first response met'
                @tone='success'
                @appearance='plain'
              />{{/if}}
          </span>
        </header>
        <div class='stats'>
          <Stat
            @label='First response'
            @tone={{this.v.firstTone}}
            @value={{this.v.firstStat}}
            @hint={{this.v.firstHint}}
            @roll={{false}}
          />
          <Stat
            @label='Resolution'
            @tone='primary'
            @value={{this.v.resStat}}
            @hint={{this.v.resHint}}
            @roll={{false}}
          />
          <Stat
            @label='Pauses'
            @tone='warning'
            @value={{this.v.pauseStat}}
            @hint={{this.v.pauseHint}}
            @roll={{false}}
          />
        </div>
        <div class='cols'>
          <div class='main'>
            <section>
              <h2>Timers</h2>
              {{#each this.v.timers as |t|}}
                <div class='row'>
                  <span class='row-id'>
                    <span class='row-name'>{{t.title}}</span>
                    <span class='meta'>{{t.detail}}</span>
                  </span>
                  <Chip
                    @label={{t.label}}
                    @tone={{t.tone}}
                    @appearance='plain'
                  />
                </div>
              {{else}}
                <p class='row meta'>No clocks running</p>
              {{/each}}
            </section>
            {{#if this.v.pauses.length}}
              <section>
                <h2>Pauses</h2>
                {{#each this.v.pauses as |p|}}
                  <div class='row'>
                    <span class='row-id'>
                      <span class='row-name'>{{p.title}}</span>
                      <span class='meta'>{{p.detail}}</span>
                    </span>
                    <Chip
                      @label={{p.label}}
                      @tone={{p.tone}}
                      @appearance='plain'
                    />
                  </div>
                {{/each}}
              </section>
            {{/if}}
            <section>
              <h2>Business hours</h2>
              <dl class='kv'>
                {{#each this.v.windowFacts as |f|}}
                  <div class='kv-r'><dt class='cap'>{{f.key}}</dt><dd
                    >{{f.value}}</dd></div>
                {{/each}}
              </dl>
            </section>
          </div>
          <aside class='side'>
            <section>
              <h2>Linked</h2>
              <dl class='kv'>
                {{#if @model.subject}}
                  <div class='kv-r'><dt class='cap'>Subject</dt><dd
                    ><@fields.subject @format='atom' /></dd></div>
                {{/if}}
                {{#if @model.policy}}
                  <div class='kv-r'><dt class='cap'>Policy</dt><dd
                    ><@fields.policy @format='atom' /></dd></div>
                {{/if}}
              </dl>
            </section>
            <section>
              <h2>Details</h2>
              <dl class='kv'>
                {{#each this.v.facts as |f|}}
                  <div class='kv-r'><dt class='cap'>{{f.key}}</dt><dd
                    >{{f.value}}</dd></div>
                {{/each}}
              </dl>
            </section>
          </aside>
        </div>
      </article>
      <style scoped>
        .iso {
          container-type: inline-size;
          min-block-size: 100%;
          box-sizing: border-box;
          background: var(--card);
          color: var(--card-foreground);
          font-family: var(--font-sans);
          font-size: var(--boxel-font-size-xs);
          line-height: 1.4;
          --text-stat: 1.375rem;
        }
        .ih {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs);
          border-bottom: 1px solid var(--border);
        }
        .ih > .mark {
          inline-size: 1.75rem;
          block-size: 1.75rem;
        }
        .t {
          display: grid;
          flex: 1 1 12rem;
          min-width: 0;
        }
        .name {
          margin: 0;
          font-family: var(--font-sans);
          font-size: var(--boxel-font-size-xs);
          font-weight: 700;
        }
        .meta {
          margin: 0;
          font-size: var(--boxel-font-size-2xs);
          color: var(--muted-foreground);
        }
        .sts {
          display: inline-flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-xs);
          font-weight: 600;
        }
        .stats {
          display: grid;
          grid-auto-flow: column;
          grid-auto-columns: minmax(0, 1fr);
          border-bottom: 1px solid var(--border);
        }
        .stats > * {
          padding: var(--boxel-sp-3xs) var(--boxel-sp-xs);
        }
        .stats > * + * {
          border-inline-start: 1px solid var(--border);
        }
        .cols {
          display: grid;
          grid-template-columns: minmax(0, 2fr) minmax(0, 1fr);
        }
        .main,
        .side {
          min-width: 0;
        }
        .side {
          border-inline-start: 1px solid var(--border);
        }
        section + section {
          border-top: 1px solid var(--border);
        }
        h2 {
          padding: var(--boxel-sp-3xs) var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-xs);
          font-weight: 700;
        }
        .row {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: var(--boxel-sp-xs);
          min-block-size: 1.75rem;
          margin: 0;
          padding: var(--boxel-sp-4xs) var(--boxel-sp-xs);
          border-top: 1px solid var(--border);
        }
        .row-id {
          display: grid;
          min-width: 0;
        }
        .row-name {
          font-weight: 700;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .kv {
          margin: 0;
        }
        .kv-r {
          display: grid;
          grid-template-columns: 7.5rem minmax(0, 1fr);
          column-gap: var(--boxel-sp-xs);
          align-items: center;
          min-block-size: 1.75rem;
          padding-inline: var(--boxel-sp-xs);
          border-top: 1px solid var(--border);
        }
        .kv-r dd {
          margin: 0;
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .cap {
          font-family: var(--font-mono);
          font-size: 0.5625rem; /* ladder 9px label: no Boxel token below 11px */
          font-weight: 600;
          letter-spacing: 0.13em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .mark {
          display: inline-grid;
          place-items: center;
          flex: none;
          border-radius: calc(var(--radius) / 2);
          background: var(--muted);
          font-family: var(--font-mono);
          font-size: 0.5625rem; /* ladder 9px label: no Boxel token below 11px */
          font-weight: 700;
        }
        @container (max-width: 40rem) {
          .stats {
            grid-auto-flow: row;
          }
          .stats > * + * {
            border-inline-start: 0;
            border-top: 1px solid var(--border);
          }
          .cols {
            grid-template-columns: minmax(0, 1fr);
          }
          .side {
            border-inline-start: 0;
            border-top: 1px solid var(--border);
          }
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get v() {
      return slaView(this.args.model);
    }
    <template>
      <FitTile>
        <:avatar><span class='mark' aria-hidden='true'>SL</span></:avatar>
        <:title><span
            class='ell'
            role='heading'
            aria-level='3'
          >{{this.v.title}}</span></:title>
        <:subtitle>{{this.v.subline}}</:subtitle>
        <:status><Chip
            @label={{this.v.stateLabel}}
            @tone={{this.v.stateTone}}
            @appearance='plain'
          /></:status>
        <:fact>
          {{! rows ranked by priority; container queries drop whole rows }}
          <dl class='fr'>
            {{#each this.v.fitTop as |f|}}
              <div class='fr-r'><dt class='cap'>{{f.key}}</dt><dd
                >{{f.value}}</dd></div>
            {{/each}}
            {{#if @model.subject}}
              <div class='fr-r'><dt class='cap'>Subject</dt><dd><@fields.subject
                    @format='atom'
                    @displayContainer={{false}}
                  /></dd></div>
            {{/if}}
            {{#each this.v.fitRest as |f|}}
              <div class='fr-r'><dt class='cap'>{{f.key}}</dt><dd
                >{{f.value}}</dd></div>
            {{/each}}
            {{#if @model.policy}}
              <div class='fr-r'><dt class='cap'>Policy</dt><dd><@fields.policy
                    @format='atom'
                    @displayContainer={{false}}
                  /></dd></div>
            {{/if}}
          </dl>
        </:fact>
      </FitTile>
      <style scoped>
        .ell {
          display: block;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .mark {
          display: inline-grid;
          place-items: center;
          inline-size: 1.375rem;
          block-size: 1.375rem;
          border-radius: calc(var(--radius) / 2);
          background: var(--muted);
          color: var(--card-foreground);
          font-family: var(--font-mono);
          font-size: 0.5625rem; /* ladder 9px label: no Boxel token below 11px */
          font-weight: 700;
        }
        .cap {
          font-family: var(--font-mono);
          font-size: 0.5625rem; /* ladder 9px label: no Boxel token below 11px */
          font-weight: 600;
          line-height: 1.2;
          letter-spacing: 0.13em;
          text-transform: uppercase;
          white-space: normal;
          color: var(--muted-foreground);
        }
        .fr {
          display: grid;
          margin: 0;
          font-size: var(--boxel-font-size-xs);
          color: var(--card-foreground);
        }
        .fr-r {
          display: grid;
          grid-template-columns: 5rem minmax(0, 1fr);
          column-gap: var(--boxel-sp-2xs);
          align-items: center;
          block-size: 1.75rem;
          border-top: 1px solid var(--border);
          overflow: hidden;
        }
        .fr-r dd {
          margin: 0;
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .fr-r:nth-child(n + 13) {
          display: none;
        }
        @container fitted-card (width < 250px) {
          .fr-r {
            grid-template-columns: minmax(0, 1fr);
          }
          .fr-r dt {
            display: none;
          }
        }
        @container fitted-card (width >= 400px) {
          .fr-r {
            grid-template-columns: 6.75rem minmax(0, 1fr);
          }
        }
        @container fitted-card (height < 445px) and (width < 400px) {
          .fr-r:nth-child(n + 7) {
            display: none;
          }
        }
        @container fitted-card (height < 445px) and (width >= 400px) {
          .fr-r:nth-child(n + 8) {
            display: none;
          }
        }
        @container fitted-card (height < 275px) {
          .fr-r:nth-child(n + 6) {
            display: none;
          }
        }
        @container fitted-card (height < 250px) and (width < 400px) {
          .fr-r:nth-child(n + 3) {
            display: none;
          }
        }
        @container fitted-card (height < 250px) and (width >= 400px) {
          .fr-r:nth-child(n + 4) {
            display: none;
          }
        }
        @container fitted-card (height < 170px) and (width < 400px) {
          .fr {
            display: none;
          }
        }
        @container fitted-card (height < 170px) and (width >= 400px) {
          .fr-r:nth-child(n + 2) {
            display: none;
          }
        }
      </style>
    </template>
  };
}

export default Sla;
