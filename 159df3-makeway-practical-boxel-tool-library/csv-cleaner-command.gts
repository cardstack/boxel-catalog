import { Command } from '@cardstack/runtime-common';
import { CsvCleanerInput } from './csv-cleaner-input';
import { CsvCleanerResult } from './csv-cleaner-result';
function parseCsv(source: string): string[][] {
  const rows: string[][] = [];
  let row: string[] = [];
  let value = '';
  let quoted = false;
  let quoteClosed = false;
  for (let i = 0; i < source.length; i++) {
    const ch = source[i];
    if (quoted) {
      if (ch === '"' && source[i + 1] === '"') {
        value += '"';
        i++;
      } else if (ch === '"') {
        quoted = false;
        quoteClosed = true;
      } else value += ch;
    } else if (quoteClosed) {
      if (ch === ',') {
        row.push(value);
        value = '';
        quoteClosed = false;
      } else if (ch === '\n' || ch === '\r') {
        if (ch === '\r' && source[i + 1] === '\n') i++;
        row.push(value);
        value = '';
        quoteClosed = false;
        if (row.some((cell) => cell !== '')) rows.push(row);
        row = [];
      } else {
        throw new Error(
          'Unexpected text after a closing quote in CSV record ' +
            (rows.length + 1) +
            '.',
        );
      }
    } else if (ch === '"') {
      if (value.length > 0)
        throw new Error(
          'A quote must start a CSV cell in record ' + (rows.length + 1) + '.',
        );
      quoted = true;
    } else if (ch === ',') {
      row.push(value);
      value = '';
    } else if (ch === '\n' || ch === '\r') {
      if (ch === '\r' && source[i + 1] === '\n') i++;
      row.push(value);
      value = '';
      if (row.some((cell) => cell !== '')) rows.push(row);
      row = [];
    } else value += ch;
  }
  if (quoted)
    throw new Error('A quoted CSV cell is missing its closing quote.');
  row.push(value);
  if (row.some((cell) => cell !== '')) rows.push(row);
  return rows;
}
function encodeCsvCell(value: string): string {
  return /[",\n\r]/.test(value) ? '"' + value.replace(/"/g, '""') + '"' : value;
}
export class CsvCleanerCommand extends Command<
  typeof CsvCleanerInput,
  typeof CsvCleanerResult
> {
  static actionVerb = 'Clean';
  static displayName = 'Clean CSV';
  async getInputType() {
    return CsvCleanerInput;
  }
  protected async run(input: CsvCleanerInput): Promise<CsvCleanerResult> {
    const source = (input.source ?? '').replace(/^\uFEFF/, '');
    if (!source.trim()) throw new Error('Paste CSV text to clean.');
    if (source.length > 1000000)
      throw new Error(
        'This CSV is over 1 MB. Split it into smaller files before cleaning.',
      );
    const rows = parseCsv(source);
    if (!rows.length) return new CsvCleanerResult({ output: '' });
    const width = rows[0].length;
    const normalized = rows.map((row, index) => {
      if (row.length !== width)
        throw new Error(
          'Record ' +
            (index + 1) +
            ' has ' +
            row.length +
            ' columns; the header has ' +
            width +
            '. Nothing was changed.',
        );
      return row;
    });
    const output = normalized
      .map((row) => row.map(encodeCsvCell).join(','))
      .join(String.fromCharCode(10));
    return new CsvCleanerResult({ output });
  }
}
