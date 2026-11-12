import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import PlusIcon from '@cardstack/boxel-icons/plus';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { Button } from '@cardstack/pretui/components/button';
import { DataTable } from '@cardstack/pretui/components/data-table';
import { FilterChips } from '@cardstack/pretui/components/filter-chips';
import { LayoutControl } from '@cardstack/pretui/components/layout-control';
import { SearchInput } from '@cardstack/pretui/components/search-input';

// Status hues from the catalog status fields, drawn with the theme's tones.
// The dot's colour is set by a scoped `.dot[data-hue]` rule in each template.
const HUE_TONE: Record<string, string> = {
  green: 'success',
  emerald: 'success',
  amber: 'warning',
  orange: 'warning',
  yellow: 'warning',
  red: 'destructive',
  rose: 'destructive',
  blue: 'primary',
  indigo: 'primary',
};

export function dotHue(hue?: string) {
  return (hue && HUE_TONE[hue]) || 'muted';
}

export interface DeskStat {
  label: string;
  value: number | string;
  hint?: string;
  hue?: string;
}

// The joined stat strip every tab opens with.
export class StatStrip extends GlimmerComponent<{
  Args: { stats: DeskStat[]; label: string };
}> {
  <template>
    <section class='strip' aria-label={{@label}}>
      <dl class='cells'>
        {{#each @stats as |s|}}
          <div class='cell'>
            <dt class='cap'><span
                class='dot'
                data-hue={{dotHue s.hue}}
              ></span>{{s.label}}</dt>
            <dd class='val'>{{s.value}}</dd>
            {{#if s.hint}}<dd class='hint'>{{s.hint}}</dd>{{/if}}
          </div>
        {{/each}}
      </dl>
    </section>
    <style scoped>
      .strip {
        container-type: inline-size;
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
        color: var(--card-foreground);
        overflow: hidden;
      }
      /* Every cell draws its right and bottom line; the frame clips the
         overhang, so a wrapped row keeps all its dividers. */
      .cells {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(9rem, 1fr));
        margin: 0 -1px -1px 0;
      }
      .cell {
        display: grid;
        gap: var(--boxel-sp-5xs);
        align-content: start;
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        min-width: 0;
        box-shadow:
          1px 0 0 var(--border),
          0 1px 0 var(--border);
      }
      dd {
        margin: 0;
      }
      .cap {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-5xs);
        font-family: var(--font-mono);
        font-weight: 600;
        font-size: var(--boxel-font-size-2xs);
        letter-spacing: 0.13em;
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .dot {
        inline-size: 0.375rem;
        block-size: 0.375rem;
        border-radius: 50%;
        background: var(--muted-foreground);
        flex: none;
      }
      .dot[data-hue='success'] {
        background: var(--success);
      }
      .dot[data-hue='warning'] {
        background: var(--warning);
      }
      .dot[data-hue='destructive'] {
        background: var(--destructive);
      }
      .dot[data-hue='primary'] {
        background: var(--primary);
      }
      .val {
        font-size: var(--boxel-font-size-lg);
        font-weight: 700;
        font-variant-numeric: tabular-nums;
        line-height: 1.1;
      }
      .hint {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
    </style>
  </template>
}

export interface DeskColumn {
  key: string;
  label: string;
  value?: (row: any) => unknown;
  align?: 'start' | 'end';
  mono?: boolean;
  /** The row's identity cell: mark + bold name, opens the card. */
  name?: boolean;
  /** Status cell: dot + text. */
  status?: boolean;
}

const SEARCH_FORMS = [
  { name: 'field', minWidth: 14 },
  { name: 'collapsed', minWidth: 1.75 },
];
const CHIP_FORMS = [
  { name: 'chips', minWidth: 16 },
  { name: 'menu', minWidth: 0 },
];
const ADD_FORMS = [
  { name: 'label', minWidth: 7 },
  { name: 'icon', minWidth: 2 },
];

interface ListSignature {
  Args: {
    title: string;
    noun: string;
    stats: DeskStat[];
    chips?: { value: string; label: string; count?: number }[];
    chip?: string;
    onChip?: (value: string) => void;
    search: string;
    onSearch: (value: string) => void;
    newLabel?: string;
    onNew?: () => void;
    rows: any[];
    columns: DeskColumn[];
    onOpen: (row: any) => void;
    mark: string;
    avatar?: boolean;
    statusOf?: (row: any) => { label: string; hue?: string };
  };
}

// One list tab: stat strip, LayoutControl toolbar, then a ruled table block.
export class DeskList extends GlimmerComponent<ListSignature> {
  get dtColumns() {
    return this.args.columns.map((c) => ({
      key: c.key,
      label: c.label,
      align: c.align,
      mono: c.mono,
      value: (row: any) => {
        let v = c.value ? c.value(row) : row?.[c.key];
        return v == null || v === '' ? '—' : v;
      },
    }));
  }

  colOf = (key: string) => this.args.columns.find((c) => c.key === key);
  isName = (key: string) => Boolean(this.colOf(key)?.name);
  isStatus = (key: string) => Boolean(this.colOf(key)?.status);
  statusLabel = (row: any) => this.args.statusOf?.(row)?.label ?? '—';
  statusDot = (row: any) => dotHue(this.args.statusOf?.(row)?.hue);
  rowKey = (row: any) => row.id;

  <template>
    <StatStrip @stats={{@stats}} @label='{{@title}} summary' />
    <LayoutControl
      @label='{{@title}} toolbar'
      @controlHeight='1.625rem'
      as |lc|
    >
      <lc.Slot
        @id='search'
        @priority={{2}}
        @forms={{SEARCH_FORMS}}
        @label='Search'
        as |form|
      >
        <div class='search'><SearchInput
            @display={{if (eq form 'collapsed') 'collapsed' 'field'}}
            @value={{@search}}
            @placeholder='Search {{@noun}}…'
            @onInput={{@onSearch}}
          /></div>
      </lc.Slot>
      {{#if @chips}}
        <lc.Slot
          @id='filter'
          @priority={{3}}
          @forms={{CHIP_FORMS}}
          @label='Show'
        >
          <FilterChips
            @options={{@chips}}
            @value={{@chip}}
            @onValueChange={{@onChip}}
            @label='Show'
          />
        </lc.Slot>
      {{/if}}
      {{#if @onNew}}
        <lc.Slot
          @id='new'
          @priority={{0}}
          @pinned={{true}}
          @forms={{ADD_FORMS}}
          @label={{@newLabel}}
          as |form|
        >
          <div class='push'><Button
              @icon={{PlusIcon}}
              @tone='primary'
              @size='s'
              @display={{if (eq form 'icon') 'icon' 'label'}}
              @label={{@newLabel}}
              {{on 'click' @onNew}}
            >{{@newLabel}}</Button></div>
        </lc.Slot>
      {{/if}}
    </LayoutControl>
    <section class='block' aria-label={{@title}}>
      <header class='block-head'><h2>{{@title}}</h2><span
          class='count'
        >{{@rows.length}}</span></header>
      <div class='dt'>
        <DataTable
          @columns={{this.dtColumns}}
          @rows={{@rows}}
          @key={{this.rowKey}}
          @label={{@title}}
          @flush={{true}}
          @striped={{false}}
          @size='xs'
          @sortable={{false}}
          @columnMenu={{false}}
          @emptyTitle='No {{@noun}} match.'
        >
          <:cell as |text row col|>
            {{#if (this.isName col.key)}}
              <button
                type='button'
                class='name'
                {{on 'click' (fn @onOpen row)}}
              >
                {{#if @avatar}}
                  <Avatar @name={{text}} @size={{18}} />
                {{else}}
                  <span class='mark' aria-hidden='true'>{{@mark}}</span>
                {{/if}}
                <b>{{text}}</b>
              </button>
            {{else if (this.isStatus col.key)}}
              <span class='status'><span
                  class='dot'
                  data-hue={{this.statusDot row}}
                ></span>{{this.statusLabel row}}</span>
            {{else}}
              <span class={{if (eq text '—') 'dim'}}>{{text}}</span>
            {{/if}}
          </:cell>
        </DataTable>
      </div>
    </section>
    <style scoped>
      .search {
        inline-size: 14rem;
        max-inline-size: 100%;
      }
      .block {
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
        color: var(--card-foreground);
        overflow: hidden;
      }
      .block-head {
        display: flex;
        align-items: baseline;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        border-bottom: 1px solid var(--border);
      }
      h2 {
        font-size: var(--boxel-font-size-xs);
        font-weight: 700;
      }
      .count {
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
      .dt {
        overflow-x: auto;
      }
      .name {
        all: unset;
        cursor: pointer;
        display: inline-flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        min-width: 0;
      }
      .name:focus-visible {
        outline: 2px solid var(--ring);
      }
      .mark {
        display: grid;
        place-items: center;
        inline-size: 1.125rem;
        block-size: 1.125rem;
        border-radius: var(--radius);
        background: var(--muted);
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-2xs);
        font-weight: 600;
      }
      .push {
        margin-inline-start: auto;
      }
      .status {
        text-transform: capitalize;
        display: inline-flex;
        align-items: center;
        gap: var(--boxel-sp-5xs);
      }
      .dot {
        inline-size: 0.375rem;
        block-size: 0.375rem;
        border-radius: 50%;
        background: var(--muted-foreground);
      }
      .dot[data-hue='success'] {
        background: var(--success);
      }
      .dot[data-hue='warning'] {
        background: var(--warning);
      }
      .dot[data-hue='destructive'] {
        background: var(--destructive);
      }
      .dot[data-hue='primary'] {
        background: var(--primary);
      }
      .dim {
        color: var(--muted-foreground);
      }
    </style>
  </template>
}
