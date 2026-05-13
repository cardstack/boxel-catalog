import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { action } from '@ember/object';
import { on } from '@ember/modifier';
import { fn, concat } from '@ember/helper';
import { htmlSafe } from '@ember/template';
import { formatCurrency, formatCurrencyShort } from './utils';

/* ---------- LINE CHART (amortization over time) ---------- */

export interface AmortPoint {
  year: number;
  principalPaid: number;
  interestPaid: number;
  totalPaid: number;
  balance: number;
}

type AmortKey = 'principalPaid' | 'interestPaid' | 'totalPaid' | 'balance';

interface LineSeriesDef {
  key: AmortKey;
  label: string;
  color: string;
  dashed: boolean;
}

interface LineChartSignature {
  Element: SVGElement;
  Args: {
    data: AmortPoint[];
    width?: number;
    height?: number;
    currencyCode?: string;
  };
}

export class LineChart extends GlimmerComponent<LineChartSignature> {
  @tracked hoverYear: number | null = null;
  @tracked enabledKeys: Set<AmortKey> = new Set([
    'totalPaid',
    'principalPaid',
    'interestPaid',
    'balance',
  ]);

  margin = { top: 24, right: 24, bottom: 36, left: 64 };

  seriesDefs: LineSeriesDef[] = [
    {
      key: 'totalPaid',
      label: 'Cumulative Paid',
      color: 'var(--mc-teal, #007272)',
      dashed: false,
    },
    {
      key: 'principalPaid',
      label: 'Cumulative Principal',
      color: 'var(--mc-green, #059669)',
      dashed: false,
    },
    {
      key: 'interestPaid',
      label: 'Cumulative Interest',
      color: 'var(--chart-5, #ef4444)',
      dashed: false,
    },
    {
      key: 'balance',
      label: 'Remaining Balance',
      color: 'var(--chart-2, #589BFF)',
      dashed: true,
    },
  ];

  get width() {
    return this.args.width ?? 640;
  }
  get height() {
    return this.args.height ?? 320;
  }
  get innerWidth() {
    return this.width - this.margin.left - this.margin.right;
  }
  get innerHeight() {
    return this.height - this.margin.top - this.margin.bottom;
  }
  get viewBox() {
    return `0 0 ${this.width} ${this.height}`;
  }
  get xMaxPx() {
    return this.margin.left + this.innerWidth;
  }
  get innerBottomY() {
    return this.margin.top + this.innerHeight;
  }
  get xMax() {
    return this.args.data?.length
      ? this.args.data[this.args.data.length - 1].year
      : 1;
  }
  get yMax() {
    if (!this.args.data?.length) return 1;
    let max = 0;
    for (let point of this.args.data) {
      for (let s of this.seriesDefs) {
        if (!this.enabledKeys.has(s.key)) continue;
        const v = point[s.key];
        if (v > max) max = v;
      }
    }
    return max || 1;
  }

  xFor = (year: number): number => {
    return this.margin.left + (year / (this.xMax || 1)) * this.innerWidth;
  };

  yFor = (value: number): number => {
    return (
      this.margin.top +
      this.innerHeight -
      (value / this.yMax) * this.innerHeight
    );
  };

  get series() {
    return this.seriesDefs.map((s) => {
      const points = this.args.data
        .map((d) => `${this.xFor(d.year)},${this.yFor(d[s.key])}`)
        .join(' ');
      return {
        ...s,
        points,
        dashArray: s.dashed ? '6,4' : '0',
        enabled: this.enabledKeys.has(s.key),
      };
    });
  }

  get yTicks() {
    const ticks: { y: number; label: string }[] = [];
    const steps = 4;
    const cc = this.args.currencyCode ?? 'USD';
    for (let i = 0; i <= steps; i++) {
      const v = (this.yMax / steps) * i;
      ticks.push({
        y: this.yFor(v),
        label: formatCurrencyShort(v, cc),
      });
    }
    return ticks;
  }

  get xTicks() {
    if (!this.args.data?.length) return [];
    const stride = Math.max(1, Math.ceil(this.xMax / 6));
    const out: { year: number; x: number }[] = [];
    for (let y = 0; y <= this.xMax; y += stride) {
      out.push({ year: y, x: this.xFor(y) });
    }
    if (out.length && out[out.length - 1].year !== this.xMax) {
      out.push({ year: this.xMax, x: this.xFor(this.xMax) });
    }
    return out;
  }

  get hoverPoint(): AmortPoint | null {
    if (this.hoverYear === null) return null;
    return this.args.data.find((d) => d.year === this.hoverYear) ?? null;
  }

  get hoverX() {
    return this.hoverPoint ? this.xFor(this.hoverPoint.year) : 0;
  }

  get hoverDots() {
    if (!this.hoverPoint) return [];
    const p = this.hoverPoint;
    return this.seriesDefs
      .filter((s) => this.enabledKeys.has(s.key))
      .map((s) => ({
        cx: this.xFor(p.year),
        cy: this.yFor(p[s.key]),
        color: s.color,
        key: s.key,
      }));
  }

  get tooltipRows() {
    if (!this.hoverPoint) return [];
    const p = this.hoverPoint;
    return this.seriesDefs
      .filter((s) => this.enabledKeys.has(s.key))
      .map((s) => ({
        label: s.label,
        color: s.color,
        value: p[s.key],
        key: s.key,
      }));
  }

  isEnabled = (key: AmortKey): boolean => {
    return this.enabledKeys.has(key);
  };

  toggleClass = (key: AmortKey): string => {
    return this.enabledKeys.has(key) ? 'lc-toggle active' : 'lc-toggle';
  };

  @action
  handleMouseMove(evt: Event) {
    const target = evt.currentTarget as SVGSVGElement;
    const rect = target.getBoundingClientRect();
    const scaleX = this.width / rect.width;
    const relX = ((evt as MouseEvent).clientX - rect.left) * scaleX;
    if (relX < this.margin.left || relX > this.xMaxPx) {
      this.hoverYear = null;
      return;
    }
    const ratio = (relX - this.margin.left) / this.innerWidth;
    const yr = Math.round(ratio * this.xMax);
    this.hoverYear = Math.max(0, Math.min(this.xMax, yr));
  }

  @action
  handleMouseLeave() {
    this.hoverYear = null;
  }

  @action
  toggleSeries(key: AmortKey) {
    const next = new Set(this.enabledKeys);
    if (next.has(key)) {
      next.delete(key);
    } else {
      next.add(key);
    }
    this.enabledKeys = next;
  }

  <template>
    <div class='line-chart'>
      <div class='lc-toggles'>
        {{#each this.seriesDefs as |item|}}
          <button
            type='button'
            class={{this.toggleClass item.key}}
            {{on 'click' (fn this.toggleSeries item.key)}}
          >
            <span
              class='lc-swatch'
              style={{htmlSafe (concat 'background:' item.color)}}
            ></span>
            {{item.label}}
          </button>
        {{/each}}
      </div>
      <svg
        viewBox={{this.viewBox}}
        class='lc-svg'
        role='img'
        aria-label='Mortgage pay-off over time'
        {{on 'mousemove' this.handleMouseMove}}
        {{on 'mouseleave' this.handleMouseLeave}}
      >
        {{#each this.yTicks as |tick|}}
          <line
            x1={{this.margin.left}}
            x2={{this.xMaxPx}}
            y1={{tick.y}}
            y2={{tick.y}}
            class='lc-grid'
          />
          <text
            x={{this.margin.left}}
            y={{tick.y}}
            class='lc-y-label'
            text-anchor='end'
            dx='-8'
            dy='4'
          >{{tick.label}}</text>
        {{/each}}

        {{#each this.xTicks as |tick|}}
          <text
            x={{tick.x}}
            y={{this.innerBottomY}}
            class='lc-x-label'
            text-anchor='middle'
            dy='20'
          >Yr {{tick.year}}</text>
        {{/each}}

        {{#each this.series as |srs|}}
          {{#if srs.enabled}}
            <polyline
              points={{srs.points}}
              fill='none'
              stroke={{srs.color}}
              stroke-width='2.5'
              stroke-linecap='round'
              stroke-linejoin='round'
              stroke-dasharray={{srs.dashArray}}
              class='lc-line'
            />
          {{/if}}
        {{/each}}

        {{#if this.hoverPoint}}
          <line
            x1={{this.hoverX}}
            x2={{this.hoverX}}
            y1={{this.margin.top}}
            y2={{this.innerBottomY}}
            class='lc-guide'
          />
          {{#each this.hoverDots as |dot|}}
            <circle
              cx={{dot.cx}}
              cy={{dot.cy}}
              r='4'
              fill={{dot.color}}
              stroke='#ffffff'
              stroke-width='2'
            />
          {{/each}}
        {{/if}}
      </svg>
      {{#if this.hoverPoint}}
        <div class='lc-tooltip'>
          <div class='lc-tooltip-year'>Year {{this.hoverPoint.year}}</div>
          {{#each this.tooltipRows as |row|}}
            <div class='lc-tooltip-row'>
              <span
                class='lc-swatch'
                style={{htmlSafe (concat 'background:' row.color)}}
              ></span>
              <span class='lc-tooltip-label'>{{row.label}}</span>
              <span class='lc-tooltip-value'>{{formatCurrency
                  row.value
                  @currencyCode
                }}</span>
            </div>
          {{/each}}
        </div>
      {{/if}}
    </div>
    <style scoped>
      .line-chart {
        position: relative;
        width: 100%;
        display: flex;
        flex-direction: column;
        gap: 0.5rem;
      }
      .lc-toggles {
        display: flex;
        flex-wrap: wrap;
        gap: 0.375rem;
        padding: 0 0.5rem;
      }
      .lc-toggle {
        display: inline-flex;
        align-items: center;
        gap: 0.375rem;
        padding: 0.25rem 0.625rem;
        font-size: 0.75rem;
        font-weight: 500;
        background: var(--muted, #f3f4f6);
        color: var(--muted-foreground, #6b7280);
        border: 1px solid var(--border, #e5e7eb);
        border-radius: 999px;
        cursor: pointer;
        transition:
          background 0.18s ease,
          color 0.18s ease,
          box-shadow 0.18s ease;
        font-family: inherit;
      }
      .lc-toggle:hover {
        background: var(--accent, #e5e7eb);
      }
      .lc-toggle.active {
        background: var(--card, #ffffff);
        color: var(--foreground, #111111);
        border-color: var(--ring, #9ca3af);
        box-shadow: var(--shadow-xs, 0 1px 2px rgba(0, 0, 0, 0.06));
      }
      .lc-swatch {
        display: inline-block;
        width: 10px;
        height: 10px;
        border-radius: 3px;
      }
      .lc-svg {
        width: 100%;
        height: auto;
        max-height: 360px;
        font-family: inherit;
        user-select: none;
        cursor: crosshair;
      }
      .lc-grid {
        stroke: var(--border, #e5e7eb);
        stroke-width: 1;
        stroke-dasharray: 2, 3;
        opacity: 0.7;
      }
      .lc-y-label,
      .lc-x-label {
        font-size: 11px;
        fill: var(--muted-foreground, #6b7280);
        font-weight: 500;
      }
      .lc-line {
        animation: lcDraw 1s ease-out;
        stroke-dasharray: 2000;
        stroke-dashoffset: 0;
      }
      .lc-guide {
        stroke: var(--ring, #9ca3af);
        stroke-width: 1;
        stroke-dasharray: 3, 3;
      }
      .lc-tooltip {
        position: absolute;
        top: 2.5rem;
        right: 1rem;
        background: var(--popover, #ffffff);
        color: var(--popover-foreground, #111111);
        border: 1px solid var(--border, #e5e7eb);
        border-radius: 0.5rem;
        padding: 0.625rem 0.75rem;
        box-shadow: var(--shadow-md, 0 4px 12px rgba(0, 0, 0, 0.1));
        font-size: 0.75rem;
        min-width: 220px;
        pointer-events: none;
        z-index: 5;
      }
      .lc-tooltip-year {
        font-weight: 700;
        margin-bottom: 0.375rem;
        font-size: 0.8125rem;
      }
      .lc-tooltip-row {
        display: grid;
        grid-template-columns: 14px 1fr auto;
        align-items: center;
        gap: 0.375rem;
        padding: 0.125rem 0;
      }
      .lc-tooltip-label {
        color: var(--muted-foreground, #6b7280);
      }
      .lc-tooltip-value {
        font-weight: 600;
        font-variant-numeric: tabular-nums;
      }
      @keyframes lcDraw {
        from {
          stroke-dashoffset: 2000;
        }
        to {
          stroke-dashoffset: 0;
        }
      }
      @media (prefers-reduced-motion: reduce) {
        .lc-line {
          animation: none;
        }
      }
    </style>
  </template>
}
