// Minimal CSV parsing shared by import commands. Quoted fields, escaped
// quotes, CRLF — enough for exported helpdesk data; not a streaming parser.
//
// The block-factory date rule lives here so no importer re-learns it: a CSV
// date is a CALENDAR DAY, not an instant. `new Date('9/30/2026').toISOString()`
// lands on the 29th east of UTC — so `parseCsvDate` builds Y-M-D from local
// parts and never round-trips through an ISO instant.

/** One CSV record with its 1-based row number as a spreadsheet shows it. */
export interface CsvRecord {
  row: number;
  cells: string[];
}

/**
 * RFC 4180 records: quoted cells may hold commas, newlines and doubled
 * quotes. A leading byte-order mark is dropped, and blank rows are skipped
 * but still counted, so `row` matches the row a spreadsheet shows.
 */
export function parseCsvRecords(text: string): CsvRecord[] {
  let records: CsvRecord[] = [];
  let row: string[] = [];
  let cell = '';
  let inQuotes = false;
  let rowNumber = 1;
  let input = text.replace(/^\uFEFF/, '');
  let end = () => {
    row.push(cell);
    if (row.some((c) => c.trim().length)) {
      records.push({ row: rowNumber, cells: row });
    }
    rowNumber++;
    row = [];
    cell = '';
  };
  for (let i = 0; i < input.length; i++) {
    let ch = input[i]!;
    if (inQuotes) {
      if (ch === '"') {
        if (input[i + 1] === '"') {
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
    } else if (ch === ',') {
      row.push(cell);
      cell = '';
    } else if (ch === '\n' || ch === '\r') {
      if (ch === '\r' && input[i + 1] === '\n') i++;
      end();
    } else {
      cell += ch;
    }
  }
  if (cell.length || row.length) {
    end();
  }
  return records;
}

/** The cells of each non-blank CSV row, without row numbers. */
export function parseCsv(text: string): string[][] {
  return parseCsvRecords(text).map((r) => r.cells);
}

/** Header row → lowercase-trimmed lookup: { 'subject': 0, ... } */
export function headerIndex(header: string[]): Record<string, number> {
  let idx: Record<string, number> = {};
  header.forEach((h, i) => (idx[h.trim().toLowerCase()] = i));
  return idx;
}

/**
 * A calendar day from a CSV cell. Accepts YYYY-MM-DD and M/D/YYYY. Throws on
 * anything else — throwing is how a cell reports itself unreadable, so the
 * importer can report the row instead of silently shifting a date.
 */
export function parseCsvDate(cell: string): Date {
  let s = cell.trim();
  let iso = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s);
  if (iso) {
    return calendarDay(cell, Number(iso[1]), Number(iso[2]), Number(iso[3]));
  }
  let us = /^(\d{1,2})\/(\d{1,2})\/(\d{4})$/.exec(s);
  if (us) {
    return calendarDay(cell, Number(us[3]), Number(us[1]), Number(us[2]));
  }
  throw new Error(
    `unreadable date "${cell}" (expected YYYY-MM-DD or M/D/YYYY)`,
  );
}

// A local calendar day, refusing one that does not exist (2026-02-30) rather
// than letting Date roll it into the next month.
function calendarDay(cell: string, y: number, m: number, d: number): Date {
  let date = new Date(y, m - 1, d);
  if (
    date.getFullYear() !== y ||
    date.getMonth() !== m - 1 ||
    date.getDate() !== d
  ) {
    throw new Error(`"${cell}" is not a calendar date`);
  }
  return date;
}
