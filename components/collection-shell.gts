import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { tracked } from '@glimmer/tracking';
import { debounce } from 'lodash-es';
import {
  type Query,
  type SearchEntryWireQuery,
  searchEntryWireQueryFromQuery,
} from '@cardstack/runtime-common';
import PlusIcon from '@cardstack/boxel-icons/plus';
import ChevronRightIcon from '@cardstack/boxel-icons/chevron-right';

import { Table, type TableColumn } from '@cardstack/catalog/components/table';
import { Button } from '@cardstack/pretui/components/button';
import { Input } from '@cardstack/pretui/components/input';
import { SegmentedControl } from '@cardstack/pretui/components/segmented-control';

export interface CollectionBadge {
  id: string;
  label: string;
  count: number;
  /** Field path + value that this badge filters on (omit for 'all'). */
  field?: string;
  value?: string;
}

export type CollectionView = 'grid' | 'list' | 'table';

interface Signature {
  Args: {
    /** Plural noun for the hero count and the empty state, e.g. "learners". */
    noun: string;
    /** Singular noun for the Add button, e.g. "Learner". */
    singular: string;
    /** The type codeRef this collection is made of. */
    cardTypeRef?: { module: string; name: string };
    /** Resolved instances (the live query's `.instances`) — feeds counts and the table. */
    items: any[];
    realms: string[];
    context?: any;
    badges: CollectionBadge[];
    columns: TableColumn[];
    onOpen: (card: any) => void;
    onAdd?: () => void;
    /** Extra sort for the prerendered views. */
    sort?: Query['sort'];
    /** Slot name for the table's custom cell rendering. */
  };
  Blocks: {
    cell: [any, TableColumn];
  };
  Element: HTMLElement;
}

/**
 * The academy's collection shell — the boxel-search-with-filter *concept*
 * (live query, one toolbar, badges with All first, grid/list/table sharing a
 * row set, +Add, visibly-clickable rows) in this kit's own clothes: a
 * "lens strip" that leads with the count as a hero figure, a search field
 * with the magnifier, segmented status badges, and the view switcher on the
 * right. Grid and list are prerendered fitted through the host's search
 * results component (click-to-open comes with it); the table is the shared
 * Table block with a chevron cue and viewCard on the row.
 *
 * The wire query and the client-side table filter are deliberate mirrors of
 * each other: toggling views must never change which rows are present.
 */
export class CollectionShell extends GlimmerComponent<Signature> {
  @tracked search = '';
  @tracked typed = '';
  @tracked badge = 'all';
  @tracked view: CollectionView = 'list';

  private commit = debounce((v: string) => (this.search = v), 250);
  setSearch = (v: string) => {
    this.typed = v;
    this.commit(v);
  };
  clearSearch = () => {
    this.typed = '';
    this.search = '';
  };
  setBadge = (id: string) => (this.badge = id);
  setView = (id: string) => (this.view = id as CollectionView);
  isBadge = (id: string) => this.badge === id;

  viewOptions = [
    { value: 'grid', label: 'Grid' },
    { value: 'list', label: 'List' },
    { value: 'table', label: 'Table' },
  ];

  get activeBadge(): CollectionBadge | undefined {
    return this.args.badges.find((b) => b.id === this.badge);
  }

  /** Wire filter: type AND (matches OR title contains) AND badge eq. */
  get filter(): any {
    let ref = this.args.cardTypeRef;
    if (!ref) return undefined;
    let every: any[] = [{ type: ref }];
    let q = this.search.trim();
    if (q)
      every.push({ any: [{ matches: q }, { contains: { cardTitle: q } }] });
    let b = this.activeBadge;
    if (b?.field && b.value != null) every.push({ eq: { [b.field]: b.value } });
    return every.length === 1 ? every[0] : { every };
  }

  wireQuery = (format: 'fitted'): SearchEntryWireQuery | undefined => {
    let filter = this.filter;
    if (!filter || !this.args.realms?.length) return undefined;
    let q = searchEntryWireQueryFromQuery({ filter, sort: this.args.sort });
    return {
      ...q,
      realms: this.args.realms,
      filter: {
        ...q.filter,
        eq: { ...q.filter?.eq, htmlQuery: { eq: { format } } },
      },
    } as SearchEntryWireQuery;
  };

  get gridQuery() {
    return this.wireQuery('fitted');
  }

  /** Client-side mirror of `filter` for the table and the counts. */
  get filteredItems(): any[] {
    let q = this.search.trim().toLowerCase();
    let b = this.activeBadge;
    return (this.args.items ?? []).filter((c) => {
      if (!c) return false;
      let badgeOk = !b?.field || (c[b.field] ?? '') === b.value;
      let textOk =
        !q ||
        JSON.stringify(c.cardTitle ?? '')
          .toLowerCase()
          .includes(q) ||
        Object.values(c).some(
          (v) => typeof v === 'string' && v.toLowerCase().includes(q),
        );
      return badgeOk && textOk;
    });
  }

  get total() {
    return (this.args.items ?? []).filter(Boolean).length;
  }
  get shown() {
    return this.filteredItems.length;
  }
  get isFiltered() {
    return this.badge !== 'all' || !!this.search.trim();
  }

  /**
   * The prerendered entry carries no click behaviour of its own (the base
   * CardList puts the handler on its <li>), so the tile does the same:
   * resolve the entry back to the loaded instance and hand it to @onOpen.
   */
  openEntry = (entryId: string, ev?: Event) => {
    ev?.preventDefault();
    let id = stripJson(entryId);
    let card = (this.args.items ?? []).find((c) => c && stripJson(c.id) === id);
    this.args.onOpen(card ?? new URL(entryId));
  };
  onTileKey = (entryId: string, ev: KeyboardEvent) => {
    if (ev.key === 'Enter' || ev.key === ' ') this.openEntry(entryId, ev);
  };

  get tableColumns(): TableColumn[] {
    return [
      ...this.args.columns,
      {
        key: '__open',
        label: '',
        width: '2.5rem',
        custom: true,
        sortable: false,
      },
    ];
  }

  <template>
    <section class='coll' ...attributes>
      <header class='lens'>
        <div class='hero'>
          <span class='hero-n'>{{this.shown}}</span>
          <span class='hero-l'>{{if
              this.isFiltered
              (concat 'of ' this.total ' ' @noun)
              @noun
            }}</span>
        </div>
        <div class='search'>
          <Input
            @type='search'
            @value={{this.typed}}
            @onInput={{this.setSearch}}
            @placeholder='Search {{@noun}}…'
            autocomplete='off'
            aria-label='Search {{@noun}}'
          />
        </div>
        <div class='badges' role='group' aria-label='Filter {{@noun}}'>
          {{#each @badges as |b|}}
            <button
              type='button'
              class='badge
                {{if (this.isBadge b.id) "on"}}
                {{if (isZero b.count) "zero"}}'
              aria-pressed={{if (this.isBadge b.id) 'true' 'false'}}
              {{on 'click' (fn this.setBadge b.id)}}
            >
              <span class='b-l'>{{b.label}}</span><span
                class='b-n'
              >{{b.count}}</span>
            </button>
          {{/each}}
        </div>
        <div class='right'>
          <SegmentedControl
            @options={{this.viewOptions}}
            @value={{this.view}}
            @onValueChange={{this.setView}}
          />
          {{#if @onAdd}}
            <Button
              class='add'
              @tone='primary'
@appearance='accent'
              @size='s'
              {{on 'click' @onAdd}}
            >
              <PlusIcon width='16' height='16' role='presentation' />
              Add
              {{@singular}}
            </Button>
          {{/if}}
        </div>
      </header>

      {{#if (eq this.view 'table')}}
        <div class='table-wrap'>
          <Table
            @items={{this.filteredItems}}
            @columns={{this.tableColumns}}
            @onRowClick={{@onOpen}}
            @caption={{@noun}}
            @emptyMessage={{emptyMsg @noun this.isFiltered}}
            @pageSize={{25}}
            class='tbl'
          >
            <:cell as |c col|>
              {{#if (eq col.key '__open')}}
                <span class='open-cue' aria-hidden='true'><ChevronRightIcon
                    width='16'
                    height='16'
                  /></span>
              {{else}}
                {{yield c col to='cell'}}
              {{/if}}
            </:cell>
          </Table>
        </div>
      {{else}}
        {{#if this.gridQuery}}
          {{#let
            (component @context.searchResultsComponent)
            as |SearchResults|
          }}
            <SearchResults @query={{this.gridQuery}} as |results|>
              {{#if results.isLoading}}
                <p class='state'>Loading {{@noun}}…</p>
              {{else if results.entries.length}}
                <ul class='cards {{this.view}}'>
                  {{#each results.entries key='id' as |entry|}}
                    <li
                      class='tile'
                      role='button'
                      tabindex='0'
                      aria-label='Open {{@singular}}'
                      {{on 'click' (fn this.openEntry entry.id)}}
                      {{on 'keydown' (fn this.onTileKey entry.id)}}
                    ><entry.component class='tile-card' /></li>
                  {{/each}}
                </ul>
              {{else}}
                <p class='state empty'>{{emptyMsg @noun this.isFiltered}}</p>
              {{/if}}
            </SearchResults>
          {{/let}}
        {{else}}
          <p class='state'>Nothing to show here yet.</p>
        {{/if}}
      {{/if}}
    </section>
    <style scoped>
      .coll {
        --coll-accent: var(--primary);
        container-type: inline-size;
        container-name: coll;
        display: grid;
        gap: var(--boxel-sp);
        min-width: 0;
        max-width: 100%;
        color: var(--foreground);
      }
      .lens {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-sm);
        /* wrapping is the overflow guard: the row never grows past the shell */
        flex-wrap: wrap;
        min-width: 0;
        padding: var(--boxel-sp-sm) var(--boxel-sp);
        border: 1px solid var(--border);
        border-left: 4px solid var(--coll-accent);
        border-radius: var(--radius);
        background: var(--card);
      }
      .hero {
        display: flex;
        align-items: baseline;
        gap: var(--boxel-sp-4xs);
        flex: 0 0 auto;
        min-width: 7rem;
      }
      .hero-n {
        font: 800 1.75rem / 1 var(--font-heading);
        font-variant-numeric: tabular-nums;
      }
      .hero-l {
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground);
        white-space: nowrap;
      }
      .search {
        flex: 0 1 22rem;
        min-width: 8rem;
      }
      .search :deep(.search) {
        --boxel-input-search-background-color: var(--background);
        --boxel-input-search-color: var(--foreground);
      }
      .search :deep(.search-icon) {
        --boxel-input-search-icon-color: var(--muted-foreground);
      }
      .badges {
        display: flex;
        flex-wrap: wrap;
        gap: 2px;
        flex: 0 1 auto;
        min-width: 0;
        padding: 2px;
        border-radius: var(--radius);
        background: var(--muted);
      }
      .badge {
        display: inline-flex;
        align-items: center;
        gap: var(--boxel-sp-4xs);
        min-height: 32px;
        padding: 0 var(--boxel-sp-sm);
        border: 0;
        border-radius: 999px;
        background: transparent;
        color: var(--muted-foreground);
        font: 600 var(--boxel-font-size-sm) inherit;
        white-space: nowrap;
        cursor: pointer;
      }
      .badge.on {
        background: var(--card);
        color: var(--foreground);
        box-shadow: 0 1px 2px
          color-mix(
            in oklab,
            var(--foreground) 12%,
            transparent
          );
      }
      .badge.zero:not(.on) {
        opacity: 0.55;
      }
      .badge:focus-visible {
        outline: 2px solid var(--ring);
        outline-offset: 1px;
      }
      .b-n {
        font-size: var(--boxel-font-size-xs);
        font-variant-numeric: tabular-nums;
        padding: 0 5px;
        border-radius: 999px;
        background: color-mix(
          in oklab,
          var(--foreground) 8%,
          transparent
        );
      }
      .badge.on .b-n {
        background: color-mix(
          in oklab,
          var(--coll-accent) 18%,
          var(--card)
        );
      }
      .right {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-sm);
        flex: 0 0 auto;
        margin-left: auto;
      }
      .add {
        min-height: 36px;
        gap: var(--boxel-sp-4xs);
      }
      .cards {
        list-style: none;
        margin: 0;
        padding: 0;
        display: grid;
        gap: var(--boxel-sp-sm);
      }
      .cards.grid {
        grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
      }
      .cards.grid .tile {
        height: 180px;
      }
      .cards.list .tile {
        height: 78px;
      }
      .tile {
        position: relative;
        cursor: pointer;
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
        overflow: hidden;
        transition:
          border-color 120ms ease-out,
          box-shadow 120ms ease-out,
          transform 120ms ease-out;
      }
      .tile::after {
        /* the static open cue: a chevron at the trailing edge */
        content: '›';
        position: absolute;
        right: var(--boxel-sp-xs);
        top: 50%;
        transform: translateY(-50%);
        font-size: 1.1rem;
        line-height: 1;
        color: var(--muted-foreground);
        pointer-events: none;
      }
      .cards.grid .tile::after {
        top: auto;
        bottom: var(--boxel-sp-xs);
        transform: none;
      }
      .tile:focus-visible {
        outline: 2px solid var(--ring);
        outline-offset: 2px;
      }
      .tile:hover,
      .tile:focus-within {
        border-color: var(--coll-accent);
        box-shadow: 0 6px 18px -12px
          color-mix(
            in oklab,
            var(--foreground) 40%,
            transparent
          );
      }
      .tile-card {
        display: block;
        height: 100%;
        cursor: pointer;
      }
      .table-wrap {
        overflow-x: auto;
      }
      .open-cue {
        color: var(--muted-foreground);
        display: inline-flex;
      }
      .state {
        margin: 0;
        padding: var(--boxel-sp);
        border: 1px dashed var(--border);
        border-radius: var(--radius);
        color: var(--muted-foreground);
        font-size: var(--boxel-font-size-sm);
      }
      .state.empty {
        font-style: italic;
      }
      @media (prefers-reduced-motion: no-preference) {
        .tile:hover {
          transform: translateY(-1px);
        }
      }
      @container coll (width < 900px) {
        .hero-l {
          display: none;
        }
      }
      @container coll (width < 560px) {
        .right {
          margin-left: 0;
          width: 100%;
          justify-content: space-between;
        }
      }
    </style>
  </template>
}

function eq(a: unknown, b: unknown) {
  return a === b;
}
function stripJson(id?: string) {
  return (id ?? '').replace(/\.json$/, '');
}
function isZero(n?: number) {
  return !n;
}
function concat(...parts: unknown[]) {
  return parts.map((p) => (p == null ? '' : String(p))).join('');
}
function emptyMsg(noun: string, filtered: boolean) {
  return filtered
    ? `No ${noun} match this search or filter.`
    : `No ${noun} yet.`;
}

export default CollectionShell;
