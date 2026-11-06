import { CardDef } from '@cardstack/base/card-api';
import { Component } from '@cardstack/base/card-api';
import {
  identifyCard,
  realmURL,
  type getCards,
} from '@cardstack/runtime-common';
import type Owner from '@ember/owner';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { htmlSafe } from '@ember/template';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { Button } from '@cardstack/pretui/components/button';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { SegmentedControl } from '@cardstack/pretui/components/segmented-control';
import { LayoutControl } from '@cardstack/pretui/components/layout-control';
import { SearchInput } from '@cardstack/pretui/components/search-input';
import { Stat } from '@cardstack/pretui/components/stat';
import { StatusChip } from '@cardstack/pretui/components/status-chip';
import { Table } from '@cardstack/pretui/components/table';
import { VisuallyHidden } from '@cardstack/pretui/components/visually-hidden';
import {
  Sidebar,
  SidebarGroup,
  SidebarItem,
} from '@cardstack/pretui/components/sidebar';
import PlusIcon from '@cardstack/boxel-icons/plus';
import LayoutDashboardIcon from '@cardstack/boxel-icons/layout-dashboard';
import BuildingIcon from '@cardstack/boxel-icons/building-2';
import FileTextIcon from '@cardstack/boxel-icons/file-text';
import SendIcon from '@cardstack/boxel-icons/send';
import ClipboardCheckIcon from '@cardstack/boxel-icons/clipboard-check';
import PackageIcon from '@cardstack/boxel-icons/package';
import ReceiptIcon from '@cardstack/boxel-icons/receipt';
import { debounce } from 'lodash';
import type { TableColumn } from '@cardstack/catalog/components/table';

import { PurchaseRequisition } from '../procurement/purchase-requisition';
import { Rfq } from '../procurement/rfq';
import { PurchaseOrder } from '../procurement/purchase-order';
import { GoodsReceipt } from '../procurement/goods-receipt';
import { Invoice } from '../commerce/invoice';
import { ProcurementBudget } from '../procurement/procurement-budget';
import { VendorProfile } from '../procurement/vendor-profile';
import { formatMoney } from '../commerce/line-item-totals';

import type { RfqToPaymentApp } from './rfq-to-payment-app';
import {
  TAB_OPTIONS,
  VIEW_OPTIONS,
  isApInvoice,
  isInvoiceSettled,
  isPoReceived,
  STATIONS,
  poValueBuckets,
  type PoValueBucket,
  type Station,
  type P2PRecords,
  awaitingVetting,
  inApFlight,
  openRequisitions,
  comparingRfqs,
  pendingApprovalPos,
  awaitingReceiptPos,
  stationCount,
  badgesFor,
  PO_COLUMNS,
  RFQ_COLUMNS,
  REQUISITION_COLUMNS,
  INVOICE_COLUMNS,
  RECEIPT_COLUMNS,
} from './rfq-to-payment-data';

const NAV_ICONS: Record<string, any> = {
  dashboard: LayoutDashboardIcon,
  vendors: BuildingIcon,
  requisitions: FileTextIcon,
  rfqs: SendIcon,
  pos: ClipboardCheckIcon,
  receipts: PackageIcon,
  invoices: ReceiptIcon,
};

const STATION_TONE: Record<string, 'info' | 'warning' | 'success'> = {
  onboarding: 'info',
  rfqs: 'info',
  approvals: 'warning',
  match: 'success',
};

const VENDOR_LANES = [
  { key: 'intake', label: 'Intake' },
  { key: 'under-review', label: 'Under Review' },
  { key: 'approved', label: 'Approved' },
  { key: 'onboarded', label: 'Onboarded' },
  { key: 'rejected', label: 'Rejected' },
];

// Lane rows shown before "+N more": the rest open from the tab's table views.
const LANE_ROWS = 3;

const STATUS_KEYS = ['status', 'posted', 'match'];
const PERSON_KEYS = ['requester', 'by'];

const toneOf = (
  value: unknown,
): 'success' | 'danger' | 'warning' | 'info' | 'neutral' => {
  let s = String(value ?? '').toLowerCase();
  if (
    /(received|closed|paid|approved|posted|matched|awarded|converted|onboarded)/.test(
      s,
    )
  ) {
    return 'success';
  }
  if (/(exception|rejected|lapsed|short|over|cancel)/.test(s)) {
    return 'danger';
  }
  if (/(pending|sent|partial|draft|review|submitted)/.test(s)) {
    return 'warning';
  }
  if (/(comparing|open|in-flight)/.test(s)) {
    return 'info';
  }
  return 'neutral';
};

// whole-dollar figures, as in the mock
const money = (n: number | undefined | null) =>
  formatMoney(n ?? 0, 'USD').replace(/\.00$/, '');

const pct = (part: number, whole: number) =>
  whole > 0 ? Math.max(0, Math.min(100, Math.round((part / whole) * 100))) : 0;

const SEARCH_FORMS = [
  { name: 'full', minWidth: 14 },
  { name: 'menu', minWidth: 0 },
];
const FILTER_FORMS = [
  { name: 'full', minWidth: 22 },
  { name: 'menu', minWidth: 0 },
];
const VIEW_FORMS = [
  { name: 'full', minWidth: 11 },
  { name: 'menu', minWidth: 0 },
];
const PRIMARY_FORMS = [{ name: 'full', minWidth: 9 }];

const PAGE_SUB: Record<string, string> = {
  dashboard:
    'Requisition, quote, approve, receive and pay. Select a stage to open exactly the records it counts.',
};

const NOUN: Record<string, string> = {
  requisitions: 'requisitions',
  rfqs: 'RFQs',
  pos: 'purchase orders',
  receipts: 'receipts',
  invoices: 'vendor invoices',
};

const EMPTY_MESSAGES: Record<string, string> = {
  requisitions: 'The P2P chain starts with a requisition.',
  rfqs: 'Convert a requisition to start comparing vendors.',
  pos: 'No purchase orders in this view.',
  receipts: 'Record what arrives against an approved PO.',
  invoices: 'Record one against a received PO to run the match.',
};

// The isolated console, hoisted out of the card class so its fields can be
// @tracked.
export class RfqToPaymentConsole extends Component<typeof RfqToPaymentApp> {
  @tracked activeTab: string = 'dashboard';
  @tracked stationFilter: string | undefined;

  private requisitionList: ReturnType<getCards> | undefined;
  private rfqList: ReturnType<getCards> | undefined;
  private poList: ReturnType<getCards> | undefined;
  private receiptList: ReturnType<getCards> | undefined;
  private budgetList: ReturnType<getCards> | undefined;
  private profileList: ReturnType<getCards> | undefined;
  private invoiceList: ReturnType<getCards> | undefined;

  constructor(owner: Owner, args: any) {
    super(owner, args);
    let live = { isLive: true as const };
    let realms = () => this.realms;
    let queryFor = (type: any) => () => {
      let ref = identifyCard(type);
      return ref ? { filter: { type: ref } } : undefined;
    };
    let ctx = this.args.context;
    this.requisitionList = ctx?.getCards(
      this,
      queryFor(PurchaseRequisition),
      realms,
      live,
    );
    this.rfqList = ctx?.getCards(this, queryFor(Rfq), realms, live);
    this.poList = ctx?.getCards(this, queryFor(PurchaseOrder), realms, live);
    this.receiptList = ctx?.getCards(
      this,
      queryFor(GoodsReceipt),
      realms,
      live,
    );
    this.budgetList = ctx?.getCards(
      this,
      queryFor(ProcurementBudget),
      realms,
      live,
    );
    this.profileList = ctx?.getCards(
      this,
      queryFor(VendorProfile),
      realms,
      live,
    );
    this.invoiceList = ctx?.getCards(this, queryFor(Invoice), realms, live);
  }

  private get realms(): string[] | undefined {
    let url = this.args.model?.[realmURL];
    return url ? [url.href] : undefined;
  }

  // CRUD functions reach the card only in interactive contexts, so their
  // absence marks prerender, where the query-heavy console must not mount.
  get isInteractive() {
    return Boolean(this.args.viewCard);
  }

  get isLoading() {
    return [
      this.requisitionList,
      this.rfqList,
      this.poList,
      this.receiptList,
      this.budgetList,
      this.profileList,
      this.invoiceList,
    ].some((list) => list?.isLoading);
  }

  // A count shown while its query is still loading would read as zero.
  stationLabel = (key: string): string =>
    this.isLoading ? '–' : String(this.stationCount(key));

  emptyTitle = (noun: string): string =>
    this.isLoading ? `Loading ${noun}…` : `No ${noun} here`;

  get requisitions(): PurchaseRequisition[] {
    return (
      (this.requisitionList?.instances ?? []) as PurchaseRequisition[]
    ).filter(Boolean);
  }
  get rfqs(): Rfq[] {
    return ((this.rfqList?.instances ?? []) as Rfq[]).filter(Boolean);
  }
  get pos(): PurchaseOrder[] {
    return ((this.poList?.instances ?? []) as PurchaseOrder[]).filter(Boolean);
  }
  get receipts(): GoodsReceipt[] {
    return ((this.receiptList?.instances ?? []) as GoodsReceipt[]).filter(
      Boolean,
    );
  }
  get budgets(): ProcurementBudget[] {
    return ((this.budgetList?.instances ?? []) as ProcurementBudget[]).filter(
      Boolean,
    );
  }
  get profiles(): VendorProfile[] {
    return ((this.profileList?.instances ?? []) as VendorProfile[]).filter(
      Boolean,
    );
  }
  // Vendor bills only; customer invoices in the same realm stay out.
  get apInvoices(): Invoice[] {
    return ((this.invoiceList?.instances ?? []) as Invoice[])
      .filter(Boolean)
      .filter(isApInvoice);
  }
  private get records(): P2PRecords {
    return {
      requisitions: this.requisitions,
      rfqs: this.rfqs,
      pos: this.pos,
      receipts: this.receipts,
      profiles: this.profiles,
      apInvoices: this.apInvoices,
    };
  }
  get awaitingVetting() {
    return awaitingVetting(this.profiles);
  }
  // The Onboarding station counts profiles awaiting vetting, so its click
  // narrows the board to exactly those.
  get vendorBoardItems(): VendorProfile[] {
    return this.stationFilter === 'onboarding'
      ? this.awaitingVetting
      : this.profiles;
  }
  get inApFlight() {
    return inApFlight(this.apInvoices);
  }
  get openRequisitions() {
    return openRequisitions(this.requisitions);
  }
  get comparingRfqs() {
    return comparingRfqs(this.rfqs);
  }
  get pendingApprovalPos() {
    return pendingApprovalPos(this.pos);
  }
  get awaitingReceiptPos() {
    return awaitingReceiptPos(this.pos);
  }

  stationCount = (key: string): number => stationCount(key, this.records);

  poColumns = PO_COLUMNS;
  rfqColumns = RFQ_COLUMNS;
  requisitionColumns = REQUISITION_COLUMNS;
  invoiceColumns = INVOICE_COLUMNS;
  receiptColumns = RECEIPT_COLUMNS;

  get badges() {
    return badgesFor(this.activeTab, this.records);
  }

  // ---- collection shell state ---------------------------------------
  // One view state shared by every tab: grid and list render the same
  // filtered records through each card's own fitted template, and table is
  // the shared Table over those records with explicit columns.
  @tracked view: string = 'table';
  setView = (id: string) => {
    this.view = id;
  };

  fittedComponent = (card: CardDef) =>
    (card.constructor as typeof CardDef).getComponent(card);

  @tracked searchText = '';
  private debouncedSetSearch = debounce((value: string) => {
    this.searchText = value;
  }, 250);
  setSearch = (value: string) => {
    this.debouncedSetSearch(value);
  };

  willDestroy() {
    super.willDestroy();
    this.debouncedSetSearch.cancel();
  }

  private matches = (q: string, ...hay: (string | undefined | null)[]) =>
    !q || hay.some((h) => h?.toLowerCase().includes(q));

  get activeBadge(): string {
    return this.stationFilter ?? 'all';
  }

  // ---- filtered tab lists (client-side filters deliberately mirror the
  // badge counts above: toggling a badge never disagrees with its count) --
  get visibleRequisitions() {
    let q = this.searchText.trim().toLowerCase();
    let rows = this.requisitions;
    if (this.stationFilter === 'requisitions') {
      rows = this.openRequisitions;
    } else if (this.stationFilter === 'converted') {
      rows = rows.filter((r) => r.status === 'converted-to-rfq');
    }
    return rows.filter((r) =>
      this.matches(q, r.title, r.requester, r.department),
    );
  }
  get visibleRfqs() {
    let q = this.searchText.trim().toLowerCase();
    let rows = this.rfqs;
    if (this.stationFilter === 'rfqs') {
      rows = this.comparingRfqs;
    } else if (this.stationFilter === 'awarded') {
      rows = rows.filter((r) => r.status === 'awarded');
    }
    return rows.filter((r) => this.matches(q, r.cardTitle));
  }
  get visiblePos() {
    let q = this.searchText.trim().toLowerCase();
    let rows = this.pos;
    if (this.stationFilter === 'approvals') {
      rows = this.pendingApprovalPos;
    } else if (this.stationFilter === 'receiving') {
      rows = this.awaitingReceiptPos;
    } else if (this.stationFilter === 'received') {
      rows = rows.filter((p) => isPoReceived(p));
    }
    return rows.filter((p) => this.matches(q, p.poNumber, p.status));
  }
  get visibleInvoices() {
    let q = this.searchText.trim().toLowerCase();
    let rows = this.apInvoices;
    if (this.stationFilter === 'match') {
      rows = this.inApFlight;
    } else if (this.stationFilter === 'exception') {
      rows = rows.filter((i) => i.status === 'exception');
    } else if (this.stationFilter === 'approved') {
      rows = rows.filter((i) => isInvoiceSettled(i));
    }
    return rows.filter((i) =>
      this.matches(q, i.invoiceNumber, i.status, i.cardTitle),
    );
  }
  get visibleReceipts() {
    let q = this.searchText.trim().toLowerCase();
    let rows = this.receipts;
    if (this.stationFilter === 'posted') {
      rows = rows.filter((g) => g.posted);
    } else if (this.stationFilter === 'draft-receipts') {
      rows = rows.filter((g) => !g.posted);
    }
    return rows.filter((g) => this.matches(q, g.title, g.receivedBy));
  }

  setTab = (key: string) => {
    this.debouncedSetSearch.cancel();
    this.activeTab = key;
    this.stationFilter = undefined;
    this.searchText = '';
  };

  setBadge = (id: string) => {
    this.stationFilter = id === 'all' ? undefined : id;
  };

  goToStation = (station: Station) => {
    this.debouncedSetSearch.cancel();
    this.activeTab = station.tab;
    this.stationFilter = station.key;
    this.searchText = '';
  };

  // ---- add actions: + Add <Noun>, inline, live query shows it instantly -
  private addCard = (type: any, attributes: Record<string, unknown>) => {
    let ref = identifyCard(type);
    let realm = this.realms?.[0];
    if (!ref || !realm) {
      return;
    }
    this.args.createCard?.(ref, undefined, {
      realmURL: new URL(realm),
      doc: { data: { attributes, meta: { adoptsFrom: ref } } },
    });
  };
  addRequisition = () => this.addCard(PurchaseRequisition, { status: 'draft' });
  addRfq = () => this.addCard(Rfq, { status: 'draft' });
  addPo = () => this.addCard(PurchaseOrder, { status: 'draft' });
  addReceipt = () => this.addCard(GoodsReceipt, { posted: false });
  addInvoice = () => this.addCard(Invoice, { status: 'received' });

  get addAction(): { label: string; run: () => void } | undefined {
    switch (this.activeTab) {
      case 'invoices':
        return { label: 'Add Vendor Invoice', run: this.addInvoice };
      case 'requisitions':
        return { label: 'Add Requisition', run: this.addRequisition };
      case 'rfqs':
        return { label: 'Add RFQ', run: this.addRfq };
      case 'pos':
        return { label: 'Add Purchase Order', run: this.addPo };
      case 'receipts':
        return { label: 'Add Receipt', run: this.addReceipt };
      default:
        return undefined;
    }
  }

  openCard = (card: CardDef) => {
    this.args.viewCard?.(card, 'isolated');
  };

  addVendorProfile = () => this.addCard(VendorProfile, { status: 'intake' });

  // ---- compact shell ---------------------------------------------------
  SEARCH_FORMS = SEARCH_FORMS;
  FILTER_FORMS = FILTER_FORMS;
  VIEW_FORMS = VIEW_FORMS;
  PRIMARY_FORMS = PRIMARY_FORMS;
  VIEW_OPTIONS = VIEW_OPTIONS;

  get navCounts(): Record<string, number> {
    return {
      vendors: this.profiles.length,
      requisitions: this.requisitions.length,
      rfqs: this.rfqs.length,
      pos: this.pos.length,
      receipts: this.receipts.length,
      invoices: this.apInvoices.length,
    };
  }

  get navOverview() {
    return this.navItems.slice(0, 1);
  }
  get navChain() {
    return this.navItems.slice(1);
  }
  private get navItems() {
    return TAB_OPTIONS.map((t) => ({
      ...t,
      icon: NAV_ICONS[t.value],
      active: t.value === this.activeTab,
      badge:
        this.isLoading || this.navCounts[t.value] === undefined
          ? undefined
          : String(this.navCounts[t.value]),
    }));
  }

  get pageTitle() {
    return TAB_OPTIONS.find((t) => t.value === this.activeTab)?.label ?? '';
  }

  get pageSub(): string {
    if (PAGE_SUB[this.activeTab]) {
      return PAGE_SUB[this.activeTab];
    }
    if (this.activeTab === 'vendors') {
      return `${this.profiles.length} vendor profiles in the vetting pipeline`;
    }
    let rows = this.tableRows;
    return `${rows.length} of ${this.navCounts[this.activeTab] ?? rows.length} shown`;
  }

  get noun() {
    return NOUN[this.activeTab] ?? 'records';
  }
  get emptyMessage() {
    return EMPTY_MESSAGES[this.activeTab];
  }

  get tableRows(): CardDef[] {
    switch (this.activeTab) {
      case 'requisitions':
        return this.visibleRequisitions;
      case 'rfqs':
        return this.visibleRfqs;
      case 'pos':
        return this.visiblePos;
      case 'receipts':
        return this.visibleReceipts;
      case 'invoices':
        return this.visibleInvoices;
      default:
        return [];
    }
  }

  get tableColumns(): TableColumn[] {
    switch (this.activeTab) {
      case 'requisitions':
        return this.requisitionColumns;
      case 'rfqs':
        return this.rfqColumns;
      case 'pos':
        return this.poColumns;
      case 'receipts':
        return this.receiptColumns;
      case 'invoices':
        return this.invoiceColumns;
      default:
        return [];
    }
  }

  // the first column is the record itself (its atom); the rest are values
  get restColumns() {
    return this.tableColumns.slice(1);
  }

  cellOf = (card: CardDef, col: TableColumn) => {
    let v = col.value?.(card);
    return v === undefined || v === null || v === '' ? '—' : v;
  };
  markOf = (card: CardDef) =>
    (card.constructor as typeof CardDef).displayName ?? '';
  isStatus = (col: TableColumn) => STATUS_KEYS.includes(col.key);
  isPerson = (col: TableColumn) => PERSON_KEYS.includes(col.key);
  isEnd = (col: TableColumn) => col.align === 'right';
  isNarrowOnly = (col: TableColumn) => Boolean(col.showAbove);
  toneOf = toneOf;

  get filterOptions() {
    return this.badges.map((b) => ({
      value: b.id,
      label: `${b.label} ${b.count}`,
    }));
  }
  get filterMenuItems() {
    return this.badges.map((b) => ({
      label: `${b.label} (${b.count})`,
      value: b.id,
      group: 'status',
      checked: b.id === this.activeBadge,
      onSelect: () => this.setBadge(b.id),
    }));
  }
  get viewMenuItems() {
    return VIEW_OPTIONS.map((v) => ({
      label: v.label,
      value: v.value,
      group: 'view',
      checked: v.value === this.view,
      onSelect: () => this.setView(v.value),
    }));
  }

  // ---- dashboard -------------------------------------------------------
  stationTone = (station: Station) => STATION_TONE[station.key] ?? 'neutral';

  get budgetRows() {
    return this.budgets.map((b) => {
      let total = b.budgetAmount ?? 0;
      let committed = b.committed ?? 0;
      let actual = b.actual ?? 0;
      let a = pct(actual, total);
      let c = Math.max(0, pct(committed, total) - a);
      return {
        card: b,
        budget: money(total),
        committed: money(committed),
        actual: money(actual),
        remaining: money(total - committed),
        label: `${a}% actual, ${c}% more committed`,
        actualStyle: htmlSafe(`inline-size: ${a}%`),
        committedStyle: htmlSafe(`inline-size: ${c}%`),
      };
    });
  }

  get poValue(): { buckets: PoValueBucket[]; mixedCurrency: boolean } {
    return poValueBuckets(this.pos);
  }

  get recentReceipts() {
    return this.receipts.slice(0, 4);
  }

  get complianceStats() {
    let ok = this.profiles.filter((p) => p.complianceOk).length;
    let total = this.profiles.length;
    let okPct = pct(ok, total);
    return {
      ok,
      lapsed: total - ok,
      total,
      okStyle: htmlSafe(`inline-size: ${okPct}%`),
      badStyle: htmlSafe(`inline-size: ${total ? 100 - okPct : 0}%`),
    };
  }

  // ---- vendors ---------------------------------------------------------
  get vendorLanes() {
    let items = this.vendorBoardItems;
    return VENDOR_LANES.map((lane) => {
      let all = items.filter((p) => (p.status ?? 'intake') === lane.key);
      return {
        ...lane,
        count: all.length,
        rows: all.slice(0, LANE_ROWS),
        more: Math.max(0, all.length - LANE_ROWS),
      };
    });
  }

  <template>
    <div class='app'>
      {{#if this.isInteractive}}
        <Sidebar
          class='shell'
          @label='RFQ to Payment'
          @collapsible='rail'
          @railBreakpoint={{1100}}
          @mobileBreakpoint={{720}}
          @bordered={{true}}
          @scroll='content'
          @resizable={{true}}
        >
          <:header as |bar|>
            <div class='brand'>
              <span class='brand-mark' aria-hidden='true'>R2</span>
              {{#unless bar.collapsed}}
                <span class='brand-name'>RFQ to Payment<small>Procure-to-Pay
                    console</small></span>
              {{/unless}}
            </div>
          </:header>
          <:nav as |bar|>
            <SidebarGroup @label='Overview' @hideLabel={{bar.collapsed}}>
              {{#each this.navOverview key='value' as |item|}}
                <SidebarItem
                  @label={{item.label}}
                  @active={{item.active}}
                  @collapsed={{bar.collapsed}}
                  @onClick={{fn this.setTab item.value}}
                >
                  <:icon><item.icon aria-hidden='true' /></:icon>
                </SidebarItem>
              {{/each}}
            </SidebarGroup>
            <SidebarGroup @label='Procure-to-Pay' @hideLabel={{bar.collapsed}}>
              {{#each this.navChain key='value' as |item|}}
                <SidebarItem
                  @label={{item.label}}
                  @badge={{unless bar.collapsed item.badge}}
                  @active={{item.active}}
                  @collapsed={{bar.collapsed}}
                  @onClick={{fn this.setTab item.value}}
                >
                  <:icon><item.icon aria-hidden='true' /></:icon>
                </SidebarItem>
              {{/each}}
            </SidebarGroup>
          </:nav>
          <:default>
            <div
              class='split {{if (eq this.activeTab "dashboard") "has-side"}}'
            >
              <main class='main'>
                <header class='head'>
                  <div>
                    <p class='cap'>Procure-to-Pay console</p>
                    <h1>{{this.pageTitle}}</h1>
                  </div>
                  <p class='meta'>{{this.pageSub}}</p>
                </header>

                {{#if (eq this.activeTab 'dashboard')}}
                  <LayoutControl @label='Dashboard actions' as |lc|>
                    <span class='grow'></span>
                    <lc.Slot
                      @id='add'
                      @priority={{0}}
                      @pinned={{true}}
                      @forms={{this.PRIMARY_FORMS}}
                      @label='Add Requisition'
                    >
                      <Button
                        @icon={{PlusIcon}}
                        {{on 'click' this.addRequisition}}
                      >Add Requisition</Button>
                    </lc.Slot>
                  </LayoutControl>

                  <section class='strip' aria-label='Procure-to-Pay pipeline'>
                    {{#each STATIONS as |station|}}
                      <button
                        type='button'
                        class='stat'
                        {{on 'click' (fn this.goToStation station)}}
                      >
                        <Stat
                          @label={{station.label}}
                          @value={{this.stationLabel station.key}}
                          @tone={{this.stationTone station}}
                          @hint={{station.filterLabel}}
                          @roll={{false}}
                        />
                      </button>
                    {{/each}}
                  </section>

                  <section class='block' aria-labelledby='budgets-title'>
                    <div class='sh'>
                      <h2 id='budgets-title'>Budgets: committed vs actual</h2>
                      <span class='legend'>
                        <span><i class='dot pr'></i>Actual</span>
                        <span><i class='dot cm'></i>Committed</span>
                      </span>
                    </div>
                    {{#if this.budgetRows.length}}
                      <div class='tw'>
                        <Table @label='Procurement budgets' @framed={{false}}>
                          <:head>
                            <tr>
                              <th scope='col'>Budget</th>
                              <th scope='col' class='end'>Budget</th>
                              <th scope='col' class='end lo'>Committed</th>
                              <th scope='col' class='end lo'>Actual</th>
                              <th scope='col' class='end'>Remaining</th>
                              <th scope='col' class='util xlo'>Utilisation</th>
                              <th scope='col' class='xlo'><VisuallyHidden
                                >Open</VisuallyHidden></th>
                            </tr>
                          </:head>
                          <:body>
                            {{#each this.budgetRows as |row|}}
                              <tr>
                                <th scope='row' class='rh'>
                                  {{#let
                                    (this.fittedComponent row.card)
                                    as |A|
                                  }}<A
                                      @format='atom'
                                      @displayContainer={{false}}
                                    />{{/let}}
                                </th>
                                <td class='end mono'>{{row.budget}}</td>
                                <td class='end mono lo'>{{row.committed}}</td>
                                <td class='end mono lo'>{{row.actual}}</td>
                                <td class='end mono'>{{row.remaining}}</td>
                                <td class='xlo'>
                                  <span
                                    class='track'
                                    role='img'
                                    aria-label={{row.label}}
                                  ><span
                                      class='fill'
                                      style={{row.actualStyle}}
                                    ></span><span
                                      class='fill cm'
                                      style={{row.committedStyle}}
                                    ></span></span>
                                </td>
                                <td class='end xlo'>
                                  <Button
                                    @appearance='plain'
                                    {{on 'click' (fn this.openCard row.card)}}
                                  >Open</Button>
                                </td>
                              </tr>
                            {{/each}}
                          </:body>
                        </Table>
                      </div>
                    {{else}}
                      <EmptyState
                        @size='s'
                        @title={{this.emptyTitle 'budgets'}}
                        @message='Commitment accounting starts when the first Procurement Budget exists.'
                      />
                    {{/if}}
                  </section>

                  <section class='block' aria-labelledby='value-title'>
                    <div class='sh'>
                      <h2 id='value-title'>Where the money is: PO value by stage</h2>
                    </div>
                    <ul class='ul'>
                      {{#each this.poValue.buckets as |b|}}
                        <li class='row bl'>
                          <span>{{b.label}}
                            <span class='meta'>({{b.count}})</span></span>
                          <span class='mono end'>{{b.totalLabel}}</span>
                          <span class='track'><span
                              class='fill hue-{{b.hue}}'
                              style={{b.barStyle}}
                            ></span></span>
                        </li>
                      {{/each}}
                    </ul>
                    {{#if this.poValue.mixedCurrency}}
                      <p class='note'>Purchase orders span several currencies,
                        so the bars compare order counts.</p>
                    {{/if}}
                  </section>
                {{/if}}

                {{#if (eq this.activeTab 'vendors')}}
                  <LayoutControl @label='Vendor actions' as |lc|>
                    <span class='grow'></span>
                    <lc.Slot
                      @id='add'
                      @priority={{0}}
                      @pinned={{true}}
                      @forms={{this.PRIMARY_FORMS}}
                      @label='Add Vendor Profile'
                    >
                      <Button
                        @icon={{PlusIcon}}
                        {{on 'click' this.addVendorProfile}}
                      >Add Vendor Profile</Button>
                    </lc.Slot>
                  </LayoutControl>
                  <section class='block' aria-labelledby='vetting-title'>
                    <div class='sh'>
                      <h2 id='vetting-title'>Vetting pipeline</h2>
                      <span class='meta'>Open a profile to move it. Onboarding
                        happens from the profile.</span>
                    </div>
                    <div
                      class='lanes'
                      role='group'
                      aria-label='Vendor vetting pipeline'
                    >
                      {{#each this.vendorLanes as |lane|}}
                        <section class='lane' aria-label={{lane.label}}>
                          <header class='lh'>
                            <h3 class='cap'>{{lane.label}}</h3>
                            <span class='mono'>{{lane.count}}</span>
                          </header>
                          <ul class='ul'>
                            {{#each lane.rows as |p|}}
                              <li class='vrow'>
                                <button
                                  type='button'
                                  class='open'
                                  {{on 'click' (fn this.openCard p)}}
                                >
                                  {{#let (this.fittedComponent p) as |A|}}<A
                                      @format='atom'
                                      @displayContainer={{false}}
                                    />{{/let}}
                                </button>
                                <span class='vs'>
                                  <StatusChip
                                    @value={{if
                                      p.complianceOk
                                      'compliant'
                                      'lapsed / thin file'
                                    }}
                                    @tone={{if
                                      p.complianceOk
                                      'success'
                                      'danger'
                                    }}
                                    @appearance='plain'
                                  />
                                  <span
                                    class='meta'
                                  >{{p.serviceCategory}}</span>
                                </span>
                              </li>
                            {{else}}
                              <li class='vrow meta'>—</li>
                            {{/each}}
                          </ul>
                          {{#if lane.more}}
                            <p class='more meta'>+{{lane.more}} more</p>
                          {{/if}}
                        </section>
                      {{/each}}
                    </div>
                  </section>
                {{/if}}

                {{#if this.tableColumns.length}}
                  <LayoutControl @label='{{this.pageTitle}} toolbar' as |lc|>
                    <lc.Slot
                      @id='search'
                      @priority={{2}}
                      @forms={{this.SEARCH_FORMS}}
                      @label='Search'
                    >
                      <label class='search'>
                        <VisuallyHidden>Search {{this.noun}}</VisuallyHidden>
                        <SearchInput
                          @placeholder='Search {{this.noun}}…'
                          @value={{this.searchText}}
                          @onInput={{this.setSearch}}
                        />
                      </label>
                    </lc.Slot>
                    <lc.Slot
                      @id='status'
                      @priority={{1}}
                      @forms={{this.FILTER_FORMS}}
                      @label='Status'
                      @menuItems={{this.filterMenuItems}}
                    >
                      <SegmentedControl
                        @label='Filter by status'
                        @options={{this.filterOptions}}
                        @value={{this.activeBadge}}
                        @onValueChange={{this.setBadge}}
                      />
                    </lc.Slot>
                    <span class='grow'></span>
                    <lc.Slot
                      @id='view'
                      @priority={{3}}
                      @forms={{this.VIEW_FORMS}}
                      @label='View'
                      @menuItems={{this.viewMenuItems}}
                    >
                      <SegmentedControl
                        @label='View as'
                        @options={{this.VIEW_OPTIONS}}
                        @value={{this.view}}
                        @onValueChange={{this.setView}}
                      />
                    </lc.Slot>
                    {{#if this.addAction}}
                      <lc.Slot
                        @id='add'
                        @priority={{0}}
                        @pinned={{true}}
                        @forms={{this.PRIMARY_FORMS}}
                        @label={{this.addAction.label}}
                      >
                        <Button
                          @icon={{PlusIcon}}
                          {{on 'click' this.addAction.run}}
                        >{{this.addAction.label}}</Button>
                      </lc.Slot>
                    {{/if}}
                  </LayoutControl>

                  <section class='block' aria-labelledby='table-title'>
                    <div class='sh'>
                      <h2 id='table-title'>All {{this.noun}}</h2>
                      <span class='meta'>{{this.tableRows.length}}
                        {{this.noun}}</span>
                    </div>
                    {{#if this.tableRows.length}}
                      {{#if (eq this.view 'table')}}
                        <div class='tw'>
                          <Table @label={{this.pageTitle}} @framed={{false}}>
                            <:head>
                              <tr>
                                {{#each this.tableColumns as |c|}}
                                  <th
                                    scope='col'
                                    class='{{if (this.isEnd c) "end"}}
                                      {{if (this.isNarrowOnly c) "lo"}}'
                                  >{{c.label}}</th>
                                {{/each}}
                                <th scope='col' class='xlo'><VisuallyHidden
                                  >Open</VisuallyHidden></th>
                              </tr>
                            </:head>
                            <:body>
                              {{#each this.tableRows key='id' as |card|}}
                                <tr>
                                  <th scope='row' class='rh'>
                                    {{! mock: mark + id only; status has its own column }}
                                    <span class='rh-id'><Avatar
                                        @name={{this.markOf card}}
                                        @shape='square'
                                        @size={{16}}
                                      /><span
                                        class='rh-nm'
                                      >{{card.cardTitle}}</span></span>
                                  </th>
                                  {{#each this.restColumns as |c|}}
                                    <td
                                      class='{{if (this.isEnd c) "end mono"}}
                                        {{if (this.isNarrowOnly c) "lo"}}'
                                    >
                                      {{#if (this.isStatus c)}}
                                        {{#let (this.cellOf card c) as |s|}}
                                          <StatusChip
                                            @value={{s}}
                                            @tone={{this.toneOf s}}
                                            @appearance='plain'
                                          />
                                        {{/let}}
                                      {{else if (this.isPerson c)}}
                                        {{#let (this.cellOf card c) as |p|}}
                                          <span class='rh-id'><Avatar
                                              @name={{p}}
                                              @size={{16}}
                                            /><span
                                              class='pn'
                                            >{{p}}</span></span>
                                        {{/let}}
                                      {{else}}
                                        {{this.cellOf card c}}
                                      {{/if}}
                                    </td>
                                  {{/each}}
                                  <td class='end xlo'>
                                    <Button
                                      @appearance='plain'
                                      {{on 'click' (fn this.openCard card)}}
                                    >Open</Button>
                                  </td>
                                </tr>
                              {{/each}}
                            </:body>
                          </Table>
                        </div>
                      {{else}}
                        <div
                          class='cards
                            {{if
                              (eq this.view "grid")
                              "grid-view"
                              "list-view"
                            }}'
                        >
                          {{#each this.tableRows key='id' as |card|}}
                            <button
                              type='button'
                              class='cell'
                              {{on 'click' (fn this.openCard card)}}
                            >
                              {{#let (this.fittedComponent card) as |C|}}
                                <C
                                  @format='fitted'
                                  @displayContainer={{false}}
                                />
                              {{/let}}
                            </button>
                          {{/each}}
                        </div>
                      {{/if}}
                    {{else}}
                      <div class='es'>
                        <EmptyState
                          @size='s'
                          @title={{this.emptyTitle this.noun}}
                          @message={{this.emptyMessage}}
                        />
                      </div>
                    {{/if}}
                  </section>
                {{/if}}
              </main>

              {{#if (eq this.activeTab 'dashboard')}}
                <aside class='docked' aria-label='Health at a glance'>
                  <section class='sec' aria-labelledby='compliance-title'>
                    <div class='sh'>
                      <h2 id='compliance-title'>Vendor compliance</h2>
                    </div>
                    <div class='pad'>
                      <p class='big'><span
                          class='num'
                        >{{this.complianceStats.ok}}</span>
                        <span class='meta'>{{this.complianceStats.ok}}
                          of
                          {{this.complianceStats.total}}
                          compliant</span></p>
                      <span
                        class='track'
                        role='img'
                        aria-label='{{this.complianceStats.ok}} current, {{this.complianceStats.lapsed}} lapsed or thin file'
                      ><span
                          class='fill hue-success'
                          style={{this.complianceStats.okStyle}}
                        ></span><span
                          class='fill hue-danger'
                          style={{this.complianceStats.badStyle}}
                        ></span></span>
                      <span class='legend'>
                        <StatusChip
                          @value='{{this.complianceStats.ok}} current'
                          @tone='success'
                          @appearance='plain'
                        />
                        <StatusChip
                          @value='{{this.complianceStats.lapsed}} lapsed / thin file'
                          @tone='danger'
                          @appearance='plain'
                        />
                      </span>
                    </div>
                  </section>
                  <section class='sec' aria-labelledby='receipts-title'>
                    <div class='sh'>
                      <h2 id='receipts-title'>Recent receipts</h2>
                      <Button
                        @appearance='plain'
                        {{on 'click' (fn this.setTab 'receipts')}}
                      >View all</Button>
                    </div>
                    <ul class='ul'>
                      {{#each this.recentReceipts as |gr|}}
                        <li class='row g2'>
                          <button
                            type='button'
                            class='open two'
                            {{on 'click' (fn this.openCard gr)}}
                          >
                            <span class='strong'>{{gr.title}}</span>
                            <span class='meta'>{{gr.matchResult}}</span>
                          </button>
                          <StatusChip
                            @value={{if gr.posted 'posted' 'draft'}}
                            @tone={{if gr.posted 'success' 'warning'}}
                            @appearance='plain'
                          />
                        </li>
                      {{else}}
                        <li class='row meta'>{{this.emptyTitle 'receipts'}}</li>
                      {{/each}}
                    </ul>
                  </section>
                </aside>
              {{/if}}
            </div>
          </:default>
        </Sidebar>
      {{else}}
        <main class='main'>
          <header class='head'>
            <div>
              <p class='cap'>Procure-to-Pay console</p>
              <h1>RFQ to Payment</h1>
            </div>
          </header>
          <p class='meta'>Requisitions, RFQs, purchase orders, receipts and
            budget health. Open the app to work the pipeline.</p>
        </main>
      {{/if}}
    </div>
    <style scoped>
      .app {
        container-type: inline-size;
        display: flex;
        block-size: 100%;
        min-block-size: 0;
        overflow: hidden;
        background: var(--background);
        color: var(--foreground);
        font-family: var(--font-sans);
        font-size: 0.75rem;
        line-height: 1.35;
        --control-height: 1.625rem;
        /* shortcut: Pret UI parts ignore --control-height until CS-14733 merges, then drop the two lines below. */
        --pretui-button-h: 1.625rem;
        --pretui-seg-h: 1.625rem;
      }
      .shell {
        block-size: 100%;
        min-block-size: 0;
        flex: 1;
      }
      .split {
        display: grid;
        grid-template-columns: minmax(0, 1fr);
        min-block-size: 100%;
      }
      .split.has-side {
        grid-template-columns: minmax(0, 1fr) 18rem;
      }
      @container (max-width: 75rem) {
        .split.has-side {
          grid-template-columns: minmax(0, 1fr);
        }
        .docked {
          margin: 0 var(--boxel-sp-lg) var(--boxel-sp-lg);
          border: 1px solid var(--border);
          border-radius: var(--radius);
        }
      }
      .main {
        box-sizing: border-box;
        min-inline-size: 0;
        padding: var(--boxel-sp-lg) var(--boxel-sp-lg) var(--boxel-sp-xl);
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
      }
      .head {
        display: flex;
        flex-wrap: wrap;
        align-items: flex-end;
        justify-content: space-between;
        gap: var(--boxel-sp-4xs) var(--boxel-sp-sm);
      }
      .cap,
      th,
      .lh h3 {
        margin: 0;
        font-family: var(--font-mono);
        font-weight: 600;
        font-size: 0.5625rem;
        line-height: 1.3;
        letter-spacing: 0.13em;
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .head .cap {
        margin-block-end: var(--boxel-sp-xxxs);
      }
      h1 {
        margin: 0;
        font-family: var(--boxel-heading-font-family, var(--font-sans));
        font-weight: 400;
        font-size: 2.5rem;
        line-height: 1;
        text-transform: uppercase;
      }
      h2 {
        margin: 0;
        font-size: 0.75rem;
        font-weight: 700;
      }
      p {
        margin: 0;
      }
      .meta {
        font-size: 0.6875rem;
        color: var(--muted-foreground);
      }
      .mono {
        font-family: var(--font-mono);
        font-size: 0.6875rem;
        font-variant-numeric: tabular-nums;
      }
      .grow {
        flex: 1;
      }
      .brand {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xxs);
      }
      .brand-mark {
        display: inline-grid;
        place-items: center;
        inline-size: 1.5rem;
        block-size: 1.5rem;
        border-radius: var(--radius);
        background: var(--primary);
        color: var(--primary-foreground);
        font-family: var(--font-mono);
        font-size: 0.625rem;
        font-weight: 700;
      }
      .brand-name {
        display: grid;
        font-size: 0.75rem;
        font-weight: 700;
      }
      .brand-name small {
        font-family: var(--font-mono);
        font-size: 0.5625rem;
        font-weight: 600;
        letter-spacing: 0.13em;
        text-transform: uppercase;
        color: var(--muted-foreground);
      }

      /* blocks: radius only on the outer card, flat inside */
      .block,
      .strip,
      .docked {
        background: var(--card);
      }
      .block,
      .strip {
        border: 1px solid var(--border);
        border-radius: var(--radius);
        overflow: hidden;
      }
      .sh {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xxs);
        min-block-size: 1.75rem;
        padding: var(--boxel-sp-4xs) var(--boxel-sp-xs);
        border-block-end: 1px solid var(--border);
      }
      .sh .meta,
      .sh .legend {
        margin-inline-start: auto;
      }
      .legend {
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp-xs);
        font-size: 0.6875rem;
        color: var(--muted-foreground);
      }
      .legend > span {
        display: inline-flex;
        align-items: center;
        gap: var(--boxel-sp-xxxs);
      }
      .dot {
        inline-size: 0.4375rem;
        block-size: 0.4375rem;
        border-radius: 50%;
        background: var(--foreground);
      }
      .dot.cm {
        background: var(--muted-foreground);
        opacity: 0.6;
      }

      /* stat strip: joined tiles, every tile draws its own dividers */
      .strip {
        display: grid;
        grid-template-columns: repeat(6, minmax(0, 1fr));
      }
      @container (max-width: 60rem) {
        .strip {
          grid-template-columns: repeat(3, minmax(0, 1fr));
        }
      }
      @container (max-width: 30rem) {
        .strip {
          grid-template-columns: repeat(2, minmax(0, 1fr));
        }
      }
      .stat {
        all: unset;
        box-sizing: border-box;
        min-inline-size: 0;
        padding: var(--boxel-sp-xxxs) var(--boxel-sp-xs);
        cursor: pointer;
        box-shadow:
          1px 0 0 var(--border),
          0 1px 0 var(--border);
      }
      .stat:hover {
        background: var(--muted);
      }
      .stat:focus-visible {
        outline: 2px solid var(--ring);
        outline-offset: -2px;
      }

      /* tables: 28px rows, mono caps head, hairlines */
      .tw {
        overflow-x: auto;
        padding-inline: var(--boxel-sp-xs);
        --pretui-table-head-height: 1.5rem;
        /* the mock has a plain head and no zebra rows */
        --inset: var(--card);
        --stripe: transparent;
      }
      th,
      td {
        padding-block: 0;
        text-align: start;
        white-space: nowrap;
        vertical-align: middle;
      }
      td {
        block-size: 1.75rem;
      }
      .rh-id {
        display: inline-flex;
        align-items: center;
        gap: var(--boxel-sp-xxxs);
        max-inline-size: 100%;
        min-inline-size: 0;
      }
      .rh-nm {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        font-weight: 600;
      }
      th.rh {
        block-size: 1.75rem;
      }
      th.rh {
        font-family: var(--font-sans);
        font-size: 0.75rem;
        font-weight: 600;
        letter-spacing: 0;
        text-transform: none;
        color: var(--foreground);
      }
      .end {
        text-align: end;
      }
      th.util {
        inline-size: 20%;
      }
      @container (max-width: 40rem) {
        .lo {
          display: none;
        }
      }
      @container (max-width: 30rem) {
        .xlo {
          display: none;
        }
      }

      .track {
        display: flex;
        block-size: 0.25rem;
        min-inline-size: 4rem;
        border-radius: 1rem;
        overflow: hidden;
        background: var(--muted);
      }
      .fill {
        display: block;
        background: var(--foreground);
      }
      .fill.cm {
        background: var(--muted-foreground);
        opacity: 0.6;
      }
      .fill.hue-warning {
        background: var(--warning, var(--foreground));
      }
      .fill.hue-success {
        background: var(--success, var(--foreground));
      }
      .fill.hue-danger {
        background: var(--destructive);
      }

      .ul {
        list-style: none;
        margin: 0;
        padding: 0 var(--boxel-sp-xs);
      }
      .row {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        min-block-size: 1.75rem;
      }
      .row + .row {
        border-block-start: 1px solid var(--border);
      }
      .row.bl {
        display: grid;
        grid-template-columns: minmax(8rem, 1fr) 6rem minmax(4rem, 1.4fr);
      }
      .row.g2 {
        justify-content: space-between;
        padding-block: var(--boxel-sp-4xs);
      }
      .note {
        padding: var(--boxel-sp-xxxs) var(--boxel-sp-xs);
        font-size: 0.6875rem;
        color: var(--muted-foreground);
      }
      .open {
        all: unset;
        cursor: pointer;
        display: inline-flex;
        min-inline-size: 0;
        max-inline-size: 100%;
      }
      .open:focus-visible {
        outline: 2px solid var(--ring);
      }
      .two {
        display: grid;
      }
      .strong {
        font-weight: 600;
      }

      /* docked side panel */
      .docked {
        border-inline-start: 1px solid var(--border);
        display: flex;
        flex-direction: column;
        overflow: hidden;
      }
      .sec + .sec {
        border-block-start: 1px solid var(--border);
      }
      .pad {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xxs);
        padding: var(--boxel-sp-xxs) var(--boxel-sp-xs) var(--boxel-sp-xs);
      }
      .big {
        display: flex;
        align-items: baseline;
        gap: var(--boxel-sp-xxs);
      }
      .num {
        font-size: 1.375rem;
        font-weight: 700;
        font-variant-numeric: tabular-nums;
        line-height: 1;
      }

      /* vendor lanes */
      .lanes {
        display: grid;
        grid-template-columns: repeat(5, minmax(11rem, 1fr));
        overflow-x: auto;
      }
      .lane {
        min-inline-size: 0;
      }
      .lane + .lane {
        border-inline-start: 1px solid var(--border);
      }
      .lh {
        display: flex;
        justify-content: space-between;
        align-items: center;
        min-block-size: 1.75rem;
        padding-inline: var(--boxel-sp-xs);
        border-block-end: 1px solid var(--border);
      }
      .vrow {
        display: grid;
        gap: var(--boxel-sp-5xs);
        padding-block: var(--boxel-sp-xxxs);
      }
      .vrow + .vrow {
        border-block-start: 1px solid var(--border);
      }
      .vs {
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp-4xs) var(--boxel-sp-xxs);
        align-items: center;
      }
      .more {
        padding: var(--boxel-sp-4xs) var(--boxel-sp-xs) var(--boxel-sp-xxxs);
      }

      /* grid / list views of fitted cards */
      .cards {
        display: grid;
        gap: var(--boxel-sp-xxs);
        padding: var(--boxel-sp-xs);
      }
      .grid-view {
        grid-template-columns: repeat(auto-fill, minmax(15.625rem, 1fr));
        grid-auto-rows: 10.625rem;
      }
      .list-view {
        grid-auto-rows: 4.0625rem;
      }
      .cell {
        all: unset;
        cursor: pointer;
        box-sizing: border-box;
        min-inline-size: 0;
        overflow: hidden;
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
      }
      .cell:focus-visible {
        outline: 2px solid var(--ring);
      }
      .es {
        padding: var(--boxel-sp-xs);
      }
      .search {
        display: block;
        min-inline-size: 14rem;
      }
    </style>
  </template>
}
