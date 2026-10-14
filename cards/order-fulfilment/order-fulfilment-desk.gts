import type { OrderFulfilmentApp } from './order-fulfilment-app';
import { BoardPanel } from './board-panel';
import { InventoryPanel } from './inventory-panel';
import { ShipDeskPanel } from './ship-desk-panel';
import { TransitPanel } from './transit-panel';
import { ReturnsPanel } from './returns-panel';
import { CardDef, Component, realmURL } from '@cardstack/base/card-api';
import {
  identifyCard,
  type getCards,
  type CodeRef,
  type Filter,
  type Query,
} from '@cardstack/runtime-common';
import { type TableColumn } from '../../components/table';
import { action } from '@ember/object';
import { cached, tracked } from '@glimmer/tracking';
import { debounce } from 'lodash-es';
import type Owner from '@ember/owner';
import TriangleAlert from '@cardstack/boxel-icons/triangle-alert';
import { FulfilmentOrder } from '../fulfilment/fulfilment-order';
import { Shipment } from '../fulfilment/shipment';
import { InventoryStock } from '../fulfilment/inventory-stock';
import { Warehouse } from '../fulfilment/warehouse';
import { Carrier, quoteService } from '../fulfilment/carrier';
import { ProductReturn } from '../fulfilment/product-return';
import { PickList } from '../fulfilment/pick-list';
import { ORDER_STATUSES } from '../fulfilment/order-status';
import { isShipmentException } from '../fulfilment/shipment-status';
import { type Coordinate } from '../../components/map-render';
import StatusChip from '../fulfilment/fulfilment-status-chip';
import { money } from '../fulfilment/fulfilment-format';
import { Tabs } from '@cardstack/pretui/components/tabs';
import {
  TABS,
  chipOptions,
  BOARD_COLUMNS,
  TRANSIT_PAGE,
  VIEW_OPTION,
  byType,
  eq,
} from './order-fulfilment-helpers';

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
  @tracked transitStatus: 'transit' | 'delivered' | 'attention' | 'all' =
    'transit';
  // Inventory defaults to the table: a stock row is six numeric columns, and
  // that is what a table is for. Returns defaults to the grid — an RMA reads as
  // a card. Both offer the other view; neither is forced into the wrong shape.
  @tracked inventoryView = 'table';
  @tracked returnsView = 'grid';
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

  inventoryColumns: TableColumn[] = [
    { key: 'sku', label: 'SKU', value: (r: any) => r.sku },
    { key: 'product', label: 'Product', value: (r: any) => r.productName },
    {
      key: 'warehouse',
      label: 'Warehouse',
      value: (r: any) => r.warehouseCode,
    },
    { key: 'bin', label: 'Bin', value: (r: any) => r.binLocation },
    {
      key: 'onHand',
      label: 'On hand',
      align: 'right',
      value: (r: any) => r.quantityOnHand,
    },
    {
      key: 'reserved',
      label: 'Reserved',
      align: 'right',
      value: (r: any) => r.quantityReserved,
    },
    {
      key: 'available',
      label: 'Available',
      align: 'right',
      value: (r: any) => r.quantityAvailable,
    },
    {
      key: 'incoming',
      label: 'Incoming',
      align: 'right',
      value: (r: any) => r.quantityIncoming,
    },
    // Custom so the cell can render the status chip. `sortValue` sorts by the
    // indexed state rather than by the chip's label, which is what a reader
    // means by "sort by status".
    {
      key: 'state',
      label: 'State',
      custom: true,
      value: (r: any) => r.stockState,
      sortValue: (r: any) => r.stockState,
    },
  ];

  returnsColumns: TableColumn[] = [
    { key: 'rma', label: 'RMA', value: (r: any) => r.rmaNumber },
    { key: 'customer', label: 'Customer', value: (r: any) => r.customerName },
    { key: 'order', label: 'Order', value: (r: any) => r.order?.orderNumber },
    { key: 'reason', label: 'Reason', value: (r: any) => r.reason },
    {
      key: 'items',
      label: 'Items',
      align: 'right',
      value: (r: any) => r.itemCount,
    },
    // Money renders through `money` for one format across the card, but sorts on
    // the raw amount — sorting the formatted string would put £9.00 after £10.00.
    {
      key: 'refund',
      label: 'Refund',
      align: 'right',
      value: (r: any) =>
        r.refundAmount?.amount == null
          ? null
          : money(r.refundAmount.amount, r.refundAmount.currency?.code),
      sortValue: (r: any) => r.refundAmount?.amount,
    },
    {
      key: 'state',
      label: 'State',
      custom: true,
      value: (r: any) => r.status,
      sortValue: (r: any) => r.lifecycleState,
    },
  ];

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

  tabOptions = TABS.map((t) => ({ value: t.key, label: t.label }));

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

  get statusLegend() {
    return ORDER_STATUSES.filter((s) =>
      BOARD_COLUMNS.some((c) => c.key === s.value),
    );
  }

  <template>
    <div class='app'>
      <header class='masthead'>
        <div class='brand'>
          <span class='brand-mark' aria-hidden='true'>
            <span></span><span></span><span></span><span></span><span></span>
          </span>
          <div>
            <h1 class='brand-name'>{{@model.operationName}}</h1>
            <p class='brand-sub'>Order fulfilment · {{@model.cardTitle}}</p>
          </div>
        </div>

        <dl class='counters'>
          <div>
            <dt>To fulfil</dt>
            <dd>{{if this.ordersLoading '—' this.todayCount}}</dd>
          </div>
          <div>
            <dt>Express</dt>
            <dd>{{if this.ordersLoading '—' this.expressCount}}</dd>
          </div>
          <div>
            <dt>In transit</dt>
            <dd>{{if this.shipmentsLoading '—' this.inTransit.length}}</dd>
          </div>
          <div class='{{if this.needsAttention.length "alarm"}}'>
            <dt>{{#if this.needsAttention.length}}<TriangleAlert
                  class='dt-alarm'
                  width='11'
                  height='11'
                  role='presentation'
                />{{/if}}Needs attention</dt>
            <dd>{{if this.shipmentsLoading '—' this.needsAttention.length}}</dd>
          </div>
          <div class='{{if this.outOfStock.length "alarm"}}'>
            <dt>{{#if this.outOfStock.length}}<TriangleAlert
                  class='dt-alarm'
                  width='11'
                  height='11'
                  role='presentation'
                />{{/if}}Out of stock</dt>
            <dd>{{if this.stockLoading '—' this.outOfStock.length}}</dd>
          </div>
        </dl>
      </header>
      <Tabs
        class='tabs'
        @options={{this.tabOptions}}
        @value={{this.tab}}
        @onValueChange={{this.setTab}}
        aria-label='Fulfilment sections'
      />

      {{#if this.isInteractive}}
        <section class='panel' aria-label='Fulfilment section'>
          {{#if (eq this.tab 'board')}}
            <BoardPanel @desk={{this}} />
          {{/if}}
          {{#if (eq this.tab 'inventory')}}
            <InventoryPanel @desk={{this}} />
          {{/if}}
          {{#if (eq this.tab 'ship')}}
            <ShipDeskPanel @desk={{this}} />
          {{/if}}
          {{#if (eq this.tab 'transit')}}
            <TransitPanel @desk={{this}} />
          {{/if}}
          {{#if (eq this.tab 'returns')}}
            <ReturnsPanel @desk={{this}} />
          {{/if}}
        </section>
      {{else}}
        <section class='panel static'>
          <p class='shell-note'>
            Fulfilment board, inventory, ship desk, tracking and returns load
            when this app is opened in the workspace.
          </p>
          <ul class='legend'>
            {{#each this.statusLegend as |s|}}
              <li><StatusChip @label={{s.label}} @hue={{s.hue}} /></li>
            {{/each}}
          </ul>
        </section>
      {{/if}}
    </div>

    <style scoped>
      .app {
        --_rule: color-mix(in oklch, var(--foreground) 12%, transparent);
        --_perf: color-mix(in oklch, var(--foreground) 22%, transparent);
        --_sunk: color-mix(in oklch, var(--foreground) 3%, transparent);

        display: flex;
        flex-direction: column;
        height: 100%;
        min-height: 0;
        overflow: hidden;
        background: var(--background);
        color: var(--foreground);
        font-family: var(--font-sans);
      }
      .masthead {
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp);
        align-items: flex-end;
        justify-content: space-between;
        padding: var(--boxel-sp-lg) var(--boxel-sp-lg) var(--boxel-sp);
        border-bottom: 2px solid var(--_perf);
      }
      .brand {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-sm);
        min-width: 0;
      }
      .brand-mark {
        display: flex;
        align-items: stretch;
        gap: 0.125rem;
        height: 2.125rem;
      }
      .brand-mark span {
        display: block;
        background: color-mix(in oklch, var(--foreground) 75%, transparent);
      }
      .brand-mark span:nth-child(odd) {
        width: 0.1875rem;
      }
      .brand-mark span:nth-child(even) {
        width: 0.3125rem;
        opacity: 0.5;
      }
      .brand-name {
        margin: 0;
        font-size: var(--boxel-font-size-lg);
        line-height: 1.05;
      }
      .brand-sub {
        margin: 0.125rem 0 0;
        font-size: var(--boxel-font-size-xs);
        letter-spacing: 0.06em;
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .counters {
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp-lg);
        margin: 0;
      }
      .counters div {
        display: flex;
        flex-direction: column;
        gap: 0.125rem;
      }
      .counters dt {
        display: flex;
        align-items: center;
        gap: 0.25rem;
        font-size: var(--boxel-font-size-2xs);
        letter-spacing: 0.12em;
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .counters dd {
        margin: 0;
        font-family: var(--font-mono);
        font-variant-numeric: tabular-nums;
        font-size: var(--boxel-font-size-xl);
        font-weight: 800;
        line-height: 1;
      }
      .counters .alarm dd {
        color: var(--destructive-ink);
      }

      .tabs {
        display: flex;
        gap: 0.125rem;
        padding: 0 var(--boxel-sp-lg);
        border-bottom: 1px solid var(--border);
        overflow-x: auto;
      }

      .panel:focus-visible {
        outline: 2px solid var(--ring);
        outline-offset: -2px;
      }
      .panel {
        container-type: inline-size;
        container-name: ful-panel;
        flex: 1;
        min-height: 0;
        overflow-y: auto;
        padding: var(--boxel-sp-lg);
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp);
      }
      @keyframes sk-pulse {
        50% {
          opacity: 0.45;
        }
      }
      .static {
        gap: var(--boxel-sp);
      }
      .shell-note {
        margin: 0;
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground);
        max-width: 60ch;
      }
      .legend {
        display: flex;
        flex-wrap: wrap;
        gap: 0.375rem;
        margin: 0;
        padding: 0;
        list-style: none;
      }

      @media (width <= 40rem) {
        .masthead,
        .panel {
          padding: var(--boxel-sp);
        }
        .counters {
          gap: var(--boxel-sp);
        }
      }
    </style>
  </template>
}
