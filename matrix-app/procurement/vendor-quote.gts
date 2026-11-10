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
import { eq } from '@cardstack/boxel-ui/helpers';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { Chip } from '@cardstack/pretui/components/chip';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import {
  KeyValue,
  type KeyValueItem,
} from '@cardstack/pretui/components/key-value';
import { Stat } from '@cardstack/pretui/components/stat';
import { Table } from '@cardstack/pretui/components/table';

import { LineItem } from '../commerce/line-item';
import { Vendor } from './vendor';
import { VendorProfile } from './vendor-profile';
import { Rfq } from './rfq';
import { formatMoney, sumLineItems } from '../commerce/line-item-totals';
import { FitTile } from '../shared/fit-tile';

function isPastDay(d?: Date | null): boolean {
  if (!d) {
    return false;
  }
  let now = new Date();
  let today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  let day = new Date(d.getFullYear(), d.getMonth(), d.getDate());
  return day < today;
}

const MARK = 'Vendor Quote';
const LINKED: KeyValueItem[] = [
  { key: 'Vendor', value: '' },
  { key: 'RFQ', value: '' },
  { key: 'Profile', value: '' },
];

const wholeUsd = (n: number) =>
  n.toLocaleString('en-US', {
    style: 'currency',
    currency: 'USD',
    maximumFractionDigits: 0,
  });

// One read of the quote for every format, so the four views never disagree.
function quoteFacts(m?: VendorQuote | null) {
  let lines = (m?.lineItems ?? []).filter(Boolean);
  let lead = m?.leadTimeDays;
  let valid = m?.validUntil;
  let stale = Boolean(m?.isStale);
  let lineRows: KeyValueItem[] = lines.map((l) => ({
    key: l.description || '—',
    value: `${l.quantity ?? 0} × ${wholeUsd(l.unitPrice?.amount ?? 0)}`,
  }));
  return {
    total: formatMoney(m?.totalAmount ?? 0, 'USD'),
    totalShort: wholeUsd(m?.totalAmount ?? 0),
    lineWord: `${lines.length} line${lines.length === 1 ? '' : 's'}`,
    lines: lines.map((l) => ({
      description: l.description || '—',
      qty: String(l.quantity ?? 0),
      unit: formatMoney(l.unitPrice?.amount ?? 0, 'USD'),
      total: formatMoney((l.quantity ?? 0) * (l.unitPrice?.amount ?? 0), 'USD'),
    })),
    lead: lead != null ? `${lead} days` : '—',
    leadTag: lead != null ? `${lead}-day lead` : '',
    validDay: valid
      ? valid.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' })
      : '—',
    validYear: valid ? String(valid.getFullYear()) : 'no expiry set',
    validFull: valid
      ? valid.toLocaleDateString('en-GB', {
          day: '2-digit',
          month: 'short',
          year: 'numeric',
        })
      : '—',
    status: stale ? 'expired' : 'valid',
    tone: (stale ? 'danger' : 'success') as 'danger' | 'success',
    sub: m?.rfq?.cardTitle ?? '',
    lineRows,
  };
}

function factRows(m?: VendorQuote | null): KeyValueItem[] {
  let f = quoteFacts(m);
  return [
    { key: 'Total', value: f.total },
    { key: 'Lead time', value: f.lead },
    { key: 'Valid until', value: f.validFull },
    { key: 'Lines', value: `${f.lines.length}` },
    ...f.lineRows,
  ];
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
    get f() {
      return quoteFacts(this.args.model as VendorQuote);
    }
    get details() {
      return factRows(this.args.model as VendorQuote);
    }
    <template>
      <article class='vq'>
        <div class='card'>
          <header class='ih'>
            <Avatar @name={{MARK}} @shape='square' @size={{24}} />
            <div class='id'>
              <h1>{{@model.title}}</h1>
              {{#if this.f.sub}}<p class='meta'>{{this.f.sub}}</p>{{/if}}
            </div>
            <Chip
              @label={{this.f.status}}
              @tone={{this.f.tone}}
              @appearance='plain'
            />
            {{#if this.f.leadTag}}
              <span class='mono meta'>{{this.f.leadTag}}</span>
            {{/if}}
          </header>
          <div class='stats'>
            <Stat
              @label='Total'
              @tone='neutral'
              @value={{this.f.totalShort}}
              @roll={{false}}
              @hint={{this.f.lineWord}}
            />
            <Stat
              @label='Lead time'
              @tone='neutral'
              @value={{this.f.lead}}
              @roll={{false}}
              @hint='from award'
            />
            <Stat
              @label='Valid until'
              @tone={{this.f.tone}}
              @value={{this.f.validDay}}
              @roll={{false}}
              @hint={{this.f.validYear}}
            />
          </div>
          <div class='cols'>
            <div class='main'>
              <section>
                <h2 class='cap' id='vq-lines'>Line items</h2>
                {{#if this.f.lines.length}}
                  <div class='tw'>
                    <Table @labelledBy='vq-lines' @framed={{false}}>
                      <:head>
                        <tr>
                          <th scope='col'>Item</th>
                          <th scope='col' class='end'>Qty</th>
                          <th scope='col' class='end'>Unit price</th>
                          <th scope='col' class='end'>Total</th>
                        </tr>
                      </:head>
                      <:body>
                        {{#each this.f.lines as |l|}}
                          <tr>
                            <td>{{l.description}}</td>
                            <td class='end mono'>{{l.qty}}</td>
                            <td class='end mono'>{{l.unit}}</td>
                            <td class='end mono'>{{l.total}}</td>
                          </tr>
                        {{/each}}
                      </:body>
                    </Table>
                  </div>
                {{else}}
                  <div class='pad'>
                    <EmptyState
                      @size='s'
                      @title='No lines recorded'
                      @message='The quote total is computed from its pricing lines.'
                    />
                  </div>
                {{/if}}
              </section>
              <section>
                <h2 class='cap'>Notes</h2>
                <p class='pad notes'>{{if @model.notes @model.notes '—'}}</p>
              </section>
            </div>
            <aside class='side'>
              <section>
                <h2 class='cap'>Linked</h2>
                <KeyValue
                  @items={{LINKED}}
                  @divided={{true}}
                  @labelStyle='eyebrow'
                  class='kv'
                >
                  <:value as |item|>
                    {{#if (eq item.key 'Vendor')}}
                      {{#if @model.vendor}}<@fields.vendor
                          @format='atom'
                          @displayContainer={{false}}
                        />{{else}}—{{/if}}
                    {{else if (eq item.key 'RFQ')}}
                      {{#if @model.rfq}}<@fields.rfq
                          @format='atom'
                          @displayContainer={{false}}
                        />{{else}}—{{/if}}
                    {{else}}
                      {{#if @model.vendorProfile}}<@fields.vendorProfile
                          @format='atom'
                          @displayContainer={{false}}
                        />{{else}}—{{/if}}
                    {{/if}}
                  </:value>
                </KeyValue>
              </section>
              <section>
                <h2 class='cap'>Details</h2>
                <KeyValue
                  @items={{this.details}}
                  @divided={{true}}
                  @labelStyle='eyebrow'
                  class='kv'
                />
              </section>
            </aside>
          </div>
        </div>
      </article>
      <style scoped>
        .vq {
          container-type: inline-size;
          box-sizing: border-box;
          block-size: 100%;
          overflow-y: auto;
          padding: var(--boxel-sp-sm);
          font-size: 0.75rem;
          line-height: 1.3;
          color: var(--card-foreground);
          --text-stat: 1.375rem;
          --text-ui-xs: 0.6875rem;
          --pretui-kv-label-font-size: 0.5625rem;
          --pretui-kv-label-color: var(--muted-foreground);
          --pretui-kv-label-font-family: var(--font-mono);
          --pretui-kv-label-font-weight: 600;
          --pretui-kv-label-letter-spacing: 0.13em;
        }
        .card {
          border: 1px solid var(--border);
          border-radius: var(--radius);
          background: var(--card);
          overflow: hidden;
        }
        .ih {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .id {
          flex: 1;
          min-inline-size: 10rem;
        }
        h1 {
          margin: 0;
          font-family: var(--font-sans);
          font-size: 0.75rem;
          font-weight: 700;
        }
        p {
          margin: 0;
        }
        .meta {
          font-size: 0.6875rem;
          color: var(--muted-foreground);
        }
        .mono {
          font-family: var(--font-mono);
          font-variant-numeric: tabular-nums;
        }
        .cap,
        th {
          margin: 0;
          font-family: var(--font-mono);
          font-size: 0.5625rem;
          font-weight: 600;
          letter-spacing: 0.13em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .stats,
        .cols {
          display: grid;
          grid-template-columns: minmax(0, 1fr) minmax(0, 1fr) minmax(0, 1fr);
          border-block-start: 1px solid var(--border);
        }
        .stats > * {
          padding: var(--boxel-sp-xxs) var(--boxel-sp-sm);
        }
        .stats > :not(:first-child) {
          border-inline-start: 1px solid var(--border);
        }
        .main {
          grid-column: span 2;
          min-inline-size: 0;
        }
        .side {
          min-inline-size: 0;
          border-inline-start: 1px solid var(--border);
        }
        section + section {
          border-block-start: 1px solid var(--border);
        }
        h2 {
          padding: var(--boxel-sp-xxs) var(--boxel-sp-sm);
          border-block-end: 1px solid var(--border);
        }
        .tw {
          overflow-x: auto;
          padding-inline: var(--boxel-sp-sm);
          --pretui-table-head-height: 1.5rem;
          --inset: var(--card);
          --stripe: transparent;
        }
        th,
        td {
          padding-block: 0;
          text-align: start;
          white-space: nowrap;
        }
        td {
          block-size: 1.75rem;
        }
        .end {
          text-align: end;
        }
        .pad {
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .notes {
          white-space: pre-wrap;
        }
        .kv {
          padding-inline: var(--boxel-sp-sm);
          row-gap: 0;
        }
        @container (width < 40rem) {
          .cols {
            grid-template-columns: minmax(0, 1fr);
          }
          .main {
            grid-column: auto;
          }
          .side {
            border-inline-start: 0;
            border-block-start: 1px solid var(--border);
          }
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    get f() {
      return quoteFacts(this.args.model as VendorQuote);
    }
    get rows(): KeyValueItem[] {
      return [...factRows(this.args.model as VendorQuote), ...LINKED];
    }
    <template>
      <article class='emb'>
        <header class='eh'>
          <Avatar @name={{MARK}} @shape='square' @size={{20}} />
          <strong class='nm'>{{@model.title}}</strong>
          <Chip
            @label={{this.f.status}}
            @tone={{this.f.tone}}
            @appearance='plain'
          />
          {{#if this.f.sub}}<span class='meta sub'>{{this.f.sub}}</span>{{/if}}
        </header>
        <KeyValue
          @items={{this.rows}}
          @divided={{true}}
          @labelStyle='eyebrow'
          class='kv'
        >
          <:value as |item|>
            {{#if (eq item.key 'Vendor')}}
              {{#if @model.vendor}}<@fields.vendor
                  @format='atom'
                  @displayContainer={{false}}
                />{{else}}—{{/if}}
            {{else if (eq item.key 'RFQ')}}
              {{#if @model.rfq}}<@fields.rfq
                  @format='atom'
                  @displayContainer={{false}}
                />{{else}}—{{/if}}
            {{else if (eq item.key 'Profile')}}
              {{#if @model.vendorProfile}}<@fields.vendorProfile
                  @format='atom'
                  @displayContainer={{false}}
                />{{else}}—{{/if}}
            {{else}}
              <span class='mono'>{{item.value}}</span>
            {{/if}}
          </:value>
        </KeyValue>
      </article>
      <style scoped>
        .emb {
          padding: var(--boxel-sp-xs);
          font-size: 0.75rem;
          line-height: 1.3;
          --pretui-kv-label-font-size: 0.5625rem;
          --pretui-kv-label-color: var(--muted-foreground);
          --pretui-kv-label-font-family: var(--font-mono);
          --pretui-kv-label-font-weight: 600;
          --pretui-kv-label-letter-spacing: 0.13em;
        }
        .eh {
          display: grid;
          grid-template-columns: auto minmax(0, 1fr) auto;
          align-items: center;
          column-gap: var(--boxel-sp-xxs);
          padding-block-end: var(--boxel-sp-xxs);
          border-block-end: 1px solid var(--border);
        }
        .nm {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          font-weight: 700;
        }
        .sub {
          grid-column: 2 / -1;
        }
        .meta {
          font-size: 0.6875rem;
          color: var(--muted-foreground);
        }
        .mono {
          font-family: var(--font-mono);
          font-size: 0.6875rem;
          font-variant-numeric: tabular-nums;
          color: var(--muted-foreground);
        }
        .kv {
          row-gap: 0;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='atom'>
        <Avatar @name={{MARK}} @shape='square' @size={{16}} />
        <span class='name'>{{@model.title}}</span>
      </span>
      <style scoped>
        .atom {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-xxxs);
          min-inline-size: 0;
          max-inline-size: 100%;
          font-size: 0.6875rem;
          font-weight: 600;
        }
        .name {
          min-inline-size: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get f() {
      return quoteFacts(this.args.model as VendorQuote);
    }
    <template>
      <FitTile>
        <:avatar><Avatar
            @name={{MARK}}
            @shape='square'
            @size={{32}}
          /></:avatar>
        <:title>{{@model.title}}</:title>
        <:subtitle>{{this.f.sub}}</:subtitle>
        <:status><Chip
            @label={{this.f.status}}
            @tone={{this.f.tone}}
            @appearance='plain'
          /></:status>
        <:fact>{{this.f.totalShort}}
          ·
          {{this.f.lead}}
          · valid until
          {{this.f.validFull}}</:fact>
        <:relations>
          {{#if @model.vendor}}<@fields.vendor
              @format='atom'
              @displayContainer={{false}}
            />{{/if}}
          {{#if @model.rfq}}<@fields.rfq
              @format='atom'
              @displayContainer={{false}}
            />{{/if}}
        </:relations>
      </FitTile>
    </template>
  };

  // Grouped by how the buyer transcribes an inbound quote (whose quote for
  // which RFQ → the priced lines → the fine print), not schema order. Three
  // sections — no nav rail. totalAmount, isStale, and
  // title are computed (computeVia) and deliberately excluded.
}
