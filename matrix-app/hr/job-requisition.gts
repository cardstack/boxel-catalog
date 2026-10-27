import {
  CardDef,
  Component,
  field,
  contains,
  linksToMany,
  StringField,
  type BaseDefComponent,
} from '@cardstack/base/card-api';
import DateField from '@cardstack/base/date';
import NumberField from '@cardstack/base/number';
import TextAreaField from '@cardstack/base/text-area';
import BriefcaseBusinessIcon from '@cardstack/boxel-icons/briefcase-business';

import { Position } from './position';
import { ApprovalChainField } from './approval-chain-field';
import {
  RequisitionStatusField,
  REQUISITION_STATUS_LABELS,
} from './requisition-field';
import { formatMoney, liveCount } from './utils';

import { Avatar } from '../../ui-component/components/avatar';
import {
  Descriptions,
  type DescriptionsItem,
} from '../../ui-component/components/descriptions';
import { FitTile } from '../../ui-component/components/fit-tile';
import {
  KeyValue,
  type KeyValueItem,
} from '../../ui-component/components/key-value';
import { Panel } from '../../ui-component/components/panel';
import { Stat } from '../../ui-component/components/stat';
import { StatusChip } from '../../ui-component/components/status-chip';
import type { PretuiToneArg } from '../../ui-component/pretui-primitives';
import { formatDay } from '@cardstack/catalog/fields/effective-period/effective-period-field';
import { QUIET_AVATAR_HUE } from './hr-ui';

// Helper to format salary range display
function salaryRangeLabel(
  min?: number | null,
  max?: number | null,
  opts?: { compact?: boolean },
): string | undefined {
  if (min == null && max == null) {
    return undefined;
  }
  let fmt = (n: number) => formatMoney(n, opts)!;
  if (min != null && max != null) {
    return `${fmt(min)} – ${fmt(max)}`;
  }
  return fmt(min ?? max!);
}

// The status chip's tone: a live or filled req is success, approved is info,
// a closed one danger and a draft neutral.
const REQUISITION_STATUS_TONES: Record<string, PretuiToneArg> = {
  draft: 'neutral',
  approved: 'info',
  posted: 'success',
  filled: 'success',
  closed: 'danger',
};

function statusTone(status?: string | null): PretuiToneArg {
  return (status && REQUISITION_STATUS_TONES[status]) || 'neutral';
}

function statusLabel(status?: string | null): string {
  return (status && REQUISITION_STATUS_LABELS[status]) || status || '';
}

function subLine(m?: Partial<JobRequisition>): string {
  let parts = [
    m?.department,
    m?.headcount != null ? `${m.headcount} headcount` : undefined,
  ].filter(Boolean);
  return parts.length ? parts.join(' · ') : 'Department not set';
}

function approvalCounts(m?: Partial<JobRequisition>) {
  let steps = (m?.approvalChain?.steps ?? []).filter(Boolean);
  return {
    total: steps.length,
    approved: steps.filter((s) => s.decision === 'approved').length,
    rejected: steps.some((s) => s.decision === 'rejected'),
  };
}

// "approved 2 / 2" beside the status, toned by how far the chain has got.
// '' when there is no chain: a template `#if` reads it as false
function approvalChip(m?: Partial<JobRequisition>): string {
  let c = approvalCounts(m);
  if (!c.total) {
    return '';
  }
  return c.rejected ? 'rejected' : `approved ${c.approved} / ${c.total}`;
}

function approvalTone(m?: Partial<JobRequisition>): PretuiToneArg {
  let c = approvalCounts(m);
  if (c.rejected) {
    return 'danger';
  }
  return c.approved === c.total ? 'success' : 'warning';
}

function approvalLabel(m?: Partial<JobRequisition>): string {
  let c = approvalCounts(m);
  return c.total ? `${c.approved} of ${c.total} approved` : 'no approvers';
}

function openedShort(m?: Partial<JobRequisition>): string | undefined {
  return m?.createdDate ? formatDay(m.createdDate) : undefined;
}

// The facts every format draws from, in the mockup's order; isolated shows
// them all, embedded the first six. Positions reads the denormalized tally,
// so a prerendered fitted view counts them too.
function requisitionFacts(m?: Partial<JobRequisition>): DescriptionsItem[] {
  return [
    {
      label: 'Salary range',
      value:
        salaryRangeLabel(m?.salaryRangeMin, m?.salaryRangeMax, {
          compact: true,
        }) ?? '—',
    },
    {
      label: 'Headcount',
      value: m?.headcount != null ? String(m.headcount) : '—',
    },
    {
      label: 'Target fill',
      value: m?.targetFillDate ? formatDay(m.targetFillDate) : '—',
    },
    {
      label: 'Created',
      value: m?.createdDate ? formatDay(m.createdDate) : '—',
    },
    { label: 'Approval', value: approvalLabel(m) },
    { label: 'Department', value: m?.department || '—' },
    {
      label: 'Positions',
      value: m?.positionTally ? m.positionTally : 'none linked',
    },
  ];
}

// Job requisition — a request to hire one or more people for a role.
// Tracks approval chain, status, and target fill date. Positions created from
// this requisition are linked as read-only backlinks (denormalized in fitted).
export class JobRequisition extends CardDef {
  static displayName = 'Job Requisition';
  static icon = BriefcaseBusinessIcon;

  @field title = contains(StringField, {
    description: 'Job title (e.g., "Senior Backend Engineer")',
  });
  @field department = contains(StringField);
  @field description = contains(TextAreaField);
  @field headcount = contains(NumberField, {
    description: 'Number of roles to fill',
  });
  @field salaryRangeMin = contains(NumberField, {
    description: 'Minimum salary in dollars',
  });
  @field salaryRangeMax = contains(NumberField, {
    description: 'Maximum salary in dollars',
  });
  @field approvalChain = contains(ApprovalChainField);
  @field status = contains(RequisitionStatusField);
  @field targetFillDate = contains(DateField);
  @field createdDate = contains(DateField);
  @field filledDate = contains(DateField);
  @field positions = linksToMany(() => Position);

  @field displayTitle = contains(StringField, {
    computeVia: function (this: JobRequisition) {
      return this.title?.trim() || 'Unnamed Requisition';
    },
  });

  // Denormalized for fitted — prerendered fitted does not resolve
  // linksToMany, so the fitted view reads this instead of positions.length.
  @field positionTally = contains(StringField, {
    computeVia: function (this: JobRequisition) {
      let n = liveCount(this.positions);
      return n === 0 ? '' : String(n);
    },
  });

  static isolated: BaseDefComponent = class Isolated extends Component<
    typeof this
  > {
    get salaryRange(): string {
      return (
        salaryRangeLabel(
          this.args.model?.salaryRangeMin,
          this.args.model?.salaryRangeMax,
          { compact: true },
        ) ?? '—'
      );
    }

    get targetFill(): string {
      let d = this.args.model?.targetFillDate;
      return d ? formatDay(d) : '—';
    }

    get openedHint(): string | undefined {
      let opened = openedShort(this.args.model);
      return opened ? `opened ${opened}` : undefined;
    }

    get details(): DescriptionsItem[] {
      return requisitionFacts(this.args.model);
    }

    <template>
      <article class='requisition-isolated'>
        <header class='iso-head'>
          <Avatar
            @name={{if @model.displayTitle @model.displayTitle '?'}}
            @hue={{QUIET_AVATAR_HUE}}
            @size={{48}}
            aria-hidden='true'
          />
          <div class='iso-id'>
            <h1>{{@model.displayTitle}}</h1>
            <p class='iso-sub'>{{subLine @model}}</p>
          </div>
          <div class='chips'>
            {{#if @model.status}}
              <StatusChip
                @value={{statusLabel @model.status}}
                @tone={{statusTone @model.status}}
              />
            {{/if}}
            {{#if (approvalChip @model)}}
              <StatusChip
                @value={{approvalChip @model}}
                @tone={{approvalTone @model}}
              />
            {{/if}}
          </div>
        </header>

        <div class='stat-row'>
          <div class='stat-tile'><Stat
              @label='Headcount'
              @value={{if @model.headcount @model.headcount '—'}}
              @hint={{@model.department}}
              @roll={{false}}
            /></div>
          <div class='stat-tile'><Stat
              @label='Salary range'
              @value={{this.salaryRange}}
              @hint='base'
              @roll={{false}}
            /></div>
          <div class='stat-tile'><Stat
              @label='Target fill'
              @value={{this.targetFill}}
              @hint={{this.openedHint}}
              @roll={{false}}
            /></div>
        </div>

        <div class='iso-body'>
          <div class='iso-col'>
            {{#if @model.description}}
              <Panel>
                <:header><h2 class='panel-h'>Description</h2></:header>
                <:default><p class='text'>{{@model.description}}</p></:default>
              </Panel>
            {{/if}}
            <Panel>
              <:header><h2 class='panel-h'>Approval chain</h2></:header>
              <:default>
                <@fields.approvalChain @format='embedded' />
              </:default>
            </Panel>
          </div>

          <div class='iso-col'>
            <Panel>
              <:header><h2 class='panel-h'>Linked</h2></:header>
              <:default>
                <ul class='linked'>
                  {{#each @fields.approvalChain.steps as |Step|}}
                    <li class='rel'><span
                        class='k'
                      >Approver</span><Step.approver
                        @format='atom'
                        @displayContainer={{false}}
                      /></li>
                  {{/each}}
                  {{#each @fields.positions as |PositionAtom|}}
                    <li class='rel'><span class='k'>Position</span><PositionAtom
                        @format='atom'
                        @displayContainer={{false}}
                      /></li>
                  {{/each}}
                </ul>
              </:default>
            </Panel>
            <Panel>
              <:header><h2 class='panel-h'>Details</h2></:header>
              <:default>
                <Descriptions @items={{this.details}} @columns={{1}} @size='xl'>
                  <:value as |item|><span
                      class='v'
                    >{{item.value}}</span></:value>
                </Descriptions>
              </:default>
            </Panel>
          </div>
        </div>
      </article>
      <style scoped>
        @layer PretComponent {
          .requisition-isolated {
            container: requisition-iso / inline-size;
            display: flex;
            flex-direction: column;
            gap: var(--boxel-sp-lg);
            box-sizing: border-box;
            height: 100%;
            overflow-y: auto;
            padding: var(--boxel-sp-lg);
          }
          .iso-head {
            display: flex;
            flex-wrap: wrap;
            align-items: center;
            gap: var(--boxel-sp);
          }
          .iso-id {
            flex: 1 1 12rem;
            min-width: 0;
          }
          h1 {
            margin: 0;
            font-size: var(--boxel-font-size-lg);
            font-weight: 600;
            line-height: 1.25;
            color: var(--primary-ink);
            overflow-wrap: anywhere;
          }
          .iso-sub {
            margin: var(--boxel-sp-6xs) 0 0;
            font-size: var(--boxel-font-size-sm);
            color: var(--muted-foreground);
          }
          .chips {
            display: flex;
            flex-wrap: wrap;
            gap: var(--boxel-sp-4xs);
          }
          .stat-row {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(10.5rem, 1fr));
            gap: var(--boxel-sp);
          }
          .stat-tile {
            padding: var(--boxel-sp);
            border-radius: var(--boxel-border-radius);
            background-color: var(--card);
            color: var(--primary-ink);
            box-shadow: var(--shadow-md);
          }
          .iso-body {
            display: grid;
            grid-template-columns: minmax(0, 2fr) minmax(15rem, 1fr);
            align-items: start;
            gap: var(--boxel-sp-lg);
          }
          .iso-col {
            display: flex;
            flex-direction: column;
            gap: var(--boxel-sp-lg);
            min-width: 0;
          }
          .panel-h {
            margin: 0;
            font-size: var(--boxel-font-size);
            font-weight: 600;
            line-height: 1.25;
          }
          .text {
            margin: 0;
            font-size: var(--boxel-font-size-sm);
            line-height: 1.5;
          }
          .linked {
            display: flex;
            flex-direction: column;
            gap: var(--boxel-sp-xs);
            margin: 0;
            padding: 0;
            list-style: none;
          }
          .rel {
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: var(--boxel-sp-sm);
            min-width: 0;
            font-size: var(--boxel-font-size-sm);
          }
          .k {
            flex: none;
            color: var(--muted-foreground);
          }
          .v {
            font-weight: 600;
            font-variant-numeric: tabular-nums;
            overflow-wrap: anywhere;
          }
          @container requisition-iso (width < 45rem) {
            .iso-body {
              grid-template-columns: minmax(0, 1fr);
            }
          }
        }
      </style>
    </template>
  };

  static embedded: BaseDefComponent = class Embedded extends Component<
    typeof this
  > {
    get facts(): DescriptionsItem[] {
      return requisitionFacts(this.args.model).slice(0, 6);
    }

    get targetFill(): string | undefined {
      let d = this.args.model?.targetFillDate;
      return d ? formatDay(d) : undefined;
    }

    <template>
      <div class='requisition-embedded'>
        <article class='emb'>
          <header class='emb-head'>
            <Avatar
              @name={{if @model.displayTitle @model.displayTitle '?'}}
              @hue={{QUIET_AVATAR_HUE}}
              @size={{40}}
              aria-hidden='true'
            />
            <div class='emb-id'>
              <h3 class='emb-title'>{{@model.displayTitle}}</h3>
              <p class='emb-sub'>{{subLine @model}}</p>
            </div>
            <div class='chips'>
              {{#if @model.status}}
                <StatusChip
                  @value={{statusLabel @model.status}}
                  @tone={{statusTone @model.status}}
                />
              {{/if}}
              {{#if (approvalChip @model)}}
                <StatusChip
                  @value={{approvalChip @model}}
                  @tone={{approvalTone @model}}
                />
              {{/if}}
            </div>
          </header>
          {{#if this.targetFill}}
            <p class='emb-fact'>Target fill
              <strong>{{this.targetFill}}</strong>{{#if (openedShort @model)}}
                · opened
                {{openedShort @model}}{{/if}}</p>
          {{/if}}
          <Descriptions
            class='emb-kv'
            @items={{this.facts}}
            @layout='vertical'
            @columns={{3}}
          >
            <:value as |item|><span class='v'>{{item.value}}</span></:value>
          </Descriptions>
          {{#if @model.approvalChain.steps.length}}
            <p class='emb-rels'>
              {{#each @fields.approvalChain.steps as |Step|}}
                <span class='rel'>Approver
                  <Step.approver
                    @format='atom'
                    @displayContainer={{false}}
                  /></span>
              {{/each}}
            </p>
          {{/if}}
        </article>
      </div>
      <style scoped>
        @layer PretComponent {
          .requisition-embedded {
            container-type: inline-size;
          }
          .emb {
            display: flex;
            flex-direction: column;
            gap: var(--boxel-sp-sm);
            padding: var(--boxel-sp);
          }
          .emb-head {
            display: flex;
            align-items: center;
            gap: var(--boxel-sp-sm);
          }
          .emb-id {
            flex: 1 1 auto;
            min-width: 0;
          }
          .emb-title {
            margin: 0;
            font-size: var(--boxel-font-size-sm);
            font-weight: 600;
            line-height: 1.5;
          }
          .emb-sub {
            margin: var(--boxel-sp-6xs) 0 0;
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          .chips {
            display: flex;
            flex-wrap: wrap;
            justify-content: flex-end;
            gap: var(--boxel-sp-4xs);
          }
          .emb-fact {
            margin: 0;
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          .emb-fact strong {
            font-weight: 600;
            color: var(--foreground);
          }
          .emb-kv {
            padding-top: var(--boxel-sp-sm);
            border-top: 1px solid var(--border);
          }
          .v {
            font-weight: 600;
            font-variant-numeric: tabular-nums;
            overflow-wrap: anywhere;
          }
          .emb-rels {
            display: flex;
            flex-wrap: wrap;
            align-items: center;
            gap: var(--boxel-sp-xs) var(--boxel-sp);
            margin: 0;
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          .rel {
            display: inline-flex;
            align-items: center;
            gap: var(--boxel-sp-xs);
          }
          /* under 400 the chips move under the name */
          @container (width < 25rem) {
            .emb-head {
              flex-wrap: wrap;
            }
            .chips {
              flex-basis: 100%;
              justify-content: flex-start;
            }
          }
        }
      </style>
    </template>
  };

  static fitted: BaseDefComponent = class Fitted extends Component<
    typeof this
  > {
    get targetFill(): string | undefined {
      let d = this.args.model?.targetFillDate;
      return d ? formatDay(d) : undefined;
    }

    // Each fact is its own KeyValue row, so a row that doesn't fit wraps
    // out of sight whole instead of showing half.
    get factRows(): KeyValueItem[][] {
      return requisitionFacts(this.args.model).map((f) => [
        { key: f.label, value: f.value ?? '—' },
      ]);
    }

    <template>
      <div class='fit'>
        <FitTile class='tile'>
          <:avatar>
            <Avatar
              @name={{if @model.displayTitle @model.displayTitle '?'}}
              @hue={{QUIET_AVATAR_HUE}}
              @size={{32}}
              aria-hidden='true'
            />
          </:avatar>
          <:title><span
              role='heading'
              aria-level='3'
            >{{@model.displayTitle}}</span></:title>
          <:subtitle>{{subLine @model}}</:subtitle>
          {{! The req's own lifecycle status first, then the approval chain's. }}
          <:status>
            {{#if @model.status}}
              <StatusChip
                @value={{statusLabel @model.status}}
                @tone={{statusTone @model.status}}
              />
            {{/if}}
            {{#if (approvalChip @model)}}
              <StatusChip
                @value={{approvalChip @model}}
                @tone={{approvalTone @model}}
              />
            {{/if}}
          </:status>
          <:fact>{{#if this.targetFill}}Target fill
              <strong class='strong'>{{this.targetFill}}</strong>{{#if
                (openedShort @model)
              }}
                · opened
                {{openedShort @model}}{{/if}}{{/if}}</:fact>
        </FitTile>
        {{! Relations, then the key facts: shown from 170 tall, and the
            relation line on a 400-wide strip. }}
        <div class='more'>
          {{#each @fields.approvalChain.steps as |Step|}}
            <p class='rel'><span class='k'>Approver</span><Step.approver
                @format='atom'
              /></p>
          {{/each}}
          {{#each this.factRows as |row|}}
            <KeyValue class='kv' @items={{row}} />
          {{/each}}
        </div>
      </div>
      <style scoped>
        @layer PretComponent, PretComposite;
        /* FitTile sizes to its rows here, so the extra rows below it get the
           rest of the card */
        @layer PretComposite {
          .tile {
            flex: none;
            block-size: auto;
          }
        }
        @layer PretComponent {
          .fit {
            display: flex;
            flex-direction: column;
            block-size: 100%;
            overflow: hidden;
          }
          .strong {
            font-weight: 600;
            color: var(--foreground);
          }
          /* a column that wraps: a row past the bottom moves to a second
             column outside the card, whole */
          .more {
            display: none;
            flex: 1 1 0;
            flex-flow: column wrap;
            align-content: flex-start;
            row-gap: var(--boxel-sp-4xs);
            column-gap: var(--boxel-sp-sm);
            min-block-size: 0;
            padding: 0 var(--boxel-sp-sm);
            overflow: hidden;
            font-size: var(--boxel-font-size-xs);
            line-height: 1.5;
          }
          .rel,
          .kv {
            inline-size: 100%;
          }
          .rel {
            display: flex;
            align-items: center;
            gap: var(--boxel-sp-xs);
            min-inline-size: 0;
            margin: 0;
            overflow: hidden;
            white-space: nowrap;
          }
          .k {
            flex: none;
            color: var(--muted-foreground);
          }
          @container fitted-card (height >= 170px) {
            .more {
              display: flex;
            }
          }
          @container fitted-card (105px <= height < 170px) and (width >= 400px) {
            .more {
              display: flex;
            }
          }
        }
      </style>
    </template>
  };

  static atom: BaseDefComponent = class Atom extends Component<typeof this> {
    <template>
      <span class='requisition-atom'>
        <span class='name'>{{@model.displayTitle}}</span>
        {{#if @model.status}}
          <StatusChip
            @value={{statusLabel @model.status}}
            @tone={{statusTone @model.status}}
          />
        {{/if}}
      </span>
      <style scoped>
        @layer PretComponent {
          .requisition-atom {
            display: inline-flex;
            align-items: center;
            gap: var(--boxel-sp-4xs);
            max-width: 100%;
            vertical-align: middle;
            font-size: var(--boxel-font-size-xs);
            font-weight: 600;
            line-height: 1.5;
            white-space: nowrap;
            color: var(--foreground);
          }
          .name {
            overflow: hidden;
            text-overflow: ellipsis;
          }
        }
      </style>
    </template>
  };
}
