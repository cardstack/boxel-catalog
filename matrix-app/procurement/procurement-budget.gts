import {
  CardDef,
  Component,
  field,
  contains,
  StringField,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { htmlSafe } from '@ember/template';
import { codeRef, realmURL } from '@cardstack/runtime-common';

import {
  BudgetUtilizationField,
  utilizationBandOf,
} from './budget-utilization-field';
import { formatMoney } from '../commerce/line-item-totals';
import { CompactFitted, CompactRow } from '../commerce/compact-parts';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { Chip } from '@cardstack/pretui/components/chip';
import { KeyValue } from '@cardstack/pretui/components/key-value';
import { ProgressBar } from '@cardstack/pretui/components/progress-bar';
import { Stat } from '@cardstack/pretui/components/stat';

// POs link TO a budget; a runtime ref keeps purchase-order out of this
// module's imports (it imports this one).
// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
const here: string = import.meta.url;
const purchaseOrderRef = codeRef(here, './purchase-order', 'PurchaseOrder');

const money = (n: number) => formatMoney(n, 'USD').replace(/\.00$/, '');

const BAND_TONE = {
  healthy: 'success',
  warning: 'warning',
  critical: 'danger',
  over: 'danger',
} as const;

function budgetFacts(m?: ProcurementBudget) {
  let budget = m?.budgetAmount ?? 0;
  let committed = m?.committed ?? 0;
  let actual = m?.actual ?? 0;
  let pct = budget > 0 ? Math.round(((committed + actual) / budget) * 100) : 0;
  let band = utilizationBandOf(pct);
  let tone = BAND_TONE[band];
  let remaining = budget - committed - actual;
  let pctText = `${pct}%`;
  let budgetText = money(budget);
  let committedText = money(committed);
  let remainingText = money(remaining);
  let kv = (key: string, value: string) => ({ key, value });
  let base = [
    kv('Budget', budgetText),
    kv('Committed', committedText),
    kv('Actual', money(actual)),
  ];
  return {
    title: m?.title ?? 'Untitled Budget',
    sub: `Budget ${budgetText} · ${pctText} used`,
    band,
    tone,
    hue: `var(--${tone})`,
    dotStyle: htmlSafe(`--dot: var(--${tone})`),
    tags: [{ label: band, tone }],
    pct,
    pctText,
    usedText: `${pctText} used`,
    budgetText,
    committedText,
    remainingText,
    factText: `${remainingText} left · ${committedText} committed`,
    ledger: [
      kv('Committed', committedText),
      kv('Actual', money(actual)),
      kv('Used', `${pctText} · ${band}`),
    ],
    fittedRows: [
      ...base,
      kv('Used', pctText),
      kv('Department', m?.department ?? '—'),
      kv('Period', m?.period ?? '—'),
    ],
    embeddedRows: [
      ...base,
      kv('Remaining', remainingText),
      kv('Used', pctText),
      kv('Department', m?.department ?? '—'),
    ],
    details: [
      ...base,
      kv('Remaining', remainingText),
      kv('Used', pctText),
      kv('Department', m?.department ?? '—'),
      kv('Period', m?.period ?? '—'),
    ],
  };
}

// A department's spending envelope for one period, tracked with commitment
// accounting: `committed` is money promised by approved-but-unreceived POs,
// `actual` is money for goods actually received. Both are maintained by the
// single writers that own those transitions (ApprovePurchaseOrderCommand
// moves 0 → committed; ReceiveGoodsCommand moves committed → actual) — never
// hand-edited, never recomputed by a query, so the numbers can't drift from
// the events that produced them.
export class ProcurementBudget extends CardDef {
  static displayName = 'Procurement Budget';
  static headerColor = '#3e4e88';

  @field department = contains(StringField);
  @field period = contains(StringField, {
    description: 'e.g. FY2026 Q1',
  });
  @field budgetAmount = contains(NumberField);
  @field committed = contains(NumberField);
  @field actual = contains(NumberField);

  @field utilization = contains(BudgetUtilizationField, {
    computeVia: function (this: ProcurementBudget) {
      return new BudgetUtilizationField({
        budget: this.budgetAmount ?? 0,
        committed: this.committed ?? 0,
        actual: this.actual ?? 0,
      });
    },
  });

  @field title = contains(StringField, {
    computeVia: function (this: ProcurementBudget) {
      let dept = this.department?.trim();
      let period = this.period?.trim();
      if (dept && period) {
        return `${dept} · ${period}`;
      }
      return dept || period || 'Untitled Budget';
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    get f() {
      return budgetFacts(this.args.model as ProcurementBudget);
    }
    // POs link TO the budget, so they are found by live query.
    poQuery = this.args.context?.getCards(
      this,
      () => {
        let id = this.args.model?.id;
        return id
          ? { filter: { on: purchaseOrderRef, eq: { 'budget.id': id } } }
          : undefined;
      },
      () => {
        let url = (this.args.model as any)?.[realmURL]?.href;
        return url ? [url] : [];
      },
      { isLive: true },
    );
    get charged() {
      return ((this.poQuery?.instances ?? []) as any[]).map((po) => ({
        card: po,
        number: po.poNumber || 'Draft PO',
        sub: [po.lineItems?.[0]?.description, po.vendor?.name]
          .filter(Boolean)
          .join(' · '),
        amount: `${money(po.totalAmount ?? 0)} ${po.status ?? ''}`.trim(),
      }));
    }
    open = (card: CardDef) => this.args.viewCard?.(card);
    <template>
      <article class='ip'>
        <header class='ih'>
          <Avatar @name='Budget' @shape='square' @size={{24}} />
          <div class='id'>
            <h1>{{this.f.title}}</h1>
            <p class='meta'>{{this.f.sub}}</p>
          </div>
          <span class='tags'>
            <Chip
              @label={{this.f.band}}
              @tone={{this.f.tone}}
              @appearance='plain'
            />
            <Chip @label={{this.f.usedText}} @appearance='plain' />
          </span>
        </header>
        <div class='stats'>
          <Stat
            @label='Budget'
            @value={{this.f.budgetText}}
            @roll={{false}}
            @hint={{@model.period}}
          />
          <Stat
            @label='Used'
            @value={{this.f.pctText}}
            @roll={{false}}
            @hint='committed + actual'
          />
          <Stat
            @label='Remaining'
            @tone='success'
            @value={{this.f.remainingText}}
            @roll={{false}}
            @hint='to commit'
          />
        </div>
        <div class='cols'>
          <div>
            <section>
              <h2>Utilisation</h2>
              <div class='pad'>
                <ProgressBar
                  @value={{this.f.pct}}
                  @hue={{this.f.hue}}
                  aria-label='Budget used'
                />
                <KeyValue
                  @items={{this.f.ledger}}
                  @divided={{true}}
                  @labelStyle='eyebrow'
                  class='kv flush'
                />
              </div>
            </section>
            <section>
              <h2>Charged here</h2>
              {{#if this.charged.length}}
                <ul class='list'>
                  {{#each this.charged as |po|}}
                    <li>
                      <button
                        type='button'
                        class='po'
                        {{on 'click' (fn this.open po.card)}}
                      >
                        <span class='two'>
                          <strong>{{po.number}}</strong>
                          <span class='meta'>{{po.sub}}</span>
                        </span>
                        <span class='mono'>{{po.amount}}</span>
                      </button>
                    </li>
                  {{/each}}
                </ul>
              {{else}}
                <p class='empty-note'>No purchase orders charged yet</p>
              {{/if}}
            </section>
          </div>
          <div>
            <section>
              <h2>Details</h2>
              <KeyValue
                @items={{this.f.details}}
                @divided={{true}}
                @labelStyle='eyebrow'
                class='kv'
              />
            </section>
          </div>
        </div>
      </article>
      <style scoped>
        .ip {
          --pretui-kv-label-font-size: 0.5625rem;
          --pretui-kv-label-color: var(--muted-foreground);
          container-type: inline-size;
          border: 1px solid var(--border);
          border-radius: var(--radius);
          font-size: 0.75rem;
          line-height: 1.25;
          color: var(--card-foreground);
          background-color: var(--card);
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
          min-inline-size: 0;
        }
        h1 {
          margin: 0;
          font-family: var(--font-sans);
          font-size: 0.75rem;
          font-weight: 700;
        }
        .meta {
          margin: 0;
          font-size: 0.6875rem;
          color: var(--muted-foreground);
        }
        .tags {
          display: flex;
          gap: 0.5rem;
        }
        .stats {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(8rem, 1fr));
          border-block-start: 1px solid var(--border);
          --text-stat: 1.375rem;
        }
        .stats > * {
          padding: 0.5rem 0.625rem;
        }
        .stats > :not(:first-child) {
          border-inline-start: 1px solid var(--border);
        }
        .cols {
          display: grid;
          grid-template-columns: minmax(0, 3fr) minmax(0, 2fr);
          border-block-start: 1px solid var(--border);
        }
        .cols > div {
          min-inline-size: 0;
        }
        .cols > div + div {
          border-inline-start: 1px solid var(--border);
        }
        section + section {
          border-block-start: 1px solid var(--border);
        }
        @container (width < 40rem) {
          .cols {
            grid-template-columns: minmax(0, 1fr);
          }
          .cols > div + div {
            border-inline-start: 0;
            border-block-start: 1px solid var(--border);
          }
        }
        h2 {
          margin: 0;
          padding: 0.625rem 0.625rem 0.25rem;
          font-size: 0.75rem;
          font-weight: 700;
        }
        .pad {
          padding: 0.25rem 0.625rem 0.4375rem;
        }
        .kv {
          /* KeyValue pads divided rows with --boxel-sp-xs: 0.35rem gives 28px rows */
          --boxel-sp-xs: 0.35rem;
          --boxel-sp-lg: 0.75rem;
          padding-inline: 0.625rem;
          row-gap: 0;
        }
        .kv.flush {
          padding-inline: 0;
          margin-block-start: 0.5rem;
        }
        .list {
          list-style: none;
          margin: 0;
          padding: 0 0.625rem 0.4375rem;
        }
        .list li + li {
          border-block-start: 1px solid var(--border);
        }
        .po {
          all: unset;
          box-sizing: border-box;
          inline-size: 100%;
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: 0.5rem;
          min-block-size: 2.25rem;
          padding-block: 0.25rem;
          cursor: pointer;
        }
        .po:focus-visible {
          outline: 2px solid var(--ring);
        }
        .two {
          display: flex;
          flex-direction: column;
          min-inline-size: 0;
        }
        .two .meta {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .mono {
          flex: none;
          font-family: var(--font-mono);
          font-size: 0.6875rem;
          font-variant-numeric: tabular-nums;
        }
        .empty-note {
          margin: 0;
          padding: 0.25rem 0.625rem 0.4375rem;
          font-size: 0.6875rem;
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    get f() {
      return budgetFacts(this.args.model as ProcurementBudget);
    }
    <template>
      <article class='emb'>
        <header class='eh'>
          <Avatar @name='Budget' @shape='square' @size={{24}} />
          <div class='id'>
            <strong>{{this.f.title}}</strong>
            <span class='meta'>{{this.f.sub}}</span>
          </div>
          <Chip
            @label={{this.f.band}}
            @tone={{this.f.tone}}
            @appearance='plain'
          />
        </header>
        <p class='fact'><strong>{{this.f.remainingText}}</strong>
          left ·
          {{this.f.committedText}}
          committed</p>
        <KeyValue
          @items={{this.f.embeddedRows}}
          @divided={{true}}
          @labelStyle='eyebrow'
          class='kv'
        />
      </article>
      <style scoped>
        .emb {
          --pretui-kv-label-font-size: 0.5625rem;
          --pretui-kv-label-color: var(--muted-foreground);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          font-size: 0.75rem;
          line-height: 1.25;
          color: var(--card-foreground);
          background-color: var(--card);
        }
        .eh {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          gap: 0.5rem;
          padding: 0.5rem 0.625rem;
        }
        .id {
          flex: 1;
          min-inline-size: 0;
          display: flex;
          flex-direction: column;
        }
        .id strong,
        .meta {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .meta {
          font-size: 0.6875rem;
          color: var(--muted-foreground);
        }
        .fact {
          margin: 0;
          padding: 0.4375rem 0.625rem;
          border-block-start: 1px solid var(--border);
        }
        .kv {
          /* KeyValue pads divided rows with --boxel-sp-xs: 0.35rem gives 28px rows */
          --boxel-sp-xs: 0.35rem;
          --boxel-sp-lg: 0.75rem;
          padding-inline: 0.625rem;
          padding-block-end: 0.25rem;
          row-gap: 0;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    get f() {
      return budgetFacts(this.args.model as ProcurementBudget);
    }
    <template>
      <span class='atom'>
        <Avatar @name='Budget' @shape='square' @size={{16}} />
        <span class='name'>{{this.f.title}}</span>
        <span class='pct'>{{this.f.pctText}}</span>
        <span
          class='dot'
          style={{this.f.dotStyle}}
          aria-label={{this.f.band}}
        ></span>
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
        .pct {
          flex: none;
          font-weight: 400;
          color: var(--muted-foreground);
        }
        .dot {
          flex: none;
          inline-size: 0.375rem;
          block-size: 0.375rem;
          border-radius: 50%;
          background-color: var(--dot);
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get f() {
      return budgetFacts(this.args.model as ProcurementBudget);
    }
    <template>
      <CompactFitted
        @mark='Budget'
        @title={{this.f.title}}
        @sub={{this.f.sub}}
        @fact={{this.f.factText}}
        @tags={{this.f.tags}}
      >
        <:rows>
          <div class='bar'><ProgressBar
              @value={{this.f.pct}}
              @hue={{this.f.hue}}
              aria-label='Budget used'
            /></div>
          {{#each this.f.fittedRows as |r|}}
            <CompactRow @k={{r.key}} @v={{r.value}} />
          {{/each}}
        </:rows>
      </CompactFitted>
      <style scoped>
        .bar {
          display: flex;
          align-items: center;
        }
        .bar > * {
          flex: 1;
        }
      </style>
    </template>
  };

  // Envelope first (who / which period / how much), then the commitment
  // ledger — which is command-maintained, so it carries a warning. Two
  // sections, no rail. Computed utilization/title are display-only and
  // excluded.
}
