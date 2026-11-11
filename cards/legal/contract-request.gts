import { markDefinition } from '@cardstack/base/mark-definition';
import {
  CardDef,
  field,
  contains,
  linksTo,
  Component,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import DateField from '@cardstack/base/date';
import TextAreaField from '@cardstack/base/text-area';
import BooleanField from '@cardstack/base/boolean';
import AmountWithCurrency from '@cardstack/base/amount-with-currency';
import enumField from '@cardstack/base/enum';
import ClipboardCheckIcon from '@cardstack/boxel-icons/clipboard-check';

import { ContractTypeField, contractTypeLabel } from './contract-type';
import { Employee } from '../hr/employee';
import { Account } from '../crm/account';
import { Contract } from './contract';
import { formatMoney } from '../commerce/line-item-totals';
import {
  AtomLayout,
  Dots,
  EmbLayout,
  Facts,
  FitLayout,
  IsoLayout,
  LinkRow,
  Mark,
  Section,
  Text,
  stats,
  type Dot,
  type Fact,
} from './compact-card';
import {
  dash,
  dayAndYear,
  formatDay,
  longMoney,
  shortMoney,
  type Tone,
} from '../shared/compact-format';
import { IsoFrame } from '../shared/compact-sheet';

/**
 * CONTRACT REQUEST — self-service intake for a new contract.
 *
 * WHY A CARD RATHER THAN A FORM ON THE APP. A request has a life of its own:
 * it is submitted, triaged, accepted or declined, and eventually points at the
 * contract it produced. A form that wrote straight into a Contract would lose
 * the decline case entirely — and "what did we refuse to paper, and why" is a
 * question legal teams get asked.
 *
 * WHAT IS CONSUMED. `ContractTypeField`, `Employee`, `Account`, `StatePill`,
 * `formatMoney` — no new vocabulary for any of them.
 */

export const REQUEST_STATES = [
  { value: 'draft', label: 'Draft', hue: 'slate' },
  { value: 'submitted', label: 'Submitted', hue: 'blue' },
  { value: 'in_triage', label: 'In triage', hue: 'amber' },
  { value: 'accepted', label: 'Accepted', hue: 'green' },
  { value: 'declined', label: 'Declined', hue: 'red' },
] as const;

export const RequestStateField = markDefinition(
  enumField(StringField, {
    options: REQUEST_STATES.map((r) => ({ value: r.value, label: r.label })),
    displayName: 'Request State',
    icon: ClipboardCheckIcon,
  }),
);

export function requestStateLabel(v?: string | null): string {
  return REQUEST_STATES.find((s) => s.value === v)?.label ?? v ?? 'Draft';
}

export function requestStateHue(v?: string | null): string {
  return REQUEST_STATES.find((s) => s.value === v)?.hue ?? 'slate';
}

export class ContractRequest extends CardDef {
  static displayName = 'Contract Request';
  static icon = ClipboardCheckIcon;

  @field whatFor = contains(StringField);
  @field contractType = contains(ContractTypeField);
  @field counterparty = linksTo(() => Account);
  @field requestedBy = linksTo(() => Employee);
  @field estimatedValue = contains(AmountWithCurrency);
  @field neededBy = contains(DateField);
  @field background = contains(TextAreaField);

  /** Routes the request through data-sensitivity review from intake on. */
  @field involvesSensitiveData = contains(BooleanField);

  @field status = contains(RequestStateField);

  /** Why it was declined. Required in practice, not enforced by the schema. */
  @field decisionNote = contains(TextAreaField);

  /** Set once the request produced a contract, so the trail joins up. */
  @field resultingContract = linksTo(() => Contract);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: ContractRequest) {
      return this.whatFor ?? 'Untitled request';
    },
  });

  @field cardDescription = contains(StringField, {
    computeVia: function (this: ContractRequest) {
      let bits = [contractTypeLabel(this.contractType)];
      let v = formatMoney(
        this.estimatedValue?.amount,
        this.estimatedValue?.currency?.code,
      );
      if (v) bits.push(v);
      return bits.filter(Boolean).join(' · ');
    },
  });

  static isolated = class Isolated extends Component<typeof ContractRequest> {
    get v() {
      return requestView(this.args.model);
    }
    <template>
      <IsoFrame>
        <IsoLayout
          @title={{this.v.title}}
          @subtitle={{this.v.subtitle}}
          @statuses={{this.v.statuses}}
          @stats={{this.v.stats}}
        >
          <:mark><Mark @text='Rq' @size='lg' /></:mark>
          <:main>
            {{#if @model.background}}
              <Section @title='Background'><Text
                >{{@model.background}}</Text></Section>
            {{/if}}
            {{#if @model.decisionNote}}
              <Section @title='Decision'><Text
                >{{@model.decisionNote}}</Text></Section>
            {{/if}}
            <Section @title='Request'><Facts
                @items={{this.v.request}}
              /></Section>
            <Section @title='Status' @flush={{true}}><Dots
                @items={{this.v.lifecycle}}
              /></Section>
          </:main>
          <:side>
            <Section @title='Linked'>
              <LinkRow @label='Requested by'><@fields.requestedBy
                  @format='atom'
                  @displayContainer={{false}}
                /></LinkRow>
              {{#if @model.counterparty}}
                <LinkRow @label='Counterparty'><@fields.counterparty
                    @format='atom'
                    @displayContainer={{false}}
                  /></LinkRow>
              {{/if}}
              {{#if @model.resultingContract}}
                <LinkRow @label='Contract'><@fields.resultingContract
                    @format='atom'
                    @displayContainer={{false}}
                  /></LinkRow>
              {{/if}}
            </Section>
            <Section @title='Details'><Facts
                @items={{this.v.facts}}
              /></Section>
          </:side>
        </IsoLayout>
      </IsoFrame>
    </template>
  };

  static embedded = class Embedded extends Component<typeof ContractRequest> {
    get v() {
      return requestView(this.args.model);
    }
    <template>
      <EmbLayout
        @title={{this.v.title}}
        @subtitle={{this.v.subtitle}}
        @status={{this.v.state}}
        @fact={{this.v.fact}}
        @facts={{this.v.facts}}
      >
        <:mark><Mark @text='Rq' /></:mark>
        <:linked>
          <LinkRow @label='Requested by'><@fields.requestedBy
              @format='atom'
              @displayContainer={{false}}
            /></LinkRow>
        </:linked>
      </EmbLayout>
    </template>
  };

  static fitted = class Fitted extends Component<typeof ContractRequest> {
    get v() {
      return requestView(this.args.model);
    }
    <template>
      <FitLayout
        @title={{this.v.title}}
        @subtitle={{this.v.subtitle}}
        @status={{this.v.state}}
        @fact={{this.v.fact}}
        @facts={{this.v.facts}}
        @stats={{this.v.fitStats}}
      >
        <:mark><Mark @text='Rq' /></:mark>
      </FitLayout>
    </template>
  };

  static atom = class Atom extends Component<typeof ContractRequest> {
    <template>
      <AtomLayout @title={{@model.cardTitle}}><:mark><Mark
            @text='Rq'
            @size='sm'
          /></:mark></AtomLayout>
    </template>
  };
}

const REQUEST_TONE: Record<string, Tone> = {
  draft: 'neutral',
  submitted: 'info',
  in_triage: 'warning',
  accepted: 'success',
  declined: 'danger',
};

/** The strings every ContractRequest format shows, read once from the model. */
function requestView(m?: Partial<ContractRequest>) {
  let type = contractTypeLabel(m?.contractType);
  let amount = m?.estimatedValue?.amount;
  let code = m?.estimatedValue?.currency?.code;
  let status = m?.status ?? 'draft';
  let label = requestStateLabel(status);
  let who = m?.requestedBy?.cardTitle as string | undefined;
  let sensitive = Boolean(m?.involvesSensitiveData);
  let [day, year] = dayAndYear(m?.neededBy);
  let state: Dot = { label: label.toLowerCase(), tone: REQUEST_TONE[status] };
  let decision =
    status === 'accepted' || status === 'declined' ? label : 'not yet';
  return {
    title: m?.cardTitle ?? 'Untitled request',
    subtitle: [type, who ? `requested by ${who}` : undefined]
      .filter(Boolean)
      .join(' · '),
    state,
    statuses: [
      state,
      ...(sensitive ? [{ label: 'sensitive data', tone: 'warning' }] : []),
    ] as Dot[],
    fact: [
      m?.neededBy ? `Needed by ${formatDay(m.neededBy)}` : undefined,
      typeof amount === 'number'
        ? `${longMoney(amount, code)} estimated`
        : undefined,
    ]
      .filter(Boolean)
      .join(' · '),
    stats: stats([
      {
        label: 'Estimate',
        value: shortMoney(amount, code),
        hint: type.toLowerCase(),
      },
      { label: 'Needed by', value: day, hint: year },
      {
        label: 'Sensitive data',
        value: sensitive ? 'Yes' : 'No',
        hint: sensitive ? 'review at intake' : undefined,
      },
    ]),
    fitStats: [
      { key: 'Estimate', value: shortMoney(amount, code) },
      { key: 'Needed by', value: day },
      { key: 'Sensitive', value: sensitive ? 'Yes' : 'No' },
    ],
    request: [
      { key: 'What for', value: dash(m?.whatFor) },
      { key: 'Contract type', value: type },
      { key: 'Estimated value', value: longMoney(amount, code), mono: true },
      { key: 'Needed by', value: formatDay(m?.neededBy), mono: true },
      { key: 'Sensitive data', value: sensitive ? 'Yes' : 'No' },
    ] as Fact[],
    lifecycle: REQUEST_STATES.map((s) => ({
      label: s.label.toLowerCase(),
      tone: s.value === status ? REQUEST_TONE[s.value] : 'neutral',
    })) as Dot[],
    facts: [
      { key: 'Estimated value', value: longMoney(amount, code), mono: true },
      { key: 'Needed by', value: formatDay(m?.neededBy), mono: true },
      { key: 'Type', value: type },
      { key: 'Sensitive data', value: sensitive ? 'Yes' : 'No' },
      { key: 'Status', value: label },
      { key: 'Decision', value: decision },
    ] as Fact[],
  };
}
