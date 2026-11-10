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
import { FitRows, TypeMark, lowercase } from './components/fit-rows';
import { eq } from '@cardstack/boxel-ui/helpers';

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
function short(value?: Date | null) {
  return value
    ? new Intl.DateTimeFormat('en-US', {
        month: 'short',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
        hour12: false,
      }).format(new Date(value))
    : '';
}
// Values set in the mono face: timestamps.
const MONO_KEYS = new Set(['Raised', 'Acknowledged']);
const isMono = (key: string) => MONO_KEYS.has(key);
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
    reasonKey: m?.reason ?? '',
    reasonTone: (m?.reason === 'breach'
      ? 'danger'
      : m?.reason
        ? 'warning'
        : 'neutral') as PretuiToneArg,
    statusKey: status,
    shortLevel: `${from}→${to}`,
    hasSubject: Boolean(subj),
    // fitted rows, highest priority first; a row the tile can't hold drops
    fitRows: [
      { key: 'Level', value: `${from} → ${to}` },
      ...(m?.reason ? [{ key: 'Reason', value: reasonLabel(m.reason) }] : []),
      ...(ackMin !== undefined
        ? [
            {
              key: 'Ack time',
              value: [`${ackMin} min`, target ? `target ${target}` : undefined]
                .filter(Boolean)
                .join(' · '),
            },
          ]
        : []),
      ...(subj ? [{ key: 'Subject', value: m?.subjectTitle ?? '' }] : []),
      ...(m?.raisedAt ? [{ key: 'Raised', value: short(m.raisedAt) }] : []),
      ...(m?.acknowledgedAt
        ? [{ key: 'Acknowledged', value: short(m.acknowledgedAt) }]
        : []),
      ...(target ? [{ key: 'Ack target', value: `${target} min` }] : []),
      ...(m?.note ? [{ key: 'Note', value: m.note }] : []),
    ] as KeyValueItem[],
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
    ],
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

  static embedded = class Embedded extends Component<typeof this> {
    get v() {
      return escView(this.args.model);
    }
    get rows(): KeyValueItem[] {
      return [
        ...this.v.facts,
        ...(this.v.hasSubject ? [{ key: 'Subject', value: '' }] : []),
      ];
    }
    <template>
      <article class='emb'>
        <header class='emb-head'>
          <TypeMark @label='Es' />
          <div class='emb-id'>
            <h3 class='emb-title'>{{this.v.title}}</h3>
            <p class='emb-sub'>{{this.v.subline}}</p>
          </div>
        </header>
        {{#if this.v.fact}}<p class='emb-fact'>{{this.v.fact}}</p>{{/if}}
        <KeyValue
          class='emb-kv'
          @items={{this.rows}}
          @labelStyle='eyebrow'
          @divided={{true}}
        >
          <:value as |item|>
            {{#if (eq item.key 'Subject')}}
              <span class='cell'><@fields.subject
                  @format='atom'
                  @displayContainer={{false}}
                /></span>
            {{else}}
              <span class={{if (isMono item.key) 'mono'}}>{{item.value}}</span>
            {{/if}}
          </:value>
        </KeyValue>
      </article>
      <style scoped>
        @layer PretComponent {
          .emb {
            display: grid;
            align-content: start;
            background: var(--card);
            color: var(--card-foreground);
          }
          .emb-head {
            display: flex;
            align-items: center;
            gap: var(--boxel-sp-xs);
            padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
            border-bottom: 1px solid var(--border);
          }
          .emb-id {
            min-width: 0;
          }
          .emb-title {
            margin: 0;
            font-size: var(--boxel-font-size-sm);
            font-weight: 600;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
          }
          .emb-sub,
          .emb-fact {
            margin: 0;
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          .emb-fact {
            padding: var(--boxel-sp-xs) var(--boxel-sp-sm) 0;
          }
          .emb-kv {
            padding: var(--boxel-sp-4xs) var(--boxel-sp-sm) var(--boxel-sp-xs);
            font-size: var(--boxel-font-size-sm);
          }
          .cell {
            display: flex;
            min-width: 0;
            max-width: 100%;
            overflow: hidden;
          }
          .mono {
            font-family: var(--font-mono);
            font-size: var(--boxel-font-size-xs);
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
        <TypeMark @label='Es' @size='sm' />
        <span class='atom-name'>{{this.v.title}}</span>
      </span>
      <style scoped>
        @layer PretComponent {
          .atom {
            display: inline-flex;
            align-items: center;
            gap: var(--boxel-sp-4xs);
            max-width: 100%;
            min-width: 0;
            vertical-align: middle;
            font-size: var(--boxel-font-size-xs);
            color: var(--card-foreground);
          }
          .atom-name {
            min-width: 0;
            font-weight: 600;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
          }
        }
      </style>
    </template>
  };

  static isolated = class Isolated extends Component<typeof this> {
    get v() {
      return escView(this.args.model);
    }
    get subjectRows(): KeyValueItem[] {
      return this.v.hasSubject ? [{ key: 'Subject', value: '' }] : [];
    }
    <template>
      <article class='iso'>
        <Panel>
          <div class='iso-head-row'>
            <TypeMark @label='Es' />
            <div class='iso-id'>
              <h1 class='iso-title'>{{this.v.title}}</h1>
              <p class='iso-sub'>{{this.v.subline}}</p>
            </div>
            <span class='iso-state'>
              <Chip
                @tone={{this.v.statusTone}}
                @appearance='plain'
              >{{this.v.statusKey}}</Chip>
              <Chip @appearance='plain'>{{this.v.shortLevel}}</Chip>
              {{#if this.v.reasonKey}}<Chip
                  @tone={{this.v.reasonTone}}
                  @appearance='plain'
                >{{this.v.reasonKey}}</Chip>{{/if}}
            </span>
          </div>
        </Panel>
        <Panel>
          <div class='iso-stats'>
            <Stat
              @label='Level'
              @value={{this.v.levelLabel}}
              @hint={{this.v.levelRole}}
              @roll={{false}}
            />
            <Stat
              @label='Ack time'
              @tone={{this.v.statusTone}}
              @value={{this.v.ackText}}
              @hint={{this.v.targetText}}
              @roll={{false}}
            />
            <Stat
              @label='Reason'
              @tone={{this.v.reasonTone}}
              @value={{this.v.reasonText}}
              @hint={{this.v.note}}
              @roll={{false}}
            />
          </div>
        </Panel>
        <div class='iso-grid'>
          <div class='iso-col'>
            {{#if this.v.note}}
              <Panel @title='Note' @variant='inspector'>
                <p class='iso-text'>{{this.v.note}}</p>
              </Panel>
            {{/if}}
            {{#if this.v.history.length}}
              <Panel @title='History' @variant='inspector'>
                <ul class='iso-rows'>
                  {{#each this.v.history as |h|}}
                    <li class='iso-row'>
                      <span class='iso-row-title'>{{h.at}}</span>
                      <span class='iso-row-meta'>{{h.title}}{{#if h.detail}}
                          ·
                          {{h.detail}}{{/if}}</span>
                    </li>
                  {{/each}}
                </ul>
              </Panel>
            {{/if}}
          </div>
          <div class='iso-col'>
            {{#if this.v.hasSubject}}
              <Panel @title='Linked' @variant='inspector'>
                <KeyValue
                  @items={{this.subjectRows}}
                  @labelStyle='eyebrow'
                  @divided={{true}}
                >
                  <:value><span class='cell'><@fields.subject
                        @format='atom'
                      /></span></:value>
                </KeyValue>
              </Panel>
            {{/if}}
            <Panel @title='Details' @variant='inspector'>
              <KeyValue
                @items={{this.v.detailFacts}}
                @labelStyle='eyebrow'
                @divided={{true}}
              >
                <:value as |item|>
                  <span
                    class={{if (isMono item.key) 'mono'}}
                  >{{item.value}}</span>
                </:value>
              </KeyValue>
            </Panel>
          </div>
        </div>
      </article>
      <style scoped>
        @layer PretComponent {
          .iso {
            container-type: inline-size;
            display: grid;
            align-content: start;
            gap: var(--boxel-sp-xs);
            min-height: 100%;
            padding: var(--boxel-sp-xs);
            background: var(--muted);
            color: var(--card-foreground);
            font-size: var(--boxel-font-size-sm);
          }
          .iso-head-row {
            display: grid;
            grid-template-columns: auto minmax(0, 1fr) auto;
            align-items: center;
            gap: var(--boxel-sp-xs);
          }
          .iso-id {
            min-width: 0;
          }
          .iso-title {
            margin: 0;
            font-family: var(--font-sans);
            font-size: var(--boxel-font-size);
            font-weight: 700;
            line-height: 1.3;
          }
          .iso-sub {
            margin: 0;
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          .iso-state {
            display: inline-flex;
            flex-wrap: wrap;
            align-items: center;
            gap: var(--boxel-sp-sm);
          }
          .iso-stats {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(9rem, 1fr));
          }
          .iso-stats > * {
            padding-inline: var(--boxel-sp-sm);
          }
          .iso-stats > * + * {
            border-inline-start: 1px solid var(--border);
          }
          .iso-stats > :first-child {
            padding-inline-start: 0;
          }
          .iso-grid {
            display: grid;
            grid-template-columns: minmax(0, 2fr) minmax(0, 1fr);
            gap: var(--boxel-sp-xs);
            align-items: start;
          }
          .iso-col {
            display: grid;
            gap: var(--boxel-sp-xs);
            min-width: 0;
          }
          .iso-text {
            margin: 0;
            padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
            white-space: pre-wrap;
          }
          .iso-rows {
            margin: 0;
            padding: 0;
            list-style: none;
          }
          .iso-row {
            display: grid;
            padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          }
          .iso-row + .iso-row {
            border-top: 1px solid var(--border);
          }
          .iso-row-title {
            font-weight: 600;
          }
          .iso-row-meta {
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          .cell {
            display: flex;
            min-width: 0;
            max-width: 100%;
            overflow: hidden;
          }
          .mono {
            font-family: var(--font-mono);
            font-size: var(--boxel-font-size-xs);
          }
          @container (width < 40rem) {
            .iso-head-row {
              grid-template-columns: auto minmax(0, 1fr);
            }
            .iso-state {
              grid-column: 1 / -1;
            }
            .iso-grid {
              grid-template-columns: minmax(0, 1fr);
            }
          }
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get v() {
      return escView(this.args.model);
    }
    <template>
      <FitRows @items={{this.v.fitRows}}>
        <:tile>
          <FitTile>
            <:avatar><TypeMark @label='Es' /></:avatar>
            <:title><span
                class='fit-title'
                role='heading'
                aria-level='3'
              >{{this.v.title}}</span></:title>
            <:subtitle>{{this.v.subline}}</:subtitle>
            <:status>
              <Chip @tone={{this.v.statusTone}} @appearance='plain'>{{lowercase
                  this.v.statusLabel
                }}</Chip>
            </:status>
          </FitTile>
        </:tile>
        <:row as |item|>
          {{#if (eq item.key 'Subject')}}
            <@fields.subject @format='atom' @displayContainer={{false}} />
          {{else}}
            <span class={{if (isMono item.key) 'mono'}}>{{item.value}}</span>
          {{/if}}
        </:row>
      </FitRows>
      <style scoped>
        @layer PretComponent {
          .fit-title {
            display: block;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
          }
          .mono {
            font-family: var(--font-mono);
          }
        }
      </style>
    </template>
  };
}
