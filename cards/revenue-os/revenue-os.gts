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
import { Tabs } from '@cardstack/pretui/components/tabs';
import {
  identifyCard,
  realmURL,
  type getCards,
} from '@cardstack/runtime-common';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import PatchCardInstanceCommand from '@cardstack/boxel-host/commands/patch-card-instance';
import ChartAreaIcon from '@cardstack/boxel-icons/chart-area';
import { Board, type BoardColumn } from '../../components/board';
import { type ImportRowResult } from '../../components/import';
import { toDate } from '../../fields/effective-period/effective-period-field';
import { AccountsPane } from './components/accounts-pane';
import { DashboardPane } from './components/dashboard-pane';
import { InvoicesPane } from './components/invoices-pane';
import { CardList } from './components/card-list';
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
import DuplicateCommand from '../../commands/duplicate';
import ClassifyCommand from '../../commands/classify';
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

  private get realms(): string[] | undefined {
    let url = (this.args.model as any)?.[realmURL];
    return url ? [url.href] : undefined;
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
        label: at.toLocaleDateString('en-US', { month: 'short' }),
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

  <template>
    {{#unless this.isInteractive}}
      <div class='app'>
        <header class='app-head'>
          <div class='brand'>
            <span class='brand-mark'><ChartAreaIcon
                width='22'
                height='22'
              /></span>
            <h1>{{@model.cardTitle}}</h1>
          </div>
        </header>
        <p class='empty'>Open in Interact mode for the pipeline, dashboard, and
          collections workspace.</p>
      </div>
    {{/unless}}
    {{#if this.isInteractive}}
      <div class='app'>
        <header class='app-head'>
          <div class='brand'>
            <span class='brand-mark'><ChartAreaIcon
                width='22'
                height='22'
              /></span>
            <h1>{{@model.cardTitle}}</h1>
          </div>
          <Tabs
            class='tabs'
            @items={{TABS}}
            @value={{this.activeTab}}
            @onValueChange={{this.setTab}}
          />
        </header>

        {{#if this.statusMessage}}
          <Alert class='status-banner' @tone='info' role='status'>
            {{this.statusMessage}}
          </Alert>
        {{/if}}

        {{#if (eq this.activeTab 'pipeline')}}
          <section class='pane'>
            <div class='board-toolbar'>
              <h2>Pipeline</h2>
              <div class='toolbar-controls'>
                <label class='switch-wrap'>
                  <Switch
                    @checked={{this.showAllStages}}
                    @onCheckedChange={{this.toggleAllStages}}
                  />
                  <span class='switch-text'>All stages</span>
                </label>
                {{#if this.owners.length}}
                  <div class='owner-select'>
                    <Select
                      @options={{this.ownerOptions}}
                      @value={{this.ownerFilter}}
                      @onValueChange={{this.setOwnerFilter}}
                      @label='Owner'
                    />
                  </div>
                {{/if}}
                <div class='owner-select'>
                  <Select
                    @options={{this.closeWindowOptions}}
                    @value={{this.closeWindow}}
                    @onValueChange={{this.setCloseWindow}}
                    @label='Close date'
                  />
                </div>
                <div class='owner-select'>
                  <Select
                    @options={{this.boardSortOptions}}
                    @value={{this.boardSort}}
                    @onValueChange={{this.setBoardSort}}
                    @label='Sort'
                  />
                </div>
              </div>
              <div class='board-stats'>
                <span class='stat'><span
                    class='stat-value'
                  >{{this.stageTotals.count}}</span>
                  open</span>
                <span class='stat'><span
                    class='stat-value'
                  >{{this.stageTotals.total}}</span>
                  total</span>
                <span class='stat'><span
                    class='stat-value'
                  >{{this.stageTotals.weighted}}</span>
                  weighted</span>
              </div>
            </div>
            {{#if this.selectedDeal}}
              <div class='selection-bar'>
                <span
                  class='selection-name'
                >{{this.selectedDeal.cardTitle}}</span>
                <Button
                  @appearance='outlined'
                  @size='sm'
                  {{on 'click' (fn this.openCard this.selectedDeal)}}
                >Open</Button>
                <Button
                  @appearance='outlined'
                  @size='sm'
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
            <div class='pane-head'>
              <h2>Leads</h2>
              <Button
                @appearance='outlined'
                @size='sm'
                {{on 'click' this.newLead}}
              >New lead</Button>
            </div>
            <CardList
              @items={{this.leadCards}}
              @label='Leads'
              @cardComponent={{this.cardComponent}}
              @loading={{this.isLoading}}
              @onOpen={{this.openCard}}
              @emptyMessage='No leads'
            >
              <:actions as |lead|>
                {{#if (this.canConvertCard lead)}}
                  <Button
                    @appearance='plain'
                    @size='sm'
                    @disabled={{this.busy}}
                    {{on 'click' (fn this.scoreLeadCard lead)}}
                  >Score</Button>
                  <Button
                    @appearance='outlined'
                    @size='sm'
                    @disabled={{this.busy}}
                    {{on 'click' (fn this.convertLeadCard lead)}}
                  >Convert</Button>
                {{else if (this.accountOfLead lead)}}
                  <Button
                    @appearance='plain'
                    @size='sm'
                    {{on 'click' (fn this.openCard (this.accountOfLead lead))}}
                  >View account →</Button>
                {{/if}}
              </:actions>
            </CardList>
          </section>
        {{/if}}
        {{#if (eq this.activeTab 'territories')}}
          <section class='pane'>
            <div class='pane-head'>
              <h2>Territories</h2>
            </div>
            <CardList
              @items={{this.territories}}
              @label='Territories'
              @cardComponent={{this.cardComponent}}
              @loading={{this.isLoading}}
              @onOpen={{this.openCard}}
              @emptyMessage='No territories'
            />
          </section>
        {{/if}}

        {{#if (eq this.activeTab 'proposals')}}
          <section class='pane'>
            <div class='pane-head'>
              <h2>Proposals</h2>
            </div>
            <CardList
              @items={{this.proposals}}
              @label='Proposals'
              @cardComponent={{this.cardComponent}}
              @loading={{this.isLoading}}
              @onOpen={{this.openCard}}
              @emptyMessage='No proposals'
            />
          </section>
        {{/if}}

        {{#if (eq this.activeTab 'quotes')}}
          <section class='pane'>
            <div class='pane-head'>
              <h2>Quotes</h2>
            </div>
            <CardList
              @items={{this.quotes}}
              @label='Quotes'
              @cardComponent={{this.cardComponent}}
              @loading={{this.isLoading}}
              @onOpen={{this.openCard}}
              @emptyMessage='No quotes'
            />
          </section>
        {{/if}}
      </div>
    {{/if}}
    <style scoped>
      .app {
        min-height: 100%;
        padding: 1.25rem 1.5rem 2rem;
        box-sizing: border-box;
        display: flex;
        flex-direction: column;
        gap: 1rem;
        color: var(--foreground);
        background: var(--background);
        --_board-height: 26.25rem;
      }
      .app-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 1rem;
        flex-wrap: wrap;
        border-bottom: 0.25rem double var(--foreground);
        padding-bottom: 0.875rem;
      }
      .brand {
        display: flex;
        align-items: center;
        gap: 0.625rem;
      }
      .brand-mark {
        display: inline-flex;
        padding: var(--boxel-sp-xs);
        border-radius: var(--boxel-border-radius-lg);
        background: var(--primary);
        color: var(--primary-foreground);
      }
      h1 {
        margin: 0;
        font-size: 1.375rem;
        font-family: var(--font-sans);
      }
      .tabs {
        display: flex;
        gap: 0.25rem;
        flex-wrap: wrap;
      }
      .status-banner {
        margin: 0;
      }
      .pane {
        display: flex;
        flex-direction: column;
        gap: 1rem;
      }
      .pane-head {
        display: flex;
        align-items: baseline;
        justify-content: space-between;
        gap: 1rem;
        flex-wrap: wrap;
      }
      h2 {
        margin: 0;
        font-size: 1.0625rem;
        font-family: var(--font-sans);
      }
      .board-wrap {
        height: var(--_board-height);
      }
      .board-toolbar {
        display: flex;
        align-items: center;
        gap: 1.25rem;
        flex-wrap: wrap;
      }
      .toolbar-controls {
        display: flex;
        align-items: center;
        gap: 1rem;
      }
      .switch-wrap {
        display: flex;
        align-items: center;
        gap: 0.4375rem;
      }
      .switch-text {
        font-size: 0.8125rem;
        font-weight: 500;
        color: var(--muted-foreground);
        white-space: nowrap;
      }
      .board-stats {
        margin-left: auto;
        display: flex;
        align-items: baseline;
        gap: 1.25rem;
      }
      .stat {
        font-size: 0.75rem;
        color: var(--muted-foreground);
        white-space: nowrap;
      }
      .stat-value {
        font-size: 0.9375rem;
        font-weight: 700;
        color: var(--foreground);
        font-variant-numeric: tabular-nums;
        margin-right: 0.25rem;
      }
      .selection-bar {
        display: flex;
        align-items: center;
        gap: 0.5rem;
        padding: 0.5rem 0.75rem;
        border: 1px solid var(--border);
        border-radius: var(--boxel-border-radius);
        background: var(--card);
      }
      .selection-name {
        font-weight: 600;
        font-size: 0.8125rem;
        margin-right: auto;
      }
      h3 {
        margin: 0 0 0.75rem;
        font-size: 0.6875rem;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.1em;
        color: var(--muted-foreground);
      }
      .empty {
        margin: 0;
        font-size: 0.8125rem;
        color: var(--muted-foreground);
      }
      .owner-select {
        min-width: 11rem;
      }
    </style>
  </template>
}

export class RevenueOs extends CardDef {
  static displayName = 'Revenue OS';
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
