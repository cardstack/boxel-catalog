import { HomeTab } from './tabs/home';
import { WorkspaceTab } from './tabs/workspace';
import { RepositoryTab } from './tabs/repository';
import { ApprovalsTab } from './tabs/approvals';
import { ObligationsTab } from './tabs/obligations';
import { ComplianceTab } from './tabs/compliance';
import { ClausesTab } from './tabs/clauses';
import { SignatoriesTab } from './tabs/signatories';
import { RenewalsTab } from './tabs/renewals';
import { TemplatesTab } from './tabs/templates';
import { RequestsTab } from './tabs/requests';
import { AuditTab } from './tabs/audit';
import {
  CardDef,
  Component,
  StringField,
  contains,
  field,
  realmURL,
  type CardContext,
} from '@cardstack/base/card-api';
import { tracked } from '@glimmer/tracking';
import { action } from '@ember/object';
import { fn } from '@ember/helper';
import { on } from '@ember/modifier';
import { eq } from '@cardstack/pretui/helpers';
import {
  RealmPaths,
  identifyCard,
  join,
  type RealmResourceIdentifier,
  type getCards,
} from '@cardstack/runtime-common';
import type Owner from '@ember/owner';
import {
  Sidebar,
  SidebarGroup,
  SidebarItem,
  SidebarTrigger,
} from '@cardstack/pretui/components/sidebar';
import {
  LayoutControl,
  type LayoutControlForm,
} from '@cardstack/pretui/components/layout-control';
import { FilterChips } from '@cardstack/pretui/components/filter-chips';
import { SearchInput } from '@cardstack/pretui/components/search-input';
import { Button } from '@cardstack/pretui/components/button';
import { IconButton } from '@cardstack/pretui/components/icon-button';
import ScaleIcon from '@cardstack/boxel-icons/scale';
import HomeIcon from '@cardstack/boxel-icons/home';
import FolderIcon from '@cardstack/boxel-icons/folder';
import FileTextIcon from '@cardstack/boxel-icons/file-text';
import CircleCheckIcon from '@cardstack/boxel-icons/circle-check';
import ListChecksIcon from '@cardstack/boxel-icons/list-checks';
import ShieldCheckIcon from '@cardstack/boxel-icons/shield-check';
import BookIcon from '@cardstack/boxel-icons/book';
import PenLineIcon from '@cardstack/boxel-icons/pen-line';
import RefreshCwIcon from '@cardstack/boxel-icons/refresh-cw';
import LayoutTemplateIcon from '@cardstack/boxel-icons/layout-template';
import InboxIcon from '@cardstack/boxel-icons/inbox';
import HistoryIcon from '@cardstack/boxel-icons/history';
import BookmarkIcon from '@cardstack/boxel-icons/bookmark';
import PlusIcon from '@cardstack/boxel-icons/plus';
import DownloadIcon from '@cardstack/boxel-icons/download';
import { Contract } from '../legal/contract';
import { contractTypeLabel } from '../legal/contract-type';
import {
  CONTRACT_STATUSES,
  contractStatusLabel,
  isInForce,
} from '../legal/contract-status';
import { Obligation } from '../legal/obligation';
import { Clause } from '../legal/clause';
import { ContractClause } from '../legal/contract-clause';
import { ApprovalRule } from '../legal/approval-rule';
import { AuditEntry } from '../audit/audit-entry';
import { ContractVersion } from '../legal/contract-version';
import { ContractTemplate } from '../legal/contract-template';
import { ContractRequest } from '../legal/contract-request';
import { Signatory } from '../legal/signatory';
import { Employee } from '../hr/employee';
import { riskGradeLabel } from '../legal/contract-risk';
import { TABS, NOTICE_WINDOW_DAYS, openStep } from './contract-execution-data';
import {
  compactMoney,
  hueTone,
  isoDate,
  riskTone,
  type Tone,
} from '../shared/compact-format';
import { RichFittedCard } from '../shared/rich-fitted-card';
import { Note, StatStrip, type Stat } from './components';
import { ObligationStats } from './tabs/obligations';
import { ComplianceStats } from './tabs/compliance';

/** A cell starting with one of these is read as a formula by spreadsheets. */
const CSV_FORMULA = /^[=+\-@\t\r]/;

const TAB_ICONS: Record<string, unknown> = {
  home: HomeIcon,
  repository: FolderIcon,
  workspace: FileTextIcon,
  approvals: CircleCheckIcon,
  obligations: ListChecksIcon,
  compliance: ShieldCheckIcon,
  clauses: BookIcon,
  signatories: PenLineIcon,
  renewals: RefreshCwIcon,
  templates: LayoutTemplateIcon,
  requests: InboxIcon,
  audit: HistoryIcon,
};

// The toolbar per tab: which list it searches and what its primary action
// makes. A tab not listed has the saved-view chips only.
const TOOLBARS: Record<
  string,
  { search: string; create?: string; card?: unknown; exportCsv?: boolean }
> = {
  home: { search: 'Search contracts', create: 'New contract', card: Contract },
  repository: {
    search: 'Search contracts…',
    create: 'New contract',
    card: Contract,
  },
  clauses: {
    search: 'Search approved language…',
    create: 'New clause',
    card: Clause,
  },
  signatories: {
    search: 'Search signatories…',
    create: 'New signatory',
    card: Signatory,
  },
  templates: {
    search: 'Search templates by name or use case',
    create: 'New template',
    card: ContractTemplate,
  },
  requests: {
    search: 'Search requests by what they are for',
    create: 'New request',
    card: ContractRequest,
  },
  audit: { search: 'Search by person, action or contract', exportCsv: true },
};

// rem, richest form first
const SEARCH_FORMS: LayoutControlForm[] = [
  { name: 'field', minWidth: 14 },
  { name: 'collapsed', minWidth: 1.75 },
];
const VIEW_FORMS: LayoutControlForm[] = [
  { name: 'chips', minWidth: 34 },
  { name: 'few', minWidth: 14 },
  { name: 'menu', minWidth: 0 },
];
const ACTION_FORMS: LayoutControlForm[] = [
  { name: 'label', minWidth: 8 },
  { name: 'icon', minWidth: 1.75 },
];

export class ContractExecutionView extends Component<
  typeof ContractExecutionApp
> {
  get context() {
    return this.args.context;
  }

  get model() {
    return this.args.model;
  }

  @tracked tab = 'home';

  // ---- Workspace + ceremony (Contract Lifecycle Desk) ----------------------
  // The contract under review. Set from Legal Home (click a deadline / a
  // deviation), from the repository, or from the picker on the Workspace tab.
  @tracked workspaceContract: Contract | undefined;
  @tracked ceremonyBusy = false;
  @tracked ceremonyNote: string | undefined;
  @tracked ceremonyProblem: string | undefined;
  @tracked ceremonyFindings: string[] = [];
  @tracked signatureProvider = 'DocuSign';

  @action openInWorkspace(contract: Contract) {
    this.workspaceContract = contract;
    this.ceremonyNote = undefined;
    this.ceremonyProblem = undefined;
    this.ceremonyFindings = [];
    this.tab = 'workspace';
  }

  /** The live instance for the picked contract, so command writes show up. */
  get workspaceLive(): Contract | undefined {
    let id = this.workspaceContract?.id;
    if (!id) return undefined;
    return this.contracts.find((c) => c.id === id) ?? this.workspaceContract;
  }

  get ceremonyStatusLabel(): string {
    return this.statusLabelOf(this.workspaceLive?.status);
  }

  contractQuery: ReturnType<getCards<Contract>> | undefined;
  obligationQuery: ReturnType<getCards<Obligation>> | undefined;
  clauseUseQuery: ReturnType<getCards<ContractClause>> | undefined;
  clauseQuery: ReturnType<getCards<Clause>> | undefined;
  signatoryQuery: ReturnType<getCards<Signatory>> | undefined;
  ruleQuery: ReturnType<getCards<ApprovalRule>> | undefined;
  auditQuery: ReturnType<getCards<AuditEntry>> | undefined;
  versionQuery: ReturnType<getCards<ContractVersion>> | undefined;
  templateQuery: ReturnType<getCards<ContractTemplate>> | undefined;
  requestQuery: ReturnType<getCards<ContractRequest>> | undefined;
  employeeQuery: ReturnType<getCards<Employee>> | undefined;

  constructor(owner: Owner, args: any) {
    super(owner, args);
    let ctx = this.args.context as CardContext | undefined;
    let realms = () => this.realms;
    let live = { isLive: true } as const;
    let contractRef = identifyCard(Contract);
    let obligationRef = identifyCard(Obligation);
    let clauseUseRef = identifyCard(ContractClause);
    let clauseRef = identifyCard(Clause);
    let signatoryRef = identifyCard(Signatory);
    let ruleRef = identifyCard(ApprovalRule);
    let auditRef = identifyCard(AuditEntry);
    let versionRef = identifyCard(ContractVersion);
    let templateRef = identifyCard(ContractTemplate);
    let requestRef = identifyCard(ContractRequest);
    let employeeRef = identifyCard(Employee);
    if (ctx && contractRef) {
      this.contractQuery = ctx.getCards(
        this,
        () => ({ filter: { type: contractRef } }),
        realms,
        live,
      ) as ReturnType<getCards<Contract>>;
    }
    if (ctx && obligationRef) {
      this.obligationQuery = ctx.getCards(
        this,
        () => ({ filter: { type: obligationRef } }),
        realms,
        live,
      ) as ReturnType<getCards<Obligation>>;
    }
    // In-contract clause instances. The Clauses tab needs them to answer
    // "used in how many contracts, and deviating in how many".
    if (ctx && clauseUseRef) {
      this.clauseUseQuery = ctx.getCards(
        this,
        () => ({ filter: { type: clauseUseRef } }),
        realms,
        live,
      ) as ReturnType<getCards<ContractClause>>;
    }
    // Counted for the tab badges. The tabs themselves render through
    // CollectionPanel, which runs its own query — these exist so a tab can say
    // how much is behind it before you open it.
    if (ctx && clauseRef) {
      this.clauseQuery = ctx.getCards(
        this,
        () => ({ filter: { type: clauseRef } }),
        realms,
        live,
      ) as ReturnType<getCards<Clause>>;
    }
    if (ctx && signatoryRef) {
      this.signatoryQuery = ctx.getCards(
        this,
        () => ({ filter: { type: signatoryRef } }),
        realms,
        live,
      ) as ReturnType<getCards<Signatory>>;
    }
    for (let [ref, assign] of [
      [ruleRef, (q: any) => (this.ruleQuery = q)],
      [auditRef, (q: any) => (this.auditQuery = q)],
      [versionRef, (q: any) => (this.versionQuery = q)],
      [templateRef, (q: any) => (this.templateQuery = q)],
      [requestRef, (q: any) => (this.requestQuery = q)],
      [employeeRef, (q: any) => (this.employeeQuery = q)],
    ] as [any, (q: any) => void][]) {
      if (ctx && ref) {
        assign(
          ctx.getCards(this, () => ({ filter: { type: ref } }), realms, live),
        );
      }
    }
  }

  get realmURLValue(): URL | undefined {
    return (this.args.model as any)?.[realmURL];
  }

  get realms(): string[] | undefined {
    let url = this.realmURLValue;
    return url ? [url.href] : undefined;
  }

  get realmList(): string[] {
    return this.realms ?? [];
  }

  /**
   * Prerender gets a static shell.
   *
   * The CRUD functions only exist in the interactive host, so gating on one of
   * them keeps indexing light and avoids prerendering six live queries and a
   * board of themed fitted cards.
   */
  get isInteractive(): boolean {
    return Boolean(this.args.viewCard);
  }

  // ---- resolved instances -------------------------------------------------

  // The raw arrays may contain holes: a live query publishes its rows before
  // every linked card has resolved, and an entry that failed to resolve arrives
  // as null. `.filter(Boolean)` is the necessary guard — but on its own it makes
  // the app assert "there are 2" about a query that returned 4, with no error
  // anywhere. So the drop count is kept and surfaced (see `unresolvedNote`)
  // rather than swallowed.
  get contractsRaw(): (Contract | null)[] {
    return (this.contractQuery?.instances ?? []) as (Contract | null)[];
  }

  get obligationsRaw(): (Obligation | null)[] {
    return (this.obligationQuery?.instances ?? []) as (Obligation | null)[];
  }

  /** Every resolved contract, ignoring the rail. Counts in the rail use this. */
  get contractsAll(): Contract[] {
    return this.contractsRaw.filter(Boolean) as Contract[];
  }

  /**
   * Contracts AFTER the saved-view scope.
   *
   * Everything downstream — approvals, obligations, compliance — reads this,
   * so selecting a view in the rail changes every derived tab rather than just
   * the repository list.
   */
  get contracts(): Contract[] {
    return this.contractsAll.filter(this.activeViewTest);
  }

  /** Every resolved obligation, ignoring the saved-view scope. */
  get obligationsAll(): Obligation[] {
    return this.obligationsRaw.filter(Boolean) as Obligation[];
  }

  get obligations(): Obligation[] {
    return this.obligationsAll;
  }

  /**
   * Rows the realm returned that this app could not resolve.
   *
   * Compared against the UNSCOPED resolved lists on purpose. Comparing against
   * the scoped ones counted every contract a saved view deliberately excluded
   * as a load failure — picking "Awaiting my approval" reported "3 records
   * could not be loaded" when nothing had failed at all. Filtering is a choice;
   * failing to resolve is a fault, and the banner is only for the fault.
   */
  get unresolvedCount(): number {
    let c = this.contractsRaw.length - this.contractsAll.length;
    let o = this.obligationsRaw.length - this.obligationsAll.length;
    return c + o;
  }

  /**
   * Shown whenever the realm returned rows this app could not resolve.
   *
   * A compliance figure computed over a silently-shortened list is worse than
   * no figure: 50% of four looks identical to 50% of two, and only one of them
   * means what the reader thinks.
   */
  get unresolvedNote(): string | undefined {
    let n = this.unresolvedCount;
    if (!n) return undefined;
    return `${n} record${n === 1 ? '' : 's'} could not be loaded — counts below exclude ${n === 1 ? 'it' : 'them'}.`;
  }

  /** The masthead counts wait for both queries they read. */
  get countsLoading(): boolean {
    return (
      Boolean(this.contractQuery?.isLoading) ||
      Boolean(this.obligationQuery?.isLoading)
    );
  }

  get isLoading(): boolean {
    return (
      Boolean(this.contractQuery?.isLoading) && this.contracts.length === 0
    );
  }

  // ---- masthead counters --------------------------------------------------

  get overdueCount(): number {
    return this.obligations.filter((o) => o.status === 'overdue').length;
  }

  get awaitingCount(): number {
    return this.contracts.filter(
      (c) => c.approvalChain?.status === 'in-progress',
    ).length;
  }

  get noticeSoonCount(): number {
    return this.contracts.filter((c) => {
      let d = c.daysToNotice;
      return typeof d === 'number' && d >= 0 && d <= NOTICE_WINDOW_DAYS;
    }).length;
  }

  /**
   * Obligations met, as a percentage.
   *
   * Returns undefined rather than 100 when nothing is tracked: a score of
   * "perfect" and a score of "we are not measuring" must never render the same,
   * because only one of them is good news.
   */
  get complianceScore(): number | undefined {
    let all = this.obligations;
    if (!all.length) return undefined;
    let open = all.filter((o) => o.status !== 'closed');
    if (!open.length) return 100;
    let breached = open.filter((o) => o.status === 'overdue').length;
    return Math.round(((open.length - breached) / open.length) * 100);
  }

  get complianceLabel(): string {
    let s = this.complianceScore;
    return typeof s === 'number' ? `${s}%` : '—';
  }

  // ---- approvals ----------------------------------------------------------

  // Real Contract cards, not a row wrapper — so `Table`'s `@onRowClick` hands
  // back a card the app can open, and every derived value comes from a column
  // accessor rather than a parallel shape that can drift from the card.
  get approvalRows(): Contract[] {
    return (
      this.contracts
        .filter((c) => openStep(c))
        // Longest waiting first — a queue sorted by arrival buries the thing
        // stuck for nine days under three that arrived today.
        .sort(
          (a, b) =>
            (openStep(b)?.waitingDays ?? 0) - (openStep(a)?.waitingDays ?? 0),
        )
    );
  }

  /**
   * Saved views are a CONTRACT SCOPE, not a repository-only filter.
   *
   * A view stores a predicate, never a frozen id list, so a contract that
   * becomes high-risk tomorrow appears in "High & critical risk" without
   * anyone re-saving anything.
   *
   * The scope then flows into every tab DERIVED from contracts: approvals,
   * obligations and compliance all recompute against it. Anything else would
   * make the rail a control that changes one screen and silently lies on the
   * other three.
   */
  get viewDefs(): { name: string; test: (c: any) => boolean }[] {
    return [
      { name: 'All contracts', test: () => true },
      { name: 'Awaiting my approval', test: (c) => Boolean(openStep(c)) },
      {
        name: 'Notice inside 90 days',
        test: (c) =>
          typeof c.daysToNotice === 'number' &&
          c.daysToNotice <= NOTICE_WINDOW_DAYS,
      },
      {
        name: 'High & critical risk',
        test: (c) => c.riskGrade === 'high' || c.riskGrade === 'critical',
      },
    ];
  }

  get savedViewOptions(): { value: string; label: string; count: number }[] {
    return (
      this.viewDefs
        .map((v) => ({
          value: v.name,
          label: v.name,
          count: this.contractsAll.filter(v.test).length,
        }))
        // A view with nothing behind it is hidden rather than shown as a zero.
        // "All contracts" always stays: it is the way back out of a scope.
        .filter((o) => o.count > 0 || o.value === 'All contracts')
    );
  }

  @tracked activeViewName?: string;

  get currentViewName(): string {
    return this.activeViewName ?? this.savedViewOptions[0]?.value ?? '';
  }

  /** The predicate behind whatever the rail currently has selected. */
  get activeViewTest(): (c: any) => boolean {
    return (
      this.viewDefs.find((v) => v.name === this.currentViewName)?.test ??
      (() => true)
    );
  }

  setViewByName = (name: string) => {
    this.activeViewName = name;
  };

  /** A tab with nothing behind it shows no count rather than a zero. */
  tabCount = (key: string): number => {
    switch (key) {
      case 'repository':
        return this.contracts.length;
      case 'approvals':
        return this.approvalRows.length;
      case 'obligations':
        return this.obligations.length;
      case 'clauses':
        return (this.clauseQuery?.instances ?? []).filter(Boolean).length;
      case 'signatories':
        return (this.signatoryQuery?.instances ?? []).filter(Boolean).length;
      case 'renewals':
        return this.renewalRows.length;
      case 'templates':
        return this.templates.length;
      case 'requests':
        return this.requests.length;
      case 'audit':
        return this.audits.length;
      default:
        return 0;
    }
  };

  /** The contract at the head of the queue — the one the rail is drawn for. */
  /**
   * Which contract the decision pane is showing.
   *
   * Held as an ID rather than the instance: the live query hands back new
   * objects on every reindex, so a stored instance would silently stop
   * matching anything in the list the moment the realm updated.
   */
  @tracked selectedApprovalId: string | undefined;

  @tracked assignBusy = false;
  @tracked assignProblem: string | undefined;

  /**
   * The approval rules in the realm. The rule that fired is rendered from
   * them, so the reason shown is the rule's own threshold and value.
   */
  get rules(): ApprovalRule[] {
    return ((this.ruleQuery?.instances ?? []) as any[]).filter(
      Boolean,
    ) as ApprovalRule[];
  }

  get audits(): AuditEntry[] {
    return ((this.auditQuery?.instances ?? []) as any[]).filter(
      Boolean,
    ) as AuditEntry[];
  }

  get requests(): ContractRequest[] {
    return ((this.requestQuery?.instances ?? []) as any[]).filter(
      Boolean,
    ) as ContractRequest[];
  }

  get templates(): ContractTemplate[] {
    return ((this.templateQuery?.instances ?? []) as any[]).filter(
      Boolean,
    ) as ContractTemplate[];
  }

  /** No rules configured at all is a setup gap, not a clean bill of health. */
  get rulesUnconfigured(): boolean {
    return this.rules.length === 0;
  }

  /** Audit entries for one contract, newest first. */
  auditFor = (contractId?: string): AuditEntry[] =>
    contractId
      ? this.audits
          .filter((a: any) => a?.subject?.id === contractId)
          .sort(
            (a: any, b: any) =>
              new Date(b?.occurredAt ?? 0).getTime() -
              new Date(a?.occurredAt ?? 0).getTime(),
          )
      : [];

  get renewalRows(): Contract[] {
    return this.contracts
      .filter((c) => {
        let d = c.daysToNotice;
        return typeof d === 'number' && d <= NOTICE_WINDOW_DAYS;
      })
      .sort((a, b) => (a.daysToNotice ?? 0) - (b.daysToNotice ?? 0));
  }

  /**
   * Who is recording the decision.
   *
   * PLATFORM GAP, handled rather than ignored. A card has no reachable identity
   * of the signed-in user — `CardContext` exposes the store, queries and
   * components, and nothing else — so the app cannot stamp the actor itself.
   *
   * An audit trail exists to answer "who decided this", so a decision with no
   * named actor is refused rather than recorded as "Someone".
   *
   * So the actor is DECLARED, and the UI says it is declared. Weaker than a
   * system identity — a person could name a colleague — and that weakness is
   * stated next to the control rather than hidden behind it.
   */
  @tracked actingAs: Employee | undefined;

  /** Free-text conditions typed into the tray before "Approve with conditions". */
  @tracked decisionNote = '';
  @tracked decisionBusy = false;
  @tracked decisionProblem: string | undefined;
  @tracked lastDecision: string | undefined;

  @tracked submitBusy = false;
  @tracked submitProblem: string | undefined;

  @tracked submitNote: string | undefined;

  // ---- actions ------------------------------------------------------------

  @action setTab(key: string) {
    this.tab = key;
  }

  @action openCard(card: CardDef) {
    this.args.viewCard?.(card, 'isolated');
  }

  statusLabelOf = (value?: string | null): string => contractStatusLabel(value);

  statusToneOf = (value?: string | null): Tone =>
    hueTone(CONTRACT_STATUSES.find((o) => o.value === value)?.hue);

  typeLabelOf = (value?: string | null): string => contractTypeLabel(value);

  riskLabelOf = (value?: string | null): string => riskGradeLabel(value);

  riskToneOf = (grade?: string | null): Tone => riskTone(grade);

  /** Deviating clauses on a contract — an input to the rules engine. */
  deviationCountFor = (contractId?: string): number =>
    contractId
      ? this.clauseUses.filter(
          (u: any) => u?.contract?.id === contractId && u?.isDeviation,
        ).length
      : 0;

  /**
   * Where new records belong, derived from where this app card itself lives.
   *
   * The app sits at `<realm>/<dir>/ContractExecutionApp/<id>.json`, so
   * `<dir>` is the mirror directory every sibling record must share.
   */
  localDirFor = (folder: string): string | undefined => {
    let id = (this.args.model as any)?.id as string | undefined;
    let url = this.realmURLValue;
    if (!id || !url) return undefined;
    try {
      let segments = new RealmPaths(url)
        .local(id as RealmResourceIdentifier)
        .split('/');
      // drop ['ContractExecutionApp', '<id>'] to leave the mirror prefix
      return join(...segments.slice(0, -2), folder);
    } catch {
      return undefined;
    }
  };

  /** The Site tools theme the app is linked to, for records it creates. */
  get themeRelationship() {
    let id = (this.args.model as any)?.cardInfo?.theme?.id as
      | string
      | undefined;
    return id ? { 'cardInfo.theme': { links: { self: id } } } : {};
  }

  get clauseUses(): ContractClause[] {
    return ((this.clauseUseQuery?.instances ?? []) as any[]).filter(
      Boolean,
    ) as ContractClause[];
  }

  // ---- shell: nav, toolbar, KPIs -------------------------------------------

  get navItems() {
    return TABS.map((t) => {
      let n = this.tabCount(t.key);
      let badge: string | undefined =
        t.key === 'obligations'
          ? this.overdueCount
            ? `${this.overdueCount} overdue`
            : undefined
          : n
            ? String(n)
            : undefined;
      return { ...t, icon: TAB_ICONS[t.key], badge };
    });
  }

  get tabLabel(): string {
    return TABS.find((t) => t.key === this.tab)?.label ?? '';
  }

  get pageTitle(): string {
    return this.tab === 'home' ? 'Legal Home' : this.tabLabel;
  }

  get toolbar() {
    return TOOLBARS[this.tab];
  }

  get todayLabel(): string {
    return new Date().toLocaleDateString('en-GB', {
      day: 'numeric',
      month: 'short',
      year: 'numeric',
    });
  }

  @tracked query = '';

  setQuery = (value: string) => {
    this.query = value ?? '';
  };

  /** The toolbar search, applied by every list tab to its own rows. */
  search = <T,>(rows: T[], text: (row: T) => unknown[]): T[] => {
    let q = this.query.trim().toLowerCase();
    if (!q) return rows;
    return rows.filter((r) =>
      text(r).some((v) =>
        String(v ?? '')
          .toLowerCase()
          .includes(q),
      ),
    );
  };

  @tracked createProblem: string | undefined;

  @action async createRecord() {
    let card = this.toolbar?.card;
    let ref = card ? identifyCard(card as typeof CardDef) : undefined;
    let realm = this.realmURLValue;
    if (!ref || !realm || !this.args.createCard) {
      this.createProblem =
        "You can't create records here. Open this app in a realm you can edit.";
      return;
    }
    this.createProblem = undefined;
    try {
      await this.args.createCard(ref, realm, {
        realmURL: realm,
        localDir: this.localDirFor('name' in ref ? ref.name : 'Contract'),
        doc: {
          data: {
            meta: { adoptsFrom: ref },
            relationships: this.themeRelationship,
          },
        },
      } as any);
    } catch (error: any) {
      this.createProblem = `Couldn't create the record${
        error?.message ? ` (${error.message})` : ''
      }. Check your connection and try again.`;
    }
  }

  /**
   * Audit log as CSV, built from the rows on screen.
   *
   * A cell that starts with = + - or @ is read as a formula by spreadsheets,
   * so it is prefixed with a quote to stay text.
   */
  @action exportAuditCsv() {
    let esc = (v: unknown) => {
      let text = String(v ?? '');
      if (CSV_FORMULA.test(text)) text = `'${text}`;
      return `"${text.replace(/"/g, '""')}"`;
    };
    let lines = [
      ['When', 'Who', 'Action', 'Subject', 'Conditions'].map(esc).join(','),
      ...this.audits.map((a: any) =>
        [
          isoDate(a?.occurredAt),
          a?.doneBy?.cardTitle,
          a?.action,
          a?.subjectTitle,
          a?.conditions,
        ]
          .map(esc)
          .join(','),
      ),
    ];
    let url = URL.createObjectURL(
      new Blob([lines.join('\n')], { type: 'text/csv' }),
    );
    let link = document.createElement('a');
    link.href = url;
    link.download = 'audit-trail.csv';
    link.click();
    URL.revokeObjectURL(url);
  }

  @action pickTab(key: string, bar?: { mobile: boolean; toggle: () => void }) {
    this.tab = key;
    this.query = '';
    if (bar?.mobile) bar.toggle();
  }

  pickView = (name: string, bar?: { mobile: boolean; toggle: () => void }) => {
    this.activeViewName = name;
    if (bar?.mobile) bar.toggle();
  };

  /** Value in force, per currency: the largest currency leads. */
  get valueInForce(): { lead: string; sub: string } {
    let inForce = this.contracts.filter(
      (c: any) => isInForce(c.status) && typeof c.value?.amount === 'number',
    );
    let byCode = new Map<string, number>();
    for (let c of inForce as any[]) {
      let code = c.value.currency?.code ?? '';
      byCode.set(code, (byCode.get(code) ?? 0) + c.value.amount);
    }
    let sorted = [...byCode].sort((a, b) => b[1] - a[1]);
    let lead = sorted[0];
    let others = sorted.length - 1;
    return {
      lead: lead ? compactMoney(lead[1], lead[0]) : '—',
      sub: `${inForce.length} agreements${
        others > 0
          ? ` · ${others} other currenc${others === 1 ? 'y' : 'ies'}`
          : ''
      }`,
    };
  }

  get longestWait(): number {
    return Math.max(
      0,
      ...this.approvalRows.map((c) => openStep(c)?.waitingDays ?? 0),
    );
  }

  get nearestNotice(): number | undefined {
    // a passed notice date is not "nearest"; it is already missed
    return (
      this.renewalRows.find((c) => (c.daysToNotice ?? -1) >= 0)?.daysToNotice ??
      undefined
    );
  }

  get openDeviations(): ContractClause[] {
    return this.clauseUses.filter(
      (u: any) => u?.isDeviation && u?.deviationSeverity !== 'approved',
    );
  }

  get worstDeviation(): string | undefined {
    let order = ['critical', 'high', 'major', 'medium', 'minor', 'low'];
    let levels = this.openDeviations.map(
      (u: any) => u?.riskLevel ?? u?.deviationSeverity,
    );
    return order.find((o) => levels.includes(o));
  }

  get kpis(): Stat[] {
    let v = this.valueInForce;
    let loading = this.countsLoading;
    let n = (x: number | string) => (loading ? '—' : x);
    return [
      { label: 'Value in force', value: n(v.lead), hint: v.sub },
      {
        label: 'Overdue obligations',
        value: n(this.overdueCount),
        hint: `of ${this.obligations.length} tracked`,
        tone: this.overdueCount ? 'danger' : 'neutral',
      },
      {
        label: 'In approval',
        value: n(this.awaitingCount),
        hint: this.awaitingCount
          ? `longest waiting ${this.longestWait} days`
          : 'nothing waiting',
      },
      {
        label: 'Notice inside 90 days',
        value: n(this.noticeSoonCount),
        hint:
          this.nearestNotice !== undefined
            ? `nearest in ${this.nearestNotice} days`
            : 'none due',
        tone: this.noticeSoonCount ? 'warning' : 'neutral',
      },
      {
        label: 'Open deviations',
        value: n(this.openDeviations.length),
        hint: this.worstDeviation
          ? `worst is ${this.worstDeviation}`
          : 'all on playbook',
      },
      {
        label: 'Compliance',
        value: n(this.complianceLabel),
        hint: 'open obligations met',
      },
    ];
  }

  get viewMenuItems() {
    return this.savedViewOptions.map((o) => ({
      label: `${o.label} ${o.count}`,
      value: o.value,
      group: 'saved-views',
      checked: o.value === this.currentViewName,
      onSelect: () => this.pickView(o.value),
    }));
  }

  <template>
    <section class='cx'>
      <Sidebar
        class='cx-shell'
        @label='Contract execution sections'
        @collapsible='rail'
        @railBreakpoint={{1100}}
        @mobileBreakpoint={{720}}
        @bordered={{true}}
        @scroll='content'
        @resizable={{true}}
      >
        <:header as |bar|>
          <div class='cx-brand'>
            <span class='cx-mark' aria-hidden='true'>CE</span>
            {{#unless bar.collapsed}}
              <span class='cx-brand-text'>
                <strong>Contract Execution</strong>
                <span class='cx-cap'>Legal desk</span>
              </span>
            {{/unless}}
          </div>
        </:header>
        <:nav as |bar|>
          <SidebarGroup @label='Desk' @hideLabel={{bar.collapsed}}>
            {{#each this.navItems as |item|}}
              <SidebarItem
                @label={{item.label}}
                @icon={{item.icon}}
                @badge={{unless bar.collapsed item.badge}}
                @active={{eq item.key this.tab}}
                @collapsed={{bar.collapsed}}
                @onClick={{fn this.pickTab item.key bar}}
              />
            {{/each}}
          </SidebarGroup>
          <SidebarGroup @label='Saved views' @hideLabel={{bar.collapsed}}>
            {{#each this.savedViewOptions as |sv|}}
              <SidebarItem
                @label={{sv.label}}
                @icon={{BookmarkIcon}}
                @badge={{unless bar.collapsed sv.count}}
                @active={{eq sv.value this.currentViewName}}
                @collapsed={{bar.collapsed}}
                @onClick={{fn this.pickView sv.value bar}}
              />
            {{/each}}
          </SidebarGroup>
        </:nav>
        <:default as |bar|>
          {{#if bar.mobile}}
            <header class='cx-topbar'>
              <SidebarTrigger
                @open={{bar.open}}
                @onToggle={{bar.toggle}}
                @controls={{bar.controls}}
                @label='contract execution sections'
              />
              <strong>{{this.pageTitle}}</strong>
            </header>
          {{/if}}
          <main class='cx-page'>
            <header class='cx-head'>
              <p class='cx-cap'>Contract execution · Desk</p>
              <h1 class='cx-title'>{{this.pageTitle}}</h1>
              <p class='cx-sub'>Contract lifecycle management ·
                {{this.currentViewName}}
                · today
                {{this.todayLabel}}</p>
            </header>

            {{#if this.isInteractive}}
              {{#if this.unresolvedNote}}
                <Note @tone='warning' @lead={{this.unresolvedNote}} />
              {{/if}}
              <StatStrip @stats={{this.kpis}} @label='Desk summary' />

              {{#if (eq this.tab 'obligations')}}
                <ObligationStats @app={{this}} />
              {{else if (eq this.tab 'compliance')}}
                <ComplianceStats @app={{this}} />
              {{/if}}

              <LayoutControl
                class='cx-toolbar'
                @label='{{this.tabLabel}} toolbar'
                @controlHeight='1.625rem'
                as |lc|
              >
                {{#if this.toolbar}}
                  <lc.Slot
                    @id='search'
                    @label='Search'
                    @priority={{2}}
                    @forms={{SEARCH_FORMS}}
                    as |form|
                  >
                    <SearchInput
                      @value={{this.query}}
                      @placeholder={{this.toolbar.search}}
                      @onInput={{this.setQuery}}
                      @display={{if (eq form 'collapsed') 'collapsed' 'field'}}
                    />
                  </lc.Slot>
                {{/if}}
                <lc.Slot
                  @id='views'
                  @label='Saved views'
                  @priority={{1}}
                  @forms={{VIEW_FORMS}}
                  @menuItems={{this.viewMenuItems}}
                  as |form|
                >
                  <FilterChips
                    @label='Saved views'
                    @options={{this.savedViewOptions}}
                    @value={{this.currentViewName}}
                    @onValueChange={{this.pickView}}
                    @display={{if (eq form 'few') 'few' 'all'}}
                  />
                </lc.Slot>
                {{#if this.toolbar.create}}
                  <lc.Slot
                    @id='create'
                    @label={{this.toolbar.create}}
                    @pinned={{true}}
                    @priority={{0}}
                    @forms={{ACTION_FORMS}}
                    as |form|
                  >
                    {{#if (eq form 'icon')}}
                      <IconButton
                        @label={{this.toolbar.create}}
                        @icon={{PlusIcon}}
                        @tone='primary'
                        @appearance='accent'
                        {{on 'click' this.createRecord}}
                      />
                    {{else}}
                      <Button
                        @size='xs'
                        @tone='primary'
                        @appearance='accent'
                        @icon={{PlusIcon}}
                        {{on 'click' this.createRecord}}
                      >{{this.toolbar.create}}</Button>
                    {{/if}}
                  </lc.Slot>
                {{else if this.toolbar.exportCsv}}
                  <lc.Slot
                    @id='export'
                    @label='Export CSV'
                    @pinned={{true}}
                    @priority={{0}}
                    @forms={{ACTION_FORMS}}
                    as |form|
                  >
                    {{#if (eq form 'icon')}}
                      <IconButton
                        @label='Export CSV'
                        @icon={{DownloadIcon}}
                        @appearance='outlined'
                        {{on 'click' this.exportAuditCsv}}
                      />
                    {{else}}
                      <Button
                        @size='xs'
                        @appearance='outlined'
                        @icon={{DownloadIcon}}
                        {{on 'click' this.exportAuditCsv}}
                      >Export CSV</Button>
                    {{/if}}
                  </lc.Slot>
                {{/if}}
              </LayoutControl>
              {{#if this.createProblem}}
                <Note @tone='danger' @lead={{this.createProblem}} />
              {{/if}}

              {{#if (eq this.tab 'home')}}
                <HomeTab @app={{this}} />
              {{else if (eq this.tab 'workspace')}}
                <WorkspaceTab @app={{this}} />
              {{else if (eq this.tab 'repository')}}
                <RepositoryTab @app={{this}} />
              {{else if (eq this.tab 'approvals')}}
                <ApprovalsTab @app={{this}} />
              {{else if (eq this.tab 'obligations')}}
                <ObligationsTab @app={{this}} />
              {{else if (eq this.tab 'compliance')}}
                <ComplianceTab @app={{this}} />
              {{else if (eq this.tab 'clauses')}}
                <ClausesTab @app={{this}} />
              {{else if (eq this.tab 'signatories')}}
                <SignatoriesTab @app={{this}} />
              {{else if (eq this.tab 'renewals')}}
                <RenewalsTab @app={{this}} />
              {{else if (eq this.tab 'templates')}}
                <TemplatesTab @app={{this}} />
              {{else if (eq this.tab 'requests')}}
                <RequestsTab @app={{this}} />
              {{else if (eq this.tab 'audit')}}
                <AuditTab @app={{this}} />
              {{/if}}
            {{else}}
              <p class='cx-sub'>Repository, approvals, obligations and renewals
                over live records. Open this card in the app to work with them.</p>
            {{/if}}
          </main>
        </:default>
      </Sidebar>
    </section>

    <style scoped>
      .cx {
        container: cx-app / inline-size;
        position: relative;
        block-size: 100%;
        overflow: hidden;
        background: var(--background);
        color: var(--foreground);
        font-family: var(--font-sans);
        font-size: var(--boxel-font-size-xs);
        line-height: 1.3;
      }
      .cx-shell {
        block-size: 100%;
        min-block-size: 0;
        --pretui-sidebar-width: 13.5rem;
        --pretui-sidebar-rail-width: 3.5rem;
        --pretui-sidebar-bg: var(--card);
        --pretui-selected: var(--primary);
        --pretui-primary-ink: var(--primary-foreground);
      }
      .cx-brand {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp-2xs) var(--boxel-sp-xs) var(--boxel-sp-sm);
      }
      .cx-mark {
        display: grid;
        place-items: center;
        flex: none;
        inline-size: 1.75rem;
        block-size: 1.75rem;
        border-radius: var(--boxel-border-radius-sm);
        background: var(--muted);
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-2xs);
        font-weight: 700;
        line-height: 1;
      }
      .cx-brand-text {
        display: grid;
        min-inline-size: 0;
      }
      .cx-cap {
        margin: 0;
        font-family: var(--font-mono);
        font-size: var(--boxel-eyebrow-font-size);
        font-weight: var(--boxel-eyebrow-font-weight);
        line-height: var(--boxel-eyebrow-line-height);
        letter-spacing: var(--boxel-eyebrow-letter-spacing);
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .cx-topbar {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp-2xs) var(--boxel-sp);
        border-bottom: 1px solid var(--border);
        background: var(--card);
      }
      .cx-page {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp-lg) var(--boxel-sp-lg) var(--boxel-sp-xl);
        min-inline-size: 0;
      }
      .cx-head {
        display: grid;
        gap: var(--boxel-sp-4xs);
      }
      .cx-title {
        font-family: var(--boxel-heading-font-family);
        font-size: var(--boxel-font-size-2xl);
        line-height: 1;
        text-transform: uppercase;
      }
      .cx-sub {
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
      }
      .cx-toolbar {
        min-inline-size: 0;
      }
      @container cx-app (width < 45rem) {
        .cx-page {
          padding: var(--boxel-sp) var(--boxel-sp);
        }
      }
    </style>
  </template>
}

export class ContractExecutionApp extends CardDef {
  static displayName = 'Contract Execution';
  static icon = ScaleIcon;
  static prefersWideFormat = true;

  @field practiceName = contains(StringField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: ContractExecutionApp) {
      return this.practiceName?.trim()?.length
        ? this.practiceName
        : 'Contract Execution';
    },
  });

  static isolated = ContractExecutionView;

  static embedded = class Embedded extends Component<
    typeof ContractExecutionApp
  > {
    <template>
      <div class='cx-emb'>
        <ScaleIcon
          class='cx-emb-icon'
          width='16'
          height='16'
          role='presentation'
        />
        <span class='cx-emb-id'>
          <strong>{{@model.cardTitle}}</strong>
          <span class='cx-emb-sub'>Repository · approvals · obligations ·
            renewals</span>
        </span>
      </div>
      <style scoped>
        .cx-emb {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-xs);
        }
        .cx-emb-icon {
          flex: none;
          color: var(--muted-foreground);
        }
        .cx-emb-id {
          display: grid;
          min-inline-size: 0;
        }
        .cx-emb-sub {
          color: var(--muted-foreground);
          font-size: var(--boxel-font-size-2xs);
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof ContractExecutionApp> {
    <template>
      <RichFittedCard>
        <:avatar><ScaleIcon class='app-mark' aria-hidden='true' /></:avatar>
        <:title>{{@model.cardTitle}}</:title>
        <:subtitle>Contract lifecycle desk</:subtitle>
        <:fact>Repository · approvals · obligations · renewals</:fact>
      </RichFittedCard>
      <style scoped>
        .app-mark {
          inline-size: var(--pretui-avatar-size);
          block-size: var(--pretui-avatar-size);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof ContractExecutionApp> {
    <template>
      <span>{{@model.cardTitle}}</span>
    </template>
  };
}

export default ContractExecutionApp;
