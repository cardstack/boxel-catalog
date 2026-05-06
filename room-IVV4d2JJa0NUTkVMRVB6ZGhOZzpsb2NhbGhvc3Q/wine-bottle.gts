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
import { htmlSafe, type SafeString } from '@ember/template';

function htmlSafeBg(color: string | null | undefined): SafeString {
  return htmlSafe(color ? `--bg: ${color};` : '');
}
function htmlSafeAccent(color: string | null | undefined): SafeString {
  return htmlSafe(color ? `--accent: ${color};` : '');
}
function htmlSafeLeft(percent: number): SafeString {
  return htmlSafe(`left: ${percent}%;`);
}
function gtZero(n: number): boolean {
  return n > 0;
}

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

function pct(start: Date | null, end: Date | null, today: Date): number {
  if (!start || !end) return 0;
  const s = start.getTime();
  const e = end.getTime();
  if (e <= s) return 0;
  const t = today.getTime();
  return Math.max(0, Math.min(100, ((t - s) / (e - s)) * 100));
}

export class WineBottle extends CardDef {
  static displayName = 'Wine Bottle';
  static icon = GlassFullIcon;

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
  @field label = linksTo(() => ImageDef);

  @field displayName = contains(StringField, {
    computeVia: function (this: WineBottle) {
      const yr = this.vintage?.value;
      const name = [this.producer, this.varietal].filter(Boolean).join(' ');
      const parts = [yr, name].filter(Boolean);
      return parts.length ? parts.join(' ') : 'New Wine';
    },
  });

  @field cardTitle = contains(StringField, {
    computeVia: function (this: WineBottle) {
      return this.cardInfo?.name ?? this.displayName;
    },
  });

  @field valueChange = contains(NumberField, {
    computeVia: function (this: WineBottle) {
      const cur = this.currentValue?.amount ?? 0;
      const buy = this.purchasePrice?.amount ?? 0;
      return cur - buy;
    },
  });

  static isolated = class Isolated extends Component<typeof WineBottle> {
    get today() {
      return new Date();
    }
    get start() {
      return this.args.model.drinkingWindow?.start ?? null;
    }
    get end() {
      return this.args.model.drinkingWindow?.end ?? null;
    }
    get hasWindow() {
      return Boolean(this.start && this.end);
    }
    get cursorPct() {
      return pct(this.start, this.end, this.today);
    }
    get windowState(): 'before-window' | 'peak-window' | 'past-window' {
      if (!this.start || !this.end) return 'peak-window';
      const t = this.today.getTime();
      if (t < this.start.getTime()) return 'before-window';
      if (t > this.end.getTime()) return 'past-window';
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
    get delta() {
      const cur = this.args.model.currentValue?.amount ?? 0;
      const buy = this.args.model.purchasePrice?.amount ?? 0;
      return cur - buy;
    }
    get deltaPct() {
      const buy = this.args.model.purchasePrice?.amount ?? 0;
      if (!buy) return 0;
      return Math.round((this.delta / buy) * 100);
    }
    get deltaSign() {
      if (this.delta > 0) return 'up';
      if (this.delta < 0) return 'down';
      return 'flat';
    }
    get glassShape(): 'flute' | 'narrow' | 'wide' | 'rosé' {
      switch (this.args.model.wineType) {
        case 'sparkling':
          return 'flute';
        case 'white':
          return 'narrow';
        case 'rosé':
          return 'rosé';
        default:
          return 'wide';
      }
    }
    get bowlPath(): string {
      switch (this.glassShape) {
        case 'flute':
          return 'M 32 8 Q 32 60 38 78 L 42 78 Q 48 60 48 8';
        case 'narrow':
          return 'M 24 8 Q 24 56 32 74 L 48 74 Q 56 56 56 8';
        case 'rosé':
          return 'M 18 8 Q 18 50 32 70 L 48 70 Q 62 50 62 8';
        default:
          return 'M 14 8 Q 14 50 32 72 L 48 72 Q 66 50 66 8';
      }
    }
    get liquidPath(): string {
      switch (this.glassShape) {
        case 'flute':
          return 'M 33 28 L 38 78 L 42 78 L 47 28 Z';
        case 'narrow':
          return 'M 27 44 Q 24 56 32 74 L 48 74 Q 56 56 53 44 Z';
        case 'rosé':
          return 'M 22 40 Q 18 50 32 70 L 48 70 Q 62 50 58 40 Z';
        default:
          return 'M 18 44 Q 14 50 32 72 L 48 72 Q 66 50 62 44 Z';
      }
    }

    <template>
      <article class='cellar-sheet' style={{htmlSafeAccent @model.liquidColor}}>
        <header class='eyebrow-row'>
          <p class='eyebrow'>CELLAR{{#if @model.region}}
              ·
              {{@model.region}}{{/if}}</p>
          {{#if @model.wineType}}
            <span class='type-chip type-{{@model.wineType}}'>
              <@fields.wineType />
            </span>
          {{/if}}
        </header>

        <section class='hero-row'>
          <div class='label-panel'>
            {{#if @model.label}}
              <@fields.label @format='embedded' />
            {{else}}
              <div class='label-placeholder'>
                <span class='placeholder-line'>{{this.startYear}}</span>
                <span class='placeholder-name'>
                  {{if @model.producer @model.producer 'No label uploaded'}}
                </span>
                <span class='placeholder-hint'>add a label image to this card</span>
              </div>
            {{/if}}
          </div>

          <div class='glass-panel'>
            <svg class='wine-glass' viewBox='0 0 80 160' aria-hidden='true'>
              <path
                class='glass-liquid'
                d={{this.liquidPath}}
                fill={{if @model.liquidColor @model.liquidColor 'transparent'}}
              />
              <path class='glass-outline' d={{this.bowlPath}} fill='none' />
              <line class='stem' x1='40' y1='72' x2='40' y2='130' />
              <ellipse class='base' cx='40' cy='138' rx='22' ry='4' />
            </svg>
          </div>

          <div class='typography-panel'>
            {{#if @model.vintage.value}}
              <p class='vintage'>{{@model.vintage.value}}</p>
            {{/if}}
            {{#if @model.producer}}
              <h1 class='producer'>{{@model.producer}}</h1>
            {{/if}}
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
            <div class='timeline'>
              <div class='timeline-track'></div>
              <div
                class='timeline-cursor cursor-{{this.windowState}}'
                style={{htmlSafeLeft this.cursorPct}}
              ></div>
            </div>
            <div class='timeline-ends'>
              <span>{{this.startYear}}</span>
              <span>{{this.endYear}}</span>
            </div>
          </section>
        {{/if}}

        <section class='price-row'>
          {{#if @model.purchasePrice.amount}}
            <div class='price-cell'>
              <span class='price-label'>Purchased</span>
              <span class='price-value'><@fields.purchasePrice /></span>
            </div>
            <span class='price-arrow'>→</span>
          {{/if}}
          {{#if @model.currentValue.amount}}
            <div class='price-cell'>
              <span class='price-label'>Current</span>
              <span class='price-value'><@fields.currentValue /></span>
            </div>
            {{#if @model.purchasePrice.amount}}
              <span class='price-delta delta-{{this.deltaSign}}'>
                {{#if (gtZero this.delta)}}+{{/if}}{{this.delta}}
                ({{#if (gtZero this.deltaPct)}}+{{/if}}{{this.deltaPct}}%)
              </span>
            {{/if}}
          {{/if}}
        </section>

        <footer class='meta-row'>
          {{#if @model.bottlesRemaining}}
            <div class='bottles'>
              <@fields.bottlesRemaining />
              <span class='bottles-label'>bottles remaining</span>
            </div>
          {{/if}}
          {{#if @model.producerUrl}}
            <div class='producer-link'>
              <@fields.producerUrl @format='atom' />
            </div>
          {{/if}}
        </footer>
      </article>

      <style scoped>
        .cellar-sheet {
          --cellar-bg: #1a0f0f;
          --cellar-bg-2: #2a1818;
          --cellar-cream: #f5efd8;
          --cellar-cream-dim: #c9b88a;
          --cellar-gold: #c9a96a;
          --cellar-burgundy: #5a1a1f;
          --cellar-rule: rgba(201, 169, 106, 0.25);
          --accent: var(--cellar-gold);
          font-family: 'Georgia', 'Times New Roman', serif;
          color: var(--cellar-cream);
          background: radial-gradient(
            ellipse at top,
            var(--cellar-bg-2) 0%,
            var(--cellar-bg) 70%
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
          border-bottom: 1px solid var(--cellar-rule);
          margin: 0;
        }

        .eyebrow {
          margin: 0;
          color: var(--cellar-gold);
          letter-spacing: 0.3em;
          font-size: 0.75rem;
          text-transform: uppercase;
          font-family: system-ui, sans-serif;
        }

        .type-chip {
          padding: 0.25rem 0.75rem;
          border-radius: 999px;
          font-size: 0.75rem;
          letter-spacing: 0.15em;
          text-transform: uppercase;
          font-family: system-ui, sans-serif;
          border: 1px solid var(--cellar-rule);
          color: var(--cellar-cream);
          background: rgba(0, 0, 0, 0.25);
        }
        .type-red {
          background: rgba(122, 30, 42, 0.4);
        }
        .type-white {
          background: rgba(232, 226, 168, 0.18);
        }
        .type-rosé {
          background: rgba(244, 199, 194, 0.25);
        }
        .type-orange {
          background: rgba(216, 154, 79, 0.3);
        }
        .type-sparkling {
          background: rgba(232, 197, 71, 0.25);
        }

        .hero-row {
          display: grid;
          grid-template-columns: minmax(12rem, 1fr) auto minmax(14rem, 1.4fr);
          gap: var(--boxel-sp-xl);
          align-items: center;
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
          background: linear-gradient(180deg, #251618, #110808);
          border: 1px solid var(--cellar-rule);
          border-radius: 4px;
          padding: var(--boxel-sp-sm);
          display: flex;
          align-items: center;
          justify-content: center;
          box-shadow:
            0 12px 32px rgba(0, 0, 0, 0.6),
            inset 0 0 0 1px rgba(255, 255, 255, 0.03);
          overflow: hidden;
        }

        .label-panel :global(img) {
          max-width: 100%;
          max-height: 100%;
          object-fit: contain;
        }

        .label-placeholder {
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          gap: var(--boxel-sp-xs);
          color: var(--cellar-cream-dim);
          text-align: center;
          background: repeating-linear-gradient(
            45deg,
            rgba(245, 239, 216, 0.02) 0 8px,
            transparent 8px 16px
          );
          width: 100%;
          height: 100%;
          padding: var(--boxel-sp);
          border: 1px dashed var(--cellar-rule);
          border-radius: 2px;
        }
        .placeholder-line {
          font-size: 2rem;
          color: var(--cellar-gold);
        }
        .placeholder-name {
          font-size: 1rem;
          font-style: italic;
        }
        .placeholder-hint {
          font-size: 0.7rem;
          letter-spacing: 0.2em;
          text-transform: uppercase;
          color: var(--cellar-cream-dim);
          opacity: 0.7;
          font-family: system-ui, sans-serif;
        }

        .glass-panel {
          display: flex;
          align-items: center;
          justify-content: center;
        }
        .wine-glass {
          width: 80px;
          height: 160px;
          filter: drop-shadow(0 8px 12px rgba(0, 0, 0, 0.5));
        }
        .glass-outline,
        .stem {
          stroke: var(--cellar-cream-dim);
          stroke-width: 1.2;
        }
        .base {
          fill: var(--cellar-cream-dim);
          opacity: 0.6;
        }
        .glass-liquid {
          opacity: 0.95;
        }

        .typography-panel {
          display: flex;
          flex-direction: column;
          gap: 0.25rem;
          position: relative;
        }
        .vintage {
          font-size: 3rem;
          font-weight: 700;
          color: var(--cellar-gold);
          letter-spacing: 0.05em;
          margin: 0;
          line-height: 1;
        }
        .producer {
          font-size: 1.75rem;
          font-weight: 600;
          margin: 0;
          color: var(--cellar-cream);
          line-height: 1.1;
        }
        .varietal {
          font-style: italic;
          color: var(--cellar-cream-dim);
          margin: 0;
          font-size: 1rem;
        }

        .wax-seal {
          margin-top: var(--boxel-sp);
          align-self: flex-start;
          width: 5.5rem;
          height: 5.5rem;
          border-radius: 50%;
          background: radial-gradient(
            circle at 35% 30%,
            #8a2434,
            var(--cellar-burgundy) 60%,
            #3d0e14
          );
          color: var(--cellar-cream);
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          box-shadow:
            0 0 0 2px var(--cellar-burgundy),
            0 0 0 3px var(--cellar-gold),
            0 6px 16px rgba(0, 0, 0, 0.55);
          transform: rotate(-6deg);
        }
        .wax-score {
          font-size: 1.875rem;
          font-weight: 700;
          line-height: 1;
        }
        .wax-label {
          font-size: 0.55rem;
          letter-spacing: 0.25em;
          font-family: system-ui, sans-serif;
          color: var(--cellar-gold);
          margin-top: 0.15rem;
        }

        .timeline-row {
          padding-top: var(--boxel-sp-sm);
          border-top: 1px solid var(--cellar-rule);
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
          font-family: system-ui, sans-serif;
          letter-spacing: 0.25em;
          font-size: 0.7rem;
          color: var(--cellar-gold);
          text-transform: uppercase;
        }
        .timeline-status {
          margin: 0;
          font-family: system-ui, sans-serif;
          font-size: 0.7rem;
          letter-spacing: 0.15em;
          text-transform: uppercase;
        }
        .status-peak-window {
          color: var(--cellar-gold);
        }
        .status-before-window {
          color: #d89a4f;
        }
        .status-past-window {
          color: rgba(201, 169, 106, 0.55);
        }
        .timeline {
          position: relative;
          height: 1.75rem;
          margin: 0.5rem 0;
        }
        .timeline-track {
          position: absolute;
          left: 0;
          right: 0;
          top: 50%;
          height: 2px;
          background: linear-gradient(
            90deg,
            rgba(201, 169, 106, 0.3),
            var(--cellar-gold) 50%,
            rgba(201, 169, 106, 0.3)
          );
          transform: translateY(-50%);
        }
        .timeline-cursor {
          position: absolute;
          top: 0;
          bottom: 0;
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
          box-shadow: 0 0 0 2px var(--cellar-bg);
          transform: translate(-50%, -50%);
        }
        .cursor-peak-window {
          color: var(--cellar-gold);
        }
        .cursor-before-window {
          color: #d89a4f;
        }
        .cursor-past-window {
          color: rgba(201, 169, 106, 0.4);
        }

        .timeline-ends {
          display: flex;
          justify-content: space-between;
          font-family: system-ui, sans-serif;
          color: var(--cellar-cream-dim);
          font-size: 0.85rem;
        }

        .price-row {
          display: flex;
          flex-wrap: wrap;
          align-items: baseline;
          gap: var(--boxel-sp);
          padding-top: var(--boxel-sp-sm);
          border-top: 1px solid var(--cellar-rule);
        }
        .price-cell {
          display: flex;
          flex-direction: column;
          gap: 0.15rem;
        }
        .price-label {
          font-family: system-ui, sans-serif;
          letter-spacing: 0.2em;
          font-size: 0.65rem;
          text-transform: uppercase;
          color: var(--cellar-cream-dim);
        }
        .price-value {
          font-size: 1.25rem;
          font-weight: 600;
          color: var(--cellar-cream);
        }
        .price-arrow {
          color: var(--cellar-gold);
          font-size: 1.25rem;
          padding: 0 0.5rem;
        }
        .price-delta {
          font-family: system-ui, sans-serif;
          font-weight: 600;
          font-size: 0.95rem;
          margin-left: auto;
        }
        .delta-up {
          color: #7bc88a;
        }
        .delta-down {
          color: #d97a7a;
        }
        .delta-flat {
          color: var(--cellar-cream-dim);
        }

        .meta-row {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: var(--boxel-sp);
          padding-top: var(--boxel-sp-sm);
          border-top: 1px solid var(--cellar-rule);
          font-family: system-ui, sans-serif;
        }
        .bottles {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          color: var(--cellar-cream);
          --primary: var(--cellar-burgundy);
          --primary-foreground: var(--cellar-cream);
          --radius: 999px;
        }
        .bottles-label {
          font-size: 0.85rem;
          color: var(--cellar-cream-dim);
        }
        .producer-link {
          font-size: 0.9rem;
          color: var(--cellar-gold);
        }
        .producer-link :global(a) {
          color: var(--cellar-gold);
          text-decoration: none;
          border-bottom: 1px solid var(--cellar-rule);
          padding-bottom: 1px;
        }
        .producer-link :global(a:hover) {
          border-bottom-color: var(--cellar-gold);
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof WineBottle> {
    <template>
      <article class='wine-card type-{{@model.wineType}}'>
        <div class='swatch' style={{htmlSafeBg @model.liquidColor}}></div>
        <div class='content'>
          <div class='top-row'>
            <span class='vintage'>{{@model.vintage.value}}</span>
            <h3 class='producer'>{{@model.producer}}</h3>
            {{#if @model.wineType}}
              <span class='type-chip'><@fields.wineType /></span>
            {{/if}}
          </div>
          <p class='sub'>{{#if @model.varietal}}<span
              >{{@model.varietal}}</span>{{/if}}{{#if @model.region}}<span
                class='region'
              >· {{@model.region}}</span>{{/if}}</p>
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

      {{! template-lint-disable no-whitespace-for-layout }}
      <style scoped>
        .wine-card {
          display: grid;
          grid-template-columns: auto 1fr auto;
          gap: var(--boxel-sp-sm);
          align-items: center;
          padding: var(--boxel-sp-sm) var(--boxel-sp);
          border-radius: var(--boxel-border-radius);
          background-color: var(--card);
          color: var(--card-foreground);
          border: 1px solid var(--border);
          border-left-width: 4px;
          border-left-color: var(--border);
          font-family: 'Georgia', serif;
        }
        .type-red {
          border-left-color: #5a1a1f;
        }
        .type-white {
          border-left-color: #c9b54a;
        }
        .type-rosé {
          border-left-color: #e89aa0;
        }
        .type-orange {
          border-left-color: #b8732a;
        }
        .type-sparkling {
          border-left-color: #d4a83a;
        }

        .swatch {
          width: 1.25rem;
          height: 1.25rem;
          border-radius: 50%;
          background-color: var(--bg, transparent);
          box-shadow: inset 0 0 0 1px rgba(0, 0, 0, 0.15);
          flex-shrink: 0;
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
          color: var(--primary);
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
        .type-chip {
          margin-left: auto;
          font-size: 0.7rem;
          letter-spacing: 0.1em;
          text-transform: uppercase;
          font-family: system-ui, sans-serif;
          padding: 0.1rem 0.5rem;
          border-radius: 999px;
          background: var(--muted);
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
        .sub {
          margin: 0.15rem 0 0;
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
          font-style: italic;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .region {
          margin-left: 0.25rem;
          font-style: normal;
        }
        .right {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-sm);
          flex-shrink: 0;
          font-family: system-ui, sans-serif;
        }
        .score-badge {
          font-weight: 700;
          color: #5a1a1f;
          background: #f5e9c8;
          padding: 0.2rem 0.5rem;
          border-radius: 4px;
          font-size: 0.95rem;
          font-family: 'Georgia', serif;
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

  static fitted = class Fitted extends Component<typeof WineBottle> {
    <template>
      <article
        class='fitted-bottle'
        style={{htmlSafeAccent @model.liquidColor}}
      >
        {{#if @model.label}}
          <div class='image-bg'>
            <@fields.label @format='fitted' />
          </div>
        {{else}}
          <div class='image-bg fallback-bg'>
            <span class='fallback-vintage'>{{@model.vintage.value}}</span>
          </div>
        {{/if}}
        <div class='gradient-overlay'></div>
        <div class='swatch-dot' style={{htmlSafeBg @model.liquidColor}}></div>
        {{#if @model.wineType}}
          <span class='type-pill'><@fields.wineType /></span>
        {{/if}}
        <div class='caption'>
          <span class='caption-vintage'>{{@model.vintage.value}}</span>
          <span class='caption-producer'>{{@model.producer}}</span>
        </div>
      </article>

      <style scoped>
        .fitted-bottle {
          position: relative;
          width: 100%;
          height: 100%;
          overflow: hidden;
          background: linear-gradient(180deg, #2a1818, #110808);
          color: #f5efd8;
          font-family: 'Georgia', serif;
        }
        .image-bg {
          position: absolute;
          inset: 0;
          display: flex;
          align-items: center;
          justify-content: center;
        }
        .image-bg :global(img) {
          width: 100%;
          height: 100%;
          object-fit: cover;
        }
        .fallback-bg {
          background: radial-gradient(
            ellipse at center,
            rgba(201, 169, 106, 0.15) 0%,
            transparent 70%
          );
        }
        .fallback-vintage {
          font-size: clamp(2rem, 12cqi, 5rem);
          font-weight: 700;
          color: #c9a96a;
          letter-spacing: 0.05em;
        }
        .gradient-overlay {
          position: absolute;
          inset: 0;
          background: linear-gradient(
            180deg,
            transparent 50%,
            rgba(0, 0, 0, 0.7) 100%
          );
          pointer-events: none;
        }
        .swatch-dot {
          position: absolute;
          top: 0.5rem;
          right: 0.5rem;
          width: 0.75rem;
          height: 0.75rem;
          border-radius: 50%;
          background-color: var(--bg, transparent);
          box-shadow:
            0 0 0 2px rgba(0, 0, 0, 0.4),
            inset 0 0 0 1px rgba(255, 255, 255, 0.2);
        }
        .type-pill {
          position: absolute;
          top: 0.5rem;
          left: 0.5rem;
          font-size: 0.6rem;
          letter-spacing: 0.15em;
          text-transform: uppercase;
          font-family: system-ui, sans-serif;
          padding: 0.15rem 0.5rem;
          border-radius: 999px;
          background: rgba(0, 0, 0, 0.55);
          color: #f5efd8;
        }
        .caption {
          position: absolute;
          left: 0.5rem;
          right: 0.5rem;
          bottom: 0.5rem;
          display: flex;
          flex-direction: column;
          line-height: 1.1;
        }
        .caption-vintage {
          font-size: clamp(0.8rem, 4cqi, 1.4rem);
          font-weight: 700;
          color: #c9a96a;
          letter-spacing: 0.05em;
        }
        .caption-producer {
          font-size: clamp(0.7rem, 3cqi, 1rem);
          color: #f5efd8;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof WineBottle> {
    <template>
      <span class='wine-atom'>
        <span class='dot' style={{htmlSafeBg @model.liquidColor}}></span>
        {{#if @model.vintage.value}}
          <span class='vintage'>{{@model.vintage.value}}</span>
        {{/if}}
        {{#if @model.producer}}
          <span class='producer'>{{@model.producer}}</span>
        {{/if}}
        {{#if @model.score}}
          <span class='score'>· {{@model.score}}</span>
        {{/if}}
      </span>

      <style scoped>
        .wine-atom {
          display: inline-flex;
          align-items: center;
          gap: 0.35rem;
          padding: 0.15rem 0.6rem;
          border-radius: 999px;
          background: var(--muted);
          border: 1px solid var(--border);
          font-family: 'Georgia', serif;
          font-size: var(--boxel-font-size-sm);
          color: var(--card-foreground);
          line-height: 1.4;
          white-space: nowrap;
        }
        .dot {
          width: 0.6rem;
          height: 0.6rem;
          border-radius: 50%;
          background-color: var(--bg, transparent);
          box-shadow: inset 0 0 0 1px rgba(0, 0, 0, 0.2);
          flex-shrink: 0;
        }
        .vintage {
          font-weight: 700;
          color: var(--primary);
        }
        .producer {
          font-weight: 500;
        }
        .score {
          color: var(--muted-foreground);
          font-family: system-ui, sans-serif;
          font-size: 0.85rem;
        }
      </style>
    </template>
  };
}
