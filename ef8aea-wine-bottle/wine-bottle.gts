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
      /* The glass itself is drawn in the theme's own ink; only the wine is a
         model colour, and it arrives as --wb-liquid from the rendering card. */
      .bowl,
      .rim,
      .stem {
        fill: none;
        stroke: var(--muted-foreground, var(--boxel-500));
        stroke-width: 1.2;
        stroke-linecap: round;
      }
      .rim {
        opacity: 0.85;
      }
      .liquid {
        fill: var(--wb-liquid, transparent);
      }
      /* `white` here is light, not palette: the lit surface and the specular
         highlight of a glass read the same in every theme. */
      .surface {
        fill: color-mix(in oklch, var(--wb-liquid, transparent), white 28%);
      }
      .shine {
        fill: white;
        opacity: 0.11;
      }
      .foot {
        fill: var(--muted-foreground, var(--boxel-500));
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
            {{! variant, not explicit colours: the variant is a guaranteed
                fill/foreground pair from the theme. }}
            <Pill class='type-pill' @variant='muted'>
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
                style={{cssVar wb-cursor-left=(concat this.cursorPct '%')}}
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
                <Pill class='bottles-pill' @variant='primary'>
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
        /* Adapter block (§1a): the only place the semantic set is read into this
           card's vocabulary, and only for shades no semantic token expresses.
           Nothing here invents a colour, so the sheet is whatever the linked
           theme says it is — dark cellar or bright tasting room. */
        .cellar-sheet {
          --wb-sheet-raised: color-mix(
            in oklch,
            var(--foreground, var(--boxel-dark)) 5%,
            var(--background, var(--boxel-light))
          );
          --wb-mark-soft: color-mix(
            in oklch,
            var(--accent, var(--boxel-300)) 30%,
            transparent
          );

          font-family: var(--font-serif, Georgia, 'Times New Roman', serif);
          color: var(--foreground, var(--boxel-dark));
          background: radial-gradient(
            ellipse at top,
            var(--wb-sheet-raised) 0%,
            var(--background, var(--boxel-light)) 70%
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
          border-bottom: 1px solid var(--border, var(--boxel-border-color));
          margin: 0;
        }

        /* Hierarchy is carried by size, weight and tracking — not by a hue the
           theme never contrast-checked against the sheet (§2). */
        .eyebrow {
          margin: 0;
          color: var(--muted-foreground, var(--boxel-500));
          letter-spacing: 0.3em;
          font-size: var(--boxel-font-size-xs);
          text-transform: uppercase;
          font-family: var(--font-sans, system-ui, sans-serif);
        }

        .type-pill {
          letter-spacing: 0.15em;
          text-transform: uppercase;
          font-family: var(--font-sans, system-ui, sans-serif);
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
          background: var(--wb-sheet-raised);
          border: 1px solid var(--border, var(--boxel-border-color));
          border-radius: var(--radius, var(--boxel-border-radius));
          padding: var(--boxel-sp-sm);
          display: flex;
          align-items: center;
          justify-content: center;
          box-shadow: var(--shadow-lg, var(--boxel-deep-box-shadow));
          overflow: hidden;
        }

        .label-panel > :deep(*) {
          width: 100%;
          height: 100%;
          border-radius: calc(var(--radius, var(--boxel-border-radius)) - 1px);
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
          filter: drop-shadow(0 8px 12px var(--boxel-dark-40));
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
          color: var(--foreground, var(--boxel-dark));
          letter-spacing: 0.05em;
          margin: 0;
          line-height: 1;
        }
        .producer {
          font-size: var(--boxel-font-size-lg);
          font-weight: 600;
          margin: 0;
          color: var(--foreground, var(--boxel-dark));
          line-height: 1.1;
        }
        .varietal {
          font-style: italic;
          color: var(--muted-foreground, var(--boxel-500));
          margin: 0;
          font-size: var(--boxel-font-size);
        }

        .wax-seal {
          margin-top: var(--boxel-sp);
          align-self: flex-start;
          width: 5.5rem;
          height: 5.5rem;
          border-radius: 50%;
          /* A wax seal is a --primary fill, so its text is --primary-foreground:
             the one pair the theme guarantees against each other. white/black in
             the mix are lighting on that fill, not colours of their own. */
          background: radial-gradient(
            circle at 35% 30%,
            color-mix(in oklch, var(--primary, var(--boxel-700)), white 18%),
            var(--primary, var(--boxel-700)) 60%,
            color-mix(in oklch, var(--primary, var(--boxel-700)), black 35%)
          );
          color: var(--primary-foreground, var(--boxel-light));
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          box-shadow:
            0 0 0 2px var(--primary, var(--boxel-700)),
            0 0 0 3px var(--wb-mark-soft),
            0 6px 16px var(--boxel-dark-50);
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
          font-family: var(--font-sans, system-ui, sans-serif);
          color: color-mix(
            in oklch,
            var(--primary-foreground, var(--boxel-light)) 78%,
            transparent
          );
          margin-top: 0.15rem;
        }

        .timeline-row {
          padding-top: var(--boxel-sp-sm);
          border-top: 1px solid var(--border, var(--boxel-border-color));
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
          font-family: var(--font-sans, system-ui, sans-serif);
          letter-spacing: 0.25em;
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-500));
          text-transform: uppercase;
        }
        .timeline-status {
          margin: 0;
          font-family: var(--font-sans, system-ui, sans-serif);
          font-size: var(--boxel-font-size-xs);
          letter-spacing: 0.15em;
          text-transform: uppercase;
        }
        /* Three states, three levels of emphasis on the theme's own ink — a
           status hue would be a colour this card invented. The cursor dot picks
           the same value up through currentColor. */
        .status-peak-window {
          color: var(--foreground, var(--boxel-dark));
          font-weight: 700;
        }
        .status-before-window {
          color: var(--muted-foreground, var(--boxel-500));
        }
        .status-past-window {
          color: color-mix(
            in oklch,
            var(--muted-foreground, var(--boxel-500)) 55%,
            transparent
          );
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
            var(--wb-mark-soft),
            var(--accent, var(--boxel-300)) 50%,
            var(--wb-mark-soft)
          );
          transform: translateY(-50%);
        }
        .timeline-cursor {
          position: absolute;
          top: 0;
          bottom: 0;
          left: var(--wb-cursor-left, 0%);
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
          box-shadow: 0 0 0 2px var(--background, var(--boxel-light));
          transform: translate(-50%, -50%);
        }
        .cursor-peak-window {
          color: var(--foreground, var(--boxel-dark));
        }
        .cursor-before-window {
          color: var(--muted-foreground, var(--boxel-500));
        }
        .cursor-past-window {
          color: color-mix(
            in oklch,
            var(--muted-foreground, var(--boxel-500)) 55%,
            transparent
          );
        }

        .timeline-ends {
          display: flex;
          justify-content: space-between;
          font-family: var(--font-sans, system-ui, sans-serif);
          color: var(--muted-foreground, var(--boxel-500));
          font-size: var(--boxel-font-size-sm);
        }

        .price-row {
          display: flex;
          flex-wrap: wrap;
          align-items: baseline;
          gap: var(--boxel-sp);
          padding-top: var(--boxel-sp-sm);
          border-top: 1px solid var(--border, var(--boxel-border-color));
        }
        .price-cell {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-5xs);
        }
        .price-label {
          font-family: var(--font-sans, system-ui, sans-serif);
          letter-spacing: 0.2em;
          font-size: var(--boxel-font-size-xs);
          text-transform: uppercase;
          color: var(--muted-foreground, var(--boxel-500));
        }
        .price-value {
          font-size: var(--boxel-font-size-md);
          font-weight: 600;
          color: var(--foreground, var(--boxel-dark));
        }
        .price-arrow {
          color: var(--muted-foreground, var(--boxel-500));
          font-size: var(--boxel-font-size-md);
          padding: 0 var(--boxel-sp-xxs);
        }
        /* Self-diluting chips (§1b): each fill is a 12% dilution of its own text
           colour, so a theme change moves both and they can never fight. */
        .price-delta {
          font-family: var(--font-sans, system-ui, sans-serif);
          font-weight: 600;
          font-size: var(--boxel-font-size-sm);
          margin-left: auto;
          padding: var(--boxel-sp-6xs) var(--boxel-sp-xxs);
          border-radius: var(--radius, var(--boxel-border-radius-sm));
        }
        .delta-up {
          color: var(--foreground, var(--boxel-dark));
          background: color-mix(
            in oklch,
            var(--foreground, var(--boxel-dark)) 12%,
            transparent
          );
        }
        /* A loss is the one signal the theme does name, and it names it as a
           fill — so the label rides its paired foreground. */
        .delta-down {
          color: var(--destructive-foreground, var(--boxel-light));
          background: var(--destructive, var(--boxel-red));
        }
        .delta-flat {
          color: var(--muted-foreground, var(--boxel-500));
          background: color-mix(
            in oklch,
            var(--muted-foreground, var(--boxel-500)) 12%,
            transparent
          );
        }

        .meta-row {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: var(--boxel-sp);
          padding-top: var(--boxel-sp-sm);
          border-top: 1px solid var(--border, var(--boxel-border-color));
          font-family: var(--font-sans, system-ui, sans-serif);
        }
        .meta-left {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp);
          min-width: 0;
        }
        .bottles-pill {
          font-family: var(--font-sans, system-ui, sans-serif);
          font-size: var(--boxel-font-size-sm);
        }
        .purchased-on {
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground, var(--boxel-500));
        }
        .producer-link {
          font-size: var(--boxel-font-size-sm);
        }
        .producer-link :deep(a) {
          color: var(--foreground, var(--boxel-dark));
          text-decoration: none;
          border-bottom: 1px solid var(--border, var(--boxel-border-color));
          padding-bottom: 1px;
        }
        .producer-link :deep(a:hover) {
          border-bottom-color: var(--accent, var(--boxel-300));
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends WineBottleComponent {
    <template>
      {{! the wine's own colour is the row's left edge — a mark, never text }}
      <article class='wine-card' style={{cssVar wb-liquid=@model.liquidColor}}>
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
          display: grid;
          grid-template-columns: auto 1fr auto;
          gap: var(--boxel-sp-sm);
          align-items: center;
          padding: var(--boxel-sp-sm) var(--boxel-sp);
          border-radius: var(--radius, var(--boxel-border-radius));
          background-color: var(--card, var(--boxel-light));
          color: var(--card-foreground, var(--boxel-dark));
          border: 1px solid var(--border, var(--boxel-border-color));
          border-left: 4px solid
            var(--wb-liquid, var(--border, var(--boxel-border-color)));
          font-family: var(--font-serif, Georgia, serif);
          container-type: inline-size;
          container-name: wine-row;
        }

        /* Narrow rows: the left border and the swatch already encode the wine,
           so drop the pill rather than ellipsis the producer to one letter. */
        @container wine-row (inline-size <= 420px) {
          .type-pill {
            display: none;
          }
          .sub .region {
            display: none;
          }
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
          color: var(--muted-foreground, var(--boxel-500));
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
          color: var(--primary-foreground, var(--boxel-light));
          background: var(--primary, var(--boxel-700));
          padding: var(--boxel-sp-5xs) var(--boxel-sp-xxs);
          border-radius: var(--radius, var(--boxel-border-radius-sm));
          font-size: var(--boxel-font-size-sm);
          font-family: var(--font-serif, Georgia, serif);
        }
        .value {
          font-weight: 600;
          color: var(--card-foreground, var(--boxel-dark));
          font-size: var(--boxel-font-size-sm);
        }
        .bottles {
          color: var(--muted-foreground, var(--boxel-500));
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
        /* A tile is a card surface, so it forwards the --card pair; the caption
           reads on that surface in either theme instead of assuming a dark one. */
        .fitted-bottle {
          --wb-tile-raised: color-mix(
            in oklch,
            var(--card-foreground, var(--boxel-dark)) 5%,
            var(--card, var(--boxel-light))
          );

          width: 100%;
          height: 100%;
          overflow: hidden;
          background: linear-gradient(
            180deg,
            var(--wb-tile-raised),
            var(--card, var(--boxel-light))
          );
          color: var(--card-foreground, var(--boxel-dark));
          font-family: var(--font-serif, Georgia, 'Times New Roman', serif);
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
            color-mix(
                in oklch,
                var(--accent, var(--boxel-300)) 15%,
                transparent
              )
              0%,
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
        /* The art can be any image, so the caption gets a ground made of the
           tile's own surface rather than a black wash that only works in a dark
           theme — the caption then keeps --card-foreground and stays legible. */
        .scrim {
          position: absolute;
          inset: 0;
          background: linear-gradient(
            180deg,
            transparent 35%,
            color-mix(
                in oklch,
                var(--card, var(--boxel-light)) 75%,
                transparent
              )
              65%,
            var(--card, var(--boxel-light)) 100%
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
          font-family: var(--font-sans, system-ui, sans-serif);
        }
        .frame-score {
          display: none;
          position: absolute;
          top: var(--boxel-sp-xxs);
          right: var(--boxel-sp-xxs);
          font-family: var(--font-sans, system-ui, sans-serif);
          font-weight: 700;
          font-size: var(--boxel-font-size-sm);
          color: var(--primary-foreground, var(--boxel-light));
          background: var(--primary, var(--boxel-700));
          border: 1px solid var(--border, var(--boxel-border-color));
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
          color: var(--card-foreground, var(--boxel-dark));
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
          color: var(--muted-foreground, var(--boxel-500));
          font-size: var(--boxel-font-size-xs);
          font-style: italic;
        }
        .caption-value {
          font-family: var(--font-sans, system-ui, sans-serif);
          font-size: var(--boxel-font-size-xs);
          color: var(--card-foreground, var(--boxel-dark));
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
            color: var(--card-foreground, var(--boxel-dark));
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
            color: var(--card-foreground, var(--boxel-dark));
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
            font-family: var(--font-sans, system-ui, sans-serif);
            font-size: var(--boxel-font-size-xs);
            font-weight: 700;
            color: var(--primary-foreground, var(--boxel-light));
            background: var(--primary, var(--boxel-700));
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
          background: var(--muted, var(--boxel-100));
          border: 1px solid var(--border, var(--boxel-border-color));
          font-family: var(--font-serif, Georgia, serif);
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground, var(--boxel-500));
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
          color: color-mix(
            in oklch,
            var(--muted-foreground, var(--boxel-500)) 75%,
            transparent
          );
          font-family: var(--font-sans, system-ui, sans-serif);
          font-size: var(--boxel-font-size-xs);
        }
      </style>
    </template>
  };
}
