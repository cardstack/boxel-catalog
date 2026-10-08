import GlimmerComponent from '@glimmer/component';
import { htmlSafe } from '@ember/template';
import { gt } from '@cardstack/boxel-ui/helpers';

import { formatAmount } from '../utils';

export interface CompComponent {
  label: string;
  amount: number;
  // Guaranteed pay lands whatever happens. At-risk pay depends on performance,
  // company results, or a vesting schedule that may never complete. The split
  // is the whole point of the component — see the class comment.
  guaranteed: boolean;
  note?: string;
}

interface CompensationBreakdownSignature {
  Args: {
    components: CompComponent[];
    currencyCode?: string;
    // The band this sits in, for the market-position line.
    bandMinimum?: number;
    bandMidpoint?: number;
    bandMaximum?: number;
    heading?: string;
  };
  Element: HTMLElement;
}

const HUES = [
  'var(--comp-a)',
  'var(--comp-b)',
  'var(--comp-c)',
  'var(--comp-d)',
  'var(--comp-e)',
];

/**
 * Total compensation, shown as what it is made of.
 *
 * ### Why a stacked bar and not five numbers
 *
 * The question someone reads a comp statement to answer is **not** "what is
 * the total" — they already know that. It is *"how much of this is actually
 * guaranteed?"* A row of figures makes the reader do that arithmetic; one
 * stacked bar answers it at a glance, which is the only reason to draw
 * anything at all.
 *
 * So the guaranteed portion is drawn solid and the at-risk portion hatched,
 * and the guaranteed subtotal is stated in words beside the total. A £180k
 * offer that is £95k guaranteed is a materially different offer from one that
 * is £150k guaranteed, and nothing else on the screen surfaces that.
 *
 * ### Market position is a marker, not a second chart
 *
 * When a band is supplied, the midpoint is drawn as a tick on the same scale.
 * A separate gauge would make the reader map between two scales to learn one
 * fact.
 */
export class CompensationBreakdown extends GlimmerComponent<CompensationBreakdownSignature> {
  get rows(): (CompComponent & { pct: number; hue: string })[] {
    let list = (this.args.components ?? []).filter(
      (c) => c && Number.isFinite(c.amount) && c.amount > 0,
    );
    let total = list.reduce((n, c) => n + c.amount, 0);
    return list.map((c, i) => ({
      ...c,
      pct: total ? (c.amount / total) * 100 : 0,
      hue: HUES[i % HUES.length],
    }));
  }

  get total(): number {
    return this.rows.reduce((n, c) => n + c.amount, 0);
  }

  get guaranteed(): number {
    return this.rows
      .filter((c) => c.guaranteed)
      .reduce((n, c) => n + c.amount, 0);
  }

  get guaranteedPercent(): number {
    return this.total ? Math.round((this.guaranteed / this.total) * 100) : 0;
  }

  get code(): string {
    return this.args.currencyCode ?? '';
  }

  money = (n: number): string => {
    return `${this.code} ${formatAmount(n)}`.trim();
  };

  segmentStyle = (row: { pct: number; hue: string }) => {
    return htmlSafe(`width:${row.pct}%;--seg:${row.hue}`);
  };

  // Where the midpoint sits on the same 0→total scale the bar uses. Clamped,
  // so a total far above the band still renders a tick inside the track
  // rather than pushing it off the end.
  get midpointStyle() {
    let mid = this.args.bandMidpoint;
    if (!mid || !this.total) {
      return undefined;
    }
    let pct = Math.min(100, Math.max(0, (mid / this.total) * 100));
    return htmlSafe(`left:${pct}%`);
  }

  get marketNote(): string {
    let mid = this.args.bandMidpoint;
    if (!mid || !this.total) {
      return '';
    }
    let ratio = this.total / mid;
    let pct = Math.round((ratio - 1) * 100);
    if (Math.abs(pct) <= 2) {
      return 'At the band midpoint';
    }
    return pct > 0
      ? `${pct}% above the band midpoint`
      : `${Math.abs(pct)}% below the band midpoint`;
  }

  <template>
    <section
      class='comp'
      aria-label={{if @heading @heading 'Compensation'}}
      ...attributes
    >
      <header class='comp-head'>
        <div>
          <h3>{{if @heading @heading 'Total compensation'}}</h3>
          <p class='total'>{{this.money this.total}}</p>
        </div>
        <p class='guar'>
          <strong>{{this.money this.guaranteed}}</strong>
          guaranteed
          <span class='gpct'>({{this.guaranteedPercent}}%)</span>
        </p>
      </header>

      {{#if (gt this.total 0)}}
        <div
          class='track'
          role='img'
          aria-label='{{this.guaranteedPercent}}% of total compensation is guaranteed'
        >
          {{#each this.rows key='label' as |row|}}
            <span
              class='seg {{unless row.guaranteed "at-risk"}}'
              style={{this.segmentStyle row}}
              title='{{row.label}} — {{this.money row.amount}}'
            ></span>
          {{/each}}
          {{#if this.midpointStyle}}
            <span
              class='tick'
              style={{this.midpointStyle}}
              aria-hidden='true'
            ></span>
          {{/if}}
        </div>

        {{#if this.marketNote}}
          <p class='market'>{{this.marketNote}}</p>
        {{/if}}

        <ul class='legend'>
          {{#each this.rows key='label' as |row|}}
            <li>
              <span
                class='dot {{unless row.guaranteed "at-risk"}}'
                style={{this.segmentStyle row}}
              ></span>
              <span class='lab'>{{row.label}}</span>
              {{#unless row.guaranteed}}<span class='risk'>at risk</span>{{/unless}}
              <span class='amt'>{{this.money row.amount}}</span>
            </li>
          {{/each}}
        </ul>
      {{else}}
        <p class='empty' role='status'>No compensation components recorded</p>
      {{/if}}
    </section>

    <style scoped>
      .comp {
        container-type: inline-size;
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-sm);
        min-width: 0;
        padding: var(--boxel-sp);
        background: var(--background, var(--boxel-light));
        color: var(--foreground, var(--boxel-dark));
        border: 1px solid var(--border, var(--boxel-200));
        border-radius: var(--radius, var(--boxel-border-radius));

        /* Five hues mixed from the theme's own accent so the chart stays
           inside whatever palette the host card is wearing. */
        --comp-a: color-mix(
          in oklch,
          var(--primary, var(--boxel-highlight)) 72%,
          var(--foreground, #000)
        );
        --comp-b: color-mix(
          in oklch,
          var(--primary, var(--boxel-highlight)) 52%,
          var(--background, #fff)
        );
        --comp-c: color-mix(
          in oklch,
          var(--primary, var(--boxel-highlight)) 34%,
          var(--background, #fff)
        );
        --comp-d: color-mix(
          in oklch,
          var(--primary, var(--boxel-highlight)) 20%,
          var(--background, #fff)
        );
        --comp-e: color-mix(
          in oklch,
          var(--primary, var(--boxel-highlight)) 10%,
          var(--background, #fff)
        );
      }
      .comp-head {
        display: flex;
        align-items: flex-start;
        justify-content: space-between;
        gap: var(--boxel-sp);
        flex-wrap: wrap;
      }
      .comp-head h3 {
        margin: 0;
        font: 600 var(--boxel-font-xs);
        text-transform: uppercase;
        letter-spacing: var(--boxel-lsp-lg);
        color: var(--muted-foreground, var(--boxel-450));
      }
      .total {
        margin: 2px 0 0;
        font: 700 var(--boxel-font-lg);
        font-variant-numeric: tabular-nums;
      }
      .guar {
        margin: 0;
        align-self: flex-end;
        font: var(--boxel-font-sm);
        font-variant-numeric: tabular-nums;
        color: var(--muted-foreground, var(--boxel-450));
      }
      .guar strong {
        color: var(--foreground, var(--boxel-dark));
      }
      .gpct {
        font-size: var(--boxel-font-size-xs);
      }
      .track {
        position: relative;
        display: flex;
        height: 26px;
        border-radius: 3px;
        overflow: hidden;
        background: var(--muted, var(--boxel-100));
      }
      .seg {
        display: block;
        height: 100%;
        background: var(--seg);
      }
      /* At-risk pay is hatched rather than a different hue: hue already
         encodes which component, and reusing it for certainty would make two
         variables fight over one channel. */
      .seg.at-risk {
        background-image: repeating-linear-gradient(
          45deg,
          transparent 0 4px,
          color-mix(in oklch, var(--background, #fff) 55%, transparent) 4px 8px
        );
      }
      .tick {
        position: absolute;
        top: -3px;
        bottom: -3px;
        width: 2px;
        background: var(--foreground, var(--boxel-dark));
      }
      .market {
        margin: 0;
        font: var(--boxel-font-xs);
        color: var(--muted-foreground, var(--boxel-450));
      }
      .legend {
        list-style: none;
        margin: 0;
        padding: 0;
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xxxs);
      }
      .legend li {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xxs);
        font: var(--boxel-font-sm);
      }
      .dot {
        flex: none;
        width: 10px;
        height: 10px;
        border-radius: 2px;
        background: var(--seg);
      }
      .dot.at-risk {
        background-image: repeating-linear-gradient(
          45deg,
          transparent 0 2px,
          color-mix(in oklch, var(--background, #fff) 55%, transparent) 2px 4px
        );
      }
      .lab {
        flex: 1;
        min-width: 0;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .risk {
        flex: none;
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground, var(--boxel-450));
      }
      .amt {
        flex: none;
        font-variant-numeric: tabular-nums;
      }
      .empty {
        margin: 0;
        padding: var(--boxel-sp) 0;
        text-align: center;
        font: var(--boxel-font-sm);
        color: var(--muted-foreground, var(--boxel-450));
      }
      @container (width < 360px) {
        .guar {
          align-self: flex-start;
        }
      }
    </style>
  </template>
}

export default CompensationBreakdown;
