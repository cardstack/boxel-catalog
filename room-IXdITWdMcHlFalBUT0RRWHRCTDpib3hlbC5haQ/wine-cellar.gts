import {
  CardDef,
  Component,
  field,
  contains,
  linksToMany,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';
import MarkdownField from 'https://cardstack.com/base/markdown';
import GlassFullIcon from '@cardstack/boxel-icons/glass-full';
import { htmlSafe, type SafeString } from '@ember/template';
import { WineBottle } from './wine-bottle';

function htmlSafeBg(color: string | null | undefined): SafeString {
  return htmlSafe(color ? `--bg: ${color};` : '');
}
function htmlSafePos(leftPct: number, widthPct: number): SafeString {
  return htmlSafe(`left: ${leftPct}%; width: ${Math.max(widthPct, 0.5)}%;`);
}
function htmlSafeLeft(pct: number): SafeString {
  return htmlSafe(`left: ${pct}%;`);
}

interface TimelineRow {
  id: string;
  name: string;
  vintage: number | null;
  liquidColor: string;
  startYear: number;
  endYear: number;
  startPct: number;
  widthPct: number;
  cursorPct: number;
  state: 'before-window' | 'peak-window' | 'past-window';
  score: number | null;
  bottlesRemaining: number | null;
  currentValue: number | null;
  currencyCode: string;
}

export class WineCellar extends CardDef {
  static displayName = 'Wine Cellar';
  static icon = GlassFullIcon;

  @field name = contains(StringField);
  @field location = contains(StringField);
  @field owner = contains(StringField);
  @field bottles = linksToMany(() => WineBottle);
  @field notes = contains(MarkdownField);

  @field totalBottles = contains(NumberField, {
    computeVia: function (this: WineCellar) {
      return (this.bottles ?? []).reduce(
        (acc, b) => acc + (b?.bottlesRemaining ?? 0),
        0,
      );
    },
  });

  @field totalValue = contains(NumberField, {
    computeVia: function (this: WineCellar) {
      return (this.bottles ?? []).reduce((acc, b) => {
        const v = b?.currentValue?.amount ?? 0;
        const n = b?.bottlesRemaining ?? 0;
        return acc + v * n;
      }, 0);
    },
  });

  @field averageScore = contains(NumberField, {
    computeVia: function (this: WineCellar) {
      const scored = (this.bottles ?? []).filter((b): b is WineBottle =>
        Boolean(b?.score),
      );
      if (!scored.length) return 0;
      const sum = scored.reduce((acc, b) => acc + (b.score ?? 0), 0);
      return Math.round((sum / scored.length) * 10) / 10;
    },
  });

  @field displayName = contains(StringField, {
    computeVia: function (this: WineCellar) {
      return this.name ?? 'New Cellar';
    },
  });

  @field cardTitle = contains(StringField, {
    computeVia: function (this: WineCellar) {
      return this.cardInfo?.name ?? this.displayName;
    },
  });

  static isolated = class Isolated extends Component<typeof WineCellar> {
    get bottles(): WineBottle[] {
      return (this.args.model.bottles ?? []).filter((b): b is WineBottle =>
        Boolean(b),
      );
    }
    get today() {
      return new Date();
    }
    get yearBounds(): { min: number; max: number } | null {
      const years: number[] = [];
      for (const b of this.bottles) {
        const s = b.drinkingWindow?.start;
        const e = b.drinkingWindow?.end;
        if (s) years.push(s.getFullYear());
        if (e) years.push(e.getFullYear());
      }
      const todayYear = this.today.getFullYear();
      years.push(todayYear);
      if (!years.length) return null;
      const min = Math.min(...years);
      const max = Math.max(...years);
      if (max === min) return { min, max: min + 1 };
      return { min, max };
    }
    get yearTicks(): number[] {
      const b = this.yearBounds;
      if (!b) return [];
      const span = b.max - b.min;
      const step = span <= 10 ? 2 : span <= 25 ? 5 : 10;
      const start = Math.ceil(b.min / step) * step;
      const ticks: number[] = [b.min];
      for (let y = start; y < b.max; y += step) {
        if (y > b.min && y < b.max) ticks.push(y);
      }
      ticks.push(b.max);
      return ticks;
    }
    get todayPct(): number {
      const b = this.yearBounds;
      if (!b) return 0;
      const t = this.today.getFullYear() + this.today.getMonth() / 12;
      return ((t - b.min) / (b.max - b.min)) * 100;
    }
    get rows(): TimelineRow[] {
      const bounds = this.yearBounds;
      if (!bounds) return [];
      const span = bounds.max - bounds.min;
      const todayMs = this.today.getTime();
      return this.bottles.map((b) => {
        const startYear = b.drinkingWindow?.start?.getFullYear() ?? bounds.min;
        const endYear = b.drinkingWindow?.end?.getFullYear() ?? bounds.max;
        const startPct = ((startYear - bounds.min) / span) * 100;
        const widthPct = ((endYear - startYear) / span) * 100;
        const cursorPct = this.todayPct;
        let state: TimelineRow['state'] = 'peak-window';
        const s = b.drinkingWindow?.start?.getTime();
        const e = b.drinkingWindow?.end?.getTime();
        if (s && todayMs < s) state = 'before-window';
        else if (e && todayMs > e) state = 'past-window';
        return {
          id: b.id ?? `${b.producer}-${b.vintage?.value ?? ''}`,
          name: [b.vintage?.value, b.producer].filter(Boolean).join(' '),
          vintage: b.vintage?.value ?? null,
          liquidColor: b.liquidColor ?? '#7a1e2a',
          startYear,
          endYear,
          startPct,
          widthPct,
          cursorPct,
          state,
          score: b.score ?? null,
          bottlesRemaining: b.bottlesRemaining ?? null,
          currentValue: b.currentValue?.amount ?? null,
          currencyCode: b.currentValue?.currency?.code ?? 'USD',
        };
      });
    }
    get typeCounts(): Array<{ type: string; count: number; color: string }> {
      const counts = new Map<string, number>();
      for (const b of this.bottles) {
        const t = b.wineType ?? 'unknown';
        counts.set(t, (counts.get(t) ?? 0) + (b.bottlesRemaining ?? 0));
      }
      const colorMap: Record<string, string> = {
        red: '#5a1a1f',
        white: '#c9b54a',
        rosé: '#e89aa0',
        orange: '#b8732a',
        sparkling: '#d4a83a',
      };
      return Array.from(counts.entries())
        .filter(([, c]) => c > 0)
        .sort((a, b) => b[1] - a[1])
        .map(([type, count]) => ({
          type,
          count,
          color: colorMap[type] ?? '#888',
        }));
    }
    get cellarDisplayName(): string {
      return this.args.model.name ?? 'Untitled Cellar';
    }

    <template>
      <article class='cellar-sheet'>
        <header class='cellar-header'>
          <div class='header-left'>
            <p class='eyebrow'>CELLAR</p>
            <h1 class='cellar-name'>{{this.cellarDisplayName}}</h1>
            {{#if @model.location}}
              <p class='location'>{{@model.location}}</p>
            {{/if}}
          </div>
          {{#if @model.owner}}
            <div class='header-right'>
              <p class='eyebrow'>OWNER</p>
              <p class='owner'>{{@model.owner}}</p>
            </div>
          {{/if}}
        </header>

        <section class='stats-strip'>
          <div class='stat'>
            <span class='stat-value'>{{@model.totalBottles}}</span>
            <span class='stat-label'>Bottles</span>
          </div>
          <div class='stat'>
            <span class='stat-value'>≈ ${{@model.totalValue}}</span>
            <span class='stat-label'>Total Value</span>
          </div>
          <div class='stat'>
            <span class='stat-value'>{{@model.averageScore}}</span>
            <span class='stat-label'>Avg Score</span>
          </div>
          {{#if this.typeCounts.length}}
            <div class='stat type-breakdown'>
              <div class='type-pills'>
                {{#each this.typeCounts as |t|}}
                  <span
                    class='type-pill type-{{t.type}}'
                    style={{htmlSafeBg t.color}}
                  >
                    <span class='type-dot'></span>
                    {{t.count}}
                    <span class='type-name'>{{t.type}}</span>
                  </span>
                {{/each}}
              </div>
              <span class='stat-label'>By Type</span>
            </div>
          {{/if}}
        </section>

        {{#if this.rows.length}}
          <section class='timeline-section'>
            <div class='timeline-header'>
              <p class='timeline-title'>Drinking Window</p>
              <p class='timeline-today'>today ↓</p>
            </div>
            <div class='timeline'>
              <div
                class='today-line'
                style={{htmlSafeLeft this.todayPct}}
              ></div>
              {{#each this.rows as |row|}}
                <div class='timeline-row'>
                  <span class='row-name'>{{row.name}}</span>
                  <div class='row-track'>
                    <div
                      class='row-bar state-{{row.state}}'
                      style={{htmlSafePos row.startPct row.widthPct}}
                    >
                      <div
                        class='bar-fill'
                        style={{htmlSafeBg row.liquidColor}}
                      ></div>
                    </div>
                  </div>
                </div>
              {{/each}}
              <div class='axis'>
                {{#each this.yearTicks as |y|}}
                  <span class='tick'>{{y}}</span>
                {{/each}}
              </div>
            </div>
          </section>
        {{/if}}

        {{#if @fields.bottles.length}}
          <section class='bottles-section'>
            <p class='section-title'>Bottles in this Cellar</p>
            <div class='bottle-grid'>
              {{#each @fields.bottles as |Bottle|}}
                <Bottle @format='embedded' />
              {{/each}}
            </div>
          </section>
        {{/if}}

        {{#if @model.notes}}
          <section class='notes-section'>
            <p class='section-title'>Cellar Notes</p>
            <div class='notes-body'>
              <@fields.notes />
            </div>
          </section>
        {{/if}}
      </article>

      {{! template-lint-disable no-whitespace-for-layout }}
      <style scoped>
        .cellar-sheet {
          --cellar-bg: #1a0f0f;
          --cellar-bg-2: #2a1818;
          --cellar-cream: #f5efd8;
          --cellar-cream-dim: #c9b88a;
          --cellar-gold: #c9a96a;
          --cellar-burgundy: #5a1a1f;
          --cellar-rule: rgba(201, 169, 106, 0.25);
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
          container-name: cellar-card;
        }

        .cellar-header {
          display: flex;
          justify-content: space-between;
          align-items: flex-start;
          gap: var(--boxel-sp);
          padding-bottom: var(--boxel-sp);
          border-bottom: 1px solid var(--cellar-rule);
        }
        .header-right {
          text-align: right;
        }
        .eyebrow {
          margin: 0;
          color: var(--cellar-gold);
          letter-spacing: 0.3em;
          font-size: 0.7rem;
          text-transform: uppercase;
          font-family: system-ui, sans-serif;
        }
        .cellar-name {
          margin: 0.25rem 0 0;
          font-size: 2rem;
          font-weight: 600;
          color: var(--cellar-cream);
          line-height: 1.1;
          letter-spacing: 0.02em;
        }
        .location {
          margin: 0.25rem 0 0;
          font-style: italic;
          color: var(--cellar-cream-dim);
          font-size: 0.95rem;
        }
        .owner {
          margin: 0.25rem 0 0;
          color: var(--cellar-cream);
          font-size: 1.1rem;
        }

        .stats-strip {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(8rem, 1fr));
          gap: var(--boxel-sp-lg);
          padding: var(--boxel-sp) 0;
          border-bottom: 1px solid var(--cellar-rule);
        }
        @container cellar-card (inline-size <= 600px) {
          .stats-strip {
            grid-template-columns: 1fr 1fr;
          }
        }
        .stat {
          display: flex;
          flex-direction: column;
          gap: 0.25rem;
        }
        .stat-value {
          font-size: 1.75rem;
          font-weight: 700;
          color: var(--cellar-gold);
          line-height: 1;
        }
        .stat-label {
          font-family: system-ui, sans-serif;
          letter-spacing: 0.2em;
          font-size: 0.65rem;
          text-transform: uppercase;
          color: var(--cellar-cream-dim);
        }
        .type-breakdown {
          gap: 0.5rem;
        }
        .type-pills {
          display: flex;
          flex-wrap: wrap;
          gap: 0.4rem;
        }
        .type-pill {
          display: inline-flex;
          align-items: center;
          gap: 0.3rem;
          padding: 0.15rem 0.5rem 0.15rem 0.4rem;
          border-radius: 999px;
          font-family: system-ui, sans-serif;
          font-size: 0.8rem;
          color: var(--cellar-cream);
          background: rgba(0, 0, 0, 0.35);
          border: 1px solid var(--cellar-rule);
        }
        .type-dot {
          width: 0.55rem;
          height: 0.55rem;
          border-radius: 50%;
          background-color: var(--bg, transparent);
          box-shadow: inset 0 0 0 1px rgba(0, 0, 0, 0.3);
        }
        .type-name {
          color: var(--cellar-cream-dim);
          font-size: 0.7rem;
          text-transform: uppercase;
          letter-spacing: 0.1em;
        }

        .timeline-section {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-sm);
          padding-bottom: var(--boxel-sp);
          border-bottom: 1px solid var(--cellar-rule);
        }
        .timeline-header {
          display: flex;
          justify-content: space-between;
          align-items: baseline;
          margin: 0;
        }
        .timeline-title {
          margin: 0;
          font-family: system-ui, sans-serif;
          letter-spacing: 0.25em;
          font-size: 0.7rem;
          color: var(--cellar-gold);
          text-transform: uppercase;
        }
        .timeline-today {
          margin: 0;
          font-family: system-ui, sans-serif;
          font-size: 0.7rem;
          color: var(--cellar-gold);
          letter-spacing: 0.1em;
        }
        .timeline {
          position: relative;
          display: grid;
          grid-template-columns: minmax(8rem, 12rem) 1fr;
          row-gap: 0.4rem;
          padding: 0.5rem 0 1.5rem;
        }
        .today-line {
          position: absolute;
          top: 0;
          bottom: 1.5rem;
          width: 1px;
          background: var(--cellar-gold);
          opacity: 0.7;
          transform: translateX(-0.5px);
          pointer-events: none;
          margin-left: clamp(8rem, 30%, 12rem);
        }
        .timeline-row {
          display: contents;
        }
        .row-name {
          font-size: 0.85rem;
          color: var(--cellar-cream);
          padding-right: var(--boxel-sp);
          align-self: center;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .row-track {
          position: relative;
          height: 1.25rem;
          background: rgba(245, 239, 216, 0.04);
          border-radius: 2px;
          align-self: center;
        }
        .row-bar {
          position: absolute;
          top: 0;
          bottom: 0;
          border-radius: 2px;
          overflow: hidden;
          box-shadow: 0 0 0 1px rgba(0, 0, 0, 0.4);
        }
        .bar-fill {
          width: 100%;
          height: 100%;
          background-color: var(--bg, var(--cellar-burgundy));
          opacity: 0.85;
        }
        .state-before-window .bar-fill {
          opacity: 0.5;
        }
        .state-past-window .bar-fill {
          opacity: 0.3;
        }

        .axis {
          grid-column: 2;
          position: relative;
          margin-top: 0.5rem;
          height: 1rem;
          font-family: system-ui, sans-serif;
          font-size: 0.7rem;
          color: var(--cellar-cream-dim);
        }
        .tick {
          position: absolute;
          transform: translateX(-50%);
        }
        .axis .tick:nth-child(1) {
          left: 0;
          transform: none;
        }
        .axis .tick:last-child {
          right: 0;
          left: auto;
          transform: none;
        }
        .axis .tick:nth-child(2) {
          left: 25%;
        }
        .axis .tick:nth-child(3) {
          left: 50%;
        }
        .axis .tick:nth-child(4) {
          left: 75%;
        }

        .section-title {
          margin: 0 0 var(--boxel-sp-sm);
          font-family: system-ui, sans-serif;
          letter-spacing: 0.25em;
          font-size: 0.7rem;
          color: var(--cellar-gold);
          text-transform: uppercase;
        }

        .bottle-grid {
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(18rem, 1fr));
          gap: var(--boxel-sp);
        }

        .notes-section {
          padding-top: var(--boxel-sp);
          border-top: 1px solid var(--cellar-rule);
        }
        .notes-body {
          color: var(--cellar-cream-dim);
          font-size: 0.95rem;
          line-height: 1.5;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof WineCellar> {
    get topSwatches(): string[] {
      const bottles = (this.args.model.bottles ?? []).filter(
        Boolean,
      ) as WineBottle[];
      return bottles.slice(0, 5).map((b) => b.liquidColor ?? '#7a1e2a');
    }

    <template>
      <article class='cellar-card-embedded'>
        <header>
          <span class='eyebrow'>CELLAR</span>
          <h3 class='name'>{{if @model.name @model.name 'Untitled Cellar'}}</h3>
          {{#if @model.location}}
            <p class='location'>{{@model.location}}</p>
          {{/if}}
        </header>
        <div class='stats-row'>
          <div class='stat'>
            <span class='value'>{{@model.totalBottles}}</span>
            <span class='label'>bottles</span>
          </div>
          <div class='stat'>
            <span class='value'>≈ ${{@model.totalValue}}</span>
            <span class='label'>value</span>
          </div>
          <div class='stat'>
            <span class='value'>{{@model.averageScore}}</span>
            <span class='label'>avg score</span>
          </div>
        </div>
        {{#if this.topSwatches.length}}
          <div class='swatch-row'>
            {{#each this.topSwatches as |c|}}
              <span class='swatch' style={{htmlSafeBg c}}></span>
            {{/each}}
          </div>
        {{/if}}
      </article>

      <style scoped>
        .cellar-card-embedded {
          padding: var(--boxel-sp);
          border-radius: var(--boxel-border-radius);
          background: radial-gradient(ellipse at top, #2a1818 0%, #1a0f0f 70%);
          color: #f5efd8;
          font-family: 'Georgia', serif;
          border: 1px solid rgba(201, 169, 106, 0.3);
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-sm);
        }
        .eyebrow {
          font-family: system-ui, sans-serif;
          letter-spacing: 0.3em;
          font-size: 0.65rem;
          color: #c9a96a;
          text-transform: uppercase;
        }
        .name {
          margin: 0.15rem 0 0;
          font-size: 1.25rem;
          font-weight: 600;
          color: #f5efd8;
          line-height: 1.1;
        }
        .location {
          margin: 0.15rem 0 0;
          font-style: italic;
          color: #c9b88a;
          font-size: 0.85rem;
        }
        .stats-row {
          display: flex;
          gap: var(--boxel-sp);
          padding-top: var(--boxel-sp-xs);
          border-top: 1px solid rgba(201, 169, 106, 0.2);
        }
        .stat {
          display: flex;
          flex-direction: column;
          gap: 0.1rem;
        }
        .value {
          font-size: 1rem;
          font-weight: 700;
          color: #c9a96a;
        }
        .label {
          font-family: system-ui, sans-serif;
          font-size: 0.6rem;
          letter-spacing: 0.15em;
          text-transform: uppercase;
          color: #c9b88a;
        }
        .swatch-row {
          display: flex;
          gap: 0.3rem;
        }
        .swatch {
          width: 0.85rem;
          height: 0.85rem;
          border-radius: 50%;
          background-color: var(--bg, transparent);
          box-shadow:
            0 0 0 1px rgba(0, 0, 0, 0.4),
            inset 0 0 0 1px rgba(255, 255, 255, 0.1);
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof WineCellar> {
    <template>
      <article class='fitted-cellar'>
        <span class='eyebrow'>CELLAR</span>
        <h3 class='name'>{{if @model.name @model.name 'Untitled Cellar'}}</h3>
        <div class='stat-line'>
          <span class='big'>{{@model.totalBottles}}</span>
          <span class='small'>bottles</span>
        </div>
        {{#if @model.location}}
          <p class='location'>{{@model.location}}</p>
        {{/if}}
      </article>

      <style scoped>
        .fitted-cellar {
          width: 100%;
          height: 100%;
          padding: var(--boxel-sp);
          background: radial-gradient(ellipse at top, #2a1818 0%, #1a0f0f 70%);
          color: #f5efd8;
          font-family: 'Georgia', serif;
          display: flex;
          flex-direction: column;
          justify-content: space-between;
          gap: var(--boxel-sp-xs);
          overflow: hidden;
        }
        .eyebrow {
          font-family: system-ui, sans-serif;
          letter-spacing: 0.25em;
          font-size: clamp(0.55rem, 2.5cqi, 0.7rem);
          color: #c9a96a;
          text-transform: uppercase;
        }
        .name {
          margin: 0.2rem 0 0;
          font-size: clamp(0.9rem, 5cqi, 1.4rem);
          font-weight: 600;
          color: #f5efd8;
          line-height: 1.05;
          overflow: hidden;
          text-overflow: ellipsis;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
        }
        .stat-line {
          display: flex;
          align-items: baseline;
          gap: 0.4rem;
        }
        .big {
          font-size: clamp(1.4rem, 8cqi, 2.5rem);
          font-weight: 700;
          color: #c9a96a;
          line-height: 1;
        }
        .small {
          font-family: system-ui, sans-serif;
          font-size: clamp(0.6rem, 2.5cqi, 0.8rem);
          letter-spacing: 0.15em;
          text-transform: uppercase;
          color: #c9b88a;
        }
        .location {
          margin: 0;
          font-style: italic;
          color: #c9b88a;
          font-size: clamp(0.6rem, 2.5cqi, 0.8rem);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof WineCellar> {
    <template>
      <span class='cellar-atom'>
        <GlassFullIcon class='icon' width='14' height='14' />
        <span class='name'>{{if @model.name @model.name 'Cellar'}}</span>
        <span class='count'>· {{@model.totalBottles}} bottles</span>
      </span>

      <style scoped>
        .cellar-atom {
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
        .icon {
          color: #5a1a1f;
          flex-shrink: 0;
        }
        .name {
          font-weight: 500;
        }
        .count {
          color: var(--muted-foreground);
          font-family: system-ui, sans-serif;
          font-size: 0.85rem;
        }
      </style>
    </template>
  };
}
