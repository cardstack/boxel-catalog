import {
  CardDef,
  Component,
  field,
  contains,
  linksTo,
  StringField,
  type BaseDefComponent,
} from '@cardstack/base/card-api';
import DateField from '@cardstack/base/date';
import NumberField from '@cardstack/base/number';
import TextAreaField from '@cardstack/base/text-area';
import enumField from '@cardstack/base/enum';
import PlaneDepartureIcon from '@cardstack/boxel-icons/plane-departure';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { concat, fn } from '@ember/helper';
import { Alert } from '../../ui-component/components/alert';
import { Button } from '../../ui-component/components/button';

import { Employee } from './employee';
import { ApprovalChainField } from './approval-chain-field';
import { ApproveChainStepCommand } from './commands/approve-chain-step-command';
import { type Hue } from '@cardstack/catalog/components/state-pill';
import { Avatar } from '../../ui-component/components/avatar';
import { Descriptions } from '../../ui-component/components/descriptions';
import { FitTile } from '../../ui-component/components/fit-tile';
import {
  KeyValue,
  type KeyValueItem,
} from '../../ui-component/components/key-value';
import { Panel } from '../../ui-component/components/panel';
import { Stat } from '../../ui-component/components/stat';
import { StatusChip } from '../../ui-component/components/status-chip';
import type { PretuiToneArg } from '../../ui-component/pretui-primitives';
import { ALERT_STYLE } from '@cardstack/catalog/components/pretui-helpers';
import { toDate } from '@cardstack/catalog/fields/effective-period/effective-period-field';
import { stateColorsOf } from './hr-ui';
import {
  FittedExtras,
  RecordAtom,
  RecordEmbedded,
  RecordIsolated,
  mediumDate,
  type FittedProgress,
  type FittedStat,
} from '../procurement/vendor';

export const PTO_TYPES = ['vacation', 'sick', 'personal', 'parental', 'unpaid'];

export const PTO_TYPE_LABELS: Record<string, string> = {
  vacation: 'Vacation',
  sick: 'Sick',
  personal: 'Personal',
  parental: 'Parental',
  unpaid: 'Unpaid',
};

// Colocated with PtoRequest — the same map colours the type pill in every
// format: vacation reads as the calm "planned time" blue,
// sick as amber (needs cover), personal purple, parental pink, unpaid slate
// (no accrual implication).
export const PTO_TYPE_HUES: Record<string, Hue> = {
  vacation: 'blue',
  sick: 'amber',
  personal: 'purple',
  parental: 'pink',
  unpaid: 'slate',
};

export const PTO_TYPE_COLORS = stateColorsOf(PTO_TYPE_HUES);

// The request's lifecycle mirrors its approval chain (see `status` computed):
// draft (no chain yet) → in-progress → approved | rejected. Same polarity as
// the approval decision hues: amber undecided, green forward, red stop.
export const PTO_STATUSES = ['draft', 'in-progress', 'approved', 'rejected'];

export const PTO_STATUS_HUES: Record<string, Hue> = {
  draft: 'slate',
  'in-progress': 'amber',
  approved: 'green',
  rejected: 'red',
};

export const PTO_STATUS_COLORS = stateColorsOf(PTO_STATUS_HUES);

export const PtoTypeField = enumField(StringField, {
  options: PTO_TYPES.map((value) => ({
    value,
    label: PTO_TYPE_LABELS[value],
  })),
  displayName: 'PTO Type',
});

// Inclusive day count — a one-day absence (start === end) is 1 day, not 0.
// Undefined (not 0) when either bound is missing or the range is inverted:
// "no dates yet" is a different fact from "zero days".
function inclusiveDays(
  start?: Date | string | null,
  end?: Date | string | null,
): number | undefined {
  if (!start || !end) {
    return undefined;
  }
  let s = toDate(start);
  let e = toDate(end);
  if (!s || !e) {
    return undefined;
  }
  let days = Math.round((e.getTime() - s.getTime()) / 86400000) + 1;
  return days > 0 ? days : undefined;
}

function shortDate(value?: Date | string | null): string | undefined {
  if (!value) {
    return undefined;
  }
  let d = toDate(value);
  return d?.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
}

// What a reader calls each lifecycle state; the stored value stays as is.
const PTO_STATUS_LABELS: Record<string, string> = {
  draft: 'draft',
  'in-progress': 'pending',
  approved: 'approved',
  rejected: 'rejected',
};

const PTO_STATUS_TONES: Record<string, PretuiToneArg> = {
  draft: 'neutral',
  'in-progress': 'warning',
  approved: 'success',
  rejected: 'danger',
};

function orDash(value?: string) {
  return value || '—';
}

// Every format reads the same labels, so a tile and the isolated view can
// never word the same request differently.
function ptoView(m?: Partial<PtoRequest>) {
  let start = toDate(m?.startDate ?? undefined);
  let end = toDate(m?.endDate ?? undefined);
  let range: string | undefined;
  if (start && end) {
    range =
      start.getFullYear() === end.getFullYear()
        ? `${shortDate(start)} – ${mediumDate(end)}`
        : `${mediumDate(start)} – ${mediumDate(end)}`;
  } else {
    range = mediumDate(start ?? end);
  }
  let days = m?.days ?? undefined;
  let daysLabel =
    days == null ? undefined : days === 1 ? '1 day' : `${days} days`;
  let steps = m?.approvalChain?.steps ?? [];
  let approved = steps.filter((st) => st.decision === 'approved').length;
  let index = m?.approvalChain?.currentStepIndex ?? undefined;
  let pending =
    m?.status === 'in-progress' && index != null && index >= 0
      ? steps[index]
      : undefined;
  let nextName = pending?.approver?.name ?? undefined;
  let type = m?.ptoType ? PTO_TYPE_LABELS[m.ptoType] : undefined;
  let status = m?.status ?? 'draft';
  let fact: string | undefined;
  if (pending) {
    fact = `Waiting on ${nextName ?? 'approval'} · step ${(index ?? 0) + 1} of ${steps.length}`;
  } else if (status === 'approved') {
    fact = `Approved · ${steps.length} of ${steps.length} sign-offs`;
  } else if (status === 'rejected') {
    fact = 'Rejected';
  } else if (status === 'draft') {
    fact = 'Draft · not yet submitted';
  }
  let requested = mediumDate(toDate(m?.requestedDate ?? undefined));
  return {
    range,
    days,
    daysLabel,
    type,
    statusLabel: PTO_STATUS_LABELS[status] ?? status,
    statusTone: PTO_STATUS_TONES[status] ?? 'neutral',
    subtitle: [range, daysLabel].filter(Boolean).join(' · ') || undefined,
    fact,
    nextName,
    requested,
    approvalShort: steps.length ? `${approved} / ${steps.length}` : undefined,
    approvalLong: steps.length
      ? `${approved} of ${steps.length} approved`
      : 'Not submitted',
    progress: steps.length ? Math.round((approved / steps.length) * 100) : 0,
    reasonShort: m?.reason?.split(/[—.]/)[0]?.trim() || undefined,
  };
}

// A PTO request — the fourth real consumer of ApprovalChainField (after
// Position, Offer, and JobRequisition). This card is the request/approval
// RECORD: who wants which days off, of what type, and where the sign-off
// stands. Balance math (allowance minus approved days) is deliberately an
// app-side live query over these cards, not a linksToMany on Employee.
class PtoRequestIsolated extends Component<typeof PtoRequest> {
  get v() {
    return ptoView(this.args.model);
  }

  get detailItems(): KeyValueItem[] {
    let v = this.v;
    return [
      { key: 'Type', value: orDash(v.type) },
      { key: 'Dates', value: orDash(v.range) },
      { key: 'Days', value: v.days == null ? '—' : String(v.days) },
      { key: 'Requested', value: orDash(v.requested) },
      { key: 'Approval', value: v.approvalLong },
      { key: 'Reason', value: orDash(v.reasonShort) },
      { key: 'Status', value: v.statusLabel },
    ];
  }

  get linkedItems(): KeyValueItem[] {
    return [{ key: 'Employee', value: '— unassigned' }];
  }

  // Click-to-decide for the pending chain step — the exact idiom Offer's
  // isolated view uses (see offer.gts + approval-chain-field.gts's class
  // comment for why the buttons live on the consuming card, not inside the
  // field's own template). ApproveChainStepCommand reads the card's
  // `approvalChain` field, which PtoRequest shares by name.
  @tracked approvalBusy = false;
  @tracked approvalError: string | undefined;

  get canDecideApproval(): boolean {
    return this.args.model?.approvalChain?.status === 'in-progress';
  }

  decideApprovalStep = (decision: 'approved' | 'rejected') => {
    void this.decideApprovalStepTask(decision);
  };

  private decideApprovalStepTask = async (
    decision: 'approved' | 'rejected',
  ) => {
    let model = this.args.model;
    let chain = model?.approvalChain;
    if (!model || !chain) {
      return;
    }
    let commandContext = this.args.context?.commandContext;
    if (!commandContext) {
      this.approvalError = 'Commands are unavailable in this mode';
      return;
    }
    this.approvalError = undefined;
    this.approvalBusy = true;
    try {
      await new ApproveChainStepCommand(commandContext).execute({
        target: model,
        stepIndex: chain.currentStepIndex,
        decision,
      } as any);
    } catch (error: any) {
      this.approvalError = error?.message ?? String(error);
    } finally {
      this.approvalBusy = false;
    }
  };

  <template>
    <RecordIsolated @title={{@model.title}} @subtitle={{this.v.subtitle}}>
      <:avatar><Avatar
          @name={{if @model.employeeName @model.employeeName '?'}}
          @hue='var(--muted-foreground)'
          @size={{48}}
          aria-hidden='true'
        /></:avatar>
      <:chips>
        <StatusChip @value={{this.v.statusLabel}} @tone={{this.v.statusTone}} />
        {{#if @model.ptoType}}
          <StatusChip @value={{@model.ptoType}} @tone='neutral' />
        {{/if}}
      </:chips>
      <:stats>
        <Panel><Stat
            @label='Days'
            @value={{if this.v.days this.v.days '—'}}
            @hint={{this.v.range}}
            @roll={{false}}
          /></Panel>
        <Panel><Stat
            @label='Type'
            @value={{orDash this.v.type}}
            @hint={{if this.v.requested (concat 'requested ' this.v.requested)}}
            @roll={{false}}
          /></Panel>
        <Panel><Stat
            @label='Approval'
            @value={{orDash this.v.approvalShort}}
            @hint={{if this.v.nextName (concat this.v.nextName ' next')}}
            @roll={{false}}
          /></Panel>
      </:stats>
      <:main>
        {{#if @model.reason}}
          <Panel @title='Reason'>
            <p class='reason'>{{@model.reason}}</p>
          </Panel>
        {{/if}}
        <Panel @title='Approval chain'>
          <@fields.approvalChain @format='embedded' />
          {{#if this.canDecideApproval}}
            <div class='decide-row'>
              <Button
                @variant='primary'
                @size='s'
                @busy={{this.approvalBusy}}
                @disabled={{this.approvalBusy}}
                {{on 'click' (fn this.decideApprovalStep 'approved')}}
              >Approve step</Button>
              <Button
                @variant='secondary'
                @size='s'
                @disabled={{this.approvalBusy}}
                {{on 'click' (fn this.decideApprovalStep 'rejected')}}
              >Reject</Button>
            </div>
          {{/if}}
          {{#if this.approvalError}}
            <Alert
              @tone='danger'
              @title='Could not record the decision'
              style={{ALERT_STYLE.danger}}
            >{{this.approvalError}}</Alert>
          {{/if}}
        </Panel>
      </:main>
      <:side>
        <Panel @title='Linked'>
          <KeyValue @items={{this.linkedItems}}>
            <:value as |row|>{{#if @model.employee}}<@fields.employee
                  @format='atom'
                  @displayContainer={{false}}
                />{{else}}{{row.value}}{{/if}}</:value>
          </KeyValue>
        </Panel>
        <Panel @title='Details'>
          <KeyValue @items={{this.detailItems}} />
        </Panel>
      </:side>
    </RecordIsolated>
    <style scoped>
      @layer PretComponent {
        .reason {
          margin: 0;
          white-space: pre-line;
        }
        .decide-row {
          display: flex;
          gap: var(--boxel-sp-xs);
          margin-block-start: var(--boxel-sp-sm);
        }
      }
    </style>
  </template>
}

export class PtoRequest extends CardDef {
  static displayName = 'PTO Request';
  static icon = PlaneDepartureIcon;

  @field employee = linksTo(() => Employee);
  @field ptoType = contains(PtoTypeField);
  @field startDate = contains(DateField);
  @field endDate = contains(DateField);
  @field reason = contains(TextAreaField);
  // Reused UNCHANGED from approval-chain-field.gts — same step/decision
  // model and read-only stepper as Position/Offer/JobRequisition.
  @field approvalChain = contains(ApprovalChainField);
  @field requestedDate = contains(DateField);

  @field days = contains(NumberField, {
    computeVia: function (this: PtoRequest) {
      return inclusiveDays(this.startDate, this.endDate);
    },
  });

  // Mirrors the chain, with one refinement: an EMPTY chain means the request
  // is still a draft (not yet submitted for sign-off), which is a different
  // fact from the chain's own 'not-started'.
  @field status = contains(StringField, {
    computeVia: function (this: PtoRequest) {
      if (!this.approvalChain?.steps?.length) {
        return 'draft';
      }
      return this.approvalChain.status ?? 'draft';
    },
  });

  // Denormalized for fitted — prerendered fitted does not resolve linksTo,
  // so the tile reads this own attribute instead of employee.name. Same
  // rationale as OnboardingChecklist.personName.
  @field employeeName = contains(StringField, {
    computeVia: function (this: PtoRequest) {
      return this.employee?.name ?? '';
    },
  });

  // Denormalized id-scalar for hot app-side getters — an app's
  // per-employee balance math runs once per employee per render, and reading
  // the `employee` linksTo there races the async link load the same way
  // Meeting.candidateId's comment explains.
  @field employeeId = contains(StringField, {
    computeVia: function (this: PtoRequest) {
      return this.employee?.id ?? '';
    },
  });

  @field title = contains(StringField, {
    computeVia: function (this: PtoRequest) {
      let name = this.employeeName?.trim() || 'Unassigned';
      let parts: string[] = [];
      if (this.ptoType) {
        parts.push(this.ptoType);
      }
      if (this.days != null) {
        parts.push(`${this.days}d`);
      }
      return parts.length ? `${name} — ${parts.join(', ')}` : name;
    },
  });

  // The operator-mode stack header renders `cardTitle`, whose base computed
  // falls back to "Untitled <type>" when cardInfo.name is unset — it never
  // consults our computed `title`. Route it through title so seeded
  // instances (cardInfo.name: null) get a real header.
  @field cardTitle = contains(StringField, {
    computeVia: function (this: PtoRequest) {
      return this.cardInfo?.name?.trim() || this.title;
    },
  });

  static isolated: BaseDefComponent = PtoRequestIsolated;

  static embedded: BaseDefComponent = class Embedded extends Component<
    typeof this
  > {
    get v() {
      return ptoView(this.args.model);
    }
    get kvItems() {
      let v = this.v;
      return [
        { label: 'Type', value: v.type },
        { label: 'Dates', value: v.range },
        { label: 'Days', value: v.days == null ? undefined : String(v.days) },
        { label: 'Requested', value: v.requested },
        { label: 'Approval', value: v.approvalLong },
        { label: 'Reason', value: v.reasonShort },
      ];
    }
    <template>
      <RecordEmbedded @title={{@model.title}} @subtitle={{this.v.subtitle}}>
        <:avatar><Avatar
            @name={{if @model.employeeName @model.employeeName '?'}}
            @hue='var(--muted-foreground)'
            @size={{40}}
            aria-hidden='true'
          /></:avatar>
        <:chips>
          <StatusChip
            @value={{this.v.statusLabel}}
            @tone={{this.v.statusTone}}
          />
          {{#if @model.ptoType}}
            <StatusChip @value={{@model.ptoType}} @tone='neutral' />
          {{/if}}
        </:chips>
        <:fact>{{this.v.fact}}</:fact>
        <:details><Descriptions
            @items={{this.kvItems}}
            @layout='vertical'
            @columns={{3}}
          /></:details>
        <:relations>
          {{#if @model.employee}}
            <span class='rel'>Employee
              <@fields.employee
                @format='atom'
                @displayContainer={{false}}
              /></span>
          {{/if}}
        </:relations>
      </RecordEmbedded>
      <style scoped>
        @layer PretComponent {
          .rel {
            display: inline-flex;
            align-items: center;
            gap: var(--boxel-sp-xs);
            min-inline-size: 0;
            max-inline-size: 100%;
          }
        }
      </style>
    </template>
  };

  // Attribute-only: employeeName, days and status are the request's own
  // attributes; the relation renders the employee's own atom.
  static fitted: BaseDefComponent = class Fitted extends Component<
    typeof this
  > {
    get v() {
      return ptoView(this.args.model);
    }
    get facts(): KeyValueItem[] {
      let v = this.v;
      return [
        { key: 'Type', value: orDash(v.type) },
        { key: 'Dates', value: orDash(v.range) },
        { key: 'Days', value: v.days == null ? '—' : String(v.days) },
        { key: 'Requested', value: orDash(v.requested) },
        { key: 'Approval', value: v.approvalLong },
        { key: 'Reason', value: orDash(v.reasonShort) },
        { key: 'Status', value: v.statusLabel },
      ];
    }
    get stats(): FittedStat[] {
      let v = this.v;
      return [
        { key: 'Days', value: v.days == null ? '—' : String(v.days) },
        { key: 'Type', value: orDash(v.type) },
        { key: 'Approval', value: orDash(v.approvalShort) },
      ];
    }
    get progress(): FittedProgress | undefined {
      let v = this.v;
      return v.approvalShort
        ? {
            label: 'Approval',
            value: v.progress,
            valueText: v.approvalShort,
          }
        : undefined;
    }
    get relations() {
      return this.args.model?.employeeName ? ['Employee'] : [];
    }
    <template>
      <FittedExtras
        @facts={{this.facts}}
        @stats={{this.stats}}
        @progress={{this.progress}}
        @relations={{this.relations}}
      >
        <:default>
          <FitTile>
            <:avatar><Avatar
                @name={{if @model.employeeName @model.employeeName '?'}}
                @hue='var(--muted-foreground)'
                @size={{32}}
                aria-hidden='true'
              /></:avatar>
            <:title><span
                class='fit-title'
                role='heading'
                aria-level='3'
              >{{@model.title}}</span></:title>
            <:subtitle>{{this.v.subtitle}}</:subtitle>
            <:status>
              <StatusChip
                @value={{this.v.statusLabel}}
                @tone={{this.v.statusTone}}
              />
              {{#if @model.ptoType}}
                <StatusChip @value={{@model.ptoType}} @tone='neutral' />
              {{/if}}
            </:status>
            <:fact>{{this.v.fact}}</:fact>
          </FitTile>
        </:default>
        <:relation><@fields.employee @format='atom' /></:relation>
      </FittedExtras>
      <style scoped>
        @layer PretComponent {
          .fit-title {
            display: block;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
          }
        }
      </style>
    </template>
  };

  static atom: BaseDefComponent = class Atom extends Component<typeof this> {
    get v() {
      return ptoView(this.args.model);
    }
    <template>
      <RecordAtom @name={{@model.title}}>
        <StatusChip @value={{this.v.statusLabel}} @tone={{this.v.statusTone}} />
      </RecordAtom>
    </template>
  };
}
