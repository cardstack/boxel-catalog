import {
  CardDef,
  FieldDef,
  Component,
  field,
  contains,
  linksTo,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import GlimmerComponent from '@glimmer/component';
import type { TemplateOnlyComponent } from '@ember/component/template-only';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import type { CardContext } from '@cardstack/base/card-api';
import ChartBarIcon from '@cardstack/boxel-icons/chart-bar';

import ChartRender from './components/chart-render';
import { Dataset, parseRows } from './dataset';
import {
  CHART_KINDS,
  BUCKETS,
  AGGREGATES,
  validateChartSpec,
  aggregate,
  compileToECharts,
  describeSpec,
  type ChartSpec,
} from './utils/chart-spec';

// ---------------------------------------------------------------------------
// A chart as a first-class card. The AI creates one of these and links it to
// a dashboard; the same card also stands alone (isolated) or embeds anywhere.
// Constrained values are enum fields (pickers in edit), the data source is a
// linked Dataset card, and dimension/measure are compound.
// ---------------------------------------------------------------------------

interface OptionPickerSignature {
  Args: {
    options: readonly string[];
    value: string | undefined | null;
    set: (value: string) => void;
  };
  Element: HTMLElement;
}

// shared edit UI for the enum fields: a row of pill buttons
const OptionPicker: TemplateOnlyComponent<OptionPickerSignature> = <template>
  <div class='option-picker' ...attributes>
    {{#each @options as |option|}}
      <button
        type='button'
        class='option {{if (eq @value option) "selected"}}'
        {{on 'click' (fn @set option)}}
        data-test-option={{option}}
      >
        {{option}}
      </button>
    {{/each}}
  </div>
  <style scoped>
    .option-picker {
      display: flex;
      flex-wrap: wrap;
      gap: var(--boxel-sp-xxs, 6px);
    }
    .option {
      border: 1px solid var(--boxel-200, #ccc);
      border-radius: 999px;
      background: transparent;
      font: inherit;
      font-size: 0.8125rem;
      padding: 4px 12px;
      cursor: pointer;
    }
    .option:hover {
      border-color: var(--boxel-highlight, #00ffba);
    }
    .option.selected {
      border-color: var(--boxel-highlight, #00ffba);
      box-shadow: 0 0 0 1px var(--boxel-highlight, #00ffba);
      font-weight: 600;
    }
  </style>
</template>;

export class ChartKindField extends StringField {
  static displayName = 'Chart Kind';
  static edit = class Edit extends Component<typeof ChartKindField> {
    <template>
      <OptionPicker @options={{CHART_KINDS}} @value={{@model}} @set={{@set}} />
    </template>
  };
}

export class BucketField extends StringField {
  static displayName = 'Time Bucket';
  static edit = class Edit extends Component<typeof BucketField> {
    <template>
      <OptionPicker @options={{BUCKETS}} @value={{@model}} @set={{@set}} />
    </template>
  };
}

export class AggregateField extends StringField {
  static displayName = 'Aggregate';
  static edit = class Edit extends Component<typeof AggregateField> {
    <template>
      <OptionPicker @options={{AGGREGATES}} @value={{@model}} @set={{@set}} />
    </template>
  };
}

// the x axis: which field, and how dates bucket
export class DimensionField extends FieldDef {
  static displayName = 'Dimension';
  @field path = contains(StringField);
  @field bucket = contains(BucketField);
}

// the y axis: which numeric field, and how values combine
export class MeasureField extends FieldDef {
  static displayName = 'Measure';
  @field path = contains(StringField);
  @field aggregate = contains(AggregateField);
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

  get option(): Record<string, any> | undefined {
    let spec = this.built.spec;
    if (!spec || spec.chartKind === 'kpi' || !this.rows.length) {
      return undefined;
    }
    return compileToECharts(spec, aggregate(this.rows, spec));
  }

  get kpiValue(): string | undefined {
    let spec = this.built.spec;
    if (spec?.chartKind !== 'kpi') {
      return undefined;
    }
    let { total } = aggregate(this.rows, spec);
    return Intl.NumberFormat('en-US', {
      maximumFractionDigits: 1,
      notation: total >= 10000 ? 'compact' : 'standard',
    }).format(total);
  }

  get mapping(): string | undefined {
    return this.built.spec ? describeSpec(this.built.spec) : undefined;
  }

  <template>
    <div class='chart-view {{if @tall "tall"}}' ...attributes>
      {{#if this.built.errors.length}}
        <div class='chart-problem'>
          <strong>This chart's spec needs a fix</strong>
          <ul>
            {{#each this.built.errors as |error|}}
              <li>{{error}}</li>
            {{/each}}
          </ul>
        </div>
      {{else if this.kpiValue}}
        <div class='kpi'>
          <span class='kpi-value'>{{this.kpiValue}}</span>
          <span class='chart-mapping'>{{this.mapping}}</span>
        </div>
      {{else if this.rows.length}}
        <ChartRender @option={{this.option}} />
        <div class='chart-mapping'>{{this.mapping}}</div>
      {{else}}
        <div class='chart-empty'>This chart's dataset has no rows yet.</div>
      {{/if}}
    </div>
    <style scoped>
      .chart-view {
        display: flex;
        flex-direction: column;
        height: 100%;
        min-height: 220px;
        padding: 4px 0;
      }
      .chart-view.tall {
        min-height: 420px;
      }
      .chart-view > :first-child {
        flex: 1;
      }
      .chart-mapping {
        font-size: 0.6875rem;
        letter-spacing: 0.04em;
        opacity: 0.55;
        padding-top: 6px;
        text-transform: uppercase;
      }
      .kpi {
        display: flex;
        flex-direction: column;
        align-items: flex-start;
        justify-content: center;
        height: 100%;
        gap: 6px;
      }
      .kpi-value {
        font-size: 3rem;
        font-weight: 650;
        line-height: 1;
        font-variant-numeric: tabular-nums;
      }
      .chart-problem {
        font-size: 0.8125rem;
        opacity: 0.8;
      }
      .chart-problem ul {
        margin: 6px 0 0;
        padding-left: 18px;
      }
      .chart-empty {
        display: flex;
        align-items: center;
        justify-content: center;
        height: 100%;
        font-size: 0.8125rem;
        opacity: 0.55;
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
    get hasLinkedTheme(): boolean {
      return Boolean(this.args.model?.cardInfo?.theme);
    }
    <template>
      <article
        class='chart-card-isolated
          {{unless this.hasLinkedTheme "gu-default-theme"}}'
      >
        <h1>{{if @model.title @model.title 'Untitled Chart'}}</h1>
        <ChartView @model={{@model}} @context={{@context}} @tall={{true}} />
      </article>
      <style scoped>
        /* the ai-image-generator pin pattern (boxel-theming-ui rule 4), minus
           its [data-theme='dark'] variant: Night Wall is a committed single
           dark identity with no scheme toggle, so a dark variant would be
           dead code — the linked-theme path handles dark via .dark blocks */
        .gu-default-theme {
          --background: #0f1217;
          --foreground: #e8ecf1;
          --card: #171c24;
          --card-foreground: #e8ecf1;
          --primary: #5b8ff9;
          --primary-foreground: #0f1217;
          --secondary: #7ed9a6;
          --secondary-foreground: #0f1217;
          --accent: #f2cf7e;
          --accent-foreground: #0f1217;
          --muted: #1c2330;
          --muted-foreground: #93a0b4;
          --destructive: #c25668;
          --destructive-foreground: #0f1217;
          --border: rgba(255, 255, 255, 0.09);
          --input: rgba(255, 255, 255, 0.09);
          --ring: #5b8ff9;
        }
        .chart-card-isolated {
          height: 100%;
          display: flex;
          flex-direction: column;
          padding: clamp(16px, 3cqi, 32px);
          background: var(--gen-ui-bg, var(--background, #0f1217));
          color: var(--gen-ui-ink, var(--foreground, #e8ecf1));
          container-type: inline-size;
        }
        .chart-card-isolated h1 {
          margin: 0 0 16px;
          font-size: 1.25rem;
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
    get hasLinkedTheme(): boolean {
      return Boolean(this.args.model?.cardInfo?.theme);
    }
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
      let { total } = aggregate(rows, spec);
      return Intl.NumberFormat('en-US', {
        maximumFractionDigits: 1,
        notation: total >= 10000 ? 'compact' : 'standard',
      }).format(total);
    }
    get mapping(): string | undefined {
      return this.spec ? describeSpec(this.spec) : undefined;
    }
    <template>
      <article class='fit {{unless this.hasLinkedTheme "gu-default-theme"}}'>
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
        .gu-default-theme {
          --background: #0f1217;
          --foreground: #e8ecf1;
          --card: #171c24;
          --card-foreground: #e8ecf1;
          --primary: #5b8ff9;
          --primary-foreground: #0f1217;
          --secondary: #7ed9a6;
          --secondary-foreground: #0f1217;
          --accent: #f2cf7e;
          --accent-foreground: #0f1217;
          --muted: #1c2330;
          --muted-foreground: #93a0b4;
          --destructive: #c25668;
          --destructive-foreground: #0f1217;
          --border: rgba(255, 255, 255, 0.09);
          --input: rgba(255, 255, 255, 0.09);
          --ring: #5b8ff9;
        }
        .fit {
          --gu-bg: var(--gen-ui-bg, var(--background, #0f1217));
          --gu-surface: var(--gen-ui-surface, var(--card, #171c24));
          --gu-border: var(
            --gen-ui-border,
            var(--border, rgba(255, 255, 255, 0.09))
          );
          --gu-text: var(--gen-ui-ink, var(--foreground, #e8ecf1));
          --gu-muted: var(--gen-ui-muted, var(--muted-foreground, #93a0b4));
          --gu-accent: var(--gen-ui-accent, var(--primary, #5b8ff9));
          --gu-green: var(--gen-ui-green, var(--secondary, #7ed9a6));
          --gu-amber: var(--gen-ui-amber, var(--accent, #f2cf7e));

          --ar: calc(max(1cqi, 1cqb) - min(1cqi, 1cqb));
          --type-ratio: 1.25;
          --type-base: clamp(
            10px,
            calc(3px + 2.2cqi + 1cqb - 0.6 * var(--ar)),
            18px
          );
          --fit-meta-size: max(7px, calc(var(--type-base) / var(--type-ratio)));
          --fit-eyebrow-size: max(
            7px,
            calc(var(--type-base) / pow(var(--type-ratio), 2))
          );
          --fit-headline-size: max(
            11px,
            calc(var(--type-base) * pow(var(--type-ratio), 1.5))
          );
          --fit-kpi-size: max(
            15px,
            calc(var(--type-base) * pow(var(--type-ratio), 3.5))
          );
          --fit-pad: clamp(6px, calc(2px + 2cqi), 16px);
          --fit-gap: clamp(3px, calc(1px + 1.2cqi), 10px);

          width: 100%;
          height: 100%;
          display: grid;
          grid-template-rows: auto minmax(0, 1fr) auto;
          grid-template-areas: 'head' 'glyph' 'meta';
          gap: var(--fit-gap);
          padding: var(--fit-pad);
          background: var(--gu-bg);
          color: var(--gu-text);
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
          color: var(--gu-accent);
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .title {
          margin: 2px 0 0;
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
          stroke: var(--gu-accent);
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
          gap: 4px;
          width: 100%;
          height: 100%;
        }
        .bars i {
          flex: 1;
          border-radius: 2px 2px 1px 1px;
          background: var(--gu-accent);
        }
        .bars .b1 {
          height: 82%;
        }
        .bars .b2 {
          height: 54%;
          background: var(--gu-green);
        }
        .bars .b3 {
          height: 30%;
        }
        .bars .b4 {
          height: 66%;
          background: var(--gu-amber);
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
            var(--gu-accent) 0 62%,
            var(--gu-green) 62% 82%,
            var(--gu-amber) 82% 100%
          );
          -webkit-mask: radial-gradient(
            circle,
            transparent 0 38%,
            #000 39% 100%
          );
          mask: radial-gradient(circle, transparent 0 38%, #000 39% 100%);
        }
        .r-meta {
          font-size: var(--fit-meta-size);
          letter-spacing: 0.04em;
          text-transform: uppercase;
          color: var(--gu-muted);
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
            grid-template-columns: minmax(0, 1fr) minmax(56px, 22cqw);
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
          padding: 12px 16px;
        }
        .chart-card-embedded h3 {
          margin: 0 0 10px;
          font-size: 0.9375rem;
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
