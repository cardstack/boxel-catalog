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
import { eq } from '@cardstack/boxel-ui/helpers';
import { Alert } from '@cardstack/pretui/components/alert';
import { Button } from '@cardstack/pretui/components/button';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { SegmentedControl } from '@cardstack/pretui/components/segmented-control';
import { Tabs } from '@cardstack/pretui/components/tabs';
import Plus from '@cardstack/boxel-icons/plus';
import { debounce } from 'lodash';

import { Table } from '../../components/table';

import PatchCardInstanceCommand from '@cardstack/boxel-host/commands/patch-card-instance';

import { PurchaseRequisition } from '../procurement/purchase-requisition';
import { Rfq } from '../procurement/rfq';
import { PurchaseOrder } from '../procurement/purchase-order';
import { GoodsReceipt } from '../procurement/goods-receipt';
import { Invoice } from '../commerce/invoice';
import { ProcurementBudget } from '../procurement/procurement-budget';
import {
  VendorProfile,
  VendorProfileStatusField,
} from '../procurement/vendor-profile';
import { StatusBoard } from '../../components/status-board';
import { CollectionToolbar } from '../../components/collection-toolbar';

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
  @tracked view: string = 'list';
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

  // ---- Vendors tab: the onboarding StatusBoard, consumed unchanged ------
  @tracked vendorFlash: string | undefined;

  vendorStatusField = VendorProfileStatusField;

  vendorStatusOf = (item: any) => (item as VendorProfile).status ?? 'intake';

  vendorMove = async (item: CardDef, statusValue: string) => {
    let commandContext = this.args.context?.commandContext;
    if (!commandContext) {
      return false;
    }
    this.vendorFlash = undefined;
    try {
      await new PatchCardInstanceCommand(commandContext, {
        cardType: VendorProfile,
      }).execute({
        cardId: item.id,
        patch: { attributes: { status: statusValue } },
      });
    } catch (error: any) {
      this.vendorFlash = error?.message ?? String(error);
      return false;
    }
    return undefined;
  };

  vendorRejected = (_i: CardDef, _f: string | undefined, to: string) => {
    this.vendorFlash =
      to === 'onboarded'
        ? 'Onboarding creates the active Vendor record — open the profile and use "Onboard as Vendor" instead of dragging.'
        : 'That move is not allowed by the vetting pipeline.';
  };

  addVendorProfile = () => this.addCard(VendorProfile, { status: 'intake' });

  // ---- dashboard analytics (CSS glyph charts, never a chart lib) --------
  get complianceStats() {
    let ok = this.profiles.filter((p) => p.complianceOk).length;
    let lapsed = this.profiles.length - ok;
    let total = Math.max(1, this.profiles.length);
    return {
      ok,
      lapsed,
      total: this.profiles.length,
      okDeg: Math.round((ok / total) * 360),
    };
  }

  get donutStyle() {
    let deg = this.complianceStats.okDeg;
    return `background: conic-gradient(var(--success) 0deg ${deg}deg, var(--destructive) ${deg}deg 360deg);`;
  }

  // PO value by lifecycle bucket: where the money is right now.
  get poValue(): { buckets: PoValueBucket[]; mixedCurrency: boolean } {
    return poValueBuckets(this.pos);
  }

  budgetComponent = (budget: ProcurementBudget) =>
    (budget.constructor as typeof CardDef).getComponent(budget);

  <template>
    <article class='app'>
      <header class='command-band'>
        <div class='head'>
          <div>
            <p class='kicker'>Procurement · Procure-to-Pay console</p>
            <h1>RFQ to Payment</h1>
          </div>
          {{#if this.isInteractive}}
            <Tabs
              class='tabs'
              @options={{TAB_OPTIONS}}
              @value={{this.activeTab}}
              @onValueChange={{this.setTab}}
            />
          {{/if}}
        </div>

        {{#if this.isInteractive}}
          <div class='rail' aria-label='Procure-to-Pay pipeline'>
            {{#each STATIONS as |station index|}}
              {{#if index}}<span class='rail-link' aria-hidden='true'><span
                    class='rail-dot'
                  ></span></span>{{/if}}
              <Button
                @appearance='accent'
                class='station'
                {{on 'click' (fn this.goToStation station)}}
              >
                <span class='station-body'><span
                    class='station-count'
                  >{{this.stationLabel station.key}}</span>
                  <span class='station-label'>{{station.label}}</span>
                  <span
                    class='station-sub'
                  >{{station.filterLabel}}</span></span>
              </Button>
            {{/each}}
          </div>
        {{/if}}
      </header>

      {{#unless this.isInteractive}}
        <p class='shell-note'>Procure-to-Pay console: requisitions, RFQs,
          purchase orders, receipts, and budget health. Open the app to work the
          pipeline.</p>
      {{/unless}}

      {{#if this.isInteractive}}
        {{#if (eq this.activeTab 'vendors')}}
          {{#if this.vendorFlash}}
            <Alert @tone='warning'>{{this.vendorFlash}}</Alert>
          {{/if}}
          <StatusBoard
            @items={{this.vendorBoardItems}}
            @statusField={{this.vendorStatusField}}
            @statusOf={{this.vendorStatusOf}}
            @onMove={{this.vendorMove}}
            @onRejected={{this.vendorRejected}}
            @onOpen={{this.openCard}}
            @onAddCard={{this.addVendorProfile}}
            @boardLabel='Vendor vetting pipeline'
            class='vendor-board'
          />
        {{/if}}
        {{#unless (eq this.activeTab 'dashboard')}}
          {{#unless (eq this.activeTab 'vendors')}}
            <CollectionToolbar
              @search={{this.searchText}}
              @onSearch={{this.setSearch}}
              @placeholder='Search this list'
              @badges={{this.badges}}
              @activeBadge={{this.activeBadge}}
              @onBadge={{this.setBadge}}
            >
              <:right>
                <SegmentedControl
                  @label='View as'
                  @options={{VIEW_OPTIONS}}
                  @value={{this.view}}
                  @onValueChange={{this.setView}}
                />
                {{#if this.addAction}}
                  <Button
                    @tone='primary'
                    @size='s'
                    {{on 'click' this.addAction.run}}
                  >
                    <Plus width='16' height='16' role='presentation' />
                    {{this.addAction.label}}
                  </Button>
                {{/if}}
              </:right>
            </CollectionToolbar>
          {{/unless}}
        {{/unless}}

        {{#if (eq this.activeTab 'dashboard')}}
          <div class='dash'>
            <section class='panel dash-main'>
              <h2>Budgets · committed vs actual</h2>
              <div class='list'>
                {{#each this.budgets as |budget|}}
                  <div class='budget-row'>
                    {{#let (this.budgetComponent budget) as |C|}}
                      <C @format='embedded' class='row-card' />
                    {{/let}}
                    <Button
                      @appearance='plain'
                      @size='s'
                      class='row-action'
                      {{on 'click' (fn this.openCard budget)}}
                    >Open</Button>
                  </div>
                {{else}}
                  <EmptyState
                    @size='s'
                    @title={{this.emptyTitle 'budgets'}}
                    @message='Commitment accounting starts when the first Procurement Budget exists.'
                  />
                {{/each}}
              </div>

              <h2 class='mt'>Where the money is · PO value by stage</h2>
              <div class='value-chart'>
                {{#each this.poValue.buckets as |b|}}
                  <div class='vc-row'>
                    <span class='vc-label'>{{b.label}}
                      <span class='vc-count'>({{b.count}})</span></span>
                    <div class='vc-track'>
                      <div
                        class='vc-bar hue-{{b.hue}}'
                        style={{b.barStyle}}
                      ></div>
                    </div>
                    <span class='vc-total'>{{b.totalLabel}}</span>
                  </div>
                {{/each}}
              </div>
              {{#if this.poValue.mixedCurrency}}
                <p class='vc-note'>Purchase orders span several currencies, so
                  the bars compare order counts.</p>
              {{/if}}
            </section>

            <aside class='dash-side'>
              <section class='panel'>
                <h2>Vendor compliance</h2>
                <div class='donut-wrap'>
                  <div class='donut' style={{this.donutStyle}}>
                    <div class='donut-hole'>
                      <span class='donut-num'>{{this.complianceStats.ok}}<span
                          class='donut-of'
                        >/{{this.complianceStats.total}}</span></span>
                      <span class='donut-label'>compliant</span>
                    </div>
                  </div>
                  <div class='donut-legend'>
                    <span><i class='swatch ok'></i>{{this.complianceStats.ok}}
                      current</span>
                    <span><i
                        class='swatch bad'
                      ></i>{{this.complianceStats.lapsed}}
                      lapsed / thin file</span>
                  </div>
                </div>
              </section>

              <section class='panel'>
                <h2>Recent receipts</h2>
                <div class='list'>
                  {{#each this.receipts as |gr|}}
                    <Button
                      @appearance='plain'
                      class='row-open'
                      {{on 'click' (fn this.openCard gr)}}
                    ><span class='row-title'>{{gr.title}}</span>
                      <span class='row-meta'>{{if gr.posted 'posted' 'draft'}}
                        ·
                        {{gr.matchResult}}</span></Button>
                  {{else}}
                    <EmptyState
                      @size='s'
                      @title={{this.emptyTitle 'receipts'}}
                    />
                  {{/each}}
                </div>
              </section>
            </aside>
          </div>
        {{/if}}

        {{#if (eq this.activeTab 'requisitions')}}
          {{#if (eq this.view 'table')}}
            <Table
              @items={{this.visibleRequisitions}}
              @columns={{this.requisitionColumns}}
              @onRowClick={{this.openCard}}
              @emptyMessage='Nothing here — the P2P chain starts with a requisition.'
              @caption='Purchase requisitions'
            />
          {{else}}
            <div
              class='cards
                {{if (eq this.view "grid") "grid-view" "strip-view"}}'
            >
              {{#each this.visibleRequisitions as |pr|}}
                <div class='cell'>
                  {{#let (this.fittedComponent pr) as |C|}}
                    <C
                      @format='fitted'
                      @displayContainer={{false}}
                      class='cell-card'
                    />
                  {{/let}}
                  <Button
                    @appearance='plain'
                    @size='s'
                    class='row-action'
                    {{on 'click' (fn this.openCard pr)}}
                  >Open</Button>
                </div>
              {{else}}
                <EmptyState
                  @size='s'
                  @title={{this.emptyTitle 'requisitions'}}
                  @message='The P2P chain starts with a requisition.'
                />
              {{/each}}
            </div>
          {{/if}}
        {{/if}}

        {{#if (eq this.activeTab 'rfqs')}}
          {{#if (eq this.view 'table')}}
            <Table
              @items={{this.visibleRfqs}}
              @columns={{this.rfqColumns}}
              @onRowClick={{this.openCard}}
              @emptyMessage='No RFQs in this view — convert a requisition to start comparing vendors.'
              @caption='Requests for quote'
            />
          {{else}}
            <div
              class='cards
                {{if (eq this.view "grid") "grid-view" "strip-view"}}'
            >
              {{#each this.visibleRfqs as |rfq|}}
                <div class='cell'>
                  {{#let (this.fittedComponent rfq) as |C|}}
                    <C
                      @format='fitted'
                      @displayContainer={{false}}
                      class='cell-card'
                    />
                  {{/let}}
                  <Button
                    @appearance='plain'
                    @size='s'
                    class='row-action'
                    {{on 'click' (fn this.openCard rfq)}}
                  >Open</Button>
                </div>
              {{else}}
                <EmptyState
                  @size='s'
                  @title={{this.emptyTitle 'RFQs'}}
                  @message='Convert a requisition to start comparing vendors.'
                />
              {{/each}}
            </div>
          {{/if}}
        {{/if}}

        {{#if (eq this.activeTab 'pos')}}
          {{#if (eq this.view 'table')}}
            <Table
              @items={{this.visiblePos}}
              @columns={{this.poColumns}}
              @onRowClick={{this.openCard}}
              @emptyMessage='No purchase orders in this view.'
              @caption='Purchase orders'
            />
          {{else}}
            <div
              class='cards
                {{if (eq this.view "grid") "grid-view" "strip-view"}}'
            >
              {{#each this.visiblePos as |po|}}
                <div class='cell'>
                  {{#let (this.fittedComponent po) as |C|}}
                    <C
                      @format='fitted'
                      @displayContainer={{false}}
                      class='cell-card'
                    />
                  {{/let}}
                  <Button
                    @appearance='plain'
                    @size='s'
                    class='row-action'
                    {{on 'click' (fn this.openCard po)}}
                  >Open</Button>
                </div>
              {{else}}
                <EmptyState
                  @size='s'
                  @title={{this.emptyTitle 'purchase orders'}}
                />
              {{/each}}
            </div>
          {{/if}}
        {{/if}}

        {{#if (eq this.activeTab 'invoices')}}
          {{#if (eq this.view 'table')}}
            <Table
              @items={{this.visibleInvoices}}
              @columns={{this.invoiceColumns}}
              @onRowClick={{this.openCard}}
              @emptyMessage='No vendor invoices yet — record one against a received PO to run the match.'
              @caption='Vendor invoices'
            />
          {{else}}
            <div
              class='cards
                {{if (eq this.view "grid") "grid-view" "strip-view"}}'
            >
              {{#each this.visibleInvoices as |inv|}}
                <div class='cell'>
                  {{#let (this.fittedComponent inv) as |C|}}
                    <C
                      @format='fitted'
                      @displayContainer={{false}}
                      class='cell-card'
                    />
                  {{/let}}
                  <Button
                    @appearance='plain'
                    @size='s'
                    class='row-action'
                    {{on 'click' (fn this.openCard inv)}}
                  >Open</Button>
                </div>
              {{else}}
                <EmptyState
                  @size='s'
                  @title={{this.emptyTitle 'vendor invoices'}}
                  @message='Record one against a received PO to run the match.'
                />
              {{/each}}
            </div>
          {{/if}}
        {{/if}}

        {{#if (eq this.activeTab 'receipts')}}
          {{#if (eq this.view 'table')}}
            <Table
              @items={{this.visibleReceipts}}
              @columns={{this.receiptColumns}}
              @onRowClick={{this.openCard}}
              @emptyMessage='No goods receipts yet — record what arrives against an approved PO.'
              @caption='Goods receipts'
            />
          {{else}}
            <div
              class='cards
                {{if (eq this.view "grid") "grid-view" "strip-view"}}'
            >
              {{#each this.visibleReceipts as |gr|}}
                <div class='cell'>
                  {{#let (this.fittedComponent gr) as |C|}}
                    <C
                      @format='fitted'
                      @displayContainer={{false}}
                      class='cell-card'
                    />
                  {{/let}}
                  <Button
                    @appearance='plain'
                    @size='s'
                    class='row-action'
                    {{on 'click' (fn this.openCard gr)}}
                  >Open</Button>
                </div>
              {{else}}
                <EmptyState
                  @size='s'
                  @title={{this.emptyTitle 'goods receipts'}}
                  @message='Record what arrives against an approved PO.'
                />
              {{/each}}
            </div>
          {{/if}}
        {{/if}}
      {{/if}}
    </article>
    <style scoped>
      .app {
        container-type: inline-size;
        padding: 0 var(--boxel-sp-lg) var(--boxel-sp-lg);
        background:
          radial-gradient(
            75rem 23.75rem at 20% -10%,
            color-mix(in oklch, var(--primary) 7%, transparent),
            transparent 65%
          ),
          var(--background);
        color: var(--foreground);
        font-family: var(--font-sans);
        min-height: 100%;
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp);
      }
      .command-band {
        background: linear-gradient(
          120deg,
          color-mix(in oklch, var(--primary) 96%, var(--foreground)),
          var(--primary) 55%,
          color-mix(in oklch, var(--primary) 82%, var(--foreground))
        );
        color: var(--primary-foreground);
        margin: 0 calc(-1 * var(--boxel-sp-lg));
        padding: var(--boxel-sp) var(--boxel-sp-lg) var(--boxel-sp);
        position: relative;
        overflow: hidden;
      }
      .command-band::after {
        content: '';
        position: absolute;
        inset: 0;
        background-image:
          linear-gradient(
            color-mix(in oklch, var(--primary-foreground) 7%, transparent) 1px,
            transparent 1px
          ),
          linear-gradient(
            90deg,
            color-mix(in oklch, var(--primary-foreground) 7%, transparent) 1px,
            transparent 1px
          );
        background-size: 1.75rem 1.75rem;
        mask-image: linear-gradient(to bottom, black, transparent 92%);
        pointer-events: none;
      }
      .head {
        display: flex;
        justify-content: space-between;
        align-items: flex-end;
        gap: var(--boxel-sp);
        flex-wrap: wrap;
        position: relative;
        z-index: 1;
      }
      .kicker {
        margin: 0;
        font-size: 0.6875rem;
        letter-spacing: 0.14em;
        text-transform: uppercase;
        color: color-mix(in oklch, var(--primary-foreground) 65%, transparent);
      }
      h1 {
        margin: var(--boxel-sp-5xs) 0 0;
        font-family: var(--font-sans);
        font-size: 1.75rem;
        letter-spacing: -0.015em;
      }
      .tabs {
        display: flex;
        gap: var(--boxel-sp-5xs);
        flex-wrap: wrap;
      }

      /* ── the P2P rail: the signature element ─────────────────────── */
      .rail {
        position: relative;
        z-index: 1;
        margin-top: var(--boxel-sp);
        display: flex;
        align-items: stretch;
        gap: 0;
      }

      .station {
        flex: 1;
        --pretui-button-h: auto;
        --pretui-button-px: var(--boxel-sp-sm);
        --pretui-button-fg: var(--primary-foreground);
        --pretui-button-bg: color-mix(
          in oklch,
          var(--primary-foreground) 7%,
          transparent
        );
      }
      .station-body {
        display: flex;
        flex-direction: column;
        align-items: flex-start;
        gap: var(--boxel-sp-5xs);
        padding-block: var(--boxel-sp-xs);
        text-align: left;
      }
      .station-count {
        font-size: 1.625rem;
        font-weight: 700;
        font-variant-numeric: tabular-nums;
        line-height: 1.1;
      }
      .station-label {
        font-size: 0.8125rem;
        font-weight: 600;
      }
      .station-sub {
        font-size: 0.6875rem;
        text-transform: uppercase;
        letter-spacing: 0.08em;
        color: color-mix(in oklch, var(--primary-foreground) 60%, transparent);
      }
      .rail-link {
        width: 2.125rem;
        align-self: center;
        height: 0.125rem;
        background: color-mix(
          in oklch,
          var(--primary-foreground) 30%,
          transparent
        );
        position: relative;
        flex: 0 0 auto;
      }
      .rail-dot {
        position: absolute;
        top: -0.125rem;
        left: 0;
        width: 0.375rem;
        height: 0.375rem;
        border-radius: 50%;
        background: var(--primary-foreground);
      }
      .panel {
        border: 1px solid var(--border);
        border-radius: var(--radius);
        padding: var(--boxel-sp);
        background: var(--card);
      }
      /* dashboard: asymmetric two-column — the money story left (wide),
         the health-at-a-glance rail right */
      .dash {
        display: grid;
        grid-template-columns: minmax(0, 2fr) minmax(16rem, 1fr);
        gap: var(--boxel-sp);
        align-items: start;
      }
      .dash-side {
        display: grid;
        gap: var(--boxel-sp);
      }
      h2.mt {
        margin-top: var(--boxel-sp);
      }
      .value-chart {
        display: grid;
        gap: var(--boxel-sp-xs);
      }
      .vc-row {
        display: grid;
        grid-template-columns: 12rem minmax(0, 1fr) auto;
        gap: var(--boxel-sp-sm);
        align-items: center;
      }
      .vc-label {
        font-size: 0.8125rem;
        color: var(--muted-foreground);
      }
      .vc-count {
        opacity: 0.7;
        font-variant-numeric: tabular-nums;
      }
      .vc-track {
        height: 0.875rem;
        border-radius: 0.4375rem;
        background: var(--muted);
        overflow: hidden;
      }
      .vc-bar {
        height: 100%;
        border-radius: 0.4375rem;
        min-width: 0.1875rem;
      }
      .vc-bar.hue-warning {
        background: var(--warning);
      }
      .vc-bar.hue-primary {
        background: repeating-linear-gradient(
          45deg,
          var(--primary),
          var(--primary) 0.25rem,
          color-mix(in oklch, var(--primary) 55%, transparent) 0.25rem,
          color-mix(in oklch, var(--primary) 55%, transparent) 0.5rem
        );
      }
      .vc-bar.hue-success {
        background: var(--success);
      }
      .vc-note {
        margin-top: var(--boxel-sp-xs);
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
      .vc-total {
        font-weight: 700;
        font-variant-numeric: tabular-nums;
        min-width: 6rem;
        text-align: right;
      }
      .donut-wrap {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp);
      }
      .donut {
        width: 6.75rem;
        height: 6.75rem;
        border-radius: 50%;
        flex: 0 0 auto;
        display: grid;
        place-items: center;
      }
      .donut-hole {
        width: 4.625rem;
        height: 4.625rem;
        border-radius: 50%;
        background: var(--card);
        display: grid;
        place-content: center;
        text-align: center;
      }
      .donut-num {
        font-size: 1.25rem;
        font-weight: 700;
        font-variant-numeric: tabular-nums;
        line-height: 1;
      }
      .donut-of {
        font-size: 0.8125rem;
        font-weight: 400;
        color: var(--muted-foreground);
      }
      .donut-label {
        font-size: 0.625rem;
        text-transform: uppercase;
        letter-spacing: 0.08em;
        color: var(--muted-foreground);
      }
      .donut-legend {
        display: grid;
        gap: var(--boxel-sp-5xs);
        font-size: 0.8125rem;
        font-variant-numeric: tabular-nums;
      }
      .swatch {
        display: inline-block;
        width: 0.625rem;
        height: 0.625rem;
        border-radius: 0.1875rem;
        margin-right: 0.375rem;
      }
      .swatch.ok {
        background: var(--success);
      }
      .swatch.bad {
        background: var(--destructive);
      }
      @container (width < 47.5rem) {
        .dash {
          grid-template-columns: 1fr;
        }
        .vc-row {
          grid-template-columns: 1fr;
          gap: var(--boxel-sp-5xs);
        }
        .vc-total {
          text-align: left;
        }
      }
      h2 {
        margin: 0 0 var(--boxel-sp-xs);
        font-size: 0.8125rem;
        letter-spacing: 0.08em;
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .list {
        display: grid;
        gap: var(--boxel-sp-xs);
      }
      /* grid & list are the same renderer — the card's own fitted — in two
         cell shapes; table is the shared Table over the same array. The
         fitted-card container itself comes from field-component's wrapper. */
      .cards {
        display: grid;
        gap: var(--boxel-sp-xs);
      }
      .cards.grid-view {
        grid-template-columns: repeat(auto-fill, minmax(15rem, 1fr));
      }
      .cards.grid-view .cell {
        height: 10.625rem;
      }
      .cards.strip-view {
        grid-template-columns: 1fr;
      }
      .cards.strip-view .cell {
        height: 4.0625rem;
      }

      .cell {
        position: relative;
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
        overflow: hidden;
        transition: border-color 140ms ease;
      }
      .cell:hover,
      .cell:focus-within {
        border-color: var(--primary);
      }
      .cell-card {
        width: 100%;
        height: 100%;
      }
      .row-action {
        position: absolute;
        inset-block-end: var(--boxel-sp-4xs);
        inset-inline-end: var(--boxel-sp-4xs);
      }

      .row-open {
        display: flex;
        justify-content: space-between;
        align-items: baseline;
        gap: var(--boxel-sp-sm);
        width: 100%;
      }

      .budget-row {
        position: relative;
      }
      .row-title {
        font-weight: 600;
        font-size: 0.9375rem;
      }
      .row-meta {
        font-size: 0.8125rem;
        color: var(--muted-foreground);
      }

      .shell-note {
        margin: 0;
        padding: var(--boxel-sp-lg);
        border: 1px dashed var(--border);
        border-radius: var(--radius);
        color: var(--muted-foreground);
        font-size: 0.875rem;
      }

      .vendor-board {
        flex: 1;
        min-height: 0;
      }
      @media (prefers-reduced-motion: no-preference) {
        .command-band {
          animation: p2p-band-in 420ms cubic-bezier(0.22, 1, 0.36, 1) both;
        }
        .station {
          animation: p2p-rise 360ms cubic-bezier(0.22, 1, 0.36, 1) both;
        }
        .rail .station:nth-of-type(1) {
          animation-delay: 120ms;
        }
        .rail .station:nth-of-type(2) {
          animation-delay: 190ms;
        }
        .rail .station:nth-of-type(3) {
          animation-delay: 260ms;
        }
        .rail .station:nth-of-type(4) {
          animation-delay: 330ms;
        }
        .rail-dot {
          animation: rail-flow 2.6s cubic-bezier(0.45, 0, 0.55, 1) infinite;
          animation-delay: 900ms;
        }
        .panel,
        .list > .row-open {
          animation: p2p-rise 360ms cubic-bezier(0.22, 1, 0.36, 1) both;
          animation-delay: 200ms;
        }
      }
      @keyframes p2p-band-in {
        from {
          opacity: 0;
          transform: translateY(-0.5rem);
        }
        to {
          opacity: 1;
          transform: translateY(0);
        }
      }
      @keyframes p2p-rise {
        from {
          opacity: 0;
          transform: translateY(0.625rem);
        }
        to {
          opacity: 1;
          transform: translateY(0);
        }
      }
      @keyframes rail-flow {
        0% {
          left: 0;
          opacity: 0;
        }
        15% {
          opacity: 1;
        }
        85% {
          opacity: 1;
        }
        100% {
          left: calc(100% - 0.375rem);
          opacity: 0;
        }
      }
      @container (max-width: 40rem) {
        .rail {
          flex-wrap: wrap;
          gap: var(--boxel-sp-xs);
        }
        .rail-link {
          display: none;
        }
        .station {
          flex: 1 1 40%;
        }
      }
    </style>
  </template>
}
