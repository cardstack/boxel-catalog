import {
  CardDef,
  Component,
  field,
  contains,
  containsMany,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import DateField from '@cardstack/base/date';
import NumberField from '@cardstack/base/number';
import TextAreaField from '@cardstack/base/text-area';
import BooleanField from '@cardstack/base/boolean';

import { LineItem } from '../commerce/line-item';
import { Vendor } from './vendor';
import { VendorProfile } from './vendor-profile';
import { Rfq } from './rfq';
import { formatMoney, sumLineItems } from '../commerce/line-item-totals';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import { Money } from '../crm/money';
import { COMPACT_EMPTY_STYLE } from '@cardstack/catalog/components/pretui-helpers';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { KeyValue } from '@cardstack/pretui/components/key-value';
import { Stat } from '@cardstack/pretui/components/stat';

const DELIVERY_FACTS = [{ key: 'Lead time', value: 'leadTimeDays' }];

function isPastDay(d?: Date | null): boolean {
  if (!d) {
    return false;
  }
  let now = new Date();
  let today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  let day = new Date(d.getFullYear(), d.getMonth(), d.getDate());
  return day < today;
}

// A vendor's priced response to an RFQ, recorded by the BUYER (single-persona
// rule: vendors do not log in — the procurement manager transcribes inbound
// quotes from email/PDF). Lines reuse LineItem so quote totals and PO lines
// speak the same shape. `vendorProfile` carries the compliance gate: the
// comparison board surfaces it and AwardRfqCommand refuses a quote without
// one.
export class VendorQuote extends CardDef {
  static displayName = 'Vendor Quote';
  static headerColor = '#3e4e88';

  @field rfq = linksTo(() => Rfq, { searchable: true });
  @field vendor = linksTo(() => Vendor);
  @field vendorProfile = linksTo(() => VendorProfile);
  @field lineItems = containsMany(LineItem);
  @field leadTimeDays = contains(NumberField);
  @field validUntil = contains(DateField);
  @field notes = contains(TextAreaField);

  @field totalAmount = contains(NumberField, {
    computeVia: function (this: VendorQuote) {
      return sumLineItems(this.lineItems ?? []).total;
    },
  });

  @field isStale = contains(BooleanField, {
    computeVia: function (this: VendorQuote) {
      return isPastDay(this.validUntil);
    },
  });

  @field title = contains(StringField, {
    computeVia: function (this: VendorQuote) {
      let vendorName = this.vendor?.name?.trim();
      return vendorName ? `Quote — ${vendorName}` : 'Vendor Quote';
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    get totalLabel() {
      return formatMoney(this.args.model?.totalAmount ?? 0, 'USD');
    }
    get validityLabel() {
      let d = this.args.model?.validUntil;
      if (!d) {
        return 'no expiry set';
      }
      let label = d.toLocaleDateString('en-US', {
        month: 'short',
        day: 'numeric',
        year: 'numeric',
      });
      return this.args.model?.isStale
        ? `expired ${label}`
        : `valid to ${label}`;
    }
    <template>
      <article class='quote'>
        <header class='head'>
          <div>
            <p class='kicker'>Vendor Quote</p>
            <h1>{{@model.title}}</h1>
            {{#if @model.rfq}}
              <p class='sub'>for <@fields.rfq @format='atom' /></p>
            {{/if}}
          </div>
          <div class='head-right'>
            <Stat
              class='total'
              @label='Quote total'
              @value={{this.totalLabel}}
              @roll={{false}}
            />
            <StatePill
              @label={{this.validityLabel}}
              @hue={{if @model.isStale 'red' 'green'}}
              @dot={{true}}
            />
          </div>
        </header>

        <div class='grid'>
          <section class='panel span'>
            <h2>Quoted Lines</h2>
            <div class='lines'>
              {{#each @fields.lineItems as |Line|}}
                <Line />
              {{else}}
                <EmptyState
                  style={{COMPACT_EMPTY_STYLE}}
                  @texture={{false}}
                  @title='No lines recorded'
                  @message='The quote total is computed from its pricing lines.'
                />
              {{/each}}
            </div>
          </section>

          <section class='panel'>
            <h2>Delivery</h2>
            <KeyValue class='facts' @items={{DELIVERY_FACTS}}>
              <:value>{{@model.leadTimeDays}} days</:value>
            </KeyValue>
          </section>

          <section class='panel'>
            <h2>Vendor</h2>
            {{#if @model.vendor}}
              <@fields.vendor @format='atom' />
            {{/if}}
            {{#if @model.vendorProfile}}
              <div class='profile-link'>
                <@fields.vendorProfile @format='atom' />
              </div>
            {{/if}}
          </section>

          {{#if @model.notes}}
            <section class='panel span'>
              <h2>Notes</h2>
              <p class='notes'>{{@model.notes}}</p>
            </section>
          {{/if}}
        </div>
      </article>
      <style scoped>
        .quote {
          container-type: inline-size;
          padding: var(--boxel-sp-lg);
        }
        .head {
          display: flex;
          justify-content: space-between;
          align-items: flex-start;
          gap: var(--boxel-sp);
          border-bottom: 1px solid var(--border);
          padding-bottom: var(--boxel-sp);
          margin-bottom: var(--boxel-sp-lg);
        }
        .kicker {
          margin: 0;
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        h1 {
          margin: var(--boxel-sp-5xs) 0;
          font-size: 1.5rem;
        }
        .sub {
          margin: 0;
          color: var(--muted-foreground);
        }
        .head-right {
          display: flex;
          flex-direction: column;
          align-items: flex-end;
          gap: var(--boxel-sp-xs);
        }
        .total {
          white-space: nowrap;
        }
        .grid {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: var(--boxel-sp);
        }
        .panel {
          border: 1px solid var(--border);
          border-radius: var(--radius);
          padding: var(--boxel-sp);
          background-color: var(--card);
          color: var(--card-foreground);
        }
        .panel.span {
          grid-column: 1 / -1;
        }
        h2 {
          margin: 0 0 var(--boxel-sp-xs);
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        /* Pret UI KeyValue at the panel's text size and column gap */
        .facts {
          --text-ui: 0.8125rem;
          --text-ui-md: 0.875rem;
          --space-6: var(--boxel-sp-xs);
          font-variant-numeric: tabular-nums;
        }
        .lines {
          display: grid;
          gap: var(--boxel-sp-5xs);
        }
        .notes {
          margin: 0;
          font-size: 0.875rem;
          white-space: pre-wrap;
        }
        .profile-link {
          margin-top: var(--boxel-sp-4xs);
        }
        @container (max-width: 560px) {
          .grid {
            grid-template-columns: 1fr;
          }
          .head {
            flex-direction: column;
          }
          .head-right {
            align-items: flex-start;
          }
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    get total() {
      return this.args.model?.totalAmount ?? 0;
    }
    <template>
      <div class='row'>
        <span class='name'>{{@model.title}}</span>
        <span class='lead'>{{@model.leadTimeDays}}d lead</span>
        <Money class='amount' @amount={{this.total}} @code='USD' />
        <StatePill
          @label={{if @model.isStale 'expired' 'valid'}}
          @hue={{if @model.isStale 'red' 'green'}}
          @dot={{true}}
        />
      </div>
      <style scoped>
        .row {
          display: grid;
          grid-template-columns: 1fr auto auto auto;
          gap: var(--boxel-sp-sm);
          align-items: center;
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .name {
          font-weight: 600;
          font-size: 0.9375rem;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .lead {
          font-size: 0.8125rem;
          color: var(--muted-foreground);
          font-variant-numeric: tabular-nums;
        }
        .amount {
          font-weight: 600;
          font-variant-numeric: tabular-nums;
          min-width: 5.5rem;
          text-align: right;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    // kit atom: name ellipsises first, whole-dollar mono amount
    get total() {
      return (this.args.model?.totalAmount ?? 0).toLocaleString('en-US', {
        style: 'currency',
        currency: 'USD',
        maximumFractionDigits: 0,
      });
    }
    <template>
      <span class='atom'><span class='nm'>{{@model.title}}</span><span
          class='amt'
        >{{this.total}}</span></span>
      <style scoped>
        .atom {
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
          max-inline-size: 100%;
          min-inline-size: 0;
          font-size: 0.75rem;
        }
        .nm {
          min-inline-size: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          font-weight: 600;
        }
        .amt {
          flex: none;
          font-family: var(--font-mono);
          font-variant-numeric: tabular-nums;
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get total() {
      return this.args.model?.totalAmount ?? 0;
    }
    <template>
      <div class='fit'>
        <span class='fit-name'>{{@model.title}}</span>
        <div class='fit-foot'>
          <Money class='fit-total' @amount={{this.total}} @code='USD' />
          <span class='fit-lead'>{{@model.leadTimeDays}}d</span>
        </div>
      </div>
      <style scoped>
        .fit {
          height: 100%;
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-5xs);
          padding: var(--boxel-sp-xs);
          overflow: hidden;
        }
        .fit-name {
          font-weight: 600;
          font-size: 0.9375rem;
          line-height: 1.2;
          overflow: hidden;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
        }
        .fit-foot {
          margin-top: auto;
          display: flex;
          justify-content: space-between;
          align-items: baseline;
        }
        .fit-total {
          font-weight: 700;
          font-variant-numeric: tabular-nums;
        }
        .fit-lead {
          font-size: 0.75rem;
          color: var(--muted-foreground);
        }
        @container fitted-card (height <= 65px) {
          .fit {
            flex-direction: row;
            align-items: center;
            gap: var(--boxel-sp-xs);
          }
          .fit-name {
            -webkit-line-clamp: 1;
          }
          .fit-foot {
            margin-top: 0;
            margin-left: auto;
            gap: var(--boxel-sp-xs);
          }
        }
      </style>
    </template>
  };

  // Grouped by how the buyer transcribes an inbound quote (whose quote for
  // which RFQ → the priced lines → the fine print), not schema order. Three
  // sections — no nav rail. totalAmount, isStale, and
  // title are computed (computeVia) and deliberately excluded.
}
