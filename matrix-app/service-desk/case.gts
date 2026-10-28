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
import { eq } from '@cardstack/boxel-ui/helpers';
import { Avatar } from '../../ui-component/components/avatar';
import type { PretuiToneArg } from '../../ui-component/pretui-primitives';
import { Chip } from '../../ui-component/components/chip';
import { Panel } from '../../ui-component/components/panel';
import { Stat } from '../../ui-component/components/stat';
import { FitTile } from '../../ui-component/components/fit-tile';
import {
  KeyValue,
  type KeyValueItem,
} from '../../ui-component/components/key-value';
import { FittedExtras, type FittedStat } from '../procurement/vendor';

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

export const CaseStatusField = enumField(StringField, {
  options: CASE_STATUSES.map((value) => ({
    value,
    label: CASE_STATUS_LABELS[value],
  })),
  displayName: 'Case Status',
});

export const CASE_SEVERITIES = ['low', 'medium', 'high', 'critical'];

export const CaseSeverityField = enumField(StringField, {
  options: CASE_SEVERITIES.map((value) => ({ value, label: value })),
  displayName: 'Case Severity',
});

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

/** The strings every SupportCase format shows, read once from the model. */
function caseView(m: Partial<Case> | undefined) {
  let severityLabel = sentence(m?.severity);
  let statusLabel = CASE_STATUS_LABELS[m?.status ?? 'open'] ?? 'Open';
  let wf = m?.workflowState?.label;
  let caseId = m?.caseId?.value;
  let team = m?.ownership?.teamName;
  let opened = shortDate(m?.openedOn);
  let o = m?.ownership;
  let ownerLine: string | undefined;
  if (o?.ownerName) {
    ownerLine = `Owner ${o.ownerName}`;
    if (o.previousOwnerName) {
      ownerLine += ` · took over from ${o.previousOwnerName}`;
      if (o.how) ownerLine += ` by ${o.how}`;
    }
  }
  let facts: KeyValueItem[] = [
    { key: 'Case ID', value: caseId ?? '—' },
    { key: 'Severity', value: severityLabel || '—' },
    { key: 'Status', value: statusLabel },
    { key: 'Workflow', value: wf ?? '—' },
    { key: 'Opened', value: shortDate(m?.openedOn, true) ?? '—' },
    { key: 'Team', value: team ?? '—' },
  ];
  for (let ref of m?.externalRefs ?? []) {
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
  return {
    severityLabel,
    severityTone: SEVERITY_TONES[m?.severity ?? 'low'] ?? 'neutral',
    statusLabel,
    statusTone: STATUS_TONES[m?.status ?? 'open'] ?? 'neutral',
    // dropped when it only repeats the status chip
    workflowLabel:
      wf && wf.toLowerCase() !== statusLabel.toLowerCase() ? wf : undefined,
    caseId,
    subline: [caseId, team, opened ? `opened ${opened}` : undefined]
      .filter(Boolean)
      .join(' · '),
    ownerName: o?.ownerName ?? '',
    ownerLine,
    duplicate: m?.relationships?.relations?.find(
      (r) => r.kind === 'duplicate-of',
    ),
    facts,
    days,
    refsCount: (m?.externalRefs ?? []).length,
    refNames: (m?.externalRefs ?? [])
      .map((r) => r.system?.name)
      .filter(Boolean)
      .join(' · '),
    ownership: [
      { key: 'Owner', value: o?.ownerName ?? '—' },
      { key: 'Team', value: team ?? '—' },
      { key: 'How', value: sentence(o?.how) || '—' },
      { key: 'Previous owner', value: o?.previousOwnerName ?? '—' },
      {
        key: 'Since',
        value: o?.since ? (shortDate(o.since, true) ?? '—') : '—',
      },
    ] as KeyValueItem[],
    externalRefs: (m?.externalRefs ?? []).map((r) => ({
      key: r.system?.name ?? 'Link',
      value: [r.externalId, r.state].filter(Boolean).join(' · '),
    })) as KeyValueItem[],
  };
}

export class Case extends CardDef {
  static displayName = 'Case';
  static headerColor = '#8b3a3a';

  @field subject = contains(StringField);
  @field account = linksTo(() => Account);
  @field owner = linksTo(() => Employee);
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
    get v() {
      return caseView(this.args.model);
    }
    <template>
      <article class='emb'>
        <header class='emb-head'>
          <span class='emb-mark' aria-hidden='true'>Cs</span>
          <div class='emb-id'>
            <h3 class='emb-title'>{{@model.subject}}</h3>
            <p class='emb-sub'>{{this.v.subline}}</p>
          </div>
          <span class='emb-chips'>
            {{#if this.v.severityLabel}}<Chip
                @tone={{this.v.severityTone}}
                @appearance='soft'
                @shape='pill'
                @dot={{false}}
              >{{this.v.severityLabel}}</Chip>{{/if}}
            <Chip
              @tone={{this.v.statusTone}}
              @appearance='soft'
              @shape='pill'
              @dot={{false}}
            >{{this.v.statusLabel}}</Chip>
            {{#if this.v.workflowLabel}}<Chip
                @tone='primary'
                @appearance='soft'
                @shape='pill'
                @dot={{false}}
              >{{this.v.workflowLabel}}</Chip>{{/if}}
          </span>
        </header>
        {{#if this.v.ownerLine}}<p
            class='emb-owner'
          >{{this.v.ownerLine}}</p>{{/if}}
        <dl class='emb-facts'>
          {{#each this.v.facts as |item|}}
            <div class='emb-fact'>
              <dt>{{item.key}}</dt>
              <dd>{{item.value}}</dd>
            </div>
          {{/each}}
        </dl>
        <div class='emb-rels'>
          {{#if this.v.ownerName}}<span class='emb-rel'><span
                class='emb-rel-k'
              >Owner</span><Avatar
                @name={{this.v.ownerName}}
                @size={{24}}
                aria-hidden='true'
              />{{this.v.ownerName}}</span>{{/if}}
          {{#if this.v.duplicate}}<span class='emb-rel'><span
                class='emb-rel-k'
              >Duplicate of</span><span
                class='mark mark-sm'
                aria-hidden='true'
              >Cs</span>{{this.v.duplicate.targetTitle}}</span>{{/if}}
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
          .emb-owner {
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
          .emb-fact {
            min-width: 0;
          }
          .emb-fact dt {
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          .emb-fact dd {
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
            display: inline-flex;
            align-items: center;
            gap: var(--boxel-sp-xs);
            font-weight: 600;
          }
          .emb-rel-k {
            font-weight: 400;
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
          .mark-sm {
            inline-size: 1.5rem;
            block-size: 1.5rem;
          }
          .emb-mark {
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
      return caseView(this.args.model);
    }
    <template>
      <span class='atom'>
        <span class='atom-mark' aria-hidden='true'>Cs</span>
        <span class='atom-name'>{{@model.subject}}</span>
        {{#if this.v.severityLabel}}<Chip
            @tone={{this.v.severityTone}}
            @appearance='soft'
            @shape='pill'
            @dot={{false}}
          >{{this.v.severityLabel}}</Chip>{{/if}}
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
      return caseView(this.args.model);
    }
    get daysText() {
      return this.v.days === undefined ? '—' : `${this.v.days} days`;
    }
    <template>
      <article class='iso'>
        <header class='iso-head'>
          <span class='iso-mark' aria-hidden='true'>Cs</span>
          <div class='iso-id'>
            <h1 class='iso-title'>{{@model.subject}}</h1>
            <p class='iso-sub'>{{this.v.subline}}</p>
          </div>
          <span class='iso-chips'>
            {{#if this.v.severityLabel}}<Chip
                @tone={{this.v.severityTone}}
                @appearance='soft'
                @shape='pill'
                @dot={{false}}
              >{{this.v.severityLabel}}</Chip>{{/if}}
            <Chip
              @tone={{this.v.statusTone}}
              @appearance='soft'
              @shape='pill'
              @dot={{false}}
            >{{this.v.statusLabel}}</Chip>
            {{#if this.v.workflowLabel}}<Chip
                @tone='primary'
                @appearance='soft'
                @shape='pill'
                @dot={{false}}
              >{{this.v.workflowLabel}}</Chip>{{/if}}
          </span>
        </header>
        <div class='iso-stats'>
          <Panel><Stat
              @label='Severity'
              @value={{if this.v.severityLabel this.v.severityLabel '—'}}
              @roll={{false}}
            /></Panel>
          <Panel><Stat
              @label='Open for'
              @value={{this.daysText}}
              @roll={{false}}
            /></Panel>
          <Panel><Stat
              @label='External refs'
              @value={{this.v.refsCount}}
              @hint={{this.v.refNames}}
              @roll={{false}}
            /></Panel>
        </div>
        <div class='iso-grid'>
          <div class='iso-col'>
            {{#if @model.problemStatement}}
              <Panel @title='Problem statement'>
                <p class='iso-text'>{{@model.problemStatement}}</p>
              </Panel>
            {{/if}}
            <Panel @title='Ownership'>
              <KeyValue @items={{this.v.ownership}} @rows='ruled' />
            </Panel>
            {{#if this.v.externalRefs.length}}
              <Panel @title='External references'>
                <KeyValue @items={{this.v.externalRefs}} @rows='ruled' />
              </Panel>
            {{/if}}
          </div>
          <div class='iso-col'>
            <Panel @title='Linked'>
              <div class='iso-links'>
                {{#if this.v.ownerName}}<span class='iso-link'><span
                      class='iso-link-k'
                    >Owner</span><span class='iso-link-v'><Avatar
                        @name={{this.v.ownerName}}
                        @size={{24}}
                        aria-hidden='true'
                      />{{this.v.ownerName}}</span></span>{{/if}}
                {{#if this.v.duplicate}}<span class='iso-link'><span
                      class='iso-link-k'
                    >Duplicate of</span><span class='iso-link-v'><span
                        class='iso-mark iso-mark-sm'
                        aria-hidden='true'
                      >Cs</span>{{this.v.duplicate.targetTitle}}</span></span>{{/if}}
              </div>
            </Panel>
            <Panel @title='Details'>
              <KeyValue @items={{this.v.facts}} @rows='ruled' />
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
          .iso-links {
            display: grid;
            gap: var(--boxel-sp-xs);
          }
          .iso-link {
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: var(--boxel-sp-xs);
            padding-bottom: var(--boxel-sp-xs);
            border-bottom: 1px solid var(--border);
          }
          .iso-link-k {
            color: var(--muted-foreground);
          }
          .iso-link-v {
            display: inline-flex;
            align-items: center;
            gap: var(--boxel-sp-xs);
            font-weight: 600;
          }
          .iso-mark {
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
          .iso-mark-sm {
            inline-size: 1.5rem;
            block-size: 1.5rem;
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
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get severityLabel() {
      return sentence(this.args.model?.severity);
    }
    get severityTone() {
      return SEVERITY_TONES[this.args.model?.severity ?? 'low'] ?? 'neutral';
    }
    get statusLabel() {
      return CASE_STATUS_LABELS[this.args.model?.status ?? 'open'] ?? 'Open';
    }
    get statusTone() {
      return STATUS_TONES[this.args.model?.status ?? 'open'] ?? 'neutral';
    }
    // The workflow chip is dropped when it only repeats the status chip
    // ("Resolved" twice); otherwise it adds the working position.
    get workflowLabel() {
      let label = this.args.model?.workflowState?.label;
      return label && label.toLowerCase() !== this.statusLabel.toLowerCase()
        ? label
        : undefined;
    }
    get caseId() {
      return this.args.model?.caseId?.value;
    }
    get team() {
      return this.args.model?.ownership?.teamName;
    }
    get subline() {
      let opened = shortDate(this.args.model?.openedOn);
      return [this.caseId, this.team, opened ? `opened ${opened}` : undefined]
        .filter(Boolean)
        .join(' · ');
    }
    get ownerName() {
      return this.args.model?.ownership?.ownerName ?? '';
    }
    get ownerLine() {
      let o = this.args.model?.ownership;
      if (!o?.ownerName) return undefined;
      let line = `Owner ${o.ownerName}`;
      if (o.previousOwnerName) {
        line += ` · took over from ${o.previousOwnerName}`;
        if (o.how) line += ` by ${o.how}`;
      }
      return line;
    }
    get duplicate() {
      return this.args.model?.relationships?.relations?.find(
        (r) => r.kind === 'duplicate-of',
      );
    }
    get facts(): KeyValueItem[] {
      let m = this.args.model;
      let items: KeyValueItem[] = [
        { key: 'Case ID', value: this.caseId ?? '—' },
        { key: 'Severity', value: this.severityLabel || '—' },
        { key: 'Status', value: this.statusLabel },
        { key: 'Workflow', value: this.workflowLabel ?? '—' },
        { key: 'Opened', value: shortDate(m?.openedOn, true) ?? '—' },
        { key: 'Team', value: this.team ?? '—' },
      ];
      for (let ref of m?.externalRefs ?? []) {
        items.push({
          key: ref.system?.name ?? 'Link',
          value: [ref.externalId, ref.state].filter(Boolean).join(' · '),
        });
      }
      return items;
    }
    get stats(): FittedStat[] {
      let m = this.args.model;
      let stats: FittedStat[] = [
        { key: 'Severity', value: this.severityLabel || '—' },
      ];
      if (m?.openedOn) {
        let end = m.resolvedOn ? new Date(m.resolvedOn) : new Date();
        let days = Math.max(
          0,
          Math.round((end.getTime() - new Date(m.openedOn).getTime()) / DAY_MS),
        );
        stats.push({ key: 'Open for', value: `${days} days` });
      }
      return stats;
    }
    get relations() {
      return [
        ...(this.ownerName ? ['Owner'] : []),
        ...(this.duplicate ? ['Duplicate of'] : []),
      ];
    }

    <template>
      <FittedExtras
        @facts={{this.facts}}
        @stats={{this.stats}}
        @relations={{this.relations}}
      >
        <:default>
          <FitTile>
            <:avatar>
              {{! the record's type mark, not a person: a square, not an Avatar }}
              <span class='fit-mark' aria-hidden='true'>Cs</span>
            </:avatar>
            <:title><span
                class='fit-title'
                role='heading'
                aria-level='3'
              >{{@model.subject}}</span></:title>
            <:subtitle>{{this.subline}}</:subtitle>
            <:status>
              {{#if this.severityLabel}}<Chip
                  @tone={{this.severityTone}}
                  @appearance='soft'
                  @shape='pill'
                  @dot={{false}}
                >{{this.severityLabel}}</Chip>{{/if}}
              <Chip
                @tone={{this.statusTone}}
                @appearance='soft'
                @shape='pill'
                @dot={{false}}
              >{{this.statusLabel}}</Chip>
              {{#if this.workflowLabel}}<Chip
                  @tone='primary'
                  @appearance='soft'
                  @shape='pill'
                  @dot={{false}}
                >{{this.workflowLabel}}</Chip>{{/if}}
            </:status>
            <:fact>{{this.ownerLine}}</:fact>
          </FitTile>
        </:default>
        <:relation as |label|>
          {{#if (eq label 'Owner')}}
            <span class='fit-rel'>
              <Avatar
                @name={{this.ownerName}}
                @size={{24}}
                aria-hidden='true'
              />
              {{this.ownerName}}
            </span>
          {{else}}
            <span class='fit-rel'>
              <span class='fit-mark fit-mark-sm' aria-hidden='true'>Cs</span>
              {{this.duplicate.targetTitle}}
            </span>
          {{/if}}
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
          .fit-mark {
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
          .fit-mark-sm {
            inline-size: 1.5rem;
            block-size: 1.5rem;
          }
          .fit-rel {
            display: inline-flex;
            align-items: center;
            gap: var(--boxel-sp-xs);
            font-weight: 600;
          }
        }
      </style>
    </template>
  };
}
