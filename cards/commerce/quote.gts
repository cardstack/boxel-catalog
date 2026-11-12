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
import { concat } from '@ember/helper';
import { guidFor } from '@ember/object/internals';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { KeyValue } from '@cardstack/pretui/components/key-value';
import { Stat } from '@cardstack/pretui/components/stat';
import { StatusChip } from '@cardstack/pretui/components/status-chip';
import { FitTile } from '../shared/fit-tile';
import { Table } from '@cardstack/pretui/components/table';
import { COMPACT_EMPTY_STYLE } from '@cardstack/catalog/components/pretui-helpers';
import { Money } from '../crm/money';
import { Deal } from './deal';
import { LineItem } from './line-item';
import { Proposal } from './proposal';
import { lineTotal, sumLineItems } from './line-item-totals';
import { hasNumber } from '../crm/utils';
import { orEmpty } from './compact-parts';
import { IsoFrame } from '../shared/compact-sheet';

// Quote — a priced proposal, not yet binding. Versioned: each negotiation
// round creates a NEW Quote with `supersedes` pointing at the previous one,
// which stays immutable. Line items are the shared `LineItem` field — a
// snapshot of description/qty/price at negotiation time, not live links to a
// price list.

const QuoteStatusField = enumField(StringField, {
  options: ['draft', 'sent', 'under-review', 'won', 'lost', 'expired'],
  displayName: 'Quote Status',
});

function quoteCurrency(quote?: Partial<Pick<Quote, 'lineItems'>>) {
  return sumLineItems(quote?.lineItems).code;
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
      <span class='atom'>
        <Avatar @name='Quote' @shape='square' @size={{16}} />
        <span class='name'>{{@model.cardTitle}}</span>
      </span>
      <style scoped>
        .atom {
          font-size: 0.6875rem;
          font-weight: 600;
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
          min-width: 0;
          max-width: 100%;
          color: var(--foreground);
        }
        .name {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof Quote> {
    get rows() {
      return quoteRows(this.args.model as Quote);
    }
    <template>
      <article class='emb'>
        <header>
          <Avatar @name='Quote' @shape='square' @size={{28}} />
          <div class='id'>
            <h3>{{@model.cardTitle}}</h3>
            <p>{{quoteSub @model}}</p>
          </div>
          {{#if @model.status}}<StatusChip
              @value={{@model.status}}
              @appearance='plain'
            />{{/if}}
        </header>
        <KeyValue
          class='kv'
          @items={{this.rows}}
          @labelStyle='eyebrow'
          @divided={{true}}
        />
        {{#if @model.deal}}
          <div class='linked'>
            <span class='cap'>Deal</span>
            <@fields.deal @format='atom' @displayContainer={{false}} />
          </div>
        {{/if}}
        {{#if @model.supersedes}}
          <div class='linked'>
            <span class='cap'>Supersedes</span>
            <@fields.supersedes @format='atom' @displayContainer={{false}} />
          </div>
        {{/if}}
      </article>
      <style scoped>
        .emb {
          font-size: 0.75rem;
          line-height: 1.4;
          --text-stat: 1.375rem;
          --text-ui-xs: 0.6875rem;
          --boxel-sp-xs: 0.35rem;
          --boxel-sp-lg: 0.75rem;
          --pretui-kv-label-font-size: 0.5625rem;
          --pretui-kv-label-color: var(--muted-foreground);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          overflow: hidden;
          display: flex;
          flex-direction: column;
          color: var(--foreground);
        }
        header {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          padding: 0.5rem 0.625rem;
        }
        .id {
          flex: 1;
          min-width: 0;
        }
        h3 {
          margin: 0;
          font-size: var(--boxel-font-size-sm, 0.8125rem);
          font-weight: 600;
        }
        p {
          margin: 0;
          font-size: 0.6875rem;
          color: var(--muted-foreground);
        }
        .linked {
          display: flex;
          align-items: center;
          gap: 0.75rem;
          padding: 0.375rem 0.625rem;
          border-top: 1px solid var(--border);
        }
        .cap {
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
          min-width: 5rem;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof Quote> {
    <template>
      <FitTile>
        <:avatar><Avatar @name='Quote' @shape='square' @size={{32}} /></:avatar>
        <:title>{{@model.cardTitle}}</:title>
        <:subtitle>{{quoteSub @model}}</:subtitle>
        <:status>{{#if @model.status}}<StatusChip
              @value={{@model.status}}
              @appearance='plain'
            />{{/if}}</:status>
        <:fact><Money @amount={{@model.total}} @code={{quoteCurrency @model}} />
          ·
          {{@model.lineItems.length}}
          items</:fact>
        <:relations>{{#if @model.deal}}<@fields.deal
              @format='atom'
              @displayContainer={{false}}
            />{{/if}}</:relations>
      </FitTile>
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
    get details() {
      return quoteRows(this.args.model as Quote);
    }
    get code() {
      return quoteCurrency(this.args.model);
    }
    get change() {
      let m = this.args.model as Quote;
      return (m?.total ?? 0) - (m?.supersedes?.total ?? 0);
    }
    get statuses() {
      let cur = this.args.model?.status;
      return ['draft', 'sent', 'under-review', 'won', 'lost'].map((label) => ({
        label,
        current: label === cur ? 'true' : undefined,
      }));
    }
    <template>
      <IsoFrame>
        <article class='page'>
          <header>
            <Avatar @name='Quote' @shape='square' @size={{32}} />
            <div class='id'>
              <h1>{{@model.cardTitle}}</h1>
              <p>{{quoteSub @model}}</p>
            </div>
            {{#if @model.status}}<StatusChip
                @value={{@model.status}}
                @appearance='plain'
              />{{/if}}
          </header>
          <div class='stats'>
            <Stat
              @label='Total'
              @tone='neutral'
              @value={{orEmpty @model.total}}
              @style='currency'
              @maximumFractionDigits={{0}}
              @currency={{this.code}}
              @hint={{concat this.rows.length ' line items'}}
              @roll={{false}}
            />
            <Stat
              @label='Version'
              @tone='neutral'
              @value={{concat 'v' @model.version}}
              @hint={{if
                @model.supersedes
                (concat 'supersedes v' @model.supersedes.version)
              }}
              @roll={{false}}
            />
            {{#if @model.supersedes}}
              <Stat
                @label='Change'
                @tone='neutral'
                @value={{this.change}}
                @style='currency'
                @maximumFractionDigits={{0}}
                @currency={{this.code}}
                @hint={{concat 'vs v' @model.supersedes.version}}
                @roll={{false}}
              />
            {{/if}}
          </div>
          <div class='cols'>
            <div class='main'>
              <section>
                <h2 id={{this.itemsId}}>Line items</h2>
                {{#if this.rows.length}}
                  <Table
                    class='lines'
                    @framed={{false}}
                    @labelledBy={{this.itemsId}}
                  >
                    <:head>
                      <tr>
                        <th scope='col'>Description</th>
                        <th scope='col' class='num'>Qty</th>
                        <th scope='col' class='num'>Unit price</th>
                        <th scope='col' class='num'>Amount</th>
                      </tr>
                    </:head>
                    <:body>
                      {{#each this.rows as |row|}}
                        <tr>
                          <td>{{row.description}}</td>
                          <td class='num'>{{row.quantity}}</td>
                          <td class='num'><Money
                              @amount={{row.unit}}
                              @code={{row.code}}
                            /></td>
                          <td class='num'><Money
                              @amount={{row.total}}
                              @code={{row.code}}
                            /></td>
                        </tr>
                      {{/each}}
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
              <section>
                <h2>Status</h2>
                <div class='steps'>
                  {{#each this.statuses as |st|}}
                    <span class='step' data-current={{st.current}}><StatusChip
                        @value={{st.label}}
                        @appearance='plain'
                      /></span>
                  {{/each}}
                </div>
              </section>
            </div>
            <div class='side'>
              <section>
                <h2>Linked</h2>
                <div class='linked'><span class='cap'>Deal</span>
                  <@fields.deal
                    @format='atom'
                    @displayContainer={{false}}
                  /></div>
                <div class='linked'><span class='cap'>Supersedes</span>
                  <@fields.supersedes
                    @format='atom'
                    @displayContainer={{false}}
                  /></div>
                <div class='linked'><span class='cap'>Proposal</span>
                  <@fields.proposal
                    @format='atom'
                    @displayContainer={{false}}
                  /></div>
              </section>
              <section>
                <h2>Details</h2>
                <KeyValue
                  @items={{this.details}}
                  @labelStyle='eyebrow'
                  @divided={{true}}
                  class='kv'
                />
              </section>
            </div>
          </div>
        </article>
      </IsoFrame>
      <style scoped>
        .stats > * {
          padding: 0.4375rem 0.625rem;
        }
        .stats > * + * {
          border-inline-start: 1px solid var(--border);
        }
        .kv {
          --pretui-kv-pad-inline: var(--boxel-sp-sm);
        }
        .linked .cap {
          font-family: var(--font-mono);
          font-size: 0.5625rem;
          font-weight: 600;
          letter-spacing: 0.13em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .cols {
          display: grid;
          grid-template-columns: minmax(0, 3fr) minmax(16rem, 2fr);
          align-items: stretch;
        }
        .side {
          border-inline-start: 1px solid var(--border);
          min-inline-size: 0;
        }
        .main {
          min-inline-size: 0;
        }
        .steps {
          display: flex;
          flex-wrap: wrap;
          gap: 0.75rem;
          padding: 0.4375rem 0.625rem;
          color: var(--muted-foreground);
        }
        .step[data-current] {
          color: var(--foreground);
          font-weight: 700;
        }
        @container (max-width: 40rem) {
          .cols {
            grid-template-columns: minmax(0, 1fr);
          }
          .side {
            border-inline-start: 0;
            border-block-start: 1px solid var(--border);
          }
        }
        .page {
          font-size: 0.75rem;
          line-height: 1.4;
          --text-stat: 1.375rem;
          --text-ui-xs: 0.6875rem;
          --boxel-sp-xs: 0.35rem;
          --boxel-sp-lg: 0.75rem;
          --pretui-kv-label-font-size: 0.5625rem;
          --pretui-kv-label-color: var(--muted-foreground);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          overflow: hidden;
          display: flex;
          flex-direction: column;
          background: var(--card);
          color: var(--foreground);
        }
        header {
          display: flex;
          align-items: center;
          gap: 0.625rem;
          padding: 0.75rem;
          border-bottom: 1px solid var(--border);
        }
        .id {
          flex: 1;
          min-width: 0;
        }
        h1 {
          font-family: var(--font-sans);
          margin: 0;
          font-size: 1rem;
          font-weight: 700;
        }
        p {
          margin: 0;
          font-size: 0.6875rem;
          color: var(--muted-foreground);
        }
        .stats {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(12rem, 1fr));
          border-bottom: 1px solid var(--border);
        }
        section h2 {
          margin: 0;
          padding: 0.5rem 0.75rem;
          font-size: 0.75rem;
          font-weight: 700;
          border-bottom: 1px solid var(--border);
        }
        .num {
          text-align: end;
        }
        .linked {
          display: flex;
          align-items: center;
          gap: 0.75rem;
          padding: 0.375rem 0.75rem;
          border-bottom: 1px solid var(--border);
        }
        .cap {
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
          min-width: 5rem;
        }
      </style>
    </template>
  };
}

function quoteSub(q: Partial<Quote> | undefined) {
  let parts = [];
  if (q?.supersedes) parts.push(`Supersedes v${q.supersedes.version ?? 1}`);
  parts.push(`${q?.lineItems?.length ?? 0} line items`);
  return parts.join(' · ');
}

function quoteRows(q: Quote) {
  let rows = [];
  if (hasNumber(q?.version))
    rows.push({ key: 'Version', value: `v${q.version}` });
  if (hasNumber(q?.total))
    rows.push({
      key: 'Total',
      value:
        `${quoteCurrency(q) ?? ''} ${q.total.toLocaleString('en-US')}`.trim(),
    });
  if (q?.status) rows.push({ key: 'Status', value: q.status });
  return rows;
}
