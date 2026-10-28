import { Component } from '@cardstack/base/card-api';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Chip } from '../../../ui-component/components/chip';
import { FitTile } from '../../../ui-component/components/fit-tile';
import {
  KeyValue,
  type KeyValueItem,
} from '../../../ui-component/components/key-value';
import { Panel } from '../../../ui-component/components/panel';
import { Stat } from '../../../ui-component/components/stat';
import { FittedExtras, type FittedStat } from '../../procurement/vendor';
import { Sla } from '../../service-desk/sla';

const STATE_TONES: Record<string, string> = {
  met: 'success',
  paused: 'neutral',
  healthy: 'primary',
  warning: 'warning',
  urgent: 'warning',
  breached: 'danger',
};
const SEVERITY_TONES: Record<string, string> = {
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
function hoursLabel(m: Sla | undefined) {
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
function slaView(m: Sla | undefined) {
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
      tone: t.satisfiedAt
        ? 'success'
        : t.breachedAt
          ? 'danger'
          : t.pausedSince
            ? 'neutral'
            : 'primary',
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

/** An SLA drawn the Support Case way. Same schema as Sla; only the formats differ. */
export class SupportSla extends Sla {
  static displayName = 'Support SLA';

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
                @shape='pill'
                @dot={{false}}
              >{{this.v.stateLabel}}</Chip>
              {{#if this.v.firstChip}}<Chip
                  @tone='success'
                  @appearance='soft'
                  @shape='pill'
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
                    @shape='pill'
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
              @shape='pill'
              @dot={{false}}
            >{{this.v.stateLabel}}</Chip>
            {{#if this.v.firstChip}}<Chip
                @tone='success'
                @appearance='soft'
                @shape='pill'
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
                      @shape='pill'
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
            align-items: center;
            gap: var(--boxel-sp-xs);
            margin: 0;
          }
          .emb-rel-k {
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
          @shape='pill'
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
              @shape='pill'
              @dot={{false}}
            >{{this.v.stateLabel}}</Chip>
            {{#if this.v.firstChip}}<Chip
                @tone='success'
                @appearance='soft'
                @shape='pill'
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
                        @shape='pill'
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
                        @shape='pill'
                        @dot={{false}}
                      >{{p.label}}</Chip>
                    </li>
                  {{/each}}
                </ul>
              </Panel>
            {{/if}}
            <Panel @title='Business hours'><KeyValue
                @items={{this.v.windowFacts}}
                @rows='ruled'
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
                            @shape='pill'
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
                @rows='ruled'
              /></Panel>
          </div>
        </div>
      </article>
      <style scoped>
        @layer PretComponent {
          .iso {
            container-type: inline-size;
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
            align-items: center;
            justify-content: space-between;
            gap: var(--boxel-sp-xs);
            margin: 0;
            padding-bottom: var(--boxel-sp-xs);
            border-bottom: 1px solid var(--border);
          }
          .iso-link-k {
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
