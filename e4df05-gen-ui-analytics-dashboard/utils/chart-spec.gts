// =============================================================================
// ChartSpec — the small declarative vocabulary the AI fills in.
//
// The AI never writes ECharts options directly: it picks one of a few
// chartKinds and names the dimension/measure, and compileToECharts() turns
// that plus the queried rows into a full ECharts option. Everything here is
// a pure function so live tests can hit the whole pipeline without a DOM.
// =============================================================================

export const CHART_KINDS = [
  'line',
  'bar',
  'stacked-bar',
  'pie',
  'donut',
  'scatter',
  'kpi',
] as const;
export type ChartKind = (typeof CHART_KINDS)[number];

export const BUCKETS = ['none', 'month', 'quarter', 'year'] as const;
export type Bucket = (typeof BUCKETS)[number];

export const AGGREGATES = ['sum', 'count', 'avg'] as const;
export type Aggregate = (typeof AGGREGATES)[number];

export interface ChartSource {
  // Either a CodeRef of the card type whose instances feed the chart...
  module?: string;
  name?: string;
  // ...or the id of a Dataset card whose rowsJson feeds it directly
  datasetId?: string;
}

export interface ChartSpec {
  chartKind: ChartKind;
  source: ChartSource;
  // dot-path into the instance for the x dimension, e.g. "closeDate" or
  // "status.label"
  x?: string;
  xBucket?: Bucket;
  y?: { field?: string; aggregate: Aggregate };
  // optional second dimension that splits the measure into series
  series?: string;
  title?: string;
}

export interface AggregatedData {
  categories: string[];
  series: { name: string; data: (number | null)[] }[];
  total: number;
}

export function validateChartSpec(raw: unknown): {
  spec?: ChartSpec;
  errors: string[];
} {
  let errors: string[] = [];
  let value: any = raw;
  if (typeof raw === 'string') {
    try {
      value = JSON.parse(raw);
    } catch (e) {
      return {
        errors: [`chartSpec is not valid JSON: ${(e as Error).message}`],
      };
    }
  }
  if (!value || typeof value !== 'object') {
    return { errors: ['chartSpec must be a JSON object'] };
  }
  if (!CHART_KINDS.includes(value.chartKind)) {
    errors.push(
      `chartKind must be one of ${CHART_KINDS.join(', ')} (got "${value.chartKind}")`,
    );
  }
  let hasTypeSource =
    typeof value.source?.module === 'string' &&
    typeof value.source?.name === 'string';
  let hasDatasetSource = typeof value.source?.datasetId === 'string';
  if (!hasTypeSource && !hasDatasetSource) {
    errors.push(
      'source must be { module, name } naming a card type, or { datasetId } pointing at a Dataset card',
    );
  }
  if (value.xBucket && !BUCKETS.includes(value.xBucket)) {
    errors.push(`xBucket must be one of ${BUCKETS.join(', ')}`);
  }
  if (value.y && !AGGREGATES.includes(value.y.aggregate)) {
    errors.push(`y.aggregate must be one of ${AGGREGATES.join(', ')}`);
  }
  if (value.chartKind !== 'kpi' && value.chartKind !== undefined && !value.x) {
    errors.push('x (dimension field path) is required for non-kpi charts');
  }
  if (value.y?.aggregate && value.y.aggregate !== 'count' && !value.y?.field) {
    errors.push('y.field is required when aggregate is sum or avg');
  }
  if (errors.length) {
    return { errors };
  }
  return { spec: value as ChartSpec, errors: [] };
}

// safe dot-path getter; never throws on missing links
export function getPath(obj: any, path: string): any {
  if (!obj || !path) {
    return undefined;
  }
  let current = obj;
  for (let part of path.split('.')) {
    if (current == null) {
      return undefined;
    }
    current = current[part];
  }
  return current;
}

// Date-only strings ("2025-01-01") are parsed by `new Date` as UTC midnight,
// while getFullYear()/getMonth() read LOCAL time — so for any viewer west of
// UTC every period-boundary date would bucket one period early. Read the Y/M/D
// out of the string and build a local date instead.
function toLocalDate(value: unknown): Date | undefined {
  if (value instanceof Date) {
    return value;
  }
  let text = String(value).trim();
  let ymd = /^(\d{4})-(\d{2})(?:-(\d{2}))?$/.exec(text);
  if (ymd) {
    return new Date(Number(ymd[1]), Number(ymd[2]) - 1, Number(ymd[3] ?? '1'));
  }
  // everything else (ISO date-times without an offset, "3/14/2025") is already
  // interpreted as local time
  let date = new Date(text);
  return isNaN(date.getTime()) ? undefined : date;
}

// "2024-04-30" + quarter -> "2024 Q2"
export function bucketDate(value: unknown, bucket: Bucket): string {
  if (bucket === 'none' || value == null) {
    return String(value ?? 'unknown');
  }
  let date = toLocalDate(value);
  if (!date) {
    return String(value);
  }
  let year = date.getFullYear();
  if (bucket === 'year') {
    return String(year);
  }
  if (bucket === 'quarter') {
    return `${year} Q${Math.floor(date.getMonth() / 3) + 1}`;
  }
  return `${year}-${String(date.getMonth() + 1).padStart(2, '0')}`;
}

function applyAggregate(values: number[], aggregate: Aggregate): number {
  if (aggregate === 'count') {
    return values.length;
  }
  let sum = values.reduce((a, b) => a + b, 0);
  return aggregate === 'avg' && values.length ? sum / values.length : sum;
}

export function aggregate(rows: any[], spec: ChartSpec): AggregatedData {
  let aggregateKind = spec.y?.aggregate ?? 'count';
  let measureOf = (row: any): number => {
    if (aggregateKind === 'count') {
      return 1;
    }
    let v = Number(getPath(row, spec.y?.field ?? ''));
    return isNaN(v) ? 0 : v;
  };

  if (spec.chartKind === 'kpi') {
    let values = rows.map(measureOf);
    let total = applyAggregate(
      aggregateKind === 'count' ? rows.map(() => 1) : values,
      aggregateKind,
    );
    return { categories: [], series: [], total };
  }

  let bucket = spec.xBucket ?? 'none';
  let categoryOf = (row: any) => bucketDate(getPath(row, spec.x!), bucket);
  let seriesOf = (row: any) =>
    spec.series ? String(getPath(row, spec.series) ?? 'other') : 'value';

  // category -> series -> number[]
  let table = new Map<string, Map<string, number[]>>();
  let seriesNames = new Set<string>();
  for (let row of rows) {
    let cat = categoryOf(row);
    let ser = seriesOf(row);
    seriesNames.add(ser);
    if (!table.has(cat)) {
      table.set(cat, new Map());
    }
    let bytSeries = table.get(cat)!;
    if (!bytSeries.has(ser)) {
      bytSeries.set(ser, []);
    }
    bytSeries.get(ser)!.push(measureOf(row));
  }

  // bucketDate emits lexicographically sortable labels ("2024", "2024 Q2",
  // "2024-03"), so bucketed axes can be sorted into chronological order. With
  // xBucket:'none' the labels are pre-aggregated by the source ("Q2 2025",
  // "Jan") and an alphabetical sort would run time backwards — keep the order
  // the rows arrived in.
  let categories = [...table.keys()];
  if (bucket !== 'none') {
    categories.sort();
  }
  let series = [...seriesNames].map((name) => ({
    name,
    data: categories.map((cat) => {
      let values = table.get(cat)?.get(name);
      return values ? applyAggregate(values, aggregateKind) : null;
    }),
  }));
  let total = rows.map(measureOf).reduce((a, b) => a + b, 0);
  return { categories, series, total };
}

// themeless default palette; the renderer may substitute theme tokens
export const DEFAULT_PALETTE = [
  '#5b8ff9',
  '#61ddaa',
  '#f6bd16',
  '#7262fd',
  '#78d3f8',
  '#f08bb4',
  '#65789b',
];

export function compileToECharts(
  spec: ChartSpec,
  agg: AggregatedData,
  palette: string[] = DEFAULT_PALETTE,
): Record<string, any> {
  let base: Record<string, any> = {
    color: palette,
    animationDuration: 400,
    tooltip: { trigger: spec.chartKind === 'pie' ? 'item' : 'axis' },
    textStyle: { fontFamily: 'inherit' },
  };

  if (spec.chartKind === 'pie' || spec.chartKind === 'donut') {
    // one slice per category, first series' data
    let data = agg.categories.map((cat, i) => ({
      name: cat,
      value: agg.series[0]?.data[i] ?? 0,
    }));
    return {
      ...base,
      legend: { bottom: 0, textStyle: { color: 'inherit' } },
      series: [
        {
          type: 'pie',
          radius: spec.chartKind === 'donut' ? ['45%', '72%'] : '72%',
          data,
          label: { color: 'inherit' },
        },
      ],
    };
  }

  if (spec.chartKind === 'scatter') {
    return {
      ...base,
      xAxis: { type: 'category', data: agg.categories },
      yAxis: { type: 'value' },
      series: agg.series.map((s) => ({
        name: s.name,
        type: 'scatter',
        data: s.data,
      })),
    };
  }

  // line / bar / stacked-bar
  let type = spec.chartKind === 'line' ? 'line' : 'bar';
  return {
    ...base,
    grid: { left: 48, right: 16, top: 32, bottom: 48 },
    legend:
      agg.series.length > 1
        ? { bottom: 0, textStyle: { color: 'inherit' } }
        : undefined,
    xAxis: { type: 'category', data: agg.categories },
    yAxis: { type: 'value' },
    series: agg.series.map((s) => ({
      name: s.name,
      type,
      stack: spec.chartKind === 'stacked-bar' ? 'total' : undefined,
      smooth: spec.chartKind === 'line',
      data: s.data,
    })),
  };
}

// one-line human summary shown on the panel so a wrong mapping is obvious
// and correctable ("make it a bar chart")
export function describeSpec(spec: ChartSpec): string {
  let sourceLabel = spec.source.datasetId ? 'dataset' : spec.source.name;
  if (spec.chartKind === 'kpi') {
    return `${sourceLabel} · ${spec.y?.aggregate ?? 'count'}(${
      spec.y?.field ?? '*'
    })`;
  }
  let measure = `${spec.y?.aggregate ?? 'count'}(${spec.y?.field ?? '*'})`;
  let dim = spec.xBucket && spec.xBucket !== 'none' ? spec.xBucket : spec.x;
  return `${sourceLabel} · ${measure} by ${dim}${
    spec.series ? ` split by ${spec.series}` : ''
  }`;
}
