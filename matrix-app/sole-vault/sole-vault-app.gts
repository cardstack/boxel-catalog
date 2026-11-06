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
import GlimmerComponent from '@glimmer/component';
import { cached, tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import GridIcon from '@cardstack/boxel-icons/layout-grid';
import LayersIcon from '@cardstack/boxel-icons/layers';
import TagIcon from '@cardstack/boxel-icons/tag';
import PackageIcon from '@cardstack/boxel-icons/package';
import ShieldCheckIcon from '@cardstack/boxel-icons/shield-check';
import PlusIcon from '@cardstack/boxel-icons/plus';
import { Button } from '@cardstack/pretui/components/button';
import {
  DataTable,
  type DataColumn,
} from '@cardstack/pretui/components/data-table';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { FilterChips } from '@cardstack/pretui/components/filter-chips';
import { LayoutControl } from '@cardstack/pretui/components/layout-control';
import { ProgressBar } from '@cardstack/pretui/components/progress-bar';
import { SearchInput } from '@cardstack/pretui/components/search-input';
import { SegmentedControl } from '@cardstack/pretui/components/segmented-control';
import {
  Sidebar,
  SidebarGroup,
  SidebarItem,
  SidebarTrigger,
} from '@cardstack/pretui/components/sidebar';
import { Stat } from '@cardstack/pretui/components/stat';
import { statusOption } from '@cardstack/catalog/fields/status/status';

import { DotLabel } from '../hr/dot-enum-field';
import { FitTile } from '../shared/fit-tile';
import { CollectionItem } from '../collectibles/collection-item';
import {
  CompletionSet,
  computeCompletion,
} from '../collectibles/completion-set';
import { Listing } from '../collectibles/listing';
import {
  AuthenticationRecord,
  AuthOutcomeField,
} from '../collectibles/authentication-record';
import { MarketplaceOffer } from '../collectibles/marketplace-offer';
import { Order, OrderStatusField } from '../collectibles/order';
import { formatMoney, currencyCode } from '../collectibles/money-format';

type TabId = 'collection' | 'sets' | 'market' | 'orders' | 'authentication';
type View = 'grid' | 'list' | 'table';

// Amounts are summed per currency, never across: a mixed set shows one total
// per currency.
function sumByCurrency(amounts: any[]): string {
  let totals = new Map<string, number>();
  for (let a of amounts) {
    if (a?.amount != null) {
      let code = currencyCode(a);
      totals.set(code, (totals.get(code) ?? 0) + a.amount);
    }
  }
  if (!totals.size) {
    return '—';
  }
  return [...totals]
    .map(([code, amount]) => formatMoney({ amount, currency: { code } } as any))
    .join(' + ');
}

function initials(text?: string | null) {
  return (text ?? '')
    .split(/\s+/)
    .filter((w) => /^[a-z0-9]/i.test(w))
    .slice(0, 2)
    .map((w) => w[0].toUpperCase())
    .join('');
}

function has(haystack: (string | null | undefined)[], q: string) {
  q = q.trim().toLowerCase();
  return !q || haystack.some((h) => h?.toLowerCase().includes(q));
}

// One drawing for a pair in the collection and the market, so grid, list and
// table read the same row set.
interface PairRow {
  card: CardDef;
  title: string;
  meta: string;
  price: string;
  photo?: string;
  marks: { label: string; hue: any }[];
}

const PAIR_COLUMNS: DataColumn<PairRow>[] = [
  { key: 'pair', label: 'Pair', value: (r) => r.title },
  { key: 'meta', label: 'Size · condition', value: (r) => r.meta },
  {
    key: 'price',
    label: 'Price',
    mono: true,
    align: 'end',
    value: (r) => r.price,
  },
  {
    key: 'state',
    label: 'State',
    value: (r) => r.marks.map((m) => m.label).join(' · '),
  },
];

interface OrderRow {
  card: any;
  reference: string;
  pair: string;
  label: string;
  hue: any;
  total: string;
}

const ORDER_COLUMNS: DataColumn<OrderRow>[] = [
  {
    key: 'reference',
    label: 'Reference',
    mono: true,
    value: (r) => r.reference,
  },
  { key: 'pair', label: 'Pair', value: (r) => r.pair },
  { key: 'status', label: 'Status', value: (r) => r.label },
  {
    key: 'total',
    label: 'Total',
    mono: true,
    align: 'end',
    value: (r) => r.total,
  },
];

interface AuthRow {
  card: any;
  label: string;
  hue: any;
  outcome: string;
  certificate: string;
  item: string;
  photo?: string;
  service: string;
}

const AUTH_COLUMNS: DataColumn<AuthRow>[] = [
  { key: 'verdict', label: 'Verdict', value: (r) => r.label },
  {
    key: 'certificate',
    label: 'Certificate',
    mono: true,
    value: (r) => r.certificate,
  },
  { key: 'item', label: 'Item', value: (r) => r.item },
  { key: 'service', label: 'Service', value: (r) => r.service },
];

const VIEW_OPTIONS = [
  { value: 'grid', label: 'Grid' },
  { value: 'list', label: 'List' },
  { value: 'table', label: 'Table' },
];

// LayoutControl forms: `minWidth` in rem, richest first.
const F = (...forms: [string, number][]) =>
  forms.map(([name, minWidth]) => ({ name, minWidth }));
const SEARCH_FORMS = F(['field', 14], ['menu', 0]);
const CHIP_FORMS = F(['full', 12], ['menu', 0]);
const VIEW_FORMS = F(['full', 12], ['menu', 0]);
const ADD_FORMS = F(['label', 7], ['icon', 2]);

const TABS: {
  id: TabId;
  label: string;
  icon: any;
  title: string;
  sub: string;
}[] = [
  {
    id: 'collection',
    label: 'Collection',
    icon: GridIcon,
    title: 'Collection',
    sub: 'Every pair you own, with what it is worth today.',
  },
  {
    id: 'sets',
    label: 'Sets',
    icon: LayersIcon,
    title: 'Sets',
    sub: 'Goals you are building toward, and the pairs still missing.',
  },
  {
    id: 'market',
    label: 'Market',
    icon: TagIcon,
    title: 'Market',
    sub: 'Pairs you have listed for sale, and the offers on them.',
  },
  {
    id: 'orders',
    label: 'Orders',
    icon: PackageIcon,
    title: 'Orders',
    sub: 'Purchases, the money held against them, and where each one stands.',
  },
  {
    id: 'authentication',
    label: 'Authentication',
    icon: ShieldCheckIcon,
    title: 'Authentication',
    sub: 'Verdicts on your pairs, with the record still awaiting one first.',
  },
];

// Grid, list and table draw the same rows, so switching views never changes
// what is shown.
class PairsView extends GlimmerComponent<{
  Args: { rows: PairRow[]; view: View; onOpen: (card: CardDef) => void };
}> {
  rowKey = (r: PairRow) => r.card.id ?? r.title;
  <template>
    {{#if (eq @view 'table')}}
      <DataTable
        @columns={{PAIR_COLUMNS}}
        @rows={{@rows}}
        @key={{this.rowKey}}
        @label='Pairs'
        @size='xs'
        @flush={{true}}
        @sortable={{false}}
        @columnMenu={{false}}
      >
        <:cell as |text row col|>
          {{#if (eq col.key 'pair')}}
            <button
              type='button'
              class='pv-open'
              {{on 'click' (fn @onOpen row.card)}}
            ><span class='pv-name'>{{text}}</span></button>
          {{else if (eq col.key 'state')}}
            <span class='pv-marks'>{{#each row.marks as |m|}}<DotLabel
                  @label={{m.label}}
                  @hue={{m.hue}}
                />{{/each}}</span>
          {{else}}
            <span class='pv-cell'>{{text}}</span>
          {{/if}}
        </:cell>
      </DataTable>
    {{else if (eq @view 'list')}}
      <ul class='pv-list'>
        {{#each @rows as |r|}}
          <li><button
              type='button'
              class='pv-row'
              {{on 'click' (fn @onOpen r.card)}}
            >
              {{#if r.photo}}<img
                  class='pv-thumb'
                  src={{r.photo}}
                  alt=''
                />{{else}}<span
                  class='pv-thumb pv-blank'
                  aria-hidden='true'
                >{{initials r.title}}</span>{{/if}}
              <span class='pv-name'>{{r.title}}</span>
              <span class='pv-meta'>{{r.meta}}</span>
              <span class='pv-marks pv-end'>{{#each r.marks as |m|}}<DotLabel
                    @label={{m.label}}
                    @hue={{m.hue}}
                  />{{/each}}</span>
              <span class='pv-mono'>{{r.price}}</span>
            </button></li>
        {{/each}}
      </ul>
    {{else}}
      <ul class='pv-grid'>
        {{#each @rows as |r|}}
          <li><button
              type='button'
              class='pv-tile'
              {{on 'click' (fn @onOpen r.card)}}
            >
              {{#if r.photo}}<img
                  class='pv-photo'
                  src={{r.photo}}
                  alt=''
                />{{else}}<span class='pv-photo' aria-hidden='true'>{{initials
                    r.title
                  }}</span>{{/if}}
              <span class='pv-body'>
                <span class='pv-title'>{{r.title}}</span>
                <span class='pv-meta'>{{r.meta}}</span>
                <span class='pv-mono'>{{r.price}}</span>
                <span class='pv-marks'>{{#each r.marks as |m|}}<DotLabel
                      @label={{m.label}}
                      @hue={{m.hue}}
                    />{{/each}}</span>
              </span>
            </button></li>
        {{/each}}
      </ul>
    {{/if}}
    <style scoped>
      .pv-grid,
      .pv-list {
        margin: 0;
        padding: 0;
        list-style: none;
      }
      .pv-grid {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(10.5rem, 1fr));
      }
      .pv-tile {
        display: grid;
        grid-template-rows: 7.875rem auto;
        inline-size: 100%;
        block-size: 100%;
        padding: 0;
        border: 0;
        box-shadow:
          1px 0 0 var(--border),
          0 1px 0 var(--border);
        background: none;
        color: inherit;
        font: inherit;
        text-align: start;
        cursor: pointer;
      }
      .pv-tile:hover,
      .pv-row:hover {
        background: var(--muted);
      }
      .pv-photo,
      .pv-blank {
        display: grid;
        place-items: center;
        inline-size: 100%;
        block-size: 100%;
        object-fit: cover;
        background: var(--muted);
        color: var(--muted-foreground);
        font: 700 var(--boxel-font-size-lg) / 1 var(--font-sans);
      }
      .pv-body {
        display: grid;
        align-content: start;
        gap: var(--boxel-sp-4xs);
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
      }
      .pv-title {
        font-weight: 600;
        display: -webkit-box;
        -webkit-line-clamp: 2;
        -webkit-box-orient: vertical;
        overflow: hidden;
      }
      .pv-meta {
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
      }
      .pv-mono {
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-2xs);
        font-variant-numeric: tabular-nums;
      }
      .pv-marks {
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp-xs);
      }
      .pv-row {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        inline-size: 100%;
        min-block-size: 1.75rem;
        padding: 0 var(--boxel-sp-sm);
        border: 0;
        border-block-end: 1px solid var(--border);
        background: none;
        color: inherit;
        font: inherit;
        text-align: start;
        cursor: pointer;
      }
      .pv-thumb {
        flex: none;
        inline-size: 1.375rem;
        block-size: 1.375rem;
        object-fit: cover;
        border-radius: var(--boxel-border-radius-xs);
        font-size: var(--boxel-font-size-2xs);
      }
      .pv-end {
        margin-inline-start: auto;
      }
      .pv-name {
        min-inline-size: 0;
        font-weight: 600;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .pv-cell {
        display: block;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .pv-open {
        padding: 0;
        border: 0;
        background: none;
        color: inherit;
        font: inherit;
        text-align: start;
        cursor: pointer;
        max-inline-size: 100%;
      }
      .pv-open:hover .pv-name {
        text-decoration: underline;
      }
      button:focus-visible {
        outline: 2px solid var(--ring);
        outline-offset: 2px;
      }
    </style>
  </template>
}

// A collector's console over live queries of the collectibles cards. The
// queries and every aggregate live here; the cards stay unaware of the app.
// Prerender gets a static shell: the panes mount only when the card's CRUD
// functions are present, which keeps indexing light.
class SoleVaultIsolated extends Component<typeof SoleVaultApp> {
  @tracked tab: TabId = 'collection';
  @tracked search = '';
  @tracked chip = 'all';
  @tracked view: View = 'grid';
  @tracked selectedOrderId: string | undefined;

  private itemsQuery: ReturnType<getCards> | undefined;
  private setsQuery: ReturnType<getCards> | undefined;
  private listingsQuery: ReturnType<getCards> | undefined;
  private authQuery: ReturnType<getCards> | undefined;
  private ordersQuery: ReturnType<getCards> | undefined;
  private offersQuery: ReturnType<getCards> | undefined;

  constructor(owner: Owner, args: any) {
    super(owner, args);
    this.itemsQuery = this.liveQuery(CollectionItem);
    this.setsQuery = this.liveQuery(CompletionSet);
    this.listingsQuery = this.liveQuery(Listing);
    this.authQuery = this.liveQuery(AuthenticationRecord);
    this.ordersQuery = this.liveQuery(Order);
    this.offersQuery = this.liveQuery(MarketplaceOffer);
  }

  private liveQuery(cardClass: typeof CardDef) {
    return this.args.context?.getCards(
      this,
      () => {
        let ref = identifyCard(cardClass);
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

  get isInteractive() {
    return Boolean(this.args.viewCard);
  }

  private read(q: ReturnType<getCards> | undefined): any[] {
    return (q?.instances ?? []).filter(Boolean);
  }
  get items() {
    return this.read(this.itemsQuery);
  }
  get sets() {
    return this.read(this.setsQuery);
  }
  get listings() {
    return this.read(this.listingsQuery);
  }
  get authRecords() {
    return this.read(this.authQuery);
  }
  get orders() {
    return this.read(this.ordersQuery);
  }
  get offers() {
    return this.read(this.offersQuery);
  }

  get isFirstLoad() {
    return [
      this.itemsQuery,
      this.setsQuery,
      this.listingsQuery,
      this.authQuery,
      this.ordersQuery,
    ].some((q) => q?.isLoading && !q.instances?.length);
  }

  get current() {
    return TABS.find((t) => t.id === this.tab)!;
  }

  // --- navigation ---
  selectTab = (tab: TabId) => {
    this.tab = tab;
    this.search = '';
    this.chip = 'all';
    this.view = 'grid';
  };
  setSearch = (v: string) => (this.search = v);
  setChip = (v: string) => (this.chip = v);
  setView = (v: string) => (this.view = v as View);
  openCard = (card: CardDef) => this.args.viewCard?.(card, 'isolated');
  selectOrder = (row: OrderRow) => (this.selectedOrderId = row.card.id);

  private create(cardClass: typeof CardDef) {
    let ref = identifyCard(cardClass);
    let realm = this.realms?.[0];
    if (ref && realm) {
      this.args.createCard?.(ref, undefined, { realmURL: new URL(realm) });
    }
  }
  addItem = () => this.create(CollectionItem);
  addSet = () => this.create(CompletionSet);
  addListing = () => this.create(Listing);

  // --- sidebar counts ---
  badge = (tab: TabId) =>
    String(
      {
        collection: this.items.length,
        sets: this.sets.length,
        market: this.activeListings.length,
        orders: this.orders.length,
        authentication: this.authRecords.length,
      }[tab],
    );

  // --- shared aggregates ---
  get fundsHeld() {
    return sumByCurrency(
      this.orders.filter((o) => o.fundsHeld).map((o) => o.total),
    );
  }
  get activeListings() {
    return this.listings.filter((l) => l.listingStatus === 'active');
  }
  get pendingAuth() {
    return this.authRecords.filter((a) => a.outcome === 'pending').length;
  }

  // --- collection ---
  get collectionValue() {
    return sumByCurrency(this.items.map((i) => i.lastKnownValue));
  }
  get overPaidHint() {
    let worth = this.items.map((i) => i.lastKnownValue).filter(Boolean);
    let paid = this.items.map((i) => i.acquisition?.price).filter(Boolean);
    let codes = new Set([...worth, ...paid].map((a) => currencyCode(a)));
    if (codes.size !== 1) {
      return 'what the pairs are worth today';
    }
    let sum = (xs: any[]) => xs.reduce((s, a) => s + (a.amount ?? 0), 0);
    let diff = sum(worth) - sum(paid);
    let code = [...codes][0];
    let label = formatMoney({
      amount: Math.abs(diff),
      currency: { code },
    } as any);
    return `${diff >= 0 ? '+' : '−'}${label} ${diff >= 0 ? 'over' : 'under'} paid`;
  }
  get forSaleCount() {
    return this.items.filter((i) => i.forSale).length;
  }
  get verifiedCount() {
    return this.items.filter((i) => i.verified).length;
  }

  private itemRow = (i: any): PairRow => ({
    card: i,
    title: i.itemTitle ?? 'Untitled pair',
    meta: [i.variantLabel, i.condition?.code].filter(Boolean).join(' · '),
    price: formatMoney(i.lastKnownValue) || '—',
    photo: i.photos?.primaryUrl,
    marks: [
      i.verified
        ? { label: 'Verified', hue: 'green' }
        : { label: 'Authenticating', hue: 'slate' },
      ...(i.forSale ? [{ label: 'For sale', hue: 'orange' }] : []),
    ],
  });

  @cached
  get collectionChips() {
    let n = this.items.length;
    return [
      { value: 'all', label: 'All', count: n },
      { value: 'for-sale', label: 'For sale', count: this.forSaleCount },
      { value: 'kept', label: 'Kept', count: n - this.forSaleCount },
    ];
  }

  get collectionRows(): PairRow[] {
    return this.items
      .filter(
        (i) =>
          (this.chip === 'all' ||
            (this.chip === 'for-sale' ? i.forSale : !i.forSale)) &&
          has([i.itemTitle, i.variantLabel, i.condition?.code], this.search),
      )
      .map(this.itemRow);
  }

  // --- market ---
  get askingValue() {
    return sumByCurrency(this.activeListings.map((l) => l.price));
  }
  get openOffers() {
    return this.offers.filter((o) => o.isOpen).length;
  }
  get marketRows(): PairRow[] {
    return this.activeListings
      .filter((l) =>
        has([l.productTitle, l.variantLabel, l.conditionCode], this.search),
      )
      .map((l) => ({
        card: l,
        title: l.productTitle ?? 'Untitled listing',
        meta: [l.variantLabel, l.conditionCode].filter(Boolean).join(' · '),
        price: formatMoney(l.price) || '—',
        photo: l.photos?.primaryUrl,
        marks: [{ label: 'Active', hue: 'green' }],
      }));
  }

  // --- sets: progress comes from the block's own arithmetic ---
  @cached
  get setRows() {
    let owned = this.items
      .filter((i) => i.item?.id)
      .map((i) => ({ productId: i.item.id, variant: i.variant }));
    return this.sets.map((s) => {
      let products = (s.products ?? []).map((p: any) => ({
        id: p?.id,
        variants: p?.availableVariants,
      }));
      let r = computeCompletion(products, owned, s.completionRule);
      let have = r.targetCount - r.missingProductIds.length;
      return {
        card: s,
        title: s.cardTitle ?? 'Untitled set',
        mark: initials(s.cardTitle),
        have,
        target: r.targetCount,
        missing: r.missingProductIds.length,
        percent: r.percent,
        complete: r.targetCount > 0 && r.missingProductIds.length === 0,
      };
    });
  }
  get visibleSets() {
    return this.setRows.filter((s) => has([s.title], this.search));
  }
  get completeSets() {
    return this.setRows.filter((s) => s.complete).length;
  }
  get missingPairs() {
    return this.setRows.reduce((n, s) => n + s.missing, 0);
  }

  // --- orders ---
  @cached
  get orderRows(): OrderRow[] {
    return this.orders.map((o) => {
      let opt = statusOption(OrderStatusField, o.orderStatus);
      return {
        card: o,
        reference: o.reference ?? '—',
        pair: o.productTitle ?? '—',
        label: opt?.label ?? o.orderStatus ?? '—',
        hue: opt?.hue,
        total: formatMoney(o.total) || '—',
      };
    });
  }
  @cached
  get orderChips() {
    let counts = new Map<string, { label: string; count: number }>();
    for (let r of this.orderRows) {
      let key = r.card.orderStatus ?? 'none';
      let c = counts.get(key) ?? { label: r.label, count: 0 };
      c.count++;
      counts.set(key, c);
    }
    return [
      { value: 'all', label: 'All', count: this.orderRows.length },
      ...[...counts].map(([value, c]) => ({ value, ...c })),
    ];
  }
  get visibleOrders() {
    return this.orderRows.filter(
      (r) =>
        (this.chip === 'all' || r.card.orderStatus === this.chip) &&
        has([r.reference, r.pair], this.search),
    );
  }
  get orderValue() {
    return sumByCurrency(this.orders.map((o) => o.total));
  }
  get selectedOrder() {
    return (
      this.orders.find((o) => o.id === this.selectedOrderId) ?? this.orders[0]
    );
  }
  get breakdown() {
    let o = this.selectedOrder;
    if (!o) {
      return [];
    }
    return [
      ['Price', o.price],
      ['Shipping', o.shippingPrice],
      ['Auth fee', o.authFee],
      ['Platform fee', o.platformFee],
      ['Total', o.total],
    ].map(([label, amount]) => ({ label, value: formatMoney(amount) || '—' }));
  }
  isSelected = (row: OrderRow) => row.card === this.selectedOrder;

  // --- authentication: the record awaiting a verdict sorts first ---
  @cached
  get authRows(): AuthRow[] {
    let rows = this.authRecords.map((a) => {
      let opt = statusOption(AuthOutcomeField, a.outcome);
      return {
        card: a,
        label: opt?.label ?? a.outcome ?? '—',
        hue: opt?.hue,
        outcome: a.outcome ?? '',
        certificate: a.certificateId ?? '—',
        item: a.itemTitle ?? '—',
        photo: a.submittedPhotos?.primaryUrl,
        service: a.service ?? '—',
      };
    });
    return [
      ...rows.filter((r) => r.outcome === 'pending'),
      ...rows.filter((r) => r.outcome !== 'pending'),
    ];
  }
  authCount = (outcome: string) =>
    this.authRecords.filter((a) => a.outcome === outcome).length;
  get authChips() {
    return [
      { value: 'all', label: 'All', count: this.authRecords.length },
      { value: 'pending', label: 'Pending', count: this.authCount('pending') },
      { value: 'passed', label: 'Passed', count: this.authCount('passed') },
      { value: 'failed', label: 'Failed', count: this.authCount('failed') },
    ];
  }
  get visibleAuth() {
    return this.authRows.filter(
      (r) =>
        (this.chip === 'all' || r.outcome === this.chip) &&
        has([r.certificate, r.item, r.service], this.search),
    );
  }

  rowKey = (r: { card: CardDef }) => r.card.id ?? '';
  plural = (n: number, one: string, many: string) =>
    `${n} ${n === 1 ? one : many}`;

  <template>
    <Sidebar
      class='sc'
      @label='Sole Vault'
      @collapsible='rail'
      @railBreakpoint={{1100}}
      @mobileBreakpoint={{720}}
      @scroll='content'
      @resizable={{true}}
      @width='13.5rem'
      @shortcut={{false}}
    >
      <:header as |bar|>
        <div class='sc-brand'>
          <span class='sc-mark' aria-hidden='true'>SC</span>
          {{#unless bar.collapsed}}
            <div class='sc-brand-text'>
              <p class='sc-brand-name'>Sole Vault</p>
              <p class='sc-eyebrow'>Sneaker vault</p>
            </div>
          {{/unless}}
        </div>
      </:header>
      <:nav as |bar|>
        <SidebarGroup @label='Vault'>
          {{#each TABS as |t|}}
            <SidebarItem
              @label={{t.label}}
              @icon={{t.icon}}
              @badge={{if
                this.isInteractive
                (unless bar.collapsed (this.badge t.id))
              }}
              @active={{eq this.tab t.id}}
              @collapsed={{bar.collapsed}}
              @onClick={{fn this.selectTab t.id}}
            />
          {{/each}}
        </SidebarGroup>
      </:nav>
      <:footer as |bar|>
        {{#unless bar.collapsed}}
          <p class='sc-sub'>{{@model.tagline}}</p>
        {{/unless}}
      </:footer>
      <:default as |bar|>
        <div class='sc-main'>
          {{#if bar.mobile}}
            <SidebarTrigger
              @open={{bar.open}}
              @onToggle={{bar.toggle}}
              @controls={{bar.controls}}
              @label='navigation'
            />
          {{/if}}
          <header class='sc-head'>
            <p class='sc-eyebrow'>Sole Vault ·
              {{this.current.label}}</p>
            <h2 class='sc-h1'>{{this.current.title}}</h2>
            <p class='sc-sub'>{{this.current.sub}}</p>
          </header>

          {{#if this.isInteractive}}
            {{#if this.isFirstLoad}}
              <p class='sc-sub' role='status'>Loading the vault…</p>
            {{else if (eq this.tab 'collection')}}
              <section class='sc-stats' aria-label='Collection summary'>
                <div class='sc-stat'><Stat
                    @label='Collection value'
                    @value={{this.collectionValue}}
                    @hint={{this.overPaidHint}}
                    @roll={{false}}
                  /></div>
                <div class='sc-stat'><Stat
                    @label='Pairs'
                    @value={{this.items.length}}
                    @hint={{this.plural this.sets.length 'set' 'sets'}}
                  /></div>
                <div class='sc-stat'><Stat
                    @label='Authenticated'
                    @value={{this.verifiedCount}}
                    @hint={{this.plural
                      this.pendingAuth
                      'check pending'
                      'checks pending'
                    }}
                  /></div>
                <div class='sc-stat'><Stat
                    @label='Listed'
                    @value={{this.forSaleCount}}
                    @hint='{{this.fundsHeld}} held in escrow'
                  /></div>
              </section>
              {{#let
                'Pairs' (this.plural this.items.length 'pair' 'pairs')
                as |title count|
              }}
                <section class='sc-block' aria-label={{title}}>
                  <div class='sc-block-head'><h3>{{title}}</h3><span
                      class='sc-count'
                    >{{count}}</span></div>
                  <div class='sc-tools'>
                    <LayoutControl
                      @label='Collection tools'
                      @controlHeight='1.625rem'
                      as |lc|
                    >
                      <lc.Slot
                        @id='search'
                        @priority={{2}}
                        @forms={{SEARCH_FORMS}}
                        @label='Search'
                      >
                        <div class='sc-search'><SearchInput
                            @value={{this.search}}
                            @placeholder='Search your collection…'
                            @onInput={{this.setSearch}}
                          /></div>
                      </lc.Slot>
                      <lc.Slot
                        @id='chips'
                        @priority={{3}}
                        @forms={{CHIP_FORMS}}
                        @label='Show'
                      >
                        <FilterChips
                          @options={{this.collectionChips}}
                          @value={{this.chip}}
                          @onValueChange={{this.setChip}}
                          @label='Show'
                        />
                      </lc.Slot>
                      <lc.Slot
                        @id='view'
                        @priority={{1}}
                        @forms={{VIEW_FORMS}}
                        @label='View'
                      >
                        <SegmentedControl
                          class='sc-push'
                          @label='View'
                          @options={{VIEW_OPTIONS}}
                          @value={{this.view}}
                          @onValueChange={{this.setView}}
                        />
                      </lc.Slot>
                      <lc.Slot
                        @id='add'
                        @priority={{0}}
                        @pinned={{true}}
                        @forms={{ADD_FORMS}}
                        @label='Add item'
                        as |form|
                      >
                        <Button
                          @icon={{PlusIcon}}
                          @tone='primary'
                          @appearance='accent'
                          @size='s'
                          @display={{if (eq form 'icon') 'icon' 'label'}}
                          @label='Add item'
                          {{on 'click' this.addItem}}
                        >Add item</Button>
                      </lc.Slot>
                    </LayoutControl>
                  </div>
                  {{#if this.collectionRows.length}}
                    <PairsView
                      @rows={{this.collectionRows}}
                      @view={{this.view}}
                      @onOpen={{this.openCard}}
                    />
                  {{else}}
                    <EmptyState
                      @size='s'
                      @title='No pairs match'
                      @message='Clear the search or pick another filter.'
                    />
                  {{/if}}
                </section>
              {{/let}}
            {{else if (eq this.tab 'sets')}}
              <section class='sc-stats' aria-label='Sets summary'>
                <div class='sc-stat'><Stat
                    @label='Sets'
                    @value={{this.sets.length}}
                    @hint='{{this.completeSets}} complete'
                  /></div>
                <div class='sc-stat'><Stat
                    @label='Complete'
                    @value={{this.completeSets}}
                    @hint='finished goals'
                  /></div>
                <div class='sc-stat'><Stat
                    @label='Pairs still missing'
                    @value={{this.missingPairs}}
                    @hint='across open sets'
                  /></div>
                <div class='sc-stat'><Stat
                    @label='Pairs owned'
                    @value={{this.items.length}}
                    @hint='counted toward sets'
                  /></div>
              </section>
              <section class='sc-block' aria-labelledby='sc-sets-h'>
                <div class='sc-block-head'><h3 id='sc-sets-h'>Completion goals</h3><span
                    class='sc-count'
                  >{{this.plural this.sets.length 'set' 'sets'}}</span></div>
                <div class='sc-tools'>
                  <LayoutControl
                    @label='Set tools'
                    @controlHeight='1.625rem'
                    as |lc|
                  >
                    <lc.Slot
                      @id='search'
                      @priority={{1}}
                      @forms={{SEARCH_FORMS}}
                      @label='Search'
                    >
                      <div class='sc-search'><SearchInput
                          @value={{this.search}}
                          @placeholder='Search sets…'
                          @onInput={{this.setSearch}}
                        /></div>
                    </lc.Slot>
                    <lc.Slot
                      @id='add'
                      @priority={{0}}
                      @pinned={{true}}
                      @forms={{ADD_FORMS}}
                      @label='Add set'
                      as |form|
                    >
                      <Button
                        class='sc-push'
                        @icon={{PlusIcon}}
                        @tone='primary'
                        @appearance='accent'
                        @size='s'
                        @display={{if (eq form 'icon') 'icon' 'label'}}
                        @label='Add set'
                        {{on 'click' this.addSet}}
                      >Add set</Button>
                    </lc.Slot>
                  </LayoutControl>
                </div>
                {{#if this.visibleSets.length}}
                  <ul class='sc-rows'>
                    {{#each this.visibleSets as |s|}}
                      <li>
                        <button
                          type='button'
                          class='sc-row sc-set'
                          {{on 'click' (fn this.openCard s.card)}}
                        >
                          <span
                            class='sc-tag'
                            aria-hidden='true'
                          >{{s.mark}}</span>
                          <span class='sc-name'>{{s.title}}</span>
                          {{#if s.complete}}
                            <DotLabel @label='Complete' @hue='green' />
                            <span class='sc-meta'>Finished goal</span>
                          {{else}}
                            <span class='sc-meta'>{{s.percent}}% complete ·
                              {{s.missing}}
                              still needed</span>
                          {{/if}}
                          <span
                            class='sc-mono sc-end'
                          >{{s.have}}/{{s.target}}</span>
                          <span class='sc-meter'>
                            {{#unless s.complete}}
                              <ProgressBar
                                @value={{s.percent}}
                                @label='{{s.title}} progress'
                              />
                            {{/unless}}
                          </span>
                        </button>
                      </li>
                    {{/each}}
                  </ul>
                {{else}}
                  <EmptyState
                    @size='s'
                    @title='No sets yet'
                    @message='Add a set to track the pairs you are collecting toward.'
                  />
                {{/if}}
              </section>
            {{else if (eq this.tab 'market')}}
              <section class='sc-stats' aria-label='Market summary'>
                <div class='sc-stat'><Stat
                    @label='Active listings'
                    @value={{this.activeListings.length}}
                    @hint='live on the market'
                  /></div>
                <div class='sc-stat'><Stat
                    @label='Asking value'
                    @value={{this.askingValue}}
                    @hint='sum of asking prices'
                    @roll={{false}}
                  /></div>
                <div class='sc-stat'><Stat
                    @label='Open offers'
                    @value={{this.openOffers}}
                    @hint='waiting on an answer'
                  /></div>
                <div class='sc-stat'><Stat
                    @label='Escrow held'
                    @value={{this.fundsHeld}}
                    @hint='held by open orders'
                    @roll={{false}}
                  /></div>
              </section>
              <section class='sc-block' aria-labelledby='sc-market-h'>
                <div class='sc-block-head'><h3 id='sc-market-h'>Active listings</h3><span
                    class='sc-count'
                  >{{this.plural
                      this.activeListings.length
                      'listing'
                      'listings'
                    }}</span></div>
                <div class='sc-tools'>
                  <LayoutControl
                    @label='Market tools'
                    @controlHeight='1.625rem'
                    as |lc|
                  >
                    <lc.Slot
                      @id='search'
                      @priority={{2}}
                      @forms={{SEARCH_FORMS}}
                      @label='Search'
                    >
                      <div class='sc-search'><SearchInput
                          @value={{this.search}}
                          @placeholder='Search active listings…'
                          @onInput={{this.setSearch}}
                        /></div>
                    </lc.Slot>
                    <lc.Slot
                      @id='view'
                      @priority={{1}}
                      @forms={{VIEW_FORMS}}
                      @label='View'
                    >
                      <SegmentedControl
                        class='sc-push'
                        @label='View'
                        @options={{VIEW_OPTIONS}}
                        @value={{this.view}}
                        @onValueChange={{this.setView}}
                      />
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
                        {{on 'click' this.addListing}}
                      >New listing</Button>
                    </lc.Slot>
                  </LayoutControl>
                </div>
                {{#if this.marketRows.length}}
                  <PairsView
                    @rows={{this.marketRows}}
                    @view={{this.view}}
                    @onOpen={{this.openCard}}
                  />
                {{else}}
                  <EmptyState
                    @size='s'
                    @title='No active listings'
                    @message='List a pair from your collection to see it here.'
                  />
                {{/if}}
              </section>
            {{else if (eq this.tab 'orders')}}
              <section class='sc-stats sc-stats-3' aria-label='Orders summary'>
                <div class='sc-stat'><Stat
                    @label='Orders'
                    @value={{this.orders.length}}
                    @hint='purchases on file'
                  /></div>
                <div class='sc-stat'><Stat
                    @label='Escrow held'
                    @value={{this.fundsHeld}}
                    @hint='held by open orders'
                    @roll={{false}}
                  /></div>
                <div class='sc-stat'><Stat
                    @label='Order value'
                    @value={{this.orderValue}}
                    @hint='all orders'
                    @roll={{false}}
                  /></div>
              </section>
              <div class='sc-split'>
                <section class='sc-block' aria-labelledby='sc-orders-h'>
                  <div class='sc-block-head'><h3
                      id='sc-orders-h'
                    >Orders</h3><span class='sc-count'>{{this.fundsHeld}}
                      in escrow</span></div>
                  <div class='sc-tools'>
                    <LayoutControl
                      @label='Order tools'
                      @controlHeight='1.625rem'
                      as |lc|
                    >
                      <lc.Slot
                        @id='search'
                        @priority={{1}}
                        @forms={{SEARCH_FORMS}}
                        @label='Search'
                      >
                        <div class='sc-search'><SearchInput
                            @value={{this.search}}
                            @placeholder='Search orders…'
                            @onInput={{this.setSearch}}
                          /></div>
                      </lc.Slot>
                      <lc.Slot
                        @id='chips'
                        @priority={{2}}
                        @forms={{CHIP_FORMS}}
                        @label='Status'
                      >
                        <FilterChips
                          @options={{this.orderChips}}
                          @value={{this.chip}}
                          @onValueChange={{this.setChip}}
                          @label='Status'
                        />
                      </lc.Slot>
                    </LayoutControl>
                  </div>
                  <DataTable
                    @columns={{ORDER_COLUMNS}}
                    @rows={{this.visibleOrders}}
                    @key={{this.rowKey}}
                    @label='Orders'
                    @size='xs'
                    @flush={{true}}
                    @sortable={{false}}
                    @columnMenu={{false}}
                    @emptyTitle='No orders match'
                    @emptyMessage='Clear the search or pick another status.'
                  >
                    <:cell as |text row col|>
                      {{#if (eq col.key 'pair')}}
                        <button
                          type='button'
                          class='sc-open'
                          aria-pressed={{if
                            (this.isSelected row)
                            'true'
                            'false'
                          }}
                          {{on 'click' (fn this.selectOrder row)}}
                        ><span class='sc-name'>{{text}}</span></button>
                      {{else if (eq col.key 'status')}}
                        <DotLabel @label={{text}} @hue={{row.hue}} />
                      {{else}}
                        <span class='sc-cell'>{{text}}</span>
                      {{/if}}
                    </:cell>
                  </DataTable>
                </section>
                {{#if this.selectedOrder}}
                  <aside class='sc-aside' aria-labelledby='sc-order-h'>
                    <div class='sc-block-head sc-between'>
                      <button
                        type='button'
                        class='sc-open'
                        id='sc-order-h'
                        {{on 'click' (fn this.openCard this.selectedOrder)}}
                      ><span
                          class='sc-name'
                        >{{this.selectedOrder.reference}}</span></button>
                      <span class='sc-count'>price breakdown</span>
                    </div>
                    <dl class='sc-kv'>
                      {{#each this.breakdown as |b|}}
                        <dt>{{b.label}}</dt><dd class='sc-mono'>{{b.value}}</dd>
                      {{/each}}
                      <dt>Escrow</dt>
                      <dd>{{#if this.selectedOrder.fundsHeld}}<DotLabel
                            @label='held'
                            @hue='blue'
                          />{{else}}<DotLabel @label='released' />{{/if}}</dd>
                    </dl>
                  </aside>
                {{/if}}
              </div>
            {{else}}
              <section class='sc-stats' aria-label='Authentication summary'>
                <div class='sc-stat'><Stat
                    @label='Records'
                    @value={{this.authRecords.length}}
                    @hint='submitted for a verdict'
                  /></div>
                <div class='sc-stat'><Stat
                    @label='Pending'
                    @value={{this.pendingAuth}}
                    @hint='awaiting a verdict'
                  /></div>
                <div class='sc-stat'><Stat
                    @label='Passed'
                    @value={{this.authCount 'passed'}}
                    @hint='verified'
                  /></div>
                <div class='sc-stat'><Stat
                    @label='Failed'
                    @value={{this.authCount 'failed'}}
                    @hint='did not pass'
                  /></div>
              </section>
              <section class='sc-block' aria-labelledby='sc-auth-h'>
                <div class='sc-block-head'><h3 id='sc-auth-h'>Authentication
                    queue</h3><span class='sc-count'>{{this.plural
                      this.authRecords.length
                      'record'
                      'records'
                    }}</span></div>
                <div class='sc-tools'>
                  <LayoutControl
                    @label='Authentication tools'
                    @controlHeight='1.625rem'
                    as |lc|
                  >
                    <lc.Slot
                      @id='search'
                      @priority={{1}}
                      @forms={{SEARCH_FORMS}}
                      @label='Search'
                    >
                      <div class='sc-search'><SearchInput
                          @value={{this.search}}
                          @placeholder='Search certificates…'
                          @onInput={{this.setSearch}}
                        /></div>
                    </lc.Slot>
                    <lc.Slot
                      @id='chips'
                      @priority={{2}}
                      @forms={{CHIP_FORMS}}
                      @label='Verdict'
                    >
                      <FilterChips
                        @options={{this.authChips}}
                        @value={{this.chip}}
                        @onValueChange={{this.setChip}}
                        @label='Verdict'
                      />
                    </lc.Slot>
                  </LayoutControl>
                </div>
                <DataTable
                  @columns={{AUTH_COLUMNS}}
                  @rows={{this.visibleAuth}}
                  @key={{this.rowKey}}
                  @label='Authentication queue'
                  @size='xs'
                  @flush={{true}}
                  @sortable={{false}}
                  @columnMenu={{false}}
                  @emptyTitle='No records match'
                  @emptyMessage='Clear the search or pick another verdict.'
                >
                  <:cell as |text row col|>
                    {{#if (eq col.key 'verdict')}}
                      <DotLabel @label={{text}} @hue={{row.hue}} />
                    {{else if (eq col.key 'item')}}
                      <button
                        type='button'
                        class='sc-open'
                        {{on 'click' (fn this.openCard row.card)}}
                      >
                        {{#if row.photo}}<img
                            class='sc-thumb'
                            src={{row.photo}}
                            alt=''
                          />{{/if}}
                        <span class='sc-name'>{{text}}</span>
                      </button>
                    {{else}}
                      <span class='sc-cell'>{{text}}</span>
                    {{/if}}
                  </:cell>
                </DataTable>
              </section>
            {{/if}}
          {{else}}
            <EmptyState
              @size='s'
              @title='Sole Vault'
              @message='Your pairs, sets, listings, orders and authentication verdicts. Open the app to work the vault.'
            />
          {{/if}}
        </div>
      </:default>
    </Sidebar>
    <style scoped>
      .sc {
        container-type: inline-size;
        block-size: 100%;
        min-block-size: 0;
        background: var(--background);
        color: var(--foreground);
        font-family: var(--font-sans);
        font-size: var(--boxel-font-size-xs);
      }
      .sc-brand {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
      }
      .sc-mark,
      .sc-tag {
        display: grid;
        place-items: center;
        flex: none;
        inline-size: 1.75rem;
        block-size: 1.75rem;
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--muted);
        font: 600 var(--boxel-font-size-2xs) / 1 var(--font-mono);
      }
      .sc-tag {
        inline-size: 1.375rem;
        block-size: 1.375rem;
      }
      .sc-brand-text {
        min-inline-size: 0;
      }
      .sc-brand-name {
        margin: 0;
        font-weight: 700;
      }
      .sc-main {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
        min-inline-size: 0;
        padding: var(--boxel-sp-lg) var(--boxel-sp-lg) var(--boxel-sp-xl);
      }
      .sc-head {
        display: grid;
        gap: var(--boxel-sp-4xs);
      }
      .sc-eyebrow,
      .sc-kv dt {
        margin: 0;
        font: 600 var(--boxel-font-size-2xs) / 1.3 var(--font-mono);
        letter-spacing: 0.13em;
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .sc-h1 {
        margin: 0;
        font-family: var(--boxel-heading-font-family);
        font-weight: 400;
        font-size: 2.5rem;
        line-height: 1;
        text-transform: uppercase;
      }
      .sc-sub,
      .sc-meta {
        margin: 0;
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
      }

      /* stat strip: every cell draws its right and bottom line and the frame
         clips the overhang, so a wrapped row keeps all its dividers */
      .sc-stats {
        --text-stat: 1.375rem;
        display: grid;
        grid-template-columns: repeat(4, minmax(0, 1fr));
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
        color: var(--card-foreground);
        overflow: hidden;
      }
      .sc-stats-3 {
        grid-template-columns: repeat(3, minmax(0, 1fr));
      }
      .sc-stat {
        min-inline-size: 0;
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        box-shadow:
          1px 0 0 var(--border),
          0 1px 0 var(--border);
      }
      @container (width <= 40rem) {
        .sc-stats,
        .sc-stats-3 {
          grid-template-columns: repeat(2, minmax(0, 1fr));
        }
      }

      /* one flat block: radius on the outside only, hairlines inside */
      .sc-block,
      .sc-aside {
        min-inline-size: 0;
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
        color: var(--card-foreground);
        overflow: hidden;
      }
      .sc-aside {
        border-radius: 0;
        border-block: 0;
        border-inline-end: 0;
        align-self: stretch;
      }
      .sc-split {
        display: grid;
        grid-template-columns: minmax(0, 1fr) 18.75rem;
        gap: var(--boxel-sp-xs);
        align-items: start;
      }
      @container (width < 60rem) {
        .sc-split {
          grid-template-columns: minmax(0, 1fr);
        }
        .sc-aside {
          border: 1px solid var(--border);
          border-radius: var(--radius);
        }
      }
      .sc-block-head {
        display: flex;
        align-items: baseline;
        justify-content: space-between;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm) 0;
      }
      .sc-between {
        padding-block-end: var(--boxel-sp-xs);
      }
      .sc-block-head h3 {
        margin: 0;
        font-size: var(--boxel-font-size-xs);
        font-weight: 700;
      }
      .sc-tools {
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        border-block-end: 1px solid var(--border);
      }
      .sc-search {
        inline-size: 14rem;
      }
      .sc-push {
        margin-inline-start: auto;
      }
      .sc-count,
      .sc-mono {
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-2xs);
        font-variant-numeric: tabular-nums;
        color: var(--muted-foreground);
      }
      .sc-name {
        min-inline-size: 0;
        font-weight: 600;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .sc-cell {
        display: block;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .sc-open {
        display: inline-flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        max-inline-size: 100%;
        padding: 0;
        border: 0;
        background: none;
        color: inherit;
        font: inherit;
        text-align: start;
        cursor: pointer;
      }
      .sc-open:hover .sc-name {
        text-decoration: underline;
      }
      .sc-open[aria-pressed='true'] .sc-name {
        text-decoration: underline;
      }
      .sc-thumb {
        flex: none;
        inline-size: 1.375rem;
        block-size: 1.375rem;
        object-fit: cover;
        border-radius: var(--boxel-border-radius-xs);
      }
      button:focus-visible {
        outline: 2px solid var(--ring);
        outline-offset: 2px;
      }

      /* rows: equal height, one hairline between */
      .sc-rows {
        margin: 0;
        padding: 0;
        list-style: none;
      }
      .sc-row {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        inline-size: 100%;
        min-block-size: 1.75rem;
        padding: 0 var(--boxel-sp-sm);
        border: 0;
        border-block-end: 1px solid var(--border);
        background: none;
        color: inherit;
        font: inherit;
        text-align: start;
        cursor: pointer;
      }
      .sc-row:hover {
        background: var(--muted);
      }
      .sc-end {
        margin-inline-start: auto;
      }
      .sc-meter {
        flex: none;
        inline-size: 6rem;
      }

      .sc-kv {
        display: grid;
        grid-template-columns: 6.25rem 1fr;
        margin: 0;
      }
      .sc-kv dt,
      .sc-kv dd {
        margin: 0;
        padding: var(--boxel-sp-4xs) var(--boxel-sp-sm);
        border-block-end: 1px solid var(--border);
        min-block-size: 1.75rem;
        display: flex;
        align-items: center;
      }
    </style>
  </template>
}

export class SoleVaultApp extends CardDef {
  static displayName = 'Sole Vault';
  static icon = GridIcon;
  static prefersWideFormat = true;

  @field tagline = contains(StringField);
  @field cardTitle = contains(StringField, {
    computeVia: function () {
      return 'Sole Vault';
    },
  });

  static isolated = SoleVaultIsolated;

  static fitted = class Fitted extends Component<typeof SoleVaultApp> {
    <template>
      <FitTile>
        <:title>Sole Vault</:title>
        <:subtitle>{{@model.tagline}}</:subtitle>
      </FitTile>
    </template>
  };
}

export default SoleVaultApp;
