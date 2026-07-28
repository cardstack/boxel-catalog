import {
  CardDef,
  Component,
  field,
  contains,
  linksTo,
  ImageDef,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';
import DateField from 'https://cardstack.com/base/date';
import YearField from 'https://cardstack.com/base/date/year';
import DateRangeField from 'https://cardstack.com/base/date-range-field';
import AmountWithCurrency from 'https://cardstack.com/base/amount-with-currency';
import ColorField from 'https://cardstack.com/base/color';
import UrlField from 'https://cardstack.com/base/url';
import enumField from 'https://cardstack.com/base/enum';
import GlassFullIcon from '@cardstack/boxel-icons/glass-full';
import { Pill, Swatch } from '@cardstack/boxel-ui/components';
import { bool, cssVar, or } from '@cardstack/boxel-ui/helpers';
import { concat } from '@ember/helper';
import { guidFor } from '@ember/object/internals';
import GlimmerComponent from '@glimmer/component';

const WineTypeField = enumField(StringField, {
  displayName: 'Wine Type',
  options: [
    { value: 'red', label: 'Red' },
    { value: 'white', label: 'White' },
    { value: 'rosé', label: 'Rosé' },
    { value: 'orange', label: 'Orange' },
    { value: 'sparkling', label: 'Sparkling' },
  ],
});

// 'rosé' is a valid enum value but not a valid CSS class suffix.
const TYPE_SLUGS: Record<string, string> = {
  red: 'red',
  white: 'white',
  rosé: 'rose',
  orange: 'orange',
  sparkling: 'sparkling',
};

const TYPE_TINTS: Record<string, string> = {
  red: 'rgba(122, 30, 42, 0.4)',
  white: 'rgba(232, 226, 168, 0.18)',
  rosé: 'rgba(244, 199, 194, 0.25)',
  orange: 'rgba(216, 154, 79, 0.3)',
  sparkling: 'rgba(232, 197, 71, 0.25)',
};

interface GlassGeometry {
  rimHalfWidth: number;
  bowlBottom: number;
  liquidTop: number;
}

// viewBox is 0 0 80 160; the bowl is centred on x=40 and its base meets the stem.
const GLASS: Record<'flute' | 'narrow' | 'rose' | 'wide', GlassGeometry> = {
  flute: { rimHalfWidth: 7, bowlBottom: 88, liquidTop: 26 },
  narrow: { rimHalfWidth: 13, bowlBottom: 76, liquidTop: 40 },
  rose: { rimHalfWidth: 16, bowlBottom: 72, liquidTop: 40 },
  wide: { rimHalfWidth: 20, bowlBottom: 74, liquidTop: 40 },
};

const RIM_Y = 10;
const FOOT_Y = 138;
const AXIS = 40;
// A glass seen slightly from above shows its rim and liquid surface as ellipses;
// this is the squash ratio that sells the 3/4 view.
const PERSPECTIVE = 0.17;

function bowlControlPoints(geom: GlassGeometry) {
  const { rimHalfWidth: rw, bowlBottom: yb } = geom;
  const waist = RIM_Y + 0.72 * (yb - RIM_Y);
  return {
    xs: [AXIS - rw, AXIS - rw, AXIS - rw * 0.5, AXIS],
    ys: [RIM_Y, waist, yb, yb],
  };
}

function cubicAt(p: number[], t: number): number {
  const u = 1 - t;
  return (
    u * u * u * p[0] +
    3 * u * u * t * p[1] +
    3 * u * t * t * p[2] +
    t * t * t * p[3]
  );
}

function bowlOutline(geom: GlassGeometry): string {
  const { xs, ys } = bowlControlPoints(geom);
  const mirror = (x: number) => 2 * AXIS - x;
  return (
    `M ${xs[0]} ${ys[0]} ` +
    `C ${xs[1]} ${ys[1]}, ${xs[2]} ${ys[2]}, ${xs[3]} ${ys[3]} ` +
    `C ${mirror(xs[2])} ${ys[2]}, ${mirror(xs[1])} ${ys[1]}, ${mirror(xs[0])} ${ys[0]}`
  );
}

// Half-width of the bowl at a given y, so the liquid's surface ellipse lands exactly
// on the glass wall. y(t) is monotonic down the wall, so bisection is enough.
function bowlHalfWidthAtY(geom: GlassGeometry, y: number): number {
  const { xs, ys } = bowlControlPoints(geom);
  let lo = 0;
  let hi = 1;
  for (let i = 0; i < 32; i++) {
    const mid = (lo + hi) / 2;
    if (cubicAt(ys, mid) < y) lo = mid;
    else hi = mid;
  }
  return Math.max(0, AXIS - cubicAt(xs, (lo + hi) / 2));
}

interface WineGlassSignature {
  Args: { clipId: string; color?: string | null; geom: GlassGeometry };
  Element: SVGSVGElement;
}

class WineGlass extends GlimmerComponent<WineGlassSignature> {
  get outline() {
    return bowlOutline(this.args.geom);
  }
  // The outline closed across the rim — the bowl's interior, used to clip the fill.
  get interior() {
    return `${this.outline} Z`;
  }
  get liquidHeight() {
    return this.args.geom.bowlBottom - this.args.geom.liquidTop;
  }
  get rimRy() {
    return this.args.geom.rimHalfWidth * PERSPECTIVE;
  }
  get surfaceRx() {
    return bowlHalfWidthAtY(this.args.geom, this.args.geom.liquidTop);
  }
  get surfaceRy() {
    return Math.max(0.8, this.surfaceRx * PERSPECTIVE);
  }
  // Highlight sits on the wine, not in the empty bowl — 11% white over a near-black
  // bowl interior reads as a grey smudge rather than a specular highlight.
  get shine() {
    const { rimHalfWidth: rw, liquidTop } = this.args.geom;
    const height = this.liquidHeight;
    return {
      cx: AXIS - rw * 0.42,
      cy: liquidTop + height * 0.52,
      rx: Math.max(0.7, rw * 0.11),
      ry: height * 0.3,
    };
  }

  <template>
    <svg
      viewBox='0 0 80 160'
      aria-hidden='true'
      style={{cssVar wb-liquid=@color}}
      ...attributes
    >
      <defs>
        <clipPath id={{@clipId}}><path d={{this.interior}} /></clipPath>
      </defs>
      {{#if @color}}
        <g clip-path='url(#{{@clipId}})'>
          <rect
            class='liquid'
            x='0'
            y={{@geom.liquidTop}}
            width='80'
            height={{this.liquidHeight}}
          />
          <ellipse
            class='shine'
            cx={{this.shine.cx}}
            cy={{this.shine.cy}}
            rx={{this.shine.rx}}
            ry={{this.shine.ry}}
          />
        </g>
      {{/if}}
      {{#if @color}}
        <ellipse
          class='surface'
          cx={{AXIS}}
          cy={{@geom.liquidTop}}
          rx={{this.surfaceRx}}
          ry={{this.surfaceRy}}
        />
      {{/if}}
      <path class='bowl' d={{this.outline}} />
      <ellipse
        class='rim'
        cx={{AXIS}}
        cy={{RIM_Y}}
        rx={{@geom.rimHalfWidth}}
        ry={{this.rimRy}}
      />
      <line
        class='stem'
        x1={{AXIS}}
        y1={{@geom.bowlBottom}}
        x2={{AXIS}}
        y2={{FOOT_Y}}
      />
      <ellipse class='foot' cx={{AXIS}} cy={{FOOT_Y}} rx='17' ry='3.2' />
    </svg>

    <style scoped>
      /* --_cream-dim / --wb-liquid inherit from the card that renders this. */
      .bowl,
      .rim,
      .stem {
        fill: none;
        stroke: var(--_cream-dim, #c9b88a);
        stroke-width: 1.2;
        stroke-linecap: round;
      }
      .rim {
        opacity: 0.85;
      }
      .liquid {
        fill: var(--wb-liquid, transparent);
      }
      .surface {
        fill: color-mix(in oklab, var(--wb-liquid, transparent), white 28%);
      }
      .shine {
        fill: #fff;
        opacity: 0.11;
      }
      .foot {
        fill: var(--_cream-dim, #c9b88a);
        opacity: 0.6;
      }
    </style>
  </template>
}

function pct(start: Date | null, end: Date | null, today: Date): number {
  if (!start || !end) return 0;
  const s = start.getTime();
  const e = end.getTime();
  if (e <= s) return 0;
  const t = today.getTime();
  return Math.max(0, Math.min(100, ((t - s) / (e - s)) * 100));
}

function amountLabel(
  amount: number | null | undefined,
  symbol: string | null | undefined,
  { signed = false } = {},
): string {
  const n = amount ?? 0;
  const sign = signed ? (n > 0 ? '+' : n < 0 ? '−' : '') : '';
  const magnitude = Math.abs(n).toLocaleString('en-US');
  return symbol ? `${sign}${symbol} ${magnitude}` : `${sign}${magnitude}`;
}

// Every getter guards `model` — a linksTo card renders before its model resolves,
// and an unguarded read crashes the whole card.
class WineBottleComponent extends Component<typeof WineBottle> {
  get typeSlug() {
    let type = this.args.model?.wineType;
    return type ? (TYPE_SLUGS[type] ?? '') : '';
  }
  get typeTint() {
    let type = this.args.model?.wineType;
    return type ? TYPE_TINTS[type] : undefined;
  }
  get vintageLabel() {
    return this.args.model?.vintage?.value ?? '—';
  }
  get glassShape(): 'flute' | 'narrow' | 'wide' | 'rose' {
    switch (this.args.model?.wineType) {
      case 'sparkling':
        return 'flute';
      case 'white':
        return 'narrow';
      case 'rosé':
        return 'rose';
      default:
        return 'wide';
    }
  }
  get glass(): GlassGeometry {
    return GLASS[this.glassShape];
  }
  get clipId(): string {
    return `wb-bowl-${guidFor(this)}`;
  }
  get producerLabel() {
    return (
      this.args.model?.producer ?? this.args.model?.displayName ?? 'New Wine'
    );
  }
}

export class WineBottle extends CardDef {
  static displayName = 'Wine Bottle';
  static icon = GlassFullIcon;
  static prefersWideFormat = true;

  @field producer = contains(StringField);
  @field varietal = contains(StringField);
  @field region = contains(StringField);
  @field wineType = contains(WineTypeField);
  @field vintage = contains(YearField);
  @field purchaseDate = contains(DateField);
  @field drinkingWindow = contains(DateRangeField);
  @field purchasePrice = contains(AmountWithCurrency);
  @field currentValue = contains(AmountWithCurrency);
  @field score = contains(NumberField, {
    configuration: { presentation: 'score' },
  });
  @field bottlesRemaining = contains(NumberField, {
    configuration: { presentation: 'badge-counter' },
  });
  @field liquidColor = contains(ColorField);
  @field producerUrl = contains(UrlField);
  @field label = linksTo(() => ImageDef, { searchable: true });

  @field displayName = contains(StringField, {
    computeVia: function (this: WineBottle) {
      const yr = this.vintage?.value;
      const name = [this.producer, this.varietal].filter(Boolean).join(' ');
      const parts = [yr, name].filter(Boolean);
      return parts.length ? parts.join(' ') : 'New Wine';
    },
  });

  static isolated = class Isolated extends WineBottleComponent {
    get today() {
      return new Date();
    }
    get start() {
      return this.args.model?.drinkingWindow?.start ?? null;
    }
    get end() {
      return this.args.model?.drinkingWindow?.end ?? null;
    }
    get hasWindow() {
      return Boolean(this.start && this.end);
    }
    get cursorPct() {
      return pct(this.start, this.end, this.today);
    }
    get windowState(): 'before-window' | 'peak-window' | 'past-window' {
      const t = this.today.getTime();
      if (t < this.start!.getTime()) return 'before-window';
      if (t > this.end!.getTime()) return 'past-window';
      return 'peak-window';
    }
    get windowLabel() {
      switch (this.windowState) {
        case 'before-window':
          return 'hold';
        case 'past-window':
          return 'past peak';
        default:
          return 'peak';
      }
    }
    get startYear() {
      return this.start ? this.start.getFullYear() : null;
    }
    get endYear() {
      return this.end ? this.end.getFullYear() : null;
    }
    get windowValueText() {
      return `${Math.round(this.cursorPct)}% through the ${this.startYear} to ${this.endYear} drinking window, ${this.windowLabel}`;
    }
    get bottlesLabel() {
      const n = this.args.model?.bottlesRemaining ?? 0;
      return `${n} ${n === 1 ? 'bottle' : 'bottles'} remaining`;
    }
    get delta() {
      const cur = this.args.model?.currentValue?.amount ?? 0;
      const buy = this.args.model?.purchasePrice?.amount ?? 0;
      return cur - buy;
    }
    get deltaPct() {
      const buy = this.args.model?.purchasePrice?.amount ?? 0;
      if (!buy) return 0;
      return Math.round((this.delta / buy) * 100);
    }
    get deltaSign() {
      if (this.delta > 0) return 'up';
      if (this.delta < 0) return 'down';
      return 'flat';
    }
    get deltaLabel() {
      const symbol =
        this.args.model?.currentValue?.currency?.symbol ??
        this.args.model?.purchasePrice?.currency?.symbol;
      const pctPart = `${this.deltaPct > 0 ? '+' : this.deltaPct < 0 ? '−' : ''}${Math.abs(this.deltaPct)}%`;
      return `${amountLabel(this.delta, symbol, { signed: true })} (${pctPart})`;
    }

    <template>
      <article class='cellar-sheet {{if @model.label "has-label" "no-label"}}'>
        <header class='eyebrow-row'>
          <p class='eyebrow'>CELLAR{{#if @model.region}}
              ·
              {{@model.region}}{{/if}}</p>
          {{#if @model.wineType}}
            <Pill
              class='type-pill'
              @pillBackgroundColor={{this.typeTint}}
              @pillFontColor='var(--_cream)'
              @pillBorderColor='var(--_rule)'
            >
              <@fields.wineType />
            </Pill>
          {{/if}}
        </header>

        <section class='hero-row'>
          {{#if @model.label}}
            <div class='label-panel'>
              {{! fitted, not embedded: embedded is height:auto in a white card container and letterboxes the frame }}
              <@fields.label @format='fitted' />
            </div>
          {{/if}}

          <div class='glass-panel'>
            <WineGlass
              class='wine-glass'
              @geom={{this.glass}}
              @color={{@model.liquidColor}}
              @clipId={{this.clipId}}
            />
          </div>

          <div class='typography-panel'>
            <p class='vintage'>{{this.vintageLabel}}</p>
            <h1 class='producer'>{{this.producerLabel}}</h1>
            {{#if @model.varietal}}
              <p class='varietal'>{{@model.varietal}}</p>
            {{/if}}

            {{#if @model.score}}
              <div class='wax-seal'>
                <span class='wax-score'>{{@model.score}}</span>
                <span class='wax-label'>POINTS</span>
              </div>
            {{/if}}
          </div>
        </section>

        {{#if this.hasWindow}}
          <section class='timeline-row'>
            <div class='timeline-header'>
              <p class='timeline-title'>Drinking Window</p>
              <p class='timeline-status status-{{this.windowState}}'>
                today ·
                {{this.windowLabel}}
              </p>
            </div>
            {{! A position marker on a range, not a completion bar — ProgressBar's fill would misread as "how much wine is left". }}
            <div
              class='timeline'
              role='progressbar'
              aria-label='Drinking window'
              aria-valuemin='0'
              aria-valuemax='100'
              aria-valuenow={{this.cursorPct}}
              aria-valuetext={{this.windowValueText}}
            >
              <div class='timeline-track'></div>
              <div
                class='timeline-cursor cursor-{{this.windowState}}'
                style={{cssVar _cursor-left=(concat this.cursorPct '%')}}
              ></div>
            </div>
            <div class='timeline-ends'>
              <span>{{this.startYear}}</span>
              <span>{{this.endYear}}</span>
            </div>
          </section>
        {{/if}}

        {{#if (or @model.purchasePrice.amount @model.currentValue.amount)}}
          <section class='price-row'>
            {{#if @model.purchasePrice.amount}}
              <div class='price-cell'>
                <span class='price-label'>Purchased</span>
                <span class='price-value'><@fields.purchasePrice /></span>
              </div>
              <span class='price-arrow' aria-hidden='true'>→</span>
            {{/if}}
            {{#if @model.currentValue.amount}}
              <div class='price-cell'>
                <span class='price-label'>Current</span>
                <span class='price-value'><@fields.currentValue /></span>
              </div>
              {{#if @model.purchasePrice.amount}}
                <span
                  class='price-delta delta-{{this.deltaSign}}'
                >{{this.deltaLabel}}</span>
              {{/if}}
            {{/if}}
          </section>
        {{/if}}

        {{#if
          (or
            (bool @model.bottlesRemaining)
            (bool @model.purchaseDate)
            (bool @model.producerUrl)
          )
        }}
          <footer class='meta-row'>
            <div class='meta-left'>
              {{#if @model.bottlesRemaining}}
                <Pill
                  class='bottles-pill'
                  @pillBackgroundColor='var(--_burgundy)'
                  @pillFontColor='var(--_cream)'
                  @pillBorderColor='var(--_rule)'
                >
                  {{this.bottlesLabel}}
                </Pill>
              {{/if}}
              {{#if @model.purchaseDate}}
                <span class='purchased-on'>
                  acquired
                  <@fields.purchaseDate />
                </span>
              {{/if}}
            </div>
            {{#if @model.producerUrl}}
              <div class='producer-link'>
                <@fields.producerUrl @format='atom' />
              </div>
            {{/if}}
          </footer>
        {{/if}}
      </article>

      <style scoped>
        /* Art-directed cellar palette: --wb-* are the public knobs; the literals
           are the card's committed identity, not a theme fallback. */
        .cellar-sheet {
          --_bg: var(--wb-bg, #1a0f0f);
          --_bg-2: var(--wb-bg-2, #2a1818);
          --_cream: var(--wb-cream, #f5efd8);
          --_cream-dim: var(--wb-cream-dim, #c9b88a);
          --_gold: var(--wb-gold, #c9a96a);
          --_burgundy: var(--wb-burgundy, #5a1a1f);
          --_rule: var(--wb-rule, rgba(201, 169, 106, 0.25));
          --_gain: var(--wb-gain, var(--success, #7bc88a));
          --_loss: var(--wb-loss, var(--destructive, #d97a7a));
          --_radius: var(--wb-radius, var(--radius, 4px));
          --_font-display: var(
            --wb-font-display,
            var(--font-serif, 'Georgia', 'Times New Roman', serif)
          );
          --_font-ui: var(
            --wb-font-ui,
            var(--font-sans, system-ui, sans-serif)
          );

          font-family: var(--_font-display);
          color: var(--_cream);
          background: radial-gradient(
            ellipse at top,
            var(--_bg-2) 0%,
            var(--_bg) 70%
          );
          padding: var(--boxel-sp-xl);
          min-height: 100%;
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-lg);
          container-type: inline-size;
          container-name: cellar;
        }

        .eyebrow-row {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: var(--boxel-sp);
          padding-bottom: var(--boxel-sp-sm);
          border-bottom: 1px solid var(--_rule);
          margin: 0;
        }

        .eyebrow {
          margin: 0;
          color: var(--_gold);
          letter-spacing: 0.3em;
          font-size: var(--boxel-font-size-xs);
          text-transform: uppercase;
          font-family: var(--_font-ui);
        }

        .type-pill {
          letter-spacing: 0.15em;
          text-transform: uppercase;
          font-family: var(--_font-ui);
          font-size: var(--boxel-font-size-xs);
        }

        .hero-row {
          display: grid;
          grid-template-columns: minmax(12rem, 1fr) auto minmax(14rem, 1.4fr);
          gap: var(--boxel-sp-xl);
          align-items: center;
        }

        /* No label image: drop the frame entirely and let the tinted glass carry
           the hero, rather than showing an empty "add an image" affordance. */
        .no-label .hero-row {
          grid-template-columns: minmax(10rem, 1fr) minmax(14rem, 1.4fr);
        }
        .no-label .hero-row {
          min-height: 22rem;
        }
        .no-label .wine-glass {
          width: 210px;
          height: 420px;
        }

        @container cellar (inline-size <= 720px) {
          .hero-row {
            grid-template-columns: 1fr;
            gap: var(--boxel-sp-lg);
          }
          .glass-panel {
            justify-self: center;
          }
        }

        .label-panel {
          aspect-ratio: 3 / 4;
          max-height: 22rem;
          background: linear-gradient(180deg, var(--_bg-2), var(--_bg));
          border: 1px solid var(--_rule);
          border-radius: var(--_radius);
          padding: var(--boxel-sp-sm);
          display: flex;
          align-items: center;
          justify-content: center;
          box-shadow:
            0 12px 32px rgb(0 0 0 / 0.6),
            inset 0 0 0 1px rgb(255 255 255 / 0.03);
          overflow: hidden;
        }

        .label-panel > :deep(*) {
          width: 100%;
          height: 100%;
          border-radius: calc(var(--_radius) - 1px);
          overflow: hidden;
        }

        .glass-panel {
          display: flex;
          align-items: center;
          justify-content: center;
        }
        .wine-glass {
          width: 80px;
          height: 160px;
          filter: drop-shadow(0 8px 12px rgb(0 0 0 / 0.5));
        }
        .typography-panel {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-4xs);
          position: relative;
        }
        .vintage {
          font-size: var(--boxel-font-size-2xl);
          font-weight: 700;
          color: var(--_gold);
          letter-spacing: 0.05em;
          margin: 0;
          line-height: 1;
        }
        .producer {
          font-size: var(--boxel-font-size-lg);
          font-weight: 600;
          margin: 0;
          color: var(--_cream);
          line-height: 1.1;
        }
        .varietal {
          font-style: italic;
          color: var(--_cream-dim);
          margin: 0;
          font-size: var(--boxel-font-size);
        }

        .wax-seal {
          margin-top: var(--boxel-sp);
          align-self: flex-start;
          width: 5.5rem;
          height: 5.5rem;
          border-radius: 50%;
          background: radial-gradient(
            circle at 35% 30%,
            color-mix(in oklab, var(--_burgundy), white 18%),
            var(--_burgundy) 60%,
            color-mix(in oklab, var(--_burgundy), black 35%)
          );
          color: var(--_cream);
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          box-shadow:
            0 0 0 2px var(--_burgundy),
            0 0 0 3px var(--_gold),
            0 6px 16px rgb(0 0 0 / 0.55);
          transform: rotate(-6deg);
        }
        .wax-score {
          font-size: var(--boxel-font-size-lg);
          font-weight: 700;
          line-height: 1;
        }
        .wax-label {
          font-size: 0.55rem;
          letter-spacing: 0.25em;
          font-family: var(--_font-ui);
          color: var(--_gold);
          margin-top: 0.15rem;
        }

        .timeline-row {
          padding-top: var(--boxel-sp-sm);
          border-top: 1px solid var(--_rule);
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-xs);
        }
        .timeline-header {
          display: flex;
          justify-content: space-between;
          align-items: baseline;
          gap: var(--boxel-sp);
        }
        .timeline-title {
          margin: 0;
          font-family: var(--_font-ui);
          letter-spacing: 0.25em;
          font-size: var(--boxel-font-size-xs);
          color: var(--_gold);
          text-transform: uppercase;
        }
        .timeline-status {
          margin: 0;
          font-family: var(--_font-ui);
          font-size: var(--boxel-font-size-xs);
          letter-spacing: 0.15em;
          text-transform: uppercase;
        }
        .status-peak-window {
          color: var(--_gold);
        }
        .status-before-window {
          color: color-mix(in oklab, var(--_gold), #ff8a00 40%);
        }
        .status-past-window {
          color: color-mix(in oklab, var(--_gold), transparent 45%);
        }
        .timeline {
          position: relative;
          height: 1.75rem;
          margin: var(--boxel-sp-xxs) 0;
        }
        .timeline-track {
          position: absolute;
          left: 0;
          right: 0;
          top: 50%;
          height: 2px;
          background: linear-gradient(
            90deg,
            color-mix(in oklab, var(--_gold), transparent 70%),
            var(--_gold) 50%,
            color-mix(in oklab, var(--_gold), transparent 70%)
          );
          transform: translateY(-50%);
        }
        .timeline-cursor {
          position: absolute;
          top: 0;
          bottom: 0;
          left: var(--_cursor-left, 0%);
          width: 2px;
          transform: translateX(-50%);
          display: flex;
          flex-direction: column;
          align-items: center;
        }
        .timeline-cursor::after {
          content: '';
          position: absolute;
          top: 50%;
          left: 50%;
          width: 0.875rem;
          height: 0.875rem;
          border-radius: 50%;
          background: currentColor;
          box-shadow: 0 0 0 2px var(--_bg);
          transform: translate(-50%, -50%);
        }
        .cursor-peak-window {
          color: var(--_gold);
        }
        .cursor-before-window {
          color: color-mix(in oklab, var(--_gold), #ff8a00 40%);
        }
        .cursor-past-window {
          color: color-mix(in oklab, var(--_gold), transparent 60%);
        }

        .timeline-ends {
          display: flex;
          justify-content: space-between;
          font-family: var(--_font-ui);
          color: var(--_cream-dim);
          font-size: var(--boxel-font-size-sm);
        }

        .price-row {
          display: flex;
          flex-wrap: wrap;
          align-items: baseline;
          gap: var(--boxel-sp);
          padding-top: var(--boxel-sp-sm);
          border-top: 1px solid var(--_rule);
        }
        .price-cell {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-5xs);
        }
        .price-label {
          font-family: var(--_font-ui);
          letter-spacing: 0.2em;
          font-size: var(--boxel-font-size-xs);
          text-transform: uppercase;
          color: var(--_cream-dim);
        }
        .price-value {
          font-size: var(--boxel-font-size-md);
          font-weight: 600;
          color: var(--_cream);
        }
        .price-arrow {
          color: var(--_gold);
          font-size: var(--boxel-font-size-md);
          padding: 0 var(--boxel-sp-xxs);
        }
        .price-delta {
          font-family: var(--_font-ui);
          font-weight: 600;
          font-size: var(--boxel-font-size-sm);
          margin-left: auto;
        }
        .delta-up {
          color: var(--_gain);
        }
        .delta-down {
          color: var(--_loss);
        }
        .delta-flat {
          color: var(--_cream-dim);
        }

        .meta-row {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: var(--boxel-sp);
          padding-top: var(--boxel-sp-sm);
          border-top: 1px solid var(--_rule);
          font-family: var(--_font-ui);
        }
        .meta-left {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp);
          min-width: 0;
        }
        .bottles-pill {
          font-family: var(--_font-ui);
          font-size: var(--boxel-font-size-sm);
        }
        .purchased-on {
          font-size: var(--boxel-font-size-sm);
          color: var(--_cream-dim);
        }
        .producer-link {
          font-size: var(--boxel-font-size-sm);
          color: var(--_gold);
        }
        .producer-link :global(a) {
          color: var(--_gold);
          text-decoration: none;
          border-bottom: 1px solid var(--_rule);
          padding-bottom: 1px;
        }
        .producer-link :global(a:hover) {
          border-bottom-color: var(--_gold);
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends WineBottleComponent {
    <template>
      <article class='wine-card type-{{this.typeSlug}}'>
        <Swatch
          class='liquid-swatch'
          @color={{@model.liquidColor}}
          @style='round'
          @hideLabel={{true}}
        />
        <div class='content'>
          <div class='top-row'>
            <span class='vintage'>{{this.vintageLabel}}</span>
            <h3 class='producer'>{{this.producerLabel}}</h3>
            {{#if @model.wineType}}
              <Pill class='type-pill' @variant='muted'>
                <@fields.wineType />
              </Pill>
            {{/if}}
          </div>
          {{#if (or @model.varietal @model.region)}}
            <p class='sub'>
              {{#if @model.varietal}}<span>{{@model.varietal}}</span>{{/if}}
              {{#if @model.region}}<span class='region'>·
                  {{@model.region}}</span>{{/if}}
            </p>
          {{/if}}
        </div>
        <div class='right'>
          {{#if @model.score}}
            <span class='score-badge'>{{@model.score}}</span>
          {{/if}}
          {{#if @model.currentValue.amount}}
            <span class='value'><@fields.currentValue /></span>
          {{/if}}
          {{#if @model.bottlesRemaining}}
            <span class='bottles'>×{{@model.bottlesRemaining}}</span>
          {{/if}}
        </div>
      </article>

      <style scoped>
        .wine-card {
          --_type-accent: var(--border);
          --_burgundy: var(--wb-burgundy, #5a1a1f);
          --_cream: var(--wb-cream, #f5efd8);
          display: grid;
          grid-template-columns: auto 1fr auto;
          gap: var(--boxel-sp-sm);
          align-items: center;
          padding: var(--boxel-sp-sm) var(--boxel-sp);
          border-radius: var(--boxel-border-radius);
          background-color: var(--card);
          color: var(--card-foreground);
          border: 1px solid var(--border);
          border-left: 4px solid var(--_type-accent);
          font-family: var(--font-serif, 'Georgia', serif);
          container-type: inline-size;
          container-name: wine-row;
        }

        /* Narrow rows: the left border already encodes wine type, so drop the
           pill rather than ellipsis the producer down to one letter. */
        @container wine-row (inline-size <= 420px) {
          .type-pill {
            display: none;
          }
          .sub .region {
            display: none;
          }
        }
        .type-red {
          --_type-accent: var(--wb-type-red, #5a1a1f);
        }
        .type-white {
          --_type-accent: var(--wb-type-white, #c9b54a);
        }
        .type-rose {
          --_type-accent: var(--wb-type-rose, #e89aa0);
        }
        .type-orange {
          --_type-accent: var(--wb-type-orange, #b8732a);
        }
        .type-sparkling {
          --_type-accent: var(--wb-type-sparkling, #d4a83a);
        }

        .liquid-swatch {
          --swatch-width: 1.25rem;
          --swatch-height: 1.25rem;
        }

        .content {
          min-width: 0;
        }
        .top-row {
          display: flex;
          align-items: baseline;
          gap: var(--boxel-sp-xs);
          min-width: 0;
        }
        .vintage {
          font-weight: 700;
          font-size: var(--boxel-font-size);
        }
        .producer {
          font-size: var(--boxel-font-size);
          font-weight: 600;
          margin: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          min-width: 0;
        }
        .type-pill {
          margin-left: auto;
          flex-shrink: 0;
          font-size: var(--boxel-font-size-xs);
          letter-spacing: 0.1em;
          text-transform: uppercase;
          font-family: var(--font-sans, system-ui, sans-serif);
        }
        .sub {
          margin: var(--boxel-sp-5xs) 0 0;
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
          font-style: italic;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .region {
          font-style: normal;
        }
        .right {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-sm);
          flex-shrink: 0;
          font-family: var(--font-sans, system-ui, sans-serif);
        }
        .score-badge {
          font-weight: 700;
          color: var(--_cream);
          background: var(--_burgundy);
          padding: var(--boxel-sp-5xs) var(--boxel-sp-xxs);
          border-radius: var(--radius, 4px);
          font-size: var(--boxel-font-size-sm);
          font-family: var(--font-serif, 'Georgia', serif);
        }
        .value {
          font-weight: 600;
          color: var(--card-foreground);
          font-size: var(--boxel-font-size-sm);
        }
        .bottles {
          color: var(--muted-foreground);
          font-size: var(--boxel-font-size-sm);
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends WineBottleComponent {
    <template>
      <article class='fitted-bottle'>
        <div class='badge'>
          <span class='badge-vintage'>{{this.vintageLabel}}</span>
          <Swatch
            class='liquid-swatch'
            @color={{@model.liquidColor}}
            @style='round'
            @hideLabel={{true}}
          />
        </div>

        <div class='strip'>
          <Swatch
            class='liquid-swatch'
            @color={{@model.liquidColor}}
            @style='round'
            @hideLabel={{true}}
          />
          <span class='strip-vintage'>{{this.vintageLabel}}</span>
          <span class='strip-producer'>{{this.producerLabel}}</span>
          {{#if @model.score}}
            <span class='strip-score'>{{@model.score}}</span>
          {{/if}}
        </div>

        {{! tile and card share one frame — only type scale and the extra caption rows differ }}
        <div class='frame'>
          <div class='art'>
            {{#if @model.label}}
              <@fields.label @format='fitted' />
            {{else}}
              <WineGlass
                class='art-glass'
                @geom={{this.glass}}
                @color={{@model.liquidColor}}
                @clipId={{this.clipId}}
              />
            {{/if}}
          </div>
          <div class='scrim'></div>
          {{#if @model.wineType}}
            <Pill class='corner-pill' @variant='muted'>
              <@fields.wineType />
            </Pill>
          {{/if}}
          {{#if @model.score}}
            <span class='frame-score'>{{@model.score}}</span>
          {{/if}}
          <div class='caption'>
            <span class='caption-vintage'>{{this.vintageLabel}}</span>
            <span class='caption-producer'>{{this.producerLabel}}</span>
            {{#if (or @model.varietal @model.region)}}
              <span class='caption-meta'>
                {{#if @model.varietal}}{{@model.varietal}}{{/if}}
                {{#if @model.region}}· {{@model.region}}{{/if}}
              </span>
            {{/if}}
            {{#if @model.currentValue.amount}}
              <span class='caption-value'><@fields.currentValue /></span>
            {{/if}}
          </div>
        </div>
      </article>

      <style scoped>
        .fitted-bottle {
          --_bg: var(--wb-bg, #1a0f0f);
          --_bg-2: var(--wb-bg-2, #2a1818);
          --_cream: var(--wb-cream, #f5efd8);
          --_cream-dim: var(--wb-cream-dim, #c9b88a);
          --_gold: var(--wb-gold, #c9a96a);
          --_burgundy: var(--wb-burgundy, #5a1a1f);
          --_font-display: var(
            --wb-font-display,
            var(--font-serif, 'Georgia', 'Times New Roman', serif)
          );
          --_font-ui: var(
            --wb-font-ui,
            var(--font-sans, system-ui, sans-serif)
          );

          width: 100%;
          height: 100%;
          overflow: hidden;
          background: linear-gradient(180deg, var(--_bg-2), var(--_bg));
          color: var(--_cream);
          font-family: var(--_font-display);
        }

        .badge,
        .strip,
        .frame {
          display: none;
          width: 100%;
          height: 100%;
          box-sizing: border-box;
          overflow: hidden;
        }

        .liquid-swatch {
          --swatch-width: 0.7rem;
          --swatch-height: 0.7rem;
        }

        /* Decorative only. `<@fields.label>` renders the linked ImageDef as a real
           card link, so without this the whole tile navigates to the image file
           instead of the wine. */
        .art {
          position: absolute;
          inset: 0;
          display: flex;
          align-items: center;
          justify-content: center;
          pointer-events: none;
          background: radial-gradient(
            ellipse at center,
            color-mix(in oklab, var(--_gold), transparent 85%) 0%,
            transparent 70%
          );
        }
        .art > :deep(*) {
          width: 100%;
          height: 100%;
        }
        .art-glass {
          width: 45%;
          max-width: 80px;
          height: auto;
          opacity: 0.85;
        }
        .scrim {
          position: absolute;
          inset: 0;
          background: linear-gradient(
            180deg,
            rgb(0 0 0 / 0.35) 0%,
            transparent 30%,
            rgb(0 0 0 / 0.82) 100%
          );
          pointer-events: none;
        }
        .corner-pill {
          position: absolute;
          top: var(--boxel-sp-xxs);
          left: var(--boxel-sp-xxs);
          font-size: var(--boxel-font-size-xs);
          letter-spacing: 0.15em;
          text-transform: uppercase;
          font-family: var(--_font-ui);
        }
        .frame-score {
          display: none;
          position: absolute;
          top: var(--boxel-sp-xxs);
          right: var(--boxel-sp-xxs);
          font-family: var(--_font-ui);
          font-weight: 700;
          font-size: var(--boxel-font-size-sm);
          color: var(--_cream);
          background: var(--_burgundy);
          border: 1px solid var(--_gold);
          border-radius: 999px;
          padding: var(--boxel-sp-6xs) var(--boxel-sp-xs);
        }
        .caption {
          position: absolute;
          left: var(--boxel-sp-xxs);
          right: var(--boxel-sp-xxs);
          bottom: var(--boxel-sp-xxs);
          display: flex;
          flex-direction: column;
          line-height: 1.15;
          min-width: 0;
        }
        .caption-vintage {
          font-weight: 700;
          color: var(--_gold);
          letter-spacing: 0.05em;
        }
        .caption-producer,
        .caption-meta,
        .caption-value {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .caption-meta,
        .caption-value {
          display: none;
        }
        .caption-meta {
          color: var(--_cream-dim);
          font-size: var(--boxel-font-size-xs);
          font-style: italic;
        }
        .caption-value {
          font-family: var(--_font-ui);
          font-size: var(--boxel-font-size-xs);
          color: var(--_cream);
          margin-top: var(--boxel-sp-6xs);
        }

        /* ══ BADGE ≤150 × ≤169 ══ */
        @container fitted-card (max-width: 150px) and (max-height: 169px) {
          .badge {
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            gap: var(--boxel-sp-5xs);
            padding: var(--boxel-sp-xxs);
          }
          .badge-vintage {
            font-size: var(--boxel-font-size-md);
            font-weight: 700;
            color: var(--_gold);
            letter-spacing: 0.05em;
          }
        }

        /* ══ STRIP >150 × ≤169 ══ */
        @container fitted-card (min-width: 151px) and (max-height: 169px) {
          .strip {
            display: flex;
            align-items: center;
            gap: var(--boxel-sp-xxs);
            padding: 0 var(--boxel-sp-xs);
          }
          .strip-vintage {
            font-weight: 700;
            color: var(--_gold);
            flex-shrink: 0;
          }
          .strip-producer {
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
            min-width: 0;
          }
          .strip-score {
            margin-left: auto;
            flex-shrink: 0;
            font-family: var(--_font-ui);
            font-size: var(--boxel-font-size-xs);
            font-weight: 700;
            color: var(--_cream);
            background: var(--_burgundy);
            border-radius: 999px;
            padding: var(--boxel-sp-6xs) var(--boxel-sp-xxs);
          }
        }

        /* ══ TILE ≤399 × ≥170 ══ */
        @container fitted-card (max-width: 399px) and (min-height: 170px) {
          .frame {
            display: block;
            position: relative;
          }
          .caption-vintage {
            font-size: var(--boxel-font-size);
          }
          .caption-producer {
            font-size: var(--boxel-font-size-sm);
          }
        }

        /* ══ CARD ≥400 × ≥170 ══ adds score, varietal/region and value ══ */
        @container fitted-card (min-width: 400px) and (min-height: 170px) {
          .frame {
            display: block;
            position: relative;
          }
          .caption-vintage {
            font-size: var(--boxel-font-size-lg);
          }
          .caption-producer {
            font-size: var(--boxel-font-size-md);
          }
          .caption-meta,
          .caption-value,
          .frame-score {
            display: block;
          }
        }
      </style>
    </template>
  };

  static atom = class Atom extends WineBottleComponent {
    <template>
      <span class='wine-atom'>
        <Swatch
          class='liquid-swatch'
          @color={{@model.liquidColor}}
          @style='round'
          @hideLabel={{true}}
        />
        <span class='vintage'>{{this.vintageLabel}}</span>
        <span class='producer'>{{this.producerLabel}}</span>
        {{#if @model.score}}
          <span class='score'>· {{@model.score}}</span>
        {{/if}}
      </span>

      <style scoped>
        .wine-atom {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-5xs);
          padding: var(--boxel-sp-6xs) var(--boxel-sp-xxs);
          border-radius: 999px;
          background: var(--muted);
          border: 1px solid var(--border);
          font-family: var(--font-serif, 'Georgia', serif);
          font-size: var(--boxel-font-size-sm);
          color: var(--card-foreground);
          line-height: 1.4;
          white-space: nowrap;
        }
        .liquid-swatch {
          --swatch-width: 0.6rem;
          --swatch-height: 0.6rem;
        }
        .vintage {
          font-weight: 700;
        }
        .producer {
          font-weight: 500;
        }
        .score {
          color: var(--muted-foreground);
          font-family: var(--font-sans, system-ui, sans-serif);
          font-size: var(--boxel-font-size-xs);
        }
      </style>
    </template>
  };
}
