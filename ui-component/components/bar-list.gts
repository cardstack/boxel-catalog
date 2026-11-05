// Pretui — BarList: a ranked list of labelled horizontal bars.
import Component from '@glimmer/component';
import { htmlSafe } from '@ember/template';
import { DataShell, DataSource } from '../data-component';
import type { DataArgs } from '../data-component';
import { cssStyleFrom, cssDeclaration } from '../pretui-css';

const NUMBERS = new Intl.NumberFormat(undefined, {
  maximumFractionDigits: 2,
});

// ── BarList ──────────────────────────────────────────────────────────────

export interface BarListItem {
  /** Row label. */
  name: string;
  /** Magnitude. Negative values are clamped to zero for the bar length. */
  value: number;
  /** Optional href — when present the label becomes a link. */
  href?: string;
  /** Optional hue override for this row's bar. Validated through `cssValue`. */
  hue?: string;
}

export interface BarListArgs extends DataArgs<BarListItem> {
  /** Sort descending by value before rendering. Default true. */
  ranked?: boolean;
  /** Cap the number of rows rendered. The remainder is summarised. */
  limit?: number;
  /** Scale the bars against this instead of the largest value — use it to
   * keep two BarLists comparable side by side. */
  max?: number;
  /** Formats the printed value. Defaults to a locale integer. */
  format?: (value: number) => string;
  /** Accessible name for the list. */
  label?: string;
  /** Row hue. Every bar shares it; per-row `hue` wins. */
  hue?: string;
  /** `'overlay'` (default) tints the bar behind the label. `'track'` puts
   * the label and value on one line with a thin track bar under them, and a
   * divider between rows. */
  layout?: 'overlay' | 'track';
}

export interface BarListSignature {
  Args: BarListArgs;
  Blocks: {
    loading: [];
    empty: [];
    error: [];
  };
  Element: HTMLDivElement;
}

interface BarRow {
  name: string;
  value: number;
  display: string;
  href: string | undefined;
  style: ReturnType<typeof htmlSafe> | undefined;
}

/**
 * The ranked distribution: label, a proportional bar, and the value AS TEXT
 * on every row. Independently the most-copied dashboard component in the
 * audit, and a genuine gap in the kit — `Meter` expresses one level, `Chart`
 * plots a series, and neither answers "which five things are biggest".
 *
 * It needs no plotting engine, so it costs a caller nothing at the package
 * boundary (Law 9): a card that shows a top-five list never loads Plot.
 *
 * Better than the inspiration: upstream bar lists render `<div>` rows with
 * the value in a floated span. Here it is an ordered list — the ranking is
 * in the markup, not implied by visual order — every row carries
 * `role=meter`-equivalent text, the bar is `aria-hidden` because the number
 * beside it already says the same thing, and the bar length is a clamped
 * NUMBER so no caller string reaches the style attribute unvalidated.
 */
export class BarList extends Component<BarListSignature> {
  data = new DataSource<BarListItem>(() => this.args);

  get ranked(): boolean {
    return this.args.ranked ?? true;
  }

  get format(): (value: number) => string {
    return this.args.format ?? ((value: number) => NUMBERS.format(value));
  }

  private get ordered(): BarListItem[] {
    let rows = this.data.visibleRows.slice();
    if (this.ranked) {
      rows.sort((a, b) => b.value - a.value);
    }
    return rows;
  }

  get scale(): number {
    if (this.args.max !== undefined && this.args.max > 0) {
      return this.args.max;
    }
    let top = 0;
    for (let row of this.ordered) {
      if (Number.isFinite(row.value) && row.value > top) {
        top = row.value;
      }
    }
    return top > 0 ? top : 1;
  }

  get layout(): 'overlay' | 'track' {
    return this.args.layout === 'track' ? 'track' : 'overlay';
  }

  get rows(): BarRow[] {
    let limit =
      this.args.limit === undefined
        ? this.ordered.length
        : Math.max(0, Math.round(this.args.limit));
    let scale = this.scale;
    return this.ordered.slice(0, limit).map((row) => {
      // A clamped number can never carry a semicolon, so the percentage is
      // safe by construction; the HUE is a caller string and goes through
      // the kit's allowlist guard instead.
      let pct = Math.max(0, Math.min(100, (row.value / scale) * 100));
      return {
        name: row.name,
        value: row.value,
        display: this.format(row.value),
        href: row.href,
        style: cssStyleFrom([
          '--pretui-barlist-fill: ' + pct.toFixed(2) + '%',
          cssDeclaration('--pretui-barlist-hue', row.hue ?? this.args.hue),
        ]),
      };
    });
  }

  get remainder(): number {
    return Math.max(0, this.ordered.length - this.rows.length);
  }

  <template>
    <div
      class='pretui-barlist'
      data-layout={{this.layout}}
      data-test-pretui-barlist
      ...attributes
    >
      <DataShell
        @state={{this.data}}
        @hasLoading={{has-block 'loading'}}
        @hasEmpty={{has-block 'empty'}}
        @hasError={{has-block 'error'}}
        @emptyTitle='Nothing ranked yet'
        @emptyMessage='No rows to rank. Once the desk logs something it appears here, largest first.'
        @skeletonRows={{4}}
      >
        <:default>
          <ol class='pretui-barlist-rows' aria-label={{@label}}>
            {{#each this.rows key='name' as |row|}}
              <li class='pretui-barlist-row' style={{row.style}}>
                {{! The bar is decoration: the number to its right states the
                    same magnitude, so announcing both would be a stutter. }}
                <span class='pretui-barlist-bar' aria-hidden='true'></span>
                <span class='pretui-barlist-name'>
                  {{#if row.href}}
                    <a href={{row.href}}>{{row.name}}</a>
                  {{else}}
                    {{row.name}}
                  {{/if}}
                </span>
                <span class='pretui-barlist-value'>{{row.display}}</span>
              </li>
            {{/each}}
          </ol>
          {{#if this.remainder}}
            <p class='pretui-barlist-more'>
              {{this.remainder}}
              more not shown.
            </p>
          {{/if}}
        </:default>
        <:loading>{{yield to='loading'}}</:loading>
        <:empty>{{yield to='empty'}}</:empty>
        <:error>{{yield to='error'}}</:error>
      </DataShell>
    </div>

    <style scoped>
      @layer PretComponent {
        .pretui-barlist {
          container-type: inline-size;
          display: block;
          min-width: 0;
          font-family: var(--font-sans);
          color: var(--foreground);
        }
        .pretui-barlist-rows {
          list-style: none;
          margin: 0;
          padding: 0;
          display: grid;
          gap: var(--pretui-barlist-gap, var(--boxel-sp-4xs));
        }
        .pretui-barlist-row {
          position: relative;
          display: grid;
          grid-template-columns: 1fr auto;
          align-items: center;
          gap: var(--boxel-sp-xs);
          min-block-size: var(--pretui-barlist-row-height, var(--boxel-sp-xl));
          padding: var(--boxel-sp-4xs) var(--boxel-sp-xs);
          border-radius: var(--boxel-border-radius-sm);
          font-size: var(--boxel-font-size-xs);
        }
        .pretui-barlist-bar {
          position: absolute;
          inset-block: 0;
          inset-inline-start: 0;
          inline-size: var(--pretui-barlist-fill, 0%);
          border-radius: var(--boxel-border-radius-sm);
          background: color-mix(
            in oklch,
            var(--pretui-barlist-hue, var(--chart-2)) 18%,
            transparent
          );
          /* Law 5: the bar grows when the value changes, which encodes the
             change. It lands on the end state under reduced motion. */
          transition: inline-size 320ms cubic-bezier(0.23, 1, 0.32, 1);
        }
        .pretui-barlist-name {
          position: relative;
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .pretui-barlist-name a {
          color: inherit;
          text-decoration-color: color-mix(
            in oklch,
            currentColor 40%,
            transparent
          );
        }
        .pretui-barlist-name a:focus-visible {
          outline: 2px solid var(--ring);
          outline-offset: 2px;
          border-radius: var(--boxel-border-radius-xs);
        }
        .pretui-barlist-value {
          position: relative;
          font-variant-numeric: tabular-nums;
          font-weight: 600;
          color: var(--muted-foreground);
        }
        .pretui-barlist-more {
          margin: var(--boxel-sp-xs) 0 0;
          color: var(--muted-foreground);
          font-size: var(--boxel-font-size-xs);
        }
        /* track: label and value on one line, a thin full-width track under
           them, a divider between rows */
        .pretui-barlist[data-layout='track'] .pretui-barlist-rows {
          gap: 0;
        }
        .pretui-barlist[data-layout='track'] .pretui-barlist-row {
          grid-template-rows: auto auto;
          row-gap: var(--boxel-sp-2xs);
          padding: var(--boxel-sp-xs) 0;
          border-radius: 0;
          font-size: var(--boxel-font-size-sm);
        }
        .pretui-barlist[data-layout='track']
          .pretui-barlist-row
          + .pretui-barlist-row {
          border-block-start: 1px solid var(--border);
        }
        .pretui-barlist[data-layout='track'] .pretui-barlist-row::after {
          content: '';
          grid-column: 1 / -1;
          grid-row: 2;
          block-size: var(--boxel-sp-4xs);
          border-radius: var(--boxel-border-radius-pill);
          background: var(--muted);
        }
        .pretui-barlist[data-layout='track'] .pretui-barlist-bar {
          position: relative;
          z-index: 1;
          grid-column: 1 / -1;
          grid-row: 2;
          block-size: var(--boxel-sp-4xs);
          border-radius: var(--boxel-border-radius-pill);
          background: var(--pretui-barlist-hue, var(--primary));
        }
        .pretui-barlist[data-layout='track'] .pretui-barlist-name,
        .pretui-barlist[data-layout='track'] .pretui-barlist-value {
          grid-row: 1;
        }
        .pretui-barlist[data-layout='track'] .pretui-barlist-value {
          font-weight: 400;
        }
        @media (prefers-reduced-motion: reduce) {
          .pretui-barlist-bar {
            transition: none;
          }
        }
      }
    </style>
  </template>
}
