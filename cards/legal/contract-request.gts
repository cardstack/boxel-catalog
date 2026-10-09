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
import TriangleAlertIcon from '@cardstack/boxel-icons/triangle-alert';
import FileTextIcon from '@cardstack/boxel-icons/file-text';
import ScrollTextIcon from '@cardstack/boxel-icons/scroll-text';

import {
  ContractTypeField,
  contractTypeLabel,
} from '@cardstack/catalog/cards/legal/contract-type';
import { Employee } from '@cardstack/catalog/cards/hr/employee';
import { Account } from '@cardstack/catalog/cards/crm/account';
import { Contract } from '@cardstack/catalog/cards/legal/contract';
import { ALERT_STYLE } from '@cardstack/catalog/components/pretui-helpers';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import type { Hue } from '@cardstack/catalog/components/state-pill';
import { formatMoney } from '@cardstack/catalog/cards/commerce/line-item-totals';
import { Alert } from '@cardstack/pretui/components/alert';
import { FormatDate } from '@cardstack/pretui/components/format-date';
import { KeyValue } from '@cardstack/pretui/components/key-value';
import { FieldContainer } from '@cardstack/boxel-ui/components';
import { eq } from '@cardstack/boxel-ui/helpers';
import { SectionedEdit } from '@cardstack/catalog/components/sectioned-edit';

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

export const RequestStateField = enumField(StringField, {
  options: REQUEST_STATES.map((r) => ({ value: r.value, label: r.label })),
  displayName: 'Request State',
  icon: ClipboardCheckIcon,
});

export function requestStateLabel(v?: string | null): string {
  return REQUEST_STATES.find((s) => s.value === v)?.label ?? v ?? 'Draft';
}

export function requestStateHue(v?: string | null): Hue {
  return (REQUEST_STATES.find((s) => s.value === v)?.hue ?? 'slate') as Hue;
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

  /**
   * The domain question: "should we paper this, and by when?"
   *
   * The deadline is the hero because it is what makes the request urgent or
   * not, and a declined request keeps its reason at the top rather than buried
   * — "what did we refuse, and why" is the thing people come back to ask.
   */
  /**
   * Edit — the intake form: what someone needs, how big and how soon, and what legal decided.
   * Grouped by task, not schema order; SectionedEdit gives it the
   * section rail.
   */
  static edit = class Edit extends Component<typeof ContractRequest> {
    sections = [
      { id: 'ask', label: 'The ask' },
      { id: 'scope', label: 'Scope & timing' },
      { id: 'decision', label: 'Legal decision' },
    ];

    <template>
      <SectionedEdit
        @sections={{this.sections}}
        @ariaLabel='Contract Request sections'
        as |e|
      >
        <e.Section @id='ask' @title='The ask'>
          <FieldContainer @label='What the contract is for' @vertical={{true}}>
            <@fields.whatFor />
          </FieldContainer>
          <div class='row cols-3'>
            <FieldContainer @label='Type' @vertical={{true}}>
              <@fields.contractType />
            </FieldContainer>
            <FieldContainer @label='Counterparty' @vertical={{true}}>
              <@fields.counterparty />
            </FieldContainer>
            <FieldContainer @label='Requested by' @vertical={{true}}>
              <@fields.requestedBy />
            </FieldContainer>
          </div>
        </e.Section>
        <e.Section @id='scope' @title='Scope & timing'>
          <div class='row cols-3'>
            <FieldContainer @label='Estimated value' @vertical={{true}}>
              <@fields.estimatedValue />
            </FieldContainer>
            <FieldContainer @label='Needed by' @vertical={{true}}>
              <@fields.neededBy />
            </FieldContainer>
            <FieldContainer @label='Involves sensitive data' @vertical={{true}}>
              <@fields.involvesSensitiveData />
            </FieldContainer>
          </div>
          <FieldContainer @label='Background' @vertical={{true}}>
            <@fields.background />
          </FieldContainer>
        </e.Section>
        <e.Section
          @id='decision'
          @title='Legal decision'
          @hint='the intake outcome; the resulting contract links once drafted'
        >
          <div class='row cols-2'>
            <FieldContainer @label='Status' @vertical={{true}}>
              <@fields.status />
            </FieldContainer>
            <FieldContainer @label='Resulting contract' @vertical={{true}}>
              <@fields.resultingContract />
            </FieldContainer>
          </div>
          <FieldContainer @label='Decision note' @vertical={{true}}>
            <@fields.decisionNote />
          </FieldContainer>
        </e.Section>
      </SectionedEdit>
      <style scoped>
        .hint {
          margin: 0.25rem 0 0;
          font-size: 0.75rem;
          color: var(--muted-foreground);
        }
        .row {
          display: grid;
          gap: var(--boxel-sp-sm);
          align-items: start;
        }
        .row.cols-2 {
          grid-template-columns: repeat(2, minmax(0, 1fr));
        }
        .row.cols-3 {
          grid-template-columns: repeat(3, minmax(0, 1fr));
        }
        .row.cols-4 {
          grid-template-columns: repeat(4, minmax(0, 1fr));
        }
        @container edit (width < 640px) {
          .row.cols-2,
          .row.cols-3,
          .row.cols-4 {
            grid-template-columns: 1fr;
          }
        }
      </style>
    </template>
  };

  static isolated = class Isolated extends Component<typeof ContractRequest> {
    get declined() {
      return this.args.model?.status === 'declined';
    }
    get glance() {
      let m = this.args.model;
      return [
        { key: 'Estimated value', value: this.money },
        { key: 'Requested by', value: m.requestedBy?.cardTitle ?? '—' },
        {
          key: 'Counterparty',
          value: m.counterparty?.cardTitle ?? 'Not named yet',
        },
      ];
    }

    get money(): string {
      return (
        formatMoney(
          this.args.model?.estimatedValue?.amount,
          this.args.model?.estimatedValue?.currency?.code,
        ) || '—'
      );
    }
    <template>
      <article class='cr-page'>
        <header class='hero'>
          <div class='hero-id'>
            <p class='kicker'><ClipboardCheckIcon role='presentation' />Contract
              request</p>
            <h1>{{@model.whatFor}}</h1>
            <div class='hero-pills'>
              <StatePill
                @label={{requestStateLabel @model.status}}
                @hue={{requestStateHue @model.status}}
                @dot={{true}}
              />
              <StatePill
                @label={{contractTypeLabel @model.contractType}}
                @hue='slate'
              />
              {{#if @model.involvesSensitiveData}}
                <StatePill @label='Sensitive data' @hue='amber' @dot={{true}} />
              {{/if}}
            </div>
          </div>
          <div class='hero-figure'>
            <span class='fig-n'>{{#if @model.neededBy}}<FormatDate
                  @date={{@model.neededBy}}
                  @dateStyle='medium'
                />{{else}}—{{/if}}</span>
            <span class='fig-u'>needed by</span>
          </div>
        </header>

        {{#if this.declined}}
          <section class='panel is-declined'>
            <h2><TriangleAlertIcon role='presentation' />Declined</h2>
            {{#if @model.decisionNote}}
              <p class='prose'>{{@model.decisionNote}}</p>
            {{else}}
              <Alert
                @tone='attention'
                @title='No reason recorded'
                style={{ALERT_STYLE.attention}}
              >A decline without a reason cannot be appealed or learned from.
                Write one.</Alert>
            {{/if}}
          </section>
        {{/if}}

        <KeyValue
          class='glance'
          @items={{this.glance}}
          @layout='inline'
          @labelStyle='eyebrow'
        >
          <:value as |item|>
            <span
              class={{if (eq item.key 'Estimated value') 'is-money'}}
            >{{item.value}}</span>
          </:value>
        </KeyValue>

        {{#if @model.background}}
          <section class='panel'>
            <h2><FileTextIcon role='presentation' />Background</h2>
            <p class='prose'>{{@model.background}}</p>
          </section>
        {{/if}}

        {{#if @model.resultingContract}}
          <section class='panel'>
            <h2><ScrollTextIcon role='presentation' />Became</h2>
            <@fields.resultingContract @format='fitted' />
          </section>
        {{else if this.declined}}{{else}}
          <p class='caveat'>No contract linked yet. Once this request produces
            one, link it here so the trail from ask to agreement joins up.</p>
        {{/if}}
      </article>

      <style scoped>
        .cr-page {
          container-type: inline-size;
          container-name: cr-page;
          --panel-bg: color-mix(in oklch, var(--foreground) 3%, transparent);
          height: 100%;
          overflow-y: auto;
          padding: var(--boxel-sp-lg);
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp);
          color: var(--foreground);
          font-family: var(--font-sans);
        }
        .hero {
          display: flex;
          align-items: flex-start;
          justify-content: space-between;
          gap: var(--boxel-sp-lg);
          border-bottom: 2px solid var(--foreground);
          padding-bottom: var(--boxel-sp);
        }
        .hero-id {
          display: flex;
          flex-direction: column;
          gap: 6px;
          min-width: 0;
          flex: 1 1 auto;
        }
        .hero-pills {
          display: flex;
          flex-wrap: wrap;
          gap: 6px;
        }
        .kicker {
          margin: 0;
          display: flex;
          align-items: center;
          gap: 6px;
          font-size: var(--boxel-font-size-xs);
          letter-spacing: 0.12em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .kicker :deep(svg) {
          width: max(14px, 1em);
          height: max(14px, 1em);
        }
        /* The heading is the one shout. The figure on the right supports it
           and is deliberately smaller — a card is opened for the thing it IS,
           and the number qualifies that rather than replacing it. */
        .hero h1 {
          margin: 0;
          font-size: var(--boxel-font-size-xl);
          font-weight: 700;
          line-height: 1.15;
          letter-spacing: -0.015em;
        }
        .hero-figure {
          flex: 0 1 auto;
          min-width: 0;
          text-align: right;
          line-height: 1;
        }
        .fig-n {
          display: block;
          font-family: var(--font-mono);
          font-variant-numeric: tabular-nums;
          font-size: 1.45rem;
          font-weight: 600;
          letter-spacing: -0.02em;
          white-space: nowrap;
        }
        .fig-u {
          display: block;
          margin-top: 4px;
          font-size: var(--boxel-font-size-xs);
          text-transform: uppercase;
          letter-spacing: 0.1em;
          color: var(--muted-foreground);
        }
        .glance {
          gap: var(--boxel-sp-xs) var(--boxel-sp-lg);
        }
        .is-money {
          font-family: var(--font-mono);
          font-variant-numeric: tabular-nums;
          white-space: nowrap;
        }
        .panel {
          padding: var(--boxel-sp) var(--boxel-sp-lg) var(--boxel-sp-lg);
          border-radius: var(--radius);
          background: var(--panel-bg);
        }
        /* Tint differs to mark a different KIND of block; padding and radius
           stay identical so every panel stays registered with the others. */
        .panel.is-declined {
          background: color-mix(
            in oklch,
            var(--destructive-ink) 8%,
            transparent
          );
        }
        .panel h2 {
          display: flex;
          align-items: center;
          gap: 8px;
          margin: 0 0 var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-sm);
          font-weight: 700;
          letter-spacing: 0.04em;
          text-transform: uppercase;
        }
        .panel h2 :deep(svg) {
          width: max(14px, 1em);
          height: max(14px, 1em);
          color: var(--muted-foreground);
        }
        .prose {
          margin: 0;
          font-size: var(--boxel-font-size);
          line-height: 1.6;
          max-width: 68ch;
        }
        .caveat {
          margin: 0;
          font-size: var(--boxel-font-size-sm);
          line-height: 1.5;
          color: var(--muted-foreground);
          max-width: 68ch;
        }
        @container cr-page (width < 560px) {
          .hero {
            flex-direction: column;
            align-items: flex-start;
            gap: var(--boxel-sp);
          }
          .hero-figure {
            text-align: left;
          }
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof ContractRequest> {
    <template>
      <article class='fit'>
        <span class='r-head'>
          <StatePill
            @label={{requestStateLabel @model.status}}
            @hue={{requestStateHue @model.status}}
            @dot={{true}}
          />
        </span>
        <span class='r-body'>{{@model.cardTitle}}</span>
        <span class='r-meta'>{{@model.cardDescription}}</span>
      </article>

      <style scoped>
        .fit {
          width: 100%;
          height: 100%;
          display: grid;
          grid-template-rows: auto minmax(0, 1fr) auto;
          gap: 2px;
          padding: var(--boxel-sp-xxs) var(--boxel-sp-xs);
          overflow: hidden;
          font-family: var(--font-sans);
          --type-base: clamp(10px, min(calc(3px + 2.1cqi + 1cqb), 10cqb), 15px);
        }
        .r-head,
        .r-body,
        .r-meta {
          overflow: hidden;
          min-height: 0;
        }
        .r-body {
          font-size: calc(var(--type-base) * 1.2);
          font-weight: 650;
          line-height: 1.2;
          display: -webkit-box;
          -webkit-box-orient: vertical;
          -webkit-line-clamp: 2;
        }
        .r-meta {
          font-size: var(--type-base);
          color: var(--muted-foreground);
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        @container fitted-card (height <= 65px) {
          .r-meta {
            display: none;
          }
        }
        @container fitted-card (height <= 45px) {
          .r-head {
            display: none;
          }
        }
      </style>
    </template>
  };
}
