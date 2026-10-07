import {
  CardDef,
  Component,
  contains,
  containsMany,
  field,
  linksTo,
  NumberField,
  StringField,
} from '@cardstack/base/card-api';
import enumField from '@cardstack/base/enum';
import FileTextIcon from '@cardstack/boxel-icons/file-text';
import { guidFor } from '@ember/object/internals';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { Table } from '@cardstack/pretui/components/table';
import { COMPACT_EMPTY_STYLE } from '@cardstack/catalog/components/pretui-helpers';
import { StatePill, type Hue } from '@cardstack/catalog/components/state-pill';
import { Money } from '@cardstack/catalog/cards/crm/money';
import { Deal } from './deal';
import { LineItem } from './line-item';
import { Proposal } from './proposal';
import { lineTotal, sumLineItems } from './line-item-totals';
import { hasNumber } from '@cardstack/catalog/cards/crm/utils';

// Quote — a priced proposal, not yet binding. Versioned: each negotiation
// round creates a NEW Quote with `supersedes` pointing at the previous one,
// which stays immutable. Line items are the shared `LineItem` field — a
// snapshot of description/qty/price at negotiation time, not live links to a
// price list.

const QuoteStatusField = enumField(StringField, {
  options: ['draft', 'sent', 'under-review', 'won', 'lost', 'expired'],
  displayName: 'Quote Status',
});

const QUOTE_STATUS_HUE: Record<string, Hue> = {
  sent: 'blue',
  'under-review': 'amber',
  won: 'green',
  lost: 'red',
  expired: 'red',
};

function quoteStatusHue(status: string | undefined): Hue {
  return (status && QUOTE_STATUS_HUE[status]) || 'slate';
}

function quoteCurrency(quote: Quote | undefined): string | undefined {
  return quote?.lineItems?.[0]?.unitPrice?.currency?.code;
}

export class Quote extends CardDef {
  static displayName = 'Quote';
  static icon = FileTextIcon;

  @field version = contains(NumberField);
  @field status = contains(QuoteStatusField);
  @field supersedes = linksTo(() => Quote);
  @field deal = linksTo(Deal);
  @field proposal = linksTo(Proposal);
  @field lineItems = containsMany(LineItem);

  @field total = contains(NumberField, {
    computeVia: function (this: Quote) {
      return sumLineItems(this.lineItems).total;
    },
  });

  @field cardTitle = contains(StringField, {
    computeVia: function (this: Quote) {
      let dealName = this.deal?.cardTitle;
      let v = this.version ? `v${this.version}` : undefined;
      if (!dealName) return `Untitled ${this.constructor.displayName}`;
      return v ? `${dealName} — Quote ${v}` : `${dealName} — Quote`;
    },
  });

  static atom = class Atom extends Component<typeof Quote> {
    <template>
      <span class='quote-atom'>
        <FileTextIcon class='qa-icon' />
        <span class='qa-name'>{{@model.cardTitle}}</span>
      </span>
      <style scoped>
        .quote-atom {
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
          font-size: 0.8125rem;
          font-weight: 500;
          color: var(--foreground);
        }
        .qa-icon {
          width: 0.875rem;
          height: 0.875rem;
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
        .qa-name {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof Quote> {
    get currency() {
      return quoteCurrency(this.args.model as Quote);
    }
    <template>
      <div class='quote-row'>
        <FileTextIcon class='icon' />
        <div class='info'>
          <span class='name'>{{@model.cardTitle}}</span>
          {{#if @model.status}}
            <StatePill
              class='status'
              @label={{@model.status}}
              @hue={{quoteStatusHue @model.status}}
            />
          {{/if}}
        </div>
        {{#if (hasNumber @model.total)}}
          <Money
            class='value'
            @amount={{@model.total}}
            @code={{this.currency}}
          />
        {{/if}}
      </div>
      <style scoped>
        .quote-row {
          display: flex;
          align-items: center;
          gap: 0.75rem;
          padding: 0.625rem 0.875rem;
          font-size: 0.875rem;
        }
        .icon {
          width: 1.25rem;
          height: 1.25rem;
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
        .info {
          min-width: 0;
          flex: 1;
          display: flex;
          flex-direction: column;
          gap: 0.125rem;
        }
        .name {
          font-weight: 600;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .status {
          align-self: flex-start;
          text-transform: capitalize;
        }
        .value {
          font-weight: 700;
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof Quote> {
    get currency() {
      return quoteCurrency(this.args.model as Quote);
    }
    <template>
      <div class='fitted'>
        <div class='fmt badge'>
          <FileTextIcon class='doc-icon' />
          <Money
            class='figure'
            @amount={{@model.total}}
            @code={{this.currency}}
          />
        </div>
        <div class='fmt strip'>
          <FileTextIcon class='doc-icon' />
          <div class='info'>
            <span class='name'>{{@model.cardTitle}}</span>
            {{#if @model.status}}
              <StatePill
                class='status'
                @label={{@model.status}}
                @hue={{quoteStatusHue @model.status}}
              />
            {{/if}}
          </div>
          <Money
            class='figure'
            @amount={{@model.total}}
            @code={{this.currency}}
          />
        </div>
      </div>
      <style scoped>
        .fitted {
          width: 100%;
          height: 100%;
          color: var(--foreground);
        }
        .fmt {
          display: none;
          width: 100%;
          height: 100%;
          box-sizing: border-box;
          overflow: hidden;
        }
        .doc-icon {
          width: 1.25rem;
          height: 1.25rem;
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
        .name {
          font-weight: 600;
          font-size: 0.8125rem;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .figure {
          font-weight: 700;
          font-variant-numeric: tabular-nums;
          font-size: 0.875rem;
          white-space: nowrap;
        }
        .info {
          display: flex;
          flex-direction: column;
          gap: 0.125rem;
          min-width: 0;
          flex: 1;
        }
        .status {
          align-self: flex-start;
          text-transform: capitalize;
        }
        @container fitted-card (max-width: 150px) and (max-height: 169px) {
          .badge {
            display: flex;
            flex-direction: column;
            justify-content: center;
            gap: 0.375rem;
            padding: 0.5rem;
            text-align: center;
          }
        }
        @container fitted-card (min-width: 151px) and (max-height: 169px) {
          .strip {
            display: flex;
            align-items: center;
            gap: 0.625rem;
            padding: 0.625rem 0.75rem;
          }
        }
      </style>
    </template>
  };

  static isolated = class Isolated extends Component<typeof Quote> {
    itemsId = `${guidFor(this)}-items`;

    get rows() {
      return (this.args.model?.lineItems ?? []).map((item) => ({
        description: item?.description || '—',
        quantity: item?.quantity ?? 0,
        unit: item?.unitPrice?.amount,
        total: lineTotal(item),
        code: item?.unitPrice?.currency?.code,
      }));
    }
    get currency() {
      return quoteCurrency(this.args.model as Quote);
    }
    <template>
      <article class='quote-doc'>
        <header class='doc-head'>
          <div>
            <p class='doc-kind'>Quote</p>
            <h1>{{@model.cardTitle}}</h1>
          </div>
          {{#if @model.status}}
            <StatePill
              class='status'
              @label={{@model.status}}
              @hue={{quoteStatusHue @model.status}}
            />
          {{/if}}
        </header>

        {{#if @model.supersedes}}
          <p class='superseded-note'>Supersedes
            <@fields.supersedes @format='atom' /></p>
        {{/if}}

        <section class='items'>
          <h2 id={{this.itemsId}}>Line items</h2>
          {{#if this.rows.length}}
            <Table class='lines' @labelledBy={{this.itemsId}}>
              <:head>
                <tr>
                  <th scope='col' class='t-desc'>Item</th>
                  <th scope='col' class='t-num'>Qty</th>
                  <th scope='col' class='t-num'>Unit</th>
                  <th scope='col' class='t-num'>Amount</th>
                </tr>
              </:head>
              <:body>
                {{#each this.rows as |row|}}
                  <tr>
                    <td class='t-desc'>{{row.description}}</td>
                    <td class='t-num'>{{row.quantity}}</td>
                    <td class='t-num'><Money
                        @amount={{row.unit}}
                        @code={{row.code}}
                      /></td>
                    <td class='t-num t-strong'><Money
                        @amount={{row.total}}
                        @code={{row.code}}
                      /></td>
                  </tr>
                {{/each}}
                <tr class='t-total-row'>
                  <th scope='row' class='t-desc' colspan='3'>Total</th>
                  <td class='t-num t-total'><Money
                      @amount={{@model.total}}
                      @code={{this.currency}}
                    /></td>
                </tr>
              </:body>
            </Table>
          {{else}}
            <EmptyState
              @title='No line items yet'
              @texture={{false}}
              style={{COMPACT_EMPTY_STYLE}}
            />
          {{/if}}
        </section>
      </article>
      <style scoped>
        .quote-doc {
          max-width: 46rem;
          margin: 0 auto;
          padding: 2rem 1.5rem;
          display: flex;
          flex-direction: column;
          gap: 1.5rem;
        }
        .doc-head {
          display: flex;
          align-items: flex-end;
          justify-content: space-between;
          gap: 1rem;
          border-bottom: 2px solid var(--foreground);
          padding-bottom: 1rem;
        }
        .doc-kind {
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          margin: 0 0 0.125rem;
          color: var(--muted-foreground);
        }
        h1 {
          margin: 0;
          font-size: 1.75rem;
          line-height: 1.1;
        }
        .status {
          text-transform: capitalize;
        }
        .superseded-note {
          font-size: 0.8125rem;
          color: var(--muted-foreground);
          margin: 0;
        }
        .items {
          display: flex;
          flex-direction: column;
          gap: 0.75rem;
        }
        h2 {
          margin: 0;
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .lines {
          --boxel-font-size-xs: 0.875rem;
        }
        .t-desc {
          text-align: start;
        }
        .t-num {
          text-align: end;
          font-variant-numeric: tabular-nums;
          white-space: nowrap;
        }
        .t-strong {
          font-weight: 600;
        }
        .t-total-row > * {
          border-top: 0.125rem solid var(--foreground);
          font-weight: 700;
        }
        .t-total {
          font-size: 1.125rem;
        }
      </style>
    </template>
  };
}
