import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { htmlSafe } from '@ember/template';
import { fn } from '@ember/helper';
import { gt, eq } from '@cardstack/boxel-ui/helpers';
import { BoxelInput, Pill } from '@cardstack/boxel-ui/components';

import type { SchemaFieldSummaryField } from '../fields/schema-field-summary/schema-field-summary-field';

interface SchemaFilePreviewSignature {
  Args: {
    fields: SchemaFieldSummaryField[];
    title?: string;
    // The document's own root type, when the file declared one.
    rootType?: string;
    searchable?: boolean;
    // Hide fields no sampled record actually carried. Off by default: a
    // declared-but-never-present field is a finding, not noise.
    hideEmpty?: boolean;
    onSelectField?: (field: SchemaFieldSummaryField) => void;
  };
  Element: HTMLElement;
}

/**
 * A schema, read as a list of fields.
 *
 * The reader is someone who opened a data file and needs to know what is in
 * it. So the table leads with **path, type, and whether it is required** —
 * the three facts that answer "can I rely on this key" — and treats the
 * description as supporting text rather than the headline.
 *
 * ### Nesting is shown by indent, not by a tree
 *
 * A collapsible tree makes the reader click to find out whether a field
 * exists. Indentation derived from `depth` shows the whole shape at rest,
 * which is what a preview is for. Deep schemas scroll; they do not fold.
 *
 * ### Fill rate is drawn, not printed
 *
 * A percentage in a column is a number the eye has to parse one row at a
 * time. A bar makes "this key is usually missing" visible while scanning, and
 * the number stays beside it for anyone who needs the exact figure.
 *
 * A field with **no** sampling is not drawn as an empty bar — an unmeasured
 * field and a never-present one must not look the same.
 */
export class SchemaFilePreview extends GlimmerComponent<SchemaFilePreviewSignature> {
  @tracked search = '';

  get rows(): SchemaFieldSummaryField[] {
    let list = (this.args.fields ?? []).filter(Boolean);
    if (this.args.hideEmpty) {
      list = list.filter((f) => f.fillRate == null || f.fillRate > 0);
    }
    let needle = this.search.trim().toLowerCase();
    if (!needle) {
      return list;
    }
    return list.filter((f) =>
      [f.path, f.name, f.type, f.description]
        .filter(Boolean)
        .some((v) => v!.toLowerCase().includes(needle)),
    );
  }

  get requiredCount(): number {
    return (this.args.fields ?? []).filter((f) => f?.required).length;
  }

  get isEmpty(): boolean {
    return this.rows.length === 0;
  }

  get emptyMessage(): string {
    if (this.search.trim()) {
      return `No field matches “${this.search.trim()}”`;
    }
    return 'This file declares no fields';
  }

  // Capped: past four levels the indent stops buying clarity and starts
  // eating the column.
  indentFor = (f: SchemaFieldSummaryField) => {
    let d = Math.min(f.depth ?? 0, 4);
    return htmlSafe(`padding-left:${d * 14}px`);
  };

  fillStyle = (f: SchemaFieldSummaryField) => {
    return htmlSafe(`width:${Math.min(100, Math.max(0, f.fillRate ?? 0))}%`);
  };

  setSearch = (v: string) => {
    this.search = v;
  };

  select = (f: SchemaFieldSummaryField) => {
    this.args.onSelectField?.(f);
  };

  <template>
    <section
      class='schema'
      aria-label={{if @title @title 'Schema'}}
      ...attributes
    >
      <header class='schema-head'>
        <div class='schema-heading'>
          <h3>{{if @title @title 'Schema'}}</h3>
          <p class='schema-sub'>
            {{this.rows.length}}
            {{if (eq this.rows.length 1) 'field' 'fields'}}
            {{#if (gt this.requiredCount 0)}}
              ·
              {{this.requiredCount}}
              required
            {{/if}}
          </p>
        </div>
        {{#if @rootType}}
          <Pill class='root-type'>{{@rootType}}</Pill>
        {{/if}}
      </header>

      {{#if @searchable}}
        <div class='schema-search'>
          <BoxelInput
            @type='search'
            @value={{this.search}}
            @onInput={{this.setSearch}}
            @placeholder='Search fields'
            aria-label='Search schema fields'
          />
        </div>
      {{/if}}

      {{#if this.isEmpty}}
        <p class='schema-empty' role='status'>{{this.emptyMessage}}</p>
      {{else}}
        <div class='table-wrap'>
          <table class='schema-table'>
            <thead>
              <tr>
                <th scope='col'>Field</th>
                <th scope='col'>Type</th>
                <th scope='col' class='num'>Present</th>
              </tr>
            </thead>
            <tbody>
              {{#each this.rows key='path' as |f|}}
                <tr class='{{if f.required "req"}}'>
                  <td class='fieldcell'>
                    <button
                      type='button'
                      class='fieldname'
                      style={{this.indentFor f}}
                      title={{f.path}}
                      {{on 'click' (fn this.select f)}}
                    >
                      {{if f.name f.name f.path}}
                      {{#if f.isArray}}<span class='arr'>[]</span>{{/if}}
                    </button>
                    {{#if f.description}}
                      <span class='desc'>{{f.description}}</span>
                    {{/if}}
                    {{#if f.hasEnum}}
                      <span class='enums'>
                        {{#each f.enumValues as |v|}}
                          <span class='enumv'>{{v}}</span>
                        {{/each}}
                      </span>
                    {{/if}}
                  </td>
                  <td class='typecell'>{{f.typeLabel}}</td>
                  <td class='num'>
                    {{#if f.fillRate}}
                      <span class='bar' aria-hidden='true'>
                        <span class='fill' style={{this.fillStyle f}}></span>
                      </span>
                      <span class='pct'>{{f.fillRate}}%</span>
                    {{else}}
                      <span class='unmeasured' title='Not sampled'>—</span>
                    {{/if}}
                  </td>
                </tr>
              {{/each}}
            </tbody>
          </table>
        </div>
      {{/if}}
    </section>

    <style scoped>
      .schema {
        container-type: inline-size;
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-sm);
        min-width: 0;
        padding: var(--boxel-sp);
        background: var(--background, var(--boxel-light));
        color: var(--foreground, var(--boxel-dark));
        border: 1px solid var(--border, var(--boxel-200));
        border-radius: var(--radius, var(--boxel-border-radius));
      }
      .schema-head {
        display: flex;
        align-items: flex-start;
        justify-content: space-between;
        gap: var(--boxel-sp-xs);
        flex-wrap: wrap;
      }
      .schema-head h3 {
        margin: 0;
        font: 600 var(--boxel-font-sm);
      }
      .schema-sub {
        margin: 2px 0 0;
        font: var(--boxel-font-xs);
        font-variant-numeric: tabular-nums;
        color: var(--muted-foreground, var(--boxel-450));
      }
      .root-type {
        --pill-font-color: var(--muted-foreground, var(--boxel-450));
        font-family: var(--font-mono, monospace);
      }
      .schema-empty {
        margin: 0;
        padding: var(--boxel-sp) 0;
        text-align: center;
        font: var(--boxel-font-sm);
        color: var(--muted-foreground, var(--boxel-450));
      }
      /* The table is the one thing allowed to exceed the container. */
      .table-wrap {
        overflow-x: auto;
      }
      .schema-table {
        width: 100%;
        border-collapse: collapse;
        font: var(--boxel-font-sm);
      }
      .schema-table th {
        text-align: left;
        font: 600 var(--boxel-font-xs);
        text-transform: uppercase;
        letter-spacing: var(--boxel-lsp-lg);
        color: var(--muted-foreground, var(--boxel-450));
        padding: var(--boxel-sp-xxxs) var(--boxel-sp-xxs);
        border-bottom: 1px solid var(--border, var(--boxel-200));
      }
      .schema-table td {
        padding: var(--boxel-sp-xxs);
        border-bottom: 1px solid var(--border, var(--boxel-100));
        vertical-align: top;
      }
      .schema-table tr:last-child td {
        border-bottom: 0;
      }
      .schema-table tbody tr:hover {
        background: var(--muted, var(--boxel-100));
      }
      .fieldname {
        display: inline-block;
        font-family: var(--font-mono, monospace);
        font-size: 0.92em;
        color: inherit;
        background: none;
        border: 0;
        text-align: left;
        cursor: pointer;
      }
      .fieldname:focus-visible {
        outline: 2px solid var(--ring, var(--boxel-highlight));
        outline-offset: 1px;
        border-radius: 2px;
      }
      /* Required is carried by weight rather than a badge column: a whole
         column spent on a boolean is a column not spent on the schema. */
      .req .fieldname {
        font-weight: 600;
      }
      .arr {
        color: var(--muted-foreground, var(--boxel-450));
      }
      .desc {
        display: block;
        margin-top: 2px;
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground, var(--boxel-450));
        max-width: 52ch;
      }
      .enums {
        display: flex;
        flex-wrap: wrap;
        gap: 3px;
        margin-top: 4px;
      }
      .enumv {
        font-family: var(--font-mono, monospace);
        font-size: var(--boxel-font-size-xs);
        padding: 1px 5px;
        border-radius: var(--radius-sm, 3px);
        background: var(--muted, var(--boxel-100));
        color: var(--muted-foreground, var(--boxel-450));
      }
      .typecell {
        font-family: var(--font-mono, monospace);
        font-size: 0.88em;
        color: var(--muted-foreground, var(--boxel-450));
        white-space: nowrap;
      }
      .num {
        text-align: right;
        white-space: nowrap;
        font-variant-numeric: tabular-nums;
      }
      .bar {
        display: inline-block;
        width: 46px;
        height: 5px;
        border-radius: 3px;
        background: var(--muted, var(--boxel-100));
        overflow: hidden;
        vertical-align: middle;
        margin-right: var(--boxel-sp-xxxs);
      }
      .fill {
        display: block;
        height: 100%;
        background: color-mix(
          in oklch,
          var(--primary, var(--boxel-highlight)) 55%,
          var(--foreground, var(--boxel-dark))
        );
      }
      .pct {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground, var(--boxel-450));
      }
      .unmeasured {
        color: var(--muted-foreground, var(--boxel-450));
      }
      /* Narrow: the bar goes, the number stays. A 46px track at phone width
         is decoration; the figure is still the fact. */
      @container (width < 420px) {
        .bar {
          display: none;
        }
        .desc {
          display: none;
        }
      }
    </style>
  </template>
}

export default SchemaFilePreview;
