import { markDefinition } from '@cardstack/base/mark-definition';
import {
  CardDef,
  Component,
  field,
  contains,
  containsMany,
  linksTo,
  linksToMany,
  StringField,
} from '@cardstack/base/card-api';
import DateField from '@cardstack/base/date';
import TextAreaField from '@cardstack/base/text-area';
import MarkdownField from '@cardstack/base/markdown';
import enumField from '@cardstack/base/enum';
import { Ticket } from './ticket';
import { Account } from '../crm/account';
import { Employee } from '../hr/employee';
import {
  stateColor,
  type StateColor,
} from '@cardstack/catalog/components/state-pill';
import { RecordIdentifierField } from '@cardstack/catalog/fields/record-identifier/record-identifier-field';
import { RecordOwnerField } from '@cardstack/catalog/fields/record-owner/record-owner-field';
import { RelationshipSetField } from '@cardstack/catalog/fields/relationship-set/relationship-set-field';
import { ExternalReferenceField } from '@cardstack/catalog/fields/external-reference/external-reference-field';
import { WorkflowStateField } from '@cardstack/catalog/fields/workflow-state/workflow-state-field';
import { Avatar } from '@cardstack/pretui/components/avatar';
import type { PretuiToneArg } from '@cardstack/pretui/pretui-primitives';
import { Chip } from '@cardstack/pretui/components/chip';
import { Panel } from '@cardstack/pretui/components/panel';
import { Stat } from '@cardstack/pretui/components/stat';
import { FitTile } from '../shared/fit-tile';
import { FitRows, TypeMark, lowercase } from './components/fit-rows';
import {
  KeyValue,
  type KeyValueItem,
} from '@cardstack/pretui/components/key-value';

export const CASE_STATUSES = [
  'open',
  'investigating',
  'waiting-on-customer',
  'resolved',
  'closed',
];

export const CASE_STATUS_LABELS: Record<string, string> = {
  open: 'Open',
  investigating: 'Investigating',
  'waiting-on-customer': 'Waiting on Customer',
  resolved: 'Resolved',
  closed: 'Closed',
};

export const CASE_STATUS_COLORS: Record<string, StateColor> = {
  open: stateColor('blue'),
  investigating: stateColor('amber'),
  'waiting-on-customer': stateColor('slate'),
  resolved: stateColor('green'),
  closed: stateColor('slate'),
};

export const STATUS_HUES: Record<string, 'blue' | 'amber' | 'slate' | 'green'> =
  {
    open: 'blue',
    investigating: 'amber',
    'waiting-on-customer': 'slate',
    resolved: 'green',
    closed: 'slate',
  };

export const CaseStatusField = markDefinition(
  enumField(StringField, {
    options: CASE_STATUSES.map((value) => ({
      value,
      label: CASE_STATUS_LABELS[value],
    })),
    displayName: 'Case Status',
  }),
);

export const CASE_SEVERITIES = ['low', 'medium', 'high', 'critical'];

export const CaseSeverityField = markDefinition(
  enumField(StringField, {
    options: CASE_SEVERITIES.map((value) => ({ value, label: value })),
    displayName: 'Case Severity',
  }),
);

export const SEVERITY_HUES: Record<string, 'slate' | 'amber' | 'red'> = {
  low: 'slate',
  medium: 'slate',
  high: 'amber',
  critical: 'red',
};

// A Case is the longer-running investigation a Ticket is not: one customer
// problem that may span several tickets, days, and owners, with its own
// severity, findings, and resolution record. Tickets stay the unit of
// conversation; the Case is the unit of accountability — it LINKS the
// related tickets rather than replacing them.
const SEVERITY_TONES: Record<string, PretuiToneArg> = {
  low: 'neutral',
  medium: 'neutral',
  high: 'warning',
  critical: 'danger',
};
const STATUS_TONES: Record<string, PretuiToneArg> = {
  open: 'info',
  investigating: 'warning',
  'waiting-on-customer': 'neutral',
  resolved: 'success',
  closed: 'neutral',
};
const DAY_MS = 86_400_000;

function sentence(value?: string | null) {
  return value ? value[0]!.toUpperCase() + value.slice(1) : '';
}
// openedOn is a calendar date: format it in UTC so it never shifts a day.
function shortDate(value?: Date | null, year = false) {
  if (!value) return undefined;
  return new Intl.DateTimeFormat('en-US', {
    month: 'short',
    day: 'numeric',
    year: year ? 'numeric' : undefined,
    timeZone: 'UTC',
  }).format(new Date(value));
}

// lastSeenAt / since are instants: shown in the reader's own clock.
function shortTime(value?: Date | null, year = false) {
  if (!value) return undefined;
  return new Intl.DateTimeFormat('en-US', {
    month: 'short',
    day: 'numeric',
    year: year ? 'numeric' : undefined,
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  }).format(new Date(value));
}

const REF_TONES: Record<string, PretuiToneArg> = {
  open: 'info',
  'in progress': 'warning',
  closed: 'neutral',
  resolved: 'success',
};
const RELATION_LABELS: Record<string, string> = {
  'duplicate-of': 'Duplicate of',
};
// Values set in the mono face: identifiers and dates.
const MONO_KEYS = new Set(['Case ID', 'Opened', 'Since']);
const isMono = (key: string) => MONO_KEYS.has(key);
const isKey = (key: string, want: string) => key === want;

type CaseView = ReturnType<typeof caseView>;

/** The strings every SupportCase format shows, read once from the model. */
function caseView(m: Partial<Case> | undefined) {
  let severityLabel = sentence(m?.severity);
  let statusLabel = CASE_STATUS_LABELS[m?.status ?? 'open'] ?? 'Open';
  let wf = m?.workflowState?.label;
  let caseId = m?.caseId?.value;
  let team = m?.ownership?.teamName;
  let opened = shortDate(m?.openedOn);
  let o = m?.ownership;
  let refs = m?.externalRefs ?? [];
  let facts: KeyValueItem[] = [
    { key: 'Case ID', value: caseId ?? '—' },
    { key: 'Severity', value: severityLabel || '—' },
    { key: 'Status', value: statusLabel },
    { key: 'Workflow', value: wf ?? '—' },
    { key: 'Opened', value: shortDate(m?.openedOn, true) ?? '—' },
    { key: 'Team', value: team ?? '—' },
  ];
  for (let ref of refs) {
    facts.push({
      key: ref.system?.name ?? 'Link',
      value: [ref.externalId, ref.state].filter(Boolean).join(' · '),
    });
  }
  let endTime = m?.resolvedOn ? new Date(m.resolvedOn) : new Date();
  let days = m?.openedOn
    ? Math.max(
        0,
        Math.round(
          (endTime.getTime() - new Date(m.openedOn).getTime()) / DAY_MS,
        ),
      )
    : undefined;
  let duplicate = m?.relationships?.relations?.find(
    (r) => r.kind === 'duplicate-of',
  );
  // read from the record fields, not the links: touching a linksTo here
  // makes Case's type reference itself
  let hasOwner = Boolean(o?.ownerName);
  let hasDuplicate = Boolean(duplicate);
  let linked: KeyValueItem[] = [
    ...(hasOwner ? [{ key: 'Owner', value: o?.ownerName ?? '' }] : []),
    ...(hasDuplicate
      ? [{ key: 'Duplicate of', value: duplicate?.targetTitle ?? '' }]
      : []),
  ];
  return {
    severityLabel,
    severityTone: SEVERITY_TONES[m?.severity ?? 'low'] ?? 'neutral',
    statusLabel,
    statusTone: STATUS_TONES[m?.status ?? 'open'] ?? 'neutral',
    workflowLabel: wf,
    caseId,
    subline: [caseId, team, opened ? `opened ${opened}` : undefined]
      .filter(Boolean)
      .join(' · '),
    ownerName: o?.ownerName ?? '',
    previousOwnerName: o?.previousOwnerName ?? '',
    tookOver: o?.previousOwnerName
      ? ` · took over from ${o.previousOwnerName}${o.how ? ` by ${o.how}` : ''}`
      : '',
    duplicate,
    facts,
    linked,
    // fitted rows, highest priority first; a row the tile can't hold drops
    fitRows: [
      { key: 'Status', value: statusLabel },
      ...(hasOwner ? [{ key: 'Owner', value: o?.ownerName ?? '' }] : []),
      ...(wf ? [{ key: 'Workflow', value: wf }] : []),
      ...(team ? [{ key: 'Team', value: team }] : []),
      ...(m?.openedOn
        ? [{ key: 'Opened', value: shortDate(m.openedOn, true) ?? '' }]
        : []),
      ...(hasDuplicate
        ? [{ key: 'Duplicate of', value: duplicate?.targetTitle ?? '' }]
        : []),
      ...(refs.length
        ? [
            {
              key: 'Refs',
              value: refs
                .map((r) => r.system?.name)
                .filter(Boolean)
                .join(' · '),
            },
          ]
        : []),
      ...(o?.previousOwnerName
        ? [{ key: 'Previous owner', value: o.previousOwnerName }]
        : []),
      ...(o?.since ? [{ key: 'Since', value: shortTime(o.since) ?? '' }] : []),
    ] as KeyValueItem[],
    days,
    daysText: days === undefined ? '—' : `${days} days`,
    openedLong: m?.openedOn ? `since ${shortDate(m.openedOn, true)}` : '',
    refsCount: refs.length,
    refNames: refs
      .map((r) => r.system?.name)
      .filter(Boolean)
      .join(' · '),
    ownership: [
      { key: 'Owner', value: o?.ownerName ?? '—' },
      { key: 'Team', value: team ?? '—' },
      { key: 'How', value: sentence(o?.how) || '—' },
      { key: 'Previous owner', value: o?.previousOwnerName ?? '—' },
      { key: 'Since', value: shortTime(o?.since, true) ?? '—' },
    ] as KeyValueItem[],
    refRows: refs.map((r) => ({
      title: [r.system?.name, r.externalId].filter(Boolean).join(' '),
      meta: [
        r.system?.kind,
        r.lastSeenAt ? `last seen ${shortTime(r.lastSeenAt)}` : undefined,
      ]
        .filter(Boolean)
        .join(' · '),
      state: r.state ?? '',
      tone: REF_TONES[(r.state ?? '').toLowerCase()] ?? 'neutral',
    })),
    relationRows: (m?.relationships?.relations ?? []).map((r) => ({
      title: `${RELATION_LABELS[r.kind ?? ''] ?? sentence(r.kind)} ${
        r.targetTitle ?? ''
      }`.trim(),
      meta: [
        r.createdByName ? `added by ${r.createdByName}` : undefined,
        shortTime(r.createdAt),
      ]
        .filter(Boolean)
        .join(' · '),
    })),
  };
}

export class Case extends CardDef {
  static displayName = 'Case';
  static headerColor = '#8b3a3a';

  @field subject = contains(StringField);
  @field account = linksTo(() => Account);
  @field owner = linksTo(() => Employee);
  /** The case this one duplicates. */
  @field duplicateOf = linksTo(() => Case);
  @field status = contains(CaseStatusField);
  @field severity = contains(CaseSeverityField);
  @field openedOn = contains(DateField);
  @field resolvedOn = contains(DateField);
  @field relatedTickets = linksToMany(() => Ticket);
  // ── Record operations: identity, ownership, relationships, references and
  // the workflow position. All optional, so a case without them still reads.
  @field caseId = contains(RecordIdentifierField);
  @field ownership = contains(RecordOwnerField);
  @field relationships = contains(RelationshipSetField);
  @field externalRefs = containsMany(ExternalReferenceField);
  @field workflowState = contains(WorkflowStateField);
  @field problemStatement = contains(TextAreaField);
  @field findings = contains(MarkdownField);
  @field resolution = contains(TextAreaField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: Case) {
      return this.subject?.trim()?.length ? this.subject : 'Untitled Case';
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    get v(): CaseView {
      return caseView(this.args.model);
    }
    get rows(): KeyValueItem[] {
      return [...this.v.facts.slice(0, 6), ...this.v.linked];
    }
    <template>
      <article class='emb'>
        <header class='emb-head'>
          <TypeMark @label='Cs' />
          <div class='emb-id'>
            <h3 class='emb-title'>{{@model.subject}}</h3>
            <p class='emb-sub'>{{this.v.subline}}</p>
          </div>
        </header>
        {{#if this.v.ownerName}}
          <p class='emb-owner'>Owner
            <strong>{{this.v.ownerName}}</strong>{{this.v.tookOver}}</p>
        {{/if}}
        <KeyValue
          class='emb-kv'
          @items={{this.rows}}
          @labelStyle='eyebrow'
          @divided={{true}}
        >
          <:value as |item|>
            {{#if (isKey item.key 'Owner')}}
              {{#if @model.owner}}<span class='cell'><@fields.owner
                    @format='atom'
                    @displayContainer={{false}}
                  /></span>{{else}}{{item.value}}{{/if}}
            {{else if (isKey item.key 'Duplicate of')}}
              {{#if @model.duplicateOf}}<span class='cell'><@fields.duplicateOf
                    @format='atom'
                    @displayContainer={{false}}
                  /></span>{{else}}{{item.value}}{{/if}}
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
          .emb-owner {
            margin: 0;
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          .emb-owner {
            padding: var(--boxel-sp-xs) var(--boxel-sp-sm) 0;
          }
          .emb-owner strong {
            color: var(--card-foreground);
            font-weight: 600;
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
    <template>
      <span class='atom'>
        <TypeMark @label='Cs' @size='sm' />
        <span class='atom-name'>{{@model.subject}}</span>
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
    get v(): CaseView {
      return caseView(this.args.model);
    }
    <template>
      <article class='iso'>
        <Panel class='iso-head'>
          <div class='iso-head-row'>
            <TypeMark @label='Cs' />
            <div class='iso-id'>
              <h1 class='iso-title'>{{@model.subject}}</h1>
              <p class='iso-sub'>{{this.v.subline}}</p>
            </div>
            <span class='iso-state'>
              {{#if this.v.severityLabel}}<Chip
                  @tone={{this.v.severityTone}}
                  @appearance='plain'
                >{{lowercase this.v.severityLabel}}</Chip>{{/if}}
              <Chip @tone={{this.v.statusTone}} @appearance='plain'>{{lowercase
                  this.v.statusLabel
                }}</Chip>
              {{#if this.v.workflowLabel}}<Chip
                  @tone='info'
                  @appearance='plain'
                >{{lowercase this.v.workflowLabel}}</Chip>{{/if}}
            </span>
          </div>
        </Panel>
        <Panel class='iso-strip'>
          <div class='iso-stats'>
            <Stat
              @label='Severity'
              @tone={{this.v.severityTone}}
              @value={{if this.v.severityLabel this.v.severityLabel '—'}}
              @roll={{false}}
            />
            <Stat
              @label='Open for'
              @tone='warning'
              @value={{this.v.daysText}}
              @hint={{this.v.openedLong}}
              @roll={{false}}
            />
            <Stat
              @label='External refs'
              @tone='info'
              @value={{this.v.refsCount}}
              @hint={{this.v.refNames}}
              @roll={{false}}
            />
          </div>
        </Panel>
        <div class='iso-grid'>
          <div class='iso-col'>
            {{#if @model.problemStatement}}
              <Panel @title='Problem statement' @variant='inspector'>
                <p class='iso-text'>{{@model.problemStatement}}</p>
              </Panel>
            {{/if}}
            <Panel @title='Ownership' @variant='inspector'>
              <KeyValue
                @items={{this.v.ownership}}
                @labelStyle='eyebrow'
                @divided={{true}}
              >
                <:value as |item|>
                  {{#if (isKey item.key 'Owner')}}
                    {{#if @model.owner}}<span class='cell'><@fields.owner
                          @format='atom'
                          @displayContainer={{false}}
                        /></span>{{else}}{{item.value}}{{/if}}
                  {{else if (isKey item.key 'Previous owner')}}
                    {{#if this.v.previousOwnerName}}<span
                        class='iso-person'
                      ><Avatar
                          @name={{this.v.previousOwnerName}}
                          @size={{20}}
                          aria-hidden='true'
                        />{{item.value}}</span>{{else}}{{item.value}}{{/if}}
                  {{else}}
                    <span
                      class={{if (isMono item.key) 'mono'}}
                    >{{item.value}}</span>
                  {{/if}}
                </:value>
              </KeyValue>
            </Panel>
            {{#if this.v.refRows.length}}
              <Panel @title='External references' @variant='inspector'>
                <ul class='iso-rows'>
                  {{#each this.v.refRows as |ref|}}
                    <li class='iso-row'>
                      <span class='iso-row-main'>
                        <span class='iso-row-title'>{{ref.title}}</span>
                        <span class='iso-row-meta'>{{ref.meta}}</span>
                      </span>
                      {{#if ref.state}}<Chip
                          @tone={{ref.tone}}
                          @appearance='plain'
                        >{{ref.state}}</Chip>{{/if}}
                    </li>
                  {{/each}}
                </ul>
              </Panel>
            {{/if}}
            {{#if this.v.relationRows.length}}
              <Panel @title='Related' @variant='inspector'>
                <ul class='iso-rows'>
                  {{#each this.v.relationRows as |rel|}}
                    <li class='iso-row'>
                      <span class='iso-row-main'>
                        <span class='iso-row-title'>{{rel.title}}</span>
                        <span class='iso-row-meta'>{{rel.meta}}</span>
                      </span>
                    </li>
                  {{/each}}
                </ul>
              </Panel>
            {{/if}}
          </div>
          <div class='iso-col'>
            {{#if this.v.linked.length}}
              <Panel @title='Linked' @variant='inspector'>
                <KeyValue
                  @items={{this.v.linked}}
                  @labelStyle='eyebrow'
                  @divided={{true}}
                >
                  <:value as |item|>
                    {{#if (isKey item.key 'Owner')}}
                      {{#if @model.owner}}<span class='cell'><@fields.owner
                            @format='atom'
                          /></span>{{else}}{{item.value}}{{/if}}
                    {{else}}
                      {{#if @model.duplicateOf}}<span
                          class='cell'
                        ><@fields.duplicateOf
                            @format='atom'
                          /></span>{{else}}{{item.value}}{{/if}}
                    {{/if}}
                  </:value>
                </KeyValue>
              </Panel>
            {{/if}}
            <Panel @title='Details' @variant='inspector'>
              <KeyValue
                @items={{this.v.facts}}
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
          .iso-person {
            display: inline-flex;
            align-items: center;
            gap: var(--boxel-sp-4xs);
            font-weight: 600;
          }
          .iso-rows {
            margin: 0;
            padding: 0;
            list-style: none;
          }
          .iso-row {
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: var(--boxel-sp-xs);
            padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          }
          .iso-row + .iso-row {
            border-top: 1px solid var(--border);
          }
          .iso-row-main {
            display: grid;
            min-width: 0;
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
    get v(): CaseView {
      return caseView(this.args.model);
    }
    <template>
      <FitRows @items={{this.v.fitRows}}>
        <:tile>
          <FitTile>
            <:avatar><TypeMark @label='Cs' /></:avatar>
            <:title><span
                class='fit-title'
                role='heading'
                aria-level='3'
              >{{@model.subject}}</span></:title>
            <:subtitle>{{this.v.subline}}</:subtitle>
            <:status>
              {{#if this.v.severityLabel}}<Chip
                  @tone={{this.v.severityTone}}
                  @appearance='plain'
                >{{lowercase this.v.severityLabel}}</Chip>{{/if}}
            </:status>
          </FitTile>
        </:tile>
        <:row as |item|>
          {{#if (isKey item.key 'Status')}}
            <Chip @tone={{this.v.statusTone}} @appearance='plain'>{{lowercase
                item.value
              }}</Chip>
          {{else if (isKey item.key 'Workflow')}}
            <Chip @tone='info' @appearance='plain'>{{lowercase
                item.value
              }}</Chip>
          {{else if (isKey item.key 'Owner')}}
            {{#if @model.owner}}<@fields.owner
                @format='atom'
                @displayContainer={{false}}
              />{{else}}{{item.value}}{{/if}}
          {{else if (isKey item.key 'Duplicate of')}}
            {{#if @model.duplicateOf}}<@fields.duplicateOf
                @format='atom'
                @displayContainer={{false}}
              />{{else}}{{item.value}}{{/if}}
          {{else if (isKey item.key 'Previous owner')}}
            <span class='fit-person'><Avatar
                @name={{item.value}}
                @size={{20}}
                aria-hidden='true'
              />{{item.value}}</span>
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
          .fit-person {
            display: inline-flex;
            align-items: center;
            gap: var(--boxel-sp-4xs);
            font-weight: 600;
          }
          .mono {
            font-family: var(--font-mono);
          }
        }
      </style>
    </template>
  };
}
