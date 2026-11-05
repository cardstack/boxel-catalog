import {
  CardDef,
  Component,
  field,
  contains,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import DateTimeField from '@cardstack/base/datetime';
import TextAreaField from '@cardstack/base/text-area';
import enumField from '@cardstack/base/enum';
import TrendingUpIcon from '@cardstack/boxel-icons/trending-up';
import { EscalationLevelField } from '@cardstack/catalog/fields/escalation-level/escalation-level-field';
import {
  stateColor,
  type Hue,
  type StateColor,
} from '@cardstack/catalog/components/state-pill';
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

export const ESCALATION_REASONS = [
  'sla-risk',
  'customer-request',
  'agent-request',
  'breach',
  'policy',
] as const;

export const EscalationReasonField = enumField(StringField, {
  displayName: 'Escalation Reason',
  options: ESCALATION_REASONS as unknown as string[],
});

export const ESCALATION_STATUSES = [
  'open',
  'acknowledged',
  'resolved',
  'cancelled',
] as const;

export const EscalationStatusField = enumField(StringField, {
  displayName: 'Escalation Status',
  options: ESCALATION_STATUSES as unknown as string[],
});

/** Exported beside the enum so every consumer colors the ladder alike. */
export const ESCALATION_STATUS_HUES: Record<string, Hue> = {
  open: 'amber',
  acknowledged: 'blue',
  resolved: 'green',
  cancelled: 'slate',
};

export const ESCALATION_STATUS_COLORS: Record<string, StateColor> =
  Object.fromEntries(
    Object.entries(ESCALATION_STATUS_HUES).map(([k, h]) => [k, stateColor(h)]),
  );

export function escalationStatusHue(status?: string | null): Hue {
  return ESCALATION_STATUS_HUES[status ?? 'open'] ?? 'slate';
}

/**
 * One rung-climb on the ladder, as a RECORD — "escalated twice last quarter"
 * must be a query, not an anecdote.
 *
 * The receiving level's acknowledgement has its own clock
 * (`toLevel.ackTargetMinutes` vs `raisedAt`→`acknowledgedAt`): an
 * unacknowledged escalation is invisible risk and renders breach-amber wherever it is
 * listed. Cancellation is a coded act with a required reason (the
 * Cancel command enforces it); nothing here is ever deleted.
 *
 * `subject` is `linksTo(CardDef)` — the ladder works for any record type.
 */
const STATUS_TONES: Record<string, PretuiToneArg> = {
  open: 'warning',
  acknowledged: 'success',
  resolved: 'success',
  cancelled: 'neutral',
};
const MINUTE_MS = 60_000;
const SEVERITY_TONES: Record<string, PretuiToneArg> = {
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
function escView(m: Partial<Escalation> | undefined) {
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

export class Escalation extends CardDef {
  static displayName = 'Escalation';
  static icon = TrendingUpIcon;

  @field subject = linksTo(CardDef);
  /** Denormalised link facts: consumers join on these instead of touching
      `subject` (a lazy linksTo that would load mid-render). */
  @field subjectId = contains(StringField, {
    computeVia: function (this: Escalation) {
      return this.subject?.id;
    },
  });
  @field subjectTitle = contains(StringField, {
    computeVia: function (this: Escalation) {
      return (this.subject as any)?.cardTitle ?? (this.subject as any)?.title;
    },
  });
  @field fromLevel = contains(EscalationLevelField);
  @field toLevel = contains(EscalationLevelField);
  @field reason = contains(EscalationReasonField);
  @field note = contains(TextAreaField);
  @field raisedByName = contains(StringField, {
    description: 'Person or "policy <name>" — automation is always attributed.',
  });
  @field raisedAt = contains(DateTimeField);
  @field acknowledgedByName = contains(StringField);
  @field acknowledgedAt = contains(DateTimeField);
  @field status = contains(EscalationStatusField);
  @field cancelledReason = contains(StringField);

  @field ackOverdue = contains(StringField, {
    computeVia: function (this: Escalation) {
      if (this.acknowledgedAt || this.status !== 'open') return 'no';
      let target = this.toLevel?.ackTargetMinutes;
      let raised = this.raisedAt
        ? new Date(this.raisedAt as unknown as string)
        : null;
      if (!target || !raised) return 'no';
      return Date.now() - raised.getTime() > target * 60000 ? 'yes' : 'no';
    },
  });

  @field title = contains(StringField, {
    computeVia: function (this: Escalation) {
      let from = this.fromLevel?.key ?? '?';
      let to = this.toLevel?.key ?? '?';
      return `Escalation ${from} → ${to}`;
    },
  });

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
                @dot={{false}}
              >{{this.v.statusLabel}}</Chip>
              <Chip
                @tone='neutral'
                @appearance='soft'
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
              @dot={{false}}
            >{{this.v.statusLabel}}</Chip>
            <Chip
              @tone='neutral'
              @appearance='soft'
              @dot={{false}}
            >{{this.v.levelLabel}}</Chip>
            {{#if this.v.reasonTag}}<Chip
                @tone='warning'
                @appearance='soft'
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
            flex-wrap: wrap;
            align-items: center;
            gap: var(--boxel-sp-xs);
            margin: 0;
          }
          .emb-subject-k {
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
              @dot={{false}}
            >{{this.v.statusLabel}}</Chip>
            <Chip
              @tone='neutral'
              @appearance='soft'
              @dot={{false}}
            >{{this.v.levelLabel}}</Chip>
            {{#if this.v.reasonTag}}<Chip
                @tone='warning'
                @appearance='soft'
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
                        @dot={{false}}
                      >{{this.v.subject.severity}}</Chip>{{/if}}</span></p>
              </Panel>
            {{/if}}
            <Panel @title='Details'>
              <KeyValue @items={{this.v.detailFacts}} @divided={{true}} />
            </Panel>
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
          .iso-text {
            margin: 0;
            white-space: pre-wrap;
          }
          .iso-linked {
            display: flex;
            flex-wrap: wrap;
            align-items: center;
            justify-content: space-between;
            gap: var(--boxel-sp-xs);
            margin: 0;
          }
          .iso-linked-k {
            flex: none;
            white-space: nowrap;
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

export default Escalation;
