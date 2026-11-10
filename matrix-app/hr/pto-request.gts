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
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Alert } from '@cardstack/pretui/components/alert';
import { Button } from '@cardstack/pretui/components/button';

import { Employee } from './employee';
import { ApprovalChainField } from './approval-chain-field';
import { ApproveChainStepCommand } from './commands/approve-chain-step-command';
import { type Hue } from '@cardstack/catalog/components/state-pill';
import type { TemplateOnlyComponent } from '@ember/component/template-only';
import { type DescriptionsItem } from '@cardstack/pretui/components/descriptions';
import { type KeyValueItem } from '@cardstack/pretui/components/key-value';
import type { PretuiToneArg } from '@cardstack/pretui/pretui-primitives';
import { ALERT_STYLE } from '@cardstack/catalog/components/pretui-helpers';
import { toDate } from '@cardstack/catalog/fields/effective-period/effective-period-field';
import { stateColorsOf } from './hr-ui';
import { mediumDate } from '../procurement/vendor';
import {
  EmbCard,
  FitCard,
  FitRow,
  IsoHead,
  IsoPage,
  Kv,
  Panel,
  SheetLine,
  StatStrip,
  type StripItem,
} from './compact-sheet';
import { DotLabel } from './dot-enum-field';

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
export const PTO_STATUS_LABELS: Record<string, string> = {
  draft: 'Draft',
  'in-progress': 'Pending',
  approved: 'Approved',
  rejected: 'Rejected',
};

export const PTO_STATUS_TONES: Record<string, PretuiToneArg> = {
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

// The record's type mark (a square, not a person): same one in every format.
const PtoMark: TemplateOnlyComponent<{ Element: HTMLSpanElement }> = <template>
  <span class='pto-mark' aria-hidden='true' ...attributes>PT</span>
  <style scoped>
    @layer PretComponent {
      .pto-mark {
        display: inline-grid;
        flex: none;
        place-items: center;
        inline-size: var(--pto-mark-size, 2rem);
        block-size: var(--pto-mark-size, 2rem);
        border-radius: calc(var(--radius) - 2px);
        background: var(--card);
        box-shadow: inset 0 0 0 1px var(--border);
        color: var(--primary-ink);
        font-size: var(--pto-mark-font-size, var(--boxel-font-size-xs));
        font-weight: 600;
        line-height: 1;
      }
    }
  </style>
</template>;

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

  get strip(): StripItem[] {
    let v = this.v;
    return [
      {
        label: 'Days',
        value: v.days == null ? '—' : String(v.days),
        hint: v.range,
        tone: 'info',
      },
      {
        label: 'Type',
        value: v.type,
        hint: v.requested ? 'requested ' + v.requested : undefined,
      },
      {
        label: 'Approval',
        value: v.approvalShort,
        hint: v.nextName ? v.nextName + ' next' : undefined,
        tone: 'warning',
      },
    ];
  }

  <template>
    <IsoPage>
      <:head>
        <IsoHead @title={{@model.title}} @meta={{this.v.subtitle}}>
          <:mark><PtoMark /></:mark>
          <:aside><DotLabel
              @label={{this.v.statusLabel}}
              @hue={{toneHue this.v.statusTone}}
            /></:aside>
          <:stats><StatStrip @items={{this.strip}} /></:stats>
        </IsoHead>
      </:head>
      <:main>
        {{#if @model.reason}}
          <Panel @title='Reason'><SheetLine><span
                class='reason'
              >{{@model.reason}}</span></SheetLine></Panel>
        {{/if}}
        <Panel @title='Approval chain'>
          <@fields.approvalChain @format='embedded' />
          {{#if this.canDecideApproval}}
            <SheetLine>
              <Button
                @tone='primary'
                @appearance='accent'
                @size='xs'
                @busy={{this.approvalBusy}}
                @disabled={{this.approvalBusy}}
                {{on 'click' (fn this.decideApprovalStep 'approved')}}
              >Approve step</Button>
              <Button
                @tone='danger'
                @appearance='link'
                @size='xs'
                @disabled={{this.approvalBusy}}
                {{on 'click' (fn this.decideApprovalStep 'rejected')}}
              >Reject</Button>
            </SheetLine>
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
      <:aside>
        <Panel @title='Linked'>
          <Kv @items={{this.linkedItems}}>
            <:value as |row|>{{#if @model.employee}}<@fields.employee
                  @format='atom'
                  @displayContainer={{false}}
                />{{else}}{{row.value}}{{/if}}</:value>
          </Kv>
        </Panel>
        <Panel @title='Details'><Kv @items={{this.detailItems}} /></Panel>
      </:aside>
    </IsoPage>
    <style scoped>
      .reason {
        white-space: pre-line;
      }
    </style>
  </template>
}

// PtoView's tone as the DotLabel hue.
function toneHue(tone?: string) {
  return (
    tone === 'success'
      ? 'green'
      : tone === 'danger'
        ? 'red'
        : tone === 'warning'
          ? 'amber'
          : tone === 'info'
            ? 'blue'
            : 'slate'
  ) as 'green' | 'red' | 'amber' | 'blue' | 'slate';
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
    get gridFacts(): DescriptionsItem[] {
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
    get rows() {
      let v = this.v;
      return [
        { key: 'Waiting on', value: v.nextName ?? '—' },
        { key: 'Type', value: v.type ?? '—' },
        { key: 'Dates', value: v.range ?? '—' },
        { key: 'Days', value: v.days == null ? '—' : String(v.days) },
        { key: 'Requested', value: v.requested ?? '—' },
        { key: 'Approval', value: v.approvalLong },
        { key: 'Employee', value: '' },
      ];
    }
    <template>
      <EmbCard @title={{@model.title}} @meta={{this.v.subtitle}}>
        <:mark><PtoMark /></:mark>
        <:aside><DotLabel
            @label={{this.v.statusLabel}}
            @hue={{toneHue this.v.statusTone}}
          /></:aside>
        <:default>
          <Kv @items={{this.rows}}>
            <:value as |row|>{{#if (eq row.key 'Employee')}}{{#if
                  @model.employee
                }}<@fields.employee
                    @format='atom'
                    @displayContainer={{false}}
                  />{{else}}—{{/if}}{{else}}{{row.value}}{{/if}}</:value>
          </Kv>
        </:default>
      </EmbCard>
    </template>
  };

  static fitted: BaseDefComponent = class Fitted extends Component<
    typeof this
  > {
    get v() {
      return ptoView(this.args.model);
    }
    get kvFacts(): DescriptionsItem[] {
      let v = this.v;
      return [
        { label: 'Type', value: orDash(v.type) },
        { label: 'Dates', value: orDash(v.range) },
        { label: 'Days', value: v.days == null ? '—' : String(v.days) },
        { label: 'Requested', value: orDash(v.requested) },
        { label: 'Approval', value: v.approvalLong },
        { label: 'Reason', value: orDash(v.reasonShort) },
        { label: 'Status', value: v.statusLabel },
      ];
    }
    get strip(): StripItem[] {
      let v = this.v;
      return [
        { label: 'Days', value: v.days == null ? '—' : String(v.days) },
        { label: 'Approval', value: v.approvalShort ?? '—' },
        { label: 'Type', value: v.type ?? '—' },
      ];
    }
    <template>
      <FitCard @title={{@model.title}}>
        <:mark><PtoMark /></:mark>
        <:status><DotLabel
            @label={{this.v.statusLabel}}
            @hue={{toneHue this.v.statusTone}}
          /></:status>
        <:default>
          <FitRow @label='Dates'><span class='mono'>{{orDash
                this.v.range
              }}</span></FitRow>
          <FitRow @label='Type'>{{orDash this.v.type}}</FitRow>
          {{#if this.v.fact}}<FitRow @left={{true}}><span
                class='meta'
              >{{this.v.fact}}</span></FitRow>{{/if}}
          {{#if @model.employee}}
            <FitRow @label='Employee' @left={{true}}><@fields.employee
                @format='atom'
                @displayContainer={{false}}
              /></FitRow>
          {{/if}}
          <StatStrip @compact={{true}} @items={{this.strip}} />
          <FitRow @label='Requested'><span class='mono'>{{orDash
                this.v.requested
              }}</span></FitRow>
          <FitRow @label='Approval'>{{this.v.approvalLong}}</FitRow>
          <FitRow @label='Reason'>{{orDash this.v.reasonShort}}</FitRow>
        </:default>
      </FitCard>
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
    get v() {
      return ptoView(this.args.model);
    }
    <template>
      <span class='pto-atom'>
        <PtoMark class='atom-mark' />
        <span class='pto-atom-name'>{{@model.title}}</span>
      </span>
      <style scoped>
        @layer PretComponent {
          .pto-atom {
            display: inline-flex;
            align-items: center;
            gap: var(--boxel-sp-4xs);
            max-width: 100%;
            vertical-align: middle;
            font-size: var(--boxel-font-size-xs);
            font-weight: 600;
            line-height: 1.5;
            color: var(--foreground);
            white-space: nowrap;
          }
          .atom-mark {
            --pto-mark-size: 1.25rem;
            --pto-mark-font-size: var(--boxel-font-size-2xs);
          }
          .pto-atom-name {
            min-width: 0;
            overflow: hidden;
            text-overflow: ellipsis;
          }
        }
      </style>
    </template>
  };
}
