import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { Button } from '@cardstack/pretui/components/button';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { Table } from '@cardstack/pretui/components/table';

import { StatePill } from '@cardstack/catalog/components/state-pill';
import { COMPACT_EMPTY_STYLE } from '@cardstack/catalog/components/pretui-helpers';
import {
  formatMoney,
  lineTotal,
} from '@cardstack/catalog/cards/commerce/line-item-totals';
import type { VendorQuote } from '../vendor-quote';

// The RFQ Comparison Board — the app's signature element. One column per
// recorded quote, one row per quoted line plus total / lead time / validity /
// compliance, with the best value in every numeric row highlighted and the
// Award action living at the foot of its column. Render-only: the consumer
// (rfq.gts) supplies resolved quotes and the award callback; this component
// has no realm access and mutates nothing.
//
// Award gating shown here is advisory UI — AwardRfqCommand re-enforces both
// gates (stale quote, lapsed compliance) server-side.

interface CellRow {
  label: string;
  values: {
    display: string;
    best: boolean;
  }[];
}

interface ColumnMeta {
  quote: VendorQuote;
  vendorName: string;
  stale: boolean;
  complianceKnown: boolean;
  complianceOk: boolean;
  blocked: boolean;
  blockedReason: string;
  awarded: boolean;
  profile?: unknown;
}

interface Signature {
  Args: {
    quotes: VendorQuote[];
    onAward?: (quote: VendorQuote) => void;
    busy?: boolean;
    awardedId?: string;
    /** RFQ already decided — hide every Award action. */
    decided?: boolean;
    /**
     * Cross-link: when given, the compliance cell becomes a click-through to
     * the vendor's profile — the buyer can jump straight from "lapsed" to
     * the document that lapsed.
     */
    onOpenProfile?: (profile: unknown) => void;
  };
  Element: HTMLElement;
}

function dayLabel(d?: Date | null): string {
  return d
    ? d.toLocaleDateString('en-US', {
        month: 'short',
        day: 'numeric',
        year: 'numeric',
      })
    : '—';
}

export class RfqComparisonBoard extends GlimmerComponent<Signature> {
  get quotes(): VendorQuote[] {
    return (this.args.quotes ?? []).filter(Boolean);
  }

  get columns(): ColumnMeta[] {
    return this.quotes.map((quote) => {
      let vendorName = 'Vendor';
      try {
        vendorName = quote.vendor?.name?.trim() || 'Vendor';
      } catch {
        // linked vendor not loaded — keep the placeholder
      }
      let complianceKnown = false;
      let complianceOk = true;
      let profile: unknown;
      try {
        if (quote.vendorProfile) {
          complianceKnown = true;
          complianceOk = Boolean(quote.vendorProfile.complianceOk);
          profile = quote.vendorProfile;
        }
      } catch {
        // linked profile not loaded — treat as unknown
      }
      let stale = Boolean(quote.isStale);
      let blocked = stale || !complianceKnown || !complianceOk;
      let blockedReason = stale
        ? 'quote expired'
        : !complianceKnown
          ? 'no vendor profile'
          : !complianceOk
            ? 'compliance lapsed'
            : '';
      return {
        quote,
        vendorName,
        stale,
        complianceKnown,
        complianceOk,
        blocked,
        blockedReason,
        awarded: Boolean(
          this.args.awardedId && quote.id === this.args.awardedId,
        ),
        profile,
      };
    });
  }

  openProfile = (profile: unknown) => {
    this.args.onOpenProfile?.(profile);
  };

  // One row per quoted line (labels from the first quote's lines — every
  // quote mirrors the RFQ's requested lines in order), values are that
  // line's total per vendor with the cheapest highlighted.
  get lineRows(): CellRow[] {
    let lineCount = Math.max(
      0,
      ...this.quotes.map((q) => q.lineItems?.length ?? 0),
    );
    let rows: CellRow[] = [];
    for (let i = 0; i < lineCount; i++) {
      let label =
        this.quotes
          .map((q) => q.lineItems?.[i]?.description?.trim())
          .find(Boolean) ?? `Line ${i + 1}`;
      let numbers = this.quotes.map((q) => {
        let item = q.lineItems?.[i];
        return item ? lineTotal(item) : undefined;
      });
      let defined = numbers.filter((n): n is number => n != null);
      let min = defined.length ? Math.min(...defined) : undefined;
      rows.push({
        label,
        values: numbers.map((n) => ({
          display: n != null ? formatMoney(n, 'USD') : '—',
          best: n != null && defined.length > 1 && n === min,
        })),
      });
    }
    return rows;
  }

  get totalRow(): CellRow {
    let totals = this.quotes.map((q) => q.totalAmount ?? 0);
    let min = totals.length ? Math.min(...totals) : 0;
    return {
      label: 'Total',
      values: totals.map((n) => ({
        display: formatMoney(n, 'USD'),
        best: totals.length > 1 && n === min,
      })),
    };
  }

  get leadRow(): CellRow {
    let leads = this.quotes.map((q) => q.leadTimeDays);
    let defined = leads.filter((n): n is number => n != null);
    let min = defined.length ? Math.min(...defined) : undefined;
    return {
      label: 'Lead time',
      values: leads.map((n) => ({
        display: n != null ? `${n} days` : '—',
        best: n != null && defined.length > 1 && n === min,
      })),
    };
  }

  get validityValues(): { display: string; stale: boolean }[] {
    return this.quotes.map((q) => ({
      display: dayLabel(q.validUntil),
      stale: Boolean(q.isStale),
    }));
  }

  award = (quote: VendorQuote) => {
    this.args.onAward?.(quote);
  };

  // The board's narrative beat: it doesn't just line the numbers up, it
  // TELLS the buyer the trade-off they are actually deciding.
  get insight(): string | undefined {
    let cols = this.columns;
    if (cols.length < 2) {
      return undefined;
    }
    let byTotal = [...cols].sort(
      (a, b) => (a.quote.totalAmount ?? 0) - (b.quote.totalAmount ?? 0),
    );
    let byLead = [...cols]
      .filter((c) => c.quote.leadTimeDays != null)
      .sort(
        (a, b) => (a.quote.leadTimeDays ?? 0) - (b.quote.leadTimeDays ?? 0),
      );
    let cheapest = byTotal[0];
    let fastest = byLead[0];
    if (!cheapest || !fastest) {
      return undefined;
    }
    if (cheapest === fastest) {
      return `${cheapest.vendorName} wins on both price and speed — an easy call.`;
    }
    let saving =
      (byTotal[1].quote.totalAmount ?? 0) - (cheapest.quote.totalAmount ?? 0);
    let daysFaster =
      (byLead[1]?.quote.leadTimeDays ?? 0) - (fastest.quote.leadTimeDays ?? 0);
    return `${cheapest.vendorName} saves ${formatMoney(saving, 'USD')}; ${fastest.vendorName} delivers ${daysFaster} days sooner. That is the decision.`;
  }

  <template>
    <div class='board' ...attributes>
      {{#if this.quotes.length}}
        {{#if this.insight}}
          <p class='insight'><span class='insight-mark'>◆</span>
            {{this.insight}}</p>
        {{/if}}
        <Table class='matrix' @label='Quote comparison'>
          <:head>
            <tr>
              <th class='row-label'></th>
              {{#each this.columns as |col|}}
                <th
                  scope='col'
                  class='vendor
                    {{if col.awarded "awarded-col"}}
                    {{if col.blocked "blocked-col"}}'
                >
                  <span class='vendor-name'>{{col.vendorName}}</span>
                  {{#if col.awarded}}
                    <StatePill
                      @label='AWARDED'
                      @hue='green'
                      @emphatic={{true}}
                    />
                  {{else if col.blocked}}
                    <StatePill
                      @label={{col.blockedReason}}
                      @hue='red'
                      @dot={{true}}
                    />
                  {{/if}}
                </th>
              {{/each}}
            </tr>
          </:head>
          <:body>
            {{#each this.lineRows as |row|}}
              <tr class='data-row'>
                <td class='row-label'>{{row.label}}</td>
                {{#each row.values as |cell|}}
                  <td class='num {{if cell.best "best"}}'>
                    <span class='cell-inner'>{{cell.display}}
                      {{#if cell.best}}<span
                          class='best-mark'
                        >◄</span>{{/if}}</span>
                  </td>
                {{/each}}
              </tr>
            {{/each}}
            <tr class='total-row data-row'>
              <td class='row-label'>{{this.totalRow.label}}</td>
              {{#each this.totalRow.values as |cell|}}
                <td class='num {{if cell.best "best"}}'>
                  <span class='cell-inner'>{{cell.display}}
                    {{#if cell.best}}<span
                        class='best-mark'
                      >◄</span>{{/if}}</span>
                </td>
              {{/each}}
            </tr>
            <tr class='data-row'>
              <td class='row-label'>{{this.leadRow.label}}</td>
              {{#each this.leadRow.values as |cell|}}
                <td class='num {{if cell.best "best"}}'>
                  <span class='cell-inner'>{{cell.display}}
                    {{#if cell.best}}<span
                        class='best-mark'
                      >◄</span>{{/if}}</span>
                </td>
              {{/each}}
            </tr>
            <tr class='data-row'>
              <td class='row-label'>Valid until</td>
              {{#each this.validityValues as |cell|}}
                <td class='num {{if cell.stale "stale"}}'>
                  {{cell.display}}
                </td>
              {{/each}}
            </tr>
            <tr class='data-row'>
              <td class='row-label'>Compliance</td>
              {{#each this.columns as |col|}}
                <td>
                  {{#if col.complianceKnown}}
                    {{#if @onOpenProfile}}
                      <button
                        type='button'
                        class='compliance-link'
                        title='Open vendor profile'
                        {{on 'click' (fn this.openProfile col.profile)}}
                      >
                        <StatePill
                          @label={{if col.complianceOk 'current' 'lapsed'}}
                          @hue={{if col.complianceOk 'green' 'red'}}
                          @dot={{true}}
                        />
                        <span
                          class='compliance-arrow'
                          aria-hidden='true'
                        >→</span>
                      </button>
                    {{else}}
                      <StatePill
                        @label={{if col.complianceOk 'current' 'lapsed'}}
                        @hue={{if col.complianceOk 'green' 'red'}}
                        @dot={{true}}
                      />
                    {{/if}}
                  {{else}}
                    <StatePill
                      @label='no profile — link one to see the gate'
                      @hue='slate'
                      @chrome={{true}}
                    />
                  {{/if}}
                </td>
              {{/each}}
            </tr>
            {{#unless @decided}}
              <tr class='action-row'>
                <td class='row-label'></td>
                {{#each this.columns as |col|}}
                  <td>
                    <Button
                      @variant={{if col.blocked 'secondary' 'primary'}}
                      @size='s'
                      @disabled={{if col.blocked true @busy}}
                      class='award-btn'
                      {{on 'click' (fn this.award col.quote)}}
                    >
                      {{if col.blocked 'Blocked' 'Award'}}
                    </Button>
                  </td>
                {{/each}}
              </tr>
            {{/unless}}
          </:body>
        </Table>
      {{else}}
        <EmptyState
          style={{COMPACT_EMPTY_STYLE}}
          @texture={{false}}
          @title='The comparison starts with the first quote'
          @message="Record each vendor's inbound quote and they'll line up here, column against column, best value highlighted."
        />
      {{/if}}
    </div>
    <style scoped>
      .board {
        /* command-console adapter: structure in the procurement ink, signal amber/red */
        --console-ink: var(--procurement-ink, var(--primary-ink));
        overflow: hidden;
      }
      .insight {
        margin: 0 0 var(--boxel-sp-sm);
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        border-left: 0.1875rem solid var(--console-ink);
        background-color: color-mix(
          in oklab,
          var(--console-ink) 6%,
          transparent
        );
        border-radius: 0 var(--radius) var(--radius) 0;
        font-size: 0.9375rem;
        line-height: 1.4;
      }
      .insight-mark {
        color: var(--console-ink);
        margin-right: 0.25rem;
        font-size: var(--boxel-font-size-xs);
      }
      .matrix {
        font-size: var(--boxel-font-size-sm);
      }
      th,
      td {
        vertical-align: middle;
      }
      thead th {
        height: auto;
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm) var(--boxel-sp-sm);
        box-shadow: inset 0 -0.125rem 0 var(--console-ink);
        white-space: normal;
      }
      td {
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
      }
      /* The Table header is mono uppercase; a vendor column holds a name
         and status pills, which keep the body face. */
      .vendor {
        min-width: 10rem;
        font-family: var(--font-sans);
        text-transform: none;
        letter-spacing: normal;
      }
      .vendor-name {
        display: block;
        font-family: var(--font-sans);
        font-weight: 700;
        font-size: 1.0625rem;
        letter-spacing: -0.01em;
        text-transform: none;
        margin-bottom: var(--boxel-sp-5xs);
        color: var(--console-ink);
      }
      .awarded-col {
        background-color: color-mix(in oklab, var(--success) 12%, var(--inset));
      }
      .blocked-col .vendor-name {
        color: var(--muted-foreground);
      }
      tbody td:nth-child(n + 2) {
        border-inline: 1px solid
          color-mix(in oklab, var(--border) 55%, transparent);
      }
      .row-label {
        font-family: var(--boxel-eyebrow-font-family);
        font-size: var(--boxel-eyebrow-font-size);
        font-weight: var(--boxel-eyebrow-font-weight);
        line-height: var(--boxel-eyebrow-line-height);
        letter-spacing: var(--boxel-eyebrow-letter-spacing);
        text-transform: uppercase;
        color: var(--muted-foreground);
        white-space: nowrap;
      }
      .num {
        font-variant-numeric: tabular-nums;
        white-space: nowrap;
        font-size: 0.9375rem;
      }
      .cell-inner {
        display: inline-block;
      }
      .num.best {
        font-weight: 700;
        color: var(--console-ink);
      }
      .num.best .cell-inner {
        position: relative;
        padding: 0.125rem 0.5rem;
        margin: -0.125rem -0.5rem;
        border-radius: var(--radius);
        background-color: color-mix(
          in oklab,
          var(--console-ink) 9%,
          transparent
        );
      }
      .best-mark {
        margin-left: 0.25rem;
        font-size: 0.6875rem;
      }
      .num.stale {
        color: var(--destructive-ink);
      }
      .compliance-link {
        display: inline-flex;
        align-items: center;
        gap: 0.25rem;
        border: none;
        background: none;
        padding: 0.125rem;
        margin: -0.125rem;
        border-radius: var(--radius);
        cursor: pointer;
        font: inherit;
      }
      .compliance-link:hover,
      .compliance-link:focus-visible {
        background-color: color-mix(
          in oklab,
          var(--console-ink) 8%,
          transparent
        );
      }
      .compliance-arrow {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
        transition: transform 140ms ease;
      }
      .compliance-link:hover .compliance-arrow {
        transform: translateX(0.125rem);
        color: var(--console-ink);
      }
      .total-row td {
        box-shadow: inset 0 0.125rem 0 var(--console-ink);
        font-weight: 600;
        font-size: 1.0625rem;
      }
      .action-row td {
        box-shadow: none;
        padding-top: var(--boxel-sp-sm);
      }
      .award-btn {
        min-width: 7rem;
        transition: transform 140ms cubic-bezier(0.34, 1.56, 0.64, 1);
      }
      .award-btn:not(:disabled):hover {
        transform: translateY(-0.0625rem) scale(1.03);
      }
      .award-btn:not(:disabled):active {
        transform: translateY(0) scale(0.98);
      }
      /* choreography: rows arrive as a considered sequence, best cells settle */
      @media (prefers-reduced-motion: no-preference) {
        .insight {
          animation: board-slide-in 360ms cubic-bezier(0.22, 1, 0.36, 1) both;
        }
        thead th {
          animation: board-slide-in 320ms cubic-bezier(0.22, 1, 0.36, 1) both;
          animation-delay: 60ms;
        }
        tbody .data-row {
          animation: board-slide-in 320ms cubic-bezier(0.22, 1, 0.36, 1) both;
        }
        tbody .data-row:nth-child(1) {
          animation-delay: 110ms;
        }
        tbody .data-row:nth-child(2) {
          animation-delay: 160ms;
        }
        tbody .data-row:nth-child(3) {
          animation-delay: 210ms;
        }
        tbody .data-row:nth-child(4) {
          animation-delay: 260ms;
        }
        tbody .data-row:nth-child(5) {
          animation-delay: 310ms;
        }
        tbody .data-row:nth-child(6) {
          animation-delay: 360ms;
        }
        .action-row {
          animation: board-slide-in 320ms cubic-bezier(0.22, 1, 0.36, 1) both;
          animation-delay: 430ms;
        }
        .num.best .cell-inner {
          animation: best-settle 480ms cubic-bezier(0.34, 1.56, 0.64, 1) both;
          animation-delay: 520ms;
        }
        .awarded-col {
          animation: awarded-wash 700ms ease-out both;
        }
      }
      @keyframes board-slide-in {
        from {
          opacity: 0;
          transform: translateY(0.625rem);
        }
        to {
          opacity: 1;
          transform: translateY(0);
        }
      }
      @keyframes best-settle {
        0% {
          transform: scale(0.92);
          background-color: color-mix(
            in oklab,
            var(--console-ink) 24%,
            transparent
          );
        }
        100% {
          transform: scale(1);
        }
      }
      @keyframes awarded-wash {
        from {
          background-color: color-mix(
            in oklab,
            var(--success) 30%,
            var(--inset)
          );
        }
      }
    </style>
  </template>
}
