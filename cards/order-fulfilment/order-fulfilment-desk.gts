import type { OrderFulfilmentApp } from './order-fulfilment-app';
import { BoardPanel } from './board-panel';
import { InventoryPanel } from './inventory-panel';
import { ShipDeskPanel } from './ship-desk-panel';
import { TransitPanel } from './transit-panel';
import { ReturnsPanel } from './returns-panel';
import { CardDef, Component, realmURL } from '@cardstack/base/card-api';
import { identifyCard, type getCards, type CodeRef, type Filter, type Query } from '@cardstack/runtime-common';
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
import { TABS, chipOptions, BOARD_COLUMNS, TRANSIT_PAGE, VIEW_OPTION, byType, eq } from './order-fulfilment-helpers';

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
  // The transit tab had no filter row at all, which is why a delivered parcel
  // was unreachable. It defaults to `transit` — the working set — but every
  // other state is now one click away instead of nowhere.
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
    // The `eq` node carries its own `on` anchor. Without it the node inherits
    // the ambient default, which is `baseCardRef` (index-query-engine.ts:746) —
    // so the engine looks for `stockState` on CardDef, does not find it, and the
    // whole request fails with HTTP 500 and
    // `Your filter refers to a nonexistent field "stockState" on type CardDef`.
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

  // An unresolved query and an empty realm both yield zero instances, so
  // without this the first paint of every tab asserted "No orders in the
  // pipeline" — an empty state stating something the app did not yet know.
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

  // An empty board with orders in hand is a SEARCH result, not an empty
  // pipeline — the old single message asserted the latter for both, so a search
  // that matched nothing read as "you have no orders at all".
  get boardEmptyMessage() {
    // Loading is not empty. Until this branch existed the first paint of the
    // board asserted the pipeline was clear.
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

  // ONE rule decides both whether a card is on the board and which column it
  // lands in. They used to be two: membership tested `status` against the
  // column list, while `columnKeyFor` fell back to 'pending' when status was
  // missing. Deleting a card empties the store's copy for a moment, and in that
  // moment the two disagreed — so a deleted Processing card reappeared under
  // Pending until the page was reloaded.
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

  // "In transit" now means what the words say: on the road. It used to be
  // `status && status !== 'delivered'`, which counted a label printed this
  // morning and a package sitting in exception as in transit — so the KPI
  // disagreed with the word above it, and the tab listed parcels that had not
  // moved yet alongside ones that had stopped moving.
  get inTransit() {
    return this.shipments.filter(
      (s) => s.status === 'in_transit' || s.status === 'out_for_delivery',
    );
  }

  // The read side of Mark delivered. Nothing in this app listed a delivered
  // shipment: the transit tab filtered them out, the ship desk queue only holds
  // pre-dispatch parcels, and the board draws orders. Marking a package
  // delivered therefore removed it from the app entirely — a write with no
  // corresponding read. Most recent first: "what landed today" is the question
  // being asked, not "what landed first".
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

  // The KPI counts what the In transit tab draws in red, which is not the same
  // as `exceptions`: a shipment three days overdue is flagged there but carries
  // no exception status, so a KPI reading `exceptions` alone said "1" over a
  // tab showing three problems.
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

  // There is no client-side mirror of the collection queries any more, and that
  // is the point: all four views are handed the same Query object, so the row
  // set cannot differ between them. Client-side filtering is still the right
  // tool for the board and for the counters below — those compute over resolved
  // fields, which a query cannot do.

  get closedReturns() {
    return this.returns.length - this.openReturns.length;
  }

  get warehouseSummary() {
    return this.warehouses.map((w) => {
      let rows = this.stock.filter((s) => s.warehouseCode === w.code);
      let value = rows.reduce(
        (sum, r) =>
          sum + (r.quantityOnHand ?? 0) * (r.product?.cost?.amount ?? 0),
        0,
      );
      return {
        warehouse: w,
        skuCount: rows.length,
        value,
        utilization: w.utilizationPercent,
        isVirtual: w.isVirtual,
      };
    });
  }

  // ── In transit ───────────────────────────────────────────────────────────

  // `getCards` publishes `isLoading`; nothing in this app read it, so every tab
  // rendered its empty state during the first fetch — the app asserting "nothing
  // in transit" about data it had not yet received.
  get shipmentsLoading() {
    return Boolean(this.shipmentQuery?.isLoading) && !this.shipments.length;
  }

  get ordersLoading() {
    return Boolean(this.orderQuery?.isLoading) && !this.orders.length;
  }

  // Redundant when the list below is already exactly this set.
  get showAttentionBanner() {
    return this.needsAttention.length > 0 && this.transitStatus !== 'attention';
  }

  // `all` is index 0, as it is on every other badge row in this card. Built last
  // it ended up last, which put the escape hatch hard against the right edge
  // where it read as the narrowest bucket rather than the widest. Position is not
  // selection: the default SELECTED badge is still `transit`, the working set.
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
    // A new filter is a new list; carrying the old page depth over would show
    // twelve of one set and then twelve more of another.
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

  // The manifest claimed this map as a reuse and nothing ever mounted it, while
  // all three warehouse instances carried real coordinates no template read.
  // One marker per warehouse that has a point; the popup carries what the tile
  // beside it carries, so the two cannot tell different stories.
  //
  // `@cached` is load-bearing, not an optimisation. MapRender's modifier decides
  // whether to rebuild its layers with `coordinates !== lastCoordinates` — an
  // IDENTITY check. An uncached getter hands it a new array on every re-render,
  // so any stock change in the realm would re-fit the whole map and yank the view
  // out from under whoever was reading it.
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

  // ── Table columns, declared rather than derived ───────────────────────────
  //
  // The schema-driven table needed three flags (`showClean`,
  // `showComputedFields`, `showPrimitivesOnly`) to guess which of the card's
  // fields belonged in a row. Declaring them answers that question instead: a
  // stock row is its identity, its location and the four quantities, and nothing
  // else. `align: 'right'` on the numerics is what makes a column of figures
  // readable — the component gives those cells tabular-nums.

  get inventoryRows() {
    return ((this.inventoryRowsQuery?.instances ?? []) as InventoryStock[]).filter(
      Boolean,
    );
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
    return Boolean(this.returnsRowsQuery?.isLoading) && !this.returnsRows.length;
  }

  inventoryColumns: TableColumn[] = [
    { key: 'sku', label: 'SKU', value: (r: any) => r.sku },
    { key: 'product', label: 'Product', value: (r: any) => r.productName },
    { key: 'warehouse', label: 'Warehouse', value: (r: any) => r.warehouseCode },
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

  // The queue the ship desk works from: a parcel with a label and no dispatch.
  // The `?? this.shipments.slice(0, 3)` fallback this used to end with invented
  // a queue out of three arbitrary shipments whenever the real one was empty —
  // so the desk offered to dispatch packages that had already landed. An empty
  // queue is a fact, and the empty state says it.
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

  // The missing link in the pipeline. The board can move an order to `packing`
  // and then nothing could carry it further: no surface in this app created a
  // Shipment, so the ship desk's own empty state ("Packed orders appear here
  // once a shipment exists for them") described a state the app could not reach.
  // An empty state that names a precondition has to also offer the action that
  // satisfies it, or it is a dead end wearing an explanation.
  get ordersAwaitingShipment() {
    let has = this.orderIdsWithShipment;
    return this.orders.filter(
      (o) => o.status === 'packing' && o.id && !has.has(o.id),
    );
  }

  // Creates the parcel for a packed order and stops there, deliberately: status
  // `label_created` is what puts it in the ship desk queue, and the rate is
  // chosen and stamped by DispatchShipmentCommand afterwards. Copying the line
  // items is a SNAPSHOT of what went in the box — a later edit to the order must
  // not rewrite what was packed.
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
            // The order already knows where it was allocated; carrying the link
            // over means the ship desk can price a parcel without asking again.
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
    let paid = shipment.customerPaid?.amount ?? 0;

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
              margin: Math.round((paid - cost) * 100) / 100,
              currency: service.baseRate?.currency?.code ?? 'GBP',
            };
          }),
      );

    return options.sort((a, b) => a.cost - b.cost);
  }

  get cheapestOption() {
    return this.rateOptions[0];
  }

  get fastestOption() {
    return [...this.rateOptions].sort((a, b) => a.days - b.days)[0];
  }

  @action selectShipment(id: string | undefined) {
    this.selectedShipmentId = id;
  }

  // ── Rendering helpers ────────────────────────────────────────────────────

  // Switching tabs no longer wipes the search: each collection owns its own
  // search state, so returning to a tab finds it as you left it.
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
            <dd>{{this.todayCount}}</dd>
          </div>
          <div>
            <dt>Express</dt>
            <dd>{{this.expressCount}}</dd>
          </div>
          <div>
            <dt>In transit</dt>
            <dd>{{this.inTransit.length}}</dd>
          </div>
          {{! The alarm state was a colour change and nothing else, which is
              invisible to anyone who cannot see the hue. The glyph carries the
              same meaning in form. }}
          <div class='{{if this.needsAttention.length "alarm"}}'>
            <dt>{{#if this.needsAttention.length}}<TriangleAlert
                  class='dt-alarm'
                  role='presentation'
                />{{/if}}Needs attention</dt>
            <dd>{{this.needsAttention.length}}</dd>
          </div>
          <div class='{{if this.outOfStock.length "alarm"}}'>
            <dt>{{#if this.outOfStock.length}}<TriangleAlert
                  class='dt-alarm'
                  role='presentation'
                />{{/if}}Out of stock</dt>
            <dd>{{this.outOfStock.length}}</dd>
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
        <section
          class='panel'
          aria-label='Fulfilment section'
        >
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
        /* Adapter block: the semantic set forwarded once into this app's
           vocabulary. Every value is a token or a mix of one. */
        --_rule: color-mix(in oklch, var(--foreground) 12%, transparent);
        --_perf: color-mix(in oklch, var(--foreground) 22%, transparent);
        /* State colour through the adapter block, not a literal hex. The semantic
           token mixed TOWARD --foreground is what keeps it legible on a dark
           ground as well as a light one: --foreground flips, so the mix flips. */
        --_danger: color-mix(
          in oklch,
          var(--destructive) 58%,
          var(--foreground)
        );
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
        gap: 2px;
        height: 34px;
      }
      .brand-mark span {
        display: block;
        background: color-mix(in oklch, var(--foreground) 75%, transparent);
      }
      .brand-mark span:nth-child(odd) {
        width: 3px;
      }
      .brand-mark span:nth-child(even) {
        width: 5px;
        opacity: 0.5;
      }
      .brand-name {
        margin: 0;
        font-size: 1.6rem;
        line-height: 1.05;
        font-family: var(--font-heading, inherit);
      }
      .brand-sub {
        margin: 2px 0 0;
        font-size: 0.75rem;
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
        gap: 2px;
      }
      .counters dt {
        display: flex;
        align-items: center;
        gap: 4px;
        font-size: 0.62rem;
        letter-spacing: 0.12em;
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .counters dd {
        margin: 0;
        font-family: var(--font-mono);
        font-variant-numeric: tabular-nums;
        font-size: 1.7rem;
        font-weight: 800;
        line-height: 1;
      }
      .dt-alarm {
        width: 11px;
        height: 11px;
        flex: none;
      }
      .counters .alarm dd {
        color: color-mix(
          in oklch,
          var(--destructive) 58%,
          var(--foreground)
        );
      }

      .tabs {
        display: flex;
        gap: 2px;
        padding: 0 var(--boxel-sp-lg);
        border-bottom: 1px solid var(--border);
        overflow-x: auto;
      }

      .panel:focus-visible {
        outline: 2px solid var(--ring);
        outline-offset: -2px;
      }
      .panel {
        /* The panel is the query container for the layouts below: the ship
           desk splits in two when there is room for it, regardless of how wide
           the browser is, because this card can sit in a narrow stack. */
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
        font-size: 0.9rem;
        color: var(--muted-foreground);
        max-width: 60ch;
      }
      .legend {
        display: flex;
        flex-wrap: wrap;
        gap: 6px;
        margin: 0;
        padding: 0;
        list-style: none;
      }

      @media (width <= 640px) {
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
