import type { TemplateOnlyComponent } from '@ember/component/template-only';
import {
  CardDef,
  Component,
  contains,
  containsMany,
  field,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import { on } from '@ember/modifier';
import { tracked } from '@glimmer/tracking';
import NumberField from '@cardstack/base/number';
import BooleanField from '@cardstack/base/boolean';
import DateField from '@cardstack/base/date';
import DateTimeField from '@cardstack/base/datetime';
import MarkdownField from '@cardstack/base/markdown';
import WrenchIcon from '@cardstack/boxel-icons/wrench';
import { Button } from '@cardstack/pretui/components/button';
import { FitTile } from '../shared/fit-tile';

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
import { InspectionFindingField } from '../audit/inspection-finding-field';
import { ApprovalChainField } from '../hr/approval-chain-field';
import {
  WorkOrderStatusField,
  WorkOrderPriorityField,
  WorkOrderKindField,
  HoldReasonField,
  HOLD_REASONS,
  WO_TERMINAL,
} from './maintenance-vocabulary';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import CompleteWorkOrderCommand from './commands/complete-work-order-command';
import { sumCost } from './utils/maintenance';
import { toDay, daysBetweenDays } from './utils/recurrence';
import {
  Chip,
  Dot,
  Head,
  Mark,
  Row,
  Kv,
  KvRow,
  Section,
  Stats,
  fmtDay,
  fmtStamp,
  initials,
  money,
  type Tone,
} from './card-ui';

const STATUS_TONE: Record<string, Tone> = {
  requested: 'muted',
  approved: 'info',
  scheduled: 'info',
  'in-progress': 'info',
  'on-hold': 'warn',
  completed: 'ok',
  closed: 'ok',
  cancelled: 'muted',
};
const PRIORITY_TONE: Record<string, Tone> = { P1: 'bad', P2: 'warn' };
const RESULT_TONE: Record<string, Tone> = { pass: 'ok', fail: 'bad' };

export function woStatusTone(status?: string | null): Tone {
  return STATUS_TONE[status ?? ''] ?? 'muted';
}
export function woStatusLabel(status?: string | null): string {
  return (status ?? 'requested').replace(/-/g, ' ');
}
function priorityTone(p?: string | null): Tone {
  return PRIORITY_TONE[p ?? ''] ?? 'muted';
}

function currency(m: Partial<WorkOrder>): string {
  return (
    m.labour?.[0]?.rate?.currency?.code ??
    m.parts?.[0]?.unitCost?.currency?.code ??
    'USD'
  );
}

// WO-0870 · corrective · Loading Dock
function metaLine(m: Partial<WorkOrder>): string {
  let place =
    (m.subjectAsset as any)?.locationName ?? (m.subjectLocation as any)?.name;
  return [m.identifier?.value, m.kind, place].filter(Boolean).join(' · ');
}

// Due Sep 8, 2026 · asset down since Sep 8
function factLine(m: Partial<WorkOrder>): string {
  let parts: string[] = [];
  if (m.dueBy) parts.push(`Due ${fmtDay(m.dueBy, true)}`);
  if (m.downtime?.startedAt && !m.downtime?.endedAt) {
    parts.push(`asset down since ${fmtDay(m.downtime.startedAt)}`);
  } else if (m.completedAt) {
    parts.push(`completed ${fmtDay(m.completedAt)}`);
  }
  return parts.join(' · ');
}

function checklistCount(m: Partial<WorkOrder>): string {
  let c = m.checklist;
  return c?.total ? `${c.done ?? 0} / ${c.total}` : '—';
}
function checklistDone(m: Partial<WorkOrder>): string {
  let c = m.checklist;
  return c?.total ? `${c.done ?? 0} of ${c.total} done` : '';
}
function labourRate(m: Partial<WorkOrder>): string {
  let r = m.labour?.[0]?.rate;
  return r?.amount != null ? `${money(r.amount, r.currency?.code)} / h` : '';
}
function requestedLine(m: Partial<WorkOrder>): string {
  return [fmtDay(m.requestedAt), m.requestedByName].filter(Boolean).join(' · ');
}
function downtimeKind(m: Partial<WorkOrder>): string {
  let d = m.downtime;
  if (!d?.startedAt) return '';
  return d.planned ? 'planned' : 'unplanned';
}

function itemSub(i: any): string {
  if (i?.kind === 'measure' && i?.expectedValue != null) {
    let tol = i.tolerance != null ? ` ± ${i.tolerance}` : '';
    return `measure · ${i.expectedValue} ${i.unit ?? ''}${tol}`.trim();
  }
  if (i?.completedByName) return i.completedByName;
  return i?.required ? 'required' : 'optional';
}
function itemTone(i: any): Tone {
  return RESULT_TONE[i?.result ?? ''] ?? 'muted';
}

function labourLine(l: any): string {
  let rate =
    l?.rate?.amount != null ? money(l.rate.amount, l.rate.currency?.code) : '';
  return [
    l?.startedAt ? `from ${fmtDay(l.startedAt)}` : '',
    rate ? `${rate} / h` : '',
  ]
    .filter(Boolean)
    .join(' · ');
}
function partLabel(p: any): string {
  return `${p?.partNumber ?? 'part'} × ${p?.quantity ?? 1}`;
}
function partLine(p: any): string {
  return [
    money(p?.cost ?? 0, p?.unitCost?.currency?.code),
    p?.fromStock ? 'from stock' : 'bought in',
  ].join(' · ');
}

const StatusDots: TemplateOnlyComponent<{
  Args: { model: Partial<WorkOrder> };
}> = <template>
  <Dot
    @tone={{woStatusTone @model.status}}
    @label={{woStatusLabel @model.status}}
  />
  {{#if @model.priority}}
    <Dot @tone={{priorityTone @model.priority}} @label={{@model.priority}} />
  {{/if}}
  {{#if @model.isOverdue}}<Dot @tone='bad' @label='late' />{{/if}}
</template>;

class WorkOrderIsolated extends Component<typeof WorkOrder> {
  // Commands need the host; a card rendered without one cannot act.
  private get commandContext() {
    let context = this.args.context?.commandContext;
    if (!context) {
      throw new Error('This action needs a running host.');
    }
    return context;
  }

  @tracked error: string | undefined;

  private save = async () => {
    await new SaveCardCommand(this.commandContext).execute({
      card: this.args.model,
    } as any);
  };

  // Non-terminal moves are direct, legal writes per WorkOrderStatusField's
  // transition graph; Complete is gated and goes through the command.
  start = async () => {
    let wo = this.args.model;
    this.error = undefined;
    wo.status = 'in-progress' as any;
    if (!wo.startedAt) wo.startedAt = new Date();
    await this.save();
  };

  hold = async () => {
    let wo = this.args.model;
    this.error = undefined;
    wo.status = 'on-hold' as any;
    wo.holdReason = HOLD_REASONS[0] as any;
    await this.save();
  };

  complete = async () => {
    this.error = undefined;
    try {
      await new CompleteWorkOrderCommand(this.commandContext).execute({
        workOrder: this.args.model,
      } as any);
    } catch (e: any) {
      this.error = e?.message ?? 'Could not complete this work order.';
    }
  };

  get canStart() {
    return ['approved', 'scheduled', 'on-hold'].includes(
      this.args.model.status ?? '',
    );
  }
  get inProgress() {
    return this.args.model.status === 'in-progress';
  }

  get stats() {
    let m = this.args.model;
    let c = m.checklist;
    let next = c?.items?.find((i) => (i?.result ?? 'pending') === 'pending');
    let parts = m.parts ?? [];
    let d = m.downtime;
    return [
      {
        label: 'Checklist',
        value: checklistCount(m),
        meta: next ? `${next.label?.toLowerCase()} still to do` : 'all done',
      },
      {
        label: 'Parts cost',
        value: money(m.partsCost ?? 0, currency(m)),
        meta: parts.length
          ? `${parts.length} part${parts.length === 1 ? '' : 's'}${
              parts.every((p) => p?.fromStock) ? ' from stock' : ''
            }`
          : 'no parts',
      },
      {
        label: 'Priority',
        value: m.priority ?? '—',
        meta: m.dueBy ? `due ${fmtDay(m.dueBy, true)}` : '',
      },
      {
        label: 'Downtime',
        value: !d?.startedAt
          ? '—'
          : d.isOpen
            ? 'Open'
            : `${Math.round((d.hours ?? 0) * 10) / 10} h`,
        meta: d?.startedAt ? `since ${fmtStamp(d.startedAt)}` : 'asset running',
      },
    ];
  }

  <template>
    <article class='wo'>
      <Head @mark='WO' @title={{@model.title}} @meta={{metaLine @model}}>
        <StatusDots @model={{@model}} />
        {{#if this.inProgress}}
          <Button
            @tone='primary'
            @appearance='accent'
            @size='s'
            {{on 'click' this.complete}}
          >Complete</Button>
          <Button
            @tone='neutral'
            @appearance='outlined'
            @size='s'
            {{on 'click' this.hold}}
          >Put on hold</Button>
        {{else if this.canStart}}
          <Button
            @tone='primary'
            @appearance='accent'
            @size='s'
            {{on 'click' this.start}}
          >{{if (isHeld @model.status) 'Resume' 'Start'}}</Button>
        {{/if}}
      </Head>
      {{#if this.error}}<p class='err' role='alert'>{{this.error}}</p>{{/if}}

      <Stats @items={{this.stats}} />

      <div class='cols'>
        <div class='col'>
          {{#if @model.description}}
            <Section @title='Description'><div
                class='prose'
              ><@fields.description /></div></Section>
          {{/if}}
          {{#if @model.failure.symptom}}
            <Section @title='Failure'>
              <Kv>
                <KvRow @label='Symptom' @value={{@model.failure.symptom}} />
                <KvRow @label='Cause' @value={{@model.failure.cause}} />
                <KvRow @label='Code' @value={{cap @model.failure.codeText}} />
                <KvRow
                  @label='Detected'
                  @value={{fmtStamp @model.failure.detectedAt}}
                />
                <KvRow
                  @label='Asset down'
                  @value={{if @model.failure.assetDown 'Yes' 'No'}}
                />
              </Kv>
            </Section>
          {{/if}}
          {{#if @model.checklist.items.length}}
            <Section @title='Checklist'>
              {{#each @model.checklist.items as |i|}}
                <Row
                  @title={{i.label}}
                  @meta={{itemSub i}}
                  @tone={{itemTone i}}
                  @state={{if i.result i.result 'pending'}}
                />
              {{/each}}
            </Section>
          {{/if}}
          <Section @title='Labor & parts'>
            <Kv>
              {{#each @model.labour as |l|}}
                <KvRow @label={{l.workerName}} @value={{labourLine l}} />
              {{/each}}
              {{#each @model.parts as |p|}}
                <KvRow @label={{partLabel p}} @value={{partLine p}} />
              {{/each}}
            </Kv>
            {{#unless (hasWork @model)}}<p class='empty'>No labor or parts
                logged yet</p>{{/unless}}
          </Section>
        </div>

        <aside class='col side'>
          <Section @title='Linked'>
            <Kv>
              <KvRow @label='Asset'>{{#if
                  @model.subjectAsset
                }}<@fields.subjectAsset
                    @format='atom'
                  />{{else}}—{{/if}}</KvRow>
              {{#if @model.subjectLocation}}
                <KvRow @label='Location'><@fields.subjectLocation
                    @format='atom'
                  /></KvRow>
              {{/if}}
              <KvRow @label='Owner'>{{#if @model.ownership.ownerName}}<Chip
                    @mark={{initials @model.ownership.ownerName}}
                    @name={{@model.ownership.ownerName}}
                  />{{else}}—{{/if}}</KvRow>
              {{#each @model.parts as |p|}}
                <KvRow @label='Part'><Chip
                    @mark='Pt'
                    @name={{p.partName}}
                  /></KvRow>
              {{/each}}
              {{#if @model.plan}}
                <KvRow @label='Plan'><@fields.plan @format='atom' /></KvRow>
              {{/if}}
            </Kv>
          </Section>
          <Section @title='Details'>
            <Kv>
              <KvRow @label='Requested' @value={{requestedLine @model}} />
              <KvRow @label='Started' @value={{fmtDay @model.startedAt true}} />
              {{#if @model.completedAt}}
                <KvRow
                  @label='Completed'
                  @value={{fmtDay @model.completedAt true}}
                />
              {{/if}}
              <KvRow @label='Checklist' @value={{checklistDone @model}} />
              <KvRow
                @label='Parts'
                @value={{money @model.partsCost (currency @model)}}
              />
              <KvRow @label='Labor rate' @value={{labourRate @model}} />
              <KvRow @label='Failure' @value={{@model.failure.codeText}} />
              <KvRow @label='Team' @value={{@model.ownership.teamName}} />
              <KvRow @label='Downtime' @value={{downtimeKind @model}} />
              {{#if @model.holdReason}}
                <KvRow
                  @label='Hold reason'
                  @value={{woStatusLabel @model.holdReason}}
                />
              {{/if}}
            </Kv>
          </Section>
        </aside>
      </div>
    </article>
    <style scoped>
      .wo {
        container-type: inline-size;
        min-block-size: 100%;
        box-sizing: border-box;
        font-family: var(--font-sans);
        font-size: var(--boxel-font-size-xs);
        line-height: 1.4;
        color: var(--card-foreground);
        background-color: var(--card);
        --pretui-button-h: 1.625rem;
      }
      .err {
        padding: 0 var(--boxel-sp-sm) var(--boxel-sp-xs);
        color: var(--destructive-ink);
      }
      .cols {
        display: grid;
        grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
      }
      .side {
        border-inline-start: 1px solid var(--border);
      }
      .col {
        min-inline-size: 0;
      }
      .prose {
        padding-block-start: var(--boxel-sp-5xs);
      }
      .empty {
        padding-block: var(--boxel-sp-5xs);
        color: var(--muted-foreground);
      }
      @container (width < 40rem) {
        .cols {
          grid-template-columns: minmax(0, 1fr);
        }
        .side {
          border-inline-start: 0;
          border-block-start: 1px solid var(--border);
        }
      }
    </style>
  </template>
}

function isHeld(status?: string | null) {
  return status === 'on-hold';
}
function hasWork(m: Partial<WorkOrder>) {
  return (m.labour?.length ?? 0) + (m.parts?.length ?? 0) > 0;
}
function cap(s?: string | null) {
  return s ? s[0]!.toUpperCase() + s.slice(1) : '';
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
    description: 'Complete Work Order accepts no labor only with this reason.',
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
    <template>
      <article class='emb'>
        <Head @mark='WO' @title={{@model.title}} @meta={{metaLine @model}} />
        <div class='body'>
          <div class='dots'><StatusDots @model={{@model}} /></div>
          {{#if (factLine @model)}}<p class='fact'>{{factLine
                @model
              }}</p>{{/if}}
          <Kv>
            <KvRow @label='Requested' @value={{requestedLine @model}} />
            <KvRow @label='Started' @value={{fmtDay @model.startedAt true}} />
            <KvRow @label='Checklist' @value={{checklistDone @model}} />
            <KvRow
              @label='Parts'
              @value={{money @model.partsCost (currency @model)}}
            />
            <KvRow @label='Labor rate' @value={{labourRate @model}} />
            <KvRow @label='Failure' @value={{@model.failure.codeText}} />
            <KvRow @label='Asset'>{{#if
                @model.subjectAsset
              }}<@fields.subjectAsset @format='atom' />{{else}}—{{/if}}</KvRow>
            <KvRow @label='Owner'>{{#if @model.ownership.ownerName}}<Chip
                  @mark={{initials @model.ownership.ownerName}}
                  @name={{@model.ownership.ownerName}}
                />{{else}}—{{/if}}</KvRow>
            {{#each @model.parts as |p|}}
              <KvRow @label='Part'><Chip
                  @mark='Pt'
                  @name={{p.partName}}
                /></KvRow>
            {{/each}}
          </Kv>
        </div>
      </article>
      <style scoped>
        .emb {
          font-family: var(--font-sans);
          font-size: var(--boxel-font-size-xs);
          line-height: 1.4;
          color: var(--card-foreground);
          background-color: var(--card);
        }
        .body {
          display: grid;
          gap: var(--boxel-sp-xs);
          padding: 0 var(--boxel-sp-sm) var(--boxel-sp-xs);
        }
        .dots {
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof WorkOrder> {
    <template>
      <FitTile class='fit'>
        <:avatar><Mark @text='WO' @size='lg' /></:avatar>
        <:title>{{@model.title}}</:title>
        <:subtitle>{{metaLine @model}}</:subtitle>
        <:status><span class='dots'><StatusDots
              @model={{@model}}
            /></span></:status>
        <:fact>{{factLine @model}}</:fact>
        <:relations>
          {{#if @model.subjectAsset}}<@fields.subjectAsset
              @format='atom'
            />{{/if}}
          {{#if @model.ownership.ownerName}}<Chip
              @mark={{initials @model.ownership.ownerName}}
              @name={{@model.ownership.ownerName}}
            />{{/if}}
        </:relations>
      </FitTile>
      <style scoped>
        .fit {
          color: var(--card-foreground);
          background-color: var(--card);
        }
        .dots {
          display: inline-flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-xs);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof WorkOrder> {
    <template>
      <Chip
        @bare={{true}}
        @mark='WO'
        @name={{@model.cardTitle}}
        @tone={{woStatusTone @model.status}}
        @meta={{woStatusLabel @model.status}}
      />
    </template>
  };
}

export default WorkOrder;
