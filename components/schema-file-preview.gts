import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { htmlSafe } from '@ember/template';
import { fn } from '@ember/helper';
import { gt, eq } from '@cardstack/boxel-ui/helpers';
import { guidFor } from '@ember/object/internals';
import { Button } from '@cardstack/pretui/components/button';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { SearchInput } from '@cardstack/pretui/components/search-input';
import { Table } from '@cardstack/pretui/components/table';
import { Token } from '@cardstack/pretui/components/token';

import {
  COMPACT_EMPTY_STYLE,
  ID_TOKEN_STYLE,
} from '@cardstack/catalog/components/pretui-helpers';

import {
  isMeasured,
  type SchemaFieldSummaryField,
} from '../fields/schema-field-summary/schema-field-summary-field';

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
  titleId = `${guidFor(this)}-title`;
  searchId = `${guidFor(this)}-search`;

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
    return htmlSafe(`padding-inline-start:${d * 0.875}rem`);
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
          <h3 id={{this.titleId}}>{{if @title @title 'Schema'}}</h3>
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
          <Token style={{ID_TOKEN_STYLE.sm}}>{{@rootType}}</Token>
        {{/if}}
      </header>

      {{#if @searchable}}
        <div class='schema-search'>
          <label class='visually-hidden' for={{this.searchId}}>Search schema
            fields</label>
          <SearchInput
            @controlId={{this.searchId}}
            @value={{this.search}}
            @onInput={{this.setSearch}}
            @placeholder='Search fields'
          />
        </div>
      {{/if}}

      {{#if this.isEmpty}}
        <EmptyState
          @title={{this.emptyMessage}}
          @texture={{false}}
          role='status'
          style={{COMPACT_EMPTY_STYLE}}
        />
      {{else}}
        <Table class='schema-table' @labelledBy={{this.titleId}}>
          <:head>
            <tr>
              <th scope='col'>Field</th>
              <th scope='col'>Type</th>
              <th scope='col' class='num'>Present</th>
            </tr>
          </:head>
          <:body>
            {{#each this.rows key='path' as |f|}}
              <tr class='{{if f.required "req"}}'>
                <td class='fieldcell'>
                  <span class='fieldname-wrap' style={{this.indentFor f}}>
                    {{#if @onSelectField}}
                      <Button
                        @appearance='link'
                        @size='s'
                        title={{f.path}}
                        {{on 'click' (fn this.select f)}}
                      ><span class='fieldname'>{{if f.name f.name f.path}}{{#if
                            f.isArray
                          }}<span class='arr'>[]</span>{{/if}}</span></Button>
                    {{else}}
                      <span class='fieldname' title={{f.path}}>{{if
                          f.name
                          f.name
                          f.path
                        }}{{#if f.isArray}}<span
                            class='arr'
                          >[]</span>{{/if}}</span>
                    {{/if}}
                  </span>
                  {{#if f.description}}
                    <span class='desc'>{{f.description}}</span>
                  {{/if}}
                  {{#if f.hasEnum}}
                    <span class='enums'>
                      {{#each f.enumValues as |v|}}
                        <Token style={{ID_TOKEN_STYLE.xs}}>{{v}}</Token>
                      {{/each}}
                    </span>
                  {{/if}}
                </td>
                <td class='typecell'>{{f.typeLabel}}</td>
                <td class='num'>
                  {{#if (isMeasured f.fillRate)}}
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
          </:body>
        </Table>
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
        background: var(--background);
        color: var(--foreground);
        border: 1px solid var(--border);
        border-radius: var(--radius);
      }
      .schema-head {
        display: flex;
        align-items: flex-start;
        justify-content: space-between;
        gap: var(--boxel-sp-xs);
        flex-wrap: wrap;
      }
      .schema-head h3 {
        font-size: var(--boxel-font-size-sm);
        font-weight: 600;
      }
      .schema-sub {
        margin: 0.125rem 0 0;
        font-size: var(--boxel-font-size-xs);
        font-variant-numeric: tabular-nums;
        color: var(--muted-foreground);
      }
      .visually-hidden {
        position: absolute;
        width: 1px;
        height: 1px;
        overflow: hidden;
        clip-path: inset(50%);
        white-space: nowrap;
      }
      .fieldname-wrap {
        display: inline-block;
      }
      .fieldname {
        font-family: var(--font-mono);
      }
      /* Required is carried by weight rather than a badge column: a whole
         column spent on a boolean is a column not spent on the schema. */
      .req .fieldname {
        font-weight: 600;
      }
      .arr {
        color: var(--muted-foreground);
      }
      .desc {
        display: block;
        margin-top: 0.125rem;
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
        max-width: 52ch;
      }
      .enums {
        display: flex;
        flex-wrap: wrap;
        gap: 0.1875rem;
        margin-top: 0.25rem;
      }
      .typecell {
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
        white-space: nowrap;
      }
      .num {
        text-align: end;
        white-space: nowrap;
        font-variant-numeric: tabular-nums;
      }
      .bar {
        display: inline-block;
        width: 2.875rem;
        height: 0.3125rem;
        border-radius: 0.1875rem;
        background: var(--muted);
        overflow: hidden;
        vertical-align: middle;
        margin-inline-end: var(--boxel-sp-xxxs);
      }
      .fill {
        display: block;
        height: 100%;
        background: color-mix(in oklch, var(--primary) 55%, var(--foreground));
      }
      .pct {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
      .unmeasured {
        color: var(--muted-foreground);
      }
    </style>
  </template>
}

export default SchemaFilePreview;
