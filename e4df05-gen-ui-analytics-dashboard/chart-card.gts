import {
  CardDef,
  Component,
  field,
  contains,
  linksTo,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import GlimmerComponent from '@glimmer/component';
import { eq } from '@cardstack/boxel-ui/helpers';
import type { CardContext } from '@cardstack/base/card-api';
import ChartBarIcon from '@cardstack/boxel-icons/chart-bar';

import ChartRender from './components/chart-render';
import OptionPicker from './components/option-picker';
import { Dataset, parseRows } from './dataset';
import { DimensionField, MeasureField } from './fields';
import {
  CHART_KINDS,
  validateChartSpec,
  aggregate,
  describeSpec,
  type AggregatedData,
  type ChartSpec,
} from './utils/chart-spec';

// ---------------------------------------------------------------------------
// A chart as a first-class card. The AI creates one of these and links it to
// a dashboard; the same card also stands alone (isolated) or embeds anywhere.
// Constrained values are enum fields (pickers in edit), the data source is a
// linked Dataset card, and dimension/measure are compound (./fields).
// ---------------------------------------------------------------------------

class ChartKindField extends StringField {
  static displayName = 'Chart Kind';
  static edit = class Edit extends Component<typeof ChartKindField> {
    <template>
      <OptionPicker
        @label='Chart kind'
        @options={{CHART_KINDS}}
        @value={{@model}}
        @set={{@set}}
      />
    </template>
  };
}

function formatKpi(total: number): string {
  return Intl.NumberFormat('en-US', {
    maximumFractionDigits: 1,
    notation: total >= 10000 ? 'compact' : 'standard',
  }).format(total);
}

function buildSpec(model: any): ChartSpec | { errors: string[] } {
  let raw: any = {
    chartKind: model?.chartKind,
    source: {
      datasetId: model?.dataset?.id || undefined,
    },
    x: model?.dimension?.path || undefined,
    xBucket: model?.dimension?.bucket || 'none',
    y: model?.measure?.aggregate
      ? {
          field: model?.measure?.path || undefined,
          aggregate: model?.measure?.aggregate,
        }
      : undefined,
    series: model?.seriesBy || undefined,
    title: model?.title || undefined,
  };
  let { spec, errors } = validateChartSpec(raw);
  return spec ?? { errors };
}

interface ChartViewSignature {
  Args: {
    model: any;
    context?: CardContext;
    tall?: boolean;
  };
  Element: HTMLElement;
}

export class ChartView extends GlimmerComponent<ChartViewSignature> {
  get built(): { spec?: ChartSpec; errors?: string[] } {
    let result = buildSpec(this.args.model);
    return 'errors' in result ? { errors: result.errors } : { spec: result };
  }

  get rows(): any[] {
    // the linked Dataset model is already hydrated — read it directly
    return parseRows(this.args.model?.dataset?.rowsJson);
  }

  get data(): AggregatedData | undefined {
    let spec = this.built.spec;
    if (!spec || spec.chartKind === 'kpi' || !this.rows.length) {
      return undefined;
    }
    return aggregate(this.rows, spec);
  }

  get kpiValue(): string | undefined {
    let spec = this.built.spec;
    // an empty dataset has no answer yet: fall through to the empty state
    // rather than printing a total of 0 as if it were real
    if (spec?.chartKind !== 'kpi' || !this.rows.length) {
      return undefined;
    }
    return formatKpi(aggregate(this.rows, spec).total);
  }

  get mapping(): string | undefined {
    return this.built.spec ? describeSpec(this.built.spec) : undefined;
  }

  <template>
    <div class='chart-view {{if @tall "tall"}}' ...attributes>
      {{#if this.built.errors.length}}
        <div class='chart-problem' role='alert'>
          <strong>This chart's spec needs a fix</strong>
          <ul>
            {{#each this.built.errors as |error|}}
              <li>{{error}}</li>
            {{/each}}
          </ul>
        </div>
      {{else if this.kpiValue}}
        <div class='kpi'>
          <data
            class='kpi-value'
            value={{this.kpiValue}}
          >{{this.kpiValue}}</data>
          <span class='chart-mapping'>{{this.mapping}}</span>
        </div>
      {{else if this.rows.length}}
        <ChartRender @spec={{this.built.spec}} @data={{this.data}} />
        <div class='chart-mapping'>{{this.mapping}}</div>
      {{else}}
        <p class='chart-empty'>This chart's dataset has no rows yet.</p>
      {{/if}}
    </div>
    <style scoped>
      .chart-view {
        display: flex;
        flex-direction: column;
        height: 100%;
        min-height: 13.75rem;
        padding: var(--boxel-sp-5xs) 0;
      }
      .chart-view.tall {
        min-height: 26.25rem;
      }
      .chart-view > :first-child {
        flex: 1;
      }
      .chart-mapping {
        font-size: var(--boxel-font-size-2xs);
        letter-spacing: 0.04em;
        color: var(--muted-foreground);
        padding-top: var(--boxel-sp-2xs);
        text-transform: uppercase;
      }
      .kpi {
        display: flex;
        flex-direction: column;
        align-items: flex-start;
        justify-content: center;
        height: 100%;
        gap: var(--boxel-sp-2xs);
      }
      .kpi-value {
        font-size: 3rem;
        font-weight: 650;
        line-height: 1;
        font-variant-numeric: tabular-nums;
      }
      .chart-problem {
        font-size: var(--boxel-font-size-sm);
        color: var(--destructive-ink);
      }
      .chart-problem ul {
        margin: var(--boxel-sp-2xs) 0 0;
        padding-left: var(--boxel-sp-lg);
        color: var(--foreground);
      }
      .chart-empty {
        display: flex;
        align-items: center;
        justify-content: center;
        height: 100%;
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground);
      }
    </style>
  </template>
}

export class ChartCard extends CardDef {
  static displayName = 'Chart';
  static icon = ChartBarIcon;

  @field title = contains(StringField);
  @field chartKind = contains(ChartKindField);
  // the data behind the chart: every chart reads one Dataset card
  @field dataset = linksTo(Dataset);
  @field dimension = contains(DimensionField);
  @field measure = contains(MeasureField);
  // optional second dimension that splits the measure into series
  @field seriesBy = contains(StringField);
  // dashboard layout hints: grid columns 1..3, grid rows 1..2
  @field span = contains(NumberField);
  @field rowSpan = contains(NumberField);

  static isolated = class Isolated extends Component<typeof ChartCard> {
    <template>
      <article class='chart-card-isolated'>
        <h1>{{if @model.title @model.title 'Untitled Chart'}}</h1>
        <ChartView @model={{@model}} @context={{@context}} @tall={{true}} />
      </article>
      <style scoped>
        .chart-card-isolated {
          height: 100%;
          display: flex;
          flex-direction: column;
          padding: clamp(1rem, 3cqi, 2rem);
          container-type: inline-size;
        }
        .chart-card-isolated h1 {
          margin: 0 0 var(--boxel-sp);
        }
        .chart-card-isolated > :last-child {
          flex: 1;
          min-height: 0;
        }
      </style>
    </template>
  };

  // "Night Wall" fitted: the chart's own kind drawn as a glyph — and a KPI
  // chart shows its real aggregated value
  static fitted = class Fitted extends Component<typeof ChartCard> {
    get spec(): ChartSpec | undefined {
      let result = buildSpec(this.args.model);
      return 'errors' in result ? undefined : result;
    }
    get glyph(): 'kpi' | 'line' | 'ring' | 'bars' {
      let kind = this.args.model?.chartKind;
      if (kind === 'kpi') {
        return 'kpi';
      }
      if (kind === 'line' || kind === 'scatter') {
        return 'line';
      }
      if (kind === 'pie' || kind === 'donut') {
        return 'ring';
      }
      return 'bars';
    }
    get kpiValue(): string | undefined {
      let spec = this.spec;
      if (spec?.chartKind !== 'kpi') {
        return undefined;
      }
      let rows = parseRows(this.args.model?.dataset?.rowsJson);
      if (!rows.length) {
        return undefined;
      }
      return formatKpi(aggregate(rows, spec).total);
    }
    get mapping(): string | undefined {
      return this.spec ? describeSpec(this.spec) : undefined;
    }
    <template>
      <article class='fit'>
        <div class='r-head'>
          <p class='eyebrow'>{{if
              @model.chartKind
              @model.chartKind
              'chart'
            }}</p>
          <h3 class='title'>{{if
              @model.title
              @model.title
              'Untitled Chart'
            }}</h3>
        </div>
        <div class='r-glyph'>
          {{#if (eq this.glyph 'kpi')}}
            <span class='kpi'>{{if this.kpiValue this.kpiValue '—'}}</span>
          {{else if (eq this.glyph 'line')}}
            <svg
              viewBox='0 0 100 44'
              preserveAspectRatio='none'
              aria-hidden='true'
            >
              <polyline
                points='4,38 24,26 46,30 68,16 96,6'
                fill='none'
                stroke-width='3'
                stroke-linecap='round'
                stroke-linejoin='round'
                vector-effect='non-scaling-stroke'
              />
            </svg>
          {{else if (eq this.glyph 'ring')}}
            <div class='ring'></div>
          {{else}}
            <div class='bars'>
              <i class='b1'></i><i class='b2'></i><i class='b3'></i><i
                class='b4'
              ></i><i class='b5'></i>
            </div>
          {{/if}}
        </div>
        <div class='r-meta'>
          <span class='mapping'>{{if
              this.mapping
              this.mapping
              @model.dataset.title
            }}</span>
        </div>
      </article>
      <style scoped>
        .fit {
          --ar: calc(max(1cqi, 1cqb) - min(1cqi, 1cqb));
          --type-ratio: 1.25;
          --type-base: clamp(
            0.625rem,
            calc(0.1875rem + 2.2cqi + 1cqb - 0.6 * var(--ar)),
            1.125rem
          );
          --fit-meta-size: max(
            0.4375rem,
            calc(var(--type-base) / var(--type-ratio))
          );
          --fit-eyebrow-size: max(
            0.4375rem,
            calc(var(--type-base) / pow(var(--type-ratio), 2))
          );
          --fit-headline-size: max(
            0.6875rem,
            calc(var(--type-base) * pow(var(--type-ratio), 1.5))
          );
          --fit-kpi-size: max(
            0.9375rem,
            calc(var(--type-base) * pow(var(--type-ratio), 3.5))
          );
          --fit-pad: clamp(0.375rem, calc(0.125rem + 2cqi), 1rem);
          --fit-gap: clamp(0.1875rem, calc(0.0625rem + 1.2cqi), 0.625rem);

          width: 100%;
          height: 100%;
          display: grid;
          grid-template-rows: auto minmax(0, 1fr) auto;
          grid-template-areas: 'head' 'glyph' 'meta';
          gap: var(--fit-gap);
          padding: var(--fit-pad);
        }
        .r-head,
        .r-glyph,
        .r-meta {
          overflow: hidden;
          min-height: 0;
        }
        .eyebrow {
          margin: 0;
          font-size: var(--fit-eyebrow-size);
          font-weight: 700;
          letter-spacing: 0.2em;
          text-transform: uppercase;
          color: var(--primary-ink);
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .title {
          margin: var(--boxel-sp-6xs) 0 0;
          font-size: var(--fit-headline-size);
          font-weight: 700;
          letter-spacing: -0.015em;
          line-height: 1.15;
          display: -webkit-box;
          -webkit-box-orient: vertical;
          -webkit-line-clamp: 2;
          overflow: hidden;
        }
        .r-glyph {
          display: flex;
          align-items: flex-end;
        }
        .r-glyph polyline {
          stroke: var(--chart-1);
        }
        .r-glyph svg {
          width: 100%;
          height: 100%;
          max-height: 100%;
        }
        .kpi {
          font-size: var(--fit-kpi-size);
          font-weight: 300;
          line-height: 1;
          letter-spacing: -0.03em;
          font-variant-numeric: tabular-nums;
          align-self: center;
        }
        .bars {
          display: flex;
          align-items: flex-end;
          gap: var(--boxel-sp-4xs);
          width: 100%;
          height: 100%;
        }
        .bars i {
          flex: 1;
          border-radius: var(--boxel-border-radius-2xs)
            var(--boxel-border-radius-2xs) 0 0;
          background-color: var(--chart-1);
        }
        .bars .b1 {
          height: 82%;
        }
        .bars .b2 {
          height: 54%;
          background-color: var(--chart-2);
        }
        .bars .b3 {
          height: 30%;
        }
        .bars .b4 {
          height: 66%;
          background-color: var(--chart-3);
        }
        .bars .b5 {
          height: 44%;
        }
        .ring {
          width: min(72cqb, 60cqi);
          aspect-ratio: 1;
          border-radius: 50%;
          align-self: center;
          margin: 0 auto;
          background: conic-gradient(
            var(--chart-1) 0 62%,
            var(--chart-2) 62% 82%,
            var(--chart-3) 82% 100%
          );
          /* a mask reads only alpha; black is the opaque stop, not a colour */
          -webkit-mask: radial-gradient(
            circle,
            transparent 0 38%,
            black 39% 100%
          );
          mask: radial-gradient(circle, transparent 0 38%, black 39% 100%);
        }
        .r-meta {
          font-size: var(--fit-meta-size);
          letter-spacing: 0.04em;
          text-transform: uppercase;
          color: var(--muted-foreground);
          white-space: nowrap;
          text-overflow: ellipsis;
        }

        /* h40: title only */
        @container fitted-card (height <= 50px) {
          .fit {
            grid-template-rows: 1fr;
            grid-template-areas: 'head';
            gap: 0;
          }
          .r-glyph,
          .r-meta {
            display: none;
          }
          .r-head {
            display: flex;
            align-items: center;
          }
          .eyebrow {
            display: none;
          }
          .title {
            margin: 0;
            -webkit-line-clamp: 1;
          }
        }
        /* h65: head + meta */
        @container fitted-card (50px < height <= 80px) {
          .fit {
            grid-template-rows: minmax(0, 1fr) auto;
            grid-template-areas: 'head' 'meta';
          }
          .r-glyph {
            display: none;
          }
          .title {
            -webkit-line-clamp: 1;
          }
        }
        /* h105: keep the glyph thin, single-line title */
        @container fitted-card (80px < height <= 130px) {
          .title {
            -webkit-line-clamp: 1;
          }
        }
        /* wide + short: glyph moves to a right-hand sidebar */
        @container fitted-card (width > 260px) and (50px < height <= 130px) {
          .fit {
            grid-template-columns: minmax(0, 1fr) minmax(3.5rem, 22cqw);
            grid-template-rows: minmax(0, 1fr) auto;
            grid-template-areas: 'head glyph' 'meta glyph';
            column-gap: calc(var(--fit-gap) * 1.5);
          }
          .r-glyph {
            display: flex;
          }
        }
        @container fitted-card (width <= 150px) {
          .r-meta {
            display: none;
          }
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof ChartCard> {
    <template>
      <div class='chart-card-embedded'>
        <h3>{{if @model.title @model.title 'Untitled Chart'}}</h3>
        <ChartView @model={{@model}} @context={{@context}} />
      </div>
      <style scoped>
        .chart-card-embedded {
          height: 100%;
          display: flex;
          flex-direction: column;
          padding: var(--boxel-sp-sm) var(--boxel-sp);
        }
        .chart-card-embedded h3 {
          margin: 0 0 var(--boxel-sp-xs);
          font-weight: 600;
        }
        .chart-card-embedded > :last-child {
          flex: 1;
          min-height: 0;
        }
      </style>
    </template>
  };
}
