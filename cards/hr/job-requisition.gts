import {
  CardDef,
  Component,
  field,
  contains,
  linksToMany,
  StringField,
  type BaseDefComponent,
} from '@cardstack/base/card-api';
import { RichFittedCard, Detail, Metric } from '../shared/rich-fitted-card';
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

import { Avatar } from '@cardstack/pretui/components/avatar';
import { type DescriptionsItem } from '@cardstack/pretui/components/descriptions';
import type { PretuiToneArg } from '@cardstack/pretui/pretui-primitives';
import { formatDay } from '@cardstack/catalog/fields/effective-period/effective-period-field';
import {
  EmbCard,
  IsoHead,
  IsoPage,
  Kv,
  kv,
  Panel,
  SheetLine,
  StatStrip,
  type StripItem,
} from '../shared/compact-sheet';

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

function approvalLabel(m?: Partial<JobRequisition>): string {
  let c = approvalCounts(m);
  return c.total ? `${c.approved} of ${c.total} approved` : 'no approvers';
}

// "Oct 1": a short month-day for a fitted stat.
function openedShortDate(d: Date): string {
  return new Date(d).toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
  });
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

    get strip(): StripItem[] {
      let m = this.args.model;
      return [
        {
          label: 'Headcount',
          value: m?.headcount == null ? '—' : String(m.headcount),
          hint: m?.department,
          tone: 'info',
        },
        { label: 'Salary range', value: this.salaryRange, hint: 'base' },
        {
          label: 'Target fill',
          value: this.targetFill,
          hint: this.openedHint,
          tone: 'success',
        },
      ];
    }

    <template>
      <IsoPage>
        <:head>
          <IsoHead @title={{@model.displayTitle}} @meta={{subLine @model}}>
            <:mark><Avatar
                @name='Rq'
                @hue='var(--muted)'
                @shape='rounded'
                @size={{36}}
                aria-hidden='true'
              /></:mark>
            <:aside>{{#if @model.status}}<@fields.status
                  @format='atom'
                  @displayContainer={{false}}
                />{{/if}}</:aside>
            <:stats><StatStrip @items={{this.strip}} /></:stats>
          </IsoHead>
        </:head>
        <:main>
          {{#if @model.description}}
            <Panel @title='Description'><SheetLine><span
                  class='prose'
                >{{@model.description}}</span></SheetLine></Panel>
          {{/if}}
          <Panel @title='Approval chain'><@fields.approvalChain
              @format='embedded'
            /></Panel>
        </:main>
        <:aside>
          <Panel @title='Linked'>
            {{#each @fields.approvalChain.steps as |Step|}}
              <SheetLine><span class='k'>Approver</span><Step.approver
                  @format='atom'
                  @displayContainer={{false}}
                /></SheetLine>
            {{/each}}
            {{#each @fields.positions as |PositionAtom|}}
              <SheetLine><span class='k'>Position</span><PositionAtom
                  @format='atom'
                  @displayContainer={{false}}
                /></SheetLine>
            {{/each}}
          </Panel>
          <Panel @title='Details'><Kv @items={{kv this.details}} /></Panel>
        </:aside>
      </IsoPage>
      <style scoped>
        .prose {
          white-space: pre-line;
        }
        .k {
          inline-size: 7.5rem;
          font-weight: 600;
          font-size: 0.5625rem; /* 9px ladder label: no token */
          line-height: 1.3;
          font-family: var(--font-mono);
          letter-spacing: 0.13em;
          text-transform: uppercase;
          color: var(--subtle-foreground);
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

    get rows() {
      return kv(requisitionFacts(this.args.model));
    }

    <template>
      <EmbCard @title={{@model.displayTitle}} @meta={{subLine @model}}>
        <:mark><Avatar
            @name='Rq'
            @hue='var(--muted)'
            @shape='rounded'
            @size={{24}}
            aria-hidden='true'
          /></:mark>
        <:aside>{{#if @model.status}}<@fields.status
              @format='atom'
              @displayContainer={{false}}
            />{{/if}}</:aside>
        <:default>
          <Kv @items={{this.rows}} />
          {{#each @fields.approvalChain.steps as |Step|}}
            <SheetLine><span class='k'>Approver</span><Step.approver
                @format='atom'
                @displayContainer={{false}}
              /></SheetLine>
          {{/each}}
        </:default>
      </EmbCard>
      <style scoped>
        .k {
          inline-size: 7.5rem;
          font-weight: 600;
          font-size: 0.5625rem; /* 9px ladder label: no token */
          line-height: 1.3;
          font-family: var(--font-mono);
          letter-spacing: 0.13em;
          text-transform: uppercase;
          color: var(--subtle-foreground);
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

    get strip(): StripItem[] {
      let m = this.args.model;
      return [
        {
          label: 'Headcount',
          value: m?.headcount == null ? '—' : String(m.headcount),
        },
        {
          label: 'From',
          value:
            m?.salaryRangeMin == null
              ? '—'
              : '$' + Math.round(m.salaryRangeMin / 1000) + 'k',
        },
        {
          label: 'Target',
          value: m?.targetFillDate ? openedShortDate(m.targetFillDate) : '—',
        },
      ];
    }

    <template>
      <RichFittedCard>
        <:avatar><Avatar
            @name='Rq'
            @hue='var(--muted)'
            @shape='rounded'
            aria-hidden='true'
          /></:avatar>
        <:title>{{@model.displayTitle}}</:title>
        <:status>{{#if @model.status}}<@fields.status
              @format='atom'
              @displayContainer={{false}}
            />{{/if}}</:status>
        <:subtitle><span class='meta'>{{subLine @model}}</span></:subtitle>
        <:metric>{{#let (get this.strip 0) as |s|}}{{#if s}}<Metric
                @value={{s.value}}
                @label={{s.label}}
              />{{/if}}{{/let}}</:metric>
        <:details>

          <Detail @label='Target fill'><span class='mono'>{{if
                this.targetFill
                this.targetFill
                '—'
              }}</span></Detail>
          <Detail @label='Salary'><span class='mono'>{{salaryRangeLabel
                @model.salaryRangeMin
                @model.salaryRangeMax
              }}</span></Detail>
          <Detail @label='Approval'>{{if
              this.approvalText
              this.approvalText
              '—'
            }}</Detail>

          {{#each @fields.approvalChain.steps as |Step|}}
            <Detail @label='Approver'><Step.approver
                @format='atom'
                @displayContainer={{false}}
              /></Detail>
          {{/each}}
          <Detail @label='Created'><span class='mono'>{{if
                @model.createdDate
                (formatDay @model.createdDate)
                '—'
              }}</span></Detail>
          <Detail @label='Department'>{{if
              @model.department
              @model.department
              '—'
            }}</Detail>
        </:details>
      </RichFittedCard>
      <style scoped>
        .meta {
          overflow: hidden;
          text-overflow: ellipsis;
          font-size: var(--boxel-font-size-2xs);
          color: var(--muted-foreground);
        }
        .mono {
          overflow: hidden;
          text-overflow: ellipsis;
          font-weight: 500;
          font-size: var(--boxel-font-size-2xs);
          font-family: var(--font-mono);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static atom: BaseDefComponent = class Atom extends Component<typeof this> {
    <template>
      <span class='requisition-atom'>
        <span class='name'>{{@model.displayTitle}}</span>
      </span>
      <style scoped>
        @layer PretComponent {
          .requisition-atom {
            display: inline-flex;
            align-items: center;
            gap: var(--boxel-sp-2xs);
            max-width: 100%;
            vertical-align: middle;
            font-size: var(--boxel-font-size-xs);
            font-weight: 600;
            block-size: 1.375rem;
            line-height: 1;
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
