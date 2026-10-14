import {
  CardDef,
  field,
  contains,
  Component,
  StringField,
  realmURL,
} from '@cardstack/base/card-api';
import { identifyCard } from '@cardstack/runtime-common';
import { tracked } from '@glimmer/tracking';
import { action } from '@ember/object';
import { debounce } from 'lodash-es';
import { Tabs } from '@cardstack/pretui/components/tabs';
import { eq } from '@cardstack/boxel-ui/helpers';
import type { TableColumn } from '../../components/table';
import ArchiveIcon from '@cardstack/boxel-icons/archive';
import { CollectionItem } from '../collectibles/collection-item';
import { CollectibleProduct } from '../collectibles/collectible-product';
import {
  CompletionSet,
  computeCompletion,
} from '../collectibles/completion-set';
import { Listing } from '../collectibles/listing';
import {
  AuthenticationRecord,
  AuthOutcomeField,
} from '../collectibles/authentication-record';
import { Order, OrderStatusField } from './order';
import { CollectionTab } from './tabs/collection';
import { SetsTab } from './tabs/sets';
import { MarketTab } from './tabs/market';
import { OrdersTab } from './tabs/orders';
import { AuthenticationTab } from './tabs/authentication';
import { MarketplaceOffer as Offer } from '../collectibles/marketplace-offer';
import { statusOption } from '../../fields/status/status';
import { formatMoney } from '../collectibles/money-format';

// Sole Vault: a collector's console over live queries of the collectibles
// cards and this folder's Order, Payment and Shipment. Each tab is its own
// component under ./tabs; the queries and the shared state live here, so the
// tabs only draw. The stat tiles are static text, not links: a metric links
// only where its destination shows the records it was computed from.

type TabId = 'collection' | 'sets' | 'market' | 'orders' | 'authentication';

class Isolated extends Component<typeof SoleVaultApp> {
  @tracked tab: TabId = 'collection';
  @tracked search = '';
  @tracked saleFilter: 'all' | 'for-sale' | 'kept' = 'all';

  // Exactly three views — grid, list, table. `card` is deliberately absent:
  // boxel-ui offers it, but it renders the card's EMBEDDED template into a row
  // envelope, which squeezes a template written for a tall envelope into a short
  // row and clips its own text.
  //
  // Grid and list share one renderer and one row set; only `table` is a different
  // layer. Switching views changes the DRAWING ONLY — never the row set, the
  // search text or the active badge — because all three read `filteredItems`.
  // That is the mirroring rule, and here it is structural rather than maintained:
  // there is one filter, so the views cannot disagree.
  @tracked view: 'grid' | 'list' | 'table' = 'grid';

  viewOptions = [
    { value: 'grid', label: 'Grid' },
    { value: 'list', label: 'List' },
    { value: 'table', label: 'Table' },
  ];

  @action setView(id: string) {
    this.view = id as 'grid' | 'list' | 'table';
  }

  // Explicit columns, because "which of a card's twenty fields belong in the
  // table" is a design decision. Each declares a `value:` accessor returning a
  // primitive — every one of these is a plain attribute or a denormalized
  // computed field, so no cell needs link resolution.
  get itemColumns(): TableColumn[] {
    return [
      {
        key: 'itemTitle',
        label: 'Pair',
        sortable: true,
        value: (i: any) => i.itemTitle,
      },
      {
        key: 'variantLabel',
        label: 'Size',
        width: '7rem',
        sortable: true,
        value: (i: any) => i.variantLabel,
      },
      {
        key: 'condition',
        label: 'Condition',
        width: '8rem',
        showAbove: 640,
        sortable: true,
        value: (i: any) => i.condition?.code,
      },
      {
        key: 'paid',
        label: 'Paid',
        align: 'right',
        width: '8rem',
        showAbove: 720,
        sortable: true,
        // sortValue keeps the numeric order — sorting the FORMATTED string would
        // order "$1,000.00" before "$90.00" because it compares character by
        // character.
        value: (i: any) => formatMoney(i.acquisition?.price),
        sortValue: (i: any) => i.acquisition?.price?.amount ?? null,
      },
      {
        key: 'worth',
        label: 'Worth',
        align: 'right',
        width: '8rem',
        sortable: true,
        value: (i: any) => formatMoney(i.lastKnownValue),
        sortValue: (i: any) => i.lastKnownValue?.amount ?? null,
      },
      {
        key: 'state',
        label: 'State',
        width: '9rem',
        showAbove: 480,
        value: (i: any) =>
          [i.verified ? 'Verified' : null, i.forSale ? 'For sale' : null]
            .filter(Boolean)
            .join(' · ') || null,
      },
    ];
  }

  get currentRealm() {
    return this.args.model[realmURL];
  }

  get realmHrefs() {
    let realm = this.currentRealm;
    return realm ? [realm.href] : [];
  }

  // Prerender gets a STATIC SHELL. The interactive panes are gated on a CRUD
  // function actually being present, which keeps indexing light and avoids the
  // known Glimmer backtracking assertion when an app card mounts themed fitted
  // cards during prerender (that stores an error_doc and surfaces as "Card
  // Error" in the app).
  get isInteractive() {
    return Boolean((this.args as any).viewCard);
  }

  private liveQuery(cardClass: any) {
    return this.args.context?.getCards(
      this,
      () => {
        let ref = identifyCard(cardClass);
        return ref ? { filter: { type: ref } } : undefined;
      },
      () => this.realmHrefs,
      { isLive: true },
    );
  }

  // One factory, five collections — each is one line, and none can drift from
  // its type because identifyCard derives the CodeRef from the class itself.
  itemsQuery = this.liveQuery(CollectionItem);
  productsQuery = this.liveQuery(CollectibleProduct);
  setsQuery = this.liveQuery(CompletionSet);
  listingsQuery = this.liveQuery(Listing);
  authQuery = this.liveQuery(AuthenticationRecord);
  ordersQuery = this.liveQuery(Order);
  offersQuery = this.liveQuery(Offer);

  // Read through a getter that drops dead slots. A deleted target leaves its
  // slot in place, so a raw `.length` counts records that no longer exist.
  get items(): any[] {
    return (this.itemsQuery?.instances ?? []).filter(Boolean);
  }
  get products(): any[] {
    return (this.productsQuery?.instances ?? []).filter(Boolean);
  }
  get sets(): any[] {
    return (this.setsQuery?.instances ?? []).filter(Boolean);
  }
  get listings(): any[] {
    return (this.listingsQuery?.instances ?? []).filter(Boolean);
  }
  get authRecords(): any[] {
    return (this.authQuery?.instances ?? []).filter(Boolean);
  }

  // Label and hue from AuthOutcomeField's own option list — same rule as
  // orderRows: the app never hand-maps outcomes to colours, so the queue's
  // chips cannot drift from the block's.
  get authRows() {
    let rows = this.authRecords.map((a) => {
      let opt = statusOption(AuthOutcomeField, a?.outcome);
      return {
        card: a,
        itemTitle: a?.itemTitle,
        service: a?.service,
        turnaroundDays: a?.turnaroundDays,
        outcomeLabel: opt?.label ?? a?.outcome,
        outcomeHue: opt?.hue,
        photoUrl: a?.submittedPhotos?.primaryUrl,
        certificateId: a?.certificateId,
        authenticator: a?.authenticator,
        pending: a?.outcome === 'pending',
      };
    });
    // A queue, not an archive: the record still awaiting a verdict is the
    // one the owner opened this tab for, so it sorts to the top.
    return [
      ...rows.filter((r) => r.pending),
      ...rows.filter((r) => !r.pending),
    ];
  }
  get orders(): any[] {
    return (this.ordersQuery?.instances ?? []).filter(Boolean);
  }
  get offers(): any[] {
    return (this.offersQuery?.instances ?? []).filter(Boolean);
  }

  // Money currently held in escrow, summed across orders whose status the graph
  // marks as holding. Computed here rather than stored on any card: it is an
  // app-level aggregate across records, which is the app's own job.
  get escrowHeldLabel(): string {
    let sum = 0;
    let currency: any = null;
    for (let o of this.orders) {
      if (o?.fundsHeld && o?.total?.amount != null) {
        sum += o.total.amount;
        currency = currency ?? o.total.currency;
      }
    }
    return sum === 0 ? '' : formatMoney({ amount: sum, currency });
  }

  // Rows precomputed here rather than reaching for getters that do not exist on
  // the card. The status LABEL and HUE come from the block's own exported
  // option list via `statusOption`, so the app never hand-maps eight statuses to
  // eight colours — one definition, in the block.
  get orderRows() {
    return this.orders.map((o) => {
      let opt = statusOption(OrderStatusField, o?.orderStatus);
      return {
        card: o,
        reference: o?.reference,
        productTitle: o?.productTitle,
        statusLabel: opt?.label ?? o?.orderStatus,
        statusHue: opt?.hue,
        total: formatMoney(o?.total),
      };
    });
  }

  get openOffersCount(): number {
    return this.offers.filter((o) => o?.isOpen).length;
  }

  // --- the owner's product ids, which is what set completion intersects with ---
  get ownedCopies(): { productId: string; variant?: string | null }[] {
    let copies: { productId: string; variant?: string | null }[] = [];
    for (let item of this.items) {
      let id = item?.item?.id;
      if (id) {
        copies.push({ productId: id, variant: item?.variant });
      }
    }
    return copies;
  }

  // --- aggregates. Computed here, never stored on a card. ---
  get collectionValue() {
    let total = 0;
    let currency: any = null;
    for (let item of this.items) {
      let v = item?.lastKnownValue;
      if (v?.amount != null) {
        total += v.amount;
        currency = currency ?? v.currency;
      }
    }
    return total === 0 ? '' : formatMoney({ amount: total, currency });
  }

  get forSaleCount() {
    return this.items.filter((i) => i?.forSale).length;
  }

  get verifiedCount() {
    return this.items.filter((i) => i?.verified).length;
  }

  get activeListings() {
    return this.listings.filter((l) => l?.listingStatus === 'active');
  }

  // Set progress uses the block's own exported arithmetic — the app does not
  // re-derive it, which is what keeps one definition of "80% complete".
  get setProgress() {
    let owned = this.ownedCopies;
    return this.sets.map((s) => {
      let products = (s?.products ?? []).map((p: any) => ({
        id: p?.id,
        variants: p?.availableVariants,
      }));
      let result = computeCompletion(products, owned, s?.completionRule);
      // No styleWidth here any more: the meter is boxel-ui's ProgressBar, which
      // owns its own fill width, so the app no longer hand-builds a style
      // string for it. `result.percent` is passed as @value instead.
      return {
        set: s,
        result,
        coverUrl: s?.coverImage?.resolvedUrl,
        // A finished goal renders a chip, not a bar — a 100% meter carries no
        // information, and three full amber stripes stacked was the pane's
        // whole problem.
        complete:
          result.targetCount > 0 && result.missingProductIds.length === 0,
      };
    });
  }

  // --- filtering. Client-side over resolved instances, because these panes need
  // real JS over fields. Named predicates then &&, so a three-criteria filter
  // stays reviewable. ---
  // The panes' live queries share one loading/error read. An unresolved
  // query MUST NOT render the empty message — "No pairs match this filter"
  // while the realm is still answering is a false statement, and a failed
  // query rendered as an empty vault sends the owner to re-create records
  // that exist. Coarse on purpose: the queries resolve together against one
  // realm, and a glance surface needs one honest answer, not five spinners.
  get vaultLoading() {
    return [
      this.itemsQuery,
      this.setsQuery,
      this.listingsQuery,
      this.ordersQuery,
      this.authQuery,
    ].some((q) => Boolean(q) && !q?.instances);
  }

  get vaultError(): string | undefined {
    for (let q of [
      this.itemsQuery,
      this.setsQuery,
      this.listingsQuery,
      this.ordersQuery,
      this.authQuery,
    ]) {
      let message = (q as any)?.errors?.[0]?.message;
      if (message) {
        return message;
      }
    }
    return undefined;
  }

  private matchesText(haystack: (string | undefined)[]) {
    let q = this.search.trim().toLowerCase();
    if (!q) {
      return true;
    }
    return haystack.some((h) => h?.toLowerCase().includes(q));
  }

  get filteredItems() {
    return this.items.filter((i) => {
      let saleOk =
        this.saleFilter === 'all' ||
        (this.saleFilter === 'for-sale' ? Boolean(i?.forSale) : !i?.forSale);
      let textOk = this.matchesText([
        i?.itemTitle,
        i?.variantLabel,
        i?.condition?.code,
        i?.packaging,
      ]);
      return saleOk && textOk;
    });
  }

  // Market pane scope, handed to CollectionPanel's `extraFilter` so grid,
  // strip and table all read the identical active-only query. Anchored with
  // `on:` — an `eq` on a field CardDef does not carry resolves against
  // CardDef without it and the request 500s (same rule as the reverse
  // queries).
  get activeListingFilter() {
    let ref = identifyCard(Listing);
    return ref
      ? ({ on: ref, eq: { listingStatus: 'active' } } as any)
      : undefined;
  }

  // Table columns for the market pane's table view. Keys are read straight
  // off the resolved Listing instance — plain attributes and the block's own
  // denormalized computed fields only, per the consume-unchanged rule.
  get listingColumns(): TableColumn[] {
    return [
      {
        key: 'productTitle',
        label: 'Listing',
        sortable: true,
        value: (l: any) => l.productTitle,
      },
      {
        key: 'variantLabel',
        label: 'Size',
        width: '7rem',
        sortable: true,
        value: (l: any) => l.variantLabel,
      },
      {
        key: 'conditionCode',
        label: 'Condition',
        width: '8rem',
        showAbove: 640,
        sortable: true,
        value: (l: any) => l.conditionCode,
      },
      {
        key: 'price',
        label: 'Price',
        width: '7rem',
        align: 'end',
        sortable: true,
        value: (l: any) => formatMoney(l.price),
      },
    ];
  }

  // 'all' is index 0, always — the row starts from the widest set and narrows
  // left to right, and the reset is where it can be found without reading.
  get saleBadges() {
    return [
      { id: 'all' as const, label: 'All', count: this.items.length },
      {
        id: 'for-sale' as const,
        label: 'For sale',
        count: this.forSaleCount,
      },
      {
        id: 'kept' as const,
        label: 'Kept',
        count: this.items.length - this.forSaleCount,
      },
    ];
  }

  get tabs() {
    return [
      {
        id: 'collection' as const,
        label: 'Collection',
        count: this.items.length,
      },
      { id: 'sets' as const, label: 'Sets', count: this.sets.length },
      {
        id: 'market' as const,
        label: 'Market',
        count: this.activeListings.length,
      },
      // Orders sits between Market and Authentication because that is the order
      // of the actual flow: browse, buy, then the check that releases the money.
      {
        id: 'orders' as const,
        label: 'Orders',
        count: this.orders.length,
      },
      {
        id: 'authentication' as const,
        label: 'Authentication',
        count: this.authRecords.length,
      },
    ];
  }

  @action setTab(id: string) {
    this.tab = id as TabId;
  }

  @action setSaleFilter(id: string) {
    this.saleFilter = id as 'all' | 'for-sale' | 'kept';
  }

  get saleOptions() {
    return this.saleBadges.map((b) => ({
      value: b.id,
      label: b.label,
      count: b.count,
    }));
  }

  get tabOptions() {
    return this.tabs.map((t) => ({
      value: t.id,
      label: `${t.label} ${t.count}`,
    }));
  }

  // Debounce the ASSIGNMENT to tracked state, not the input's own value — the
  // field must feel immediate; it is the filtering that waits.
  private debouncedSearch = debounce((v: string) => {
    this.search = v;
  }, 250);

  @action setSearch(v: string) {
    this.debouncedSearch(v);
  }

  // CRUD rides on component args, not context.actions — the wrong path silently
  // no-ops rather than erroring.
  @action open(card: any) {
    (this.args as any).viewCard?.(card, 'isolated');
  }

  @action addCollectionItem() {
    let ref = identifyCard(CollectionItem);
    let realm = this.currentRealm;
    if (!ref || !realm) {
      return;
    }
    (this.args as any).createCard?.(ref, undefined, { realmURL: realm });
  }

  @action addSet() {
    let ref = identifyCard(CompletionSet);
    let realm = this.currentRealm;
    if (!ref || !realm) {
      return;
    }
    (this.args as any).createCard?.(ref, undefined, { realmURL: realm });
  }

  <template>
    <article class='vault'>
      {{! Split-screen shell: a sticky identity rail on the left (brand,
          value plaque, ledger, vertical section nav), the content stage on
          the right. The rail is what breaks the templated
          masthead-tabs-content stack; under 860px it folds back on top.
          `.frame` exists because `.vault` IS the container and a container
          cannot be laid out by its own query. }}
      <div class='frame'>
        <aside class='rail'>
          <div class='brand'>
            <ArchiveIcon class='plaque-glyph' aria-hidden='true' />
            <h1 class='wordmark'>{{if
                @model.cardTitle
                @model.cardTitle
                'Sole Vault'
              }}</h1>
            <p class='tagline'>{{if
                @model.tagline
                @model.tagline
                'Your collection is your storefront'
              }}</p>
          </div>

          {{! Static figures, deliberately not links — see the
              no-lying-affordances note at the top of this module. }}
          <dl class='ledger'>
            <div class='ledger-hero'>
              <dt>Collection value</dt>
              <dd>{{if this.collectionValue this.collectionValue '—'}}</dd>
            </div>
            <div class='ledger-facts'>
              <div class='fact'>
                <dt>Pairs</dt>
                <dd>{{this.items.length}}</dd>
              </div>
              <div class='fact'>
                <dt>Authenticated</dt>
                <dd>{{this.verifiedCount}}</dd>
              </div>
              <div class='fact'>
                <dt>Listed</dt>
                <dd>{{this.forSaleCount}}</dd>
              </div>
            </div>
          </dl>

        </aside>

        <main class='stage'>
          <Tabs
            class='tabs'
            aria-label='Sections'
            @options={{this.tabOptions}}
            @value={{this.tab}}
            @onValueChange={{this.setTab}}
          />
          {{#if this.isInteractive}}
            {{#if (eq this.tab 'collection')}}
              <CollectionTab @tracker={{this}} />
            {{else if (eq this.tab 'sets')}}
              <SetsTab @tracker={{this}} />
            {{else if (eq this.tab 'market')}}
              <MarketTab @tracker={{this}} @context={{@context}} />
            {{else if (eq this.tab 'orders')}}
              <OrdersTab @tracker={{this}} />
            {{else}}
              <AuthenticationTab @tracker={{this}} />
            {{/if}}
          {{else}}
            {{! Static shell for prerender — see isInteractive. }}
            <p class='empty'>
              <ArchiveIcon width='22' height='22' aria-hidden='true' />
              Open this card to browse the vault.
            </p>
          {{/if}}
        </main>
      </div>
    </article>

    <style scoped>
      .vault {
        container-type: inline-size;
        container-name: vault;
        width: 100%;
        height: 100%;
        overflow-y: auto;

        /* --- palette: near-black warm stone ground, committed gold identity --- */
        --_raised: color-mix(in oklch, var(--card) 80%, var(--foreground) 20%);
        --_hairline: color-mix(in oklch, var(--border) 55%, transparent);
        /* Text-grade gold: --gold at 11-12px on white measures ~3.3:1, under
           AA's 4.5:1. Small gold STRINGS use this darkened mix; --gold stays
           for fills, rules and large serif figures. oklab per the stateColor
           note (oklch hue-rotates against achromatic endpoints). */

        /* The theme's geometricLanguage: sharp-ish 6px radius, technical not
           friendly — applied to boxel-ui buttons too, whose default is a
           100px pill. */
        --boxel-button-border-radius: 6px;

        background: var(--background);
        background-image: radial-gradient(
          ellipse 1200px 640px at 15% -10%,
          var(--card) 0%,
          transparent 60%
        );
        color: var(--foreground);
        font-family: var(--font-sans);
        padding: 2rem;
        display: flex;
        flex-direction: column;
        gap: 1.75rem;

        scrollbar-color: var(--primary) var(--card);
      }
      .vault::-webkit-scrollbar {
        width: 10px;
        height: 10px;
      }
      .vault::-webkit-scrollbar-track {
        background: var(--card);
      }
      .vault::-webkit-scrollbar-thumb {
        background: var(--primary);
        border-radius: 999px;
        border: 2px solid var(--card);
      }
      .vault ::selection {
        background: var(--primary);
        color: var(--primary-foreground);
      }
      .vault *:focus-visible {
        outline: 2px solid var(--primary);
        outline-offset: 2px;
      }
      .frame {
        display: grid;
        grid-template-columns: minmax(15rem, 18rem) minmax(0, 1fr);
        gap: 2.25rem;
        align-items: start;
      }
      .rail {
        position: sticky;
        top: 0;
        display: grid;
        gap: 1.5rem;
        padding-right: 2rem;
        border-right: 1px solid var(--_hairline);
        min-width: 0;
      }
      .stage {
        min-width: 0;
        display: flex;
        flex-direction: column;
      }
      .brand {
        display: grid;
        gap: 0.5rem;
        justify-items: start;
      }
      .plaque-glyph {
        width: 2rem;
        height: 2rem;
        color: var(--gold-ink, var(--primary));
      }
      .wordmark {
        margin: 0;
        font-family: var(--font-serif);
        font-size: clamp(2rem, 1.2rem + 2.4cqi, 3rem);
        line-height: 1.02;
        font-weight: 900;
        letter-spacing: -0.02em;
      }
      .tagline {
        margin: 0;
        font-size: 0.875rem;
        line-height: 1.45;
        color: var(--muted-foreground);
      }
      .ledger {
        margin: 0;
        display: grid;
        gap: 0.75rem;
      }
      .ledger-hero {
        display: grid;
        align-content: center;
        gap: 0.2rem;
        background: var(--card);
        border: 1px solid var(--_hairline);
        border-top: 3px solid var(--primary);
        border-radius: 6px;
        /* Same 1rem inline inset as .fact rows — two grounded siblings with
           different insets read as misregistered (measured 55.4 vs 49 px). */
        padding: 1.1rem 1rem;
        box-shadow: var(--shadow-xs);
      }
      .ledger-hero dt {
        font-size: 0.6875rem;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.08em;
        color: var(--gold-ink, var(--primary));
      }
      .ledger-hero dd {
        margin: 0;
        font-family: var(--font-serif);
        font-size: clamp(2.25rem, 1rem + 4.5cqi, 3.75rem);
        line-height: 1;
        font-weight: 900;
        letter-spacing: -0.02em;
        color: var(--foreground);
        font-variant-numeric: tabular-nums;
        animation: vault-reveal 640ms cubic-bezier(0.16, 1, 0.3, 1) both;
      }
      .ledger-facts {
        display: grid;
        gap: 0;
        border: 1px solid var(--_hairline);
        border-radius: 6px;
        background: var(--card);
        box-shadow: var(--shadow-xs);
      }
      .fact {
        display: flex;
        align-items: baseline;
        justify-content: space-between;
        gap: 0.75rem;
        padding: 0.7rem 1rem;
        border-top: 1px solid var(--_hairline);
      }
      .fact:first-child {
        border-top: 0;
      }
      .fact dt {
        font-size: 0.75rem;
        color: var(--muted-foreground);
      }
      .fact dd {
        margin: 0;
        font-family: var(--font-serif);
        font-size: 1.25rem;
        font-weight: 700;
        font-variant-numeric: tabular-nums;
        color: var(--foreground);
      }
      @media (prefers-reduced-motion: reduce) {
        .ledger-hero dd {
          animation: none;
        }
      }
      .empty {
        margin: 0;
        display: flex;
        align-items: center;
        gap: 0.6rem;
        padding: 2rem;
        background: var(--card);
        border: 1px solid var(--_hairline);
        border-radius: 6px;
        color: var(--muted-foreground);
        font-size: 0.9375rem;
        box-shadow: var(--shadow-xs);
      }
      @container vault (width < 860px) {
        .frame {
          grid-template-columns: 1fr;
          gap: 1.5rem;
        }
        .rail {
          position: static;
          border-right: 0;
          border-bottom: 1px solid var(--_hairline);
          padding-right: 0;
          padding-bottom: 1.5rem;
          gap: 1.25rem;
        }
        .ledger {
          grid-template-columns: minmax(11rem, 1fr) minmax(0, 1.4fr);
          align-items: stretch;
        }
      }
      @container vault (width < 620px) {
        .ledger {
          grid-template-columns: 1fr;
        }
      }
      @container vault (width < 460px) {
        .wordmark {
          font-size: 1.625rem;
        }
      }
    </style>
  </template>
}

export type SoleVaultView = Isolated;

export class SoleVaultApp extends CardDef {
  static displayName = 'Sole Vault';
  static icon = ArchiveIcon;

  // This card IS a layout surface, not one record's detail view: it lays out
  // tabbed collections, prerendered tile grids and a paginated field table, all
  // of which the default ~800px stack cap would force into a cramped scroller.
  // That is exactly the case `prefersWideFormat` exists for — CardsGrid,
  // Workspace and SkillSet in the base realm all set it for the same reason.
  //
  // It is also a PLATFORM-LEVEL SIGNAL, not only a width knob: the workspace's
  // entry-point grid reads this flag to label a door "App" rather than "Card".
  // Without it, Sole Vault advertises itself as a single card.
  //
  // ORDERING NOTE: this flag changes the actual pixel width every
  // `@container vault (...)` rule below sees (full stack width instead of the
  // 800px cap), so it is set BEFORE the breakpoints are re-tuned — a breakpoint
  // measured against the capped width fires at the wrong place once the flag
  // flips. The 820/620/460 stops still hold because they are container-relative
  // and the reflow order they encode is unchanged; what needs a fresh measured
  // walk is whether the toolbar now has slack it never had.
  static prefersWideFormat = true;

  @field tagline = contains(StringField);

  static isolated = Isolated;

  // FITTED — this is the app's DOOR: the tile the workspace entry-point grid
  // draws, so it is the first thing anyone sees of Sole Vault. Without it the
  // card falls back to the library default template, which is the generic
  // white-card-with-an-icon this family exists not to look like.
  //
  // Hand-rolled rather than FittedCard, and this is the one place in the family
  // where that fork is right: the app has no image field and only two strings,
  // so FittedCard's slot model would render exactly the boring tell. What
  // carries it instead is a TYPOGRAPHIC anchor (Rule 2, tier 3) — the wordmark
  // at weight 900 in the display serif — over the plaque rule the rest of the
  // family uses. Two facts, two slots, no repeats.
  static fitted = class Fitted extends Component<typeof SoleVaultApp> {
    <template>
      <div class='fit'>
        <div class='r-head'>
          <ArchiveIcon class='glyph' aria-hidden='true' />
          <h3 class='wordmark'>{{if
              @model.cardTitle
              @model.cardTitle
              'Sole Vault'
            }}</h3>
        </div>
        <p class='r-meta'>{{@model.tagline}}</p>
      </div>

      <style scoped>
        /* NO container-type / container-name — the HOST wrapper declares
           `container-type: size; container-name: fitted-card`, and declaring one
           here would capture those queries and make every rule below inert. */
        .fit {
          width: 100%;
          height: 100%;
          display: grid;
          /* The meta row is `auto`, never a fixed height: a fixed text row under
             overflow:hidden is what shears type through the middle of its
             letters. Visibility is the lever, not truncation. */
          grid-template-rows: minmax(0, 1fr) auto;
          gap: 0.2rem;

          /* ONE type scale for the whole template, CAPPED against the container
             HEIGHT as well as its width. The cap belongs on the base — a per-role
             cqb cap never binds in a wide+short cell, because cqb is tiny there
             and the cqi term is what overflows. */
          --type-base: clamp(11px, min(calc(4px + 1.9cqi + 1cqb), 10cqb), 17px);

          background: var(--card);
          color: var(--foreground);
          font-family: var(--font-sans);
          padding: 0.6rem 0.85rem;
          box-sizing: border-box;
          /* The vault plaque, as the family's inset gold edge. */
          box-shadow: inset 3px 0 0 0 var(--primary);
          overflow: hidden;
        }

        .r-head {
          min-height: 0;
          overflow: hidden;
          display: flex;
          align-items: center;
          gap: 0.45em;
        }
        /* Rule 2: the glyph identifies, it does not compete — and it is the
           card's OWN static icon, the same one the isolated masthead uses. */
        .glyph {
          width: max(14px, 1.3em);
          height: max(14px, 1.3em);
          color: var(--gold-ink, var(--primary));
          flex: none;
        }
        /* THE ANCHOR — typographic, because this card has no image to lead with.
           Display serif at 900, decisively the loudest thing at all 16 sizes. */
        .wordmark {
          margin: 0;
          font-family: 'Playfair Display', Georgia, serif;
          font-size: calc(var(--type-base) * 1.55);
          line-height: 1.1;
          font-weight: 900;
          letter-spacing: -0.01em;
          min-width: 0;
          /* Clamped at a LINE boundary with an ellipsis — the reader never sees
             half a letter. */
          display: -webkit-box;
          -webkit-box-orient: vertical;
          -webkit-line-clamp: 2;
          overflow: hidden;
        }
        .r-meta {
          margin: 0;
          min-height: 0;
          overflow: hidden;
          font-size: var(--type-base);
          line-height: 1.25;
          color: var(--muted-foreground);
          display: -webkit-box;
          -webkit-box-orient: vertical;
          -webkit-line-clamp: 2;
        }

        /* ---- quanta: structure and visibility only; the scale never steps ---- */

        /* Badge tier: the wordmark is the only survivor and must still shout. */
        @container fitted-card (height <= 50px) {
          .fit {
            grid-template-rows: 1fr;
            padding: 0.25rem 0.4rem;
          }
          .r-meta {
            display: none;
          }
          .wordmark {
            -webkit-line-clamp: 1;
          }
        }

        /* Thin strips: one line of tagline rather than two, so the block-axis
           budget stays inside 100cqb without shrinking anything into a clip. */
        @container fitted-card (height > 50px) and (height <= 105px) {
          .r-meta {
            -webkit-line-clamp: 1;
          }
          .wordmark {
            -webkit-line-clamp: 1;
          }
        }

        /* Narrow cells: the glyph would take the row the wordmark needs, so it
           is the first thing dropped — a decorative mark never costs the
           anchor its space. */
        @container fitted-card (width <= 150px) {
          .glyph {
            display: none;
          }
        }
      </style>
    </template>
  };
}

export default SoleVaultApp;
