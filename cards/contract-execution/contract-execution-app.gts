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
import { FilterChips } from '@cardstack/pretui/components/filter-chips';
import { Tabs } from '@cardstack/pretui/components/tabs';
import { FittedCard } from '@cardstack/boxel-ui/components';
import { eq } from '@cardstack/boxel-ui/helpers';
import { identifyCard, type getCards } from '@cardstack/runtime-common';
import type Owner from '@ember/owner';
import ScaleIcon from '@cardstack/boxel-icons/scale';
import TriangleAlertIcon from '@cardstack/boxel-icons/triangle-alert';
import { Contract } from '../legal/contract';
import { contractTypeLabel } from '../legal/contract-type';
import {
  CONTRACT_STATUSES,
  contractStatusLabel,
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
import { StatePill, type Hue } from '../../components/state-pill';
import {
  TABS,
  NOTICE_WINDOW_DAYS,
  scaleBands,
  openStep,
} from './contract-execution-data';
/**
 * Contract Execution — the app that composes the contract blocks.
 *
 * WHAT THIS CARD DOES NOT DO, on purpose:
 *
 *   - It holds no `linksToMany` collections. Every pane is a live realm query,
 *     so a contract created by a command appears without a reload and two
 *     panes can never disagree about what exists.
 *   - It renders no table, no search box and no create button of its own.
 *     Repository, Clauses and Signatories are all `CollectionPanel`, which
 *     already carries query + search + grid/table switch + create. The two
 *     panes that are NOT a plain collection — the approval queue and the
 *     obligation tracker — mount `Table` (table.gts) directly, because they
 *     group and sort by something a generic panel has no opinion about.
 *   - It never styles a block's internals. Where a block needs to look
 *     different here, that is an argument on the block, not CSS reaching into
 *     it from this file.
 */

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

  get realms(): string[] | undefined {
    let url = (this.args.model as any)?.[realmURL];
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

  /**
   * The rail belongs to the Repository only.
   *
   * Saved views belong to one object: "All contracts · 3" beside
   * "Obligations 4" would read as a contradiction rather than as a scope.
   *
   * The SCOPE still travels: you set it here, and every derived tab recomputes
   * against it and says so in a banner with a way out. Setting it belongs to
   * one place; obeying it belongs everywhere.
   */
  get railApplies(): boolean {
    return this.tab === 'repository';
  }

  /** Row severity, encoded at the row edge by `Table`'s `@rowClass`. */
  contractSeverity = (c: any): string => {
    if (c?.riskGrade === 'critical' || c?.riskGrade === 'high')
      return 'sev-over';
    if (
      typeof c?.daysToNotice === 'number' &&
      c.daysToNotice <= NOTICE_WINDOW_DAYS
    )
      return 'sev-note';
    if (c?.status === 'signed') return 'sev-ok';
    return 'sev-cool';
  };

  obligationSeverity = (o: any): string => {
    let st = o?.status;
    if (st === 'overdue' || st === 'due_today') return 'sev-over';
    if (st === 'due_soon') return 'sev-note';
    if (st === 'closed') return '';
    return 'sev-ok';
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

  /** Overdue work is the one count that earns an alarm colour. */
  get tabOptions(): { value: string; label: string }[] {
    return TABS.map((t) => {
      let n = this.tabCount(t.key);
      return { value: t.key, label: n ? `${t.label} ${n}` : t.label };
    });
  }

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

  get riskBands() {
    let bands = ['critical', 'high', 'medium', 'low'];
    let rows = bands
      .map((grade) => {
        let cards = this.contracts.filter((c) => c.riskGrade === grade);
        return {
          grade,
          label: riskGradeLabel(grade),
          count: cards.length,
          hue: (grade === 'critical'
            ? 'red'
            : grade === 'high'
              ? 'orange'
              : grade === 'medium'
                ? 'amber'
                : 'green') as Hue,
        };
      })
      .filter((b) => b.count);
    return scaleBands(rows);
  }

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

  statusHueOf = (value?: string | null): Hue =>
    (CONTRACT_STATUSES.find((o) => o.value === value)?.hue ?? 'slate') as Hue;

  typeLabelOf = (value?: string | null): string => contractTypeLabel(value);

  riskLabelOf = (value?: string | null): string => riskGradeLabel(value);

  riskHueOf = (grade?: string | null): Hue =>
    grade === 'critical'
      ? 'red'
      : grade === 'high'
        ? 'orange'
        : grade === 'medium'
          ? 'amber'
          : grade === 'low'
            ? 'green'
            : 'slate';

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
    let realm = this.realmList[0];
    if (!id || !realm) return undefined;
    let rest = id.startsWith(realm) ? id.slice(realm.length) : '';
    let parts = rest.split('/').filter(Boolean);
    // drop ['ContractExecutionApp', '<id>'] to leave the mirror prefix
    let prefix = parts.slice(0, -2).join('/');
    return prefix ? `${prefix}/${folder}` : folder;
  };

  get clauseUses(): ContractClause[] {
    return ((this.clauseUseQuery?.instances ?? []) as any[]).filter(
      Boolean,
    ) as ContractClause[];
  }

  <template>
    <div class='cx'>
      <header class='cx-mast' aria-label='Workspace summary'>
        <div class='cx-brand'>
          <span class='cx-seal'><ScaleIcon
              width='18'
              height='18'
              role='presentation'
            /></span>
          <div>
            <h1 class='cx-title'>{{@model.cardTitle}}</h1>
            <p class='cx-sub'>Contract lifecycle management</p>
          </div>
        </div>

        <dl class='cx-counters'>
          <div class='cx-ct {{if this.overdueCount "is-alarm"}}'>
            <dt>Overdue</dt>
            <dd>
              {{#if this.countsLoading}}
                —
              {{else}}
                {{#if this.overdueCount}}
                  <TriangleAlertIcon
                    width='14'
                    height='14'
                    role='presentation'
                  />
                {{/if}}
                {{this.overdueCount}}
              {{/if}}
            </dd>
          </div>
          <div class='cx-ct'>
            <dt>In approval</dt>
            <dd>{{if this.countsLoading '—' this.awaitingCount}}</dd>
          </div>
          <div class='cx-ct'>
            <dt>Notice 90d</dt>
            <dd>{{if this.countsLoading '—' this.noticeSoonCount}}</dd>
          </div>
          <div class='cx-ct'>
            <dt>Compliance</dt>
            <dd>{{if this.countsLoading '—' this.complianceLabel}}</dd>
          </div>
        </dl>
      </header>

      {{#if this.isInteractive}}
        {{#if this.unresolvedNote}}
          <p class='cx-unresolved' role='status'>{{this.unresolvedNote}}</p>
        {{/if}}

        <div class='cx-tabbar'>
          <Tabs
            class='cx-tabs'
            aria-label='Sections'
            @options={{this.tabOptions}}
            @value={{this.tab}}
            @onValueChange={{this.setTab}}
          />
        </div>

        <div class='cx-split {{unless this.railApplies "is-full"}}'>
          {{#if this.railApplies}}
            <nav class='cx-rail' aria-label='Saved views'>
              <p class='cx-rail-h'>Saved views</p>
              <FilterChips
                @label='Saved views'
                @options={{this.savedViewOptions}}
                @value={{this.currentViewName}}
                @onValueChange={{this.setViewByName}}
              />
            </nav>
          {{/if}}

          <main class='cx-panel'>
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
          </main>
        </div>
      {{else}}
        <main class='cx-panel cx-static'>
          <p class='cx-static-note'>Contract lifecycle management — repository,
            approvals, obligations and renewals. Open this card in the app to
            work with live records.</p>
          <ul class='cx-legend'>
            {{#each CONTRACT_STATUSES as |o|}}
              <li><StatePill
                  @label={{o.label}}
                  @hue={{o.hue}}
                  @dot={{true}}
                /></li>
            {{/each}}
          </ul>
        </main>
      {{/if}}
    </div>

    <style scoped>
      .cx {
        display: flex;
        flex-direction: column;
        height: 100%;
        min-height: 0;
        overflow: hidden;
        background: var(--background);
        color: var(--foreground);
        font-family: var(--font-sans);
        container-type: inline-size;
        container-name: cx-app;

        /* The measure every text-and-figure block is capped to.
           Without it, a `1fr` column on a 2000px display stretches a
           label/value pair ~870px apart and the pair stops reading as a pair.
           Tables are exempt — they legitimately use the full width. */
        --_cx-measure: 68rem;
      }

      .cx-mast {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: var(--boxel-sp);
        padding: var(--boxel-sp) var(--boxel-sp-lg);
        border-bottom: 1px solid var(--border);
      }
      .cx-brand {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
      }
      .cx-seal {
        width: 2rem;
        height: 2rem;
        border-radius: var(--boxel-border-radius-sm);
        display: grid;
        place-items: center;
        flex: none;
        background: color-mix(in oklch, var(--foreground) 8%, transparent);
      }
      .cx-title {
        margin: 0;
        font-size: var(--boxel-font-size-lg);
        font-weight: 600;
        line-height: 1.15;
      }
      .cx-sub {
        margin: 0;
        font-size: var(--boxel-font-size-xs);
        letter-spacing: 0.08em;
        text-transform: uppercase;
        color: var(--muted-foreground);
      }

      .cx-counters {
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp-lg);
        margin: 0 0 0 auto;
      }
      .cx-ct dt {
        font-size: var(--boxel-font-size-2xs);
        letter-spacing: 0.12em;
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .cx-ct dd {
        margin: 0;
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-3xs);
        font-size: var(--boxel-font-size-lg);
        font-weight: 600;
        font-variant-numeric: tabular-nums;
      }
      /* The alarm is never colour alone — the glyph carries it too. */
      .cx-ct.is-alarm dd {
        color: var(--destructive-ink);
      }

      .cx-unresolved {
        margin: 0;
        padding: var(--boxel-sp-2xs) var(--boxel-sp-lg);
        font-size: var(--boxel-font-size-xs);
        font-weight: 600;
        color: var(--destructive-ink);
        background: color-mix(in oklch, var(--destructive) 8%, transparent);
        border-bottom: 1px solid var(--border);
      }
      /* Twelve tabs outgrow a narrow card: the bar scrolls sideways and each
         tab keeps its label on one line. */
      .cx-tabbar {
        overflow-x: auto;
        border-bottom: 1px solid var(--border);
        padding: 0 var(--boxel-sp-lg);
      }
      .cx-tabs {
        width: max-content;
      }

      .cx-panel {
        min-height: 0;
        min-width: 0;
        overflow: auto;
        padding: var(--boxel-sp-lg);
      }
      .cx-static {
        display: grid;
        gap: var(--boxel-sp);
        align-content: start;
      }
      .cx-static-note {
        margin: 0;
        max-width: 52ch;
        color: var(--muted-foreground);
      }
      .cx-legend {
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp-2xs);
        list-style: none;
        margin: 0;
        padding: 0;
      }

      /* ============================================================
         APPROVAL CHAIN RAIL
         Drawn for the APPROVER, not the workflow author. `is-now` is the
         viewer's own step and is the only one that takes the accent.
         ============================================================ */
      /* ============================================================
         SPLIT: saved-view rail + work surface
         ============================================================ */
      /* ============================================================
         COMPLIANCE: KPI row + three charts
         ============================================================ */
      /* Same rule as the rail's assign control: an editable field is taller
         than the text around it, so it reads as editable at rest. */
      /* Destructive action carries the semantic danger colour and sits apart
         from the primary, per the platform's own guidance. */
      /* A blocked capability is stated in-product, not hidden. Neutral ground,
         not an error colour — nothing has gone wrong, it simply cannot run. */

      /* A submit that fails must say why. Without this the button did nothing
         visible when no rule matched, which reads as a broken control rather
         than as a configuration answer. */

      /* ---- Workspace tab (Contract Lifecycle Desk) ---- */
      /* An identifier or amount never ellipsises — it is read aloud and typed
         into other systems, so a neighbour shrinks instead. */

      /* `.cx-split` is the flex child of `.cx`: the grid stretches and each
         column scrolls on its own. */
      .cx-split {
        display: grid;
        grid-template-columns: 13rem minmax(0, 1fr);
        gap: var(--boxel-sp);
        align-items: stretch;
        flex: 1;
        min-height: 0;
      }
      .cx-rail {
        padding: var(--boxel-sp-xs) var(--boxel-sp-xs);
        border-right: 1px solid var(--border);
        min-height: 0;
        overflow-y: auto;
      }
      .cx-split.is-full {
        grid-template-columns: minmax(0, 1fr);
      }
      .cx-rail-h {
        margin: 0 0 var(--boxel-sp-xs);
        padding-left: var(--boxel-sp-2xs);
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-2xs);
        letter-spacing: 0.13em;
        text-transform: uppercase;
        color: var(--muted-foreground);
      }

      /* ============================================================
         KPI ROLL-UP
         ============================================================ */
      /* Full-bleed to the section edge so the KPI strip's first text lands on
         the same left as every other block. Measured 37.3 vs 21.3 before. */

      @container cx-app (width < 45rem) {
        /* the rail becomes a horizontal scroller rather than eating half a
           narrow panel — the views stay reachable, they stop being a column */
        .cx-split {
          grid-template-columns: 1fr;
        }
        .cx-rail {
          border-right: 0;
          border-bottom: 1px solid var(--border);
          overflow-x: auto;
        }
      }

      @container cx-app (width < 45rem) {
        .cx-counters {
          gap: var(--boxel-sp);
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
        <span>{{@model.cardTitle}}</span>
      </div>
      <style scoped>
        .cx-emb {
          /* The host wraps a linked card in a CardContainer that draws a
           boundary and deliberately adds NO padding (base/field-component.gts),
           because padding there would shift the container-query breakpoints the
           inner card reasons about. So the inset has to come from here, or the
           text sits flush against the pill the host draws. */
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-2xs);
          font-weight: 600;
        }
        .cx-emb-icon {
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  /**
   * Attribute-only. An app card is mounted in workspace grids, and the default
   * fitted would give it no identity at the badge quantum.
   */
  static fitted = class Fitted extends Component<typeof ContractExecutionApp> {
    <template>
      <FittedCard @titleTag='h3'>
        <:eyebrow><span class='fit-eyebrow'>Contract lifecycle</span></:eyebrow>
        <:title>{{@model.cardTitle}}</:title>
        <:subtitle>Repository · Approvals · Obligations</:subtitle>
        <:footer>
          <ScaleIcon
            class='fit-glyph'
            width='16'
            height='16'
            role='presentation'
          />
        </:footer>
      </FittedCard>
      <style scoped>
        .fit-eyebrow {
          color: var(--primary-ink);
        }
        .fit-glyph {
          color: var(--primary-ink);
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
