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

// The colours and font a chart paints with. ECharts draws to a canvas, so it
// cannot read CSS custom properties itself: the renderer resolves the theme's
// tokens (--chart-1..7, --foreground, --muted-foreground, --border, the body
// font) off the chart element and hands them in here. Without a theme the
// option leaves colours unset and ECharts falls back to its own defaults.
export interface ChartTheme {
  palette: string[];
  ink: string;
  muted: string;
  border: string;
  fontFamily: string;
}

function isRound(kind: ChartKind) {
  return kind === 'pie' || kind === 'donut';
}

export function compileToECharts(
  spec: ChartSpec,
  agg: AggregatedData,
  theme?: ChartTheme,
): Record<string, any> {
  let text = theme
    ? { color: theme.ink, fontFamily: theme.fontFamily }
    : undefined;
  let mutedText = theme
    ? { color: theme.muted, fontFamily: theme.fontFamily }
    : undefined;
  let axisLine = theme ? { lineStyle: { color: theme.border } } : undefined;
  let splitLine = theme ? { lineStyle: { color: theme.border } } : undefined;
  let base: Record<string, any> = {
    ...(theme ? { color: theme.palette, textStyle: text } : {}),
    animationDuration: 400,
    // pie and donut are both drawn as `type: 'pie'` with no cartesian axis, so
    // an axis trigger would never fire on their slices
    tooltip: { trigger: isRound(spec.chartKind) ? 'item' : 'axis' },
  };
  let categoryAxis = {
    type: 'category',
    data: agg.categories,
    axisLabel: mutedText,
    axisLine,
  };
  let valueAxis = { type: 'value', axisLabel: mutedText, splitLine };

  if (isRound(spec.chartKind)) {
    // one slice per category, first series' data
    let data = agg.categories.map((cat, i) => ({
      name: cat,
      value: agg.series[0]?.data[i] ?? 0,
    }));
    // the legend already names every slice, so slice labels stay off: in a
    // dashboard-sized tile they collide with the legend and each other
    return {
      ...base,
      legend: { type: 'scroll', bottom: 0, textStyle: mutedText },
      series: [
        {
          type: 'pie',
          center: ['50%', '45%'],
          radius: spec.chartKind === 'donut' ? ['42%', '66%'] : '66%',
          data,
          label: { show: false },
          emphasis: { label: { show: true, ...text, fontWeight: 600 } },
        },
      ],
    };
  }

  // containLabel grows the left margin to fit the widest y-axis label, so
  // seven-digit values are not clipped to ",800,000"
  let grid = { left: 16, right: 16, top: 32, bottom: 48, containLabel: true };

  if (spec.chartKind === 'scatter') {
    return {
      ...base,
      grid,
      xAxis: categoryAxis,
      yAxis: valueAxis,
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
    grid,
    legend:
      agg.series.length > 1 ? { bottom: 0, textStyle: mutedText } : undefined,
    xAxis: categoryAxis,
    yAxis: valueAxis,
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
