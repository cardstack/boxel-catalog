import { CardDef } from '@cardstack/base/card-api';
import { Component } from '@cardstack/base/card-api';
import { identifyCard, realmURL, type getCards } from '@cardstack/runtime-common';
import type Owner from '@ember/owner';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import {
  Pill,
  Button,
  BoxelInput,
  ViewSelector,
} from '@cardstack/boxel-ui/components';
import Plus from '@cardstack/boxel-icons/plus';
import LayoutGrid from '@cardstack/boxel-icons/layout-grid';
import LayoutList from '@cardstack/boxel-icons/layout-list';
import TableIcon from '@cardstack/boxel-icons/table';
import { debounce } from 'lodash';

import { Table } from '../../components/table';
import { formatMoney } from '../commerce/line-item-totals';

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

import type { RfqToPaymentApp } from './rfq-to-payment-app';
import {
  TABS,
  STATIONS,
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
    let live = { isLive: true };
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
    let url = (this.args.model as any)?.[realmURL];
    return url ? [url.href] : undefined;
  }

  // Prerender gets the static shell; the query-heavy console mounts only
  // when CRUD functions are present (interactive contexts).
  get isInteractive() {
    return Boolean((this.args as any).viewCard);
  }

  get requisitions(): PurchaseRequisition[] {
    return ((this.requisitionList?.instances ??
      []) as PurchaseRequisition[]).filter(Boolean);
  }
  get rfqs(): Rfq[] {
    return ((this.rfqList?.instances ?? []) as Rfq[]).filter(Boolean);
  }
  get pos(): PurchaseOrder[] {
    return ((this.poList?.instances ?? []) as PurchaseOrder[]).filter(
      Boolean,
    );
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
  // AP-leg invoices only: a vendor invoice names its PO. Sell-side
  // invoices in the same realm never enter this console.
  get apInvoices(): Invoice[] {
    return ((this.invoiceList?.instances ?? []) as Invoice[])
      .filter(Boolean)
      .filter((i) => {
        try {
          return Boolean(i.purchaseOrder);
        } catch {
          return false;
        }
      });
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

  // ---- collection shell state (one set of names per collection) --------
  // One view state shared by every tab (§7.3 consistency): grid and list
  // render the SAME filtered array through each card's own fitted template
  // (live mounts — demo-scale realm, and it keeps the mirroring rule
  // trivially true: three drawings of one array); table is the shared
  // Table block fed that same array with explicit columns.
  @tracked view: string = 'list';
  viewItems = [
    { id: 'grid', icon: LayoutGrid },
    { id: 'list', icon: LayoutList },
    { id: 'table', icon: TableIcon },
  ];
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
    return rows.filter((r) => this.matches(q, r.title));
  }
  get visiblePos() {
    let q = this.searchText.trim().toLowerCase();
    let rows = this.pos;
    if (this.stationFilter === 'approvals') {
      rows = this.pendingApprovalPos;
    } else if (this.stationFilter === 'receiving') {
      rows = this.awaitingReceiptPos;
    } else if (this.stationFilter === 'received') {
      rows = rows.filter((p) =>
        ['received', 'closed'].includes(p.status ?? ''),
      );
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
      rows = rows.filter((i) =>
        ['approved-for-payment', 'partial', 'paid'].includes(i.status ?? ''),
      );
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
    this.activeTab = key;
    this.stationFilter = undefined;
    this.searchText = '';
  };

  setBadge = (id: string) => {
    this.stationFilter = id === 'all' ? undefined : id;
  };

  goToStation = (station: Station) => {
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
    (this.args as any).createCard?.(ref, undefined, {
      realmURL: new URL(realm),
      doc: { data: { attributes, meta: { adoptsFrom: ref } } },
    });
  };
  addRequisition = () =>
    this.addCard(PurchaseRequisition, { status: 'draft' });
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
    (this.args as any).viewCard?.(card, 'isolated');
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
    return `background: conic-gradient(var(--state-green-fg, #15803d) 0deg ${deg}deg, var(--state-red-fg, #b91c1c) ${deg}deg 360deg);`;
  }

  // PO value by lifecycle bucket — the "where is the money right now"
  // chart a finance reader scans first.
  get poValueBuckets() {
    let buckets = [
      { key: 'pending', label: 'Pending approval', statuses: ['pending-approval'], hue: 'amber' },
      { key: 'committed', label: 'Approved · committed', statuses: ['approved', 'sent', 'partially-received'], hue: 'ink' },
      { key: 'received', label: 'Received · actual', statuses: ['received', 'closed'], hue: 'green' },
    ].map((b) => ({
      ...b,
      total: this.pos
        .filter((p) => b.statuses.includes(p.status ?? ''))
        .reduce((s, p) => s + (p.totalAmount ?? 0), 0),
      count: this.pos.filter((p) => b.statuses.includes(p.status ?? ''))
        .length,
    }));
    let max = Math.max(1, ...buckets.map((b) => b.total));
    return buckets.map((b) => ({
      ...b,
      totalLabel: formatMoney(b.total, 'USD'),
      barStyle: `width: ${Math.round((b.total / max) * 100)}%;`,
    }));
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
            <nav class='tabs'>
              {{#each TABS as |tab|}}
                <button
                  type='button'
                  class='tab {{if (eq this.activeTab tab.key) "active"}}'
                  {{on 'click' (fn this.setTab tab.key)}}
                >{{tab.label}}</button>
              {{/each}}
            </nav>
          {{/if}}
        </div>

        {{#if this.isInteractive}}
          <div class='rail' aria-label='Procure-to-Pay pipeline'>
            {{#each STATIONS as |station index|}}
              {{#if index}}<span class='rail-link' aria-hidden='true'><span
                    class='rail-dot'
                  ></span></span>{{/if}}
              <button
                type='button'
                class='station'
                {{on 'click' (fn this.goToStation station)}}
              >
                <span class='station-count'>{{this.stationCount
                    station.key
                  }}</span>
                <span class='station-label'>{{station.label}}</span>
                <span class='station-sub'>{{station.filterLabel}}</span>
              </button>
            {{/each}}
          </div>
        {{/if}}
      </header>

      {{#unless this.isInteractive}}
        <p class='shell-note'>Procure-to-Pay console: requisitions, RFQs,
          purchase orders, receipts, and budget health. Open the app to
          work the pipeline.</p>
      {{/unless}}

      {{#if this.isInteractive}}
        {{#if (eq this.activeTab 'vendors')}}
          {{#if this.vendorFlash}}
            <div class='flash warn'>{{this.vendorFlash}}</div>
          {{/if}}
          <StatusBoard
            @items={{this.profiles}}
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
          <div class='collection-toolbar'>
            <div class='toolbar-left'>
              <div class='search'>
                <BoxelInput
                  @type='search'
                  @value={{this.searchText}}
                  @onInput={{this.setSearch}}
                  @placeholder='Search this list'
                  autocomplete='off'
                />
              </div>
              <div class='badge-row'>
                {{#each this.badges as |b|}}
                  <Pill
                    @kind='button'
                    class='badge {{if (eq this.activeBadge b.id) "active"}}'
                    aria-pressed='{{eq this.activeBadge b.id}}'
                    {{on 'click' (fn this.setBadge b.id)}}
                  >
                    {{b.label}}
                    <span class='badge-count'>{{b.count}}</span>
                  </Pill>
                {{/each}}
              </div>
            </div>
            <div class='toolbar-right'>
              <ViewSelector
                @items={{this.viewItems}}
                @selectedId={{this.view}}
                @onChange={{this.setView}}
              />
              {{#if this.addAction}}
                <Button
                  @kind='primary'
                  @size='small'
                  {{on 'click' this.addAction.run}}
                >
                  <Plus width='16' height='16' role='presentation' />
                  {{this.addAction.label}}
                </Button>
              {{/if}}
            </div>
          </div>
        {{/unless}}
        {{/unless}}

        {{#if (eq this.activeTab 'dashboard')}}
          <div class='dash'>
            <section class='panel dash-main'>
              <h2>Budgets · committed vs actual</h2>
              <div class='list'>
                {{#each this.budgets as |budget|}}
                  <button
                    type='button'
                    class='row-open budget-row'
                    {{on 'click' (fn this.openCard budget)}}
                  >
                    {{#let (this.budgetComponent budget) as |C|}}
                      <C @format='embedded' />
                    {{/let}}
                  </button>
                {{else}}
                  <p class='empty'>No budgets yet — commitment accounting
                    starts when the first Procurement Budget exists.</p>
                {{/each}}
              </div>

              <h2 class='mt'>Where the money is · PO value by stage</h2>
              <div class='value-chart'>
                {{#each this.poValueBuckets as |b|}}
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
                    <button
                      type='button'
                      class='row-open'
                      {{on 'click' (fn this.openCard gr)}}
                    ><span class='row-title'>{{gr.title}}</span>
                      <span class='row-meta'>{{if
                          gr.posted
                          'posted'
                          'draft'
                        }}
                        · {{gr.matchResult}}</span></button>
                  {{else}}
                    <p class='empty'>Nothing received yet.</p>
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
              class='cards {{if (eq this.view "grid") "grid-view" "strip-view"}}'
            >
              {{#each this.visibleRequisitions as |pr|}}
                <button
                  type='button'
                  class='cell'
                  {{on 'click' (fn this.openCard pr)}}
                >
                  {{#let (this.fittedComponent pr) as |C|}}
                    <C @format='fitted' @displayContainer={{false}} />
                  {{/let}}
                </button>
              {{else}}
                <p class='empty'>Nothing here — the P2P chain starts with
                  a requisition.</p>
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
              class='cards {{if (eq this.view "grid") "grid-view" "strip-view"}}'
            >
              {{#each this.visibleRfqs as |rfq|}}
                <button
                  type='button'
                  class='cell'
                  {{on 'click' (fn this.openCard rfq)}}
                >
                  {{#let (this.fittedComponent rfq) as |C|}}
                    <C @format='fitted' @displayContainer={{false}} />
                  {{/let}}
                </button>
              {{else}}
                <p class='empty'>No RFQs in this view — convert a
                  requisition to start comparing vendors.</p>
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
              class='cards {{if (eq this.view "grid") "grid-view" "strip-view"}}'
            >
              {{#each this.visiblePos as |po|}}
                <button
                  type='button'
                  class='cell'
                  {{on 'click' (fn this.openCard po)}}
                >
                  {{#let (this.fittedComponent po) as |C|}}
                    <C @format='fitted' @displayContainer={{false}} />
                  {{/let}}
                </button>
              {{else}}
                <p class='empty'>No purchase orders in this view.</p>
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
              class='cards {{if (eq this.view "grid") "grid-view" "strip-view"}}'
            >
              {{#each this.visibleInvoices as |inv|}}
                <button
                  type='button'
                  class='cell'
                  {{on 'click' (fn this.openCard inv)}}
                >
                  {{#let (this.fittedComponent inv) as |C|}}
                    <C @format='fitted' @displayContainer={{false}} />
                  {{/let}}
                </button>
              {{else}}
                <p class='empty'>No vendor invoices yet — record one
                  against a received PO to run the match.</p>
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
              class='cards {{if (eq this.view "grid") "grid-view" "strip-view"}}'
            >
              {{#each this.visibleReceipts as |gr|}}
                <button
                  type='button'
                  class='cell'
                  {{on 'click' (fn this.openCard gr)}}
                >
                  {{#let (this.fittedComponent gr) as |C|}}
                    <C @format='fitted' @displayContainer={{false}} />
                  {{/let}}
                </button>
              {{else}}
                <p class='empty'>No goods receipts yet — record what
                  arrives against an approved PO.</p>
              {{/each}}
            </div>
          {{/if}}
        {{/if}}
      {{/if}}
    </article>
    <style scoped>
      .app {
        --console-ink: var(--procurement-ink, var(--primary, var(--boxel-dark)));
        --console-ink-fg: var(--procurement-ink-fg, var(--primary-foreground, var(--boxel-light)));
        container-type: inline-size;
        padding: 0 var(--boxel-sp-lg) var(--boxel-sp-lg);
        background:
          radial-gradient(
            1200px 380px at 20% -10%,
            color-mix(in oklch, var(--console-ink) 7%, transparent),
            transparent 65%
          ),
          var(--background, var(--boxel-light));
        color: var(--foreground, var(--boxel-dark));
        font-family: var(--font-sans, inherit);
        min-height: 100%;
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp);
      }
      .command-band {
        background:
          linear-gradient(
            120deg,
            color-mix(in oklch, var(--console-ink) 96%, black),
            var(--console-ink) 55%,
            color-mix(in oklch, var(--console-ink) 82%, #4a5bc4)
          );
        color: var(--console-ink-fg);
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
            color-mix(in oklch, var(--console-ink-fg) 7%, transparent) 1px,
            transparent 1px
          ),
          linear-gradient(
            90deg,
            color-mix(in oklch, var(--console-ink-fg) 7%, transparent) 1px,
            transparent 1px
          );
        background-size: 28px 28px;
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
        color: color-mix(in oklch, var(--console-ink-fg) 65%, transparent);
      }
      h1 {
        margin: var(--boxel-sp-5xs) 0 0;
        font-family: var(--font-heading, inherit);
        font-size: 1.75rem;
        letter-spacing: -0.015em;
      }
      .tabs {
        display: flex;
        gap: var(--boxel-sp-5xs);
        flex-wrap: wrap;
      }
      .tab {
        border: 1px solid
          color-mix(in oklch, var(--console-ink-fg) 25%, transparent);
        border-radius: 999px;
        background: transparent;
        color: color-mix(in oklch, var(--console-ink-fg) 85%, transparent);
        font: inherit;
        font-size: 0.875rem;
        padding: var(--boxel-sp-4xs) var(--boxel-sp-sm);
        cursor: pointer;
        transition:
          background 140ms ease,
          color 140ms ease;
      }
      .tab:hover {
        background: color-mix(in oklch, var(--console-ink-fg) 12%, transparent);
      }
      .tab.active {
        background: var(--console-ink-fg);
        color: var(--console-ink);
        border-color: var(--console-ink-fg);
        font-weight: 600;
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
        display: flex;
        flex-direction: column;
        align-items: flex-start;
        gap: 2px;
        border: 1px solid
          color-mix(in oklch, var(--console-ink-fg) 18%, transparent);
        border-radius: var(--radius, var(--boxel-border-radius));
        background: color-mix(in oklch, var(--console-ink-fg) 7%, transparent);
        color: var(--console-ink-fg);
        font: inherit;
        text-align: left;
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        cursor: pointer;
        transition:
          transform 160ms cubic-bezier(0.34, 1.56, 0.64, 1),
          background 160ms ease;
      }
      .station:hover {
        background: color-mix(in oklch, var(--console-ink-fg) 16%, transparent);
        transform: translateY(-2px);
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
        color: color-mix(in oklch, var(--console-ink-fg) 60%, transparent);
      }
      .rail-link {
        width: 34px;
        align-self: center;
        height: 2px;
        background: color-mix(in oklch, var(--console-ink-fg) 30%, transparent);
        position: relative;
        flex: 0 0 auto;
      }
      .rail-dot {
        position: absolute;
        top: -2px;
        left: 0;
        width: 6px;
        height: 6px;
        border-radius: 50%;
        background: var(--console-ink-fg);
      }
      .collection-toolbar {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        flex-wrap: wrap;
      }
      .toolbar-left {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        flex: 1 1 auto;
        min-width: 0;
        flex-wrap: nowrap;
      }
      .toolbar-right {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        flex: 0 0 auto;
        margin-left: auto;
      }
      .search {
        flex: 0 1 24rem;
        min-width: 8rem;
      }
      .search :deep(.search) {
        --boxel-input-search-background-color: var(--card, var(--boxel-light));
        --boxel-input-search-color: var(--foreground, var(--boxel-dark));
      }
      .search :deep(.search-icon) {
        --boxel-input-search-icon-color: var(
          --muted-foreground,
          var(--boxel-450)
        );
      }
      .badge-row {
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp-4xs);
        min-width: 0;
      }
      .badge {
        flex: 0 0 auto;
        white-space: nowrap;
      }
      .badge.active {
        background: var(--console-ink);
        color: var(--console-ink-fg);
        border-color: var(--console-ink);
      }
      .badge-count {
        font-variant-numeric: tabular-nums;
        opacity: 0.7;
        margin-left: 4px;
      }
      @container (width < 760px) {
        .toolbar-left {
          flex-wrap: wrap;
        }
      }
      .panel {
        border: 1px solid var(--border, var(--boxel-200));
        border-radius: var(--radius, var(--boxel-border-radius));
        padding: var(--boxel-sp);
        background: var(--card, transparent);
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
        color: var(--muted-foreground, var(--boxel-450));
      }
      .vc-count {
        opacity: 0.7;
        font-variant-numeric: tabular-nums;
      }
      .vc-track {
        height: 14px;
        border-radius: 7px;
        background: var(--muted, var(--boxel-100));
        overflow: hidden;
      }
      .vc-bar {
        height: 100%;
        border-radius: 7px;
        min-width: 3px;
      }
      .vc-bar.hue-amber {
        background: var(--state-amber-fg, #b45309);
      }
      .vc-bar.hue-ink {
        background: repeating-linear-gradient(
          45deg,
          var(--console-ink),
          var(--console-ink) 4px,
          color-mix(in oklch, var(--console-ink) 55%, transparent) 4px,
          color-mix(in oklch, var(--console-ink) 55%, transparent) 8px
        );
      }
      .vc-bar.hue-green {
        background: var(--state-green-fg, #15803d);
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
        width: 108px;
        height: 108px;
        border-radius: 50%;
        flex: 0 0 auto;
        display: grid;
        place-items: center;
      }
      .donut-hole {
        width: 74px;
        height: 74px;
        border-radius: 50%;
        background: var(--card, var(--boxel-light));
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
        color: var(--muted-foreground, var(--boxel-450));
      }
      .donut-label {
        font-size: 0.625rem;
        text-transform: uppercase;
        letter-spacing: 0.08em;
        color: var(--muted-foreground, var(--boxel-450));
      }
      .donut-legend {
        display: grid;
        gap: var(--boxel-sp-5xs);
        font-size: 0.8125rem;
        font-variant-numeric: tabular-nums;
      }
      .swatch {
        display: inline-block;
        width: 10px;
        height: 10px;
        border-radius: 3px;
        margin-right: 6px;
      }
      .swatch.ok {
        background: var(--state-green-fg, #15803d);
      }
      .swatch.bad {
        background: var(--state-red-fg, #b91c1c);
      }
      @container (width < 760px) {
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
        color: var(--muted-foreground, var(--boxel-450));
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
        grid-template-columns: repeat(auto-fill, minmax(240px, 1fr));
      }
      .cards.grid-view .cell {
        height: 170px;
      }
      .cards.strip-view {
        grid-template-columns: 1fr;
      }
      .cards.strip-view .cell {
        height: 65px;
      }
      .cell {
        padding: 0;
        border: 1px solid var(--border, var(--boxel-200));
        border-radius: var(--radius, var(--boxel-border-radius));
        background: var(--card, var(--boxel-light));
        overflow: hidden;
        cursor: pointer;
        text-align: left;
        font: inherit;
        color: inherit;
        transition:
          border-color 140ms ease,
          box-shadow 140ms ease,
          transform 140ms ease;
      }
      .cell:hover,
      .cell:focus-visible {
        border-color: var(--console-ink);
        box-shadow: 0 2px 10px -6px
          color-mix(in oklch, var(--console-ink) 55%, transparent);
        transform: translateY(-1px);
      }
      .cell:focus-visible {
        outline: 2px solid var(--console-ink);
        outline-offset: 2px;
      }
      .cell > :deep(.field-component-card.fitted-format) {
        width: 100%;
        height: 100%;
      }
      .row-open {
        display: flex;
        justify-content: space-between;
        align-items: baseline;
        gap: var(--boxel-sp-sm);
        width: 100%;
        text-align: left;
        border: 1px solid var(--border, var(--boxel-200));
        border-radius: var(--radius, var(--boxel-border-radius));
        background: var(--card, transparent);
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        cursor: pointer;
        font: inherit;
        color: inherit;
        transition:
          border-color 140ms ease,
          transform 140ms ease;
      }
      .row-open:hover {
        border-color: var(--console-ink);
        transform: translateX(2px);
      }
      .budget-row {
        display: block;
      }
      .row-title {
        font-weight: 600;
        font-size: 0.9375rem;
      }
      .row-title.mono {
        font-family: var(--font-mono, ui-monospace, monospace);
      }
      .row-meta {
        font-size: 0.8125rem;
        color: var(--muted-foreground, var(--boxel-450));
      }
      .empty {
        margin: 0;
        padding: var(--boxel-sp-sm);
        border: 1px dashed var(--border, var(--boxel-300));
        border-radius: var(--radius, var(--boxel-border-radius));
        color: var(--muted-foreground, var(--boxel-450));
        font-size: 0.875rem;
        font-style: italic;
      }
      .shell-note {
        margin: 0;
        padding: var(--boxel-sp-lg);
        border: 1px dashed var(--border, var(--boxel-300));
        border-radius: var(--radius, var(--boxel-border-radius));
        color: var(--muted-foreground, var(--boxel-450));
        font-size: 0.875rem;
      }
      .flash {
        border-radius: var(--radius, var(--boxel-border-radius));
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        font-size: 0.875rem;
      }
      .flash.warn {
        background: color-mix(
          in oklch,
          var(--state-amber-fg, #b45309) 12%,
          transparent
        );
        color: var(--state-amber-fg, #b45309);
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
        .rail .station:nth-of-type(1) { animation-delay: 120ms; }
        .rail .station:nth-of-type(2) { animation-delay: 190ms; }
        .rail .station:nth-of-type(3) { animation-delay: 260ms; }
        .rail .station:nth-of-type(4) { animation-delay: 330ms; }
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
          transform: translateY(-8px);
        }
        to {
          opacity: 1;
          transform: translateY(0);
        }
      }
      @keyframes p2p-rise {
        from {
          opacity: 0;
          transform: translateY(10px);
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
          left: calc(100% - 6px);
          opacity: 0;
        }
      }
      @container (max-width: 640px) {
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
