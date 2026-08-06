// =============================================================================
// Client-side CSV parsing — structured files never go through the LLM.
// Pure functions: parse, infer column types, and suggest a chart heuristically
// (the same selection rules the AI skill uses, mechanized).
// =============================================================================

import type { DatasetColumn } from '../dataset';
import type { Aggregate, Bucket, ChartKind } from './chart-spec';

export interface ParsedCsv {
  columns: DatasetColumn[];
  rows: Record<string, string | number>[];
}

export interface SuggestedChart {
  chartKind: ChartKind;
  x?: string;
  xBucket: Bucket;
  y?: { field?: string; aggregate: Aggregate };
  title: string;
}

// RFC-4180-ish: quoted fields, escaped quotes, commas/newlines in quotes.
// Auto-detects tab vs comma delimiters.
export function splitCsv(text: string): string[][] {
  let delimiter = detectDelimiter(text);
  let rows: string[][] = [];
  let row: string[] = [];
  let cell = '';
  let inQuotes = false;
  for (let i = 0; i < text.length; i++) {
    let ch = text[i];
    if (inQuotes) {
      if (ch === '"') {
        if (text[i + 1] === '"') {
          cell += '"';
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        cell += ch;
      }
    } else if (ch === '"') {
      inQuotes = true;
    } else if (ch === delimiter) {
      row.push(cell);
      cell = '';
    } else if (ch === '\n' || ch === '\r') {
      if (ch === '\r' && text[i + 1] === '\n') {
        i++;
      }
      row.push(cell);
      cell = '';
      if (row.some((c) => c.trim() !== '')) {
        rows.push(row);
      }
      row = [];
    } else {
      cell += ch;
    }
  }
  row.push(cell);
  if (row.some((c) => c.trim() !== '')) {
    rows.push(row);
  }
  return rows;
}

function detectDelimiter(text: string): string {
  let firstLine = text.slice(0, text.indexOf('\n') + 1 || text.length);
  let tabs = (firstLine.match(/\t/g) ?? []).length;
  let commas = (firstLine.match(/,/g) ?? []).length;
  return tabs > commas ? '\t' : ',';
}

const NUMBER_RE = /^-?\$?[\d,]+(\.\d+)?%?$/;
const DATE_RE =
  /^\d{4}-\d{2}(-\d{2})?([T ].*)?$|^\d{1,2}[/-]\d{1,2}[/-]\d{2,4}$/;

function toNumber(value: string): number {
  return Number(value.replace(/[$,%]/g, '').replace(/,/g, ''));
}

export function parseCsv(text: string): ParsedCsv | undefined {
  let grid = splitCsv(text.trim());
  if (grid.length < 2) {
    return undefined;
  }
  let headers = grid[0].map(
    (h, i) => h.trim().replace(/\s+/g, ' ') || `col${i + 1}`,
  );
  let body = grid.slice(1).filter((r) => r.length > 1 || r[0]?.trim());
  if (!body.length) {
    return undefined;
  }

  // a column is numeric/date only if every non-empty cell matches
  let types: DatasetColumn['type'][] = headers.map((_, col) => {
    let cells = body.map((r) => (r[col] ?? '').trim()).filter(Boolean);
    if (!cells.length) {
      return 'string';
    }
    if (cells.every((c) => NUMBER_RE.test(c))) {
      return 'number';
    }
    if (cells.every((c) => DATE_RE.test(c))) {
      return 'date';
    }
    return 'string';
  });

  let columns: DatasetColumn[] = headers.map((name, i) => ({
    name,
    type: types[i],
  }));
  let rows = body.map((r) => {
    let obj: Record<string, string | number> = {};
    headers.forEach((name, i) => {
      let raw = (r[i] ?? '').trim();
      obj[name] = types[i] === 'number' && raw !== '' ? toNumber(raw) : raw;
    });
    return obj;
  });
  return { columns, rows };
}

// the skill's selection table, mechanized: date → line, few categories →
// donut, categories → bar, single numeric row → kpi
export function suggestChart(parsed: ParsedCsv, name: string): SuggestedChart {
  let { columns, rows } = parsed;
  let numeric = columns.find((c) => c.type === 'number');
  let date = columns.find((c) => c.type === 'date');
  let category = columns.find((c) => c.type === 'string');

  if (!numeric) {
    // nothing to measure: count rows per first column
    let dim = columns[0]?.name;
    return {
      chartKind: 'bar',
      x: dim,
      xBucket: 'none',
      y: { aggregate: 'count' },
      title: name,
    };
  }
  if (rows.length === 1) {
    return {
      chartKind: 'kpi',
      xBucket: 'none',
      y: { field: numeric.name, aggregate: 'sum' },
      title: name,
    };
  }
  if (date) {
    return {
      chartKind: 'line',
      x: date.name,
      xBucket: rows.length > 31 ? 'month' : 'none',
      y: { field: numeric.name, aggregate: 'sum' },
      title: name,
    };
  }
  if (category) {
    let distinct = new Set(rows.map((r) => r[category!.name])).size;
    return {
      chartKind: distinct <= 6 ? 'donut' : 'bar',
      x: category.name,
      xBucket: 'none',
      y: { field: numeric.name, aggregate: 'sum' },
      title: name,
    };
  }
  return {
    chartKind: 'bar',
    x: columns[0]?.name,
    xBucket: 'none',
    y: { field: numeric.name, aggregate: 'sum' },
    title: name,
  };
}
