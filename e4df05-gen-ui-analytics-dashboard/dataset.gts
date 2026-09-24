import { CardDef, Component, field, contains } from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import TableIcon from '@cardstack/boxel-icons/table';

// A schema-less table: any screenshot / CSV / pasted grid becomes one of
// these, whatever its columns. Charts reference it via source.datasetId, so
// ad-hoc data never needs its own CardDef.

export interface DatasetColumn {
  name: string;
  type: 'string' | 'number' | 'date';
}

export function parseColumns(columnsJson: string | undefined): DatasetColumn[] {
  if (!columnsJson) {
    return [];
  }
  try {
    let parsed = JSON.parse(columnsJson);
    return Array.isArray(parsed)
      ? parsed.filter((c) => c && typeof c.name === 'string')
      : [];
  } catch {
    return [];
  }
}

export function parseRows(rowsJson: string | undefined): any[] {
  if (!rowsJson) {
    return [];
  }
  try {
    let parsed = JSON.parse(rowsJson);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

// the provenance badge reads the sourceNote's provenance vocabulary:
// web-sourced (live search), AI-recalled (model memory), extracted (a file
// the user dropped)
export function provenanceKind(
  sourceNote: string | undefined,
): 'web' | 'ai' | 'file' | 'none' {
  let note = (sourceNote ?? '').toLowerCase();
  if (!note) {
    return 'none';
  }
  if (note.startsWith('web-sourced')) {
    return 'web';
  }
  if (note.includes('ai-recalled')) {
    return 'ai';
  }
  return 'file';
}

const PROVENANCE_LABELS: Record<string, string> = {
  web: 'Web-sourced',
  ai: 'AI-recalled',
  file: 'Extracted from file',
  none: 'No source recorded',
};

function get(row: any, key: string): string {
  let value = row?.[key];
  return value == null ? '' : String(value);
}

function isNumberCol(col: DatasetColumn): boolean {
  return col.type === 'number';
}

// Provenance maps onto the status hues: web-sourced reads as info, AI-recalled
// as a warning (check it), extracted-from-file as success. Each format sets
// --prov / --prov-ink from the kind class and consumes them diluted.

class DatasetIsolated extends Component<typeof Dataset> {
  get columns(): DatasetColumn[] {
    return parseColumns(this.args.model?.columnsJson);
  }
  get rows(): any[] {
    return parseRows(this.args.model?.rowsJson);
  }
  get provenance(): string {
    return provenanceKind(this.args.model?.sourceNote);
  }
  get provenanceLabel(): string {
    return PROVENANCE_LABELS[this.provenance];
  }

  <template>
    <article class='dataset-isolated'>
      <header class='ds-header'>
        <div class='ds-heading'>
          <h1>{{if @model.title @model.title 'Untitled Dataset'}}</h1>
          <p class='ds-meta-row'>
            <span
              class='ds-badge prov-{{this.provenance}}'
            >{{this.provenanceLabel}}</span>
            <span class='ds-stat'>{{this.rows.length}} rows</span>
            <span class='ds-stat'>{{this.columns.length}} columns</span>
          </p>
        </div>
        {{#if @model.sourceFileUrl}}
          <a
            class='ds-source-link'
            href={{@model.sourceFileUrl}}
            target='_blank'
            rel='noopener noreferrer'
          >View source ⤢</a>
        {{/if}}
      </header>
      {{#if @model.sourceNote}}
        <p class='ds-note'>{{@model.sourceNote}}</p>
      {{/if}}

      <ul class='ds-columns' aria-label='Columns'>
        {{#each this.columns as |col|}}
          <li class='ds-col-chip'>
            {{col.name}}
            <em>{{col.type}}</em>
          </li>
        {{/each}}
      </ul>

      {{#if this.rows.length}}
        <div class='ds-table-scroll'>
          <table>
            <thead>
              <tr>
                {{#each this.columns as |col|}}
                  <th
                    scope='col'
                    class={{if (isNumberCol col) 'num'}}
                  >{{col.name}}</th>
                {{/each}}
              </tr>
            </thead>
            <tbody>
              {{#each this.rows as |row|}}
                <tr>
                  {{#each this.columns as |col|}}
                    <td class={{if (isNumberCol col) 'num'}}>{{get
                        row
                        col.name
                      }}</td>
                  {{/each}}
                </tr>
              {{/each}}
            </tbody>
          </table>
        </div>
      {{else}}
        <p class='ds-empty'>No rows yet.</p>
      {{/if}}
    </article>
    <style scoped>
      .dataset-isolated {
        height: 100%;
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-sm);
        padding: clamp(1rem, 3cqi, 2rem);
        container-type: inline-size;
        overflow: auto;
      }
      .ds-header {
        display: flex;
        align-items: flex-start;
        justify-content: space-between;
        gap: var(--boxel-sp);
        flex-wrap: wrap;
      }
      .ds-heading h1 {
        margin: 0 0 var(--boxel-sp-xs);
      }
      .ds-meta-row {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        flex-wrap: wrap;
      }
      .prov-web {
        --prov: var(--info);
        --prov-ink: var(--info-ink);
      }
      .prov-ai {
        --prov: var(--warning);
        --prov-ink: var(--warning-ink);
      }
      .prov-file {
        --prov: var(--success);
        --prov-ink: var(--success-ink);
      }
      .prov-none {
        --prov: var(--muted-foreground);
        --prov-ink: var(--muted-foreground);
      }
      .ds-badge {
        font-size: var(--boxel-font-size-2xs);
        font-weight: 650;
        letter-spacing: 0.06em;
        text-transform: uppercase;
        padding: var(--boxel-sp-5xs) var(--boxel-sp-xs);
        border-radius: var(--boxel-border-radius-2xl);
        color: var(--prov-ink);
        background-color: color-mix(in oklch, var(--prov) 12%, transparent);
        border: 1px solid color-mix(in oklch, var(--prov) 35%, transparent);
      }
      .ds-stat {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
        font-variant-numeric: tabular-nums;
      }
      .ds-source-link {
        flex-shrink: 0;
        font-size: var(--boxel-font-size-sm);
        color: var(--primary-ink);
        text-decoration: none;
        border: 1px solid var(--border);
        border-radius: var(--boxel-border-radius-2xl);
        padding: var(--boxel-sp-2xs) var(--boxel-sp-sm);
      }
      .ds-source-link:hover {
        border-color: var(--ring);
      }
      .ds-note {
        margin: 0;
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground);
      }
      .ds-columns {
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp-2xs);
        margin: 0;
        padding: 0;
        list-style: none;
      }
      .ds-col-chip {
        font-size: var(--boxel-font-size-xs);
        background-color: var(--muted);
        color: var(--foreground);
        border: 1px solid var(--border);
        border-radius: var(--boxel-border-radius-2xl);
        padding: var(--boxel-sp-5xs) var(--boxel-sp-sm);
      }
      .ds-col-chip em {
        font-style: normal;
        color: var(--muted-foreground);
        font-size: var(--boxel-font-size-2xs);
        margin-left: var(--boxel-sp-4xs);
      }
      .ds-table-scroll {
        flex: 1;
        min-height: 0;
        overflow: auto;
        border: 1px solid var(--border);
        border-radius: var(--boxel-border-radius-lg);
        background-color: var(--card);
        color: var(--card-foreground);
      }
      table {
        border-collapse: collapse;
        width: 100%;
        font-size: var(--boxel-font-size-sm);
      }
      th,
      td {
        text-align: left;
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        border-bottom: 1px solid var(--border);
        white-space: nowrap;
      }
      th {
        position: sticky;
        top: 0;
        z-index: 1;
        background-color: var(--card);
        font-weight: 600;
        font-size: var(--boxel-font-size-2xs);
        text-transform: uppercase;
        letter-spacing: 0.05em;
        color: var(--muted-foreground);
      }
      td {
        font-variant-numeric: tabular-nums;
      }
      th.num,
      td.num {
        text-align: right;
      }
      tbody tr:nth-child(even) {
        background-color: var(--stripe);
      }
      tbody tr:hover {
        background-color: var(--hover);
      }
      .ds-empty {
        color: var(--muted-foreground);
      }
    </style>
  </template>
}

class DatasetEmbedded extends Component<typeof Dataset> {
  get columns(): DatasetColumn[] {
    return parseColumns(this.args.model?.columnsJson);
  }
  get rows(): any[] {
    return parseRows(this.args.model?.rowsJson);
  }
  get shownRows(): any[] {
    return this.rows.slice(0, 12);
  }
  get hiddenCount(): number {
    return Math.max(0, this.rows.length - 12);
  }
  get provenance(): string {
    return provenanceKind(this.args.model?.sourceNote);
  }
  get provenanceLabel(): string {
    return PROVENANCE_LABELS[this.provenance];
  }

  <template>
    <div class='dataset-embedded'>
      <p class='dse-meta'>
        <span
          class='dse-badge prov-{{this.provenance}}'
        >{{this.provenanceLabel}}</span>
        <span class='dse-count'>{{this.rows.length}} rows</span>
        {{#if @model.sourceFileUrl}}
          <a
            class='dse-source'
            href={{@model.sourceFileUrl}}
            target='_blank'
            rel='noopener noreferrer'
          >source ⤢</a>
        {{/if}}
      </p>
      {{#if this.rows.length}}
        <div class='dse-scroll'>
          <table>
            <thead>
              <tr>
                {{#each this.columns as |col|}}
                  <th
                    scope='col'
                    class={{if (isNumberCol col) 'num'}}
                  >{{col.name}}</th>
                {{/each}}
              </tr>
            </thead>
            <tbody>
              {{#each this.shownRows as |row|}}
                <tr>
                  {{#each this.columns as |col|}}
                    <td class={{if (isNumberCol col) 'num'}}>{{get
                        row
                        col.name
                      }}</td>
                  {{/each}}
                </tr>
              {{/each}}
            </tbody>
          </table>
        </div>
        {{#if this.hiddenCount}}
          <p class='dse-more'>+
            {{this.hiddenCount}}
            more rows — open the card to see all</p>
        {{/if}}
      {{else}}
        <p class='dse-empty'>No rows yet.</p>
      {{/if}}
    </div>
    <style scoped>
      .dataset-embedded {
        padding: var(--boxel-sp-sm) var(--boxel-sp);
        font-size: var(--boxel-font-size-sm);
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
        height: 100%;
      }
      .dse-meta {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        flex-wrap: wrap;
      }
      .prov-web {
        --prov: var(--info);
        --prov-ink: var(--info-ink);
      }
      .prov-ai {
        --prov: var(--warning);
        --prov-ink: var(--warning-ink);
      }
      .prov-file {
        --prov: var(--success);
        --prov-ink: var(--success-ink);
      }
      .prov-none {
        --prov: var(--muted-foreground);
        --prov-ink: var(--muted-foreground);
      }
      .dse-badge {
        font-size: var(--boxel-font-size-2xs);
        font-weight: 650;
        letter-spacing: 0.06em;
        text-transform: uppercase;
        padding: var(--boxel-sp-6xs) var(--boxel-sp-xs);
        border-radius: var(--boxel-border-radius-2xl);
        color: var(--prov-ink);
        border: 1px solid color-mix(in oklch, var(--prov) 45%, transparent);
      }
      .dse-count {
        color: var(--muted-foreground);
        font-size: var(--boxel-font-size-xs);
        font-variant-numeric: tabular-nums;
      }
      .dse-source {
        font-size: var(--boxel-font-size-xs);
        color: var(--primary-ink);
      }
      .dse-scroll {
        overflow: auto;
        min-height: 0;
      }
      table {
        border-collapse: collapse;
        width: 100%;
      }
      th,
      td {
        text-align: left;
        padding: var(--boxel-sp-4xs) var(--boxel-sp-xs);
        border-bottom: 1px solid var(--border);
        white-space: nowrap;
      }
      th {
        font-weight: 600;
        font-size: var(--boxel-font-size-2xs);
        text-transform: uppercase;
        letter-spacing: 0.03em;
        color: var(--muted-foreground);
      }
      td {
        font-variant-numeric: tabular-nums;
      }
      th.num,
      td.num {
        text-align: right;
      }
      .dse-more {
        margin: 0;
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
      }
      .dse-empty {
        color: var(--muted-foreground);
      }
    </style>
  </template>
}

export class Dataset extends CardDef {
  static displayName = 'Dataset';
  static icon = TableIcon;

  @field title = contains(StringField);
  @field columnsJson = contains(StringField); // [{name, type}]
  @field rowsJson = contains(StringField); // [{col: value, ...}]
  @field sourceNote = contains(StringField); // e.g. "extracted from whiteboard.png"
  // realm file URL of the original screenshot/CSV (a raw file write returns
  // a URL, not a card id, so this stays a string — same call TSP made)
  @field sourceFileUrl = contains(StringField);

  static isolated = DatasetIsolated;
  static embedded = DatasetEmbedded;

  // "Night Wall" fitted: a miniature table — real column chips over skeleton
  // rows, provenance carried by the eyebrow color
  static fitted = class Fitted extends Component<typeof Dataset> {
    get rows(): any[] {
      return parseRows(this.args.model?.rowsJson);
    }
    get allColumns(): DatasetColumn[] {
      return parseColumns(this.args.model?.columnsJson);
    }
    // the chip strip only has room for three; the count reports them all
    get columns(): DatasetColumn[] {
      return this.allColumns.slice(0, 3);
    }
    get provenance(): string {
      return provenanceKind(this.args.model?.sourceNote);
    }
    get provenanceLabel(): string {
      return PROVENANCE_LABELS[this.provenance];
    }
    <template>
      <article class='fit'>
        <div class='r-head'>
          <p
            class='eyebrow prov-{{this.provenance}}'
          >{{this.provenanceLabel}}</p>
          <h3 class='title'>{{if
              @model.title
              @model.title
              'Untitled Dataset'
            }}</h3>
        </div>
        <div class='r-table'>
          <div class='cols'>
            {{#each this.columns as |col|}}
              <span class='col'>{{col.name}}</span>
            {{/each}}
          </div>
          <div class='rows'>
            <i class='w1'></i>
            <i class='w2'></i>
            <i class='w3'></i>
            <i class='w4'></i>
          </div>
        </div>
        <div class='r-meta'>
          <span>{{this.rows.length}} rows</span>
          <span>·</span>
          <span>{{this.allColumns.length}} columns</span>
        </div>
      </article>
      <style scoped>
        .fit {
          --ar: calc(max(1cqi, 1cqb) - min(1cqi, 1cqb));
          --type-ratio: 1.25;
          --type-base: clamp(
            0.625rem,
            calc(0.1875rem + 2.2cqi + 1cqb - 0.6 * var(--ar)),
            1.125rem
          );
          --fit-meta-size: max(
            0.5rem,
            calc(var(--type-base) / var(--type-ratio))
          );
          --fit-eyebrow-size: max(
            0.4375rem,
            calc(var(--type-base) / pow(var(--type-ratio), 2))
          );
          --fit-headline-size: max(
            0.6875rem,
            calc(var(--type-base) * pow(var(--type-ratio), 1.5))
          );
          --fit-pad: clamp(0.375rem, calc(0.125rem + 2cqi), 1rem);
          --fit-gap: clamp(0.1875rem, calc(0.0625rem + 1.2cqi), 0.625rem);

          width: 100%;
          height: 100%;
          display: grid;
          grid-template-rows: auto minmax(0, 1fr) auto;
          grid-template-areas: 'head' 'table' 'meta';
          gap: var(--fit-gap);
          padding: var(--fit-pad);
        }
        .r-head,
        .r-table,
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
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
          color: var(--muted-foreground);
        }
        .eyebrow.prov-web {
          color: var(--info-ink);
        }
        .eyebrow.prov-ai {
          color: var(--warning-ink);
        }
        .eyebrow.prov-file {
          color: var(--success-ink);
        }
        .title {
          margin: var(--boxel-sp-6xs) 0 0;
          font-size: var(--fit-headline-size);
          font-weight: 700;
          letter-spacing: -0.015em;
          line-height: 1.15;
          display: -webkit-box;
          -webkit-box-orient: vertical;
          -webkit-line-clamp: 2;
          overflow: hidden;
        }
        .r-table {
          display: flex;
          flex-direction: column;
          gap: calc(var(--fit-gap) * 0.7);
          background-color: var(--inset);
          color: var(--foreground);
          border: 1px solid var(--border);
          border-radius: var(--boxel-border-radius-sm);
          padding: calc(var(--fit-pad) * 0.55);
        }
        .cols {
          display: flex;
          gap: calc(var(--fit-gap) * 0.7);
          flex-shrink: 0;
          overflow: hidden;
        }
        .col {
          font-size: var(--fit-eyebrow-size);
          font-weight: 650;
          letter-spacing: 0.08em;
          text-transform: uppercase;
          color: var(--muted-foreground);
          border-bottom: 1px solid var(--border);
          padding-bottom: var(--boxel-sp-6xs);
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
          max-width: 38%;
        }
        .rows {
          flex: 1;
          min-height: 0;
          display: flex;
          flex-direction: column;
          justify-content: space-evenly;
          gap: var(--boxel-sp-6xs);
          overflow: hidden;
        }
        .rows .w1 {
          width: 88%;
        }
        .rows .w2 {
          width: 72%;
        }
        .rows .w3 {
          width: 80%;
        }
        .rows .w4 {
          width: 58%;
        }
        .rows i {
          height: max(0.1875rem, 6cqb);
          max-height: 0.5rem;
          border-radius: var(--boxel-border-radius-2xs);
          background-color: var(--muted);
          flex-shrink: 0;
        }
        .r-meta {
          display: flex;
          gap: var(--boxel-sp-4xs);
          font-size: var(--fit-meta-size);
          color: var(--muted-foreground);
          font-variant-numeric: tabular-nums;
          white-space: nowrap;
        }

        /* h40: title only */
        @container fitted-card (height <= 50px) {
          .fit {
            grid-template-rows: 1fr;
            grid-template-areas: 'head';
            gap: 0;
          }
          .r-table,
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
          .r-table {
            display: none;
          }
          .title {
            -webkit-line-clamp: 1;
          }
        }
        /* h105: single-line title, table stays thin */
        @container fitted-card (80px < height <= 130px) {
          .title {
            -webkit-line-clamp: 1;
          }
          .cols {
            display: none;
          }
        }
        /* wide + short: mini table docks right */
        @container fitted-card (width > 260px) and (50px < height <= 130px) {
          .fit {
            grid-template-columns: minmax(0, 1fr) minmax(4rem, 24cqw);
            grid-template-rows: minmax(0, 1fr) auto;
            grid-template-areas: 'head table' 'meta table';
            column-gap: calc(var(--fit-gap) * 1.5);
          }
          .r-table {
            display: flex;
          }
          .cols {
            display: none;
          }
        }
        @container fitted-card (width <= 150px) {
          .cols .col:nth-child(n + 3) {
            display: none;
          }
        }
      </style>
    </template>
  };
}
