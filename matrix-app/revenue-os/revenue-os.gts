import { CardDef, Component, contains, field } from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import type Owner from '@ember/owner';
import { tracked } from '@glimmer/tracking';
import { action } from '@ember/object';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Alert } from '@cardstack/pretui/components/alert';
import { Button } from '@cardstack/pretui/components/button';
import { Select } from '@cardstack/pretui/components/select';
import { Switch } from '@cardstack/pretui/components/switch';
import {
  identifyCard,
  realmURL,
  type getCards,
} from '@cardstack/runtime-common';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import PatchCardInstanceCommand from '@cardstack/boxel-host/commands/patch-card-instance';
import ChartAreaIcon from '@cardstack/boxel-icons/chart-area';
import { Board, type BoardColumn } from '@cardstack/catalog/components/board';
import { type ImportRowResult } from '@cardstack/catalog/components/import';
import { toDate } from '@cardstack/catalog/fields/effective-period/effective-period-field';
import {
  Sidebar,
  SidebarGroup,
  SidebarItem,
} from '@cardstack/pretui/components/sidebar';
import { LayoutControl } from '@cardstack/pretui/components/layout-control';
import PlusIcon from '@cardstack/boxel-icons/plus';
import LayoutKanbanIcon from '@cardstack/boxel-icons/layout-kanban';
import LayoutDashboardIcon from '@cardstack/boxel-icons/layout-dashboard';
import BuildingIcon from '@cardstack/boxel-icons/building-2';
import ReceiptIcon from '@cardstack/boxel-icons/receipt';
import TargetIcon from '@cardstack/boxel-icons/target';
import MapPinIcon from '@cardstack/boxel-icons/map-pin';
import FileTextIcon from '@cardstack/boxel-icons/file-text';
import TagIcon from '@cardstack/boxel-icons/tag';
import { PageHead } from './components/page-head';
import { StatStrip } from './components/stat-strip';
import { AccountsPane } from './components/accounts-pane';
import { DashboardPane } from './components/dashboard-pane';
import { InvoicesPane } from './components/invoices-pane';
import { RecordTable, type RecordColumn } from './components/record-table';
import { VisuallyHidden } from '@cardstack/pretui/components/visually-hidden';
import { SearchInput } from '@cardstack/pretui/components/search-input';
import { Opportunity, PIPELINE_STAGES, STAGE_COLORS } from '../crm/opportunity';
import { Account } from '../crm/account';
import { Invoice } from '../commerce/invoice';
import { Subscription } from '../commerce/subscription';
import { Lead } from '../crm/lead';
import { Contact } from '../crm/contact';
import { Deal } from '../commerce/deal';
import { Territory } from '../commerce/territory';
import { Proposal } from '../commerce/proposal';
import { Quote } from '../commerce/quote';
import { Activity } from '../crm/activity';
import ConvertLeadCommand from '../crm/commands/convert-lead';
import RecordPaymentCommand from '../commerce/commands/record-payment';
import CloseWonCommand from '../crm/commands/close-won';
import DuplicateCommand from '@cardstack/catalog/commands/duplicate';
import ClassifyCommand from '@cardstack/catalog/commands/classify';
import { formatMoney, outstandingBalance } from '../commerce/line-item-totals';

import {
  BASE_CURRENCY,
  BOARD_SORT_OPTIONS,
  CLOSE_WINDOW_OPTIONS,
  LEAD_SCORING_CRITERIA,
  OPEN_INVOICE_STATUSES,
  OPEN_STAGES,
  PERIOD_OPTIONS,
  TABS,
  asCalendarDay,
  inBase,
  isBaseInvoice,
  type TrendPoint,
} from './revenue-os-data';

export class RevenueOsConsole extends Component<typeof RevenueOs> {
  @tracked activeTab = 'pipeline';
  @tracked invoiceFilter = 'open';
  @tracked ownerFilter = 'all';
  @tracked closeWindow = 'all';
  @tracked boardSort = 'value';
  @tracked period = 'month';
  @tracked comparePrevious = false;
  @tracked showAllStages = false;
  @tracked accountQuery = '';
  @tracked selectedAccountId: string | undefined;
  @tracked selectedDeal: Opportunity | undefined;
  @tracked statusMessage = '';
  @tracked busy = false;

  private opportunityList: ReturnType<getCards> | undefined;
  private accountList: ReturnType<getCards> | undefined;
  private invoiceList: ReturnType<getCards> | undefined;
  private subscriptionList: ReturnType<getCards> | undefined;
  private leadList: ReturnType<getCards> | undefined;
  private contactList: ReturnType<getCards> | undefined;
  private activityList: ReturnType<getCards> | undefined;
  private territoryList: ReturnType<getCards> | undefined;
  private proposalList: ReturnType<getCards> | undefined;
  private quoteList: ReturnType<getCards> | undefined;

  constructor(owner: Owner, args: any) {
    super(owner, args);
    let live = { isLive: true as const };
    let realms = () => this.realms;
    let queryFor = (type: any) => () => {
      let ref = identifyCard(type);
      return ref ? { filter: { type: ref } } : undefined;
    };
    let ctx = this.args.context;
    this.opportunityList = ctx?.getCards(
      this,
      queryFor(Opportunity),
      realms,
      live,
    );
    this.accountList = ctx?.getCards(this, queryFor(Account), realms, live);
    this.invoiceList = ctx?.getCards(this, queryFor(Invoice), realms, live);
    this.subscriptionList = ctx?.getCards(
      this,
      queryFor(Subscription),
      realms,
      live,
    );
    this.leadList = ctx?.getCards(this, queryFor(Lead), realms, live);
    this.contactList = ctx?.getCards(this, queryFor(Contact), realms, live);
    this.activityList = ctx?.getCards(this, queryFor(Activity), realms, live);
    this.territoryList = ctx?.getCards(this, queryFor(Territory), realms, live);
    this.proposalList = ctx?.getCards(this, queryFor(Proposal), realms, live);
    this.quoteList = ctx?.getCards(this, queryFor(Quote), realms, live);
  }

  // One array per realm href: the 13 getCards thunks read this on every render, and a
  // fresh array each time re-sets realmsToSearch after it was consumed (autotracking error).
  private realmsCache: { href: string; list: string[] } | undefined;
  private get realms(): string[] | undefined {
    let href = (this.args.model as any)?.[realmURL]?.href as string | undefined;
    if (!href) return undefined;
    if (this.realmsCache?.href !== href) {
      this.realmsCache = { href, list: [href] };
    }
    return this.realmsCache.list;
  }

  get realm(): string | undefined {
    return this.realms?.[0];
  }

  get commandContext() {
    return this.args.context?.commandContext;
  }

  // CardCrudFunctions ride on component args only in interactive contexts;
  // prerender gets the static shell so the indexer never mounts the board.
  private get isInteractive() {
    return Boolean(this.args.viewCard);
  }

  // ── data ──────────────────────────────────────────────────────────
  get opportunities(): Opportunity[] {
    return ((this.opportunityList?.instances ?? []) as Opportunity[]).filter(
      Boolean,
    );
  }
  get territories(): Territory[] {
    return ((this.territoryList?.instances ?? []) as Territory[]).filter(
      Boolean,
    );
  }
  get proposals(): Proposal[] {
    return ((this.proposalList?.instances ?? []) as Proposal[]).filter(Boolean);
  }
  get quotes(): Quote[] {
    return ((this.quoteList?.instances ?? []) as Quote[]).filter(Boolean);
  }
  get accounts(): Account[] {
    return ((this.accountList?.instances ?? []) as Account[]).filter(Boolean);
  }
  get invoices(): Invoice[] {
    return ((this.invoiceList?.instances ?? []) as Invoice[]).filter(Boolean);
  }
  get subscriptions(): Subscription[] {
    return ((this.subscriptionList?.instances ?? []) as Subscription[]).filter(
      Boolean,
    );
  }
  get leads(): Lead[] {
    return ((this.leadList?.instances ?? []) as Lead[]).filter(Boolean);
  }
  get contacts(): Contact[] {
    return ((this.contactList?.instances ?? []) as Contact[]).filter(Boolean);
  }
  get activities(): Activity[] {
    return ((this.activityList?.instances ?? []) as Activity[]).filter(Boolean);
  }

  // ── pipeline ──────────────────────────────────────────────────────
  boardColumns: BoardColumn[] = PIPELINE_STAGES.map((s) => ({
    key: s,
    label: s,
    color: STAGE_COLORS[s],
  }));
  columnKeyFor = (item: CardDef) => (item as Opportunity)?.stage;

  get owners(): string[] {
    let names = new Set<string>();
    for (let o of this.opportunities) {
      let n = o.owner?.name?.trim();
      if (n) names.add(n);
    }
    return [...names].sort();
  }

  get isLoading(): boolean {
    return !this.queriesSettled;
  }

  get queriesSettled(): boolean {
    return ![
      this.opportunityList,
      this.accountList,
      this.invoiceList,
      this.subscriptionList,
      // read here, at the top of the pane, so each search resource is first consumed
      // outside a nested list's render (consuming it inside re-sets its realms mid-render)
      this.contactList,
      this.activityList,
    ].some((list: any) => list?.isLoading);
  }

  get boardItems(): Opportunity[] {
    let items = this.opportunities;
    if (this.ownerFilter !== 'all') {
      items = items.filter((o) => o.owner?.name === this.ownerFilter);
    }
    let closesBy = this.closeWindowEnd;
    if (closesBy) {
      // A forecast window looks forward: a date that has already passed is
      // overdue, not "closing this week". And a deal with no close date has
      // not been forecast at all, so it cannot be claimed to close in one.
      let from = new Date();
      from.setHours(0, 0, 0, 0);
      items = items.filter((o) => {
        if (!o.closeDate) return false;
        let at = toDate(o.closeDate);
        if (!at) return false;
        return at >= from && at <= closesBy;
      });
    }
    // Board keeps whatever order it is handed, per column.
    let sorted = [...items];
    if (this.boardSort === 'value') {
      sorted.sort((a, b) => inBase(b.value) - inBase(a.value));
    } else if (this.boardSort === 'probability') {
      sorted.sort(
        (a, b) => (b.effectiveProbability ?? 0) - (a.effectiveProbability ?? 0),
      );
    } else if (this.boardSort === 'stale') {
      sorted.sort((a, b) => (b.daysInStage ?? 0) - (a.daysInStage ?? 0));
    }
    return sorted;
  }

  private get closeWindowEnd(): Date | undefined {
    if (this.closeWindow === 'all') return undefined;
    let now = new Date();
    let end = new Date(now);
    if (this.closeWindow === 'week') end.setDate(end.getDate() + 7);
    if (this.closeWindow === 'month') end.setMonth(end.getMonth() + 1);
    if (this.closeWindow === 'quarter') end.setMonth(end.getMonth() + 3);
    return end;
  }

  closeWindowOptions = CLOSE_WINDOW_OPTIONS;
  boardSortOptions = BOARD_SORT_OPTIONS;

  @action setCloseWindow(value: string) {
    this.closeWindow = value;
  }

  @action setBoardSort(value: string) {
    this.boardSort = value;
  }

  get ownerOptions() {
    return [
      { value: 'all', label: 'All owners' },
      ...this.owners.map((o) => ({ value: o, label: o })),
    ];
  }

  @action setOwnerFilter(value: string) {
    this.ownerFilter = value;
  }

  @action toggleAllStages() {
    this.showAllStages = !this.showAllStages;
  }

  // Actions hang off the selected card rather than sitting on the card face:
  // the face is the drag handle, and the toolbar has room for real labels.
  @action selectDeal(item: CardDef | undefined) {
    this.selectedDeal = item as Opportunity | undefined;
  }

  @action async addDealToStage(columnKey: string | null) {
    let ref = identifyCard(Deal);
    if (!ref) return;
    await this.args.createCard?.(ref, undefined, {
      realmURL: this.realm ? new URL(this.realm) : undefined,
      doc: {
        data: {
          attributes: {
            stage: columnKey ?? 'qualified',
            lastStageChangedAt: asCalendarDay(new Date()),
          },
          meta: { adoptsFrom: ref },
        },
      },
    });
  }

  @action async logDealActivity() {
    let deal = this.selectedDeal;
    let ref = identifyCard(Activity);
    if (!ref || !deal?.id) return;
    await this.args.createCard?.(ref, undefined, {
      realmURL: this.realm ? new URL(this.realm) : undefined,
      doc: {
        data: {
          attributes: {
            activityType: 'note',
            occurredAt: new Date().toISOString(),
          },
          relationships: { about: { links: { self: deal.id } } },
          meta: { adoptsFrom: ref },
        },
      },
    });
  }
  onMove = async (item: CardDef, columnKey: string) => {
    if (!this.commandContext || !this.realm) return false;
    if (columnKey === 'closed won') {
      await this.closeWon(item as Opportunity);
      return undefined;
    }
    let deal = item as Opportunity;
    let stageBefore = deal.stage;
    let changedBefore = deal.lastStageChangedAt;
    deal.stage = columnKey;
    deal.lastStageChangedAt = new Date();
    try {
      await new SaveCardCommand(this.commandContext).execute({
        card: item,
        realm: this.realm,
      } as any);
    } catch (e: any) {
      deal.stage = stageBefore;
      deal.lastStageChangedAt = changedBefore;
      this.statusMessage = e?.message ?? 'Moving the deal failed';
      return false;
    }
    return undefined;
  };

  // Winning a deal is the handoff the app exists to remove: the command
  // activates the subscription and drafts the first invoice, so dragging
  // into Closed Won runs it instead of just writing the stage.
  @action async closeWon(deal: Opportunity) {
    if (!this.commandContext || !this.realm) return;
    // The command works on its own refetched copy, so move the card here too
    // or it sits in its old column until the live query catches up.
    let stageBefore = deal.stage;
    deal.stage = 'closed won';
    this.busy = true;
    try {
      let result: any = await new CloseWonCommand(this.commandContext).execute({
        deal,
        realm: this.realm,
      } as any);
      this.statusMessage = result?.message ?? `${deal.name} closed won`;
    } catch (e: any) {
      deal.stage = stageBefore;
      this.statusMessage = e?.message ?? 'Close won failed';
    } finally {
      this.busy = false;
    }
  }

  get stageTotals() {
    // Counts the board you are looking at, not the whole pipeline — totals
    // beside a filtered board have to describe the filtered board.
    let open = this.boardItems.filter((o) =>
      OPEN_STAGES.includes(o.stage as (typeof OPEN_STAGES)[number]),
    );
    let total = 0;
    let weighted = 0;
    for (let o of open) {
      let v = inBase(o.value);
      total += v;
      weighted += (v * (o.effectiveProbability ?? 0)) / 100;
    }
    return {
      count: open.length,
      total: formatMoney(total, BASE_CURRENCY),
      weighted: formatMoney(weighted, BASE_CURRENCY),
    };
  }

  // ── dashboard ─────────────────────────────────────────────────────
  periodOptions = PERIOD_OPTIONS;

  @action setPeriod(value: string) {
    this.period = value;
  }

  @action toggleCompare() {
    this.comparePrevious = !this.comparePrevious;
  }

  // Two equal-length windows ending now and immediately before it.
  private get windows() {
    let now = new Date();
    let months =
      this.period === 'month' ? 1 : this.period === 'quarter' ? 3 : 12;
    let start = new Date(now);
    start.setMonth(start.getMonth() - months);
    let priorStart = new Date(start);
    priorStart.setMonth(priorStart.getMonth() - months);
    return { start, end: now, priorStart, priorEnd: start };
  }

  private inWindow(value: any, start: Date, end: Date): boolean {
    if (!value) return false;
    let at = toDate(value)?.getTime();
    if (at === undefined) return false;
    return at >= start.getTime() && at < end.getTime();
  }

  // A closed deal's lastStageChangedAt is when it reached its terminal
  // stage, which is the only close timestamp these records carry.
  private closedIn(start: Date, end: Date) {
    let won = this.opportunities.filter(
      (o) =>
        o.stage === 'closed won' &&
        this.inWindow(o.lastStageChangedAt, start, end),
    );
    let lost = this.opportunities.filter(
      (o) =>
        o.stage === 'closed lost' &&
        this.inWindow(o.lastStageChangedAt, start, end),
    );
    return { won, lost };
  }

  private collectedIn(start: Date, end: Date): number {
    let total = 0;
    for (let invoice of this.invoices) {
      for (let payment of invoice.payments ?? []) {
        if (this.inWindow(payment?.paidAt, start, end)) {
          total += inBase(payment?.amount);
        }
      }
    }
    return total;
  }

  private delta(now: number, before: number): string {
    if (!this.comparePrevious) return '';
    if (!before) return now ? 'new' : '';
    let change = Math.round(((now - before) / before) * 100);
    if (!change) return 'flat';
    return change > 0 ? `+${change}% vs prior` : `${change}% vs prior`;
  }

  get periodMetrics() {
    let { start, end, priorStart, priorEnd } = this.windows;
    let current = this.closedIn(start, end);
    let prior = this.closedIn(priorStart, priorEnd);
    let wonValue = (list: Opportunity[]) =>
      list.reduce((acc, o) => acc + inBase(o.value), 0);
    let rate = (c: { won: Opportunity[]; lost: Opportunity[] }) => {
      let closed = c.won.length + c.lost.length;
      return closed ? (c.won.length / closed) * 100 : 0;
    };
    let collected = this.collectedIn(start, end);
    let collectedBefore = this.collectedIn(priorStart, priorEnd);
    return [
      {
        label: 'Closed won',
        value: formatMoney(wonValue(current.won), BASE_CURRENCY),
        note: this.delta(wonValue(current.won), wonValue(prior.won)),
      },
      {
        label: 'Win rate',
        value:
          current.won.length + current.lost.length
            ? `${Math.round(rate(current))}%`
            : 'no closed deals',
        note: this.delta(rate(current), rate(prior)),
      },
      {
        label: 'Cash collected',
        value: formatMoney(collected, BASE_CURRENCY),
        note: this.delta(collected, collectedBefore),
      },
    ];
  }

  get dash() {
    let mrr = 0;
    let code = BASE_CURRENCY;
    for (let s of this.subscriptions) {
      if (!['active', 'trial'].includes(s.status ?? '')) continue;
      let p = inBase(s.price);
      mrr += s.billingCycle === 'yearly' ? p / 12 : p;
    }
    let open = this.invoices.filter(
      (i) => OPEN_INVOICE_STATUSES.includes(i.status ?? '') && isBaseInvoice(i),
    );
    let balanceOf = (list: Invoice[]) =>
      list.reduce(
        (acc, i) => acc + outstandingBalance(i.lineItems, i.payments),
        0,
      );
    return {
      mrr: formatMoney(mrr, code),
      arr: formatMoney(mrr * 12, code),
      secondary: [
        { label: 'Pipeline', value: this.stageTotals.total, tab: 'pipeline' },
        {
          label: 'Weighted forecast',
          value: this.stageTotals.weighted,
        },
        {
          label: 'Outstanding',
          value: formatMoney(balanceOf(open), code),
          tab: 'invoices',
          filter: 'open',
        },
      ],
    };
  }

  // A subscription earned in a past month if it had started by then and had
  // not been cancelled by then. Reading today's status alone would erase a
  // churned subscription from the months it was live, which makes the series
  // incapable of ever declining — the one thing an MRR trend exists to show.
  private earnedIn(s: Subscription, at: Date): boolean {
    let started = toDate(s.startDate);
    if (!started || started > at) return false;
    if (s.status === 'canceled') {
      // An undated cancellation is unknowable, so don't claim the revenue.
      let canceled = toDate(s.canceledAt);
      return canceled ? canceled > at : false;
    }
    return ['active', 'trial'].includes(s.status ?? '');
  }

  get mrrTrend(): TrendPoint[] {
    let now = new Date();
    let months: TrendPoint[] = [];
    for (let back = 7; back >= 0; back--) {
      let at = new Date(now.getFullYear(), now.getMonth() - back + 1, 0);
      let mrr = 0;
      for (let s of this.subscriptions) {
        if (!this.earnedIn(s, at)) continue;
        let p = inBase(s.price);
        mrr += s.billingCycle === 'yearly' ? p / 12 : p;
      }
      months.push({
        // Pret UI Chart sorts a point axis alphabetically; i leading zero-width
        // spaces keep the months in calendar order without changing how they read.
        label:
          '\u200b'.repeat(7 - back) +
          at.toLocaleDateString('en-US', { month: 'short' }),
        value: Math.round(mrr),
      });
    }
    return months;
  }
  chartMoney = (n: number) => formatMoney(n, BASE_CURRENCY);

  get stageBars() {
    let byStage = OPEN_STAGES.map((stage) => {
      let opps = this.opportunities.filter((o) => o.stage === stage);
      return {
        stage,
        count: opps.length,
        total: opps.reduce((acc, o) => acc + inBase(o.value), 0),
      };
    });
    return byStage.map((b) => ({ name: b.stage, value: b.total }));
  }

  // ── accounts / 360 ────────────────────────────────────────────────
  get filteredAccounts(): Account[] {
    let q = this.accountQuery.trim().toLowerCase();
    if (!q) return this.accounts;
    let matchingContactAccountIds = new Set(
      this.contacts
        .filter((c) => c.email?.toLowerCase().includes(q))
        .map((c) => c.account?.id)
        .filter(Boolean),
    );
    return this.accounts.filter(
      (a) =>
        a.name?.toLowerCase().includes(q) ||
        a.domain?.toLowerCase().includes(q) ||
        a.email?.toLowerCase().includes(q) ||
        (a.id && matchingContactAccountIds.has(a.id)),
    );
  }

  @action setAccountQuery(value: string) {
    this.accountQuery = value;
  }

  @action async logActivity() {
    let account = this.selectedAccount;
    let ref = identifyCard(Activity);
    if (!ref || !account?.id) return;
    await this.args.createCard?.(ref, undefined, {
      realmURL: this.realm ? new URL(this.realm) : undefined,
      doc: {
        data: {
          attributes: {
            activityType: 'note',
            occurredAt: new Date().toISOString(),
          },
          relationships: { about: { links: { self: account.id } } },
          meta: { adoptsFrom: ref },
        },
      },
    });
  }

  @action async newAccount() {
    let ref = identifyCard(Account);
    if (!ref) return;
    await this.args.createCard?.(ref, undefined, {
      realmURL: this.realm ? new URL(this.realm) : undefined,
      doc: { data: { attributes: {}, meta: { adoptsFrom: ref } } },
    });
  }

  @action async newInvoice() {
    let ref = identifyCard(Invoice);
    if (!ref) return;
    await this.args.createCard?.(ref, undefined, {
      realmURL: this.realm ? new URL(this.realm) : undefined,
      doc: {
        data: {
          attributes: {
            status: 'draft',
            issueDate: asCalendarDay(new Date()),
          },
          meta: { adoptsFrom: ref },
        },
      },
    });
  }

  // Quick-add from the 360 arrives already belonging to the account on
  // screen — that is what makes it quick.
  @action async newContact() {
    let account = this.selectedAccount;
    let ref = identifyCard(Contact);
    if (!ref || !account?.id) return;
    await this.args.createCard?.(ref, undefined, {
      realmURL: this.realm ? new URL(this.realm) : undefined,
      doc: {
        data: {
          attributes: {},
          relationships: { account: { links: { self: account.id } } },
          meta: { adoptsFrom: ref },
        },
      },
    });
  }

  @action async newDeal() {
    let account = this.selectedAccount;
    let ref = identifyCard(Deal);
    if (!ref || !account?.id) return;
    await this.args.createCard?.(ref, undefined, {
      realmURL: this.realm ? new URL(this.realm) : undefined,
      doc: {
        data: {
          attributes: {
            stage: 'qualified',
            lastStageChangedAt: asCalendarDay(new Date()),
          },
          relationships: { account: { links: { self: account.id } } },
          meta: { adoptsFrom: ref },
        },
      },
    });
  }

  @action async newLead() {
    let ref = identifyCard(Lead);
    if (!ref) return;
    await this.args.createCard?.(ref, undefined, {
      realmURL: this.realm ? new URL(this.realm) : undefined,
      doc: {
        data: {
          attributes: { status: 'new' },
          meta: { adoptsFrom: ref },
        },
      },
    });
  }

  get selectedAccount(): Account | undefined {
    let chosen = this.filteredAccounts.find(
      (a) => a.id === this.selectedAccountId,
    );
    if (chosen) return chosen;
    let weight = (a: Account) =>
      this.invoices.filter((i) => i.account?.id === a.id).length +
      this.subscriptions.filter((s) => s.account?.id === a.id).length;
    return [...this.filteredAccounts].sort((a, b) => weight(b) - weight(a))[0];
  }
  @action selectAccount(account: CardDef) {
    this.selectedAccountId = account.id;
  }

  @action reportImport(results: ImportRowResult[]) {
    let added = results.filter((r) => r.ok).length;
    let failed = results.filter((r) => !r.ok);
    if (!failed.length) {
      this.statusMessage = `Imported ${added} invoice${added === 1 ? '' : 's'}`;
      return;
    }
    // Partial success is the point: say what landed, then why the rest did not.
    let detail = failed
      .slice(0, 3)
      .map((r) => `row ${r.row} — ${r.error}`)
      .join('; ');
    let more = failed.length > 3 ? `, and ${failed.length - 3} more` : '';
    this.statusMessage = `Imported ${added}, skipped ${failed.length}: ${detail}${more}`;
  }

  @action openCard(item: CardDef) {
    this.args.viewCard?.(item, 'isolated');
  }

  @action async recordBalancePayment(item: CardDef) {
    let inv = item as Invoice;
    if (!this.commandContext || !this.realm) return;
    let amount = outstandingBalance(inv.lineItems, inv.payments);
    if (amount <= 0) return;
    this.busy = true;
    try {
      let result: any = await new RecordPaymentCommand(
        this.commandContext,
      ).execute({
        invoice: inv,
        amount,
        method: 'bank transfer',
        reference: `APP-${Date.now()}`,
        realm: this.realm,
      } as any);
      this.statusMessage = result?.message ?? 'Payment recorded';
    } catch (e: any) {
      this.statusMessage = e?.message ?? 'Recording payment failed';
    } finally {
      this.busy = false;
    }
  }

  // ── leads ─────────────────────────────────────────────────────────
  canConvert = (lead: Lead) =>
    !['converted', 'disqualified'].includes(lead.status ?? '');

  get leadCards(): Lead[] {
    return this.leads;
  }

  canConvertCard = (card: CardDef) => this.canConvert(card as Lead);

  // A converted lead's account is found by email domain, then company name.
  accountOfLead = (card: CardDef): Account | undefined => {
    let lead = card as Lead;
    if (lead.status !== 'converted') return undefined;
    let domain = lead.email?.split('@')[1];
    return (
      this.accounts.find((a) => a.domain && a.domain === domain) ??
      this.accounts.find((a) => a.name && a.name === lead.company)
    );
  };

  // A duplicated invoice is a fresh draft, not a second copy of a sent bill:
  // the command clones, then the app clears what must not be reused.
  @action async duplicateCard(item: CardDef) {
    if (!this.commandContext || !this.realm) return;
    this.busy = true;
    try {
      let result: any = await new DuplicateCommand(this.commandContext).execute(
        { card: item, realm: this.realm } as any,
      );
      let copy = result?.card as Invoice | undefined;
      if (copy?.id) {
        let today = new Date();
        let due = new Date(today);
        due.setDate(due.getDate() + 30);
        // A linksToMany clears per index, not with a single null: the copy
        // must not claim the original's payments.
        let relationships: Record<string, unknown> = {};
        ((item as Invoice).payments ?? []).forEach((_, i) => {
          relationships[`payments.${i}`] = { links: { self: null } };
        });
        await new PatchCardInstanceCommand(this.commandContext, {
          cardType: Invoice,
        }).execute({
          cardId: copy.id,
          patch: {
            attributes: {
              invoiceNumber: null,
              status: 'draft',
              issueDate: asCalendarDay(today),
              sentDate: null,
              dueDate: asCalendarDay(due),
            },
            relationships,
          },
        });
      }
      this.statusMessage = 'Duplicated as a new draft invoice';
    } catch (e: any) {
      this.statusMessage = e?.message ?? 'Duplicate failed';
    } finally {
      this.busy = false;
    }
  }

  @action scoreLeadCard(card: CardDef) {
    return this.scoreLead(card as Lead);
  }

  @action convertLeadCard(card: CardDef) {
    return this.convertLead(card as Lead);
  }

  @action async convertLead(lead: Lead) {
    if (!this.commandContext || !this.realm) return;
    this.busy = true;
    try {
      let result: any = await new ConvertLeadCommand(
        this.commandContext,
      ).execute({ lead, realm: this.realm } as any);
      this.statusMessage = result?.message ?? `${lead.name} converted`;
    } catch (e: any) {
      this.statusMessage = e?.message ?? 'Convert failed';
    } finally {
      this.busy = false;
    }
  }

  @action async scoreLead(lead: Lead) {
    if (!this.commandContext || !this.realm) return;
    this.busy = true;
    try {
      let campaign = lead.campaign;
      let result = await new ClassifyCommand(this.commandContext).execute({
        criteria: LEAD_SCORING_CRITERIA,
        facts: JSON.stringify({
          name: lead.name ?? null,
          company: lead.company ?? null,
          emailDomain: lead.email?.split('@')[1] ?? null,
          source: lead.source ?? null,
          status: lead.status ?? null,
          campaign: campaign
            ? {
                name: campaign.name ?? null,
                type: campaign.campaignType ?? null,
                status: campaign.status ?? null,
              }
            : null,
        }),
      } as any);
      let score = Math.max(0, Math.min(100, Math.round(result.score ?? 0)));
      lead.score = score;
      await new SaveCardCommand(this.commandContext).execute({
        card: lead,
        realm: this.realm,
      } as any);
      this.statusMessage = `${lead.name} scored ${score} (${
        result.label ?? '—'
      }): ${result.rationale ?? ''}`;
    } catch (e: any) {
      this.statusMessage = e?.message ?? 'Scoring failed';
    } finally {
      this.busy = false;
    }
  }

  @action setTab(key: string) {
    this.listQuery = '';
    this.activeTab = key;
    this.statusMessage = '';
  }
  @action setInvoiceFilter(key: string) {
    this.invoiceFilter = key;
  }

  // "I'm from Acme, can you check our invoice?" — the spec's reason for the
  // 360 tab. From an invoice row, the account is the useful destination.
  @action openAccountFor(item: CardDef) {
    let account = (item as Invoice).account;
    if (!account?.id) return;
    this.selectedAccountId = account.id;
    this.accountQuery = '';
    this.setTab('accounts');
  }

  @action drillTo(tab: string, filter?: string) {
    if (filter) this.invoiceFilter = filter;
    this.setTab(tab);
  }

  cardComponent = (card: CardDef) => {
    return (card.constructor as typeof CardDef).getComponent(card);
  };

  FORMS = [
    { name: 'full', minWidth: 11 },
    { name: 'menu', minWidth: 0 },
  ];
  PRIMARY_FORMS = [{ name: 'full', minWidth: 7 }];

  get navItems() {
    let openDeals = this.opportunities.filter((o) =>
      OPEN_STAGES.includes(o.stage as (typeof OPEN_STAGES)[number]),
    ).length;
    let openInvoices = this.invoices.filter((i) =>
      OPEN_INVOICE_STATUSES.includes(i.status ?? ''),
    ).length;
    let counts: Record<string, number> = {
      pipeline: openDeals,
      accounts: this.accounts.length,
      invoices: openInvoices,
      leads: this.leads.length,
      territories: this.territories.length,
      proposals: this.proposals.length,
      quotes: this.quotes.length,
    };
    let icons: Record<string, any> = {
      pipeline: LayoutKanbanIcon,
      dashboard: LayoutDashboardIcon,
      accounts: BuildingIcon,
      invoices: ReceiptIcon,
      leads: TargetIcon,
      territories: MapPinIcon,
      proposals: FileTextIcon,
      quotes: TagIcon,
    };
    return TABS.map((t) => ({
      value: t.value,
      label: t.label,
      icon: icons[t.value],
      badge: counts[t.value],
      active: this.activeTab === t.value,
    }));
  }

  get activeLabel() {
    return TABS.find((t) => t.value === this.activeTab)?.label ?? '';
  }

  get pipelineStats() {
    let [won, rate] = this.periodMetrics;
    return [
      {
        label: 'Open pipeline',
        value: this.stageTotals.total,
        hint: `${this.stageTotals.count} deals on the board`,
        tone: 'info',
      },
      {
        label: 'Weighted forecast',
        value: this.stageTotals.weighted,
        hint: 'by stage probability',
        tone: 'neutral',
      },
      {
        label: 'Closed won',
        value: won.value,
        hint: won.note,
        tone: 'success',
      },
      {
        label: 'Win rate',
        value: rate.value.startsWith('no closed') ? '—' : rate.value,
        hint: rate.value.startsWith('no closed')
          ? 'no closed deals yet'
          : rate.note,
        tone: 'warning',
      },
      {
        label: 'Outstanding',
        value: this.dash.secondary[2].value,
        hint: 'unpaid invoices',
        tone: 'danger',
      },
    ];
  }

  @tracked listQuery = '';
  @action setListQuery(value: string) {
    this.listQuery = value;
  }
  SEARCH_FORMS = [
    { name: 'full', minWidth: 14 },
    { name: 'menu', minWidth: 0 },
  ];
  matches = <T extends CardDef>(list: readonly T[]): T[] => {
    let q = this.listQuery.trim().toLowerCase();
    return q
      ? list.filter((c) => (c.cardTitle ?? '').toLowerCase().includes(q))
      : [...list];
  };
  money = (n: number | undefined) =>
    typeof n === 'number'
      ? formatMoney(n, BASE_CURRENCY).replace(/\.00$/, '')
      : '—';

  leadColumns: RecordColumn[] = [
    { label: 'Lead', kind: 'title', value: (c) => c },
    {
      label: 'Company · Source',
      kind: 'text',
      value: (c) => (c as Lead).company || '—',
      meta: (c) => (c as Lead).source ?? undefined,
    },
    { label: 'Status', kind: 'status', value: (c) => (c as Lead).status },
    {
      label: 'Score',
      kind: 'mono',
      align: 'end',
      value: (c) => (c as Lead).score ?? '—',
    },
  ];
  territoryColumns: RecordColumn[] = [
    { label: 'Territory', kind: 'title', value: (c) => c },
    {
      label: 'Region',
      kind: 'text',
      value: (c) => (c as Territory).region || '—',
    },
    { label: 'Owner', kind: 'atom', value: (c) => (c as Territory).owner },
  ];
  proposalColumns: RecordColumn[] = [
    { label: 'Proposal', kind: 'title', value: (c) => c },
    { label: 'Deal', kind: 'atom', value: (c) => (c as Proposal).deal },
  ];
  quoteColumns: RecordColumn[] = [
    { label: 'Quote', kind: 'title', value: (c) => c },
    { label: 'Deal', kind: 'atom', value: (c) => (c as Quote).deal },
    { label: 'Status', kind: 'status', value: (c) => (c as Quote).status },
    {
      label: 'Supersedes',
      kind: 'mono',
      value: (c) =>
        (c as Quote).supersedes
          ? `v${(c as Quote).supersedes?.version ?? 1}`
          : '—',
    },
    {
      label: 'Total',
      kind: 'mono',
      align: 'end',
      value: (c) => this.money((c as Quote).total),
    },
  ];

  get leadStats() {
    let n = (s: string) => this.leads.filter((l) => l.status === s).length;
    return [
      {
        label: 'Leads',
        value: this.leads.length,
        hint: 'in the funnel',
        tone: 'neutral',
      },
      { label: 'New', value: n('new'), hint: 'not yet worked', tone: 'info' },
      {
        label: 'Converted',
        value: n('converted'),
        hint: 'became accounts',
        tone: 'success',
      },
    ];
  }

  <template>
    {{#unless this.isInteractive}}
      <div class='app'>
        <main class='main'>
          <PageHead @title={{if @model.cardTitle @model.cardTitle 'Revenue OS'}} />
          <p class='empty'>Open in Interact mode for the pipeline, dashboard,
            and collections workspace.</p>
        </main>
      </div>
    {{/unless}}
    {{#if this.isInteractive}}
      <div class='app'>
        <Sidebar
          class='shell'
          @label='Revenue OS'
          @collapsible='rail'
          @railBreakpoint={{1100}}
          @mobileBreakpoint={{720}}
          @bordered={{true}}
          @scroll='content'
          @resizable={{true}}
        >
          <:header as |bar|>
            <div class='brand'>
              <span class='brand-mark' aria-hidden='true'><ChartAreaIcon
                  width='16'
                  height='16'
                /></span>
              {{#unless bar.collapsed}}
                <span class='brand-name'>Revenue OS<small
                  >{{@model.orgName}}</small></span>
              {{/unless}}
            </div>
          </:header>
          <:nav as |bar|>
            <SidebarGroup @label='Workspace' @hideLabel={{bar.collapsed}}>
              {{#each this.navItems key='value' as |item|}}
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
            <main class='main'>
              {{#if this.statusMessage}}
                <Alert class='status-banner' @tone='info' role='status'>
                  {{this.statusMessage}}
                </Alert>
              {{/if}}

              {{#if (eq this.activeTab 'pipeline')}}
                <section class='pane'>
                  <PageHead
                    @title='Pipeline'
                    @subtitle='{{this.stageTotals.count}} open deals across {{this.boardColumns.length}} stages · drag a deal to change its stage'
                  />
                  <StatStrip
                    @stats={{this.pipelineStats}}
                    @label='Pipeline totals'
                  />
                  <LayoutControl @label='Pipeline filters' as |lc|>
                    <lc.Slot
                      @id='stages'
                      @priority={{3}}
                      @forms={{this.FORMS}}
                      @label='Stages'
                    >
                      <label class='switch-wrap'>
                        <Switch
                          @checked={{this.showAllStages}}
                          @onCheckedChange={{this.toggleAllStages}}
                        />
                        <span class='switch-text'>All stages</span>
                      </label>
                    </lc.Slot>
                    {{#if this.owners.length}}
                      <lc.Slot
                        @id='owner'
                        @priority={{2}}
                        @forms={{this.FORMS}}
                        @label='Owner'
                      >
                        <Select
                          @options={{this.ownerOptions}}
                          @value={{this.ownerFilter}}
                          @onValueChange={{this.setOwnerFilter}}
                          @label='Owner'
                        />
                      </lc.Slot>
                    {{/if}}
                    <lc.Slot
                      @id='close'
                      @priority={{2}}
                      @forms={{this.FORMS}}
                      @label='Close date'
                    >
                      <Select
                        @options={{this.closeWindowOptions}}
                        @value={{this.closeWindow}}
                        @onValueChange={{this.setCloseWindow}}
                        @label='Close date'
                      />
                    </lc.Slot>
                    <lc.Slot
                      @id='sort'
                      @priority={{1}}
                      @forms={{this.FORMS}}
                      @label='Sort'
                    >
                      <Select
                        @options={{this.boardSortOptions}}
                        @value={{this.boardSort}}
                        @onValueChange={{this.setBoardSort}}
                        @label='Sort'
                      />
                    </lc.Slot>
                    <lc.Slot
                      @id='new'
                      @priority={{0}}
                      @pinned={{true}}
                      @forms={{this.PRIMARY_FORMS}}
                      @label='New deal'
                    >
                      <Button
                        @icon={{PlusIcon}}
                        @appearance='accent'
                        {{on 'click' this.newDeal}}
                      >New deal</Button>
                    </lc.Slot>
                  </LayoutControl>
                  <div class='block'>
                    <div class='block-head'>
                      <h2>Deals by stage</h2>
                      <span class='meta'>{{this.stageTotals.count}}
                        open deals</span>
                    </div>
                    {{#if this.selectedDeal}}
                      <div class='selection-bar'>
                        <span
                          class='selection-name'
                        >{{this.selectedDeal.cardTitle}}</span>
                        <Button
                          @appearance='outlined'
                          {{on 'click' (fn this.openCard this.selectedDeal)}}
                        >Open</Button>
                        <Button
                          @appearance='outlined'
                          {{on 'click' this.logDealActivity}}
                        >Log activity</Button>
                      </div>
                    {{/if}}
                    <div class='board-wrap'>
                      {{#if this.queriesSettled}}
                        <Board
                          @boardLabel='Pipeline'
                          @items={{this.boardItems}}
                          @columns={{this.boardColumns}}
                          @columnKeyFor={{this.columnKeyFor}}
                          @onMove={{this.onMove}}
                          @onOpen={{this.openCard}}
                          @onSelect={{this.selectDeal}}
                          @onAddCard={{this.addDealToStage}}
                          @hideEmpty={{unless this.showAllStages true}}
                        />
                      {{else}}
                        <p class='empty'>Loading pipeline…</p>
                      {{/if}}
                    </div>
                  </div>
                </section>
              {{/if}}

              {{#if (eq this.activeTab 'dashboard')}}
                <DashboardPane @console={{this}} />
              {{/if}}

              {{#if (eq this.activeTab 'accounts')}}
                <AccountsPane @console={{this}} @context={{@context}} />
              {{/if}}

              {{#if (eq this.activeTab 'invoices')}}
                <InvoicesPane @console={{this}} />
              {{/if}}

              {{#if (eq this.activeTab 'leads')}}
                <section class='pane'>
                  <PageHead
                    @title='Leads'
                    @subtitle='{{this.leads.length}} leads on file'
                  />
                  <StatStrip @stats={{this.leadStats}} @label='Lead totals' />
                  <LayoutControl @label='Leads search' as |lc|>
                    <lc.Slot
                      @id='search'
                      @priority={{1}}
                      @forms={{this.SEARCH_FORMS}}
                      @label='Search'
                    >
                      <label class='search-label'>
                        <VisuallyHidden>Search leads</VisuallyHidden>
                        <SearchInput
                          @placeholder='Search leads'
                          @value={{this.listQuery}}
                          @onInput={{this.setListQuery}}
                        />
                      </label>
                    </lc.Slot>
                    <span class='spacer'></span>
                    <lc.Slot
                      @id='new'
                      @priority={{0}}
                      @pinned={{true}}
                      @forms={{this.PRIMARY_FORMS}}
                      @label='New lead'
                    >
                      <Button
                        @icon={{PlusIcon}}
                        @appearance='accent'
                        {{on 'click' this.newLead}}
                      >New lead</Button>
                    </lc.Slot>
                  </LayoutControl>
                  <div class='block'>
                    <h2 class='block-title'>Leads</h2>
                    <RecordTable
                      @rows={{this.matches this.leadCards}}
                      @columns={{this.leadColumns}}
                      @label='Leads'
                      @onOpen={{this.openCard}}
                      @emptyMessage='No leads'
                    >
                      <:actions as |lead|>
                        {{#if (this.canConvertCard lead)}}
                          <Button
                            @appearance='plain'
                            @disabled={{this.busy}}
                            {{on 'click' (fn this.scoreLeadCard lead)}}
                          >Score</Button>
                          <Button
                            @appearance='plain'
                            @disabled={{this.busy}}
                            {{on 'click' (fn this.convertLeadCard lead)}}
                          >Convert</Button>
                        {{else if (this.accountOfLead lead)}}
                          <Button
                            @appearance='plain'
                            {{on
                              'click'
                              (fn this.openCard (this.accountOfLead lead))
                            }}
                          >View account →</Button>
                        {{/if}}
                      </:actions>
                    </RecordTable>
                  </div>
                </section>
              {{/if}}
              {{#if (eq this.activeTab 'territories')}}
                <section class='pane'>
                  <PageHead @title='Territories' />
                  <LayoutControl @label='Territories search' as |lc|>
                    <lc.Slot
                      @id='search'
                      @priority={{1}}
                      @forms={{this.SEARCH_FORMS}}
                      @label='Search'
                    >
                      <label class='search-label'>
                        <VisuallyHidden>Search territories</VisuallyHidden>
                        <SearchInput
                          @placeholder='Search territories'
                          @value={{this.listQuery}}
                          @onInput={{this.setListQuery}}
                        />
                      </label>
                    </lc.Slot>
                  </LayoutControl>
                  <div class='block'>
                    <h2 class='block-title'>Territories</h2>
                    <RecordTable
                      @rows={{this.matches this.territories}}
                      @columns={{this.territoryColumns}}
                      @label='Territories'
                      @onOpen={{this.openCard}}
                      @emptyMessage='No territories'
                    />
                  </div>
                </section>
              {{/if}}
              {{#if (eq this.activeTab 'proposals')}}
                <section class='pane'>
                  <PageHead @title='Proposals' />
                  <LayoutControl @label='Proposals search' as |lc|>
                    <lc.Slot
                      @id='search'
                      @priority={{1}}
                      @forms={{this.SEARCH_FORMS}}
                      @label='Search'
                    >
                      <label class='search-label'>
                        <VisuallyHidden>Search proposals</VisuallyHidden>
                        <SearchInput
                          @placeholder='Search proposals'
                          @value={{this.listQuery}}
                          @onInput={{this.setListQuery}}
                        />
                      </label>
                    </lc.Slot>
                  </LayoutControl>
                  <div class='block'>
                    <h2 class='block-title'>Proposals</h2>
                    <RecordTable
                      @rows={{this.matches this.proposals}}
                      @columns={{this.proposalColumns}}
                      @label='Proposals'
                      @onOpen={{this.openCard}}
                      @emptyMessage='No proposals'
                    />
                  </div>
                </section>
              {{/if}}
              {{#if (eq this.activeTab 'quotes')}}
                <section class='pane'>
                  <PageHead @title='Quotes' />
                  <LayoutControl @label='Quotes search' as |lc|>
                    <lc.Slot
                      @id='search'
                      @priority={{1}}
                      @forms={{this.SEARCH_FORMS}}
                      @label='Search'
                    >
                      <label class='search-label'>
                        <VisuallyHidden>Search quotes</VisuallyHidden>
                        <SearchInput
                          @placeholder='Search quotes'
                          @value={{this.listQuery}}
                          @onInput={{this.setListQuery}}
                        />
                      </label>
                    </lc.Slot>
                  </LayoutControl>
                  <div class='block'>
                    <h2 class='block-title'>Quotes</h2>
                    <RecordTable
                      @rows={{this.matches this.quotes}}
                      @columns={{this.quoteColumns}}
                      @label='Quotes'
                      @onOpen={{this.openCard}}
                      @emptyMessage='No quotes'
                    />
                  </div>
                </section>
              {{/if}}
            </main>
          </:default>
        </Sidebar>
      </div>
    {{/if}}
    <style scoped>
      .app {
        display: flex;
        block-size: 100%;
        min-block-size: 0;
        overflow: hidden;
        color: var(--foreground);
        background: var(--background);
        font-family: var(--font-sans);
        --_board-height: 26.25rem;
      }
      .shell {
        block-size: 100%;
        min-block-size: 0;
      }
      .main {
        min-block-size: 100%;
        box-sizing: border-box;
        flex: 1;
        min-width: 0;
        padding: var(--boxel-sp-lg) var(--boxel-sp-lg) var(--boxel-sp-xl);
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-sm);
      }
      .brand {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
      }
      .brand-mark {
        display: inline-flex;
        padding: var(--boxel-sp-xxs);
        background: var(--muted);
        color: var(--foreground);
      }
      .brand-name {
        display: grid;
        font-size: 0.75rem;
        font-weight: 700;
      }
      .brand-name small {
        font-size: 0.6875rem;
        font-weight: 600;
        color: var(--muted-foreground);
      }
      .status-banner {
        margin: 0;
      }
      .pane {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-sm);
      }
      .block {
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
        overflow: hidden;
      }
      .block-title {
        margin: 0;
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        font-size: 0.75rem;
        font-weight: 700;
      }
      .spacer {
        flex: 1;
      }
      .block-head {
        display: flex;
        align-items: baseline;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
      }
      h2 {
        margin: 0;
        font-size: 0.75rem;
        font-weight: 700;
      }
      .meta {
        font-size: 0.6875rem;
        color: var(--muted-foreground);
      }
      .board-wrap {
        height: var(--_board-height);
      }
      .switch-wrap {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
      }
      .switch-text {
        font-size: 0.75rem;
        font-weight: 600;
        color: var(--muted-foreground);
        white-space: nowrap;
      }
      .selection-bar {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp-xxs) var(--boxel-sp-sm);
        border-top: 1px solid var(--border);
      }
      .selection-name {
        font-weight: 600;
        font-size: 0.75rem;
        margin-right: auto;
      }
      .empty {
        margin: 0;
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        font-size: 0.75rem;
        color: var(--muted-foreground);
      }
    </style>
  </template>
}

export class RevenueOs extends CardDef {
  static displayName = 'Revenue OS';
  static prefersWideFormat = true;
  static icon = ChartAreaIcon;

  @field orgName = contains(StringField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: RevenueOs) {
      return this.orgName?.trim()?.length
        ? `Revenue OS — ${this.orgName}`
        : 'Revenue OS';
    },
  });

  static isolated = RevenueOsConsole;
}
