import { fn } from '@ember/helper';
import { on } from '@ember/modifier';

import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import HomeIcon from '@cardstack/boxel-icons/home';
import {
  CardDef,
  Component,
  field,
  contains,
} from 'https://cardstack.com/base/card-api';
import NumberField from 'https://cardstack.com/base/number';
import StringField from 'https://cardstack.com/base/string';
import AmountWithCurrency from 'https://cardstack.com/base/amount-with-currency';

// ─── Formatters ────────────────────────────────────────────────────────────

function fmt(
  val: number | null | undefined,
  currencyCode?: string | null,
): string {
  if (val == null || isNaN(val) || !isFinite(val)) return '—';
  const cc = currencyCode || 'USD';
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: cc,
    maximumFractionDigits: 0,
  }).format(val);
}

function fmtFull(
  val: number | null | undefined,
  currencyCode?: string | null,
): string {
  if (val == null || isNaN(val) || !isFinite(val)) return '—';
  const cc = currencyCode || 'USD';
  if (val >= 1_000_000) {
    const symbol =
      new Intl.NumberFormat('en-US', { style: 'currency', currency: cc })
        .formatToParts(0)
        .find((p) => p.type === 'currency')?.value ?? cc;
    return symbol + (val / 1_000_000).toFixed(2) + 'M';
  }
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: cc,
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  }).format(val);
}

// ─── Donut Ring Chart ──────────────────────────────────────────────────────

const RING_SIZE = 192;
const RING_STROKE = 28;
const RING_R = (RING_SIZE - RING_STROKE) / 2;
const RING_CX = RING_SIZE / 2;
const RING_CY = RING_SIZE / 2;
const GAP_DEG = 2; // degrees gap between segments

/** Build a filled donut-sector SVG path from startDeg sweeping sweepDeg. */
function donutArcPath(
  cx: number,
  cy: number,
  r: number,
  sw: number,
  startDeg: number,
  sweepDeg: number,
): string {
  if (Math.abs(sweepDeg) < 0.3) return '';
  const clamp = Math.min(Math.abs(sweepDeg), 359.99);
  const toR = (d: number) => (d * Math.PI) / 180;
  const sRad = toR(startDeg);
  const eRad = toR(startDeg + clamp);
  const ro = r + sw / 2;
  const ri = r - sw / 2;
  const f = (n: number) => n.toFixed(3);
  const x1o = cx + ro * Math.cos(sRad);
  const y1o = cy + ro * Math.sin(sRad);
  const x2o = cx + ro * Math.cos(eRad);
  const y2o = cy + ro * Math.sin(eRad);
  const x1i = cx + ri * Math.cos(eRad);
  const y1i = cy + ri * Math.sin(eRad);
  const x2i = cx + ri * Math.cos(sRad);
  const y2i = cy + ri * Math.sin(sRad);
  const la = clamp > 180 ? 1 : 0;
  return (
    `M ${f(x1o)} ${f(y1o)} ` +
    `A ${ro} ${ro} 0 ${la} 1 ${f(x2o)} ${f(y2o)} ` +
    `L ${f(x1i)} ${f(y1i)} ` +
    `A ${ri} ${ri} 0 ${la} 0 ${f(x2i)} ${f(y2i)} Z`
  );
}

interface RingSegment {
  color: string;
  value: number;
  label?: string;
  formattedValue?: string;
}

interface ComputedArc {
  color: string;
  d: string;
  label: string;
  formattedValue: string;
  arcStyle: string;
}

interface DonutRingSignature {
  Args: {
    segments: RingSegment[];
    total: number;
    centerText: string;
    centerSubText: string;
  };
}

class DonutRing extends GlimmerComponent<DonutRingSignature> {
  @tracked hoveredIndex: number | null = null;

  onSegmentEnter = (index: number): void => {
    this.hoveredIndex = index;
  };

  onSegmentLeave = (): void => {
    this.hoveredIndex = null;
  };

  get activeIndex(): number {
    return this.hoveredIndex ?? 0;
  }

  get arcs(): ComputedArc[] {
    const { segments, total } = this.args;
    if (!total || total <= 0) return [];
    let angle = -90;
    return segments.map((seg, i) => {
      const pct = ((seg.value || 0) / total) * 100;
      const fullSweep = (pct / 100) * 360;
      const sweepDeg = Math.max(0, fullSweep - GAP_DEG);
      const startDeg = angle + GAP_DEG / 2;
      const d = donutArcPath(
        RING_CX,
        RING_CY,
        RING_R,
        RING_STROKE,
        startDeg,
        sweepDeg,
      );
      angle += fullSweep;

      const isActive = this.activeIndex === i;

      const arcStyle = isActive
        ? 'filter: brightness(1.5) saturate(1.2); opacity: 1;'
        : 'opacity: 0.3;';

      return {
        color: seg.color,
        d,
        label: seg.label ?? '',
        formattedValue: seg.formattedValue ?? '',
        arcStyle,
      };
    });
  }

  get activeArc(): ComputedArc | null {
    return this.arcs[this.activeIndex] ?? null;
  }

  get centerMainText(): string {
    return this.activeArc?.formattedValue ?? this.args.centerText;
  }

  get centerSubLabel(): string {
    if (!this.activeArc) return this.args.centerSubText;
    const upper = this.activeArc.label.toUpperCase();
    // SVG inner-ring safe width is ~130px at font-size 11; truncate anything > 14 chars
    return upper.length > 14 ? upper.split(' ')[0] + '…' : upper;
  }

  get centerTextColor(): string {
    return this.activeArc?.color ?? '#ffffff';
  }

  <template>
    <svg
      viewBox='0 0 192 192'
      width={{RING_SIZE}}
      height={{RING_SIZE}}
      class='donut-ring'
      aria-hidden='true'
      {{on 'mouseleave' this.onSegmentLeave}}
    >
      {{! Invisible hit-area rect so mouseleave fires reliably over the hole }}
      <rect
        x='0'
        y='0'
        width={{RING_SIZE}}
        height={{RING_SIZE}}
        fill='transparent'
        style='pointer-events: all'
      />

      {{! Background track }}
      <circle
        cx='96'
        cy='96'
        r='82'
        fill='none'
        stroke='rgba(255,255,255,0.08)'
        stroke-width='28'
      />

      {{! Coloured arc segments — only mouseenter here; leave is on the SVG }}
      {{#each this.arcs as |arc i|}}
        {{#if arc.d}}
          <path
            d={{arc.d}}
            fill={{arc.color}}
            class='donut-arc'
            style={{arc.arcStyle}}
            {{on 'mouseenter' (fn this.onSegmentEnter i)}}
          >
            <title>{{arc.label}}: {{arc.formattedValue}}</title>
          </path>
        {{/if}}
      {{/each}}

      {{! Centre text — updates reactively on hover }}
      <text
        x='96'
        y='92'
        text-anchor='middle'
        font-size='20'
        font-weight='800'
        fill={{this.centerTextColor}}
        class='donut-center-main'
      >{{this.centerMainText}}</text>
      <text
        x='96'
        y='113'
        text-anchor='middle'
        font-size='11'
        fill='rgba(255,255,255,0.5)'
        letter-spacing='1'
        class='donut-center-sub'
      >{{this.centerSubLabel}}</text>

      <style>
        .donut-arc {
          cursor: pointer;
          transition:
            opacity 0.5s ease,
            filter 0.5s ease;
        }
        .donut-center-main {
          transition: fill 0.4s ease;
        }
      </style>
    </svg>
  </template>
}

// ─── Standard Wheel View (Modal) ────────────────────────────────────────────

const CX3D = 150;
const CY3D = 150;
const R3D = 118;
const SW3D = 28;
interface Css3DWheelArc {
  color: string;
  d: string;
  label: string;
  formattedValue: string;
  pctLabel: string;
  pct: number;
  isActive: boolean;
  originalIndex: number;
}

interface Css3DWheelSignature {
  Args: {
    segments: RingSegment[];
    total: number;
    centerText: string;
    centerSub: string;
  };
}

class Css3DWheelView extends GlimmerComponent<Css3DWheelSignature> {
  @tracked hoveredIndex: number | null = null;

  onHover = (index: number): void => {
    this.hoveredIndex = index;
  };

  onLeave = (): void => {
    this.hoveredIndex = null;
  };

  get activeIndex(): number {
    return this.hoveredIndex ?? 0;
  }

  get activeSeg(): Css3DWheelArc | null {
    return this.arcs[this.activeIndex] ?? null;
  }

  get centerDisplayText(): string {
    return this.activeSeg?.formattedValue ?? this.args.centerText;
  }

  get centerDisplaySub(): string {
    if (!this.activeSeg) return this.args.centerSub;
    const upper = this.activeSeg.label.toUpperCase();
    return upper.length > 14 ? upper.split(' ')[0] + '…' : upper;
  }

  get centerDisplayColor(): string {
    return this.activeSeg?.color ?? '#ffffff';
  }

  get arcs(): Css3DWheelArc[] {
    const { segments, total } = this.args;
    if (!total || total <= 0) return [];
    let angle = -90;
    return segments.map((seg, i) => {
      const value = seg.value || 0;
      const pct = (value / total) * 100;
      const fullSweep = (pct / 100) * 360;
      const sweepDeg = Math.max(0, fullSweep - GAP_DEG);
      const startDeg = angle + GAP_DEG / 2;
      const d = donutArcPath(CX3D, CY3D, R3D, SW3D, startDeg, sweepDeg);
      angle += fullSweep;
      const isActive = this.activeIndex === i;
      const arcStyle = isActive
        ? `opacity:1;filter:drop-shadow(0 0 14px ${seg.color}) brightness(1.25) saturate(1.2)`
        : 'opacity:0.14';
      return {
        color: seg.color,
        d,
        label: seg.label ?? '',
        formattedValue: seg.formattedValue ?? '',
        pctLabel: Math.round(pct) + '%',
        pct,
        isActive,
        arcStyle,
        originalIndex: i,
      };
    });
  }

  <template>
    <div class='cw-wrap' {{on 'mouseleave' this.onLeave}}>

      {{! ── Left: big flat donut wheel ── }}
      <div class='cw-col-wheel'>
        <div class='cw-donut-glow' aria-hidden='true'></div>
        <svg
          class='cw-svg'
          viewBox='0 0 300 300'
          aria-hidden='true'
          {{on 'mouseleave' this.onLeave}}
        >
          <defs>
            <radialGradient id='cw-center-glow' cx='50%' cy='50%' r='50%'>
              <stop offset='0%' stop-color='rgba(99,102,241,0.28)' />
              <stop offset='60%' stop-color='rgba(99,102,241,0.06)' />
              <stop offset='100%' stop-color='rgba(0,0,0,0)' />
            </radialGradient>
          </defs>

          {{! Background track }}
          <circle
            cx='150'
            cy='150'
            r='118'
            fill='none'
            stroke='rgba(255,255,255,0.06)'
            stroke-width='28'
          />

          {{! Inner decorative ring }}
          <circle
            cx='150'
            cy='150'
            r='82'
            fill='none'
            stroke='rgba(255,255,255,0.04)'
            stroke-width='1'
          />

          {{! Center radial glow }}
          <circle
            cx='150'
            cy='150'
            r='80'
            fill='url(#cw-center-glow)'
            pointer-events='none'
          />

          {{! Segments }}
          {{#each this.arcs as |arc|}}
            {{#if arc.d}}
              <path
                d={{arc.d}}
                fill={{arc.color}}
                class='cw-seg'
                style={{arc.arcStyle}}
                {{on 'mouseenter' (fn this.onHover arc.originalIndex)}}
              >
                <title>{{arc.label}}: {{arc.formattedValue}}</title>
              </path>
            {{/if}}
          {{/each}}

          {{! Centre – shows active segment value or total }}
          <text
            x='150'
            y='141'
            text-anchor='middle'
            font-size='30'
            font-weight='800'
            fill={{this.centerDisplayColor}}
            class='cw-center-val'
          >{{this.centerDisplayText}}</text>
          <text
            x='150'
            y='170'
            text-anchor='middle'
            font-size='16'
            fill='rgba(255,255,255,0.5)'
            letter-spacing='1'
            font-weight='600'
            class='cw-center-sub'
          >{{this.centerDisplaySub}}</text>
        </svg>
      </div>

      {{! ── Right: Category breakdown cards ── }}
      <div class='cw-pills'>
        {{#each this.arcs as |arc|}}
          <div
            class='cw-pill {{if arc.isActive "cw-pill--active" ""}}'
            {{on 'mouseenter' (fn this.onHover arc.originalIndex)}}
          >
            <span class='cw-pill-bar' style='background: {{arc.color}}'></span>
            <div class='cw-pill-info'>
              <div class='cw-pill-row-top'>
                <span class='cw-pill-name'>{{arc.label}}</span>
                <span class='cw-pill-pct'>{{arc.pctLabel}}</span>
              </div>
              <span
                class='cw-pill-val'
                style='color: {{arc.color}}'
              >{{arc.formattedValue}}</span>
              <div class='cw-pill-track'>
                <div
                  class='cw-pill-fill'
                  style='--w: {{arc.pct}}%; background: {{arc.color}}'
                ></div>
              </div>
            </div>
          </div>
        {{/each}}
      </div>

    </div>

    <style>
      .cw-wrap {
        --c-surface: rgba(255, 255, 255, 0.04);
        --c-border: rgba(255, 255, 255, 0.09);
        --c-border-active: rgba(255, 255, 255, 0.28);
        display: flex;
        align-items: center;
        justify-content: center;
        gap: 3.5rem;
        flex: 1;
        padding: 2rem 3rem;
        height: 100%;
        box-sizing: border-box;
        overflow: hidden;
      }

      /* ── Left column ── */
      .cw-col-wheel {
        display: flex;
        flex-direction: column;
        align-items: center;
        flex-shrink: 0;
        position: relative;
      }

      /* Ambient glow orb behind the donut */
      .cw-donut-glow {
        position: absolute;
        width: 320px;
        height: 320px;
        border-radius: 50%;
        background: radial-gradient(
          circle,
          rgba(99, 102, 241, 0.18) 0%,
          rgba(139, 92, 246, 0.1) 40%,
          transparent 70%
        );
        filter: blur(20px);
        pointer-events: none;
        z-index: 0;
      }

      /* ── Flat SVG donut ── */
      .cw-svg {
        width: 300px;
        height: 300px;
        filter: drop-shadow(0 2px 24px rgba(0, 0, 0, 0.7));
        position: relative;
        z-index: 1;
        animation: cw-breathe 5s cubic-bezier(0.45, 0.05, 0.55, 0.95) infinite;
      }

      @keyframes cw-breathe {
        0%,
        100% {
          filter: drop-shadow(0 2px 24px rgba(0, 0, 0, 0.7))
            drop-shadow(0 0 0px rgba(99, 102, 241, 0));
        }
        50% {
          filter: drop-shadow(0 2px 24px rgba(0, 0, 0, 0.5))
            drop-shadow(0 0 32px rgba(99, 102, 241, 0.22));
        }
      }

      .cw-seg {
        cursor: pointer;
        transition:
          opacity 0.45s ease,
          filter 0.45s ease;
      }

      .cw-center-val {
        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
        transition: fill 0.3s ease;
      }

      .cw-center-sub {
        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
      }

      /* ── Pills ── */
      .cw-pills {
        display: flex;
        flex-direction: column;
        gap: 0.625rem;
        width: 264px;
        flex-shrink: 0;
      }

      .cw-pill {
        display: flex;
        align-items: stretch;
        background: var(--c-surface);
        border: 1px solid var(--c-border);
        border-radius: 12px;
        overflow: hidden;
        cursor: pointer;
        transition:
          background 0.22s ease,
          border-color 0.22s ease,
          transform 0.22s ease,
          box-shadow 0.22s ease;
        backdrop-filter: blur(8px);
      }

      .cw-pill:hover {
        background: rgba(255, 255, 255, 0.075);
        border-color: rgba(255, 255, 255, 0.18);
        transform: translateX(-2px);
      }

      .cw-pill--active {
        background: rgba(255, 255, 255, 0.1);
        border-color: var(--c-border-active);
        transform: translateX(-5px);
        box-shadow:
          0 4px 20px rgba(0, 0, 0, 0.45),
          0 0 0 1px rgba(255, 255, 255, 0.14),
          inset 0 1px 0 rgba(255, 255, 255, 0.08);
      }

      .cw-pill-bar {
        width: 4px;
        flex-shrink: 0;
        opacity: 0.45;
        transition: opacity 0.22s ease;
      }

      .cw-pill--active .cw-pill-bar {
        opacity: 1;
      }

      .cw-pill-info {
        flex: 1;
        display: flex;
        flex-direction: column;
        gap: 4px;
        padding: 0.75rem 1rem;
        min-width: 0;
      }

      .cw-pill-row-top {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 0.5rem;
      }

      .cw-pill-name {
        font-size: 0.625rem;
        font-weight: 700;
        color: rgba(255, 255, 255, 0.45);
        text-transform: uppercase;
        letter-spacing: 0.1em;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }

      .cw-pill--active .cw-pill-name {
        color: rgba(255, 255, 255, 0.7);
      }

      .cw-pill-pct {
        font-size: 0.625rem;
        font-weight: 700;
        color: rgba(255, 255, 255, 0.3);
        flex-shrink: 0;
        letter-spacing: 0.06em;
      }

      .cw-pill--active .cw-pill-pct {
        color: rgba(255, 255, 255, 0.55);
      }

      .cw-pill-val {
        font-size: 1.125rem;
        font-weight: 800;
        font-variant-numeric: tabular-nums;
        letter-spacing: -0.03em;
        line-height: 1;
        filter: drop-shadow(0 0 8px currentColor);
        opacity: 0.9;
        transition: opacity 0.22s ease;
      }

      .cw-pill--active .cw-pill-val {
        opacity: 1;
        filter: drop-shadow(0 0 12px currentColor);
      }

      .cw-pill-track {
        height: 3px;
        border-radius: 99px;
        background: rgba(255, 255, 255, 0.07);
        overflow: hidden;
        margin-top: 6px;
      }

      .cw-pill-fill {
        height: 100%;
        border-radius: 99px;
        width: var(--w, 0%);
        opacity: 0.6;
      }

      .cw-pill--active .cw-pill-fill {
        opacity: 1;
      }
    </style>
  </template>
}

interface BarChartSignature {
  Args: {
    segments: RingSegment[];
    total: number;
    currency: string;
    lifetimePrincipal: number | null | undefined;
    lifetimeTaxes: number | null | undefined;
    lifetimeInsurance: number | null | undefined;
    lifetimeHoa: number | null | undefined;
    lifetimeTotal: number | null | undefined;
  };
}

class BarChartView extends GlimmerComponent<BarChartSignature> {
  get rows() {
    const { segments, total } = this.args;
    const lifetimes = [
      this.args.lifetimePrincipal,
      this.args.lifetimeTaxes,
      this.args.lifetimeInsurance,
      this.args.lifetimeHoa,
    ];
    return segments.map((seg, i) => ({
      color: seg.color,
      label: seg.label ?? '',
      monthly: seg.formattedValue ?? '—',
      lifetime: fmtFull(lifetimes[i], this.args.currency),
      barPct: total > 0 ? Math.max(2, ((seg.value || 0) / total) * 100) : 0,
      pctLabel:
        total > 0 ? Math.round(((seg.value || 0) / total) * 100) + '%' : '0%',
    }));
  }

  <template>
    <div class='bv-wrap'>
      <div class='bv-header'>
        <span class='bv-col-cat'>Category</span>
        <span class='bv-col-bar'></span>
        <span class='bv-col-mo'>Monthly</span>
        <span class='bv-col-life'>Lifetime</span>
        <span class='bv-col-pct'>Share</span>
      </div>
      {{#each this.rows as |row|}}
        <div class='bv-row'>
          <div class='bv-cat'>
            <span class='bv-dot' style='background:{{row.color}}'></span>
            <span class='bv-name'>{{row.label}}</span>
          </div>
          <div class='bv-bar-track'>
            <div
              class='bv-bar-fill'
              style='--w:{{row.barPct}}%;background:{{row.color}}'
            ></div>
          </div>
          <span class='bv-mo'>{{row.monthly}}</span>
          <span class='bv-life'>{{row.lifetime}}</span>
          <span class='bv-pct'>{{row.pctLabel}}</span>
        </div>
      {{/each}}
      <div class='bv-total-row'>
        <div class='bv-cat'>
          <span class='bv-dot bv-dot--total'></span>
          <span class='bv-name bv-name--bold'>Total</span>
        </div>
        <div class='bv-bar-track'>
          <div class='bv-bar-fill bv-bar-fill--total' style='--w:100%'></div>
        </div>
        <span class='bv-mo bv-mo--bold'>{{fmt @total @currency}}</span>
        <span class='bv-life bv-life--bold'>{{fmtFull
            @lifetimeTotal
            @currency
          }}</span>
        <span class='bv-pct'>100%</span>
      </div>
    </div>

    <style>
      .bv-wrap {
        display: flex;
        flex-direction: column;
        padding: 2rem 2.5rem;
        height: 100%;
        box-sizing: border-box;
        overflow-y: auto;
        gap: 0;
      }

      .bv-header {
        display: grid;
        grid-template-columns: 210px 1fr 120px 140px 72px;
        gap: 14px;
        align-items: center;
        padding-bottom: 0.75rem;
        border-bottom: 2px solid rgba(255, 255, 255, 0.1);
        margin-bottom: 0.25rem;
      }

      .bv-col-cat,
      .bv-col-mo,
      .bv-col-life,
      .bv-col-pct {
        font-size: 0.625rem;
        font-weight: 700;
        letter-spacing: 0.1em;
        text-transform: uppercase;
        color: rgba(255, 255, 255, 0.4);
      }

      .bv-col-mo,
      .bv-col-life,
      .bv-col-pct {
        text-align: right;
      }

      .bv-row,
      .bv-total-row {
        display: grid;
        grid-template-columns: 210px 1fr 120px 140px 72px;
        gap: 14px;
        align-items: center;
        padding: 0.875rem 0;
        border-bottom: 1px solid rgba(255, 255, 255, 0.06);
      }

      .bv-total-row {
        border-top: 2px solid rgba(255, 255, 255, 0.14);
        border-bottom: none;
        margin-top: 0.375rem;
      }

      .bv-cat {
        display: flex;
        align-items: center;
        gap: 10px;
      }

      .bv-dot {
        width: 11px;
        height: 11px;
        border-radius: 50%;
        flex-shrink: 0;
      }

      .bv-dot--total {
        background: linear-gradient(135deg, #6366f1, #8b5cf6);
      }

      .bv-name {
        font-size: 0.875rem;
        font-weight: 500;
        color: rgba(255, 255, 255, 0.82);
        white-space: nowrap;
      }

      .bv-name--bold {
        font-weight: 800;
        color: rgba(255, 255, 255, 0.96);
      }

      .bv-bar-track {
        height: 10px;
        border-radius: 99px;
        background: rgba(255, 255, 255, 0.07);
        overflow: hidden;
      }

      .bv-bar-fill {
        height: 100%;
        border-radius: 99px;
        width: var(--w, 0%);
      }

      .bv-bar-fill--total {
        background: linear-gradient(90deg, #6366f1, #8b5cf6);
      }

      .bv-mo,
      .bv-life,
      .bv-pct {
        font-size: 0.875rem;
        font-weight: 600;
        color: rgba(255, 255, 255, 0.72);
        text-align: right;
        font-variant-numeric: tabular-nums;
      }

      .bv-mo--bold,
      .bv-life--bold {
        font-weight: 800;
        color: rgba(255, 255, 255, 0.95);
      }

      .bv-pct {
        font-size: 0.8125rem;
        color: rgba(255, 255, 255, 0.45);
      }
    </style>
  </template>
}

// ─── Isolated Template ────────────────────────────────────────────────────────

class IsolatedTemplate extends Component<typeof MortgageCalculator> {
  // ── Modal state ──────────────────────────────────────────────────────
  @tracked isModalOpen = false;
  @tracked modalView: 'wheel' | 'bar' = 'wheel';

  openModal = (): void => {
    this.isModalOpen = true;
  };
  closeModal = (): void => {
    this.isModalOpen = false;
  };
  switchToWheel = (): void => {
    this.modalView = 'wheel';
  };
  switchToBar = (): void => {
    this.modalView = 'bar';
  };
  stopModalProp = (e: Event): void => {
    e.stopPropagation();
  };

  get isWheelView(): boolean {
    return this.modalView === 'wheel';
  }
  get isBarView(): boolean {
    return this.modalView === 'bar';
  }
  get tabWheelClass(): string {
    return this.modalView === 'wheel'
      ? 'mc-mod-tab mc-mod-tab--active'
      : 'mc-mod-tab';
  }
  get tabBarClass(): string {
    return this.modalView === 'bar'
      ? 'mc-mod-tab mc-mod-tab--active'
      : 'mc-mod-tab';
  }

  get displayCurrency(): string {
    return this.args.model.homePrice?.currency?.code ?? 'USD';
  }

  get chartSegments() {
    const m = this.args.model;
    const cc = this.displayCurrency;
    return [
      {
        color: '#2563eb',
        value: m.monthlyMortgagePayment ?? 0,
        label: 'Principal & Interest',
        formattedValue: fmt(m.monthlyMortgagePayment, cc),
      },
      {
        color: '#f59e0b',
        value: m.taxPerMonth?.amount ?? 0,
        label: 'Property Tax',
        formattedValue: fmt(m.taxPerMonth?.amount, cc),
      },
      {
        color: '#10b981',
        value: m.insurancePerMonth?.amount ?? 0,
        label: 'Insurance',
        formattedValue: fmt(m.insurancePerMonth?.amount, cc),
      },
      {
        color: '#8b5cf6',
        value: m.hoaFeesPerMonth?.amount ?? 0,
        label: 'HOA Fees',
        formattedValue: fmt(m.hoaFeesPerMonth?.amount, cc),
      },
    ].filter((s) => s.value > 0);
  }

  get chartTotal() {
    return this.args.model.monthlyTotal ?? 0;
  }

  get centerText() {
    return fmt(this.args.model.monthlyTotal, this.displayCurrency);
  }

  <template>
    <div class='mc-iso'>

      {{! ── New 2-col layout: sidebar LEFT, right panel contains hero + results ── }}
      <div class='mc-body'>

        {{! ── Left: inputs sidebar (always visible) ── }}
        <aside class='mc-sidebar'>
          <div class='mc-sidebar-inner'>

            <div class='mc-group'>
              <div class='mc-group-label'>
                <svg
                  width='11'
                  height='11'
                  viewBox='0 0 24 24'
                  fill='none'
                  stroke='currentColor'
                  stroke-width='2.5'
                  aria-hidden='true'
                ><path
                    d='M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z'
                  /></svg>
                Purchase
              </div>
              <div class='mc-field-row'>
                <label class='mc-label'>Home Price</label>
                <@fields.homePrice @format='edit' />
              </div>
              <div class='mc-field-row'>
                <label class='mc-label'>Down Payment</label>
                <div class='mc-input-row'>
                  <@fields.downPaymentPercentage @format='edit' />
                  <span class='mc-unit'>%</span>
                </div>
              </div>
            </div>

            <div class='mc-group'>
              <div class='mc-group-label'>
                <svg
                  width='11'
                  height='11'
                  viewBox='0 0 24 24'
                  fill='none'
                  stroke='currentColor'
                  stroke-width='2.5'
                  aria-hidden='true'
                ><rect x='2' y='7' width='20' height='14' rx='2' /><path
                    d='M16 7V5a2 2 0 0 0-4 0v2'
                  /></svg>
                Loan Terms
              </div>
              <div class='mc-field-row'>
                <label class='mc-label'>Interest Rate</label>
                <div class='mc-input-row'>
                  <@fields.interestRatePercentage @format='edit' />
                  <span class='mc-unit'>%</span>
                </div>
              </div>
              <div class='mc-field-row'>
                <label class='mc-label'>Loan Term</label>
                <div class='mc-input-row'>
                  <@fields.loanTermYears @format='edit' />
                  <span class='mc-unit'>yrs</span>
                </div>
              </div>
            </div>

            <div class='mc-group'>
              <div class='mc-group-label'>
                <svg
                  width='11'
                  height='11'
                  viewBox='0 0 24 24'
                  fill='none'
                  stroke='currentColor'
                  stroke-width='2.5'
                  aria-hidden='true'
                ><line x1='12' y1='1' x2='12' y2='23' /><path
                    d='M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6'
                  /></svg>
                Monthly Costs
              </div>
              <div class='mc-field-row'>
                <label class='mc-label'>Property Tax</label>
                <@fields.taxPerMonth @format='edit' />
              </div>
              <div class='mc-field-row'>
                <label class='mc-label'>Home Insurance</label>
                <@fields.insurancePerMonth @format='edit' />
              </div>
              <div class='mc-field-row'>
                <label class='mc-label'>HOA Fees</label>
                <@fields.hoaFeesPerMonth @format='edit' />
              </div>
            </div>

          </div>
        </aside>

        {{! ── Right column: hero on top, results below ── }}
        <div class='mc-right-col'>

          {{! Dark hero panel at top of right column }}
          <div class='mc-hero'>
            <div class='mc-hero-left'>
              <div class='mc-hero-eyebrow'>
                <svg
                  width='14'
                  height='14'
                  viewBox='0 0 24 24'
                  fill='none'
                  stroke='currentColor'
                  stroke-width='2'
                  class='mc-hero-eyebrow-icon'
                  aria-hidden='true'
                ><path
                    d='M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z'
                  /><polyline points='9 22 9 12 15 12 15 22' /></svg>
                <span>Mortgage Calculator</span>
              </div>
              <h1 class='mc-hero-title'>{{@model.title}}</h1>
              <div class='mc-hero-payment'>
                <span class='mc-hero-amount'>{{fmt
                    @model.monthlyTotal
                    this.displayCurrency
                  }}</span>
                <div class='mc-hero-amount-meta'>
                  <span class='mc-hero-mo'>/ month</span>
                </div>
              </div>
              <div class='mc-hero-pills'>
                <div class='mc-hero-pill'>
                  <span class='mc-hero-pill-label'>Loan</span>
                  <span class='mc-hero-pill-value'>{{fmt
                      @model.loanAmount
                      this.displayCurrency
                    }}</span>
                </div>
                <div class='mc-hero-pill'>
                  <span class='mc-hero-pill-label'>Down</span>
                  <span
                    class='mc-hero-pill-value'
                  >{{@model.downPaymentPercentage}}%</span>
                </div>
                <div class='mc-hero-pill'>
                  <span class='mc-hero-pill-label'>Rate</span>
                  <span
                    class='mc-hero-pill-value'
                  >{{@model.interestRatePercentage}}%</span>
                </div>
                <div class='mc-hero-pill'>
                  <span class='mc-hero-pill-label'>Term</span>
                  <span
                    class='mc-hero-pill-value'
                  >{{@model.loanTermYears}}yr</span>
                </div>
              </div>
            </div>
            <div class='mc-hero-right'>
              <div class='mc-ring-wrap'>
                <DonutRing
                  @segments={{this.chartSegments}}
                  @total={{this.chartTotal}}
                  @centerText={{this.centerText}}
                  @centerSubText='PER MONTH'
                />
                <button
                  type='button'
                  class='mc-breakdown-btn'
                  {{on 'click' this.openModal}}
                >
                  <svg
                    width='11'
                    height='11'
                    viewBox='0 0 24 24'
                    fill='none'
                    stroke='currentColor'
                    stroke-width='2.5'
                    aria-hidden='true'
                  ><polyline points='15 3 21 3 21 9' /><polyline
                      points='9 21 3 21 3 15'
                    /><line x1='21' y1='3' x2='14' y2='10' /><line
                      x1='3'
                      y1='21'
                      x2='10'
                      y2='14'
                    /></svg>
                  View Breakdown
                </button>
              </div>
              <div class='mc-hero-legend'>
                <div class='mc-hero-legend-row'>
                  <span
                    class='mc-hero-swatch'
                    style='background:#2563eb'
                  ></span>
                  <span class='mc-hero-legend-name'>Principal &amp; Interest</span>
                  <span class='mc-hero-legend-val'>{{fmt
                      @model.monthlyMortgagePayment
                      this.displayCurrency
                    }}</span>
                </div>
                <div class='mc-hero-legend-row'>
                  <span
                    class='mc-hero-swatch'
                    style='background:#f59e0b'
                  ></span>
                  <span class='mc-hero-legend-name'>Property Tax</span>
                  <span class='mc-hero-legend-val'>{{fmt
                      @model.taxPerMonth.amount
                      this.displayCurrency
                    }}</span>
                </div>
                <div class='mc-hero-legend-row'>
                  <span
                    class='mc-hero-swatch'
                    style='background:#10b981'
                  ></span>
                  <span class='mc-hero-legend-name'>Insurance</span>
                  <span class='mc-hero-legend-val'>{{fmt
                      @model.insurancePerMonth.amount
                      this.displayCurrency
                    }}</span>
                </div>
                <div class='mc-hero-legend-row'>
                  <span
                    class='mc-hero-swatch'
                    style='background:#8b5cf6'
                  ></span>
                  <span class='mc-hero-legend-name'>HOA Fees</span>
                  <span class='mc-hero-legend-val'>{{fmt
                      @model.hoaFeesPerMonth.amount
                      this.displayCurrency
                    }}</span>
                </div>
              </div>
            </div>
          </div>

          {{! Results below hero ── }}
          <div class='mc-results'>

            {{! Stat cards row ── }}
            <div class='mc-stat-cards'>
              <div class='mc-stat-card mc-stat-card--blue'>
                <div class='mc-stat-card-label'>Loan Amount</div>
                <div class='mc-stat-card-value'>{{fmt
                    @model.loanAmount
                    this.displayCurrency
                  }}</div>
                <div class='mc-stat-card-bar'>
                  <div class='mc-stat-card-track'>
                    <div class='mc-stat-card-fill mc-fill--blue'></div>
                  </div>
                </div>
              </div>
              <div class='mc-stat-card mc-stat-card--emerald'>
                <div class='mc-stat-card-label'>Down Payment</div>
                <div class='mc-stat-card-value'>{{fmt
                    @model.downPayment
                    this.displayCurrency
                  }}</div>
                <div class='mc-stat-card-bar'>
                  <div class='mc-stat-card-track'>
                    <div class='mc-stat-card-fill mc-fill--emerald'></div>
                  </div>
                </div>
              </div>
              <div class='mc-stat-card mc-stat-card--slate'>
                <div class='mc-stat-card-label'>Loan Term</div>
                <div class='mc-stat-card-value'>{{@model.loanTermYears}}<span
                    class='mc-stat-card-unit'
                  >yr</span></div>
                <div class='mc-stat-card-bar'>
                  <div class='mc-stat-card-track'>
                    <div class='mc-stat-card-fill mc-fill--slate'></div>
                  </div>
                </div>
              </div>
              <div class='mc-stat-card mc-stat-card--violet'>
                <div class='mc-stat-card-label'>Lifetime Cost</div>
                <div class='mc-stat-card-value'>{{fmtFull
                    @model.lifetimeTotal
                    this.displayCurrency
                  }}</div>
                <div class='mc-stat-card-bar'>
                  <div class='mc-stat-card-track'>
                    <div class='mc-stat-card-fill mc-fill--violet'></div>
                  </div>
                </div>
              </div>
            </div>

            {{! Breakdown table ── }}
            <section class='mc-section'>
              <div class='mc-section-head'>
                <svg
                  width='12'
                  height='12'
                  viewBox='0 0 24 24'
                  fill='none'
                  stroke='currentColor'
                  stroke-width='2.5'
                  class='mc-section-icon'
                  aria-hidden='true'
                ><line x1='8' y1='6' x2='21' y2='6' /><line
                    x1='8'
                    y1='12'
                    x2='21'
                    y2='12'
                  /><line x1='8' y1='18' x2='21' y2='18' /><line
                    x1='3'
                    y1='6'
                    x2='3.01'
                    y2='6'
                  /><line x1='3' y1='12' x2='3.01' y2='12' /><line
                    x1='3'
                    y1='18'
                    x2='3.01'
                    y2='18'
                  /></svg>
                Payment Breakdown
              </div>
              <div class='mc-table-head'>
                <span></span>
                <span class='mc-col-h'>Category</span>
                <span class='mc-col-h'>Monthly</span>
                <span class='mc-col-h'>Lifetime</span>
              </div>
              <div class='mc-row'>
                <span class='mc-dot' style='background:#2563eb'></span>
                <span class='mc-row-name'>Principal &amp; Interest</span>
                <span class='mc-row-num'>{{fmt
                    @model.monthlyMortgagePayment
                    this.displayCurrency
                  }}</span>
                <span class='mc-row-num'>{{fmtFull
                    @model.lifetimeMortgagePayment
                    this.displayCurrency
                  }}</span>
              </div>
              <div class='mc-row'>
                <span class='mc-dot' style='background:#f59e0b'></span>
                <span class='mc-row-name'>Property Tax</span>
                <span class='mc-row-num'>{{fmt
                    @model.taxPerMonth.amount
                    this.displayCurrency
                  }}</span>
                <span class='mc-row-num'>{{fmtFull
                    @model.lifetimeTaxes
                    this.displayCurrency
                  }}</span>
              </div>
              <div class='mc-row'>
                <span class='mc-dot' style='background:#10b981'></span>
                <span class='mc-row-name'>Home Insurance</span>
                <span class='mc-row-num'>{{fmt
                    @model.insurancePerMonth.amount
                    this.displayCurrency
                  }}</span>
                <span class='mc-row-num'>{{fmtFull
                    @model.lifetimeInsurance
                    this.displayCurrency
                  }}</span>
              </div>
              <div class='mc-row'>
                <span class='mc-dot' style='background:#8b5cf6'></span>
                <span class='mc-row-name'>HOA Fees</span>
                <span class='mc-row-num'>{{fmt
                    @model.hoaFeesPerMonth.amount
                    this.displayCurrency
                  }}</span>
                <span class='mc-row-num'>{{fmtFull
                    @model.lifetimeHoaFees
                    this.displayCurrency
                  }}</span>
              </div>
              <div class='mc-row mc-row--total'>
                <span class='mc-dot mc-dot--total'></span>
                <span class='mc-row-name'>Total Out-of-Pocket</span>
                <span class='mc-row-num mc-row-num--bold'>{{fmt
                    @model.monthlyTotal
                    this.displayCurrency
                  }}</span>
                <span class='mc-row-num mc-row-num--bold'>{{fmtFull
                    @model.lifetimeTotal
                    this.displayCurrency
                  }}</span>
              </div>
            </section>

          </div>
        </div>{{! end mc-right-col }}
      </div>{{! end mc-body }}

      {{! ── Full-overlay Modal ─────────────────────────────────────── }}
      {{#if this.isModalOpen}}
        <div
          class='mc-modal-backdrop'
          role='dialog'
          aria-modal='true'
          {{on 'click' this.closeModal}}
        >
          <div class='mc-modal' {{on 'click' this.stopModalProp}}>

            {{! Decorative background orbs }}
            <div class='mc-modal-orbs' aria-hidden='true'>
              <div class='mc-orb mc-orb--blue'></div>
              <div class='mc-orb mc-orb--violet'></div>
              <div class='mc-orb mc-orb--amber'></div>
              <div class='mc-orb mc-orb--emerald'></div>
            </div>

            {{! Header: title + total + tabs + close }}
            <div class='mc-modal-header'>
              <div class='mc-modal-header-left'>
                <span class='mc-modal-title'>Mortgage Breakdown</span>
                <div class='mc-modal-total-badge'>
                  <span class='mc-modal-total-amount'>{{this.centerText}}</span>
                  <span class='mc-modal-total-label'>/ mo total</span>
                </div>
              </div>

              <div class='mc-modal-header-right'>
                <div class='mc-modal-tabs'>
                  <button
                    type='button'
                    class={{this.tabWheelClass}}
                    {{on 'click' this.switchToWheel}}
                  >
                    <svg
                      width='13'
                      height='13'
                      viewBox='0 0 24 24'
                      fill='none'
                      stroke='currentColor'
                      stroke-width='2'
                      aria-hidden='true'
                    ><circle cx='12' cy='12' r='10' /><circle
                        cx='12'
                        cy='12'
                        r='4'
                      /></svg>
                    Wheel
                  </button>
                  <button
                    type='button'
                    class={{this.tabBarClass}}
                    {{on 'click' this.switchToBar}}
                  >
                    <svg
                      width='13'
                      height='13'
                      viewBox='0 0 24 24'
                      fill='none'
                      stroke='currentColor'
                      stroke-width='2'
                      aria-hidden='true'
                    ><line x1='18' y1='20' x2='18' y2='10' /><line
                        x1='12'
                        y1='20'
                        x2='12'
                        y2='4'
                      /><line x1='6' y1='20' x2='6' y2='14' /><line
                        x1='2'
                        y1='20'
                        x2='22'
                        y2='20'
                      /></svg>
                    Bar
                  </button>
                </div>

                <button
                  type='button'
                  class='mc-modal-close'
                  aria-label='Close'
                  {{on 'click' this.closeModal}}
                >
                  <svg
                    width='16'
                    height='16'
                    viewBox='0 0 24 24'
                    fill='none'
                    stroke='currentColor'
                    stroke-width='2.5'
                    aria-hidden='true'
                  ><line x1='18' y1='6' x2='6' y2='18' /><line
                      x1='6'
                      y1='6'
                      x2='18'
                      y2='18'
                    /></svg>
                </button>
              </div>
            </div>

            {{! Body: switch between 3D wheel, bar chart, line chart }}
            <div class='mc-modal-body'>
              {{#if this.isWheelView}}
                <Css3DWheelView
                  @segments={{this.chartSegments}}
                  @total={{this.chartTotal}}
                  @centerText={{this.centerText}}
                  @centerSub='PER MONTH'
                />
              {{else if this.isBarView}}
                <BarChartView
                  @segments={{this.chartSegments}}
                  @total={{this.chartTotal}}
                  @currency={{this.displayCurrency}}
                  @lifetimePrincipal={{@model.lifetimeMortgagePayment}}
                  @lifetimeTaxes={{@model.lifetimeTaxes}}
                  @lifetimeInsurance={{@model.lifetimeInsurance}}
                  @lifetimeHoa={{@model.lifetimeHoaFees}}
                  @lifetimeTotal={{@model.lifetimeTotal}}
                />
              {{/if}}
            </div>

          </div>
        </div>
      {{/if}}

    </div>{{! end mc-iso }}

    <style scoped>
      /* ── Root ───────────────────────────────────────────────── */
      .mc-iso {
        /* ── Design tokens ── */
        --c-bg: #f1f5f9;
        --c-white: #ffffff;
        --c-text: #0f172a;
        --c-text-2: #374151;
        --c-muted: #64748b;
        --c-muted-2: #94a3b8;
        --c-slate: #475569;
        --c-border: #e2e8f0;
        --c-border-2: #f1f5f9;
        --c-shadow:
          0 1px 3px rgba(0, 0, 0, 0.07), 0 1px 2px rgba(0, 0, 0, 0.04);
        --c-shadow-md:
          0 4px 12px rgba(0, 0, 0, 0.08), 0 2px 4px rgba(0, 0, 0, 0.04);
        --c-blue: #2563eb;
        --c-amber: #f59e0b;
        --c-emerald: #10b981;
        --c-violet: #8b5cf6;
        --c-violet-dark: #7c3aed;
        --hero-bg-start: #0c1220;
        --hero-bg-mid: #0f1e3d;
        --hero-bg-end: #1a0a2e;
        --stat-blue-bg: linear-gradient(135deg, #eff6ff, #dbeafe);
        --stat-blue-border: #bfdbfe;
        --stat-emerald-bg: linear-gradient(135deg, #f0fdf4, #dcfce7);
        --stat-emerald-border: #bbf7d0;
        --stat-violet-bg: linear-gradient(135deg, #faf5ff, #ede9fe);
        --stat-violet-border: #ddd6fe;
        --stat-slate-bg: linear-gradient(135deg, #f8fafc, #f1f5f9);
        --stat-slate-border: #e2e8f0;

        container-type: inline-size;
        container-name: iso-card;
        display: flex;
        height: 100%;
        background: var(--c-bg);
        font-family: var(
          --boxel-font-family,
          -apple-system,
          BlinkMacSystemFont,
          'Segoe UI',
          sans-serif
        );
        overflow: hidden;
        position: relative; /* needed for modal overlay */
        border: 1px solid rgba(99, 102, 241, 0.28);
        box-shadow:
          0 0 0 1px rgba(99, 102, 241, 0.08),
          0 0 32px rgba(99, 102, 241, 0.12),
          inset 0 0 48px rgba(99, 102, 241, 0.04);
        animation: neon-border-pulse 6s cubic-bezier(0.45, 0.05, 0.55, 0.95)
          infinite;
      }

      @keyframes neon-border-pulse {
        0%,
        100% {
          box-shadow:
            0 0 0 1px rgba(99, 102, 241, 0.08),
            0 0 32px rgba(99, 102, 241, 0.12),
            inset 0 0 48px rgba(99, 102, 241, 0.04);
          border-color: rgba(99, 102, 241, 0.28);
        }
        50% {
          box-shadow:
            0 0 0 1px rgba(139, 92, 246, 0.16),
            0 0 48px rgba(99, 102, 241, 0.22),
            inset 0 0 64px rgba(99, 102, 241, 0.07);
          border-color: rgba(139, 92, 246, 0.48);
        }
      }

      /* ── Body: sidebar left + right col ─────────────────────── */
      .mc-body {
        display: flex;
        flex: 1;
        min-height: 0;
        overflow: hidden;
      }

      /* ── Right column: hero on top + scrollable results below ── */
      .mc-right-col {
        flex: 1;
        min-width: 0;
        display: flex;
        flex-direction: column;
        overflow: hidden;
      }

      /* ══ HERO (now inside right col) ═════════════════════════ */
      .mc-hero {
        background: linear-gradient(
          135deg,
          var(--hero-bg-start) 0%,
          var(--hero-bg-mid) 45%,
          var(--hero-bg-end) 100%
        );
        padding: 1.5rem 1.75rem;
        display: flex;
        gap: 2rem;
        align-items: center;
        flex-shrink: 0;
        position: relative;
        overflow: hidden;
        border-bottom: 1px solid rgba(99, 102, 241, 0.45);
        box-shadow:
          0 1px 0 rgba(99, 102, 241, 0.18),
          0 4px 24px rgba(99, 102, 241, 0.12);
      }

      .mc-hero::before {
        content: '';
        position: absolute;
        inset: 0;
        background: radial-gradient(
          ellipse 60% 80% at 80% 50%,
          rgba(99, 102, 241, 0.18) 0%,
          transparent 70%
        );
        pointer-events: none;
      }

      .mc-hero::after {
        content: '';
        position: absolute;
        top: -40px;
        right: 30%;
        width: 280px;
        height: 280px;
        border-radius: 50%;
        background: radial-gradient(
          circle,
          rgba(139, 92, 246, 0.12) 0%,
          transparent 70%
        );
        pointer-events: none;
      }

      .mc-hero-left {
        flex: 1;
        display: flex;
        flex-direction: column;
        gap: 0.875rem;
        position: relative;
        z-index: 1;
        min-width: 0;
      }

      .mc-hero-eyebrow {
        display: inline-flex;
        align-items: center;
        gap: 7px;
        font-size: 0.6875rem;
        font-weight: 700;
        letter-spacing: 0.14em;
        text-transform: uppercase;
        color: rgba(167, 139, 250, 1);
        background: rgba(139, 92, 246, 0.12);
        border: 1px solid rgba(139, 92, 246, 0.25);
        border-radius: 99px;
        padding: 0.25rem 0.75rem 0.25rem 0.5rem;
        width: fit-content;
      }

      .mc-hero-eyebrow-icon {
        color: rgba(167, 139, 250, 1);
        flex-shrink: 0;
      }

      .mc-hero-title {
        font-size: 1.625rem;
        font-weight: 800;
        color: #f8fafc;
        letter-spacing: -0.01em;
        line-height: 1.15;
        margin: 0;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      .mc-hero-payment {
        display: flex;
        align-items: baseline;
        gap: 0.5rem;
      }

      .mc-hero-amount {
        font-size: 3.25rem;
        font-weight: 900;
        color: var(--c-white);
        letter-spacing: -0.02em;
        line-height: 1;
        font-variant-numeric: tabular-nums;
        text-shadow: 0 0 32px rgba(99, 102, 241, 0.4);
      }

      .mc-hero-amount-meta {
        display: flex;
        flex-direction: column;
        gap: 2px;
        padding-bottom: 4px;
      }

      .mc-hero-mo {
        font-size: 1rem;
        color: rgba(255, 255, 255, 0.55);
        font-weight: 500;
        letter-spacing: 0.01em;
      }

      .mc-hero-year {
        font-size: 0.75rem;
        color: rgba(255, 255, 255, 0.35);
        font-variant-numeric: tabular-nums;
      }

      .mc-hero-pills {
        display: flex;
        gap: 0.5rem;
        flex-wrap: wrap;
      }

      .mc-hero-pill {
        display: flex;
        flex-direction: column;
        gap: 3px;
        background: rgba(255, 255, 255, 0.07);
        border: 1px solid rgba(255, 255, 255, 0.13);
        border-radius: 10px;
        padding: 0.45rem 0.875rem;
        backdrop-filter: blur(8px);
        transition:
          background 0.2s ease,
          border-color 0.2s ease;
      }

      .mc-hero-pill:hover {
        background: rgba(255, 255, 255, 0.12);
        border-color: rgba(255, 255, 255, 0.22);
      }

      .mc-hero-pill-label {
        font-size: 0.625rem;
        font-weight: 700;
        letter-spacing: 0.12em;
        text-transform: uppercase;
        color: rgba(255, 255, 255, 0.48);
      }

      .mc-hero-pill-value {
        font-size: 0.9375rem;
        font-weight: 700;
        color: rgba(255, 255, 255, 0.95);
        font-variant-numeric: tabular-nums;
        letter-spacing: -0.01em;
      }

      .mc-hero-right {
        display: flex;
        align-items: center;
        gap: 1.5rem;
        flex-shrink: 0;
        position: relative;
        z-index: 1;
      }

      .mc-ring-wrap {
        filter: drop-shadow(0 0 24px rgba(99, 102, 241, 0.4));
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 0.5rem;

        filter: drop-shadow(0 0 16px rgba(99, 102, 241, 0.3));
      }

      .mc-breakdown-btn {
        display: inline-flex;
        align-items: center;
        gap: 0.35rem;
        padding: 0.3rem 0.875rem;
        background: rgba(99, 102, 241, 0.08);
        border: 1px solid rgba(99, 102, 241, 0.45);
        border-radius: 99px;
        color: rgba(180, 185, 255, 0.85);
        font-family: var(
          --boxel-font-family,
          -apple-system,
          BlinkMacSystemFont,
          'Segoe UI',
          sans-serif
        );
        font-size: 0.625rem;
        font-weight: 700;
        letter-spacing: 0.07em;
        text-transform: uppercase;
        cursor: pointer;
        box-shadow:
          0 0 8px rgba(99, 102, 241, 0.25),
          inset 0 0 8px rgba(99, 102, 241, 0.06);
        transition:
          background 0.25s ease,
          border-color 0.25s ease,
          color 0.25s ease,
          box-shadow 0.25s ease,
          transform 0.25s ease;
      }

      .mc-breakdown-btn:hover {
        background: rgba(99, 102, 241, 0.18);
        border-color: rgba(139, 92, 246, 0.9);
        color: #ffffff;
        transform: translateY(-1px);
        box-shadow:
          0 0 16px rgba(99, 102, 241, 0.55),
          0 0 32px rgba(99, 102, 241, 0.25),
          inset 0 0 12px rgba(139, 92, 246, 0.12);
        text-shadow: 0 0 10px rgba(180, 185, 255, 0.8);
      }

      .mc-breakdown-btn:active {
        transform: translateY(0);
        box-shadow: 0 0 8px rgba(99, 102, 241, 0.4);
      }

      .mc-hero-legend {
        display: flex;
        flex-direction: column;
        gap: 0.3rem;
      }

      .mc-hero-legend-row {
        display: flex;
        align-items: center;
        gap: 0.625rem;
        background: rgba(255, 255, 255, 0.055);
        border: 1px solid rgba(255, 255, 255, 0.09);
        border-radius: 8px;
        padding: 0.3rem 0.75rem 0.3rem 0.5rem;
        transition:
          background 0.18s ease,
          border-color 0.18s ease;
      }

      .mc-hero-legend-row:hover {
        background: rgba(255, 255, 255, 0.09);
        border-color: rgba(255, 255, 255, 0.16);
      }

      .mc-hero-swatch {
        width: 4px;
        height: 32px;
        border-radius: 4px;
        flex-shrink: 0;
        opacity: 0.85;
      }

      .mc-hero-legend-name {
        font-size: 0.6875rem;
        font-weight: 600;
        color: rgba(255, 255, 255, 0.8);
        flex: 1;
        min-width: 0;
        white-space: nowrap;
        letter-spacing: 0.02em;
      }

      .mc-hero-legend-val {
        font-size: 0.875rem;
        font-weight: 800;
        color: rgba(255, 255, 255, 0.95);
        font-variant-numeric: tabular-nums;
        letter-spacing: -0.02em;
      }

      /* ── Sidebar ─────────────────────────────────────────────── */
      .mc-sidebar {
        width: 300px;
        flex-shrink: 0;
        background: var(--c-white);
        border-right: 1px solid var(--c-border);
        overflow-y: auto;
      }

      .mc-sidebar-inner {
        padding: 1rem;
        display: flex;
        flex-direction: column;
        gap: 0.75rem;
      }

      /* ── Input groups ────────────────────────────────────────── */
      .mc-group {
        border: 1px solid var(--c-border);
        border-radius: 0.625rem;
        /* no overflow:hidden — would create a stacking context that traps the currency dropdown */
        box-shadow: 0 1px 3px rgba(0, 0, 0, 0.05);
        overflow: hidden;
      }

      .mc-group-label {
        font-size: 0.6875rem;
        font-weight: 700;
        letter-spacing: 0.08em;
        text-transform: uppercase;
        color: var(--c-slate);
        background: #f8fafc;
        padding: 0.4375rem 0.875rem;
        border-bottom: 1px solid var(--c-border);
        display: flex;
        align-items: center;
        gap: 5px;
      }

      .mc-field-row {
        display: flex;
        flex-direction: column;
        gap: 2px;
        padding: 0.5rem 0.875rem;
        border-bottom: 1px solid var(--c-bg);
      }

      .mc-field-row:last-child {
        border-bottom: none;
      }

      .mc-label {
        font-size: 0.75rem;
        font-weight: 500;
        color: var(--c-muted);
      }

      .mc-input-row {
        display: flex;
        align-items: center;
        gap: 0.5rem;
      }

      .mc-input-row > :first-child {
        flex: 1;
      }

      .mc-unit {
        font-size: 0.8125rem;
        font-weight: 600;
        color: var(--c-muted-2);
        min-width: 22px;
      }

      .mc-sidebar :deep(input) {
        background: #f8fafc;
        border: 1px solid var(--c-border);
        border-radius: 6px;
        padding: 5px 8px;
        font-size: 0.8125rem;
        color: var(--c-text);
        width: 100%;
        box-sizing: border-box;
        transition:
          border-color 0.15s,
          box-shadow 0.15s;
      }

      .mc-sidebar :deep(input:focus) {
        outline: none;
        border-color: #6366f1;
        background: #fff;
        box-shadow: 0 0 0 3px rgba(99, 102, 241, 0.12);
      }

      /* ── AmountWithCurrency — single-row compact layout ──────── */
      .mc-sidebar :deep(.input-selectable-currency-amount) {
        --boxel-input-group-border-radius: 6px;
        display: flex;
        flex-direction: row;
        flex-wrap: nowrap;
        align-items: stretch;
        overflow: hidden;
      }

      .mc-sidebar :deep(.input-selectable-currency-amount:focus-within) {
        box-shadow: 0 0 0 3px rgba(99, 102, 241, 0.12);
      }

      /* $ symbol prefix */
      .mc-sidebar :deep(.input-selectable-currency-amount .text-accessory) {
        display: flex;
        align-items: center;
        flex-shrink: 0;
        padding: 0 4px 0 10px;
        font-size: 0.875rem;
        font-weight: 600;
        color: var(--c-muted);
        background: transparent;
      }

      /* Number input — fills remaining space */
      .mc-sidebar :deep(.input-selectable-currency-amount input) {
        flex: 1;
        min-width: 0;
        border: none;
        background: transparent;
        box-shadow: none;
        padding: 6px 6px 6px 4px;
        font-size: 0.8125rem;
        color: var(--c-text);
      }

      /* Currency selector wrapper */
      .mc-sidebar :deep(.input-selectable-currency) {
        display: flex;
        align-items: stretch;
        flex-shrink: 0;
        border-left: 1px solid var(--c-border);
      }

      /* The BoxelSelect trigger — wide enough that the portaled dropdown
         inherits a usable width (ember-power-select matches trigger width) */
      .mc-sidebar :deep(.currency-field-edit) {
        font-size: 0.75rem;
        font-weight: 500;
        background: #f8fafc;
        border: none;
        border-radius: 0;
        height: 100%;
      }

      /* ── Results ─────────────────────────────────────────────── */
      .mc-results {
        flex: 1;
        overflow-y: auto;
        padding: 1rem;
        display: flex;
        flex-direction: column;
        gap: 0.875rem;
        min-width: 0;
        background: var(--c-bg);
      }

      /* ── Stat Cards ──────────────────────────────────────────── */
      .mc-stat-cards {
        display: grid;
        grid-template-columns: repeat(4, 1fr);
        gap: 0.625rem;
      }

      .mc-stat-card {
        border-radius: 0.75rem;
        padding: 0.875rem 1rem 0.75rem;
        display: flex;
        flex-direction: column;
        gap: 2px;
        border: 1px solid transparent;
        position: relative;
        overflow: hidden;
        cursor: default;
        transition:
          transform 0.18s ease,
          box-shadow 0.18s ease,
          border-color 0.18s ease;
      }

      .mc-stat-card:hover {
        transform: translateY(-2px);
      }

      .mc-stat-card--blue:hover {
        box-shadow:
          0 8px 24px rgba(37, 99, 235, 0.18),
          0 2px 8px rgba(37, 99, 235, 0.1);
        border-color: #93c5fd;
      }

      .mc-stat-card--emerald:hover {
        box-shadow:
          0 8px 24px rgba(16, 185, 129, 0.18),
          0 2px 8px rgba(16, 185, 129, 0.1);
        border-color: #6ee7b7;
      }

      .mc-stat-card--violet:hover {
        box-shadow:
          0 8px 24px rgba(139, 92, 246, 0.18),
          0 2px 8px rgba(139, 92, 246, 0.1);
        border-color: #c4b5fd;
      }

      .mc-stat-card--slate:hover {
        box-shadow:
          0 8px 24px rgba(71, 85, 105, 0.14),
          0 2px 8px rgba(71, 85, 105, 0.08);
        border-color: #cbd5e1;
      }

      .mc-stat-card:hover .mc-stat-card-fill {
        filter: brightness(1.12);
      }

      .mc-stat-card--blue {
        background: var(--stat-blue-bg);
        border-color: var(--stat-blue-border);
      }
      .mc-stat-card--emerald {
        background: var(--stat-emerald-bg);
        border-color: var(--stat-emerald-border);
      }
      .mc-stat-card--violet {
        background: var(--stat-violet-bg);
        border-color: var(--stat-violet-border);
      }
      .mc-stat-card--slate {
        background: var(--stat-slate-bg);
        border-color: var(--stat-slate-border);
      }

      .mc-stat-card-label {
        font-size: 0.6875rem;
        font-weight: 600;
        letter-spacing: 0.06em;
        text-transform: uppercase;
        color: var(--c-muted);
      }

      .mc-stat-card-value {
        font-size: 1.125rem;
        font-weight: 800;
        color: var(--c-text);
        letter-spacing: -0.025em;
        font-variant-numeric: tabular-nums;
        line-height: 1.2;
      }

      .mc-stat-card-unit {
        font-size: 0.75rem;
        font-weight: 600;
        color: var(--c-muted);
        margin-left: 1px;
      }

      .mc-stat-card-bar {
        margin-top: 6px;
      }

      .mc-stat-card-track {
        height: 3px;
        border-radius: 99px;
        background: rgba(0, 0, 0, 0.08);
        overflow: hidden;
      }

      .mc-stat-card-fill {
        height: 100%;
        border-radius: 99px;
        width: 70%;
      }

      .mc-fill--blue {
        background: var(--c-blue);
      }
      .mc-fill--emerald {
        background: var(--c-emerald);
      }
      .mc-fill--violet {
        background: var(--c-violet-dark);
      }
      .mc-fill--slate {
        background: var(--c-slate);
      }

      /* ── Section card ────────────────────────────────────────── */
      .mc-section {
        background: var(--c-white);
        border-radius: 0.75rem;
        border: 1px solid var(--c-border);
        overflow: hidden;
        box-shadow:
          0 1px 4px rgba(0, 0, 0, 0.06),
          0 4px 12px rgba(0, 0, 0, 0.04);
      }

      .mc-section-head {
        font-size: 0.6875rem;
        font-weight: 700;
        letter-spacing: 0.08em;
        text-transform: uppercase;
        color: var(--c-slate);
        background: #f8fafc;
        padding: 0.5625rem 1rem;
        border-bottom: 1px solid var(--c-border);
        display: flex;
        align-items: center;
        gap: 6px;
      }

      .mc-section-icon {
        color: var(--c-muted-2);
        flex-shrink: 0;
      }

      /* ── Breakdown table ─────────────────────────────────────── */
      .mc-table-head {
        display: grid;
        grid-template-columns: 10px 1fr 108px 116px;
        gap: 8px;
        padding: 0.4375rem 1rem;
        background: #f8fafc;
        border-bottom: 1px solid var(--c-border);
      }

      .mc-col-h {
        font-size: 0.6875rem;
        font-weight: 700;
        letter-spacing: 0.07em;
        text-transform: uppercase;
        color: var(--c-muted-2);
        text-align: right;
      }

      .mc-col-h:nth-child(2) {
        text-align: left;
      }

      .mc-row {
        display: grid;
        grid-template-columns: 10px 1fr 108px 116px;
        gap: 8px;
        align-items: center;
        padding: 0.6875rem 1rem;
        border-bottom: 1px solid var(--c-bg);
        transition: background 0.12s;
      }

      .mc-row:last-child {
        border-bottom: none;
      }

      .mc-row:hover:not(.mc-row--total) {
        background: #f8fafc;
      }

      .mc-row--total {
        background: linear-gradient(90deg, #f8fafc, var(--c-bg));
        border-top: 2px solid var(--c-border);
      }

      .mc-dot {
        width: 10px;
        height: 10px;
        border-radius: 50%;
        flex-shrink: 0;
      }

      .mc-dot--total {
        background: var(--c-text);
      }

      .mc-row-name {
        font-size: 0.8125rem;
        color: var(--c-text-2);
      }

      .mc-row--total .mc-row-name {
        font-weight: 700;
        color: var(--c-text);
      }

      .mc-row-num {
        font-size: 0.8125rem;
        color: var(--c-text-2);
        text-align: right;
        font-variant-numeric: tabular-nums;
      }

      .mc-row-num--bold {
        font-weight: 800;
        color: var(--c-text);
      }

      /* ══ RESPONSIVE BREAKPOINTS ══════════════════════════════ */

      /* ── ≤ 1050px: hide legend — it crowds mc-hero-left at mid widths ── */
      @container iso-card (max-width: 1050px) {
        .mc-hero-legend {
          display: none;
        }
      }

      /* ── ≤ 800px: compact hero — smaller ring, tighter text ── */
      @container iso-card (max-width: 800px) {
        .mc-hero {
          padding: 1rem 1.25rem;
          gap: 1rem;
        }

        .mc-ring-wrap :deep(.donut-ring) {
          width: 140px;
          height: 140px;
        }

        .mc-hero-amount {
          font-size: 2.25rem;
        }

        .mc-hero-title {
          font-size: 1.125rem;
        }
      }

      /* ── ≤ 600px: stack sidebar on top of right col ─────────── */
      @container iso-card (max-width: 600px) {
        .mc-iso {
          flex-direction: column;
        }

        .mc-body {
          flex-direction: column;
          overflow-y: auto;
        }

        .mc-sidebar {
          width: 100%;
          border-right: none;
          border-bottom: 1px solid var(--c-border);
          overflow-y: visible;
          flex-shrink: 0;
        }

        .mc-sidebar-inner {
          padding: 0.75rem;
        }

        .mc-results {
          overflow-y: visible;
          padding: 0.75rem;
        }

        .mc-stat-cards {
          grid-template-columns: repeat(2, 1fr);
        }

        .mc-hero {
          flex-direction: column;
          align-items: flex-start;
          gap: 0.75rem;
          padding: 1rem;
        }

        .mc-hero-right {
          align-self: center;
        }
      }

      /* ── ≤ 420px: tighter hero, 2-col stat cards ────────────── */
      @container iso-card (max-width: 420px) {
        .mc-stat-cards {
          grid-template-columns: 1fr 1fr;
        }

        .mc-hero-payment {
          flex-direction: column;
          gap: 0.25rem;
          align-items: flex-start;
        }

        .mc-hero-amount {
          font-size: 1.875rem;
        }

        .mc-hero-amount-meta {
          flex-direction: row;
          gap: 0.5rem;
        }

        .mc-table-head,
        .mc-row {
          grid-template-columns: 10px 1fr 88px 96px;
          font-size: 0.75rem;
        }
      }

      /* ── ≤ 340px: ultra-compact ──────────────────────────────── */
      @container iso-card (max-width: 340px) {
        .mc-hero-pills {
          display: none;
        }

        .mc-table-head,
        .mc-row {
          grid-template-columns: 10px 1fr 88px;
        }

        .mc-table-head span:last-child,
        .mc-row span:last-child {
          display: none;
        }

        .mc-stat-cards {
          grid-template-columns: 1fr 1fr;
        }
      }

      /* ══ MODAL OVERLAY ═══════════════════════════════════════ */

      /* ── Decorative ambient orbs ── */
      .mc-modal-orbs {
        position: absolute;
        inset: 0;
        pointer-events: none;
        z-index: 0;
        overflow: hidden;
      }

      .mc-orb {
        position: absolute;
        border-radius: 50%;
        filter: blur(60px);
      }

      .mc-orb--blue {
        width: 380px;
        height: 380px;
        background: radial-gradient(circle, #2563eb 0%, transparent 70%);
        top: -120px;
        left: -80px;
        opacity: 0.22;
      }

      .mc-orb--violet {
        width: 340px;
        height: 340px;
        background: radial-gradient(circle, #8b5cf6 0%, transparent 70%);
        bottom: -100px;
        right: -80px;
        opacity: 0.2;
      }

      .mc-orb--amber {
        width: 260px;
        height: 260px;
        background: radial-gradient(circle, #f59e0b 0%, transparent 70%);
        top: 40%;
        left: 25%;
        opacity: 0.1;
      }

      .mc-orb--emerald {
        width: 220px;
        height: 220px;
        background: radial-gradient(circle, #10b981 0%, transparent 70%);
        bottom: 10%;
        left: 10%;
        opacity: 0.1;
      }

      .mc-modal-backdrop {
        position: absolute;
        inset: 0;
        z-index: 200;
        background: rgba(2, 6, 23, 0.92);
        backdrop-filter: blur(12px);
        display: flex;
        align-items: stretch;
        justify-content: stretch;
      }

      .mc-modal {
        position: absolute;
        inset: 0;
        display: flex;
        flex-direction: column;
        background: linear-gradient(
          160deg,
          #040810 0%,
          #080f20 35%,
          #0a1530 70%,
          #06090f 100%
        );
        overflow: hidden;
      }

      /* top multi-color accent line */
      .mc-modal::before {
        content: '';
        position: absolute;
        top: 0;
        left: 0;
        right: 0;
        height: 2px;
        background: linear-gradient(
          90deg,
          transparent 0%,
          #2563eb 20%,
          #8b5cf6 50%,
          #10b981 80%,
          transparent 100%
        );
        z-index: 10;
      }

      /* ── Modal header ── */
      .mc-modal-header {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 1.5rem;
        padding: 1.125rem 1.75rem;
        border-bottom: 1px solid rgba(255, 255, 255, 0.07);
        flex-shrink: 0;
        background: linear-gradient(
          180deg,
          rgba(255, 255, 255, 0.04) 0%,
          rgba(255, 255, 255, 0.01) 100%
        );
        position: relative;
        z-index: 5;
      }

      .mc-modal-header-left {
        display: flex;
        flex-direction: column;
        gap: 0.2rem;
        min-width: 0;
      }

      .mc-modal-title {
        font-size: 0.625rem;
        font-weight: 700;
        color: rgba(255, 255, 255, 0.32);
        letter-spacing: 0.14em;
        text-transform: uppercase;
      }

      .mc-modal-total-badge {
        display: flex;
        align-items: baseline;
        gap: 0.5rem;
      }

      .mc-modal-total-amount {
        font-size: 2rem;
        font-weight: 900;
        background: linear-gradient(
          135deg,
          #e0e7ff 0%,
          #a5b4fc 40%,
          #c4b5fd 70%,
          #f0abfc 100%
        );
        -webkit-background-clip: text;
        -webkit-text-fill-color: transparent;
        background-clip: text;
        letter-spacing: -0.04em;
        font-variant-numeric: tabular-nums;
        line-height: 1;
        filter: drop-shadow(0 0 16px rgba(139, 92, 246, 0.5));
      }

      .mc-modal-total-label {
        font-size: 0.625rem;
        font-weight: 600;
        color: rgba(255, 255, 255, 0.3);
        letter-spacing: 0.08em;
        text-transform: uppercase;
        align-self: center;
      }

      .mc-modal-header-right {
        display: flex;
        align-items: center;
        gap: 0.75rem;
        flex-shrink: 0;
      }

      .mc-modal-tabs {
        display: flex;
        gap: 2px;
        background: rgba(255, 255, 255, 0.04);
        border: 1px solid rgba(255, 255, 255, 0.09);
        border-radius: 12px;
        padding: 3px;
      }

      .mc-mod-tab {
        display: flex;
        align-items: center;
        gap: 5px;
        padding: 0.4rem 1rem;
        border-radius: 9px;
        border: none;
        background: transparent;
        font-size: 0.75rem;
        font-weight: 600;
        color: rgba(255, 255, 255, 0.32);
        cursor: pointer;
        transition:
          background 0.2s ease,
          color 0.2s ease,
          box-shadow 0.2s ease;
        letter-spacing: 0.02em;
        font-family: inherit;
      }

      .mc-mod-tab:hover {
        color: rgba(255, 255, 255, 0.72);
        background: rgba(255, 255, 255, 0.08);
      }

      .mc-mod-tab--active {
        background: linear-gradient(
          135deg,
          rgba(99, 102, 241, 0.35) 0%,
          rgba(139, 92, 246, 0.28) 100%
        );
        color: rgba(255, 255, 255, 0.97);
        box-shadow:
          0 0 0 1px rgba(139, 92, 246, 0.5),
          0 4px 14px rgba(99, 102, 241, 0.3),
          inset 0 1px 0 rgba(255, 255, 255, 0.12);
      }

      .mc-modal-close {
        width: 34px;
        height: 34px;
        border-radius: 9px;
        border: 1px solid rgba(255, 255, 255, 0.09);
        background: rgba(255, 255, 255, 0.04);
        color: rgba(255, 255, 255, 0.35);
        cursor: pointer;
        display: flex;
        align-items: center;
        justify-content: center;
        flex-shrink: 0;
        transition:
          background 0.2s ease,
          color 0.2s ease,
          border-color 0.2s ease,
          box-shadow 0.2s ease,
          transform 0.15s ease;
      }

      .mc-modal-close:hover {
        background: rgba(239, 68, 68, 0.18);
        border-color: rgba(239, 68, 68, 0.45);
        color: #fca5a5;
        box-shadow: 0 0 12px rgba(239, 68, 68, 0.2);
        transform: scale(1.05);
      }

      /* ── Modal body ── */
      .mc-modal-body {
        flex: 1;
        overflow: hidden;
        min-height: 0;
        position: relative;
        z-index: 1;
        display: flex;
        flex-direction: column;
      }
    </style>
  </template>
}

// ─── Fitted Template ──────────────────────────────────────────────────────────

class FittedTemplate extends Component<typeof MortgageCalculator> {
  // ── Modal state ──────────────────────────────────────────────────────
  @tracked isModalOpen = false;
  @tracked modalView: 'wheel' | 'bar' = 'wheel';

  openModal = (): void => {
    this.isModalOpen = true;
  };
  closeModal = (): void => {
    this.isModalOpen = false;
  };
  switchToWheel = (): void => {
    this.modalView = 'wheel';
  };
  switchToBar = (): void => {
    this.modalView = 'bar';
  };
  stopModalProp = (e: Event): void => {
    e.stopPropagation();
  };

  get isWheelView(): boolean {
    return this.modalView === 'wheel';
  }
  get isBarView(): boolean {
    return this.modalView === 'bar';
  }
  get tabWheelClass(): string {
    return this.modalView === 'wheel'
      ? 'mc-mod-tab mc-mod-tab--active'
      : 'mc-mod-tab';
  }
  get tabBarClass(): string {
    return this.modalView === 'bar'
      ? 'mc-mod-tab mc-mod-tab--active'
      : 'mc-mod-tab';
  }

  get displayCurrency(): string {
    return this.args.model.homePrice?.currency?.code ?? 'USD';
  }

  get hasData() {
    return (this.args.model.homePrice?.amount ?? 0) > 0;
  }

  get monthlyDisplay() {
    return fmt(this.args.model.monthlyTotal, this.displayCurrency);
  }

  // Proportional bar segments — zero-value items filtered out
  get barSegments() {
    const m = this.args.model;
    const total = m.monthlyTotal ?? 0;
    if (!total) return [];
    const items = [
      {
        color: '#2563eb',
        value: m.monthlyMortgagePayment ?? 0,
        label: 'P&I',
      },
      { color: '#f59e0b', value: m.taxPerMonth?.amount ?? 0, label: 'Tax' },
      {
        color: '#10b981',
        value: m.insurancePerMonth?.amount ?? 0,
        label: 'Ins',
      },
      {
        color: '#8b5cf6',
        value: m.hoaFeesPerMonth?.amount ?? 0,
        label: 'HOA',
      },
    ];
    return items
      .filter((s) => s.value > 0)
      .map((s) => ({ ...s, pct: (s.value / total) * 100 }));
  }

  // Segments for DonutRing — card (wide) layout, zero-value items filtered out
  // label + formattedValue drive the ring's hover center-text
  get ringSegments() {
    const m = this.args.model;
    const cc = this.displayCurrency;
    return [
      {
        color: '#2563eb',
        value: m.monthlyMortgagePayment ?? 0,
        label: 'Principal & Interest',
        formattedValue: fmt(m.monthlyMortgagePayment, cc),
      },
      {
        color: '#f59e0b',
        value: m.taxPerMonth?.amount ?? 0,
        label: 'Property Tax',
        formattedValue: fmt(m.taxPerMonth?.amount, cc),
      },
      {
        color: '#10b981',
        value: m.insurancePerMonth?.amount ?? 0,
        label: 'Insurance',
        formattedValue: fmt(m.insurancePerMonth?.amount, cc),
      },
      {
        color: '#8b5cf6',
        value: m.hoaFeesPerMonth?.amount ?? 0,
        label: 'HOA Fees',
        formattedValue: fmt(m.hoaFeesPerMonth?.amount, cc),
      },
    ].filter((s) => s.value > 0);
  }

  get ringTotal() {
    return this.args.model.monthlyTotal ?? 0;
  }

  <template>
    <article class='mc-fitted'>

      {{! ══ BADGE  ≤150 × ≤169 ══ }}
      <section class='badge'>
        <div class='badge-glow'></div>
        <div class='badge-icon'>
          <svg
            width='18'
            height='18'
            viewBox='0 0 24 24'
            fill='none'
            stroke='currentColor'
            stroke-width='1.8'
            aria-hidden='true'
          ><path d='M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z' /><polyline
              points='9 22 9 12 15 12 15 22'
            /></svg>
        </div>
        {{#if this.hasData}}
          <span class='badge-amount'>{{this.monthlyDisplay}}</span>
          <span class='badge-sub'>/ month</span>
        {{else}}
          <span class='badge-name'>Mortgage</span>
          <span class='badge-sub'>Calculator</span>
        {{/if}}
      </section>

      {{! ══ STRIP  >150 × ≤169 ══ }}
      <section class='strip'>
        <div class='strip-icon'>
          <svg
            width='13'
            height='13'
            viewBox='0 0 24 24'
            fill='none'
            stroke='currentColor'
            stroke-width='2'
            aria-hidden='true'
          ><path d='M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z' /></svg>
        </div>
        <div class='strip-body'>
          <span class='strip-eyebrow'>Mortgage</span>
          <span class='strip-title'>{{if
              @model.title
              @model.title
              'Mortgage Calculator'
            }}</span>
        </div>
        {{#if this.hasData}}
          <div class='strip-right'>
            <div class='strip-amount-row'>
              <span class='strip-amount'>{{this.monthlyDisplay}}</span>
              <span class='strip-mo'>/mo</span>
            </div>
            <div class='strip-bar'>
              {{#each this.barSegments as |seg|}}
                <div
                  class='strip-bar-seg'
                  style='width:{{seg.pct}}%;background:{{seg.color}}'
                ></div>
              {{/each}}
            </div>
          </div>
        {{else}}
          <span class='strip-empty'>—</span>
        {{/if}}
      </section>

      {{! ══ TILE  ≤399 × ≥170 ══ }}
      <article class='tile'>
        <div class='tile-top'>
          <div class='tile-glow'></div>
          {{#if this.hasData}}
            <div class='tile-ring-wrap'>
              <DonutRing
                @segments={{this.ringSegments}}
                @total={{this.ringTotal}}
                @centerText={{this.monthlyDisplay}}
                @centerSubText='/ MO'
              />
            </div>
            <div class='tile-info-col'>
              <div class='tile-legend-col'>
                {{#each this.barSegments as |seg|}}
                  <span class='tile-legend-item'>
                    <span
                      class='tile-legend-dot'
                      style='background:{{seg.color}}'
                    ></span>
                    <span class='tile-legend-lbl'>{{seg.label}}</span>
                  </span>
                {{/each}}
              </div>
            </div>
          {{else}}
            <span class='tile-empty'>—</span>
            <span class='tile-empty-sub'>Enter home price</span>
          {{/if}}
        </div>
        {{#if this.hasData}}
          <div class='tile-foot'>
            <div class='tile-stat'>
              <span class='tile-sk'>Loan</span>
              <span class='tile-sv'>{{fmt
                  @model.loanAmount
                  this.displayCurrency
                }}</span>
            </div>
            <div class='tile-sep'></div>
            <div class='tile-stat'>
              <span class='tile-sk'>Rate</span>
              <span class='tile-sv'>{{@model.interestRatePercentage}}%</span>
            </div>
            <div class='tile-sep'></div>
            <div class='tile-stat'>
              <span class='tile-sk'>Term</span>
              <span class='tile-sv'>{{@model.loanTermYears}}yr</span>
            </div>
          </div>
        {{/if}}
      </article>

      {{! ══ CARD  ≥400 × ≥170 ══ }}
      <article class='card'>
        <div class='card-left'>
          <div class='card-left-glow'></div>
          <div class='card-eyebrow'>
            <svg
              width='9'
              height='9'
              viewBox='0 0 24 24'
              fill='none'
              stroke='currentColor'
              stroke-width='2.5'
              aria-hidden='true'
            ><path d='M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z' /></svg>
            Mortgage Calculator
          </div>
          {{#if this.hasData}}
            <div class='card-ring-wrap'>
              <DonutRing
                @segments={{this.ringSegments}}
                @total={{this.ringTotal}}
                @centerText={{this.monthlyDisplay}}
                @centerSubText='/ MO'
              />
            </div>
            <div class='card-legend'>
              {{#each this.barSegments as |seg|}}
                <span class='card-legend-item'>
                  <span
                    class='card-legend-dot'
                    style='background:{{seg.color}}'
                  ></span>
                  {{seg.label}}
                </span>
              {{/each}}
            </div>
          {{else}}
            <span class='card-empty-amount'>—</span>
            <span class='card-empty-sub'>No data</span>
          {{/if}}
        </div>

        <div class='card-right'>
          <h2 class='card-title'>{{if
              @model.title
              @model.title
              'Mortgage Calculator'
            }}</h2>
          {{#if this.hasData}}
            <div class='card-monthly-total'>
              <span class='card-monthly-amount'>{{this.monthlyDisplay}}</span>
              <span class='card-monthly-mo'>/ mo</span>
            </div>
            <div class='card-rows'>
              <div class='card-row'>
                <span class='card-row-dot' style='background:#2563eb'></span>
                <span class='card-row-lbl'>Principal &amp; Interest</span>
                <span class='card-row-val'>{{fmt
                    @model.monthlyMortgagePayment
                    this.displayCurrency
                  }}</span>
              </div>
              <div class='card-row'>
                <span class='card-row-dot' style='background:#f59e0b'></span>
                <span class='card-row-lbl'>Property Tax</span>
                <span class='card-row-val'>{{fmt
                    @model.taxPerMonth.amount
                    this.displayCurrency
                  }}</span>
              </div>
              <div class='card-row'>
                <span class='card-row-dot' style='background:#10b981'></span>
                <span class='card-row-lbl'>Insurance</span>
                <span class='card-row-val'>{{fmt
                    @model.insurancePerMonth.amount
                    this.displayCurrency
                  }}</span>
              </div>
              <div class='card-row'>
                <span class='card-row-dot' style='background:#8b5cf6'></span>
                <span class='card-row-lbl'>HOA Fees</span>
                <span class='card-row-val'>{{fmt
                    @model.hoaFeesPerMonth.amount
                    this.displayCurrency
                  }}</span>
              </div>
            </div>
            <div class='card-lifetime'>
              Lifetime:
              <strong>{{fmtFull
                  @model.lifetimeTotal
                  this.displayCurrency
                }}</strong>
            </div>
          {{else}}
            <p class='card-placeholder'>Enter home price and loan details to
              calculate payments.</p>
          {{/if}}
        </div>
      </article>

      {{! ── Full-overlay Modal (Fitted) ─────────────────────────────── }}
      {{#if this.isModalOpen}}
        <div
          class='mc-modal-backdrop'
          role='dialog'
          aria-modal='true'
          {{on 'click' this.closeModal}}
        >
          <div class='mc-modal' {{on 'click' this.stopModalProp}}>
            <div class='mc-modal-orbs' aria-hidden='true'>
              <div class='mc-orb mc-orb--blue'></div>
              <div class='mc-orb mc-orb--violet'></div>
              <div class='mc-orb mc-orb--amber'></div>
              <div class='mc-orb mc-orb--emerald'></div>
            </div>
            <div class='mc-modal-header'>
              <div class='mc-modal-header-left'>
                <span class='mc-modal-title'>Mortgage Breakdown</span>
                <div class='mc-modal-total-badge'>
                  <span
                    class='mc-modal-total-amount'
                  >{{this.monthlyDisplay}}</span>
                  <span class='mc-modal-total-label'>/ mo total</span>
                </div>
              </div>
              <div class='mc-modal-header-right'>
                <div class='mc-modal-tabs'>
                  <button
                    type='button'
                    class={{this.tabWheelClass}}
                    {{on 'click' this.switchToWheel}}
                  >
                    <svg
                      width='13'
                      height='13'
                      viewBox='0 0 24 24'
                      fill='none'
                      stroke='currentColor'
                      stroke-width='2'
                      aria-hidden='true'
                    ><circle cx='12' cy='12' r='10' /><circle
                        cx='12'
                        cy='12'
                        r='4'
                      /></svg>
                    Wheel
                  </button>
                  <button
                    type='button'
                    class={{this.tabBarClass}}
                    {{on 'click' this.switchToBar}}
                  >
                    <svg
                      width='13'
                      height='13'
                      viewBox='0 0 24 24'
                      fill='none'
                      stroke='currentColor'
                      stroke-width='2'
                      aria-hidden='true'
                    ><line x1='18' y1='20' x2='18' y2='10' /><line
                        x1='12'
                        y1='20'
                        x2='12'
                        y2='4'
                      /><line x1='6' y1='20' x2='6' y2='14' /><line
                        x1='2'
                        y1='20'
                        x2='22'
                        y2='20'
                      /></svg>
                    Bar
                  </button>
                </div>
                <button
                  type='button'
                  class='mc-modal-close'
                  aria-label='Close'
                  {{on 'click' this.closeModal}}
                >
                  <svg
                    width='16'
                    height='16'
                    viewBox='0 0 24 24'
                    fill='none'
                    stroke='currentColor'
                    stroke-width='2.5'
                    aria-hidden='true'
                  ><line x1='18' y1='6' x2='6' y2='18' /><line
                      x1='6'
                      y1='6'
                      x2='18'
                      y2='18'
                    /></svg>
                </button>
              </div>
            </div>
            <div class='mc-modal-body'>
              {{#if this.isWheelView}}
                <Css3DWheelView
                  @segments={{this.ringSegments}}
                  @total={{this.ringTotal}}
                  @centerText={{this.monthlyDisplay}}
                  @centerSub='PER MONTH'
                />
              {{else if this.isBarView}}
                <BarChartView
                  @segments={{this.ringSegments}}
                  @total={{this.ringTotal}}
                  @currency={{this.displayCurrency}}
                  @lifetimePrincipal={{@model.lifetimeMortgagePayment}}
                  @lifetimeTaxes={{@model.lifetimeTaxes}}
                  @lifetimeInsurance={{@model.lifetimeInsurance}}
                  @lifetimeHoa={{@model.lifetimeHoaFees}}
                  @lifetimeTotal={{@model.lifetimeTotal}}
                />
              {{/if}}
            </div>
          </div>
        </div>
      {{/if}}

    </article>

    <style scoped>
      /* ── Root ──────────────────────────────────────────────── */
      .mc-fitted {
        --sky: #0ea5e9;
        --sky-dim: rgba(14, 165, 233, 0.18);
        --blue: #2563eb;
        --amber: #f59e0b;
        --emerald: #10b981;
        --violet: #8b5cf6;
        --dark-900: #060d1a;
        --dark-800: #0a1628;
        --dark-700: #0f2040;
        --c-bg: #f1f5f9;
        --c-white: #ffffff;
        --c-text: #0f172a;
        --c-muted: #64748b;
        --c-border: #e2e8f0;
        --c-blue: var(--blue);
        --c-amber: var(--amber);
        --c-emerald: var(--emerald);
        --c-violet: var(--violet);

        width: 100%;
        height: 100%;
        position: relative; /* needed for modal overlay */
        font-family:
          'Inter',
          -apple-system,
          BlinkMacSystemFont,
          'Segoe UI',
          sans-serif;
        font-feature-settings: 'tnum' 1;
      }

      /* ── All sub-formats hidden by default ─────────────────── */
      .badge,
      .strip,
      .tile,
      .card {
        display: none;
        width: 100%;
        height: 100%;
        box-sizing: border-box;
        overflow: hidden;
      }

      /* ══════════════════════════════════════════════════════════
         BADGE  ≤150 × ≤169
      ══════════════════════════════════════════════════════════ */
      @container fitted-card (max-width: 150px) and (max-height: 169px) {
        .badge {
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          gap: 5px;
        }
      }

      .badge {
        background: linear-gradient(
          160deg,
          var(--dark-900) 0%,
          var(--dark-700) 100%
        );
        padding: 10px 8px;
        position: relative;
      }

      .badge-glow {
        position: absolute;
        inset: 0;
        background: radial-gradient(
          ellipse 90% 70% at 50% 15%,
          rgba(14, 165, 233, 0.22) 0%,
          transparent 70%
        );
        pointer-events: none;
      }

      .badge-icon {
        width: 38px;
        height: 38px;
        border-radius: 12px;
        background: linear-gradient(135deg, var(--sky) 0%, #0284c7 100%);
        display: flex;
        align-items: center;
        justify-content: center;
        color: white;
        box-shadow:
          0 0 20px rgba(14, 165, 233, 0.45),
          0 4px 12px rgba(0, 0, 0, 0.3);
        position: relative;
        flex-shrink: 0;
      }

      .badge-amount {
        font-size: 12px;
        font-weight: 800;
        color: var(--c-white);
        font-variant-numeric: tabular-nums;
        letter-spacing: -0.02em;
        position: relative;
        line-height: 1;
      }

      .badge-name {
        font-size: 12px;
        font-weight: 700;
        color: rgba(255, 255, 255, 0.9);
        position: relative;
        line-height: 1;
      }

      .badge-sub {
        font-size: 8px;
        font-weight: 600;
        color: rgba(255, 255, 255, 0.38);
        text-transform: uppercase;
        letter-spacing: 0.08em;
        position: relative;
      }

      /* ══════════════════════════════════════════════════════════
         STRIP  >150 × ≤169
      ══════════════════════════════════════════════════════════ */
      @container fitted-card (min-width: 151px) and (max-height: 169px) {
        .strip {
          display: flex;
          align-items: center;
          gap: 10px;
          padding: 0 14px;
        }
      }

      .strip {
        background: linear-gradient(
          90deg,
          var(--dark-900) 0%,
          var(--dark-800) 100%
        );
        border-left: 3px solid var(--sky);
      }

      .strip-icon {
        flex-shrink: 0;
        width: 32px;
        height: 32px;
        border-radius: 9px;
        background: linear-gradient(135deg, var(--sky) 0%, #0284c7 100%);
        display: flex;
        align-items: center;
        justify-content: center;
        color: white;
        box-shadow: 0 0 14px rgba(14, 165, 233, 0.4);
      }

      .strip-body {
        flex: 1;
        min-width: 0;
        display: flex;
        flex-direction: column;
        gap: 1px;
      }

      .strip-eyebrow {
        font-size: 8.5px;
        font-weight: 700;
        letter-spacing: 0.1em;
        text-transform: uppercase;
        color: var(--sky);
      }

      .strip-title {
        font-size: 12px;
        font-weight: 600;
        color: rgba(255, 255, 255, 0.9);
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      .strip-right {
        flex-shrink: 0;
        display: flex;
        flex-direction: column;
        align-items: flex-end;
        gap: 5px;
      }

      .strip-amount-row {
        display: flex;
        align-items: baseline;
        gap: 2px;
      }

      .strip-amount {
        font-size: 15px;
        font-weight: 800;
        color: var(--c-white);
        font-variant-numeric: tabular-nums;
        letter-spacing: -0.02em;
      }

      .strip-mo {
        font-size: 9.5px;
        color: rgba(255, 255, 255, 0.4);
        font-weight: 500;
      }

      .strip-bar {
        width: 64px;
        height: 4px;
        border-radius: 0;
        display: flex;
        overflow: hidden;
        gap: 0;
        background: rgba(255, 255, 255, 0.08);
      }

      .strip-bar-seg {
        height: 100%;
        border-radius: 0;
        flex-shrink: 0;
      }

      .strip-empty {
        font-size: 14px;
        font-weight: 700;
        color: rgba(255, 255, 255, 0.3);
      }

      /* ══════════════════════════════════════════════════════════
         TILE  ≤399 × ≥170
      ══════════════════════════════════════════════════════════ */
      @container fitted-card (max-width: 399px) and (min-height: 170px) {
        .tile {
          display: flex;
          flex-direction: column;
        }
      }

      .tile-top {
        flex: 1;
        background: linear-gradient(
          150deg,
          var(--dark-900) 0%,
          var(--dark-800) 55%,
          #0d1f3a 100%
        );
        display: flex;
        flex-direction: row;
        align-items: center;
        justify-content: center;
        gap: 10px;
        padding: 12px 14px;
        position: relative;
        overflow: hidden;
      }

      .tile-glow {
        position: absolute;
        top: -30px;
        left: 50%;
        transform: translateX(-50%);
        width: 200px;
        height: 140px;
        background: radial-gradient(
          ellipse,
          rgba(14, 165, 233, 0.22) 0%,
          transparent 70%
        );
        pointer-events: none;
      }

      /* ── Tile ring ── */
      .tile-ring-wrap {
        flex-shrink: 0;
        filter: drop-shadow(0 0 14px rgba(37, 99, 235, 0.45));
        position: relative;
        z-index: 1;
      }

      .tile-ring-wrap :deep(.donut-ring) {
        width: clamp(80px, 45cqh, 130px);
        height: clamp(80px, 45cqh, 130px);
      }

      /* ── Tile info column (right of ring) ── */
      .tile-info-col {
        display: flex;
        flex-direction: column;
        gap: 8px;
        position: relative;
        z-index: 1;
        min-width: 0;
      }

      .tile-eyebrow {
        display: flex;
        align-items: center;
        gap: 4px;
        font-size: 8.5px;
        font-weight: 700;
        letter-spacing: 0.12em;
        text-transform: uppercase;
        color: var(--sky);
        position: relative;
      }

      .tile-legend-col {
        display: flex;
        flex-direction: column;
        gap: 5px;
      }

      .tile-legend-item {
        display: flex;
        align-items: center;
        gap: 5px;
      }

      .tile-legend-dot {
        width: 6px;
        height: 6px;
        border-radius: 50%;
        flex-shrink: 0;
      }

      .tile-legend-lbl {
        font-size: 8px;
        font-weight: 600;
        color: rgba(255, 255, 255, 0.55);
        letter-spacing: 0.04em;
        text-transform: uppercase;
        white-space: nowrap;
      }

      .tile-empty {
        font-size: 28px;
        font-weight: 900;
        color: rgba(255, 255, 255, 0.2);
        position: relative;
      }

      .tile-empty-sub {
        font-size: 9px;
        color: rgba(255, 255, 255, 0.35);
        text-transform: uppercase;
        letter-spacing: 0.08em;
        position: relative;
      }

      .tile-foot {
        display: flex;
        align-items: center;
        background: var(--c-white);
        border-top: 1px solid var(--c-border);
        flex-shrink: 0;
      }

      .tile-stat {
        flex: 1;
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 1px;
        padding: 7px 4px;
      }

      .tile-sep {
        width: 1px;
        height: 22px;
        background: var(--c-border);
        flex-shrink: 0;
      }

      .tile-sk {
        font-size: 7.5px;
        font-weight: 700;
        color: var(--c-muted);
        text-transform: uppercase;
        letter-spacing: 0.07em;
      }

      .tile-sv {
        font-size: 11.5px;
        font-weight: 800;
        color: var(--c-text);
        font-variant-numeric: tabular-nums;
        letter-spacing: -0.02em;
      }

      /* ── Narrow tile  ≤185 × ≥170 : stack ring + legend vertically ── */
      @container fitted-card (max-width: 185px) and (min-height: 170px) {
        .tile-top {
          flex-direction: column;
          align-items: center;
          justify-content: center;
          gap: 6px;
          padding: 10px 12px 8px;
        }

        .tile-ring-wrap :deep(.donut-ring) {
          width: clamp(76px, 48cqw, 110px);
          height: clamp(76px, 48cqw, 110px);
        }

        .tile-info-col {
          align-items: center;
          gap: 0;
        }

        .tile-legend-col {
          flex-direction: row;
          flex-wrap: wrap;
          justify-content: center;
          gap: 3px 7px;
        }

        .tile-legend-lbl {
          display: none;
        }
      }

      /* ══════════════════════════════════════════════════════════
         CARD  ≥400 × ≥170
      ══════════════════════════════════════════════════════════ */
      @container fitted-card (min-width: 400px) and (min-height: 170px) {
        .card {
          display: flex;
          flex-direction: row;
        }
      }

      /* ── Card left panel (dark) ─────────────────────────────── */
      .card-left {
        width: clamp(120px, 30%, 165px);
        flex-shrink: 0;
        background: linear-gradient(
          160deg,
          var(--dark-900) 0%,
          var(--dark-800) 50%,
          #0d1f3a 100%
        );
        border-right: 1px solid rgba(14, 165, 233, 0.14);
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 7px;
        padding: 14px 12px;
        position: relative;
        overflow: hidden;
      }

      .card-left-glow {
        position: absolute;
        top: -40px;
        left: 50%;
        transform: translateX(-50%);
        width: 200px;
        height: 160px;
        background: radial-gradient(
          ellipse,
          rgba(14, 165, 233, 0.26) 0%,
          transparent 65%
        );
        pointer-events: none;
      }

      .card-eyebrow {
        display: flex;
        align-items: center;
        gap: 4px;
        font-size: 8px;
        font-weight: 700;
        letter-spacing: 0.12em;
        text-transform: uppercase;
        color: var(--sky);
        position: relative;
      }

      .card-ring-wrap {
        position: relative;
        filter: drop-shadow(0 0 16px rgba(14, 165, 233, 0.35));
      }

      .card-ring-wrap :deep(.donut-ring) {
        width: clamp(80px, 32cqh, 116px);
        height: clamp(80px, 32cqh, 116px);
      }

      .card-legend {
        display: flex;
        flex-wrap: wrap;
        gap: 3px 7px;
        justify-content: center;
        position: relative;
      }

      .card-legend-item {
        display: flex;
        align-items: center;
        gap: 3px;
        font-size: 7.5px;
        font-weight: 600;
        color: rgba(255, 255, 255, 0.5);
        letter-spacing: 0.04em;
        text-transform: uppercase;
      }

      .card-legend-dot {
        width: 6px;
        height: 6px;
        border-radius: 50%;
        flex-shrink: 0;
      }

      .card-empty-amount {
        font-size: 28px;
        font-weight: 900;
        color: rgba(255, 255, 255, 0.2);
        position: relative;
      }

      .card-empty-sub {
        font-size: 8.5px;
        color: rgba(255, 255, 255, 0.3);
        text-transform: uppercase;
        letter-spacing: 0.08em;
        position: relative;
      }

      /* ── Card right panel (white) ───────────────────────────── */
      .card-right {
        flex: 1;
        background: var(--c-white);
        display: flex;
        flex-direction: column;
        padding: 14px 16px;
        gap: 7px;
        min-width: 0;
        justify-content: center;
      }

      .card-title {
        font-size: clamp(12px, 3cqw, 15px);
        font-weight: 800;
        color: var(--c-text);
        margin: 0;
        letter-spacing: -0.025em;
        line-height: 1.15;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      .card-monthly-total {
        display: flex;
        align-items: baseline;
        gap: 4px;
        padding-bottom: 6px;
        border-bottom: 1px solid var(--c-border);
      }

      .card-monthly-amount {
        font-size: clamp(18px, 5cqw, 26px);
        font-weight: 900;
        color: var(--c-text);
        letter-spacing: -0.04em;
        font-variant-numeric: tabular-nums;
        line-height: 1;
      }

      .card-monthly-mo {
        font-size: 10px;
        font-weight: 600;
        color: var(--c-muted);
        text-transform: uppercase;
        letter-spacing: 0.05em;
      }

      .card-rows {
        display: flex;
        flex-direction: column;
        gap: 4px;
      }

      .card-row {
        display: flex;
        align-items: center;
        gap: 6px;
      }

      .card-row-dot {
        width: 6px;
        height: 6px;
        border-radius: 50%;
        flex-shrink: 0;
      }

      .card-row-lbl {
        flex: 1;
        font-size: 10px;
        color: var(--c-muted);
        font-weight: 500;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }

      .card-row-val {
        font-size: 11px;
        font-weight: 800;
        color: var(--c-text);
        font-variant-numeric: tabular-nums;
        letter-spacing: -0.02em;
        flex-shrink: 0;
      }

      .card-lifetime {
        font-size: 9.5px;
        color: var(--c-muted);
        margin: 0;
        display: flex;
        align-items: center;
        gap: 3px;
        border-top: 1px solid var(--c-border);
        padding-top: 6px;
      }

      .card-lifetime strong {
        color: var(--c-text);
        font-weight: 800;
        font-variant-numeric: tabular-nums;
        letter-spacing: -0.02em;
      }

      .card-placeholder {
        font-size: 10.5px;
        color: var(--c-muted);
        margin: 0;
        line-height: 1.5;
        font-style: italic;
      }

      /* ══ MODAL OVERLAY (Fitted) ═════════════════════════════ */

      /* ── Ambient orbs ── */
      .mc-modal-orbs {
        position: absolute;
        inset: 0;
        pointer-events: none;
        z-index: 0;
        overflow: hidden;
      }

      .mc-orb {
        position: absolute;
        border-radius: 50%;
        filter: blur(60px);
      }

      .mc-orb--blue {
        width: 380px;
        height: 380px;
        background: radial-gradient(circle, #2563eb 0%, transparent 70%);
        top: -120px;
        left: -80px;
        opacity: 0.22;
      }

      .mc-orb--violet {
        width: 340px;
        height: 340px;
        background: radial-gradient(circle, #8b5cf6 0%, transparent 70%);
        bottom: -100px;
        right: -80px;
        opacity: 0.2;
      }

      .mc-orb--amber {
        width: 260px;
        height: 260px;
        background: radial-gradient(circle, #f59e0b 0%, transparent 70%);
        top: 40%;
        left: 25%;
        opacity: 0.1;
      }

      .mc-orb--emerald {
        width: 220px;
        height: 220px;
        background: radial-gradient(circle, #10b981 0%, transparent 70%);
        bottom: 10%;
        left: 10%;
        opacity: 0.1;
      }

      .mc-modal-backdrop {
        position: absolute;
        inset: 0;
        z-index: 200;
        background: rgba(2, 6, 23, 0.92);
        backdrop-filter: blur(12px);
        display: flex;
        align-items: stretch;
        justify-content: stretch;
      }

      .mc-modal {
        position: absolute;
        inset: 0;
        display: flex;
        flex-direction: column;
        background: linear-gradient(
          160deg,
          #040810 0%,
          #080f20 35%,
          #0a1530 70%,
          #06090f 100%
        );
        overflow: hidden;
      }

      /* top multi-color accent line */
      .mc-modal::before {
        content: '';
        position: absolute;
        top: 0;
        left: 0;
        right: 0;
        height: 2px;
        background: linear-gradient(
          90deg,
          transparent 0%,
          #2563eb 20%,
          #8b5cf6 50%,
          #10b981 80%,
          transparent 100%
        );
        z-index: 10;
      }

      .mc-modal-header {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 1.5rem;
        padding: 1.125rem 1.75rem;
        border-bottom: 1px solid rgba(255, 255, 255, 0.07);
        flex-shrink: 0;
        background: linear-gradient(
          180deg,
          rgba(255, 255, 255, 0.04) 0%,
          rgba(255, 255, 255, 0.01) 100%
        );
        position: relative;
        z-index: 5;
      }

      .mc-modal-header-left {
        display: flex;
        flex-direction: column;
        gap: 0.2rem;
        min-width: 0;
      }

      .mc-modal-title {
        font-size: 0.625rem;
        font-weight: 700;
        color: rgba(255, 255, 255, 0.32);
        letter-spacing: 0.14em;
        text-transform: uppercase;
      }

      .mc-modal-total-badge {
        display: flex;
        align-items: baseline;
        gap: 0.5rem;
      }

      .mc-modal-total-amount {
        font-size: 2rem;
        font-weight: 900;
        background: linear-gradient(
          135deg,
          #e0e7ff 0%,
          #a5b4fc 40%,
          #c4b5fd 70%,
          #f0abfc 100%
        );
        -webkit-background-clip: text;
        -webkit-text-fill-color: transparent;
        background-clip: text;
        letter-spacing: -0.04em;
        font-variant-numeric: tabular-nums;
        line-height: 1;
        filter: drop-shadow(0 0 16px rgba(139, 92, 246, 0.5));
      }

      .mc-modal-total-label {
        font-size: 0.625rem;
        font-weight: 600;
        color: rgba(255, 255, 255, 0.3);
        letter-spacing: 0.08em;
        text-transform: uppercase;
        align-self: center;
      }

      .mc-modal-header-right {
        display: flex;
        align-items: center;
        gap: 0.75rem;
        flex-shrink: 0;
      }

      .mc-modal-tabs {
        display: flex;
        gap: 2px;
        background: rgba(255, 255, 255, 0.04);
        border: 1px solid rgba(255, 255, 255, 0.09);
        border-radius: 12px;
        padding: 3px;
      }

      .mc-mod-tab {
        display: flex;
        align-items: center;
        gap: 5px;
        padding: 0.4rem 1rem;
        border-radius: 9px;
        border: none;
        background: transparent;
        font-size: 0.75rem;
        font-weight: 600;
        color: rgba(255, 255, 255, 0.32);
        cursor: pointer;
        transition:
          background 0.2s ease,
          color 0.2s ease,
          box-shadow 0.2s ease;
        letter-spacing: 0.02em;
        font-family: inherit;
      }

      .mc-mod-tab:hover {
        color: rgba(255, 255, 255, 0.72);
        background: rgba(255, 255, 255, 0.08);
      }

      .mc-mod-tab--active {
        background: linear-gradient(
          135deg,
          rgba(99, 102, 241, 0.35) 0%,
          rgba(139, 92, 246, 0.28) 100%
        );
        color: rgba(255, 255, 255, 0.97);
        box-shadow:
          0 0 0 1px rgba(139, 92, 246, 0.5),
          0 4px 14px rgba(99, 102, 241, 0.3),
          inset 0 1px 0 rgba(255, 255, 255, 0.12);
      }

      .mc-modal-close {
        width: 34px;
        height: 34px;
        border-radius: 9px;
        border: 1px solid rgba(255, 255, 255, 0.09);
        background: rgba(255, 255, 255, 0.04);
        color: rgba(255, 255, 255, 0.35);
        cursor: pointer;
        display: flex;
        align-items: center;
        justify-content: center;
        flex-shrink: 0;
        transition:
          background 0.2s ease,
          color 0.2s ease,
          border-color 0.2s ease,
          box-shadow 0.2s ease,
          transform 0.15s ease;
      }

      .mc-modal-close:hover {
        background: rgba(239, 68, 68, 0.18);
        border-color: rgba(239, 68, 68, 0.45);
        color: #fca5a5;
        box-shadow: 0 0 12px rgba(239, 68, 68, 0.2);
        transform: scale(1.05);
      }

      .mc-modal-body {
        flex: 1;
        overflow: hidden;
        min-height: 0;
        position: relative;
        z-index: 1;
        display: flex;
        flex-direction: column;
      }
    </style>
  </template>
}

// ─── Card Definition ───────────────────────────────────────────────────────

export class MortgageCalculator extends CardDef {
  static displayName = 'Mortgage Calculator';
  static icon = HomeIcon;
  static prefersWideFormat = true;

  // ── Inputs ──────────────────────────────────────────────────────────────
  @field homePrice = contains(AmountWithCurrency);
  @field downPaymentPercentage = contains(NumberField);
  @field loanTermYears = contains(NumberField);
  @field interestRatePercentage = contains(NumberField);
  @field taxPerMonth = contains(AmountWithCurrency);
  @field insurancePerMonth = contains(AmountWithCurrency);
  @field hoaFeesPerMonth = contains(AmountWithCurrency);

  // ── Computed: loan basics ────────────────────────────────────────────────
  @field downPayment = contains(NumberField, {
    computeVia(this: MortgageCalculator) {
      return (
        (this.homePrice?.amount ?? 0) *
        ((this.downPaymentPercentage ?? 0) / 100)
      );
    },
  });

  @field loanAmount = contains(NumberField, {
    computeVia(this: MortgageCalculator) {
      return (this.homePrice?.amount ?? 0) - this.downPayment;
    },
  });

  @field numberOfPayments = contains(NumberField, {
    computeVia(this: MortgageCalculator) {
      return (this.loanTermYears ?? 0) * 12;
    },
  });

  @field monthlyInterestRate = contains(NumberField, {
    computeVia(this: MortgageCalculator) {
      return (this.interestRatePercentage ?? 0) / 100 / 12;
    },
  });

  // ── Computed: monthly ────────────────────────────────────────────────────
  @field monthlyMortgagePayment = contains(NumberField, {
    computeVia(this: MortgageCalculator) {
      const r = this.monthlyInterestRate;
      const n = this.numberOfPayments;
      const p = this.loanAmount;
      if (!r || !n || !p) return 0;
      return p * ((r * Math.pow(1 + r, n)) / (Math.pow(1 + r, n) - 1));
    },
  });

  @field monthlyTotal = contains(NumberField, {
    computeVia(this: MortgageCalculator) {
      return (
        (this.monthlyMortgagePayment ?? 0) +
        (this.taxPerMonth?.amount ?? 0) +
        (this.insurancePerMonth?.amount ?? 0) +
        (this.hoaFeesPerMonth?.amount ?? 0)
      );
    },
  });

  // ── Computed: lifetime ───────────────────────────────────────────────────
  @field lifetimeMortgagePayment = contains(NumberField, {
    computeVia(this: MortgageCalculator) {
      return (this.monthlyMortgagePayment ?? 0) * (this.numberOfPayments ?? 0);
    },
  });

  @field lifetimeTaxes = contains(NumberField, {
    computeVia(this: MortgageCalculator) {
      return (this.taxPerMonth?.amount ?? 0) * (this.numberOfPayments ?? 0);
    },
  });

  @field lifetimeInsurance = contains(NumberField, {
    computeVia(this: MortgageCalculator) {
      return (
        (this.insurancePerMonth?.amount ?? 0) * (this.numberOfPayments ?? 0)
      );
    },
  });

  @field lifetimeHoaFees = contains(NumberField, {
    computeVia(this: MortgageCalculator) {
      return (this.hoaFeesPerMonth?.amount ?? 0) * (this.numberOfPayments ?? 0);
    },
  });

  @field lifetimeTotal = contains(NumberField, {
    computeVia(this: MortgageCalculator) {
      return (
        (this.lifetimeMortgagePayment ?? 0) +
        (this.lifetimeTaxes ?? 0) +
        (this.lifetimeInsurance ?? 0) +
        (this.lifetimeHoaFees ?? 0)
      );
    },
  });

  @field title = contains(StringField, {
    computeVia(this: MortgageCalculator) {
      const amount = this.homePrice?.amount;
      if (amount) {
        return `Home: ${fmt(amount, this.homePrice?.currency?.code ?? 'USD')}`;
      }
      return 'Mortgage Calculator';
    },
  });

  // ─── Isolated ─────────────────────────────────────────────────────────────
  static isolated = IsolatedTemplate;

  // ─── Fitted ───────────────────────────────────────────────────────────────
  static fitted = FittedTemplate;

  // ─── Atom ──────────────────────────────────────────────────────────────────
  static atom = class Atom extends Component<typeof MortgageCalculator> {
    <template>
      <span class='mc-atom'>
        <HomeIcon class='mc-atom-icon' />
        <span class='mc-atom-value'>{{fmt
            @model.monthlyTotal
            @model.homePrice.currency.code
          }}</span>
        <span class='mc-atom-unit'>/mo</span>
      </span>

      <style scoped>
        .mc-atom {
          display: inline-flex;
          align-items: center;
          gap: 4px;
          font-family: var(--boxel-font-family, -apple-system, sans-serif);
        }

        .mc-atom-icon {
          width: 13px;
          height: 13px;
          color: #2563eb;
          flex-shrink: 0;
        }

        .mc-atom-value {
          font-size: 13px;
          font-weight: 700;
          color: #1e293b;
          font-variant-numeric: tabular-nums;
        }

        .mc-atom-unit {
          font-size: 11px;
          color: #94a3b8;
          font-weight: 500;
        }
      </style>
    </template>
  };
}
