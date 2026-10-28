import { Component } from '@cardstack/base/card-api';
import { Chip } from '../../../ui-component/components/chip';
import { FitTile } from '../../../ui-component/components/fit-tile';
import {
  KeyValue,
  type KeyValueItem,
} from '../../../ui-component/components/key-value';
import { Panel } from '../../../ui-component/components/panel';
import { Stat } from '../../../ui-component/components/stat';
import { FittedExtras, type FittedStat } from '../../procurement/vendor';
import { Escalation } from '../../service-desk/escalation';

const STATUS_TONES: Record<string, string> = {
  open: 'warning',
  acknowledged: 'success',
  resolved: 'success',
  cancelled: 'neutral',
};
const MINUTE_MS = 60_000;
const SEVERITY_TONES: Record<string, string> = {
  low: 'neutral',
  medium: 'neutral',
  high: 'warning',
  critical: 'danger',
};

function sentence(value?: string | null) {
  return value ? value[0]!.toUpperCase() + value.slice(1) : '';
}
/** "sla-risk" -> "SLA risk" (the one acronym this enum carries). */
function reasonLabel(value?: string | null) {
  if (!value) return '';
  return sentence(value.replace(/-/g, ' ')).replace(/^Sla /, 'SLA ');
}
/** "sla-risk" -> "Sla-Risk", the tag chip's wording. */
function reasonTag(value?: string | null) {
  return (value ?? '')
    .split('-')
    .map((w) => sentence(w))
    .join('-');
}
const STAMP = new Intl.DateTimeFormat('en-US', {
  month: 'short',
  day: 'numeric',
  year: 'numeric',
  hour: '2-digit',
  minute: '2-digit',
  hour12: false,
});
function stamp(value?: Date | null) {
  return value ? STAMP.format(new Date(value)) : undefined;
}
function clock(value?: Date | null) {
  return value
    ? new Intl.DateTimeFormat('en-US', {
        hour: '2-digit',
        minute: '2-digit',
        hour12: false,
      }).format(new Date(value))
    : '';
}

/** The strings every SupportEscalation format shows, read once from the model. */
function escView(m: Escalation | undefined) {
  let from = m?.fromLevel?.key ?? '?';
  let to = m?.toLevel?.key ?? '?';
  let caseId = (m?.subject as any)?.caseId?.value ?? m?.subjectTitle;
  let status = m?.status ?? 'open';
  let target = m?.toLevel?.ackTargetMinutes;
  let ackMin =
    m?.raisedAt && m?.acknowledgedAt
      ? Math.max(
          0,
          Math.round(
            (new Date(m.acknowledgedAt).getTime() -
              new Date(m.raisedAt).getTime()) /
              MINUTE_MS,
          ),
        )
      : undefined;
  let raisedBy = m?.raisedByName;
  let fact: string | undefined;
  if (status === 'cancelled') {
    fact = `Cancelled${m?.cancelledReason ? `: ${m.cancelledReason}` : ''}`;
  } else if (m?.acknowledgedAt) {
    fact = [
      `Acked${m.acknowledgedByName ? ` by ${m.acknowledgedByName}` : ''}${
        ackMin !== undefined ? ` in ${ackMin} min` : ''
      }`,
      target ? `target ${target} min` : undefined,
    ]
      .filter(Boolean)
      .join(' · ');
  } else {
    fact = [
      m?.ackOverdue === 'yes' ? 'Ack overdue' : 'Awaiting ack',
      target ? `target ${target} min` : undefined,
    ]
      .filter(Boolean)
      .join(' · ');
  }
  let facts: KeyValueItem[] = [
    { key: 'From', value: from },
    {
      key: 'To',
      value: [to, m?.toLevel?.targetRoleName].filter(Boolean).join(' · '),
    },
    { key: 'Reason', value: reasonLabel(m?.reason) || '—' },
    { key: 'Raised', value: stamp(m?.raisedAt) ?? '—' },
    { key: 'Acknowledged', value: stamp(m?.acknowledgedAt) ?? '—' },
    { key: 'Ack target', value: target ? `${target} min` : '—' },
  ];
  let progress =
    ackMin !== undefined && target
      ? {
          label: 'Ack time',
          value: Math.min(100, Math.round((ackMin / target) * 100)),
          valueText: `${ackMin} of ${target} min`,
        }
      : undefined;
  let subj = m?.subject as any;
  let subjSeverity = sentence(subj?.severity);
  return {
    subject: subj
      ? {
          title: m?.subjectTitle,
          severity: subjSeverity,
          tone: SEVERITY_TONES[subj?.severity ?? 'low'] ?? 'neutral',
        }
      : undefined,
    title: `Escalation ${from}→${to}${caseId ? ` · ${caseId}` : ''}`,
    subline: [
      reasonLabel(m?.reason),
      raisedBy ? `raised by ${raisedBy}` : undefined,
    ]
      .filter(Boolean)
      .join(' · '),
    statusLabel: sentence(status),
    statusTone: STATUS_TONES[status] ?? 'neutral',
    levelLabel: `${from} → ${to}`,
    shortTitle: `Escalation ${from}→${to}`,
    // fitted keeps the facts the mockup keeps at each height: status before the
    // ack time, the note last
    fitFacts: [
      facts[0]!,
      facts[1]!,
      facts[2]!,
      facts[3]!,
      facts[5]!,
      { key: 'Status', value: sentence(status) },
      facts[4]!,
      ...(m?.note ? [{ key: 'Note', value: m.note }] : []),
    ] as KeyValueItem[],
    reasonTag: reasonTag(m?.reason),
    reasonText: reasonLabel(m?.reason) || '—',
    fact,
    facts,
    detailFacts: [
      ...facts,
      ...(m?.note ? [{ key: 'Note', value: m.note }] : []),
      { key: 'Status', value: sentence(status) },
    ] as KeyValueItem[],
    note: m?.note,
    ackText: ackMin !== undefined ? `${ackMin} min` : '—',
    targetText: target ? `target ${target} min` : undefined,
    levelRole: m?.toLevel?.targetRoleName,
    progress,
    stats: [
      { key: 'Level', value: `${from} → ${to}` },
      ...(ackMin !== undefined
        ? [{ key: 'Ack time', value: `${ackMin} min` }]
        : []),
      { key: 'Reason', value: reasonLabel(m?.reason) || '—' },
    ] as FittedStat[],
    history: [
      m?.raisedAt
        ? {
            at: clock(m.raisedAt),
            title: `Raised ${from} → ${to}`,
            detail: [raisedBy, reasonLabel(m?.reason)]
              .filter(Boolean)
              .join(' · '),
          }
        : undefined,
      m?.acknowledgedAt
        ? {
            at: clock(m.acknowledgedAt),
            title: 'Acknowledged',
            detail: [
              m.acknowledgedByName,
              ackMin !== undefined
                ? `${ackMin} min${target ? `, ${ackMin <= target ? 'inside' : 'past'} the ${target} min target` : ''}`
                : undefined,
            ]
              .filter(Boolean)
              .join(' · '),
          }
        : undefined,
    ].filter(Boolean) as { at: string; title: string; detail: string }[],
  };
}

/** An Escalation drawn the Support Case way. Same schema as Escalation; only
    the formats differ. */
export class SupportEscalation extends Escalation {
  static displayName = 'Support Escalation';

  static fitted = class Fitted extends Component<typeof this> {
    get v() {
      return escView(this.args.model);
    }
    <template>
      <FittedExtras
        @facts={{this.v.fitFacts}}
        @stats={{this.v.stats}}
        @progress={{this.v.progress}}
        @relations={{if this.v.subject this.relations}}
      >
        <:default>
          <FitTile>
            <:avatar><span class='mark' aria-hidden='true'>Es</span></:avatar>
            <:title><span
                class='fit-title'
                role='heading'
                aria-level='3'
              >{{this.v.shortTitle}}</span></:title>
            <:subtitle>{{this.v.subline}}</:subtitle>
            <:status>
              <Chip
                @tone={{this.v.statusTone}}
                @appearance='soft'
                @shape='pill'
                @dot={{false}}
              >{{this.v.statusLabel}}</Chip>
              <Chip
                @tone='neutral'
                @appearance='soft'
                @shape='pill'
                @dot={{false}}
              >{{this.v.levelLabel}}</Chip>
            </:status>
            <:fact>{{this.v.fact}}</:fact>
          </FitTile>
        </:default>
        <:relation>
          <span class='subj'><span
              class='subj-mark'
              aria-hidden='true'
            >Cs</span><span
              class='subj-title'
            >{{this.v.subject.title}}</span>{{#if this.v.subject.severity}}<span
                class='subj-sev'
              ><Chip
                  @tone={{this.v.subject.tone}}
                  @appearance='soft'
                  @shape='pill'
                  @dot={{false}}
                >{{this.v.subject.severity}}</Chip></span>{{/if}}</span>
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
    relations = ['Subject'];
  };

  static embedded = class Embedded extends Component<typeof this> {
    get v() {
      return escView(this.args.model);
    }
    <template>
      <article class='emb'>
        <header class='emb-head'>
          <span class='mark' aria-hidden='true'>Es</span>
          <div class='emb-id'>
            <h3 class='emb-title'>{{this.v.title}}</h3>
            <p class='emb-sub'>{{this.v.subline}}</p>
          </div>
          <span class='emb-chips'>
            <Chip
              @tone={{this.v.statusTone}}
              @appearance='soft'
              @shape='pill'
              @dot={{false}}
            >{{this.v.statusLabel}}</Chip>
            <Chip
              @tone='neutral'
              @appearance='soft'
              @shape='pill'
              @dot={{false}}
            >{{this.v.levelLabel}}</Chip>
            {{#if this.v.reasonTag}}<Chip
                @tone='warning'
                @appearance='soft'
                @shape='pill'
                @dot={{false}}
              >{{this.v.reasonTag}}</Chip>{{/if}}
          </span>
        </header>
        <p class='emb-fact'>{{this.v.fact}}</p>
        <dl class='emb-facts'>
          {{#each this.v.facts as |item|}}
            <div class='emb-item'>
              <dt>{{item.key}}</dt>
              <dd>{{item.value}}</dd>
            </div>
          {{/each}}
        </dl>
        {{#if this.v.subject}}<p class='emb-subject'><span
              class='emb-subject-k'
            >Subject</span><span class='subj'><span
                class='subj-mark'
                aria-hidden='true'
              >Cs</span><span
                class='subj-title'
              >{{this.v.subject.title}}</span>{{#if
                this.v.subject.severity
              }}<Chip
                  @tone={{this.v.subject.tone}}
                  @appearance='soft'
                  @shape='pill'
                  @dot={{false}}
                >{{this.v.subject.severity}}</Chip>{{/if}}</span></p>{{/if}}
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
          .emb-subject {
            display: flex;
            align-items: center;
            gap: var(--boxel-sp-xs);
            margin: 0;
          }
          .emb-subject-k {
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
      return escView(this.args.model);
    }
    <template>
      <span class='atom'>
        <span class='atom-mark' aria-hidden='true'>Es</span>
        <span class='atom-name'>{{this.v.title}}</span>
        <Chip
          @tone={{this.v.statusTone}}
          @appearance='soft'
          @shape='pill'
          @dot={{false}}
        >{{this.v.statusLabel}}</Chip>
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
      return escView(this.args.model);
    }
    <template>
      <article class='iso'>
        <header class='iso-head'>
          <span class='mark' aria-hidden='true'>Es</span>
          <div class='iso-id'>
            <h1 class='iso-title'>{{this.v.title}}</h1>
            <p class='iso-sub'>{{this.v.subline}}</p>
          </div>
          <span class='iso-chips'>
            <Chip
              @tone={{this.v.statusTone}}
              @appearance='soft'
              @shape='pill'
              @dot={{false}}
            >{{this.v.statusLabel}}</Chip>
            <Chip
              @tone='neutral'
              @appearance='soft'
              @shape='pill'
              @dot={{false}}
            >{{this.v.levelLabel}}</Chip>
            {{#if this.v.reasonTag}}<Chip
                @tone='warning'
                @appearance='soft'
                @shape='pill'
                @dot={{false}}
              >{{this.v.reasonTag}}</Chip>{{/if}}
          </span>
        </header>
        <div class='iso-stats'>
          <Panel><Stat
              @label='Level'
              @value={{this.v.levelLabel}}
              @hint={{this.v.levelRole}}
              @roll={{false}}
            /></Panel>
          <Panel><Stat
              @label='Ack time'
              @value={{this.v.ackText}}
              @hint={{this.v.targetText}}
              @roll={{false}}
            /></Panel>
          <Panel><Stat
              @label='Reason'
              @value={{this.v.reasonText}}
              @roll={{false}}
            /></Panel>
        </div>
        <div class='iso-grid'>
          <div class='iso-col'>
            {{#if this.v.note}}
              <Panel @title='Note'><p
                  class='iso-text'
                >{{this.v.note}}</p></Panel>
            {{/if}}
            {{#if this.v.history.length}}
              <Panel @title='History'>
                <ol class='iso-history'>
                  {{#each this.v.history as |h|}}
                    <li class='iso-event'>
                      <span class='iso-time'>{{h.at}}</span>
                      <span class='iso-event-body'><strong>{{h.title}}</strong>
                        <span
                          class='iso-event-detail'
                        >{{h.detail}}</span></span>
                    </li>
                  {{/each}}
                </ol>
              </Panel>
            {{/if}}
          </div>
          <div class='iso-col'>
            {{#if this.v.subject}}
              <Panel @title='Linked'>
                <p class='iso-linked'><span
                    class='iso-linked-k'
                  >Subject</span><span class='subj'><span
                      class='subj-mark'
                      aria-hidden='true'
                    >Cs</span><span
                      class='subj-title'
                    >{{this.v.subject.title}}</span>{{#if
                      this.v.subject.severity
                    }}<Chip
                        @tone={{this.v.subject.tone}}
                        @appearance='soft'
                        @shape='pill'
                        @dot={{false}}
                      >{{this.v.subject.severity}}</Chip>{{/if}}</span></p>
              </Panel>
            {{/if}}
            <Panel @title='Details'>
              <KeyValue @items={{this.v.detailFacts}} @rows='ruled' />
            </Panel>
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
          .iso-text {
            margin: 0;
            white-space: pre-wrap;
          }
          .iso-linked {
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: var(--boxel-sp-xs);
            margin: 0;
          }
          .iso-linked-k {
            color: var(--muted-foreground);
          }
          .iso-history {
            list-style: none;
            margin: 0;
            padding: 0;
            display: grid;
            gap: var(--boxel-sp-sm);
          }
          .iso-event {
            display: grid;
            grid-template-columns: auto minmax(0, 1fr);
            gap: var(--boxel-sp-sm);
            padding-bottom: var(--boxel-sp-sm);
            border-bottom: 1px solid var(--border);
          }
          .iso-event:last-child {
            border-bottom: 0;
            padding-bottom: 0;
          }
          .iso-time {
            align-self: start;
            padding: var(--boxel-sp-4xs) var(--boxel-sp-xs);
            border-radius: var(--radius);
            background: var(--muted);
            color: var(--primary);
            font-size: var(--boxel-font-size-sm);
            font-weight: 600;
          }
          .iso-event-body {
            display: grid;
          }
          .iso-event-detail {
            color: var(--muted-foreground);
            font-size: var(--boxel-font-size-sm);
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
