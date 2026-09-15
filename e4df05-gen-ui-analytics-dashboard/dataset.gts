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

class DatasetIsolated extends Component<typeof Dataset> {
  get hasLinkedTheme(): boolean {
    return Boolean(this.args.model?.cardInfo?.theme);
  }
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
    <article
      class='dataset-isolated {{unless this.hasLinkedTheme "gu-default-theme"}}'
    >
      <div class='ds-header'>
        <div class='ds-heading'>
          <h1>{{if @model.title @model.title 'Untitled Dataset'}}</h1>
          <div class='ds-meta-row'>
            <span
              class='ds-badge {{this.provenance}}'
            >{{this.provenanceLabel}}</span>
            <span class='ds-stat'>{{this.rows.length}} rows</span>
            <span class='ds-stat'>{{this.columns.length}} columns</span>
          </div>
        </div>
        {{#if @model.sourceFileUrl}}
          <a
            class='ds-source-link'
            href={{@model.sourceFileUrl}}
            target='_blank'
            rel='noopener noreferrer'
          >View source ⤢</a>
        {{/if}}
      </div>
      {{#if @model.sourceNote}}
        <p class='ds-note'>{{@model.sourceNote}}</p>
      {{/if}}

      <div class='ds-columns'>
        {{#each this.columns as |col|}}
          <span class='ds-col-chip'>
            {{col.name}}
            <em>{{col.type}}</em>
          </span>
        {{/each}}
      </div>

      {{#if this.rows.length}}
        <div class='ds-table-scroll'>
          <table>
            <thead>
              <tr>
                {{#each this.columns as |col|}}
                  <th class={{if (isNumberCol col) 'num'}}>{{col.name}}</th>
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
      /* the ai-image-generator pin pattern (boxel-theming-ui rule 4), minus
         its [data-theme='dark'] variant: Night Wall is a committed single
         dark identity with no scheme toggle, so a dark variant would be
         dead code — the linked-theme path handles dark via .dark blocks */
      .gu-default-theme {
        --background: #0f1217;
        --foreground: #e8ecf1;
        --card: #171c24;
        --card-foreground: #e8ecf1;
        --primary: #5b8ff9;
        --primary-foreground: #0f1217;
        --secondary: #7ed9a6;
        --secondary-foreground: #0f1217;
        --accent: #f2cf7e;
        --accent-foreground: #0f1217;
        --muted: #1c2330;
        --muted-foreground: #93a0b4;
        --destructive: #c25668;
        --destructive-foreground: #0f1217;
        --border: rgba(255, 255, 255, 0.09);
        --input: rgba(255, 255, 255, 0.09);
        --ring: #5b8ff9;
      }
      .dataset-isolated {
        --ds-bg: var(--gen-ui-bg, var(--background, #0f1217));
        --ds-surface: var(--gen-ui-surface, var(--card, #171c24));
        --ds-border: var(
          --gen-ui-border,
          var(--border, rgba(255, 255, 255, 0.08))
        );
        --ds-text: var(--gen-ui-ink, var(--foreground, #e8ecf1));
        --ds-muted: var(--gen-ui-muted, var(--muted-foreground, #93a0b4));
        --ds-accent: var(--gen-ui-accent, var(--primary, #5b8ff9));
        height: 100%;
        display: flex;
        flex-direction: column;
        gap: 14px;
        padding: clamp(16px, 3cqi, 32px);
        background: var(--ds-bg);
        color: var(--ds-text);
        container-type: inline-size;
        font-family: var(--font-sans, ui-sans-serif, system-ui, sans-serif);
        overflow: auto;
      }
      .ds-header {
        display: flex;
        align-items: flex-start;
        justify-content: space-between;
        gap: 16px;
        flex-wrap: wrap;
      }
      .ds-heading h1 {
        margin: 0 0 8px;
        font-size: clamp(1.15rem, 2.6cqi, 1.6rem);
        letter-spacing: -0.015em;
      }
      .ds-meta-row {
        display: flex;
        align-items: center;
        gap: 10px;
        flex-wrap: wrap;
      }
      .ds-badge {
        font-size: 0.6875rem;
        font-weight: 650;
        letter-spacing: 0.06em;
        text-transform: uppercase;
        padding: 3px 10px;
        border-radius: 999px;
        border: 1px solid;
      }
      .ds-badge.web {
        color: #7db4ff;
        border-color: rgba(125, 180, 255, 0.4);
        background: rgba(125, 180, 255, 0.1);
      }
      .ds-badge.ai {
        color: #f2cf7e;
        border-color: rgba(242, 207, 126, 0.4);
        background: rgba(242, 207, 126, 0.08);
      }
      .ds-badge.file {
        color: #7ed9a6;
        border-color: rgba(126, 217, 166, 0.4);
        background: rgba(126, 217, 166, 0.08);
      }
      .ds-badge.none {
        color: var(--ds-muted);
        border-color: var(--ds-border);
      }
      .ds-stat {
        font-size: 0.75rem;
        color: var(--ds-muted);
        font-variant-numeric: tabular-nums;
      }
      .ds-source-link {
        flex-shrink: 0;
        font-size: 0.8125rem;
        color: var(--ds-accent);
        text-decoration: none;
        border: 1px solid var(--ds-border);
        border-radius: 999px;
        padding: 7px 14px;
      }
      .ds-source-link:hover {
        border-color: var(--ds-accent);
      }
      .ds-note {
        margin: 0;
        font-size: 0.8125rem;
        color: var(--ds-muted);
      }
      .ds-columns {
        display: flex;
        flex-wrap: wrap;
        gap: 6px;
      }
      .ds-col-chip {
        font-size: 0.75rem;
        background: var(--ds-surface);
        border: 1px solid var(--ds-border);
        border-radius: 999px;
        padding: 4px 12px;
      }
      .ds-col-chip em {
        font-style: normal;
        color: var(--ds-muted);
        font-size: 0.6875rem;
        margin-left: 5px;
      }
      .ds-table-scroll {
        flex: 1;
        min-height: 0;
        overflow: auto;
        border: 1px solid var(--ds-border);
        border-radius: 12px;
        background: var(--ds-surface);
      }
      table {
        border-collapse: collapse;
        width: 100%;
        font-size: 0.8125rem;
      }
      th,
      td {
        text-align: left;
        padding: 8px 14px;
        border-bottom: 1px solid var(--ds-border);
        white-space: nowrap;
      }
      th {
        position: sticky;
        top: 0;
        z-index: 1;
        background: var(--ds-surface);
        font-weight: 600;
        font-size: 0.6875rem;
        text-transform: uppercase;
        letter-spacing: 0.05em;
        color: var(--ds-muted);
      }
      td {
        font-variant-numeric: tabular-nums;
      }
      th.num,
      td.num {
        text-align: right;
      }
      tbody tr:nth-child(even) {
        background: rgba(255, 255, 255, 0.02);
      }
      tbody tr:hover {
        background: rgba(91, 143, 249, 0.07);
      }
      .ds-empty {
        color: var(--ds-muted);
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
      <div class='dse-meta'>
        <span
          class='dse-badge {{this.provenance}}'
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
      </div>
      {{#if this.rows.length}}
        <div class='dse-scroll'>
          <table>
            <thead>
              <tr>
                {{#each this.columns as |col|}}
                  <th class={{if (isNumberCol col) 'num'}}>{{col.name}}</th>
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
        padding: 12px 16px;
        font-size: 0.8125rem;
        display: flex;
        flex-direction: column;
        gap: 8px;
        height: 100%;
      }
      .dse-meta {
        display: flex;
        align-items: center;
        gap: 10px;
        flex-wrap: wrap;
      }
      .dse-badge {
        font-size: 0.625rem;
        font-weight: 650;
        letter-spacing: 0.06em;
        text-transform: uppercase;
        padding: 2px 8px;
        border-radius: 999px;
        border: 1px solid;
      }
      .dse-badge.web {
        color: #4d82d6;
        border-color: rgba(77, 130, 214, 0.45);
      }
      .dse-badge.ai {
        color: #b08a2e;
        border-color: rgba(176, 138, 46, 0.45);
      }
      .dse-badge.file {
        color: #3e9e6b;
        border-color: rgba(62, 158, 107, 0.45);
      }
      .dse-badge.none {
        color: inherit;
        opacity: 0.55;
        border-color: currentColor;
      }
      .dse-count {
        opacity: 0.65;
        font-size: 0.75rem;
        font-variant-numeric: tabular-nums;
      }
      .dse-source {
        font-size: 0.75rem;
        color: inherit;
        opacity: 0.75;
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
        padding: 5px 10px;
        border-bottom: 1px solid rgba(128, 128, 128, 0.25);
        white-space: nowrap;
      }
      th {
        font-weight: 600;
        font-size: 0.6875rem;
        text-transform: uppercase;
        letter-spacing: 0.03em;
        opacity: 0.7;
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
        font-size: 0.6875rem;
        opacity: 0.55;
      }
      .dse-empty {
        opacity: 0.55;
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
    get hasLinkedTheme(): boolean {
      return Boolean(this.args.model?.cardInfo?.theme);
    }
    get rows(): any[] {
      return parseRows(this.args.model?.rowsJson);
    }
    get columns(): DatasetColumn[] {
      return parseColumns(this.args.model?.columnsJson).slice(0, 3);
    }
    get provenance(): string {
      return provenanceKind(this.args.model?.sourceNote);
    }
    get provenanceLabel(): string {
      return PROVENANCE_LABELS[this.provenance];
    }
    <template>
      <article class='fit {{unless this.hasLinkedTheme "gu-default-theme"}}'>
        <div class='r-head'>
          <p class='eyebrow {{this.provenance}}'>{{this.provenanceLabel}}</p>
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
          <span>{{this.columns.length}} columns</span>
        </div>
      </article>
      <style scoped>
        .gu-default-theme {
          --background: #0f1217;
          --foreground: #e8ecf1;
          --card: #171c24;
          --card-foreground: #e8ecf1;
          --primary: #5b8ff9;
          --primary-foreground: #0f1217;
          --secondary: #7ed9a6;
          --secondary-foreground: #0f1217;
          --accent: #f2cf7e;
          --accent-foreground: #0f1217;
          --muted: #1c2330;
          --muted-foreground: #93a0b4;
          --destructive: #c25668;
          --destructive-foreground: #0f1217;
          --border: rgba(255, 255, 255, 0.09);
          --input: rgba(255, 255, 255, 0.09);
          --ring: #5b8ff9;
        }
        .fit {
          --gu-bg: var(--gen-ui-bg, var(--background, #0f1217));
          --gu-surface: var(--gen-ui-surface, var(--card, #171c24));
          --gu-border: var(
            --gen-ui-border,
            var(--border, rgba(255, 255, 255, 0.09))
          );
          --gu-text: var(--gen-ui-ink, var(--foreground, #e8ecf1));
          --gu-muted: var(--gen-ui-muted, var(--muted-foreground, #93a0b4));

          --ar: calc(max(1cqi, 1cqb) - min(1cqi, 1cqb));
          --type-ratio: 1.25;
          --type-base: clamp(
            10px,
            calc(3px + 2.2cqi + 1cqb - 0.6 * var(--ar)),
            18px
          );
          --fit-meta-size: max(8px, calc(var(--type-base) / var(--type-ratio)));
          --fit-eyebrow-size: max(
            7px,
            calc(var(--type-base) / pow(var(--type-ratio), 2))
          );
          --fit-headline-size: max(
            11px,
            calc(var(--type-base) * pow(var(--type-ratio), 1.5))
          );
          --fit-pad: clamp(6px, calc(2px + 2cqi), 16px);
          --fit-gap: clamp(3px, calc(1px + 1.2cqi), 10px);

          width: 100%;
          height: 100%;
          display: grid;
          grid-template-rows: auto minmax(0, 1fr) auto;
          grid-template-areas: 'head' 'table' 'meta';
          gap: var(--fit-gap);
          padding: var(--fit-pad);
          background: var(--gu-bg);
          color: var(--gu-text);
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
          color: var(--gu-muted);
        }
        .eyebrow.web {
          color: #7db4ff;
        }
        .eyebrow.ai {
          color: #f2cf7e;
        }
        .eyebrow.file {
          color: #7ed9a6;
        }
        .title {
          margin: 2px 0 0;
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
          background: var(--gu-surface);
          border: 1px solid var(--gu-border);
          border-radius: 6px;
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
          color: var(--gu-muted);
          border-bottom: 1px solid var(--gu-border);
          padding-bottom: 3px;
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
          gap: 3px;
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
          height: max(3px, 6cqb);
          max-height: 8px;
          border-radius: 2px;
          background: rgba(255, 255, 255, 0.08);
          flex-shrink: 0;
        }
        .r-meta {
          display: flex;
          gap: 5px;
          font-size: var(--fit-meta-size);
          color: var(--gu-muted);
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
            grid-template-columns: minmax(0, 1fr) minmax(64px, 24cqw);
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
