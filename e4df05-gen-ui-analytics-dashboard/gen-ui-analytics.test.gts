import { module, test } from 'qunit';

import { parseColumns, parseRows, provenanceKind } from './dataset';
import {
  aggregate,
  bucketDate,
  validateChartSpec,
  type ChartSpec,
} from './utils/chart-spec';
import { parseCsv, splitCsv, suggestChart } from './utils/parse-csv';

export function runTests() {
  module('Unit | gen-ui-analytics utils', function () {
    // ── dataset parsing ────────────────────────────────────────────────

    test('parseRows returns arrays and never throws on bad input', function (assert) {
      assert.deepEqual(
        parseRows('[{"quarter":"Q1","deliveries":336681}]'),
        [{ quarter: 'Q1', deliveries: 336681 }],
        'valid JSON array parses',
      );
      assert.deepEqual(parseRows(undefined), [], 'undefined yields empty');
      assert.deepEqual(
        parseRows('not json'),
        [],
        'malformed JSON yields empty',
      );
      assert.deepEqual(parseRows('{"a":1}'), [], 'non-array JSON yields empty');
    });

    test('parseColumns keeps only entries with a string name', function (assert) {
      assert.deepEqual(
        parseColumns('[{"name":"quarter","type":"string"},{"type":"number"}]'),
        [{ name: 'quarter', type: 'string' }],
        'entries without a name are dropped',
      );
      assert.deepEqual(parseColumns('oops'), [], 'malformed JSON yields empty');
    });

    test('provenanceKind reads the sourceNote vocabulary', function (assert) {
      assert.strictEqual(
        provenanceKind('web-sourced: quarterly press releases'),
        'web',
        'web-sourced prefix',
      );
      assert.strictEqual(
        provenanceKind('AI-recalled figures — may be outdated'),
        'ai',
        'AI-recalled marker',
      );
      assert.strictEqual(
        provenanceKind('extracted from whiteboard.png'),
        'file',
        'anything else with content is a file',
      );
      assert.strictEqual(provenanceKind(undefined), 'none', 'no note');
      assert.strictEqual(provenanceKind(''), 'none', 'empty note');
    });

    // ── chart spec validation ──────────────────────────────────────────

    test('validateChartSpec accepts a well-formed dataset-backed bar spec', function (assert) {
      let { spec, errors } = validateChartSpec({
        chartKind: 'bar',
        source: { datasetId: 'https://example.test/Dataset/d1' },
        x: 'region',
        y: { field: 'deliveries', aggregate: 'sum' },
      });
      assert.deepEqual(errors, [], 'no errors');
      assert.strictEqual(spec?.chartKind, 'bar', 'spec returned');
    });

    test('validateChartSpec rejects bad kind, missing source, missing x', function (assert) {
      let { spec, errors } = validateChartSpec({ chartKind: 'sparkline' });
      assert.notOk(spec, 'no spec returned');
      assert.ok(
        errors.some((e) => e.includes('chartKind')),
        'flags the unknown chartKind',
      );
      assert.ok(
        errors.some((e) => e.includes('source')),
        'flags the missing source',
      );
    });

    test('validateChartSpec requires y.field for sum but not for count', function (assert) {
      let base = {
        chartKind: 'bar',
        source: { datasetId: 'd1' },
        x: 'region',
      };
      let sum = validateChartSpec({ ...base, y: { aggregate: 'sum' } });
      assert.ok(
        sum.errors.some((e) => e.includes('y.field')),
        'sum without a field is rejected',
      );
      let count = validateChartSpec({ ...base, y: { aggregate: 'count' } });
      assert.deepEqual(count.errors, [], 'count needs no field');
    });

    test('aggregate sums a kpi total and groups categories', function (assert) {
      let rows = [
        { quarter: 'Q1', deliveries: 100 },
        { quarter: 'Q1', deliveries: 50 },
        { quarter: 'Q2', deliveries: 25 },
      ];
      let kpi = aggregate(rows, {
        chartKind: 'kpi',
        source: { datasetId: 'd1' },
        y: { field: 'deliveries', aggregate: 'sum' },
      } as ChartSpec);
      assert.strictEqual(kpi.total, 175, 'kpi totals every row');

      let bar = aggregate(rows, {
        chartKind: 'bar',
        source: { datasetId: 'd1' },
        x: 'quarter',
        y: { field: 'deliveries', aggregate: 'sum' },
      } as ChartSpec);
      assert.deepEqual(bar.categories, ['Q1', 'Q2'], 'grouped by dimension');
      assert.deepEqual(
        bar.series[0]?.data,
        [150, 25],
        'sums within each category',
      );
    });

    test('bucketDate reads date-only strings in local time', function (assert) {
      // `new Date('2025-01-01')` is UTC midnight while getFullYear() reads local
      // time, so west of UTC an unguarded implementation buckets a period early
      assert.strictEqual(bucketDate('2025-01-01', 'year'), '2025', 'year');
      assert.strictEqual(
        bucketDate('2025-01-01', 'quarter'),
        '2025 Q1',
        'quarter',
      );
      assert.strictEqual(bucketDate('2025-01-01', 'month'), '2025-01', 'month');
      assert.strictEqual(
        bucketDate('2024-12-31', 'quarter'),
        '2024 Q4',
        'the other side of the boundary',
      );
      assert.strictEqual(
        bucketDate('not a date', 'month'),
        'not a date',
        'unparseable values pass through',
      );
    });

    test('aggregate keeps source order for pre-aggregated labels', function (assert) {
      let rows = [
        { period: 'Q4 2024', units: 3 },
        { period: 'Q1 2025', units: 5 },
      ];
      let unbucketed = aggregate(rows, {
        chartKind: 'line',
        source: { datasetId: 'd1' },
        x: 'period',
        xBucket: 'none',
        y: { field: 'units', aggregate: 'sum' },
      } as ChartSpec);
      assert.deepEqual(
        unbucketed.categories,
        ['Q4 2024', 'Q1 2025'],
        'an alphabetical sort would run time backwards here',
      );

      let bucketed = aggregate(
        [
          { day: '2025-03-02', units: 1 },
          { day: '2025-01-04', units: 2 },
        ],
        {
          chartKind: 'line',
          source: { datasetId: 'd1' },
          x: 'day',
          xBucket: 'month',
          y: { field: 'units', aggregate: 'sum' },
        } as ChartSpec,
      );
      assert.deepEqual(
        bucketed.categories,
        ['2025-01', '2025-03'],
        'bucketed labels are sortable, so they are sorted chronologically',
      );
    });

    // ── csv ingestion ──────────────────────────────────────────────────

    test('splitCsv handles quoted fields and auto-detects tabs', function (assert) {
      assert.deepEqual(
        splitCsv('a,b\n"1,5",x'),
        [
          ['a', 'b'],
          ['1,5', 'x'],
        ],
        'commas inside quotes survive',
      );
      assert.deepEqual(
        splitCsv('a\tb\n1\t2'),
        [
          ['a', 'b'],
          ['1', '2'],
        ],
        'tab-delimited input is detected',
      );
    });

    test('parseCsv infers column types and coerces numbers', function (assert) {
      let parsed = parseCsv(
        'product,units,sold_on\nWidget,"1,200",2025-01-15\nGadget,$85,2025-02-01\n',
      );
      assert.ok(parsed, 'parses');
      assert.deepEqual(
        parsed?.columns,
        [
          { name: 'product', type: 'string' },
          { name: 'units', type: 'number' },
          { name: 'sold_on', type: 'date' },
        ],
        'types inferred per column',
      );
      assert.strictEqual(
        parsed?.rows[0]?.units,
        1200,
        'currency/thousands separators are stripped',
      );
      assert.strictEqual(
        parseCsv('only-a-header\n'),
        undefined,
        'a header with no body is rejected',
      );
    });

    test('suggestChart follows the selection table', function (assert) {
      let categories = parseCsv('line,sales\nCars,10\nPlanes,8\nTrains,3\n')!;
      assert.strictEqual(
        suggestChart(categories, 't').chartKind,
        'donut',
        'few categories suggest a donut',
      );

      let dates = parseCsv('day,sales\n2025-01-01,4\n2025-01-02,6\n')!;
      assert.strictEqual(
        suggestChart(dates, 't').chartKind,
        'line',
        'a date dimension suggests a line',
      );

      let single = parseCsv('total\n42\n')!;
      assert.strictEqual(
        suggestChart(single, 't').chartKind,
        'kpi',
        'a single numeric row suggests a kpi',
      );
    });

    test('suggestChart does not chart the year column against itself', function (assert) {
      // a `year` column matches NUMBER_RE before DATE_RE, so it types as
      // `number`; the measure has to skip whichever column became the dimension
      let byYear = parseCsv('year,revenue\n2023,120\n2024,150\n2025,190\n')!;
      let spec = suggestChart(byYear, 't');
      assert.strictEqual(spec.x, 'year', 'the year column is the dimension');
      assert.strictEqual(
        spec.y?.field,
        'revenue',
        'the measure is the numeric column that is not the dimension',
      );
    });
  });
}
