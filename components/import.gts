import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { action } from '@ember/object';
import type { CardDef } from '@cardstack/base/card-api';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import { FileTrigger } from '@cardstack/pretui/components/file-trigger';

import { parseCsvRecords, type CsvRecord } from '../utils/csv';

// How one CSV column becomes one field on the card. `parse` is the consumer's
// job because only it knows that "8/14/2026" is this card's dueDate and that
// "4,200.00" is money rather than a string.
export interface ImportColumn {
  header: string;
  field: string;
  required?: boolean;
  parse?: (raw: string) => unknown;
}

export interface ImportRowResult {
  row: number;
  ok: boolean;
  error?: string;
  id?: string;
}

export { parseCsv } from '../utils/csv';

// Turns parsed text into per-row attribute objects. A row that cannot be
// mapped fails on its own rather than taking the file down with it.
export function mapRows(
  records: CsvRecord[],
  columns: ImportColumn[],
): { row: number; attributes?: Record<string, unknown>; error?: string }[] {
  let [first, ...body] = records;
  let header = first?.cells ?? [];
  let index = new Map(
    header.map((h, i) => [h.trim().toLowerCase(), i] as [string, number]),
  );
  let missing = columns
    .filter((c) => c.required && !index.has(c.header.trim().toLowerCase()))
    .map((c) => c.header);
  if (missing.length) {
    return body.map(({ row }) => ({
      row,
      error: `File is missing required column${missing.length > 1 ? 's' : ''}: ${missing.join(', ')}`,
    }));
  }

  return body.map(({ row, cells }) => {
    let attributes: Record<string, unknown> = {};
    for (let column of columns) {
      let at = index.get(column.header.trim().toLowerCase());
      let raw = at === undefined ? '' : (cells[at] ?? '').trim();
      if (!raw) {
        if (column.required) {
          return { row, error: `${column.header} is empty` };
        }
        continue;
      }
      try {
        attributes[column.field] = column.parse ? column.parse(raw) : raw;
      } catch (e: any) {
        return {
          row,
          error: `${column.header}: ${e?.message ?? 'could not be read'}`,
        };
      }
    }
    return { row, attributes };
  });
}

interface ImportButtonSignature {
  Args: {
    cardType: typeof CardDef;
    columns: ImportColumn[];
    commandContext: any;
    label?: string;
    onComplete?: (results: ImportRowResult[]) => void;
    realm: string;
  };
  Element: HTMLElement;
}

export class ImportButton extends GlimmerComponent<ImportButtonSignature> {
  @tracked busy = false;

  @action async pick(files: File[]) {
    let file = files[0];
    if (!file) return;
    this.busy = true;
    try {
      let results = await this.ingest(await file.text());
      this.args.onComplete?.(results);
    } finally {
      this.busy = false;
    }
  }

  private async ingest(text: string): Promise<ImportRowResult[]> {
    let mapped = mapRows(parseCsvRecords(text), this.args.columns);
    let results: ImportRowResult[] = [];
    for (let entry of mapped) {
      let row = entry.row;
      if (entry.error || !entry.attributes) {
        results.push({ row, ok: false, error: entry.error });
        continue;
      }
      try {
        // One save with the row's values, so a failed write leaves no
        // half-filled card behind.
        let card = (await new SaveCardCommand(this.args.commandContext).execute(
          {
            card: new (this.args.cardType as any)(entry.attributes),
            realm: this.args.realm,
          } as any,
        )) as CardDef;
        results.push({ row, ok: true, id: card.id });
      } catch (e: any) {
        results.push({
          row,
          ok: false,
          error: e?.message ?? 'Could not be saved',
        });
      }
    }
    return results;
  }

  <template>
    <FileTrigger
      @accept='.csv,text/csv'
      @label={{if this.busy 'Importing…' (if @label @label 'Import CSV')}}
      @disabled={{this.busy}}
      @tone='neutral'
      @appearance='outlined'
      @size='s'
      @onSelect={{this.pick}}
      ...attributes
    />
  </template>
}
