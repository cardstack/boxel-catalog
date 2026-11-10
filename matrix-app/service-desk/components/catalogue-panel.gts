import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { consume } from 'ember-provide-consume-context';
import { debounce } from 'lodash-es';
import PlusIcon from '@cardstack/boxel-icons/plus';
import { eq } from '@cardstack/boxel-ui/helpers';
import type {
  CardContext,
  CardCrudFunctions,
  CardDef,
} from '@cardstack/base/card-api';
import {
  identifyCard,
  searchEntryWireQueryFromQuery,
  CardCrudFunctionsContextName,
  type Query,
  type getCards,
} from '@cardstack/runtime-common';
import { Alert } from '@cardstack/pretui/components/alert';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { Button } from '@cardstack/pretui/components/button';
import { LayoutControl } from '@cardstack/pretui/components/layout-control';
import { SearchInput } from '@cardstack/pretui/components/search-input';
import { SegmentedControl } from '@cardstack/pretui/components/segmented-control';
import { DataTable } from '@cardstack/pretui/components/data-table';
import { Chip } from '@cardstack/pretui/components/chip';
import LayoutGridIcon from '@cardstack/boxel-icons/layout-grid';
import ListIcon from '@cardstack/boxel-icons/list';
import TableIcon from '@cardstack/boxel-icons/table';

export interface CatalogueColumn {
  key: string;
  label: string;
  /** Hide below this container width (px). */
  showAbove?: number;
  /** Render as status dot + text. */
  dot?: boolean;
  /** Machine value: mono, tabular. */
  mono?: boolean;
}

type View = 'grid' | 'strip' | 'table';

interface Signature {
  Args: {
    cardClass: typeof CardDef;
    context?: CardContext;
    realms: string[];
    columns: CatalogueColumn[];
    label: string;
    searchPlaceholder?: string;
    newLabel?: string;
    /** Show an avatar before the first column's value (people). */
    avatar?: boolean;
  };
  Element: HTMLElement;
}

const F = (...forms: [string, number][]) =>
  forms.map(([name, minWidth]) => ({ name, minWidth }));
const SEARCH_FORMS = F(['field', 12], ['field-s', 8], ['icon', 2], ['menu', 0]);
const VIEW_FORMS = F(['text', 14], ['icon', 7], ['menu', 0]);
const ADD_FORMS = F(['label', 8], ['icon', 2]);
const VIEWS = [
  { value: 'grid', label: 'Grid', icon: LayoutGridIcon },
  { value: 'strip', label: 'Strip', icon: ListIcon },
  { value: 'table', label: 'Table', icon: TableIcon },
];

// One catalogue tab: a ruled table (or the cards' own fitted tiles) over one
// live query, with a LayoutControl toolbar.
export class CataloguePanel extends GlimmerComponent<Signature> {
  @consume(CardCrudFunctionsContextName)
  declare cardCrudFunctions: CardCrudFunctions | undefined;

  @tracked view: View = 'table';
  @tracked search = '';
  @tracked creating = false;
  @tracked createProblem: string | undefined;
  private rowsQuery: ReturnType<getCards> | undefined;

  constructor(owner: unknown, args: Signature['Args']) {
    super(owner as never, args as never);
    this.rowsQuery = this.args.context?.getCards(
      this,
      () => this.query,
      () => this.args.realms,
      { isLive: true },
    );
  }

  willDestroy() {
    super.willDestroy();
    this.setSearchNow.cancel();
  }

  private setSearchNow = debounce((v: string) => {
    this.search = v;
  }, 250);
  setSearch = (v: string) => this.setSearchNow(v);
  setView = (v: string) => {
    this.view = v as View;
  };
  viewChoices = VIEWS.map((v) => ({
    label: v.label,
    value: v.value,
    group: 'view',
    onSelect: () => this.setView(v.value),
  }));

  get ref() {
    return identifyCard(this.args.cardClass);
  }

  get query(): Query | undefined {
    let ref = this.ref;
    if (!ref || !this.args.realms.length) return undefined;
    let text = this.search.trim();
    let filter = text
      ? {
          every: [
            { type: ref },
            { any: [{ matches: text }, { contains: { cardTitle: text } }] },
          ],
        }
      : { type: ref };
    return {
      filter,
      sort: [{ by: 'title', on: ref, direction: 'asc' }],
    } as Query;
  }

  get wireQuery() {
    let q = this.query;
    return q
      ? { ...searchEntryWireQueryFromQuery(q), realms: this.args.realms }
      : undefined;
  }

  get rows(): CardDef[] {
    return ((this.rowsQuery?.instances ?? []) as CardDef[]).filter(Boolean);
  }

  get problem(): string | undefined {
    if (this.createProblem) return this.createProblem;
    let errors = (this.rowsQuery as any)?.errors as
      | { message?: string }[]
      | undefined;
    return errors?.length
      ? (errors[0]?.message ?? 'The query could not run.')
      : undefined;
  }

  get emptyMessage() {
    return this.search.trim()
      ? `Nothing in ${this.args.label} matches “${this.search.trim()}”.`
      : `No ${this.args.label.toLowerCase()} yet.`;
  }

  get canAdd() {
    return Boolean(this.cardCrudFunctions?.createCard);
  }

  get firstKey() {
    return this.args.columns[0]?.key;
  }

  get dtColumns() {
    return this.args.columns.map((c) => ({
      key: c.key,
      label: c.label,
      mono: c.mono,
      value: (row: CardDef) => {
        let v = this.cell(row, c.key);
        return v === '' ? undefined : v;
      },
    }));
  }

  rowKey = (row: CardDef) => row.id;

  isDot = (key: string) =>
    Boolean(this.args.columns.find((c) => c.key === key)?.dot);

  // shortcut: tone from the text's leading tier/priority word; upgrade to a per-column tone map when a tab needs more.
  toneOf = (text: string) => {
    let t = text.toLowerCase();
    if (/^(p1|vip|critical|l3|draft)/.test(t)) return 'danger';
    if (/^(p2|premium|enterprise|high|l2|review)/.test(t)) return 'warning';
    if (/^(published|active|standard|l1|public)/.test(t)) return 'success';
    return 'neutral';
  };

  cell = (row: CardDef, key: string): string => {
    let v = (row as any)?.[key];
    return v == null || typeof v === 'object' ? '' : String(v);
  };

  open = (row: CardDef) => {
    (this.cardCrudFunctions as any)?.viewCard?.(row);
  };

  openEntry = (id: string) => {
    if (id) this.cardCrudFunctions?.viewCard?.(new URL(id));
  };

  create = async () => {
    let make = this.cardCrudFunctions?.createCard;
    let ref = this.ref;
    let realm = this.args.realms[0];
    if (!make || !ref || !realm) return;
    this.creating = true;
    this.createProblem = undefined;
    try {
      await make(ref, new URL(realm), { realmURL: new URL(realm) });
    } catch (e: any) {
      this.createProblem = e?.message ?? String(e);
    } finally {
      this.creating = false;
    }
  };

  <template>
    <section class='cp' aria-label={{@label}} ...attributes>
      <header class='cp-head'>
        <h2>{{@label}}</h2>
        <span class='mono'>{{this.rows.length}} rows</span>
      </header>
      <div class='cp-tools'>
        <LayoutControl
          @label='{{@label}} toolbar'
          @controlHeight='1.625rem'
          as |lc|
        >
          <lc.Slot
            @id='search'
            @priority={{1}}
            @forms={{SEARCH_FORMS}}
            @label='Search'
          >
            <div class='sbox'><SearchInput
                @value={{this.search}}
                @onInput={{this.setSearch}}
                @placeholder={{if
                  @searchPlaceholder
                  @searchPlaceholder
                  'Search…'
                }}
              /></div>
          </lc.Slot>
          <lc.Slot
            @id='view'
            @priority={{2}}
            @forms={{VIEW_FORMS}}
            @label='View'
            @menuItems={{this.viewChoices}}
            as |form|
          >
            <div class='push'><SegmentedControl
                @label='View'
                @display={{if (eq form 'icon') 'icon' 'text'}}
                @options={{VIEWS}}
                @value={{this.view}}
                @onValueChange={{this.setView}}
              /></div>
          </lc.Slot>
          {{#if this.canAdd}}
            <lc.Slot
              @id='new'
              @priority={{0}}
              @pinned={{true}}
              @forms={{ADD_FORMS}}
              @label='New {{@newLabel}}'
            >
              <Button
                @icon={{PlusIcon}}
                @tone='primary'
                @appearance='accent'
                @size='s'
                @busy={{this.creating}}
                {{on 'click' this.create}}
              >
                New
                {{@newLabel}}
              </Button>
            </lc.Slot>
          {{/if}}
        </LayoutControl>
      </div>

      {{#if this.problem}}
        <Alert
          @tone='danger'
          @title='{{@label}} could not load.'
        >{{this.problem}}</Alert>
      {{else if (eq this.view 'table')}}
        <div class='dt'>
          <DataTable
            @columns={{this.dtColumns}}
            @rows={{this.rows}}
            @key={{this.rowKey}}
            @label={{@label}}
            @flush={{true}}
            @striped={{false}}
            @size='s'
            @sortable={{false}}
            @columnMenu={{false}}
            @emptyTitle={{this.emptyMessage}}
          >
            <:cell as |text row col|>
              <span class='c'>
                {{#if (eq col.key this.firstKey)}}
                  <button
                    type='button'
                    class='first'
                    {{on 'click' (fn this.open row)}}
                  >
                    {{#if @avatar}}<Avatar
                        @name={{text}}
                        @size={{18}}
                      />{{else}}<Avatar
                        @name={{text}}
                        @shape='square'
                        @size={{18}}
                      />{{/if}}
                    <b>{{text}}</b>
                  </button>
                {{else if (this.isDot col.key)}}
                  {{#if (eq text '—')}}<span class='dim'>—</span>{{else}}<Chip
                      @appearance='plain'
                      @tone={{this.toneOf text}}
                    >{{text}}</Chip>{{/if}}
                {{else}}
                  <span
                    class='{{if (eq text "—") "dim"}} {{if col.mono "mono"}}'
                  >{{text}}</span>
                {{/if}}
              </span>
            </:cell>
          </DataTable>
        </div>
      {{else if @context.searchResultsComponent}}
        {{#let (component @context.searchResultsComponent) as |Search|}}
          <Search @query={{this.wireQuery}} @mode='none' as |results|>
            <div class='grid {{if (eq this.view "strip") "strip"}}'>
              {{#each results.entries key='id' as |entry|}}
                <div
                  class='tile'
                  role='button'
                  tabindex='0'
                  {{on 'click' (fn this.openEntry entry.id)}}
                >
                  <entry.component />
                </div>
              {{else}}
                <p class='dim note'>{{this.emptyMessage}}</p>
              {{/each}}
            </div>
          </Search>
        {{/let}}
      {{/if}}
    </section>

    <style scoped>
      .cp {
        container-type: inline-size;
        display: flex;
        flex-direction: column;
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
        overflow: hidden;
        font-family: var(--font-sans);
        font-size: var(--boxel-font-size-xs);
        color: var(--foreground);
      }
      .cp-head {
        display: flex;
        align-items: baseline;
        justify-content: space-between;
        padding: var(--boxel-sp-xs) var(--boxel-sp-xs) 0;
      }
      h2 {
        font-size: var(--boxel-font-size-xs);
        font-weight: 700;
      }
      .mono {
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-2xs);
      }
      .cp-tools {
        padding: var(--boxel-sp-2xs) var(--boxel-sp-xs);
      }
      .sbox {
        inline-size: 16rem;
        max-inline-size: 100%;
      }
      .c {
        font-size: var(--boxel-font-size-xs);
        font-family: var(--font-sans);
      }
      .push {
        margin-inline-start: auto;
      }
      .first {
        all: unset;
        cursor: pointer;
        display: inline-flex;
        align-items: center;
        gap: var(--boxel-sp-2xs);
      }
      .dim {
        color: var(--muted-foreground);
      }
      .grid {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(15rem, 1fr));
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp-xs);
      }
      .grid.strip {
        grid-template-columns: 1fr;
      }
      .tile {
        cursor: pointer;
        block-size: 6.5rem;
      }
      .strip .tile {
        block-size: 2.5rem;
      }
      .note {
        padding: var(--boxel-sp-xs);
      }
      @container (width <= 40rem) {

      }
    </style>
  </template>
}

export default CataloguePanel;
