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
import { FittedCard } from '@cardstack/boxel-ui/components';
import { Button } from '@cardstack/pretui/components/button';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { FilterChips } from '@cardstack/pretui/components/filter-chips';
import { Input } from '@cardstack/pretui/components/input';
import { Select } from '@cardstack/pretui/components/select';
import { Stat } from '@cardstack/pretui/components/stat';

import {
  PropertyListing,
  PROPERTY_LISTING_STATUSES,
  PROPERTY_LISTING_STATUS_HUES,
  PROPERTY_LISTING_STATUS_LABELS,
} from '../real-estate/property-listing';
import { formatMoney } from '../commerce/line-item-totals';
import { StatePill } from '../../components/state-pill';

const SORT_OPTIONS = [
  { value: 'newest', label: 'Newest' },
  { value: 'dom', label: 'Days on market' },
  { value: 'price', label: 'Price' },
];

const STALE_DAYS = 30;

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

// The isolated console, hoisted out of the card class so its fields can be
// @tracked.
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
    return formatMoney(total, [...codes][0] ?? 'USD');
  }

  get mixedCurrency() {
    return this.valueOnMarket === '—' && this.onMarket.length > 0;
  }

  get liveNoun() {
    return this.onMarket.length === 1 ? 'listing' : 'listings';
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

  // One chip per stage of the listing ladder, then the two exits.
  @cached
  get stageOptions() {
    return [
      { value: 'all', label: 'All', count: this.listings.length },
      ...PROPERTY_LISTING_STATUSES.map((status) => ({
        value: status,
        label: PROPERTY_LISTING_STATUS_LABELS[status] ?? status,
        count: this.listings.filter((l) => statusOf(l) === status).length,
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

  get attentionClear() {
    return !this.stale.length && !this.unprepared.length;
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

  labelOf = (listing: PropertyListing) =>
    PROPERTY_LISTING_STATUS_LABELS[statusOf(listing)] ?? 'Draft';

  hueOf = (listing: PropertyListing) =>
    PROPERTY_LISTING_STATUS_HUES[statusOf(listing)] ?? 'slate';

  priceOf = (l: PropertyListing) => {
    let p = l.askingPrice;
    return p?.amount != null ? formatMoney(p.amount, p.currency?.code) : '—';
  };

  factsOf = (l: PropertyListing) =>
    [
      l.bedrooms != null ? `${l.bedrooms} bd` : null,
      l.bathrooms != null ? `${l.bathrooms} ba` : null,
      l.areaSqft != null ? `${l.areaSqft.toLocaleString('en-US')} sf` : null,
    ]
      .filter(Boolean)
      .join(' · ');

  placeOf = (l: PropertyListing) =>
    [l.neighborhood, l.address?.city].filter(Boolean).join(', ');

  heroOf = (l: PropertyListing) => l.photos?.resolvedUrls?.[0];

  domOf = (l: PropertyListing) =>
    l.daysOnMarket != null ? `${l.daysOnMarket}d` : '';

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
    <article class='market'>
      <header class='bar'>
        <div class='bar-copy'>
          <p class='kicker'>Residential · Listing desk</p>
          <h1>Property Marketplace</h1>
        </div>
        {{#if this.isInteractive}}
          <Button
            @tone='primary'
            @appearance='accent'
            {{on 'click' this.newListing}}
          >New listing</Button>
        {{/if}}
      </header>

      {{#if this.isInteractive}}
        {{#if this.isFirstLoad}}
          <p class='status-line' role='status'>Loading listings…</p>
        {{else if this.isEmpty}}
          <EmptyState
            @title='No listings yet'
            @message='Property Listings in this realm appear here as a book, with the value on the market and what needs attention.'
          >
            <:action>
              <Button
                @tone='primary'
                @appearance='accent'
                {{on 'click' this.newListing}}
              >Create the first listing</Button>
            </:action>
          </EmptyState>
        {{else}}
          <section class='hero' aria-label='Market summary'>
            <div class='hero-main'>
              <Stat
                @label='Value on the market'
                @value={{this.valueOnMarket}}
                @roll={{false}}
              />
              <p class='hero-sub'>
                {{#if this.mixedCurrency}}
                  Live listings are priced in more than one currency.
                {{else}}
                  across
                  {{this.onMarket.length}}
                  live
                  {{this.liveNoun}}
                {{/if}}
              </p>
            </div>
            <div class='hero-side'>
              <Stat @label='Active' @value={{this.activeCount}} />
              <Stat @label='Under offer' @value={{this.underOfferCount}} />
              <Stat
                @label='Avg days on market'
                @value={{this.avgDom}}
                @roll={{false}}
              />
            </div>
          </section>

          <FilterChips
            class='pipeline'
            @label='Listing stage'
            @options={{this.stageOptions}}
            @value={{this.statusFilter}}
            @onValueChange={{this.setFilter}}
          />

          <div class='cols'>
            <section class='book' aria-label='Listings'>
              <div class='book-bar'>
                <Input
                  @type='search'
                  @value={{this.search}}
                  @placeholder='Search title, neighbourhood or city'
                  @onInput={{this.setSearch}}
                  aria-label='Search listings'
                />
                <Select
                  @label='Sort listings'
                  @options={{SORT_OPTIONS}}
                  @value={{this.sortKey}}
                  @onValueChange={{this.setSort}}
                />
              </div>

              {{#if this.visible.length}}
                <ul class='rows'>
                  {{#each this.visible as |l|}}
                    <li>
                      {{! A whole-row open target: the row is one control
                        holding a photo, facts and status, which no Pret UI
                        control composes. }}
                      <button
                        type='button'
                        class='row'
                        {{on 'click' (fn this.openCard l)}}
                      >
                        {{#if (this.heroOf l)}}
                          <img class='row-img' src={{this.heroOf l}} alt='' />
                        {{else}}
                          <span
                            class='row-img row-img-empty'
                            aria-hidden='true'
                          >—</span>
                        {{/if}}
                        <span class='row-who'>
                          <span class='row-name'>{{l.cardTitle}}</span>
                          <span class='row-meta'>{{this.placeOf l}}
                            {{#if (this.factsOf l)}}·
                              {{this.factsOf l}}{{/if}}</span>
                        </span>
                        <span class='row-price'>{{this.priceOf l}}</span>
                        <span class='row-dom'>{{this.domOf l}}</span>
                        <span class='row-state'>
                          <StatePill
                            @label={{this.labelOf l}}
                            @hue={{this.hueOf l}}
                          />
                        </span>
                      </button>
                    </li>
                  {{/each}}
                </ul>
              {{else}}
                <EmptyState
                  @size='s'
                  @title='No listings match'
                  @message='Clear the search or choose another stage.'
                />
              {{/if}}
            </section>

            <aside class='attn' aria-labelledby='pm-attn-title'>
              <h2 id='pm-attn-title' class='attn-title'>Needs attention</h2>
              {{#if this.stale.length}}
                <h3 class='attn-group'>{{STALE_DAYS}}+ days on market</h3>
                <ul class='attn-list'>
                  {{#each this.stale as |l|}}
                    <li>
                      <button
                        type='button'
                        class='attn-row warn'
                        {{on 'click' (fn this.openCard l)}}
                      >
                        <span class='attn-name'>{{l.cardTitle}}</span>
                        <span class='attn-tag'>{{this.domOf l}}
                          on market: consider a price move</span>
                      </button>
                    </li>
                  {{/each}}
                </ul>
              {{/if}}
              {{#if this.unprepared.length}}
                <h3 class='attn-group'>Drafts missing photos or price</h3>
                <ul class='attn-list'>
                  {{#each this.unprepared as |l|}}
                    <li>
                      <button
                        type='button'
                        class='attn-row'
                        {{on 'click' (fn this.openCard l)}}
                      >
                        <span class='attn-name'>{{l.cardTitle}}</span>
                        <span class='attn-tag'>Not ready to publish</span>
                      </button>
                    </li>
                  {{/each}}
                </ul>
              {{/if}}
              {{#if this.attentionClear}}
                <p class='attn-quiet'>Nothing waiting on you.</p>
              {{/if}}
            </aside>
          </div>
        {{/if}}
      {{else}}
        <EmptyState
          class='shell'
          @size='s'
          @title='Listing desk'
          @message='Value on the market, the listing ladder and the book of Property Listings. Open the app to work the book.'
        />
      {{/if}}
    </article>
    <style scoped>
      .market {
        container-type: inline-size;
        min-height: 100%;
        background: var(--background);
        color: var(--foreground);
        font-family: var(--font-sans);
        padding: var(--boxel-sp-lg);
        display: grid;
        gap: var(--boxel-sp);
        align-content: start;
      }
      .bar {
        display: flex;
        justify-content: space-between;
        align-items: flex-end;
        gap: var(--boxel-sp);
      }
      .bar-copy {
        min-width: 0;
      }
      .kicker {
        font-size: var(--boxel-font-size-2xs);
        letter-spacing: 0.12em;
        text-transform: uppercase;
        color: var(--primary-ink);
      }
      h1 {
        margin-top: var(--boxel-sp-5xs);
      }
      .status-line {
        margin-top: var(--boxel-sp-5xs);
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground);
      }
      .hero {
        display: flex;
        justify-content: space-between;
        align-items: flex-end;
        gap: var(--boxel-sp-xl);
        border: 1px solid var(--border);
        border-top: 3px solid var(--primary);
        border-radius: var(--radius);
        background: var(--card);
        color: var(--card-foreground);
        padding: var(--boxel-sp-lg);
      }
      .hero-main {
        --text-stat: var(--boxel-font-size-2xl);
      }
      .hero-sub {
        margin-top: var(--boxel-sp-5xs);
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground);
      }
      .hero-side {
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp-lg);
      }
      .cols {
        display: grid;
        grid-template-columns: minmax(0, 1fr) 17rem;
        gap: var(--boxel-sp);
        align-items: start;
      }
      .book {
        display: grid;
        gap: var(--boxel-sp-sm);
        min-width: 0;
      }
      .book-bar {
        display: grid;
        grid-template-columns: minmax(0, 1fr) 11rem;
        gap: var(--boxel-sp-xs);
        align-items: center;
      }
      .rows {
        list-style: none;
        padding: 0;
        display: grid;
        gap: var(--boxel-sp-5xs);
      }
      .row {
        width: 100%;
        display: grid;
        grid-template-columns: auto minmax(0, 1fr) auto auto auto;
        align-items: center;
        gap: var(--boxel-sp-sm);
        padding: var(--boxel-sp-xs);
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
        color: var(--card-foreground);
        font-family: inherit;
        font-size: inherit;
        line-height: inherit;
        text-align: left;
        cursor: pointer;
      }
      .row:hover {
        border-color: var(--primary);
      }
      .row:focus-visible,
      .attn-row:focus-visible {
        outline: 2px solid var(--ring);
        outline-offset: 2px;
      }
      .row-img {
        width: 4rem;
        height: 2.75rem;
        object-fit: cover;
        border-radius: var(--radius);
      }
      .row-img-empty {
        display: grid;
        place-items: center;
        background: var(--muted);
        color: var(--muted-foreground);
      }
      .row-who {
        display: grid;
        gap: var(--boxel-sp-6xs);
        min-width: 0;
      }
      .row-name {
        font-weight: 600;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .row-meta {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .row-price {
        font-weight: 700;
        font-variant-numeric: tabular-nums;
      }
      .row-dom {
        min-width: 2.25rem;
        text-align: right;
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
        font-variant-numeric: tabular-nums;
      }
      .attn {
        display: grid;
        gap: var(--boxel-sp-xs);
        align-content: start;
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
        color: var(--card-foreground);
        padding: var(--boxel-sp);
      }
      .attn-title {
        font-size: var(--boxel-font-size-xs);
        letter-spacing: 0.1em;
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .attn-group {
        margin-top: var(--boxel-sp-5xs);
        font-size: var(--boxel-font-size-sm);
        font-weight: 600;
      }
      .attn-list {
        list-style: none;
        padding: 0;
        display: grid;
        gap: var(--boxel-sp-5xs);
      }
      .attn-row {
        width: 100%;
        display: grid;
        gap: var(--boxel-sp-6xs);
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: transparent;
        color: inherit;
        font-family: inherit;
        font-size: inherit;
        line-height: inherit;
        text-align: left;
        padding: var(--boxel-sp-xs);
        cursor: pointer;
      }
      .attn-row.warn {
        border-color: var(--warning);
      }
      .attn-name {
        font-size: var(--boxel-font-size-sm);
        font-weight: 600;
      }
      .attn-tag {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
      .attn-quiet {
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground);
      }
      @container (width < 47.5rem) {
        .cols {
          grid-template-columns: minmax(0, 1fr);
        }
        .hero {
          flex-direction: column;
          align-items: flex-start;
          gap: var(--boxel-sp);
        }
      }
      @container (width < 30rem) {
        .market {
          padding: var(--boxel-sp);
        }
        .bar {
          flex-direction: column;
          align-items: flex-start;
        }
        .row {
          grid-template-columns: auto minmax(0, 1fr) auto;
        }
        .row-dom {
          display: none;
        }
        .book-bar {
          grid-template-columns: minmax(0, 1fr);
        }
        .row-state {
          grid-column: 2 / -1;
          justify-self: start;
        }
      }
    </style>
  </template>
}

// The listing agent's desk. Every Property Listing in the realm is read
// from one live query: the value on the market leads, the listing ladder
// filters the book, and a Needs attention rail names stale live listings
// and unready drafts. Rows open the listing; nothing is changed from the
// app, since publishing lives on the listing card. Prerender gets a static
// shell: the book mounts only when the card's CRUD functions are present,
// which keeps indexing light.
export class PropertyMarketplaceApp extends CardDef {
  static displayName = 'Property Marketplace';
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
      <FittedCard @titleTag='h3'>
        <:eyebrow><span class='fit-eyebrow'>Real estate</span></:eyebrow>
        <:title>Property Marketplace</:title>
        <:subtitle>value on the market · the book · needs attention</:subtitle>
        <:footer>
          <span class='ladder' aria-hidden='true'>
            <i></i><i></i><i class='lit'></i><i></i><i></i>
          </span>
        </:footer>
      </FittedCard>
      <style scoped>
        .fit-eyebrow {
          color: var(--primary-ink);
        }
        .ladder {
          display: flex;
          gap: var(--boxel-sp-5xs);
          width: 100%;
        }
        .ladder i {
          flex: 0 1 1.75rem;
          height: 0.3125rem;
          border-radius: var(--radius);
          background: color-mix(in oklch, var(--primary) 25%, transparent);
        }
        .ladder i.lit {
          background: var(--primary);
        }
      </style>
    </template>
  };
}
