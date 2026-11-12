import {
  CardDef,
  Component,
  field,
  contains,
  StringField,
} from '@cardstack/base/card-api';
import {
  identifyCard,
  realmURL,
  type getCards,
} from '@cardstack/runtime-common';
import type Owner from '@ember/owner';
import { cached, tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import HouseIcon from '@cardstack/boxel-icons/house';
import PlusIcon from '@cardstack/boxel-icons/plus';
import { Button } from '@cardstack/pretui/components/button';
import {
  DataTable,
  type DataColumn,
} from '@cardstack/pretui/components/data-table';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { LayoutControl } from '@cardstack/pretui/components/layout-control';
import { SearchInput } from '@cardstack/pretui/components/search-input';
import { Select } from '@cardstack/pretui/components/select';
import {
  Sidebar,
  SidebarGroup,
  SidebarItem,
  SidebarTrigger,
} from '@cardstack/pretui/components/sidebar';
import { Stat } from '@cardstack/pretui/components/stat';

import { DotLabel } from '../hr/dot-enum-field';
import { RichFittedCard } from '../shared/rich-fitted-card';
import {
  PropertyListing,
  PROPERTY_LISTING_STATUSES,
  PROPERTY_LISTING_STATUS_HUES,
  PROPERTY_LISTING_STATUS_LABELS,
  money,
} from '../real-estate/property-listing';

const SORT_OPTIONS = [
  { value: 'newest', label: 'Newest' },
  { value: 'dom', label: 'Days on market' },
  { value: 'price', label: 'Price' },
];

const STALE_DAYS = 30;

// LayoutControl forms: `minWidth` in rem, richest first.
const F = (...forms: [string, number][]) =>
  forms.map(([name, minWidth]) => ({ name, minWidth }));
const SEARCH_FORMS = F(['field', 14], ['collapsed', 1.75]);
const SELECT_FORMS = F(['full', 8], ['menu', 0]);
const ADD_FORMS = F(['label', 7], ['icon', 2]);

type SortKey = 'newest' | 'dom' | 'price';

// A listing with no status is a draft, everywhere this app counts or filters.
function statusOf(listing: PropertyListing): string {
  return listing.status ?? 'draft';
}

function isLive(listing: PropertyListing) {
  let status = statusOf(listing);
  return status === 'published' || status === 'under-offer';
}

function publishedTime(listing: PropertyListing): number {
  let at = listing.publishedAt;
  return at ? new Date(at).getTime() : 0;
}

const COLUMNS: DataColumn<PropertyListing>[] = [
  { key: 'listing', label: 'Listing', value: (l) => l.cardTitle },
  {
    key: 'area',
    label: 'Area',
    value: (l) => [l.neighborhood, l.address?.city].filter(Boolean).join(', '),
  },
  {
    key: 'specs',
    label: 'Specs',
    mono: true,
    align: 'start',
    value: (l) =>
      [
        l.bedrooms != null ? `${l.bedrooms} bd` : null,
        l.bathrooms != null ? `${l.bathrooms} ba` : null,
        l.areaSqft != null ? `${l.areaSqft.toLocaleString('en-US')} sf` : null,
      ]
        .filter(Boolean)
        .join(' · '),
  },
  {
    key: 'asking',
    label: 'Asking',
    mono: true,
    align: 'end',
    value: (l) =>
      l.askingPrice?.amount != null
        ? money(l.askingPrice.amount, l.askingPrice.currency?.code)
        : null,
  },
  {
    key: 'days',
    label: 'Days',
    mono: true,
    align: 'end',
    value: (l) => (l.daysOnMarket != null ? `${l.daysOnMarket}d` : null),
  },
  {
    key: 'stage',
    label: 'Stage',
    value: (l) => PROPERTY_LISTING_STATUS_LABELS[statusOf(l)],
  },
];

// The listing agent's desk. Every Property Listing in the realm is read
// from one live query: the value on the market leads, the stage filter
// narrows the book, and a docked Needs attention panel names stale live
// listings and unready drafts. Rows open the listing; publishing lives on
// the listing card. Prerender gets a static shell: the book mounts only
// when the card's CRUD functions are present, which keeps indexing light.
class PropertyMarketplaceIsolated extends Component<
  typeof PropertyMarketplaceApp
> {
  @tracked statusFilter = 'all';
  @tracked sortKey: SortKey = 'newest';
  @tracked search = '';

  private listingsQuery: ReturnType<getCards> | undefined;

  constructor(owner: Owner, args: any) {
    super(owner, args);
    this.listingsQuery = this.args.context?.getCards(
      this,
      () => {
        let ref = identifyCard(PropertyListing);
        return ref ? { filter: { type: ref } } : undefined;
      },
      () => this.realms,
      { isLive: true },
    );
  }

  private get realms(): string[] | undefined {
    let url = this.args.model?.[realmURL];
    return url ? [url.href] : undefined;
  }

  // CRUD functions reach the card only in interactive contexts, so their
  // absence marks prerender, where the book must not mount.
  get isInteractive() {
    return Boolean(this.args.viewCard);
  }

  get listingCount() {
    return String(this.listings.length);
  }

  get isLoading() {
    return Boolean(this.listingsQuery?.isLoading);
  }

  get listings(): PropertyListing[] {
    return ((this.listingsQuery?.instances ?? []) as PropertyListing[]).filter(
      Boolean,
    );
  }

  @cached
  get onMarket(): PropertyListing[] {
    return this.listings.filter(isLive);
  }

  // Asking prices are summed only within one currency; a book priced in
  // several has no single value on the market.
  @cached
  get valueOnMarket(): string {
    let codes = new Set(
      this.onMarket.map((l) => l.askingPrice?.currency?.code ?? 'USD'),
    );
    if (codes.size > 1) {
      return '—';
    }
    let total = this.onMarket.reduce(
      (sum, l) => sum + (l.askingPrice?.amount ?? 0),
      0,
    );
    return money(total, [...codes][0] ?? 'USD');
  }

  get valueHint() {
    if (this.valueOnMarket === '—' && this.onMarket.length) {
      return 'priced in more than one currency';
    }
    let n = this.onMarket.length;
    return `across ${n} live ${n === 1 ? 'listing' : 'listings'}`;
  }

  get activeCount() {
    return this.listings.filter((l) => statusOf(l) === 'published').length;
  }

  get underOfferCount() {
    return this.listings.filter((l) => statusOf(l) === 'under-offer').length;
  }

  @cached
  get avgDom(): number | string {
    let doms = this.onMarket
      .map((l) => l.daysOnMarket)
      .filter((d): d is number => d != null);
    if (!doms.length) {
      return '—';
    }
    return Math.round(doms.reduce((a, b) => a + b, 0) / doms.length);
  }

  @cached
  get stageOptions() {
    let count = (s: string) =>
      this.listings.filter((l) => statusOf(l) === s).length;
    return [
      { value: 'all', label: `Stage: All (${this.listings.length})` },
      ...PROPERTY_LISTING_STATUSES.map((s) => ({
        value: s,
        label: `Stage: ${PROPERTY_LISTING_STATUS_LABELS[s] ?? s} (${count(s)})`,
      })),
    ];
  }

  @cached
  get stale(): PropertyListing[] {
    return this.onMarket
      .filter((l) => (l.daysOnMarket ?? 0) >= STALE_DAYS)
      .sort((a, b) => (b.daysOnMarket ?? 0) - (a.daysOnMarket ?? 0));
  }

  @cached
  get unprepared(): PropertyListing[] {
    return this.listings.filter(
      (l) =>
        statusOf(l) === 'draft' &&
        (!(l.photoCount ?? 0) || l.askingPrice?.amount == null),
    );
  }

  get attentionCount() {
    return this.stale.length + this.unprepared.length;
  }

  get subtitle() {
    let n = this.attentionCount;
    if (!n) {
      return 'Nothing needs attention.';
    }
    return `${n} ${n === 1 ? 'listing needs' : 'listings need'} attention.`;
  }

  @cached
  get visible(): PropertyListing[] {
    let rows = this.listings;
    if (this.statusFilter !== 'all') {
      rows = rows.filter((l) => statusOf(l) === this.statusFilter);
    }
    let q = this.search.trim().toLowerCase();
    if (q) {
      rows = rows.filter((l) =>
        [l.cardTitle, l.address?.city, l.neighborhood]
          .filter(Boolean)
          .some((s) => String(s).toLowerCase().includes(q)),
      );
    }
    let sorted = [...rows];
    if (this.sortKey === 'dom') {
      sorted.sort((a, b) => (b.daysOnMarket ?? -1) - (a.daysOnMarket ?? -1));
    } else if (this.sortKey === 'price') {
      sorted.sort(
        (a, b) => (b.askingPrice?.amount ?? 0) - (a.askingPrice?.amount ?? 0),
      );
    } else {
      sorted.sort((a, b) => publishedTime(b) - publishedTime(a));
    }
    return sorted;
  }

  get isEmpty() {
    return !this.isLoading && this.listings.length === 0;
  }

  // Until the first result arrives there is nothing honest to total.
  get isFirstLoad() {
    return this.isLoading && this.listings.length === 0;
  }

  setFilter = (value: string) => {
    this.statusFilter = value;
  };

  setSort = (value: string) => {
    this.sortKey = value as SortKey;
  };

  setSearch = (value: string) => {
    this.search = value;
  };

  rowKey = (l: PropertyListing) => l.id ?? l.cardTitle;

  labelOf = (l: PropertyListing) =>
    PROPERTY_LISTING_STATUS_LABELS[statusOf(l)] ?? 'Draft';

  hueOf = (l: PropertyListing) =>
    PROPERTY_LISTING_STATUS_HUES[statusOf(l)] ?? 'slate';

  heroOf = (l: PropertyListing) => {
    let urls = l.photos?.resolvedUrls ?? [];
    return urls[l.heroIndex ?? 0] || urls[0];
  };

  openCard = (card: CardDef) => {
    this.args.viewCard?.(card, 'isolated');
  };

  newListing = () => {
    let ref = identifyCard(PropertyListing);
    let realm = this.realms?.[0];
    if (!ref || !realm) {
      return;
    }
    this.args.createCard?.(ref, undefined, {
      realmURL: new URL(realm),
      doc: {
        data: {
          attributes: { status: 'draft' },
          meta: { adoptsFrom: ref },
        },
      },
    });
  };

  <template>
    <Sidebar
      class='pm'
      @label='Property Marketplace'
      @collapsible='rail'
      @railBreakpoint={{1100}}
      @mobileBreakpoint={{720}}
      @scroll='content'
      @resizable={{true}}
      @width='13.5rem'
      @shortcut={{false}}
    >
      <:header as |bar|>
        <div class='pm-brand'>
          <span class='pm-mark' aria-hidden='true'>Pm</span>
          {{#unless bar.collapsed}}
            <p class='pm-brand-text'>Property Marketplace</p>
          {{/unless}}
        </div>
      </:header>
      <:nav as |bar|>
        <SidebarGroup @label='Listings'>
          <SidebarItem
            @label='Listing desk'
            @icon={{HouseIcon}}
            @badge={{unless bar.collapsed this.listingCount}}
            @active={{true}}
            @collapsed={{bar.collapsed}}
          />
        </SidebarGroup>
      </:nav>
      <:default as |bar|>
        <div class='pm-layout'>
          <div class='pm-main'>
            {{#if bar.mobile}}
              <SidebarTrigger
                @open={{bar.open}}
                @onToggle={{bar.toggle}}
                @controls={{bar.controls}}
                @label='navigation'
              />
            {{/if}}
            <header class='pm-head'>
              <p class='pm-eyebrow'>Residential listing desk</p>
              <h2 class='pm-h1'>Listing desk</h2>
              {{#if this.isInteractive}}
                <p class='pm-sub'>{{this.subtitle}}</p>
              {{/if}}
            </header>

            {{#if this.isInteractive}}
              {{#if this.isFirstLoad}}
                <p class='pm-sub' role='status'>Loading listings…</p>
              {{else if this.isEmpty}}
                <EmptyState
                  @title='No listings yet'
                  @message='Property Listings in this realm appear here as a book, with the value on the market and what needs attention.'
                >
                  <:action>
                    <Button
                      @icon={{PlusIcon}}
                      @tone='primary'
                      @appearance='accent'
                      {{on 'click' this.newListing}}
                    >Create the first listing</Button>
                  </:action>
                </EmptyState>
              {{else}}
                <section class='pm-stats' aria-label='Market summary'>
                  <div class='pm-stat'><Stat
                      @label='Value on the market'
                      @value={{this.valueOnMarket}}
                      @hint={{this.valueHint}}
                      @tone='success'
                      @roll={{false}}
                    /></div>
                  <div class='pm-stat'><Stat
                      @label='Active'
                      @value={{this.activeCount}}
                      @hint='published'
                      @tone='success'
                    /></div>
                  <div class='pm-stat'><Stat
                      @label='Under offer'
                      @value={{this.underOfferCount}}
                      @hint='awaiting close'
                      @tone='warning'
                    /></div>
                  <div class='pm-stat'><Stat
                      @label='Avg days on market'
                      @value={{this.avgDom}}
                      @hint='live listings'
                      @tone='info'
                      @roll={{false}}
                    /></div>
                </section>

                <LayoutControl
                  @label='Listing tools'
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
                    <div class='pm-search'><SearchInput
                        @display={{if
                          (eq form 'collapsed')
                          'collapsed'
                          'field'
                        }}
                        @value={{this.search}}
                        @placeholder='Search title, neighbourhood or city'
                        @onInput={{this.setSearch}}
                      /></div>
                  </lc.Slot>
                  <lc.Slot
                    @id='stage'
                    @priority={{1}}
                    @forms={{SELECT_FORMS}}
                    @label='Stage'
                  >
                    <Select
                      @label='Listing stage'
                      @options={{this.stageOptions}}
                      @value={{this.statusFilter}}
                      @onValueChange={{this.setFilter}}
                    />
                  </lc.Slot>
                  <lc.Slot
                    @id='sort'
                    @align='end'
                    @priority={{3}}
                    @forms={{SELECT_FORMS}}
                    @label='Sort'
                  >
                    <div class='pm-sort'><Select
                        @label='Sort listings'
                        @options={{SORT_OPTIONS}}
                        @value={{this.sortKey}}
                        @onValueChange={{this.setSort}}
                      /></div>
                  </lc.Slot>
                  <lc.Slot
                    @id='add'
                    @priority={{0}}
                    @pinned={{true}}
                    @forms={{ADD_FORMS}}
                    @label='New listing'
                    as |form|
                  >
                    <Button
                      @icon={{PlusIcon}}
                      @tone='primary'
                      @appearance='accent'
                      @size='s'
                      @display={{if (eq form 'icon') 'icon' 'label'}}
                      @label='New listing'
                      {{on 'click' this.newListing}}
                    >New listing</Button>
                  </lc.Slot>
                </LayoutControl>

                <section class='pm-block' aria-labelledby='pm-book-h'>
                  <div class='pm-block-head'>
                    <h3 id='pm-book-h'>Listings</h3>
                    <span class='pm-count'>{{this.visible.length}}
                      of
                      {{this.listings.length}}</span>
                  </div>
                  <DataTable
                    @columns={{COLUMNS}}
                    @rows={{this.visible}}
                    @key={{this.rowKey}}
                    @label='Listings'
                    @size='xs'
                    @flush={{true}}
                    @sortable={{false}}
                    @columnMenu={{false}}
                    @emptyTitle='No listings match'
                    @emptyMessage='Clear the search or choose another stage.'
                  >
                    <:cell as |text row col|>
                      {{#if (eq col.key 'listing')}}
                        <button
                          type='button'
                          class='pm-open'
                          {{on 'click' (fn this.openCard row)}}
                        >
                          {{#if (this.heroOf row)}}
                            <img
                              class='pm-thumb'
                              src={{this.heroOf row}}
                              alt=''
                            />
                          {{else}}
                            <span
                              class='pm-thumb pm-thumb-empty'
                              aria-hidden='true'
                            >–</span>
                          {{/if}}
                          <span class='pm-name'>{{text}}</span>
                        </button>
                      {{else if (eq col.key 'stage')}}
                        <DotLabel
                          @label={{this.labelOf row}}
                          @hue={{this.hueOf row}}
                        />
                      {{else}}
                        <span class='pm-cell'>{{text}}</span>
                      {{/if}}
                    </:cell>
                  </DataTable>
                </section>
              {{/if}}
            {{else}}
              <EmptyState
                @size='s'
                @title='Listing desk'
                @message='Value on the market, the listing stages and the book of Property Listings. Open the app to work the book.'
              />
            {{/if}}
          </div>

          {{#if this.isInteractive}}
            <aside class='pm-aside' aria-labelledby='pm-attn-h'>
              <div class='pm-block-head'>
                <h3 id='pm-attn-h'>Needs attention</h3>
                <span class='pm-count'>{{this.attentionCount}}</span>
              </div>
              {{#if this.stale.length}}
                <p class='pm-group'>{{STALE_DAYS}}+ days on market
                  <small>Consider a price move</small></p>
                <ul class='pm-list'>
                  {{#each this.stale as |l|}}
                    <li><button
                        type='button'
                        class='pm-attn-row'
                        {{on 'click' (fn this.openCard l)}}
                      ><span class='pm-name'>{{l.cardTitle}}</span>
                        <span class='pm-mono'>{{l.daysOnMarket}}d</span>
                      </button></li>
                  {{/each}}
                </ul>
              {{/if}}
              {{#if this.unprepared.length}}
                <p class='pm-group'>Drafts missing photos or price
                  <small>Not ready to publish</small></p>
                <ul class='pm-list'>
                  {{#each this.unprepared as |l|}}
                    <li><button
                        type='button'
                        class='pm-attn-row'
                        {{on 'click' (fn this.openCard l)}}
                      ><span class='pm-name'>{{l.cardTitle}}</span>
                        <DotLabel @label='Draft' @hue='slate' />
                      </button></li>
                  {{/each}}
                </ul>
              {{/if}}
              {{#unless this.attentionCount}}
                <p class='pm-group'><small>Nothing waiting on you.</small></p>
              {{/unless}}
            </aside>
          {{/if}}
        </div>
      </:default>
    </Sidebar>
    <style scoped>
      .pm {
        container-type: inline-size;
        block-size: 100%;
        min-block-size: 0;
        background: var(--background);
        color: var(--foreground);
        font-family: var(--font-sans);
        font-size: var(--boxel-font-size-xs);
      }
      .pm-brand {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
      }
      .pm-mark {
        display: grid;
        place-items: center;
        flex: none;
        inline-size: 1.75rem;
        block-size: 1.75rem;
        border: 1px solid var(--border);
        border-radius: var(--radius);
        font-weight: 600;
        font-size: var(--boxel-font-size-2xs);
        line-height: 1;
        font-family: var(--font-mono);
      }
      .pm-brand-text {
        margin: 0;
        min-inline-size: 0;
        font-weight: 700;
      }

      /* main column + the attention panel docked flush to the right edge */
      .pm-layout {
        display: grid;
        grid-template-columns: minmax(0, 1fr) 18.75rem;
        min-block-size: 100%;
      }
      .pm-main {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
        min-inline-size: 0;
        padding: var(--boxel-sp-lg) var(--boxel-sp-lg) var(--boxel-sp-xl);
      }
      .pm-aside {
        min-inline-size: 0;
        border-inline-start: 1px solid var(--border);
        background: var(--card);
        color: var(--card-foreground);
      }
      @container (width < 60rem) {
        .pm-layout {
          grid-template-columns: minmax(0, 1fr);
        }
        .pm-aside {
          border-inline-start: 0;
          border-block-start: 1px solid var(--border);
        }
      }

      .pm-head {
        display: grid;
        gap: var(--boxel-sp-4xs);
      }
      .pm-eyebrow,
      .pm-group {
        font-weight: 600;
        font-size: 0.5625rem; /* 9px ladder label: no token */
        line-height: 1.3;
        font-family: var(--font-mono);
        letter-spacing: 0.13em;
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .pm-h1 {
        font-family: var(--boxel-heading-font-family);
        font-weight: 400;
        font-size: 2.5rem; /* ladder 40px display: no Boxel display token */
        line-height: 1;
        text-transform: uppercase;
      }
      .pm-sub {
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
      }

      /* stat strip: every cell draws its right and bottom line and the frame
         clips the overhang, so a wrapped row keeps all its dividers */
      .pm-stats {
        --text-stat: var(--boxel-font-size-lg);
        display: grid;
        grid-template-columns: repeat(4, minmax(0, 1fr));
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
        color: var(--card-foreground);
        overflow: hidden;
      }
      .pm-stat {
        min-inline-size: 0;
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        box-shadow:
          1px 0 0 var(--border),
          0 1px 0 var(--border);
      }
      @container (width <= 40rem) {
        .pm-stats {
          grid-template-columns: repeat(2, minmax(0, 1fr));
        }
      }
      .pm-search {
        inline-size: 18rem;
      }
      .pm-sort {
        inline-size: 8rem;
      }

      /* one flat block: radius on the outside only, hairlines inside */
      .pm-block {
        min-inline-size: 0;
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
        color: var(--card-foreground);
        overflow: hidden;
      }
      .pm-block-head {
        display: flex;
        align-items: baseline;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        border-block-end: 1px solid var(--border);
      }
      .pm-aside .pm-block-head {
        justify-content: space-between;
      }
      .pm-block-head h3 {
        font-size: var(--boxel-font-size-xs);
        font-weight: 700;
      }
      .pm-count,
      .pm-mono {
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-2xs);
        font-variant-numeric: tabular-nums;
        color: var(--muted-foreground);
      }
      .pm-open {
        display: inline-flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        max-inline-size: 100%;
        padding: 0;
        border: 0;
        background: none;
        color: inherit;
        font-family: inherit;
        font-size: inherit;
        font-weight: inherit;
        line-height: inherit;
        text-align: start;
      }
      .pm-open:hover .pm-name {
        text-decoration: underline;
      }
      .pm-open:focus-visible,
      .pm-attn-row:focus-visible {
        outline: 2px solid var(--ring);
        outline-offset: 2px;
      }
      .pm-thumb {
        flex: none;
        inline-size: 1.375rem;
        block-size: 1.375rem;
        object-fit: cover;
        border-radius: var(--boxel-border-radius-xs);
      }
      .pm-thumb-empty {
        display: grid;
        place-items: center;
        background: var(--muted);
        color: var(--muted-foreground);
      }
      .pm-name {
        min-inline-size: 0;
        font-weight: 600;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .pm-cell {
        display: block;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      .pm-group {
        display: grid;
        gap: var(--boxel-sp-6xs);
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        border-block-end: 1px solid var(--border);
      }
      .pm-group small {
        font-family: var(--font-sans);
        font-size: var(--boxel-font-size-2xs);
        font-weight: 400;
        letter-spacing: normal;
        text-transform: none;
      }
      .pm-list {
        margin: 0;
        padding: 0;
        list-style: none;
      }
      .pm-attn-row {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: var(--boxel-sp-xs);
        inline-size: 100%;
        min-block-size: 1.75rem;
        padding: 0 var(--boxel-sp-sm);
        border: 0;
        border-block-end: 1px solid var(--border);
        background: none;
        color: inherit;
        font-family: inherit;
        font-size: inherit;
        font-weight: inherit;
        line-height: inherit;
        text-align: start;
      }
      @media (hover: hover) {
        .pm-attn-row:hover {
          background: var(--hover);
        }
      }
    </style>
  </template>
}

export class PropertyMarketplaceApp extends CardDef {
  static displayName = 'Property Marketplace';
  static icon = HouseIcon;
  static prefersWideFormat = true;

  @field cardTitle = contains(StringField, {
    computeVia: function () {
      return 'Property Marketplace';
    },
  });

  static isolated = PropertyMarketplaceIsolated;

  static fitted = class Fitted extends Component<
    typeof PropertyMarketplaceApp
  > {
    <template>
      <RichFittedCard>
        <:avatar><HouseIcon class='app-mark' aria-hidden='true' /></:avatar>
        <:title>Property Marketplace</:title>
        <:subtitle>Value on the market, the book and what needs attention</:subtitle>
      </RichFittedCard>
      <style scoped>
        .app-mark {
          inline-size: var(--pretui-avatar-size);
          block-size: var(--pretui-avatar-size);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };
}

export default PropertyMarketplaceApp;
