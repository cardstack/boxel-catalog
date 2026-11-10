import type { OrderFulfilmentApp } from './order-fulfilment-app';
import { CardDef, Component, realmURL } from '@cardstack/base/card-api';
import CardList from '@cardstack/base/components/card-list';
import {
  identifyCard,
  type getCards,
  type CodeRef,
  type Filter,
  type Query,
} from '@cardstack/runtime-common';
import { Board } from '@cardstack/catalog/components/board';
import { MapRender } from '@cardstack/catalog/components/map-render';
import { type Coordinate } from '@cardstack/catalog/components/map-render';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { Button } from '@cardstack/pretui/components/button';
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
import { Table } from '@cardstack/pretui/components/table';
import { on } from '@ember/modifier';
import { fn, get } from '@ember/helper';
import { action } from '@ember/object';
import { cached, tracked } from '@glimmer/tracking';
import { debounce } from 'lodash-es';
import type Owner from '@ember/owner';
import KanbanIcon from '@cardstack/boxel-icons/kanban';
import PackageIcon from '@cardstack/boxel-icons/package';
import PlusIcon from '@cardstack/boxel-icons/plus';
import RouteIcon from '@cardstack/boxel-icons/route';
import TruckIcon from '@cardstack/boxel-icons/truck';
import Undo2Icon from '@cardstack/boxel-icons/undo-2';
import { FulfilmentOrder } from '../fulfilment/fulfilment-order';
import { Shipment } from '../fulfilment/shipment';
import { InventoryStock } from '../fulfilment/inventory-stock';
import { Warehouse } from '../fulfilment/warehouse';
import { Carrier, quoteService } from '../fulfilment/carrier';
import { ProductReturn } from '../fulfilment/product-return';
import { PickList } from '../fulfilment/pick-list';
import { isShipmentException } from '../fulfilment/shipment-status';
import { money, stamp } from '../fulfilment/fulfilment-format';
import {
  TABS,
  chipOptions,
  BOARD_COLUMNS,
  TRANSIT_PAGE,
  VIEW_OPTION,
  VIEW_OPTIONS,
  SEARCH_FORMS,
  CHIP_FORMS,
  VIEW_FORMS,
  ADD_FORMS,
  asOrder,
  byType,
  eq,
  hue,
  isNumber,
  lt,
  plural,
  shipmentProgress,
  stockHue,
} from './order-fulfilment-helpers';

const NAV_ICONS: Record<string, any> = {
  board: KanbanIcon,
  inventory: PackageIcon,
  ship: TruckIcon,
  transit: RouteIcon,
  returns: Undo2Icon,
};

type StatTile = { label: string; value: number; hint: string; tone?: string };

export class OrderFulfilmentDesk extends Component<typeof OrderFulfilmentApp> {
  @tracked tab = 'board';

  // One set of state names per collection, rather than a single `search` the
  // tabs fight over: `<x>Search` / `<x>Status` / `<x>View`.
  @tracked boardSearch = '';
  @tracked inventorySearch = '';
  @tracked returnsSearch = '';
  @tracked transitSearch = '';
  @tracked inventoryStatus: 'all' | 'low' | 'out' = 'all';
  @tracked returnsStatus: 'all' | 'open' | 'closed' = 'all';
  @tracked transitStatus: 'transit' | 'delivered' | 'attention' | 'all' = 'all';
  // Inventory defaults to the table: a stock row is six numeric columns, and
  // that is what a table is for. Returns defaults to the grid — an RMA reads as
  // a card. Both offer the other view; neither is forced into the wrong shape.
  @tracked inventoryView = 'table';
  @tracked returnsView = 'table';
  @tracked transitLimit = TRANSIT_PAGE;
  @tracked selectedShipmentId: string | undefined = undefined;

  private orderQuery: ReturnType<getCards> | undefined;
  private shipmentQuery: ReturnType<getCards> | undefined;
  private stockQuery: ReturnType<getCards> | undefined;
  private warehouseQuery: ReturnType<getCards> | undefined;
  private carrierQuery: ReturnType<getCards> | undefined;
  private returnQuery: ReturnType<getCards> | undefined;
  private pickQuery: ReturnType<getCards> | undefined;
  // The table view needs RESOLVED instances, while the grid/list views take the
  // Query itself. Feeding the table from `this.stock` would break the mirroring
  // rule — that resource is unfiltered, so the table would show rows the grid had
  // filtered out. These two follow `inventoryQuery` / `returnsQuery`, the very
  // objects CardList is handed, so the row sets cannot diverge.
  private inventoryRowsQuery: ReturnType<getCards> | undefined;
  private returnsRowsQuery: ReturnType<getCards> | undefined;

  constructor(owner: Owner, args: any) {
    super(owner, args);
    let ctx = this.args.context;
    let realms = () => this.realms;
    let live = { isLive: true } as const;
    this.orderQuery = ctx?.getCards(
      this,
      () => byType(FulfilmentOrder),
      realms,
      live,
    );
    this.shipmentQuery = ctx?.getCards(
      this,
      () => byType(Shipment),
      realms,
      live,
    );
    this.stockQuery = ctx?.getCards(
      this,
      () => byType(InventoryStock),
      realms,
      live,
    );
    this.warehouseQuery = ctx?.getCards(
      this,
      () => byType(Warehouse),
      realms,
      live,
    );
    this.carrierQuery = ctx?.getCards(
      this,
      () => byType(Carrier),
      realms,
      live,
    );
    this.returnQuery = ctx?.getCards(
      this,
      () => byType(ProductReturn),
      realms,
      live,
    );
    this.pickQuery = ctx?.getCards(this, () => byType(PickList), realms, live);
    this.inventoryRowsQuery = ctx?.getCards(
      this,
      () => this.inventoryQuery,
      realms,
      live,
    );
    this.returnsRowsQuery = ctx?.getCards(
      this,
      () => this.returnsQuery,
      realms,
      live,
    );
  }

  get realmList(): string[] {
    return this.realms ?? [];
  }

  get realms(): string[] | undefined {
    let url = (this.args.model as any)?.[realmURL];
    return url ? [url.href] : undefined;
  }

  // ── Search plumbing ──────────────────────────────────────────────────────

  // No text → a plain type filter. Text → the type AND (full-document `matches`
  // OR title `contains`). Both halves of the `any` are needed: `matches` finds a
  // term buried in the document but can miss the title the user obviously meant;
  // `contains` on cardTitle guarantees that case. The `every` keeps the type
  // anchor so a search never returns cards of other types.
  private searchTextFilter(ref: CodeRef, search: string): Filter {
    let q = search.trim();
    if (!q) {
      return { type: ref };
    }
    return {
      every: [
        { type: ref },
        { any: [{ matches: q }, { contains: { cardTitle: q } }] },
      ],
    };
  }

  // ONE Query per collection, handed unchanged to all four views. The mirroring
  // rule of the skill stops being something maintained by hand here: card, list
  // and grid render it through CardList, and table renders the same object
  // through the Table component, so they cannot disagree about the row set.
  private collectionQuery(
    cardClass: typeof CardDef,
    search: string,
    sortBy: string,
    // The status predicate, as an indexed field/value pair. It must be a real
    // field on the card — a getter is invisible to the query engine.
    status?: { field: string; value: string },
  ): Query | undefined {
    let ref = identifyCard(cardClass);
    // Rendering nothing beats querying every realm for every type while the ref
    // is still unresolved.
    if (!ref || !this.realms?.length) {
      return undefined;
    }
    let textFilter = this.searchTextFilter(ref, search);
    // The `eq` node carries its own `on` anchor; without it the filter would look
    // for the field on CardDef and fail.
    let filter: Filter = status
      ? {
          every: [
            textFilter,
            { on: ref, eq: { [status.field]: status.value } },
          ],
        }
      : textFilter;
    return {
      filter,
      sort: [{ by: sortBy, on: ref, direction: 'asc' as const }],
    };
  }

  get inventoryQuery() {
    return this.collectionQuery(
      InventoryStock,
      this.inventorySearch,
      'sku',
      this.inventoryStatus === 'all'
        ? undefined
        : { field: 'stockState', value: this.inventoryStatus },
    );
  }

  get returnsQuery() {
    return this.collectionQuery(
      ProductReturn,
      this.returnsSearch,
      'rmaNumber',
      this.returnsStatus === 'all'
        ? undefined
        : { field: 'lifecycleState', value: this.returnsStatus },
    );
  }

  // `card` / `list` / `grid` are cell shapes over one renderer; `table` is the
  // other layer entirely.
  isCardListView = (view: string) => view !== 'table';
  viewOptionFor = (view: string) => VIEW_OPTION[view] ?? 'grid';

  // Debounce the assignment to tracked state, not the input's own value: the
  // field must feel immediate, it is the query that waits.
  private debouncedBoardSearch = debounce((v: string) => {
    this.boardSearch = v;
  }, 250);
  private debouncedInventorySearch = debounce((v: string) => {
    this.inventorySearch = v;
  }, 250);
  private debouncedReturnsSearch = debounce((v: string) => {
    this.returnsSearch = v;
  }, 250);
  private debouncedTransitSearch = debounce((v: string) => {
    this.transitSearch = v;
  }, 250);

  @action setBoardSearch(v: string) {
    this.debouncedBoardSearch(v);
  }
  @action setInventorySearch(v: string) {
    this.debouncedInventorySearch(v);
  }
  @action setReturnsSearch(v: string) {
    this.debouncedReturnsSearch(v);
  }

  @action setInventoryView(id: string) {
    this.inventoryView = id;
  }
  @action setReturnsView(id: string) {
    this.returnsView = id;
  }

  // Prerender gets a static shell. The CRUD functions are only present in the
  // interactive host, so gating on them keeps indexing light and avoids
  // rendering boards of themed fitted cards during prerender.
  get isInteractive() {
    return Boolean(this.args.viewCard);
  }

  // Loading is not empty: an unresolved query and an empty realm both yield

  // zero instances, so views check the query's loading state first.
  get orders(): FulfilmentOrder[] {
    return ((this.orderQuery?.instances ?? []) as FulfilmentOrder[]).filter(
      Boolean,
    );
  }

  get shipments(): Shipment[] {
    return ((this.shipmentQuery?.instances ?? []) as Shipment[]).filter(
      Boolean,
    );
  }

  get stock(): InventoryStock[] {
    return ((this.stockQuery?.instances ?? []) as InventoryStock[]).filter(
      Boolean,
    );
  }

  get warehouses(): Warehouse[] {
    return ((this.warehouseQuery?.instances ?? []) as Warehouse[]).filter(
      Boolean,
    );
  }

  get carriers(): Carrier[] {
    return ((this.carrierQuery?.instances ?? []) as Carrier[]).filter(Boolean);
  }

  get returns(): ProductReturn[] {
    return ((this.returnQuery?.instances ?? []) as ProductReturn[]).filter(
      Boolean,
    );
  }

  get pickLists(): PickList[] {
    return ((this.pickQuery?.instances ?? []) as PickList[]).filter(Boolean);
  }

  // ── Board ────────────────────────────────────────────────────────────────

  get boardColumns() {
    return BOARD_COLUMNS;
  }

  get boardEmptyMessage() {
    if (this.ordersLoading) {
      return 'Loading orders…';
    }
    if (this.boardSearch.trim() && this.orders.length) {
      return 'No orders match this search.';
    }
    return 'No orders in the pipeline. Everything raised so far is shipped, delivered or on hold.';
  }

  get boardOrders() {
    let term = this.boardSearch.trim().toLowerCase();
    let inPipeline = this.orders.filter(this.isOnBoard);
    if (!term) {
      return inPipeline;
    }
    return inPipeline.filter((o) => {
      let haystack = [
        o.orderNumber,
        o.customerName,
        ...(o.lineItems ?? []).map((l) => l?.sku),
      ]
        .filter(Boolean)
        .join(' ')
        .toLowerCase();
      return haystack.includes(term);
    });
  }

  private isOnBoard = (order: FulfilmentOrder) =>
    BOARD_COLUMNS.some((c) => c.key === order.status);

  @action columnKeyFor(card: CardDef) {
    let order = card as FulfilmentOrder;
    // Safe without a fallback: `boardOrders` has already guaranteed the status
    // names a column. A fallback here could only ever invent one.
    return order.status;
  }

  @action
  async moveOrder(card: CardDef, columnKey: string) {
    let order = card as FulfilmentOrder;
    let store = (this.args as any).context?.store;
    if (!store || !order.id) {
      throw new Error('No store available to record the move');
    }
    await store.patch(order.id, { attributes: { status: columnKey } });
  }

  @action openCard(card: CardDef) {
    this.args.viewCard?.(card, 'isolated');
  }

  @action async createOrder() {
    let create = this.args.createCard;
    // `realms` are strings but the host reads `opts.realmURL.href` — pass a URL.
    let realmHref = this.realms?.[0];
    let realm = realmHref ? new URL(realmHref) : undefined;
    let ref = identifyCard(FulfilmentOrder);
    if (!create || !ref || !realm) {
      return;
    }
    await create(ref, undefined, {
      realmURL: realm,
      doc: {
        data: {
          // When a `doc` is supplied the host skips `ref` entirely and adds the
          // document as-is, so the doc has to carry its own adoptsFrom.
          meta: { adoptsFrom: ref },
          attributes: {
            status: 'pending',
            priority: 'normal',
            source: 'manual',
            paymentStatus: 'pending',
            placedAt: new Date().toISOString(),
          },
        },
      },
    });
  }

  @action async createStockRow() {
    let create = this.args.createCard;
    // `realms` are strings but the host reads `opts.realmURL.href` — pass a URL.
    let realmHref = this.realms?.[0];
    let realm = realmHref ? new URL(realmHref) : undefined;
    let ref = identifyCard(InventoryStock);
    if (!create || !ref || !realm) {
      return;
    }
    await create(ref, undefined, {
      realmURL: realm,
      doc: { data: { meta: { adoptsFrom: ref } } },
    });
  }

  @action async createReturn() {
    let create = this.args.createCard;
    // `realms` are strings but the host reads `opts.realmURL.href` — pass a URL.
    let realmHref = this.realms?.[0];
    let realm = realmHref ? new URL(realmHref) : undefined;
    let ref = identifyCard(ProductReturn);
    if (!create || !ref || !realm) {
      return;
    }
    await create(ref, undefined, {
      realmURL: realm,
      doc: {
        data: {
          meta: { adoptsFrom: ref },
          attributes: {
            status: 'requested',
            requestedAt: new Date().toISOString(),
          },
        },
      },
    });
  }

  // ── Counters ─────────────────────────────────────────────────────────────

  get todayCount() {
    return this.orders.filter((o) =>
      ['pending', 'processing', 'picking', 'packing'].includes(o.status ?? ''),
    ).length;
  }

  get expressCount() {
    return this.orders.filter(
      (o) =>
        o.isExpress && !['delivered', 'cancelled'].includes(o.status ?? ''),
    ).length;
  }

  get inTransit() {
    return this.shipments.filter(
      (s) => s.status === 'in_transit' || s.status === 'out_for_delivery',
    );
  }

  // Delivered shipments, most recent first: what landed today.
  get deliveredShipments() {
    return this.shipments
      .filter((s) => s.status === 'delivered')
      .sort(
        (a, b) =>
          (b.deliveredAt?.getTime() ?? 0) - (a.deliveredAt?.getTime() ?? 0),
      );
  }

  get exceptions() {
    return this.shipments.filter((s) => isShipmentException(s.status));
  }

  get lateShipments() {
    return this.shipments.filter((s) => s.isLate && s.status !== 'delivered');
  }

  // The masthead counts what the In transit tab flags, which includes overdue

  // shipments that carry no exception status.
  get needsAttention() {
    let seen = new Set(this.exceptions);
    for (let s of this.lateShipments) {
      seen.add(s);
    }
    return [...seen];
  }

  get lowStock() {
    return this.stock.filter((s) => s.isLowStock);
  }

  get outOfStock() {
    return this.stock.filter((s) => s.isOutOfStock);
  }

  // Reads the card's own `lifecycleState` rather than re-listing the closed
  // statuses here — the badge count and the two filtered views then cannot
  // disagree about what "open" means.
  get openReturns() {
    return this.returns.filter((r) => r.lifecycleState === 'open');
  }

  // ── Inventory ────────────────────────────────────────────────────────────

  // All four views take the same Query object, so their row sets match.

  // The board and the counters filter on the client, because they compute over

  // resolved fields.

  get closedReturns() {
    return this.returns.length - this.openReturns.length;
  }

  get warehouseSummary() {
    return this.warehouses.map((w) => {
      let rows = this.stock.filter((s) => s.warehouseCode === w.code);
      let codes = new Set(
        rows
          .filter((r) => r.product?.cost?.amount != null)
          .map((r) => r.product?.cost?.currency?.code ?? null),
      );
      // A total is only meaningful in one currency; mixed stock shows none.
      let currency =
        codes.size === 1 ? ([...codes][0] ?? undefined) : undefined;
      let value =
        codes.size > 1
          ? undefined
          : rows.reduce(
              (sum, r) =>
                sum + (r.quantityOnHand ?? 0) * (r.product?.cost?.amount ?? 0),
              0,
            );
      return {
        warehouse: w,
        skuCount: rows.length,
        value,
        currency,
        utilization: w.utilizationPercent,
        isVirtual: w.isVirtual,
      };
    });
  }

  // ── In transit ───────────────────────────────────────────────────────────

  get shipmentsLoading() {
    return Boolean(this.shipmentQuery?.isLoading) && !this.shipments.length;
  }

  get ordersLoading() {
    return Boolean(this.orderQuery?.isLoading) && !this.orders.length;
  }

  get stockLoading() {
    return Boolean(this.stockQuery?.isLoading) && !this.stock.length;
  }

  // Redundant when the list below is already exactly this set.
  get showAttentionBanner() {
    return this.needsAttention.length > 0 && this.transitStatus !== 'attention';
  }

  get transitBadges() {
    return [
      { id: 'all' as const, label: 'All', count: this.shipments.length },
      {
        id: 'transit' as const,
        label: 'On the road',
        count: this.inTransit.length,
      },
      {
        id: 'attention' as const,
        label: 'Needs attention',
        count: this.needsAttention.length,
      },
      {
        id: 'delivered' as const,
        label: 'Delivered',
        count: this.deliveredShipments.length,
      },
    ];
  }

  // Each badge names exactly the set it draws, so a count can never advertise a
  // list the tab does not then render.
  get transitSet(): Shipment[] {
    switch (this.transitStatus) {
      case 'delivered':
        return this.deliveredShipments;
      case 'attention':
        return this.needsAttention;
      case 'all':
        return this.shipments;
      default:
        return this.inTransit;
    }
  }

  get transitShipments() {
    let term = this.transitSearch.trim().toLowerCase();
    if (!term) {
      return this.transitSet;
    }
    return this.transitSet.filter((s) => {
      let haystack = [
        s.shipmentNumber,
        s.orderNumber,
        s.carrierLabel,
        s.serviceLevel,
        s.trackingNumber?.number,
      ]
        .filter(Boolean)
        .join(' ')
        .toLowerCase();
      return haystack.includes(term);
    });
  }

  // A tracker per row is tall — twelve is already a long scroll and two hundred
  // is a stall. The cap is stated in the UI rather than applied silently,
  // because a truncated list that looks complete is worse than a long one.
  get transitVisible() {
    return this.transitShipments.slice(0, this.transitLimit);
  }

  get transitHiddenCount() {
    return Math.max(0, this.transitShipments.length - this.transitLimit);
  }

  @action showMoreTransit() {
    this.transitLimit += TRANSIT_PAGE;
  }

  @action setTransitStatus(
    value: 'transit' | 'delivered' | 'attention' | 'all',
  ) {
    this.transitStatus = value;
    this.transitLimit = TRANSIT_PAGE;
  }

  @action setTransitSearch(v: string) {
    this.debouncedTransitSearch(v);
  }

  get transitEmptyMessage() {
    if (this.transitSearch.trim()) {
      return 'No shipments match this search.';
    }
    switch (this.transitStatus) {
      case 'delivered':
        return 'Nothing delivered yet. Packages appear here once someone marks them delivered.';
      case 'attention':
        return 'No shipment is in exception or past its promised window.';
      case 'all':
        return 'No shipments yet. One is created when an order is packed.';
      default:
        return 'Nothing on the road. Dispatched packages appear here until they land.';
    }
  }

  @cached
  get warehousePoints(): Coordinate[] {
    return this.warehouseSummary
      .map(({ warehouse, skuCount, value }) => {
        let lat = warehouse.latitude;
        let lng = warehouse.longitude;
        if (lat == null || lng == null) {
          return undefined;
        }
        let label = `${skuCount} ${skuCount === 1 ? 'SKU' : 'SKUs'} · ${money(
          value,
        )}`;
        return {
          id: warehouse.id ?? warehouse.code ?? '',
          lat,
          lng,
          name: warehouse.warehouseName ?? warehouse.code ?? 'Warehouse',
          address: label,
        };
      })
      .filter(Boolean) as Coordinate[];
  }

  get hasWarehouseMap() {
    return this.warehousePoints.length > 0;
  }

  mapConfig = {
    disableMapClick: true,
    showGoogleMapsLink: true,
    // Three markers spread across two countries: without a re-fit control, one
    // pan away from Solingen and the London sites are off screen with no way
    // back short of a reload.
    showFitButton: true,
  };

  // ── Table columns ──────────────────────────────────────────────────────────

  //

  // A stock row is its identity, its location and four quantities. Numeric

  // columns align right.

  get inventoryRows() {
    return (
      (this.inventoryRowsQuery?.instances ?? []) as InventoryStock[]
    ).filter(Boolean);
  }

  get returnsRows() {
    return ((this.returnsRowsQuery?.instances ?? []) as ProductReturn[]).filter(
      Boolean,
    );
  }

  get inventoryLoading() {
    return (
      Boolean(this.inventoryRowsQuery?.isLoading) && !this.inventoryRows.length
    );
  }

  get returnsLoading() {
    return (
      Boolean(this.returnsRowsQuery?.isLoading) && !this.returnsRows.length
    );
  }

  @action setInventoryStatus(value: 'all' | 'low' | 'out') {
    this.inventoryStatus = value;
  }

  @action setReturnsStatus(value: 'all' | 'open' | 'closed') {
    this.returnsStatus = value;
  }

  // Every badge carries its count, derived from the same collection the view
  // renders. A zero-count badge still renders — a disappearing badge makes the
  // row jump as data changes.
  get inventoryBadges() {
    return [
      { id: 'all' as const, label: 'All', count: this.stock.length },
      { id: 'low' as const, label: 'Low', count: this.lowStock.length },
      { id: 'out' as const, label: 'Out', count: this.outOfStock.length },
    ];
  }

  get returnsBadges() {
    return [
      { id: 'all' as const, label: 'All', count: this.returns.length },
      { id: 'open' as const, label: 'Open', count: this.openReturns.length },
      { id: 'closed' as const, label: 'Closed', count: this.closedReturns },
    ];
  }

  // ── Ship desk ────────────────────────────────────────────────────────────

  get shipDeskQueue() {
    return this.shipments.filter(
      (s) => !s.shippedAt || s.status === 'label_created',
    );
  }

  // Which orders already have a parcel. Read from the shipments rather than from
  // a flag on the order, because the shipment is the thing that knows.
  get orderIdsWithShipment() {
    return new Set(
      this.shipments.map((s) => s.order?.id).filter(Boolean) as string[],
    );
  }

  // Turns a packed order into a shipment, so the ship desk can rate it.
  get ordersAwaitingShipment() {
    let has = this.orderIdsWithShipment;
    return this.orders.filter(
      (o) => o.status === 'packing' && o.id && !has.has(o.id),
    );
  }

  @action async createShipmentFor(order: FulfilmentOrder) {
    let create = this.args.createCard;
    let realmHref = this.realms?.[0];
    let realm = realmHref ? new URL(realmHref) : undefined;
    let ref = identifyCard(Shipment);
    if (!create || !ref || !realm || !order.id) {
      return;
    }
    let lineItems = (order.lineItems ?? []).filter(Boolean).map((l) => ({
      sku: l.sku ?? null,
      productName: l.productName ?? null,
      quantity: l.quantity ?? null,
      unitPrice: l.unitPrice?.amount
        ? {
            amount: l.unitPrice.amount,
            currency: { code: l.unitPrice.currency?.code ?? 'GBP' },
          }
        : null,
    }));
    await create(ref, undefined, {
      realmURL: realm,
      doc: {
        data: {
          type: 'card',
          meta: { adoptsFrom: ref },
          attributes: {
            status: 'label_created',
            shipmentNumber: `SHP-${order.orderNumber ?? 'NEW'}`,
            lineItems,
          },
          relationships: {
            order: { links: { self: order.id } },
            ...(order.allocatedWarehouse?.id
              ? {
                  originWarehouse: {
                    links: { self: order.allocatedWarehouse.id },
                  },
                }
              : {}),
          },
        },
      },
    });
  }

  get selectedShipment(): Shipment | undefined {
    let list = this.shipDeskQueue;
    if (!list.length) {
      return undefined;
    }
    return list.find((s) => s.id === this.selectedShipmentId) ?? list[0];
  }

  // Rate shopping over the rates configured on the Carrier cards. There is no
  // carrier API here and the app does not pretend otherwise — every number
  // below traces to a service on a card someone filled in.
  get rateOptions() {
    let shipment = this.selectedShipment;
    if (!shipment) {
      return [];
    }
    let parcel = shipment.parcel;
    let paid = shipment.customerPaid?.amount;
    let paidCurrency = shipment.customerPaid?.currency?.code;

    let options = this.carriers
      .filter((c) => c.isActive !== false)
      .flatMap((carrier) =>
        (carrier.services ?? [])
          .filter((s) => s?.baseRate?.amount != null)
          .map((service) => {
            let divisor = carrier.dimDivisor ?? 5000;
            let volume =
              parcel?.length && parcel?.width && parcel?.height
                ? parcel.length * parcel.width * parcel.height
                : 0;
            let volumetric = volume ? volume / divisor : 0;
            let billable =
              Math.round(Math.max(parcel?.weight ?? 0, volumetric) * 100) / 100;
            let cost = quoteService(service, billable) ?? 0;
            let currency = service.baseRate?.currency?.code ?? 'GBP';
            return {
              key: `${carrier.code}-${service.code}`,
              carrier,
              carrierName: carrier.carrierName ?? carrier.code ?? '',
              serviceName: service.serviceName ?? service.code ?? '',
              serviceCode: service.code ?? '',
              speed: service.speedLabel ?? '—',
              days: service.deliveryDaysMin ?? 99,
              billable,
              cost,
              // Margin only compares like with like.
              margin:
                paid != null && paidCurrency === currency
                  ? Math.round((paid - cost) * 100) / 100
                  : undefined,
              currency,
            };
          }),
      );

    // Costs in different currencies don't order against each other, so
    // options sort by currency first, then by cost.
    return options.sort(
      (a, b) => a.currency.localeCompare(b.currency) || a.cost - b.cost,
    );
  }

  // Cheapest and fastest only rank options priced in the customer's currency.
  get comparableOptions() {
    let code = this.selectedShipment?.customerPaid?.currency?.code;
    let options = this.rateOptions;
    return code ? options.filter((o) => o.currency === code) : options;
  }

  get cheapestOption() {
    return this.comparableOptions[0];
  }

  get fastestOption() {
    return [...this.comparableOptions].sort((a, b) => a.days - b.days)[0];
  }

  queueKey = (shipment: Shipment, index: number) =>
    shipment.id ?? String(index);

  queueLabel = (shipment: Shipment) => shipment.shipmentNumber ?? 'Shipment';

  get selectedQueueKeys(): string[] {
    return this.selectedShipmentId ? [this.selectedShipmentId] : [];
  }

  @action chooseQueued(_keys: unknown[], rows: Shipment[]) {
    this.selectShipment(rows[0]?.id);
  }

  @action selectShipment(id: string | undefined) {
    this.selectedShipmentId = id;
  }

  // ── Rendering helpers ────────────────────────────────────────────────────

  @action setTab(key: string) {
    this.tab = key;
  }

  get currentTab() {
    return TABS.find((t) => t.key === this.tab) ?? TABS[0];
  }

  get navItems() {
    let badge: Record<string, string> = {
      board: String(this.boardOrders.length),
      inventory: `${this.outOfStock.length} out`,
      ship: String(this.ordersAwaitingShipment.length),
      transit: String(this.inTransit.length),
      returns: String(this.openReturns.length),
    };
    return TABS.map((t) => ({
      ...t,
      icon: NAV_ICONS[t.key],
      badge: badge[t.key],
    }));
  }

  get activeCarriers() {
    return this.carriers.filter((c) => c.isActive !== false);
  }

  get stats(): StatTile[] {
    switch (this.tab) {
      case 'inventory':
        return [
          {
            label: 'Stock rows',
            value: this.stock.length,
            hint: 'across all warehouses',
          },
          {
            label: 'Low stock',
            value: this.lowStock.length,
            hint: 'flagged low',
            tone: 'warning',
          },
          {
            label: 'Out of stock',
            value: this.outOfStock.length,
            hint: 'SKUs at zero available',
            tone: 'destructive',
          },
          {
            label: 'Warehouses',
            value: this.warehouses.length,
            hint: 'on file',
          },
        ];
      case 'ship':
        return [
          {
            label: 'Awaiting parcel',
            value: this.ordersAwaitingShipment.length,
            hint: 'packed, no shipment yet',
            tone: 'warning',
          },
          {
            label: 'Labelled',
            value: this.shipDeskQueue.length,
            hint: 'ready to rate and dispatch',
          },
          {
            label: 'Carriers',
            value: this.activeCarriers.length,
            hint: 'active on the desk',
          },
        ];
      case 'transit':
        return [
          {
            label: 'On the road',
            value: this.inTransit.length,
            hint: 'in transit or out for delivery',
            tone: 'info',
          },
          {
            label: 'Delivered',
            value: this.deliveredShipments.length,
            hint: 'landed',
            tone: 'success',
          },
          {
            label: 'Needs attention',
            value: this.needsAttention.length,
            hint: 'exception or past window',
            tone: 'destructive',
          },
          {
            label: 'Late',
            value: this.lateShipments.length,
            hint: 'past promised window',
            tone: 'warning',
          },
        ];
      case 'returns':
        return [
          {
            label: 'Open',
            value: this.openReturns.length,
            hint: 'awaiting resolution',
            tone: 'warning',
          },
          {
            label: 'Closed',
            value: this.closedReturns,
            hint: 'resolved',
            tone: 'success',
          },
          { label: 'All returns', value: this.returns.length, hint: 'on file' },
        ];
      default:
        return [
          {
            label: 'To fulfil',
            value: this.todayCount,
            hint: 'pending to packing',
          },
          {
            label: 'Express',
            value: this.expressCount,
            hint: 'ship first',
            tone: 'warning',
          },
          {
            label: 'In transit',
            value: this.inTransit.length,
            hint: `across ${plural(this.activeCarriers.length, 'carrier')}`,
          },
          {
            label: 'Needs attention',
            value: this.needsAttention.length,
            hint: 'carrier exceptions',
            tone: 'destructive',
          },
          {
            label: 'Out of stock',
            value: this.outOfStock.length,
            hint: 'SKUs at zero available',
            tone: 'destructive',
          },
        ];
    }
  }

  get primaryAction() {
    switch (this.tab) {
      case 'board':
        return { label: 'Add order', run: this.createOrder };
      case 'inventory':
        return { label: 'Add stock row', run: this.createStockRow };
      case 'returns':
        return { label: 'Add return', run: this.createReturn };
      default:
        return undefined;
    }
  }

  get searchSpec() {
    switch (this.tab) {
      case 'board':
        return {
          value: this.boardSearch,
          set: this.setBoardSearch,
          placeholder: 'Search order number, customer or SKU',
        };
      case 'inventory':
        return {
          value: this.inventorySearch,
          set: this.setInventorySearch,
          placeholder: 'Search SKU, product, bin or warehouse',
        };
      case 'transit':
        return {
          value: this.transitSearch,
          set: this.setTransitSearch,
          placeholder: 'Search shipment, order, carrier or tracking number',
        };
      case 'returns':
        return {
          value: this.returnsSearch,
          set: this.setReturnsSearch,
          placeholder: 'Search RMA, customer, reason or order',
        };
      default:
        return undefined;
    }
  }

  get chipSpec() {
    switch (this.tab) {
      case 'inventory':
        return {
          options: this.inventoryChipOptions,
          value: this.inventoryStatus,
          set: this.chooseInventoryStatus,
        };
      case 'transit':
        return {
          options: this.transitChipOptions,
          value: this.transitStatus,
          set: this.chooseTransitStatus,
        };
      case 'returns':
        return {
          options: this.returnsChipOptions,
          value: this.returnsStatus,
          set: this.chooseReturnsStatus,
        };
      default:
        return undefined;
    }
  }

  get viewSpec() {
    switch (this.tab) {
      case 'inventory':
        return { value: this.inventoryView, set: this.setInventoryView };
      case 'returns':
        return { value: this.returnsView, set: this.setReturnsView };
      default:
        return undefined;
    }
  }

  get inventoryChipOptions() {
    return chipOptions(this.inventoryBadges);
  }

  get returnsChipOptions() {
    return chipOptions(this.returnsBadges);
  }

  get transitChipOptions() {
    return chipOptions(this.transitBadges);
  }

  @action chooseInventoryStatus(value: string) {
    this.setInventoryStatus(value as 'all' | 'low' | 'out');
  }

  @action chooseReturnsStatus(value: string) {
    this.setReturnsStatus(value as 'all' | 'open' | 'closed');
  }

  @action chooseTransitStatus(value: string) {
    this.setTransitStatus(
      value as 'transit' | 'delivered' | 'attention' | 'all',
    );
  }

  <template>
    <Sidebar
      class='of-shell'
      @label='Order Fulfilment'
      @collapsible='rail'
      @railBreakpoint={{1100}}
      @mobileBreakpoint={{720}}
      @scroll='content'
      @resizable={{true}}
      @width='13.5rem'
      @shortcut={{false}}
    >
      <:header as |bar|>
        <div class='of-brand'>
          <span class='of-mark' aria-hidden='true'>OF</span>
          {{#unless bar.collapsed}}
            <p class='of-brand-text'>
              Order Fulfilment
              <small>{{@model.operationName}}</small>
            </p>
          {{/unless}}
        </div>
      </:header>
      <:nav as |bar|>
        <SidebarGroup @label='Fulfilment'>
          {{#each this.navItems as |item|}}
            <SidebarItem
              @label={{item.label}}
              @icon={{item.icon}}
              @badge={{unless bar.collapsed item.badge}}
              @active={{eq this.tab item.key}}
              @collapsed={{bar.collapsed}}
              @onClick={{fn this.setTab item.key}}
            />
          {{/each}}
        </SidebarGroup>
      </:nav>
      <:default as |bar|>
        <div
          class='of-layout
            {{if (eq this.tab "ship") (if this.selectedShipment "has-aside")}}'
        >
          <main class='of-main'>
            {{#if bar.mobile}}
              <SidebarTrigger
                @open={{bar.open}}
                @onToggle={{bar.toggle}}
                @controls={{bar.controls}}
                @label='navigation'
              />
            {{/if}}
            <header class='of-head'>
              <p class='eyebrow'>Order Fulfilment · Fulfilment</p>
              <h1 class='of-h1'>{{this.currentTab.label}}</h1>
              <p class='of-sub'>{{this.currentTab.sub}}</p>
            </header>

            {{#if this.isInteractive}}
              {{#if this.searchSpec}}
                <LayoutControl
                  @label='{{this.currentTab.label}} tools'
                  @controlHeight='1.625rem'
                  as |lc|
                >
                  <lc.Slot
                    @id='search'
                    @priority={{2}}
                    @forms={{SEARCH_FORMS}}
                    @label='Search'
                  >
                    <div class='of-search'><SearchInput
                        @value={{this.searchSpec.value}}
                        @placeholder={{this.searchSpec.placeholder}}
                        @onInput={{this.searchSpec.set}}
                      /></div>
                  </lc.Slot>
                  {{#if this.chipSpec}}
                    <lc.Slot
                      @id='status'
                      @priority={{3}}
                      @forms={{CHIP_FORMS}}
                      @label='Show'
                    >
                      <FilterChips
                        @options={{this.chipSpec.options}}
                        @value={{this.chipSpec.value}}
                        @onValueChange={{this.chipSpec.set}}
                        @label='Show'
                      />
                    </lc.Slot>
                  {{/if}}
                  {{#if this.viewSpec}}
                    <lc.Slot
                      @id='view'
                      @priority={{1}}
                      @forms={{VIEW_FORMS}}
                      @label='View'
                    >
                      <SegmentedControl
                        class='of-push'
                        @label='View'
                        @options={{VIEW_OPTIONS}}
                        @value={{this.viewSpec.value}}
                        @onValueChange={{this.viewSpec.set}}
                      />
                    </lc.Slot>
                  {{/if}}
                  {{#if this.primaryAction}}
                    <lc.Slot
                      @id='add'
                      @priority={{0}}
                      @pinned={{true}}
                      @forms={{ADD_FORMS}}
                      @label={{this.primaryAction.label}}
                      as |form|
                    >
                      <Button
                        class={{unless this.viewSpec 'of-push'}}
                        @icon={{PlusIcon}}
                        @tone='primary'
                        @size='s'
                        @display={{if (eq form 'icon') 'icon' 'label'}}
                        @label={{this.primaryAction.label}}
                        {{on 'click' this.primaryAction.run}}
                      >{{this.primaryAction.label}}</Button>
                    </lc.Slot>
                  {{/if}}
                </LayoutControl>
              {{/if}}

              <section
                class='of-stats'
                aria-label='{{this.currentTab.label}} totals'
              >
                <div class='of-stat-cells' data-count={{this.stats.length}}>
                  {{#each this.stats as |st|}}
                    <div class='of-stat'>
                      <Stat
                        @label={{st.label}}
                        @value={{st.value}}
                        @tone={{st.tone}}
                        @hint={{st.hint}}
                        @roll={{false}}
                      />
                    </div>
                  {{/each}}
                </div>
              </section>

              {{#if (eq this.tab 'board')}}
                <section class='block'>
                  <div class='block-head'>
                    <h2>Order fulfilment board</h2>
                    <p class='block-meta'>{{this.boardOrders.length}}
                      open orders</p>
                  </div>
                  <Board
                    class='of-board'
                    @items={{this.boardOrders}}
                    @columns={{this.boardColumns}}
                    @columnKeyFor={{this.columnKeyFor}}
                    @onMove={{this.moveOrder}}
                    @onOpen={{this.openCard}}
                    @cardSize='regular-tile'
                    @boardLabel='Order fulfilment board'
                    @emptyMessage={{this.boardEmptyMessage}}
                  >
                    <:card as |card|>
                      {{#let (asOrder card) as |order|}}
                        <div class='bc'>
                          <p class='bc-top'>
                            <span
                              class='mono muted'
                            >{{order.orderNumber}}</span>
                            {{#if order.isExpress}}
                              <span class='status'><span
                                  class='dot'
                                  style={{hue 'var(--warning)'}}
                                ></span>Express</span>
                            {{/if}}
                            <span class='mono bc-total'>{{money
                                order.total.amount
                                order.currencyCode
                              }}</span>
                          </p>
                          <p class='strong'>{{order.customerName}}</p>
                          {{#let (get order.lineItems 0) as |line|}}
                            {{#if line}}
                              <p class='bc-line'>{{line.productName}}
                                ·
                                {{line.sku}}</p>
                            {{/if}}
                          {{/let}}
                          <p class='muted'>{{plural order.itemCount 'item'}}
                            {{#if order.warehouseCode}}
                              ·
                              {{order.warehouseCode}}{{/if}}</p>
                        </div>
                      {{/let}}
                    </:card>
                  </Board>
                </section>

                {{#if this.pickLists.length}}
                  <section class='block'>
                    <div class='block-head'>
                      <h2>Pick lists on the floor</h2>
                      <p class='block-meta'>{{this.pickLists.length}}
                        active</p>
                    </div>
                    <div class='tbl-wrap'>
                      <Table class='tbl' @framed={{false}} @striped={{false}}>
                        <:head><tr>
                            <th>Pick list</th>
                            <th>Assigned to</th>
                            <th>Next pick</th>
                            <th class='num'>Picked</th>
                          </tr></:head>
                        <:body>
                          {{#each this.pickLists as |pl|}}
                            <tr>
                              <td><Button
                                  class='link mono'
                                  @tone='neutral'
                                  @appearance='link'
                                  @size='s'
                                  {{on 'click' (fn this.openCard pl)}}
                                >{{pl.pickListNumber}}</Button></td>
                              <td>
                                {{#if pl.assignedTo}}
                                  <span class='unit'><Avatar
                                      @name={{pl.assignedTo}}
                                      @size={{18}}
                                    />{{pl.assignedTo}}</span>
                                {{else}}—{{/if}}
                              </td>
                              <td>
                                {{#if pl.nextItem}}
                                  <span
                                    class='strong'
                                  >{{pl.nextItem.productName}}</span>
                                  <span
                                    class='mono muted'
                                  >{{pl.nextItem.sku}}</span>
                                {{else}}—{{/if}}
                              </td>
                              <td class='num mono'>{{pl.doneCount}}
                                /
                                {{pl.route.length}}</td>
                            </tr>
                          {{/each}}
                        </:body>
                      </Table>
                    </div>
                  </section>
                {{/if}}
              {{/if}}

              {{#if (eq this.tab 'inventory')}}
                <section class='block'>
                  <div class='block-head'><h2>Warehouses</h2></div>
                  {{#if this.hasWarehouseMap}}
                    <div class='of-map'>
                      <MapRender
                        @coordinates={{this.warehousePoints}}
                        @mapConfig={{this.mapConfig}}
                      />
                    </div>
                  {{/if}}
                  <div class='tbl-wrap'>
                    <Table class='tbl' @framed={{false}} @striped={{false}}>
                      <:body>
                        {{#each this.warehouseSummary as |w|}}
                          <tr>
                            <td class='mono muted'>{{w.warehouse.code}}</td>
                            <td><Button
                                class='link strong'
                                @tone='neutral'
                                @appearance='link'
                                @size='s'
                                {{on 'click' (fn this.openCard w.warehouse)}}
                              >{{w.warehouse.warehouseName}}</Button></td>
                            <td class='muted'>{{plural w.skuCount 'SKU'}}
                              {{#if (isNumber w.value)}}
                                ·
                                {{money w.value w.currency}}
                              {{/if}}</td>
                            <td class='of-util'>
                              {{#if w.isVirtual}}
                                <span class='muted'>Virtual, supplier ships
                                  direct</span>
                              {{else if w.utilization}}
                                <ProgressBar
                                  @value={{w.utilization}}
                                  @label='{{w.utilization}}% of bins filled'
                                />
                              {{else}}—{{/if}}
                            </td>
                          </tr>
                        {{/each}}
                      </:body>
                    </Table>
                  </div>
                </section>

                <section class='block'>
                  <div class='block-head'>
                    <h2>Stock rows</h2>
                    <p class='block-meta'>{{this.inventoryRows.length}}</p>
                  </div>
                  {{#if this.inventoryQuery}}
                    {{#if (this.isCardListView this.inventoryView)}}
                      <div class='block-body'><CardList
                          @context={{@context}}
                          @query={{this.inventoryQuery}}
                          @realms={{this.realmList}}
                          @format='fitted'
                          @isLive={{true}}
                          @viewOption={{this.viewOptionFor this.inventoryView}}
                        /></div>
                    {{else}}
                      <div class='tbl-wrap'>
                        <Table class='tbl' @framed={{false}} @striped={{false}}>
                          <:head><tr>
                              <th>SKU</th>
                              <th>Product</th>
                              <th>Warehouse</th>
                              <th>Bin</th>
                              <th class='num'>On hand</th>
                              <th class='num'>Reserved</th>
                              <th class='num'>Available</th>
                              <th class='num'>Incoming</th>
                              <th>State</th>
                            </tr></:head>
                          <:body>
                            {{#each this.inventoryRows as |row|}}
                              <tr>
                                <td><Button
                                    class='link mono'
                                    @tone='neutral'
                                    @appearance='link'
                                    @size='s'
                                    {{on 'click' (fn this.openCard row)}}
                                  >{{row.sku}}</Button></td>
                                <td class='strong'>{{row.productName}}</td>
                                <td
                                  class='mono muted'
                                >{{row.warehouseCode}}</td>
                                <td class='mono muted'>{{row.binLocation}}</td>
                                <td class='num mono'>{{row.quantityOnHand}}</td>
                                <td
                                  class='num mono'
                                >{{row.quantityReserved}}</td>
                                <td
                                  class='num mono'
                                >{{row.quantityAvailable}}</td>
                                <td
                                  class='num mono'
                                >{{row.quantityIncoming}}</td>
                                <td><span class='status'><span
                                      class='dot'
                                      style={{stockHue row}}
                                    ></span>{{row.stockStateLabel}}</span></td>
                              </tr>
                            {{/each}}
                          </:body>
                        </Table>
                      </div>
                      {{#unless this.inventoryRows.length}}
                        <EmptyState
                          @size='s'
                          @texture={{false}}
                          @title={{if
                            this.inventoryLoading
                            'Loading stock…'
                            'No stock rows match this filter'
                          }}
                          @message='Add a stock row, or clear the search and filter.'
                        />
                      {{/unless}}
                    {{/if}}
                  {{/if}}
                </section>
              {{/if}}

              {{#if (eq this.tab 'ship')}}
                <section class='block'>
                  <div class='block-head'>
                    <h2>Step 1 · Packed, needs a parcel</h2>
                    <p class='block-meta'>Create a parcel for each packed order.</p>
                  </div>
                  {{#if this.ordersAwaitingShipment.length}}
                    <div class='tbl-wrap'>
                      <Table class='tbl' @framed={{false}} @striped={{false}}>
                        <:body>
                          {{#each this.ordersAwaitingShipment as |o|}}
                            <tr>
                              <td><Button
                                  class='link mono'
                                  @tone='neutral'
                                  @appearance='link'
                                  @size='s'
                                  {{on 'click' (fn this.openCard o)}}
                                >{{o.orderNumber}}</Button></td>
                              <td><span class='unit'><Avatar
                                    @name={{o.customerName}}
                                    @size={{18}}
                                  />{{o.customerName}}</span></td>
                              <td class='muted'>{{plural
                                  o.itemCount
                                  'item'
                                }}</td>
                              <td class='num mono'>{{money
                                  o.total.amount
                                  o.currencyCode
                                }}</td>
                              <td class='num'><Button
                                  @size='s'
                                  @appearance='plain'
                                  {{on 'click' (fn this.createShipmentFor o)}}
                                >Create parcel</Button></td>
                            </tr>
                          {{/each}}
                        </:body>
                      </Table>
                    </div>
                  {{else}}
                    <EmptyState
                      @size='s'
                      @texture={{false}}
                      @title={{if
                        this.ordersLoading
                        'Loading orders…'
                        'No packed order is waiting'
                      }}
                      @message='Move an order to Packing on the board and it appears here.'
                    />
                  {{/if}}
                </section>

                <section class='block'>
                  <div class='block-head'>
                    <h2>Step 2 · Labelled, ready to dispatch</h2>
                    <p class='block-meta'>Select a parcel to rate it.</p>
                  </div>
                  {{#if this.shipDeskQueue.length}}
                    <ul class='rows'>
                      {{#each this.shipDeskQueue as |s|}}
                        <li><button
                            type='button'
                            class='row-pick mono'
                            aria-pressed={{if
                              (eq s.id this.selectedShipment.id)
                              'true'
                              'false'
                            }}
                            {{on 'click' (fn this.selectShipment s.id)}}
                          >{{s.shipmentNumber}}</button></li>
                      {{/each}}
                    </ul>
                  {{else}}
                    <EmptyState
                      @size='s'
                      @texture={{false}}
                      @title={{if
                        this.shipmentsLoading
                        'Loading shipments…'
                        'Nothing has a label yet'
                      }}
                      @message='Create a parcel above and it arrives here for rating and dispatch.'
                    />
                  {{/if}}
                </section>
              {{/if}}

              {{#if (eq this.tab 'transit')}}
                {{#if this.showAttentionBanner}}
                  <section class='block'>
                    <div class='block-head'>
                      <h2>Needs attention</h2>
                      <p class='block-meta'>{{this.needsAttention.length}}</p>
                    </div>
                    <div class='tbl-wrap'>
                      <Table class='tbl' @framed={{false}} @striped={{false}}>
                        <:body>
                          {{#each this.needsAttention as |s|}}
                            <tr>
                              <td><Button
                                  class='link mono'
                                  @tone='neutral'
                                  @appearance='link'
                                  @size='s'
                                  {{on 'click' (fn this.openCard s)}}
                                >{{s.shipmentNumber}}</Button></td>
                              <td class='wide'><span class='status'><span
                                    class='dot'
                                    style={{hue 'var(--destructive)'}}
                                  ></span>{{if
                                    s.latestEvent.statusDescription
                                    s.latestEvent.statusDescription
                                    'Past promised window'
                                  }}</span></td>
                              <td
                                class='num muted'
                              >{{s.latestEvent.location}}</td>
                            </tr>
                          {{/each}}
                        </:body>
                      </Table>
                    </div>
                  </section>
                {{/if}}

                <section class='block'>
                  <div class='block-head'>
                    <h2>Shipments</h2>
                    <p class='block-meta'>{{this.transitShipments.length}}</p>
                  </div>
                  {{#if this.transitVisible.length}}
                    <div class='tbl-wrap'>
                      <Table class='tbl' @framed={{false}} @striped={{false}}>
                        <:head><tr>
                            <th>Shipment</th>
                            <th>Carrier</th>
                            <th>Status</th>
                            <th>Progress</th>
                            <th>Last event</th>
                          </tr></:head>
                        <:body>
                          {{#each this.transitVisible as |s|}}
                            <tr>
                              <td><Button
                                  class='link mono'
                                  @tone='neutral'
                                  @appearance='link'
                                  @size='s'
                                  {{on 'click' (fn this.openCard s)}}
                                >{{s.shipmentNumber}}</Button></td>
                              <td class='strong'>{{s.carrierLabel}}
                                {{s.serviceLevel}}</td>
                              <td><span class='status'><span
                                    class='dot'
                                    style={{hue s.statusStyle.hue}}
                                  ></span>{{s.statusStyle.label}}</span></td>
                              <td class='of-progress'><ProgressBar
                                  @value={{shipmentProgress s.status}}
                                  aria-label='{{s.statusStyle.label}} progress'
                                /></td>
                              <td
                                class='muted'
                              >{{s.latestEvent.statusDescription}}
                                {{#if s.latestEvent.occurredAt}}
                                  ·
                                  {{stamp s.latestEvent.occurredAt}}
                                {{/if}}</td>
                            </tr>
                            {{#if (eq s.status 'delivered')}}
                              <tr class='tbl-detail'>
                                <td colspan='5'>
                                  <dl class='kv-row'>
                                    <div><dt class='eyebrow'>Delivered</dt>
                                      <dd>{{stamp s.deliveredAt}}</dd></div>
                                    <div><dt class='eyebrow'>Against promise</dt>
                                      <dd>{{#if s.deliveryWindow.latest}}{{if
                                            s.isLate
                                            'Late'
                                            'On time'
                                          }}{{else}}No promised window{{/if}}</dd></div>
                                    <div><dt class='eyebrow'>Proof of delivery</dt>
                                      <dd>{{if
                                          s.proofOfDelivery
                                          s.proofOfDelivery
                                          'Not recorded'
                                        }}</dd></div>
                                  </dl>
                                </td>
                              </tr>
                            {{/if}}
                          {{/each}}
                        </:body>
                      </Table>
                    </div>
                    {{#if this.transitHiddenCount}}
                      <div class='block-foot'><Button
                          @size='s'
                          @appearance='plain'
                          {{on 'click' this.showMoreTransit}}
                        >Show {{this.transitHiddenCount}} more</Button></div>
                    {{/if}}
                  {{else}}
                    <EmptyState
                      @size='s'
                      @texture={{false}}
                      @title={{if
                        this.shipmentsLoading
                        'Loading shipments…'
                        'Nothing to show'
                      }}
                      @message={{this.transitEmptyMessage}}
                    />
                  {{/if}}
                </section>
              {{/if}}

              {{#if (eq this.tab 'returns')}}
                <section class='block'>
                  <div class='block-head'>
                    <h2>Returns</h2>
                    <p class='block-meta'>{{this.returnsRows.length}}</p>
                  </div>
                  {{#if this.returnsQuery}}
                    {{#if (this.isCardListView this.returnsView)}}
                      <div class='block-body'><CardList
                          @context={{@context}}
                          @query={{this.returnsQuery}}
                          @realms={{this.realmList}}
                          @format='fitted'
                          @isLive={{true}}
                          @viewOption={{this.viewOptionFor this.returnsView}}
                        /></div>
                    {{else if this.returnsRows.length}}
                      <div class='tbl-wrap'>
                        <Table class='tbl' @framed={{false}} @striped={{false}}>
                          <:head><tr>
                              <th>RMA</th>
                              <th>Status</th>
                              <th>Customer · order</th>
                              <th>Reason</th>
                              <th class='num'>Items</th>
                              <th class='num'>Value</th>
                            </tr></:head>
                          <:body>
                            {{#each this.returnsRows as |rma|}}
                              <tr>
                                <td><Button
                                    class='link mono'
                                    @tone='neutral'
                                    @appearance='link'
                                    @size='s'
                                    {{on 'click' (fn this.openCard rma)}}
                                  >{{rma.rmaNumber}}</Button></td>
                                <td><span class='status'><span
                                      class='dot'
                                      style={{hue rma.statusStyle.hue}}
                                    ></span>{{rma.statusStyle.label}}</span></td>
                                <td><span
                                    class='strong'
                                  >{{rma.customerName}}</span>
                                  {{#if rma.orderNumber}}
                                    <span class='muted'>Order
                                      {{rma.orderNumber}}</span>
                                  {{/if}}</td>
                                <td class='muted'>{{rma.reasonLabel}}</td>
                                <td class='num mono'>{{plural
                                    rma.itemCount
                                    'item'
                                  }}</td>
                                <td class='num mono'>{{#if
                                    (isNumber rma.refundAmount.amount)
                                  }}{{money
                                      rma.refundAmount.amount
                                      rma.refundAmount.currency.code
                                    }}{{else}}—{{/if}}</td>
                              </tr>
                            {{/each}}
                          </:body>
                        </Table>
                      </div>
                    {{else}}
                      <EmptyState
                        @size='s'
                        @texture={{false}}
                        @title={{if
                          this.returnsLoading
                          'Loading returns…'
                          'No returns match this filter'
                        }}
                        @message='Add a return, or clear the search and filter.'
                      />
                    {{/if}}
                  {{/if}}
                </section>
              {{/if}}
            {{else}}
              <p class='of-sub'>Board, inventory, ship desk, tracking and
                returns load when this app is opened in the workspace.</p>
            {{/if}}
          </main>

          {{#if (eq this.tab 'ship')}}
            {{#if this.selectedShipment}}
              <aside class='of-aside' aria-label='Parcel'>
                <section class='aside-block'>
                  <div class='aside-head'>
                    <h2>Parcel</h2>
                    <p
                      class='strong'
                    >{{this.selectedShipment.shipmentNumber}}</p>
                    <p class='muted'>Order
                      {{this.selectedShipment.orderNumber}}
                      · from
                      {{this.selectedShipment.originCode}}</p>
                  </div>
                  <dl class='kv'>
                    <div><dt class='eyebrow'>Measured</dt>
                      <dd>{{this.selectedShipment.parcel.sizeLabel}}</dd></div>
                    <div><dt class='eyebrow'>Weight</dt>
                      <dd>{{#if
                          this.selectedShipment.parcel.weight
                        }}{{this.selectedShipment.parcel.weight}}
                          kg{{else}}—{{/if}}</dd></div>
                    <div><dt class='eyebrow'>Customer paid</dt>
                      <dd>{{money
                          this.selectedShipment.customerPaid.amount
                          this.selectedShipment.customerPaid.currency.code
                        }}</dd></div>
                  </dl>
                  <div class='aside-action'><Button
                      @tone='primary'
                      @size='s'
                      {{on 'click' (fn this.openCard this.selectedShipment)}}
                    >Open shipment to dispatch</Button></div>
                </section>
                <section class='aside-block'>
                  <div class='aside-head'>
                    <h2>Rate comparison</h2>
                    <p class='muted'>Priced from the services configured on your
                      carrier cards, against this parcel's billable weight. No
                      carrier API is called.</p>
                  </div>
                  <ul class='rows'>
                    {{#each this.rateOptions as |opt|}}
                      <li class='rate'>
                        <div>
                          <p class='strong'>{{opt.carrierName}}
                            {{opt.serviceName}}</p>
                          <p class='muted'>{{opt.speed}}
                            ·
                            {{opt.billable}}
                            kg billable</p>
                          {{#if (eq opt.key this.cheapestOption.key)}}
                            <span class='status'><span
                                class='dot'
                                style={{hue 'var(--success)'}}
                              ></span>Cheapest</span>
                          {{else if (eq opt.key this.fastestOption.key)}}
                            <span class='status'><span
                                class='dot'
                                style={{hue 'var(--info)'}}
                              ></span>Fastest</span>
                          {{/if}}
                        </div>
                        <div class='rate-nums'>
                          <p class='mono strong'>{{money
                              opt.cost
                              opt.currency
                            }}</p>
                          {{#if (isNumber opt.margin)}}
                            <p
                              class='muted {{if (lt opt.margin 0) "neg"}}'
                            >{{money opt.margin opt.currency}} margin</p>
                          {{/if}}
                        </div>
                      </li>
                    {{else}}
                      <li class='muted'>No carrier has a priced service yet. Add
                        one on a Carrier card and it appears here.</li>
                    {{/each}}
                  </ul>
                </section>
              </aside>
            {{/if}}
          {{/if}}
        </div>
      </:default>
    </Sidebar>

    <style scoped>
      .of-shell {
        container-type: inline-size;
        block-size: 100%;
        min-block-size: 0;
        background: var(--background);
        color: var(--foreground);
        font-family: var(--font-sans);
        font-size: var(--boxel-font-size-xs);
      }
      p {
      }
      .of-brand {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
      }
      .of-mark {
        display: grid;
        place-items: center;
        flex: none;
        inline-size: 1.75rem;
        block-size: 1.75rem;
        border: 1px solid var(--border);
        border-radius: var(--radius);
        font-family: var(--font-mono);
        font-size: 0.5625rem; /* ladder 9px label: no Boxel token below 11px */
        font-weight: 600;
        line-height: 1;
      }
      .of-brand-text {
        display: grid;
        min-inline-size: 0;
        font-weight: 700;
        line-height: 1.2;
      }
      .of-brand-text small {
        font-weight: 600;
        color: var(--muted-foreground);
      }
      .eyebrow {
        font-family: var(--font-mono);
        font-size: 0.5625rem; /* ladder 9px label: no Boxel token below 11px */
        font-weight: 600;
        line-height: 1.3;
        letter-spacing: 0.13em;
        text-transform: uppercase;
        color: var(--muted-foreground);
      }

      /* main column + a parcel panel docked flush to the right edge */
      .of-layout {
        display: grid;
        grid-template-columns: minmax(0, 1fr);
        min-block-size: 100%;
      }
      .of-layout.has-aside {
        grid-template-columns: minmax(0, 1fr) 22.5rem;
      }
      .of-main {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
        min-inline-size: 0;
        padding: var(--boxel-sp-lg) var(--boxel-sp-lg) var(--boxel-sp-xl);
      }
      .of-aside {
        min-inline-size: 0;
        border-inline-start: 1px solid var(--border);
        background: var(--card);
        color: var(--card-foreground);
      }
      @container (width < 60rem) {
        .of-layout.has-aside {
          grid-template-columns: minmax(0, 1fr);
        }
        .of-aside {
          border-inline-start: 0;
          border-block-start: 1px solid var(--border);
        }
      }

      .of-head {
        display: grid;
        gap: var(--boxel-sp-4xs);
      }
      .of-h1 {
        font-family: var(--boxel-heading-font-family, var(--font-sans));
        font-weight: 400;
        font-size: 2.5rem; /* ladder 40px page title: no Boxel display token */
        line-height: 1;
        text-transform: uppercase;
      }
      .of-sub {
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
      }
      .of-search {
        inline-size: 17.5rem;
      }
      .of-push {
        margin-inline-start: auto;
      }

      /* stat strip: every cell draws its right and bottom line and the frame
         clips the overhang, so a wrapped row keeps all its dividers */
      .of-stats {
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
        overflow: hidden;
      }
      .of-stat-cells {
        --text-stat: 1.375rem;
        display: grid;
        grid-template-columns: repeat(var(--cols, 5), minmax(0, 1fr));
        margin: 0 -1px -1px 0;
      }
      .of-stat-cells[data-count='3'] {
        --cols: 3;
      }
      .of-stat-cells[data-count='4'] {
        --cols: 4;
      }
      .of-stat {
        min-inline-size: 0;
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        box-shadow:
          1px 0 0 var(--border),
          0 1px 0 var(--border);
      }
      @container (width <= 48rem) {
        .of-stat-cells {
          --cols: 3;
        }
      }
      @container (width <= 30rem) {
        .of-stat-cells[data-count] {
          --cols: 2;
        }
      }

      /* one flat block: radius on the outside only, hairline sections inside */
      .block {
        min-inline-size: 0;
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
        border-block-end: 1px solid var(--border);
      }
      .block-head h2,
      .aside-head h2 {
        margin: 0;
        font-size: var(--boxel-font-size-xs);
        font-weight: 700;
      }
      .block-meta {
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
      }
      .block-body {
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
      }
      .block-foot {
        padding: var(--boxel-sp-4xs) var(--boxel-sp-sm);
        border-block-start: 1px solid var(--border);
      }
      .of-board {
        min-block-size: 22rem;
      }
      .of-map {
        block-size: 10rem;
        border-block-end: 1px solid var(--border);
      }

      /* ruled table: equal 28px rows, one hairline between, mono caps head */
      .tbl-wrap {
        overflow-x: auto;
      }
      .tbl th {
        padding: var(--boxel-sp-5xs) var(--boxel-sp-sm);
        text-align: start;
        white-space: nowrap;
        font-family: var(--font-mono);
        font-size: 0.5625rem; /* ladder 9px label: no Boxel token below 11px */
        font-weight: 600;
        line-height: 1.3;
        letter-spacing: 0.13em;
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .tbl td {
        block-size: 1.75rem;
        padding: 0 var(--boxel-sp-sm);
        white-space: nowrap;
      }
      .tbl .num {
        text-align: end;
      }
      .tbl .wide {
        inline-size: 100%;
      }
      .tbl-detail td {
        padding-block: var(--boxel-sp-4xs);
        background: var(--muted);
      }
      .of-util {
        inline-size: 30%;
      }
      .of-progress {
        inline-size: 6.5rem;
      }

      .mono {
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-2xs);
        font-variant-numeric: tabular-nums;
      }
      .strong {
        font-weight: 600;
      }
      .muted {
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
      }
      .neg {
        color: var(--destructive-ink);
      }
      .unit {
        display: inline-flex;
        align-items: center;
        gap: var(--boxel-sp-4xs);
      }
      .status {
        display: inline-flex;
        align-items: center;
        gap: var(--boxel-sp-5xs);
        font-weight: 600;
      }
      .dot {
        flex: none;
        inline-size: 0.375rem;
        block-size: 0.375rem;
        border-radius: 50%;
        background: var(--dot);
      }
      .link {
        color: inherit;
        text-align: start;
      }
      .link.mono {
        color: var(--muted-foreground);
      }
      @media (hover: hover) {
        .link:hover {
          text-decoration: underline;
        }
      }
      .link:focus-visible,
      .row-pick:focus-visible {
        outline: 2px solid var(--ring);
        outline-offset: 1px;
      }

      /* board card face */
      .bc {
        display: grid;
        align-content: start;
        gap: var(--boxel-sp-5xs);
        block-size: 100%;
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        border-block-end: 1px solid var(--border);
        background: var(--card);
        color: var(--card-foreground);
        cursor: pointer;
      }
      .bc-top {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
      }
      .bc-total {
        margin-inline-start: auto;
      }
      .bc-line {
        font-size: var(--boxel-font-size-2xs);
      }

      .rows {
        display: grid;
        margin: 0;
        padding: 0;
        list-style: none;
      }
      .rows > li + li {
        border-block-start: 1px solid var(--border);
      }
      .row-pick {
        display: block;
        inline-size: 100%;
        block-size: 1.75rem;
        padding: 0 var(--boxel-sp-sm);
        border: 0;
        border-inline-start: 2px solid transparent;
        background: none;
        color: var(--muted-foreground);
        text-align: start;
      }
      .row-pick[aria-pressed='true'] {
        border-inline-start-color: var(--foreground);
        background: var(--muted);
        color: var(--foreground);
      }

      /* docked parcel panel */
      .aside-block + .aside-block {
        border-block-start: 1px solid var(--border);
      }
      .aside-head {
        display: grid;
        gap: var(--boxel-sp-5xs);
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
      }
      .aside-action {
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
      }
      .kv {
        margin: 0;
        border-block: 1px solid var(--border);
      }
      .kv > div {
        display: grid;
        grid-template-columns: 7.5rem minmax(0, 1fr);
        align-items: center;
        block-size: 1.75rem;
        padding: 0 var(--boxel-sp-sm);
      }
      .kv > div + div {
        border-block-start: 1px solid var(--border);
      }
      .kv dd,
      .kv-row dd {
        margin: 0;
      }
      .kv-row {
        display: grid;
        grid-template-columns: repeat(3, minmax(0, 1fr));
        gap: var(--boxel-sp-sm);
        margin: 0;
      }
      .rate {
        display: flex;
        justify-content: space-between;
        gap: var(--boxel-sp-sm);
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
      }
      .rate-nums {
        text-align: end;
      }
      .aside-block .rows {
        border-block-start: 1px solid var(--border);
      }
    </style>
  </template>
}
