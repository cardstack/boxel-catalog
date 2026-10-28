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
import { Chip } from '../../ui-component/components/chip';
import {
  Descriptions,
  type DescriptionsItem,
} from '../../ui-component/components/descriptions';
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

export function statusTone(status?: string | null): PretuiToneArg {
  return (status && REQUISITION_STATUS_TONES[status]) || 'neutral';
}

export function statusLabel(status?: string | null): string {
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
            background: var(--canvas);
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
    get facts(): DescriptionsItem[] {
      return requisitionFacts(this.args.model);
    }
    get approvalText(): string {
      return approvalChip(this.args.model);
    }

    <template>
      <article class='fit'>
        <header class='who'>
          {{! the record's type mark, not a person: a square, not an Avatar }}
          <span class='mark' aria-hidden='true'>Rq</span>
          <div class='id'>
            <div class='line1'>
              <h3 class='title'>{{@model.displayTitle}}</h3>
              <span class='chips chips-inline'>
                {{#if @model.status}}<Chip
                    @tone={{statusTone @model.status}}
                    @appearance='soft'
                    @shape='pill'
                    @dot={{false}}
                  >{{statusLabel @model.status}}</Chip>{{/if}}
                {{#if this.approvalText}}<Chip
                    class='chip-approval'
                    @tone={{approvalTone @model}}
                    @appearance='soft'
                    @shape='pill'
                    @dot={{false}}
                  >{{this.approvalText}}</Chip>{{/if}}
              </span>
            </div>
            <p class='sub'>{{subLine @model}}</p>
          </div>
        </header>
        <div class='chips chips-row'>
          {{#if @model.status}}<Chip
              @tone={{statusTone @model.status}}
              @appearance='soft'
              @shape='pill'
              @dot={{false}}
            >{{statusLabel @model.status}}</Chip>{{/if}}
          {{#if this.approvalText}}<Chip
              class='chip-approval'
              @tone={{approvalTone @model}}
              @appearance='soft'
              @shape='pill'
              @dot={{false}}
            >{{this.approvalText}}</Chip>{{/if}}
        </div>
        {{#if this.targetFill}}
          <p class='fact'>Target fill
            <strong>{{this.targetFill}}</strong>{{#if (openedShort @model)}}
              · opened
              {{openedShort @model}}{{/if}}</p>
        {{/if}}
        <dl class='kv'>
          {{#each this.facts as |f|}}
            <div class='kv-i'><dt>{{f.label}}</dt><dd>{{f.value}}</dd></div>
          {{/each}}
        </dl>
        {{#if @model.approvalChain.steps.length}}
          <ul class='rels'>
            {{#each @fields.approvalChain.steps as |Step|}}
              <li><span class='k'>Approver</span><Step.approver
                  @format='atom'
                  @displayContainer={{false}}
                /></li>
            {{/each}}
          </ul>
        {{/if}}
      </article>
      <style scoped>
        @layer PretComponent {
          /* off-ladder gaps from the IMS rule (8 / 4 / 2); type reads the
             ladder, set here so a host's font-size never leaks in */
          .fit {
            --_fit-gap: 0.5rem;
            --_fit-gap-tight: 0.25rem;
            --_fit-hair: 0.125rem;

            display: flex;
            flex-direction: column;
            gap: var(--_fit-gap);
            block-size: 100%;
            box-sizing: border-box;
            padding: var(--boxel-sp-sm);
            overflow: hidden;
            font-size: var(--boxel-font-size-sm);
            line-height: 1.5;
          }
          .fit > * {
            flex: none;
            min-inline-size: 0;
            margin: 0;
          }
          .who {
            display: flex;
            align-items: flex-start;
            gap: var(--boxel-sp-sm);
            min-inline-size: 0;
          }
          .mark {
            display: none;
            flex: none;
            place-items: center;
            inline-size: 2rem;
            block-size: 2rem;
            border-radius: var(--radius);
            background: var(--card);
            box-shadow: inset 0 0 0 1px var(--border);
            color: var(--primary-ink);
            font-size: var(--boxel-font-size-xs);
            font-weight: 600;
          }
          .id {
            display: flex;
            flex: 1 1 auto;
            flex-direction: column;
            gap: var(--_fit-hair);
            min-inline-size: 0;
          }
          .line1 {
            display: flex;
            align-items: center;
            gap: var(--_fit-gap);
            min-inline-size: 0;
          }
          .title {
            flex: 1 1 auto;
            min-inline-size: 7rem;
            margin: 0;
            font-size: var(--boxel-font-size-sm);
            font-weight: 600;
            line-height: 1.5;
          }
          .title,
          .sub,
          .fact,
          .kv dd {
            overflow: hidden;
            white-space: nowrap;
            text-overflow: ellipsis;
          }
          .sub {
            margin: 0;
          }
          .sub,
          .fact,
          .kv,
          .rels {
            font-size: var(--boxel-font-size-xs);
          }
          .sub,
          .fact,
          .k,
          .kv dt {
            color: var(--muted-foreground);
          }
          .fact strong {
            font-weight: 600;
            color: var(--foreground);
          }
          .chips {
            display: flex;
            gap: var(--_fit-gap-tight);
            min-inline-size: 0;
            overflow: hidden;
          }
          .chips-inline,
          .chip-approval,
          .kv,
          .rels .k {
            display: none;
          }
          .chips-inline {
            flex: 0 1 auto;
          }
          /* as many rows as fit the space left; rows past the bottom get
             zero height, so none shows half */
          .kv {
            flex: 1 1 0;
            grid-template-columns: minmax(0, 1fr);
            grid-template-rows: repeat(auto-fill, 1.125rem);
            grid-auto-rows: 0;
            gap: var(--_fit-gap-tight) var(--boxel-sp-sm);
            min-block-size: 0;
            overflow: hidden;
          }
          .kv-i {
            display: flex;
            justify-content: space-between;
            gap: var(--_fit-gap);
            min-inline-size: 0;
            overflow: hidden;
          }
          .kv dt {
            flex: none;
          }
          .kv dd {
            margin: 0;
            font-weight: 600;
            text-align: end;
            font-variant-numeric: tabular-nums;
          }
          .rels {
            display: flex;
            flex-direction: column;
            gap: var(--_fit-gap-tight);
            margin: 0;
            padding: 0;
            list-style: none;
            overflow: hidden;
          }
          .rels li {
            display: flex;
            align-items: center;
            gap: var(--_fit-gap);
            min-inline-size: 0;
            overflow: hidden;
            line-height: 1.375rem;
          }
          .rels .k {
            flex: none;
          }

          /* ── per size: the container is the host's fitted-card ── */

          /* the type mark shows from 250 wide and 105 tall, and from 250 tall */
          @container fitted-card ((width >= 250px) and (height >= 105px)) or (height >= 250px) {
            .mark {
              display: grid;
            }
          }
          /* the approval chip joins the status from 250 wide */
          @container fitted-card (width >= 250px) {
            .chip-approval {
              display: inline-flex;
            }
          }
          /* relations name their link from 250 wide and 170 tall */
          @container fitted-card (width >= 250px) and (height >= 170px) {
            .rels .k {
              display: inline;
            }
          }
          @container fitted-card (width <= 150px) {
            .fact strong {
              font-weight: inherit;
              color: inherit;
            }
          }
          /* 400 wide: state moves beside the title */
          @container fitted-card (width >= 400px) {
            .chips-inline {
              display: flex;
            }
            .chips-row {
              display: none;
            }
          }
          /* under 170 tall: tight rows */
          @container fitted-card (height < 170px) {
            .fit {
              gap: var(--_fit-gap-tight);
              padding: var(--_fit-gap) var(--boxel-sp-sm);
            }
          }
          /* 105 – 169 tall, under 400 wide: no relations line */
          @container fitted-card (height < 170px) and (width < 400px) {
            .rels {
              display: none;
            }
          }
          /* 105 – 169 tall, 400 wide: the relations are one line of atoms */
          @container fitted-card (height < 170px) and (width >= 400px) {
            .rels {
              flex-flow: row wrap;
              max-block-size: 1.375rem;
            }
          }
          /* under 105 tall: who only, state beside the title from 250 wide */
          @container fitted-card (height < 105px) {
            .chips-row,
            .fact,
            .rels {
              display: none;
            }
          }
          @container fitted-card (height < 105px) and (width >= 250px) {
            .chips-inline {
              display: flex;
            }
          }
          /* 250 wide under 65 tall: status only beside the title */
          @container fitted-card (height < 65px) {
            .sub,
            .chip-approval {
              display: none;
            }
          }
          @container fitted-card (height < 65px) and (width < 250px) {
            .chips-inline {
              display: none;
            }
          }
          /* 250 tall: roomier padding and a larger mark; under 250 wide the
             mark stacks above the name */
          @container fitted-card (height >= 250px) {
            .fit {
              padding: var(--boxel-sp);
            }
            .mark {
              inline-size: 2.5rem;
              block-size: 2.5rem;
              font-size: var(--boxel-font-size-sm);
            }
          }
          @container fitted-card (height >= 250px) and (width < 250px) {
            .who {
              flex-direction: column;
              gap: var(--_fit-gap);
            }
            .id {
              align-self: stretch;
            }
          }
          /* 275 tall: the remaining facts fill the space left */
          @container fitted-card (height >= 275px) {
            .kv {
              display: grid;
            }
          }
          @container fitted-card (height >= 275px) and (height < 400px) and (width >= 400px) {
            .kv {
              grid-template-columns: repeat(2, minmax(0, 1fr));
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
          <Chip
            @tone={{statusTone @model.status}}
            @appearance='soft'
            @shape='pill'
            @dot={{false}}
          >{{statusLabel @model.status}}</Chip>
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
