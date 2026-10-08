// Minimal CSV parsing shared by import commands. Quoted fields, escaped
// quotes, CRLF — enough for exported helpdesk data; not a streaming parser.
//
// The block-factory date rule lives here so no importer re-learns it: a CSV
// date is a CALENDAR DAY, not an instant. `new Date('9/30/2026').toISOString()`
// lands on the 29th east of UTC — so `parseCsvDate` builds Y-M-D from local
// parts and never round-trips through an ISO instant.

export function parseCsv(text: string): string[][] {
  let rows: string[][] = [];
  let row: string[] = [];
  let cell = '';
  let inQuotes = false;
  for (let i = 0; i < text.length; i++) {
    let ch = text[i]!;
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
    } else if (ch === ',') {
      row.push(cell);
      cell = '';
    } else if (ch === '\n' || ch === '\r') {
      if (ch === '\r' && text[i + 1] === '\n') i++;
      row.push(cell);
      cell = '';
      if (row.length > 1 || row[0] !== '') rows.push(row);
      row = [];
    } else {
      cell += ch;
    }
  }
  row.push(cell);
  if (row.length > 1 || row[0] !== '') rows.push(row);
  return rows;
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
    return new Date(Number(iso[1]), Number(iso[2]) - 1, Number(iso[3]));
  }
  let us = /^(\d{1,2})\/(\d{1,2})\/(\d{4})$/.exec(s);
  if (us) {
    return new Date(Number(us[3]), Number(us[1]) - 1, Number(us[2]));
  }
  throw new Error(
    `unreadable date "${cell}" (expected YYYY-MM-DD or M/D/YYYY)`,
  );
}
