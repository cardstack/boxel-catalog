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
import type { TemplateOnlyComponent } from '@ember/component/template-only';
import { htmlSafe } from '@ember/template';
import { Chip } from '../../ui-component/components/chip';
import {
  Descriptions,
  type DescriptionsItem,
} from '../../ui-component/components/descriptions';
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
import { RecordIsolated, mediumDate } from '../procurement/vendor';

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

// Status then type as soft pills: the chip set the embedded format prints.
const PtoChips: TemplateOnlyComponent<{
  Args: { model?: Partial<PtoRequest> };
  Element: HTMLSpanElement;
}> = <template>
  {{#let (ptoView @model) as |v|}}
    <span class='pto-chips' ...attributes>
      <Chip
        @tone={{v.statusTone}}
        @appearance='soft'
        @shape='pill'
        @dot={{false}}
      >{{v.statusLabel}}</Chip>
      {{#if v.type}}<Chip
          @appearance='soft'
          @shape='pill'
          @dot={{false}}
        >{{v.type}}</Chip>{{/if}}
    </span>
  {{/let}}
  <style scoped>
    @layer PretComponent {
      .pto-chips {
        display: flex;
        flex-wrap: wrap;
        justify-content: flex-end;
        gap: var(--boxel-sp-4xs);
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

  <template>
    <RecordIsolated @title={{@model.title}} @subtitle={{this.v.subtitle}}>
      <:avatar><PtoMark class='iso-mark' /></:avatar>
      <:chips><PtoChips @model={{@model}} /></:chips>
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
          <KeyValue @items={{this.detailItems}} @rows='ruled' />
        </Panel>
      </:side>
    </RecordIsolated>
    <style scoped>
      @layer PretComponent {
        .iso-mark {
          --pto-mark-size: 3rem;
          --pto-mark-font-size: var(--boxel-font-size-sm);
        }
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
    <template>
      <article class='pto-embedded'>
        <header class='emb-head'>
          <PtoMark />
          <div class='emb-id'>
            <h3 class='emb-title'>{{@model.title}}</h3>
            {{#if this.v.subtitle}}<p
                class='emb-sub'
              >{{this.v.subtitle}}</p>{{/if}}
          </div>
          <PtoChips class='emb-chips' @model={{@model}} />
        </header>
        {{#if this.v.fact}}<p class='emb-fact'>{{this.v.fact}}</p>{{/if}}
        <Descriptions
          class='emb-kv'
          @items={{this.gridFacts}}
          @layout='vertical'
          @columns={{3}}
        >
          <:value as |row|><span class='v'>{{row.value}}</span></:value>
        </Descriptions>
        {{#if @model.employee}}
          <div class='emb-rels'>
            <span class='rel'>Employee
              <@fields.employee
                @format='atom'
                @displayContainer={{false}}
              /></span>
            {{#each @fields.approvalChain.steps as |Step|}}
              <span class='rel'>Approver
                <Step.approver
                  @format='atom'
                  @displayContainer={{false}}
                /></span>
            {{/each}}
          </div>
        {{/if}}
      </article>
      <style scoped>
        @layer PretComponent {
          .pto-embedded {
            container-type: inline-size;
            display: flex;
            flex-direction: column;
            gap: var(--boxel-sp-sm);
            padding: var(--boxel-sp);
            background-color: var(--card);
            color: var(--card-foreground);
          }
          .emb-head {
            display: flex;
            align-items: center;
            gap: var(--boxel-sp-sm);
          }
          .emb-id {
            flex: 1 1 0;
            min-width: 0;
          }
          .emb-title {
            margin: 0;
            font-size: var(--boxel-font-size-sm);
            font-weight: 600;
            line-height: 1.25;
            overflow-wrap: anywhere;
          }
          .emb-sub,
          .emb-fact {
            margin: var(--boxel-sp-6xs) 0 0;
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          .emb-fact {
            margin: 0;
          }
          .emb-kv {
            padding-top: var(--boxel-sp-sm);
            border-top: 1px solid var(--border);
          }
          .v {
            font-weight: 600;
            font-variant-numeric: tabular-nums;
          }
          .emb-rels {
            display: flex;
            flex-wrap: wrap;
            align-items: center;
            gap: var(--boxel-sp-xs) var(--boxel-sp);
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          .rel {
            display: inline-flex;
            align-items: center;
            gap: var(--boxel-sp-xs);
            min-width: 0;
            max-width: 100%;
          }
          @container (max-width: 25rem) {
            .emb-head {
              flex-wrap: wrap;
            }
            .emb-chips {
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
    <template>
      <article class='fit'>
        <header class='who'>
          <PtoMark class='mark' />
          <div class='id'>
            <div class='line1'>
              <h3 class='title'>{{@model.title}}</h3>
              <span class='chips chips-inline'>
                <Chip
                  @tone={{this.v.statusTone}}
                  @appearance='soft'
                  @shape='pill'
                  @dot={{false}}
                >{{this.v.statusLabel}}</Chip>
                {{#if this.v.type}}<Chip
                    class='chip-extra'
                    @appearance='soft'
                    @shape='pill'
                    @dot={{false}}
                  >{{this.v.type}}</Chip>{{/if}}
              </span>
            </div>
            <p class='sub'>{{this.v.subtitle}}</p>
          </div>
        </header>
        <span class='chips chips-row'>
          <Chip
            @tone={{this.v.statusTone}}
            @appearance='soft'
            @shape='pill'
            @dot={{false}}
          >{{this.v.statusLabel}}</Chip>
          {{#if this.v.type}}<Chip
              class='chip-extra'
              @appearance='soft'
              @shape='pill'
              @dot={{false}}
            >{{this.v.type}}</Chip>{{/if}}
        </span>
        {{#if this.v.fact}}<p class='fact'>{{this.v.fact}}</p>{{/if}}
        <dl class='stats'>
          <div><dt>Days</dt><dd>{{if this.v.days this.v.days '—'}}</dd></div>
          <div><dt>Type</dt><dd>{{orDash this.v.type}}</dd></div>
          <div><dt>Approval</dt><dd>{{orDash this.v.approvalShort}}</dd></div>
        </dl>
        {{#if this.v.approvalShort}}
          <div class='meter'>
            <span class='meter-label'><span>Approval</span><span
              >{{this.v.approvalShort}}</span></span>
            <span class='meter-bar' aria-hidden='true'><span
                style={{htmlSafe (concat 'inline-size:' this.v.progress '%')}}
              ></span></span>
          </div>
        {{/if}}
        <dl class='kv'>
          {{#each this.kvFacts as |f|}}
            <div class='kv-i'><dt>{{f.label}}</dt><dd>{{f.value}}</dd></div>
          {{/each}}
        </dl>
        <ul class='rels'>
          {{#if @model.employee}}
            <li><span class='k'>Employee</span><@fields.employee
                @format='atom'
                @displayContainer={{false}}
              /></li>
          {{/if}}
          {{#each @fields.approvalChain.steps as |Step|}}
            <li><span class='k'>Approver</span><Step.approver
                @format='atom'
                @displayContainer={{false}}
              /></li>
          {{/each}}
        </ul>
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
          .chip-extra,
          .kv,
          .rels .k,
          .stats,
          .meter {
            display: none;
          }
          .chips-inline {
            flex: none;
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
          /* a link that doesn't fit wraps into a second column, which the
             overflow clips, so no row ever shows half */
          .rels {
            display: flex;
            flex: 1 1 0;
            flex-flow: column wrap;
            align-content: flex-start;
            min-block-size: 0;
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
            flex: none;
            inline-size: 100%;
            block-size: 1.375rem;
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
          /* the level and remote chips join the status from 250 wide */
          @container fitted-card (width >= 250px) {
            .chip-extra {
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
            .chip-extra {
              display: none;
            }
          }
          /* a pill strip under 400 wide keeps the status only; in the
             chip's dot + text form (under 65 tall or 150 wide) the level
             rides along, the remote flag does not */
          @container fitted-card (65px <= height < 105px) and (150px < width < 400px) {
            .chip-level {
              display: none;
            }
          }
          @container fitted-card (height < 105px) and (width < 400px) {
            .chip-extra {
              display: none;
            }
          }

          .stats {
            grid-template-columns: repeat(3, minmax(0, 1fr));
            gap: var(--_fit-gap);
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          .stats dd {
            margin: 0;
            font-size: var(--boxel-font-size-sm);
            font-weight: 600;
            color: var(--foreground);
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
          }
          .stats dt {
            margin: 0;
          }
          .meter {
            gap: var(--_fit-hair);
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          .meter-bar {
            block-size: 0.25rem;
            border-radius: var(--boxel-border-radius-pill);
            background: var(--muted);
            overflow: hidden;
          }
          .meter-bar > span {
            display: block;
            block-size: 100%;
            background: var(--primary);
          }
          .chips > * {
            flex: none;
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
          /* 400 tall: the headline numbers and approval progress lead */
          @container fitted-card (height >= 400px) {
            .stats,
            .meter {
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
    get v() {
      return ptoView(this.args.model);
    }
    <template>
      <span class='pto-atom'>
        <PtoMark class='atom-mark' />
        <span class='pto-atom-name'>{{@model.title}}</span>
        <StatusChip
          @value={{this.v.statusLabel}}
          @tone={{this.v.statusTone}}
          @appearance='soft'
          @shape='pill'
          @dot={{false}}
        />
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
