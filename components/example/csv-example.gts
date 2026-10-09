import {
  CardDef,
  Component,
  FieldDef,
  contains,
  containsMany,
  field,
  realmURL,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import { tracked } from '@glimmer/tracking';
import { Table } from '@cardstack/pretui/components/table';

import { ExportButton, type ExportColumn } from '../export';
import {
  ImportButton,
  type ImportColumn,
  type ImportRowResult,
} from '../import';

export class SeatRowField extends FieldDef {
  static displayName = 'Seat Row';

  @field name = contains(StringField);
  @field email = contains(StringField);
  @field seats = contains(NumberField);
}

/** The card the Import button creates, one per CSV row. */
export class SeatHolder extends CardDef {
  static displayName = 'Seat Holder';

  @field name = contains(StringField);
  @field email = contains(StringField);
  @field seats = contains(NumberField);
}

const EXPORT_COLUMNS: ExportColumn<SeatRowField>[] = [
  { key: 'name', label: 'Name', value: (r) => r.name },
  { key: 'email', label: 'Email', value: (r) => r.email },
  { key: 'seats', label: 'Seats', value: (r) => r.seats },
];

const IMPORT_COLUMNS: ImportColumn[] = [
  { header: 'Name', field: 'name', required: true },
  { header: 'Email', field: 'email', required: true },
  {
    header: 'Seats',
    field: 'seats',
    parse: (raw: string) => {
      let n = Number(raw);
      if (!Number.isInteger(n) || n < 0) {
        throw new Error(`"${raw}" is not a whole number of seats`);
      }
      return n;
    },
  },
];

class CsvExampleIsolated extends Component<typeof CsvExample> {
  @tracked results: ImportRowResult[] = [];

  get rows(): SeatRowField[] {
    return this.args.model.rows ?? [];
  }

  get realm(): string | undefined {
    return (this.args.model as any)?.[realmURL]?.href;
  }

  get failed(): ImportRowResult[] {
    return this.results.filter((r) => !r.ok);
  }

  get created(): number {
    return this.results.filter((r) => r.ok).length;
  }

  onImported = (results: ImportRowResult[]) => {
    this.results = results;
  };

  <template>
    <article class='csv'>
      <header>
        <h1>{{@model.title}}</h1>
        <div class='actions'>
          <ExportButton
            @filename='seat-roster.csv'
            @rows={{this.rows}}
            @columns={{EXPORT_COLUMNS}}
          />
          {{#if this.realm}}
            <ImportButton
              @cardType={{SeatHolder}}
              @columns={{IMPORT_COLUMNS}}
              @commandContext={{@context.commandContext}}
              @realm={{this.realm}}
              @label='Import CSV'
              @onComplete={{this.onImported}}
            />
          {{/if}}
        </div>
      </header>

      <Table @label='Seat roster'>
        <:head>
          <tr>
            <th scope='col'>Name</th>
            <th scope='col'>Email</th>
            <th scope='col' class='num'>Seats</th>
          </tr>
        </:head>
        <:body>
          {{#each @model.rows as |row|}}
            <tr>
              <th scope='row'>{{row.name}}</th>
              <td>{{row.email}}</td>
              <td class='num'>{{row.seats}}</td>
            </tr>
          {{/each}}
        </:body>
      </Table>

      {{#if this.results.length}}
        <p class='outcome' role='status'>{{this.created}}
          created,
          {{this.failed.length}}
          failed.</p>
        {{#each this.failed as |r|}}
          <p class='failed'>Row {{r.row}}: {{r.error}}</p>
        {{/each}}
      {{/if}}
    </article>
    <style scoped>
      .csv {
        display: grid;
        gap: var(--boxel-sp);
        padding: var(--boxel-sp-lg);
        color: var(--foreground);
      }
      header {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        justify-content: space-between;
        gap: var(--boxel-sp-sm);
      }
      h1 {
        margin: 0;
        font-size: var(--boxel-font-size-lg);
      }
      .actions {
        display: flex;
        gap: var(--boxel-sp-xs);
      }
      .num {
        text-align: end;
        font-variant-numeric: tabular-nums;
      }
      .outcome,
      .failed {
        margin: 0;
        font-size: var(--boxel-font-size-sm);
      }
      .failed {
        color: var(--destructive-ink);
      }
    </style>
  </template>
}

/**
 * A seat roster that round-trips through CSV: Export downloads the rows, and
 * Import reads a file with the same headers into one Seat Holder card per row,
 * reporting each row's outcome.
 */
export class CsvExample extends CardDef {
  static displayName = 'CSV Example';

  @field title = contains(StringField);
  @field rows = containsMany(SeatRowField);

  static isolated = CsvExampleIsolated;
}
