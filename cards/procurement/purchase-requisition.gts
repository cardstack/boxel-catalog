import { markDefinition } from '@cardstack/base/mark-definition';
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
import enumField from '@cardstack/base/enum';

import { LineItem } from '../commerce/line-item';
import { ProcurementBudget } from './procurement-budget';
import { sumLineItems } from '../commerce/line-item-totals';
import { concat } from '@ember/helper';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { Chip } from '@cardstack/pretui/components/chip';
import { Stat } from '@cardstack/pretui/components/stat';
import { List } from '@cardstack/pretui/components/list';
import { Item } from '@cardstack/pretui/components/item';
import { CompactFitted, CompactRow } from '../commerce/compact-parts';
import {
  KeyValue,
  type KeyValueItem,
} from '@cardstack/pretui/components/key-value';
import {
  stateColor,
  type StateColor,
} from '@cardstack/catalog/components/state-pill';
import { eq } from '@cardstack/boxel-ui/helpers';

export const REQUISITION_STATUSES = [
  'draft',
  'submitted',
  'converted-to-rfq',
  'rejected',
];

export const REQUISITION_STATUS_LABELS: Record<string, string> = {
  draft: 'Draft',
  submitted: 'Submitted',
  'converted-to-rfq': 'Converted to RFQ',
  rejected: 'Rejected',
};

export const REQUISITION_STATUS_COLORS: Record<string, StateColor> = {
  draft: stateColor('slate'),
  submitted: stateColor('amber'),
  'converted-to-rfq': stateColor('green'),
  rejected: stateColor('red'),
};

const STATUS_TONES: Record<
  string,
  'neutral' | 'warning' | 'success' | 'danger'
> = {
  draft: 'neutral',
  submitted: 'warning',
  'converted-to-rfq': 'success',
  rejected: 'danger',
};

const BUDGET_ROW = [{ key: 'Budget', value: '' }];

const usd = new Intl.NumberFormat('en-US', {
  style: 'currency',
  currency: 'USD',
  maximumFractionDigits: 0,
});

// DateField yields local midnight, so format in local time (compact-parts'
// fmtDate formats in UTC and shows the day before east of UTC).
function fmtDate(d?: Date | string | null, year = true): string {
  if (!d) return '';
  let date = d instanceof Date ? d : new Date(d);
  if (Number.isNaN(date.getTime())) return '';
  return date.toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    year: year ? 'numeric' : undefined,
  });
}

// What every format reads off the requisition, in one place.
function reqFacts(m?: PurchaseRequisition) {
  let status = m?.status || 'draft';
  let label = REQUISITION_STATUS_LABELS[status] ?? 'Draft';
  let items = (m?.lineItems ?? []).filter(Boolean);
  let lines = items.map((li) => {
    let qty = li?.quantity ?? 0;
    let unit = li?.unitPrice?.amount ?? 0;
    return {
      description: li?.description || '—',
      each: `${qty} × ${usd.format(unit)}`,
      total: usd.format(qty * unit),
    };
  });
  let neededBy = fmtDate(m?.neededBy);
  let neededShort = fmtDate(m?.neededBy, false);
  let total = usd.format(m?.estimatedTotal ?? 0);
  let n = items.length;
  return {
    name: m?.cardInfo?.name?.trim() || m?.title || 'Untitled Requisition',
    sub: [m?.requester, m?.department].filter(Boolean).join(' · '),
    requester: m?.requester ?? '',
    department: m?.department ?? '',
    status,
    statusLabel: label,
    statusShort: label.split(' ')[0].toLowerCase(),
    statusWord: label.split(' ')[0],
    statusHint: label.split(' ').slice(1).join(' '),
    tone: STATUS_TONES[status] ?? 'neutral',
    total,
    neededBy,
    neededShort,
    neededYear: m?.neededBy ? `${new Date(m.neededBy).getFullYear()}` : '',
    fact: `Est. ${total}${neededShort ? ` · needed by ${neededShort}` : ''}`,
    quantity: items.reduce((a, li) => a + (li?.quantity ?? 0), 0),
    lineCount: n,
    linesCountText: `${n}`,
    linesLabel: `${n} line${n === 1 ? '' : 's'}`,
    lines,
    // one ruled row per line, keyed by the line's first word ("Laptop 40 × $1,180")
    lineKv: lines.map((l) => ({
      key: l.description.split(' ')[0],
      value: l.each,
    })),
  };
}

export const RequisitionStatusField = markDefinition(
  enumField(StringField, {
    options: REQUISITION_STATUSES.map((value) => ({
      value,
      label: REQUISITION_STATUS_LABELS[value],
    })),
    displayName: 'Requisition Status',
  }),
);

// The internal "I need to buy X" request that starts the Procure-to-Pay
// audit trail. No vendor is involved yet: a requisition names what is
// needed, by when, against which budget, and why — the RFQ that follows
// copies its line items. Single-persona: the procurement manager records
// requisitions on behalf of requesters.
export class PurchaseRequisition extends CardDef {
  static displayName = 'Purchase Requisition';
  static headerColor = '#3e4e88';

  @field requester = contains(StringField);
  @field department = contains(StringField);
  @field neededBy = contains(DateField);
  @field lineItems = containsMany(LineItem);
  @field justification = contains(TextAreaField);
  @field status = contains(RequisitionStatusField);
  @field budget = linksTo(() => ProcurementBudget);

  @field estimatedTotal = contains(NumberField, {
    computeVia: function (this: PurchaseRequisition) {
      return sumLineItems(this.lineItems ?? []).total;
    },
  });

  @field title = contains(StringField, {
    computeVia: function (this: PurchaseRequisition) {
      let first = this.lineItems?.[0]?.description?.trim();
      if (first) {
        let more = (this.lineItems?.length ?? 0) - 1;
        return more > 0 ? `${first} +${more} more` : first;
      }
      return this.requester?.trim()
        ? `Requisition — ${this.requester}`
        : 'Untitled Requisition';
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    get f() {
      return reqFacts(this.args.model as PurchaseRequisition);
    }
    get request(): KeyValueItem[] {
      return [
        { key: 'Requester', value: this.f.requester || '—' },
        { key: 'Department', value: this.f.department || '—' },
        { key: 'Needed by', value: this.f.neededBy || '—' },
        { key: 'Estimated total', value: this.f.total },
      ];
    }
    get details(): KeyValueItem[] {
      return [
        { key: 'Estimated total', value: this.f.total },
        { key: 'Needed by', value: this.f.neededBy || '—' },
        { key: 'Requester', value: this.f.requester || '—' },
        { key: 'Department', value: this.f.department || '—' },
        ...this.f.lineKv,
        { key: 'Lines', value: `${this.f.lineCount}` },
        { key: 'Status', value: this.f.statusLabel },
      ];
    }
    <template>
      <article class='ip'>
        <section class='card'>
          <header class='ih'>
            <Avatar @name='Pr' @shape='square' @size={{24}} />
            <div class='id'>
              <h1>{{this.f.name}}</h1>
              <p class='meta'>{{this.f.sub}}</p>
            </div>
            <span class='tags'>
              <Chip
                @label={{this.f.status}}
                @tone={{this.f.tone}}
                @appearance='plain'
              />
              <Chip @label={{this.f.linesLabel}} @appearance='plain' />
            </span>
          </header>
          <div class='stats'>
            <Stat
              @label='Estimated total'
              @value={{this.f.total}}
              @roll={{false}}
              @hint={{this.f.linesLabel}}
            />
            <Stat
              @label='Needed by'
              @value={{if this.f.neededShort this.f.neededShort '—'}}
              @roll={{false}}
              @hint={{this.f.neededYear}}
            />
            <Stat
              @label='Quantity'
              @value={{this.f.quantity}}
              @roll={{false}}
              @hint={{concat 'units across ' this.f.linesLabel}}
            />
            <Stat
              @label='Status'
              @tone={{this.f.tone}}
              @value={{this.f.statusWord}}
              @roll={{false}}
              @hint={{this.f.statusHint}}
            />
          </div>
        </section>
        <div class='cols'>
          <div class='col'>
            <section class='card'>
              <h2>Justification</h2>
              <p class='body'>{{if
                  @model.justification
                  @model.justification
                  '—'
                }}</p>
            </section>
            <section class='card'>
              <h2>Line items</h2>
              {{#if this.f.lines.length}}
                <List
                  class='lines'
                  @items={{this.f.lines}}
                  @size='xs'
                  @label='Line items'
                >
                  <:item as |line|>
                    <Item
                      @title={{line.description}}
                      @description={{line.each}}
                    >
                      <:trailing><span
                          class='mono'
                        >{{line.total}}</span></:trailing>
                    </Item>
                  </:item>
                </List>
              {{else}}
                <p class='body muted'>No items added yet</p>
              {{/if}}
            </section>
          </div>
          <div class='col'>
            <section class='card'>
              <h2>Request</h2>
              <KeyValue
                class='kv kv-pad'
                @items={{this.request}}
                @divided={{true}}
                @labelStyle='eyebrow'
              />
            </section>
            <section class='card'>
              <h2>Linked</h2>
              {{#if @model.budget}}
                <KeyValue
                  class='kv kv-pad'
                  @items={{BUDGET_ROW}}
                  @divided={{true}}
                  @labelStyle='eyebrow'
                >
                  <:value><@fields.budget
                      @format='atom'
                      @displayContainer={{false}}
                    /></:value>
                </KeyValue>
              {{else}}
                <p class='body muted'>No budget linked</p>
              {{/if}}
            </section>
            <section class='card'>
              <h2>Details</h2>
              <KeyValue
                class='kv kv-pad'
                @items={{this.details}}
                @divided={{true}}
                @labelStyle='eyebrow'
              />
            </section>
          </div>
        </div>
      </article>
      <style scoped>
        .kv-pad {
          padding-inline: var(--boxel-sp-sm);
        }

        .ip {
          --text-stat: 1.375rem;
          --text-ui-xs: 0.6875rem;
          --pretui-kv-label-font-size: 0.5625rem;
          --pretui-kv-label-color: var(--muted-foreground);
          --boxel-sp-xs: 0.35rem;
          container-type: inline-size;
          display: grid;
          gap: 0.5rem;
          padding: var(--boxel-sp-sm);
          font-size: 0.75rem;
          line-height: 1.25;
          color: var(--card-foreground);

          background: var(--background);
          min-height: 100%;
        }
        .card {
          min-inline-size: 0;
          border: 1px solid var(--border);
          border-radius: var(--radius);
          background: var(--card);
          overflow-x: auto;
        }
        .ih {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          gap: 0.625rem;
          padding: 0.625rem;
        }
        .id {
          flex: 1;
          min-inline-size: 8rem;
        }
        h1 {
          margin: 0;
          font-family: var(--font-sans);
          font-size: 0.8125rem;
          font-weight: 700;
        }
        .meta {
          margin: 0;
          font-size: 0.6875rem;
          color: var(--muted-foreground);
        }
        .tags {
          display: flex;
          flex-wrap: wrap;
          gap: 0.625rem;
        }
        .stats {
          display: grid;
          grid-template-columns: repeat(4, minmax(0, 1fr));
          border-block-start: 1px solid var(--border);
        }
        .stats > * {
          padding: 0.5rem 0.625rem;
          box-shadow:
            1px 0 0 var(--border),
            0 1px 0 var(--border);
        }
        .cols {
          display: grid;
          grid-template-columns: minmax(0, 3fr) minmax(0, 2fr);
          gap: 0.5rem;
          align-items: start;
        }
        .col {
          display: grid;
          gap: 0.5rem;
          min-inline-size: 0;
        }
        h2 {
          margin: 0;
          padding: 0.4375rem 0.625rem;
          border-block-end: 1px solid var(--border);
          font-family: var(--font-sans);
          font-size: 0.75rem;
          font-weight: 700;
        }
        .body {
          margin: 0;
          padding: 0.4375rem 0.625rem;
          white-space: pre-wrap;
        }
        .muted {
          color: var(--muted-foreground);
        }
        .lines {
          padding-inline: 0.625rem;
          font-size: 0.75rem;
        }
        .mono,
        .kv {
          font-variant-numeric: tabular-nums;
        }
        .mono {
          font-family: var(--font-mono);
          font-size: 0.6875rem;
        }
        .kv {
          padding: 0.25rem 0.625rem;
          row-gap: 0;
        }
        @container (width < 40rem) {
          .cols,
          .stats {
            grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
          }
          .cols {
            grid-template-columns: minmax(0, 1fr);
          }
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    get f() {
      return reqFacts(this.args.model as PurchaseRequisition);
    }
    get items(): KeyValueItem[] {
      let rows: KeyValueItem[] = [
        { key: 'Estimated total', value: this.f.total },
        { key: 'Needed by', value: this.f.neededBy || '—' },
        { key: 'Requester', value: this.f.requester || '—' },
        { key: 'Department', value: this.f.department || '—' },
        ...this.f.lineKv,
      ];
      if (this.args.model?.budget) rows.push(BUDGET_ROW[0]);
      return rows;
    }
    <template>
      <article class='emb'>
        <header class='eh'>
          <div class='eh1'>
            <Avatar @name='Pr' @shape='square' @size={{20}} />
            <strong class='nm'>{{this.f.name}}</strong>
            <Chip
              @label={{this.f.status}}
              @tone={{this.f.tone}}
              @appearance='plain'
            />
          </div>
          <div class='eh2'>
            <span class='meta'>{{this.f.sub}}</span>
            <Chip @label={{this.f.linesLabel}} @appearance='plain' />
          </div>
        </header>
        <p class='fact'>Est.
          <strong>{{this.f.total}}</strong>{{#if this.f.neededBy}}
            · needed by
            {{this.f.neededBy}}{{/if}}</p>
        <KeyValue
          class='kv kv-pad'
          @items={{this.items}}
          @divided={{true}}
          @labelStyle='eyebrow'
        >
          <:value as |row|>
            {{#if (eq row.key 'Budget')}}<@fields.budget
                @format='atom'
                @displayContainer={{false}}
              />{{else}}{{row.value}}{{/if}}
          </:value>
        </KeyValue>
      </article>
      <style scoped>
        .kv-pad {
          padding-inline: var(--boxel-sp-sm);
        }

        .emb {
          --pretui-kv-label-font-size: 0.5625rem;
          --pretui-kv-label-color: var(--muted-foreground);
          --boxel-sp-xs: 0.35rem;
          font-size: 0.75rem;
          line-height: 1.25;
          color: var(--card-foreground);
        }
        .eh {
          display: grid;
          gap: 0.25rem;
          padding: 0.4375rem 0.625rem;
          border-block-end: 1px solid var(--border);
        }
        .eh1,
        .eh2 {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          gap: 0.375rem 0.625rem;
        }
        .nm {
          flex: 1;
          min-inline-size: 6rem;
          font-weight: 700;
        }
        .eh2 {
          justify-content: space-between;
        }
        .meta {
          font-size: 0.6875rem;
          color: var(--muted-foreground);
        }
        .fact {
          margin: 0;
          padding: 0.4375rem 0.625rem;
          border-block-end: 1px solid var(--border);
        }
        .kv {
          padding: 0.25rem 0.625rem;
          row-gap: 0;
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    get f() {
      return reqFacts(this.args.model as PurchaseRequisition);
    }
    <template>
      <span class='atom'>
        <Avatar @name='Pr' @shape='square' @size={{16}} />
        <span class='name'>{{this.f.name}}</span>
        <Chip
          class='st'
          @label={{this.f.statusShort}}
          @tone={{this.f.tone}}
          @appearance='plain'
        />
      </span>
      <style scoped>
        .atom {
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
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
        .st {
          flex: none;
          font-weight: 400;
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get f() {
      return reqFacts(this.args.model as PurchaseRequisition);
    }
    get tags() {
      return [{ label: this.f.status, tone: this.f.tone }];
    }
    <template>
      <CompactFitted
        @mark='Pr'
        @title={{this.f.name}}
        @sub={{this.f.sub}}
        @fact={{this.f.fact}}
        @big={{this.f.total}}
        @bigLabel='Est. total'
        @tags={{this.tags}}
      >
        <:rows>
          {{#if this.f.neededBy}}<CompactRow
              @k='Needed by'
              @v={{this.f.neededBy}}
            />{{/if}}
          {{#if this.f.requester}}<CompactRow
              @k='Requester'
              @v={{this.f.requester}}
            />{{/if}}
          {{#if this.f.department}}<CompactRow
              @k='Department'
              @v={{this.f.department}}
            />{{/if}}
          {{#each this.f.lineKv as |row|}}<CompactRow
              @k={{row.key}}
              @v={{row.value}}
            />{{/each}}
          <CompactRow @k='Lines' @v={{this.f.linesCountText}} />
          {{#each this.f.lines as |line|}}<CompactRow
              @k={{line.description}}
              @v={{line.total}}
            />{{/each}}
        </:rows>
      </CompactFitted>
    </template>
  };

  // Grouped by how a requisition is actually captured (who needs what by
  // when → the items themselves → why and against which budget), not by
  // schema order. Three sections — no nav rail needed.
  // estimatedTotal and title are computed (computeVia) and deliberately
  // excluded from the form.
}
