import {
  CardDef,
  Component,
  contains,
  containsMany,
  field,
  linksTo,
  StringField,
  realmURL,
} from '@cardstack/base/card-api';
import { identifyCard, type getCards } from '@cardstack/runtime-common';
import { tracked } from '@glimmer/tracking';
import type Owner from '@ember/owner';
import NumberField from '@cardstack/base/number';
import BooleanField from '@cardstack/base/boolean';
import DateField from '@cardstack/base/date';
import DateTimeField from '@cardstack/base/datetime';
import MarkdownField from '@cardstack/base/markdown';
import { FieldContainer, FittedCard } from '@cardstack/boxel-ui/components';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import WrenchIcon from '@cardstack/boxel-icons/wrench';
import ZapOffIcon from '@cardstack/boxel-icons/zap-off';
import ShieldCheckIcon from '@cardstack/boxel-icons/shield-check';
import FlagIcon from '@cardstack/boxel-icons/flag';

import { Asset } from './asset';
import { Location } from '../events/location';
import { MaintenancePlan } from './maintenance-plan';
import { RecordIdentifierField } from '@cardstack/catalog/fields/record-identifier/record-identifier-field';
import { RecordOwnerField } from '@cardstack/catalog/fields/record-owner/record-owner-field';
import { ChecklistField } from './checklist-field';
import { LabourEntryField } from './labour-entry-field';
import { PartUsageField } from './part-usage-field';
import { DowntimeField } from './downtime-field';
import { FailureReportField } from './failure-report-field';
import { InspectionFindingField } from '@cardstack/catalog/cards/audit/inspection-finding-field';
import { ApprovalChainField } from '@cardstack/catalog/cards/hr/approval-chain-field';
import {
  WorkOrderStatusField,
  WorkOrderPriorityField,
  WorkOrderKindField,
  HoldReasonField,
  WO_KIND_LABEL,
  WO_STATUS_HUE,
  WO_TERMINAL,
} from './maintenance-vocabulary';
import { SectionedEdit } from '@cardstack/catalog/components/sectioned-edit';
import { WorkOrderWorkbench } from './components/work-order-workbench';
import { SparePart } from './spare-part';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import CompleteWorkOrderCommand from './commands/complete-work-order-command';
import { sumCost, formatHours } from './utils/maintenance';
import { toDay, daysBetweenDays } from './utils/recurrence';
import { formatMoneyDisplay } from '@cardstack/catalog/components/money-display';
import type { Hue } from '@cardstack/catalog/components/state-pill';

class WorkOrderIsolated extends Component<typeof WorkOrder> {
  get workOrder() {
    return this.args.model as WorkOrder;
  }

  // Commands need the host; a card rendered without one cannot act.
  private get commandContext() {
    let context = this.args.context?.commandContext;
    if (!context) {
      throw new Error('This action needs a running host.');
    }
    return context;
  }

  @tracked workbenchError: string | undefined;

  partQuery: ReturnType<getCards> | undefined;

  constructor(owner: Owner, args: any) {
    super(owner, args);
    let realmHref = (this.args.model as any)?.[realmURL]?.href;
    this.partQuery = this.args.context?.getCards(
      this,
      () => {
        let ref = identifyCard(SparePart);
        return ref ? { filter: { type: ref } } : undefined;
      },
      () => (realmHref ? [realmHref] : undefined),
      { isLive: true },
    );
  }

  get parts(): SparePart[] {
    return ((this.partQuery?.instances ?? []) as SparePart[]).filter(Boolean);
  }

  // Same non-terminal moves the board's own drag allows (a direct, legal
  // write per WorkOrderStatusField's transition graph); Complete is gated
  // business logic and goes through the single-writer command instead.
  // These live on the card itself (not an app shell) so opening the Work
  // Order on its own — via viewCard from anywhere — is the full technician
  // workbench, not a read-only summary.
  startWorkOrder = async () => {
    let wo = this.args.model;
    this.workbenchError = undefined;
    wo.status = 'in-progress' as any;
    if (!wo.startedAt) {
      wo.startedAt = new Date();
    }
    await new SaveCardCommand(this.commandContext).execute({
      card: wo,
    } as any);
  };

  holdWorkOrder = async (reason: string) => {
    let wo = this.args.model;
    this.workbenchError = undefined;
    wo.status = 'on-hold' as any;
    wo.holdReason = reason as any;
    await new SaveCardCommand(this.commandContext).execute({
      card: wo,
    } as any);
  };

  resumeWorkOrder = async () => {
    let wo = this.args.model;
    this.workbenchError = undefined;
    wo.status = 'in-progress' as any;
    await new SaveCardCommand(this.commandContext).execute({
      card: wo,
    } as any);
  };

  completeWorkOrder = async () => {
    let wo = this.args.model;
    this.workbenchError = undefined;
    try {
      await new CompleteWorkOrderCommand(this.commandContext).execute({
        workOrder: wo,
      } as any);
    } catch (e: any) {
      this.workbenchError = e?.message ?? 'Could not complete this work order.';
    }
  };

  saveWorkOrder = async () => {
    await new SaveCardCommand(this.commandContext).execute({
      card: this.args.model,
    } as any);
  };

  get cost() {
    let m = this.args.model;
    let code =
      m.labour?.[0]?.rate?.currency?.code ??
      m.parts?.[0]?.unitCost?.currency?.code ??
      'USD';
    return {
      labour: formatMoneyDisplay(m.labourCost ?? 0, code),
      parts: formatMoneyDisplay(m.partsCost ?? 0, code),
      total: formatMoneyDisplay(m.totalCost ?? 0, code),
      hours: formatHours(m.labourHours ?? 0),
    };
  }
  get hasFindings() {
    return (this.args.model.findings?.length ?? 0) > 0;
  }
  get hasApproval() {
    return (this.args.model.approval?.steps?.length ?? 0) > 0;
  }
  <template>
    <article class='wo'>
      <div class='wo-meta'>
        <div class='meta-block'>
          <span class='meta-l'>Owner</span>
          <@fields.ownership @format='embedded' />
        </div>
        <div class='meta-block'>
          <span class='meta-l'>Cost so far</span>
          <span class='meta-big'>{{this.cost.total}}</span>
          <span class='meta-s'>{{this.cost.hours}}
            labour ·
            {{this.cost.labour}}
            · parts
            {{this.cost.parts}}</span>
        </div>
        {{#if @model.warrantyCovered}}
          <div class='banner'><ShieldCheckIcon class='ic' />
            Asset under warranty — claim, don't pay for parts.</div>
        {{/if}}
      </div>

      {{#if @model.description}}
        <section class='sec'><@fields.description /></section>
      {{/if}}

      <WorkOrderWorkbench
        @workOrder={{this.workOrder}}
        @asset={{@model.subjectAsset}}
        @parts={{this.parts}}
        @onStart={{this.startWorkOrder}}
        @onHold={{this.holdWorkOrder}}
        @onResume={{this.resumeWorkOrder}}
        @onComplete={{this.completeWorkOrder}}
        @onChange={{this.saveWorkOrder}}
        @errorMessage={{this.workbenchError}}
      />

      {{#if @model.failure.symptom}}
        <section class='sec'>
          <h2><ZapOffIcon class='ic' /> Failure</h2>
          <@fields.failure @format='embedded' />
        </section>
      {{/if}}

      {{#if this.hasFindings}}
        <section class='sec'>
          <h2><FlagIcon class='ic' /> Inspection findings</h2>
          <ul class='list'>{{#each @fields.findings as |F|}}<li><F
                  @format='embedded'
                /></li>{{/each}}</ul>
        </section>
      {{/if}}

      {{#if this.hasApproval}}
        <section class='sec'>
          <h2><ShieldCheckIcon class='ic' /> Approval</h2>
          <@fields.approval @format='embedded' />
        </section>
      {{/if}}
    </article>
    <style scoped>
      .wo {
        container-type: inline-size;
        display: grid;
        grid-template-columns: minmax(0, 1fr);
        gap: var(--boxel-sp-lg);
        padding: var(--boxel-sp-lg);
        color: var(--foreground);
        background: var(--background);
      }
      .head {
        display: grid;
        grid-template-columns: minmax(0, 1fr) 16rem;
        gap: var(--boxel-sp-lg);
        align-items: start;
      }
      .head-main {
        display: grid;
        gap: var(--boxel-sp-xs);
        min-width: 0;
      }
      .chips {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        flex-wrap: wrap;
      }
      .tag {
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-sm);
        font-weight: 600;
        padding: 2px 0.375rem;
        border: 1px solid var(--border);
        border-radius: 0.25rem;
        background: var(--card);
      }
      .kind {
        font-size: var(--boxel-font-size-xs);
        font-weight: 700;
        letter-spacing: 0.1em;
        color: var(--muted-foreground);
      }
      .title {
        margin: 0;
        font-size: 1.75rem;
        line-height: 1.15;
        font-weight: 700;
        text-wrap: balance;
      }
      .subject,
      .dates {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        flex-wrap: wrap;
        font-size: var(--boxel-font-size-sm);
      }
      .dates span {
        display: inline-flex;
        align-items: center;
        gap: 0.25rem;
        color: var(--muted-foreground);
        font-variant-numeric: tabular-nums;
      }
      .alarm,
      .dates .alarm {
        color: var(--destructive-ink);
        font-weight: 600;
      }
      .muted {
        color: var(--muted-foreground);
      }
      .banner {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        border-radius: var(--radius);
        background: color-mix(in oklab, var(--primary) 12%, transparent);
        color: var(--foreground);
        font-size: var(--boxel-font-size-sm);
        font-weight: 500;
      }
      .wo-meta {
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp-sm);
        align-items: flex-start;
      }
      .meta-block {
        display: grid;
        gap: var(--boxel-sp-4xs);
        padding: var(--boxel-sp-sm);
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
      }
      .meta-l {
        font-size: var(--boxel-font-size-xs);
        letter-spacing: 0.08em;
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .meta-big {
        font-size: 1.5rem;
        font-weight: 700;
        font-variant-numeric: tabular-nums;
      }
      .meta-s {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
      .sec {
        display: grid;
        gap: var(--boxel-sp-sm);
        min-width: 0;
      }
      .sec h2 {
        margin: 0;
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        font-size: var(--boxel-font-size-sm);
        letter-spacing: 0.08em;
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .two {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(17.5rem, 1fr));
        gap: var(--boxel-sp-lg);
      }
      .list {
        list-style: none;
        margin: 0;
        padding: 0;
        display: grid;
        gap: var(--boxel-sp-xs);
      }
      .ic {
        width: 1rem;
        height: 1rem;
        flex: none;
      }
      @container (width < 40rem) {
        .head {
          grid-template-columns: 1fr;
        }
      }
    </style>
  </template>
}

/**
 * One job on one asset (or place): the unit of maintenance work, cost and
 * history. Kind decides the flavour — preventive / corrective / inspection /
 * project; an **Inspection is a Work Order with `kind = inspection`** whose
 * Complete Inspection turns failed checklist items into Inspection Findings.
 *
 * Single writers: Raise Work Order (creation, id minting), the board / Run
 * transition helper (status), Complete Work Order + Complete Inspection
 * (completion, rollups, plan advancement), Cancel; the edit form shows those
 * fields read-only. `planDueKey` is the generator's idempotency key: one work
 * order per plan per due day ("plan-slug@yyyy-mm-dd"), or per meter value
 * for a meter-due occurrence ("plan-slug@meter-4810").
 *
 * The owner field is named `ownership` so the shared Assign Owner command
 * accepts this card unchanged.
 */
export class WorkOrder extends CardDef {
  static displayName = 'Work Order';
  static icon = WrenchIcon;

  @field identifier = contains(RecordIdentifierField);
  @field subjectAsset = linksTo(() => Asset);
  @field subjectLocation = linksTo(() => Location);
  @field plan = linksTo(() => MaintenancePlan);
  @field planDueKey = contains(StringField, {
    description:
      'Idempotency key set by Generate PM Work Orders: "plan-slug@yyyy-mm-dd", or "plan-slug@meter-N" for a meter-due occurrence.',
  });
  @field kind = contains(WorkOrderKindField);
  @field priority = contains(WorkOrderPriorityField);
  @field status = contains(WorkOrderStatusField);
  @field title = contains(StringField);
  @field description = contains(MarkdownField);
  @field requestedByName = contains(StringField);
  @field requestedAt = contains(DateTimeField);
  @field scheduledFor = contains(DateField);
  // Position within `scheduledFor`'s day — the run order a supervisor drags
  // into on the calendar. `scheduledFor` is a DateField (no time of day), so
  // there is nowhere else for "do this one before that one on Tuesday" to
  // live. Additive and optional: an unset value sorts after every set one,
  // so existing instances keep their current order until someone drags.
  @field daySequence = contains(NumberField);
  @field dueBy = contains(DateField);
  @field startedAt = contains(DateTimeField);
  @field completedAt = contains(DateTimeField);
  @field closedAt = contains(DateTimeField);
  @field ownership = contains(RecordOwnerField);
  @field checklist = contains(ChecklistField);
  @field labour = containsMany(LabourEntryField);
  @field parts = containsMany(PartUsageField);
  @field downtime = contains(DowntimeField);
  @field failure = contains(FailureReportField);
  @field findings = containsMany(InspectionFindingField);
  @field approval = contains(ApprovalChainField);
  @field holdReason = contains(HoldReasonField);
  @field cancelReason = contains(StringField);
  @field noLabourReason = contains(StringField, {
    description: 'Complete Work Order accepts no labour only with this reason.',
  });

  @field labourCost = contains(NumberField, {
    computeVia: function (this: WorkOrder) {
      return sumCost(this.labour);
    },
  });
  @field partsCost = contains(NumberField, {
    computeVia: function (this: WorkOrder) {
      return sumCost(this.parts);
    },
  });
  @field totalCost = contains(NumberField, {
    computeVia: function (this: WorkOrder) {
      return (
        Math.round((sumCost(this.labour) + sumCost(this.parts)) * 100) / 100
      );
    },
  });
  @field labourHours = contains(NumberField, {
    computeVia: function (this: WorkOrder) {
      return (this.labour ?? []).reduce(
        (acc, l) => acc + (l?.effectiveHours ?? 0),
        0,
      );
    },
  });

  @field isTerminal = contains(BooleanField, {
    computeVia: function (this: WorkOrder) {
      return WO_TERMINAL.has(this.status ?? '') || this.status === 'completed';
    },
  });

  @field isOverdue = contains(BooleanField, {
    computeVia: function (this: WorkOrder) {
      if (this.isTerminal) return false;
      let due = toDay(this.dueBy);
      if (!due) return false;
      return daysBetweenDays(toDay(new Date())!, due) < 0;
    },
  });

  @field isCompliant = contains(BooleanField, {
    computeVia: function (this: WorkOrder) {
      let due = toDay(this.dueBy);
      let done = toDay(this.completedAt);
      if (!due || !done) return false;
      return done.getTime() <= due.getTime();
    },
  });

  @field warrantyCovered = contains(BooleanField, {
    computeVia: function (this: WorkOrder) {
      return !!(this.subjectAsset as any)?.warranty?.isActive;
    },
  });

  @field assetId = contains(StringField, {
    computeVia: function (this: WorkOrder) {
      return this.subjectAsset?.id;
    },
  });
  @field planId = contains(StringField, {
    computeVia: function (this: WorkOrder) {
      return this.plan?.id;
    },
  });
  @field assetTag = contains(StringField, {
    computeVia: function (this: WorkOrder) {
      return (this.subjectAsset as any)?.identifier?.value as
        | string
        | undefined;
    },
  });
  @field assetName = contains(StringField, {
    computeVia: function (this: WorkOrder) {
      return (
        (this.subjectAsset as any)?.name ?? (this.subjectLocation as any)?.name
      );
    },
  });

  @field cardTitle = contains(StringField, {
    computeVia: function (this: WorkOrder) {
      let id = this.identifier?.value;
      let t = this.title ?? 'Untitled work order';
      return id ? `${id} · ${t}` : t;
    },
  });

  static isolated = WorkOrderIsolated;

  static embedded = class Embedded extends Component<typeof WorkOrder> {
    get kindLabel() {
      return WO_KIND_LABEL[this.args.model.kind ?? ''] ?? 'WO';
    }
    get statusHue(): Hue {
      return WO_STATUS_HUE[this.args.model.status ?? ''] ?? 'slate';
    }
    get due() {
      let m = this.args.model;
      let d = toDay(m.dueBy);
      return d ? fmtDay(d) : undefined;
    }
    <template>
      <div class='wo-emb'>
        <code class='tag'>{{@model.identifier.value}}</code>
        <div class='body'>
          <div class='row'>
            <span class='kind'>{{this.kindLabel}}</span>
            <span class='title'>{{@model.title}}</span>
          </div>
          <div class='meta'>
            {{#if @model.assetTag}}{{@model.assetTag}}
              ·
            {{/if}}{{@model.assetName}}
            {{#if @model.ownership.ownerName}}·
              {{@model.ownership.ownerName}}{{/if}}
            {{#if this.due}}· due {{this.due}}{{/if}}
          </div>
        </div>
        <@fields.priority @format='atom' />
        <StatePill
          @label={{if @model.isOverdue 'overdue' @model.status}}
          @hue={{if @model.isOverdue 'orange' this.statusHue}}
          @dot={{true}}
        />
      </div>
      <style scoped>
        .wo-emb {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          min-width: 0;
        }
        .tag {
          flex: none;
          font-family: var(--font-mono);
          font-size: var(--boxel-font-size-xs);
          font-weight: 600;
        }
        .body {
          flex: 1;
          min-width: 0;
          display: grid;
          gap: 2px;
        }
        .row {
          display: flex;
          align-items: baseline;
          gap: var(--boxel-sp-xs);
          min-width: 0;
        }
        .kind {
          font-size: var(--boxel-font-size-xs);
          font-weight: 700;
          letter-spacing: 0.08em;
          color: var(--muted-foreground);
        }
        .title {
          font-weight: 600;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .meta {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof WorkOrder> {
    get kindLabel() {
      return WO_KIND_LABEL[this.args.model.kind ?? ''] ?? 'WO';
    }
    get statusHue(): Hue {
      return WO_STATUS_HUE[this.args.model.status ?? ''] ?? 'slate';
    }
    get due() {
      let m = this.args.model;
      let d = toDay(m.dueBy);
      if (!d) return undefined;
      let n = daysBetweenDays(toDay(new Date())!, d);
      if (m.isTerminal) return fmtDay(d);
      return n < 0
        ? `${Math.abs(n)} d overdue`
        : n === 0
          ? 'due today'
          : `due in ${n} d`;
    }
    <template>
      <FittedCard class='fit' @titleTag='h3'>
        <:eyebrow><span class='mono'>{{@model.identifier.value}}</span>
          ·
          {{this.kindLabel}}</:eyebrow>
        <:title>{{@model.title}}</:title>
        <:subtitle>{{@model.assetTag}} {{@model.assetName}}</:subtitle>
        <:meta><span
            class={{if @model.isOverdue 'alarm'}}
          >{{this.due}}</span>{{#if @model.ownership.ownerName}}
            ·
            {{@model.ownership.ownerName}}{{/if}}</:meta>
        <:badge><StatePill
            @label={{@model.status}}
            @hue={{if @model.isOverdue 'orange' this.statusHue}}
            @dot={{true}}
          /></:badge>
      </FittedCard>
      <style scoped>
        .fit {
          --fc-title-font-size: var(--boxel-font-size-sm);
          --fc-subtitle-font-size: var(--boxel-font-size-xs);
        }
        .mono {
          font-family: var(--font-mono);
        }
        .alarm {
          color: var(--destructive-ink);
          font-weight: 600;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof WorkOrder> {
    <template>
      <span class='wo-atom'><code>{{@model.identifier.value}}</code>
        {{@model.title}}</span>
      <style scoped>
        .wo-atom {
          font-size: var(--boxel-font-size-xs);
          font-weight: 500;
        }
        .wo-atom code {
          font-family: var(--font-mono);
          font-weight: 600;
        }
      </style>
    </template>
  };

  static edit = class Edit extends Component<typeof WorkOrder> {
    sections = [
      { id: 'job', label: 'Job' },
      { id: 'subject', label: 'Subject & schedule' },
      { id: 'work', label: 'Work done' },
      { id: 'costs', label: 'Costs' },
      { id: 'failure', label: 'Failure & findings' },
    ];
    <template>
      <SectionedEdit
        @sections={{this.sections}}
        @ariaLabel='Work order sections'
        as |e|
      >
        <e.Section @id='job' @title='Job' @cols={{2}}>
          <FieldContainer @label='Title' @vertical={{true}}><@fields.title
            /></FieldContainer>
          <FieldContainer
            @label='Identifier'
            @vertical={{true}}
          ><@fields.identifier /></FieldContainer>
          <FieldContainer @label='Kind' @vertical={{true}}><@fields.kind
            /></FieldContainer>
          <FieldContainer @label='Priority' @vertical={{true}}><@fields.priority
            /></FieldContainer>
          <FieldContainer @label='Status' @vertical={{true}}><@fields.status
              @format='atom'
            /></FieldContainer>
          <FieldContainer
            @label='Hold reason'
            @vertical={{true}}
          ><@fields.holdReason /></FieldContainer>
          <FieldContainer
            @label='Description'
            @vertical={{true}}
          ><@fields.description /></FieldContainer>
          <FieldContainer @label='Owner' @vertical={{true}}><@fields.ownership
            /></FieldContainer>
        </e.Section>
        <e.Section @id='subject' @title='Subject & schedule' @cols={{2}}>
          <FieldContainer
            @label='Asset'
            @vertical={{true}}
          ><@fields.subjectAsset /></FieldContainer>
          <FieldContainer
            @label='Location'
            @vertical={{true}}
          ><@fields.subjectLocation /></FieldContainer>
          <FieldContainer @label='Plan' @vertical={{true}}><@fields.plan
            /></FieldContainer>
          <FieldContainer
            @label='Requested by'
            @vertical={{true}}
          ><@fields.requestedByName /></FieldContainer>
          <FieldContainer
            @label='Requested at'
            @vertical={{true}}
          ><@fields.requestedAt /></FieldContainer>
          <FieldContainer
            @label='Scheduled for'
            @vertical={{true}}
          ><@fields.scheduledFor /></FieldContainer>
          <FieldContainer @label='Due by' @vertical={{true}}><@fields.dueBy
            /></FieldContainer>
          <FieldContainer @label='Started' @vertical={{true}}><@fields.startedAt
              @format='atom'
            /></FieldContainer>
          <FieldContainer
            @label='Completed'
            @vertical={{true}}
          ><@fields.completedAt @format='atom' /></FieldContainer>
          <FieldContainer @label='Closed' @vertical={{true}}><@fields.closedAt
              @format='atom'
            /></FieldContainer>
        </e.Section>
        <e.Section
          @id='work'
          @title='Work done'
          @hint='The checklist defines done; the timer writes labour'
        >
          <@fields.checklist />
          <FieldContainer @label='Downtime' @vertical={{true}}><@fields.downtime
            /></FieldContainer>
          <FieldContainer
            @label='No-labour reason'
            @vertical={{true}}
          ><@fields.noLabourReason /></FieldContainer>
        </e.Section>
        <e.Section @id='costs' @title='Costs' @cols={{2}}>
          <FieldContainer @label='Labour' @vertical={{true}}><@fields.labour
            /></FieldContainer>
          <FieldContainer @label='Parts' @vertical={{true}}><@fields.parts
            /></FieldContainer>
        </e.Section>
        <e.Section
          @id='failure'
          @title='Failure & findings'
          @hint='Corrective work needs a remedy; inspections produce findings'
        >
          <FieldContainer
            @label='Failure report'
            @vertical={{true}}
          ><@fields.failure /></FieldContainer>
          <FieldContainer @label='Findings' @vertical={{true}}><@fields.findings
            /></FieldContainer>
          <FieldContainer
            @label='Cancel reason'
            @vertical={{true}}
          ><@fields.cancelReason /></FieldContainer>
        </e.Section>
        <e.Section
          @id='approval'
          @title='Approval'
          @hint='Required when estimated cost is over the App Configuration threshold'
        >
          <FieldContainer
            @label='Approval chain'
            @vertical={{true}}
          ><@fields.approval /></FieldContainer>
        </e.Section>
      </SectionedEdit>
    </template>
  };
}

function fmtDay(d: Date): string {
  return d.toLocaleDateString(undefined, { day: 'numeric', month: 'short' });
}

export default WorkOrder;
