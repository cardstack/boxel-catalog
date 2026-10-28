import { concat } from '@ember/helper';
import {
  CardDef,
  Component,
  realmURL,
  type Format,
  type ViewCardFn,
  type CreateCardFn,
} from '@cardstack/base/card-api';
import {
  type Query,
  type LooseSingleCardDocument,
  identifyCard,
  searchEntryWireQueryFromQuery,
  type SearchEntryWireQuery,
} from '@cardstack/runtime-common';
import { cached, tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { debounce } from 'lodash';
import { eq, not } from '@cardstack/boxel-ui/helpers';
import { Alert } from '../../../ui-component/components/alert';
import { Avatar } from '../../../ui-component/components/avatar';
import { BarList } from '../../../ui-component/components/bar-list';
import { Button } from '../../../ui-component/components/button';
import {
  DataTable,
  type DataColumn,
} from '../../../ui-component/components/data-table';
import { EmptyState } from '../../../ui-component/components/empty-state';
import { Panel } from '../../../ui-component/components/panel';
import { Item } from '../../../ui-component/components/item';
import {
  PageScaffold,
  type PageStat,
} from '../../../ui-component/components/page-scaffold';
import { ProgressBar } from '../../../ui-component/components/progress-bar';
import {
  Sidebar,
  SidebarGroup,
  SidebarItem,
  SidebarTrigger,
} from '../../../ui-component/components/sidebar';
import { SegmentedControl } from '../../../ui-component/components/segmented-control';
import { StatusChip } from '../../../ui-component/components/status-chip';

import {
  Case,
  CASE_STATUSES,
  CASE_STATUS_LABELS,
  SEVERITY_HUES,
} from '../../service-desk/case';
import { Employee } from '../../hr/employee';
import { Role } from '../../service-desk/role';
import { CustomerReply } from '../../service-desk/customer-reply';
import { Escalation } from '../../service-desk/escalation';
import { Sla } from '../../service-desk/sla';
import { type BreachRiskRow } from '../../service-desk/components/command-center';
import {
  SupportQueue,
  type QueueRow,
} from '../../service-desk/components/support-queue';
import {
  WorkflowBoard,
  type BoardCard,
} from '../../service-desk/components/workflow-board';
import { LiveClock } from '../../service-desk/components/live-clock';
import { type HomeRail } from '../../../components/workspace-home';
import { Board, type BoardColumn } from '../../../components/board';
import ArrowRightIcon from '@cardstack/boxel-icons/arrow-right';
import SirenIcon from '@cardstack/boxel-icons/siren';
import { Input } from '../../../ui-component/components/input';
import { Dialog } from '../../../ui-component/components/dialog';
import { RadioGroup } from '../../../ui-component/components/radio-group';
import { Grid } from '../../../ui-component/components/grid';
import { FilterChips } from '../../../ui-component/components/filter-chips';
import { SearchInput } from '../../../ui-component/components/search-input';
import {
  timerSnapshot,
  sortByUrgency,
  type TimerFacts,
} from '../../service-desk/utils/sla';
import { getCard } from '../../../utils/find-card';
import { mintIdentifier } from '../../../fields/record-identifier/record-identifier-field';
import AssignOwnerCommand from '../../service-desk/commands/assign-owner-command';
import BatchTransformCommand from '../../service-desk/commands/batch-transform-command';
import RunWorkflowCommand from '../../service-desk/commands/run-workflow-command';
import EscalateCaseCommand from '../../service-desk/commands/escalate-case-command';
import {
  ESCALATION_LEVELS,
  levelRank,
} from '../../../fields/escalation-level/escalation-level-field';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';

import { DeskSetup } from './desk-setup';
import { DeskCopilot } from './desk-copilot';
import { DeskEscalations } from './desk-escalations';
import type { SupportCaseApp } from '../support-case-app';

// The rail, in the reference's order. `wall` is the Command Center.
const NAV = [
  { id: 'wall', label: 'Command Center' },
  { id: 'queues', label: 'Queues' },
  { id: 'board', label: 'Board' },
  { id: 'cases', label: 'Cases' },
  { id: 'escalations', label: 'Escalations' },
  { id: 'agents', label: 'Agents' },
  { id: 'home', label: 'My Desk' },
  { id: 'setup', label: 'Setup' },
] as const;

// Rail groups in the tracker's style: the first stands alone, the rest are
// labelled.
const NAV_GROUPS: { label?: string; ids: string[] }[] = [
  { ids: ['wall'] },
  { label: 'Work', ids: ['cases', 'queues', 'board', 'escalations'] },
  { label: 'People', ids: ['agents', 'home'] },
  { label: 'Admin', ids: ['setup'] },
];

type CaseView = 'grid' | 'list' | 'table';

const CASE_VIEWS = [
  { value: 'grid', label: 'Grid' },
  { value: 'list', label: 'List' },
  { value: 'table', label: 'Table' },
];
const QUEUE_VIEWS = [
  { value: 'lanes', label: 'By queue' },
  { value: 'list', label: 'Nearest breach' },
];

function plural(n: number, noun: string) {
  return `${n} ${n === 1 ? noun : `${noun}s`}`;
}

/** The desk itself: the Support Case App's isolated view. */
export class SupportDesk extends Component<typeof SupportCaseApp> {
  @tracked currentTab: string = 'wall';
  @tracked caseView: CaseView = 'table';
  @tracked caseSearch = '';
  @tracked caseStatusFilter = 'all';
  @tracked actionNote: string | null = null;
  @tracked queueView: 'lanes' | 'list' = 'lanes';
  @tracked queueSearch = '';
  @tracked queueSeverity = 'all';
  @tracked laneRefusal: string | null = null;

  // ── realm + queries ────────────────────────────────────────────────
  get commandContext() {
    let ctx = this.args.context?.commandContext;
    if (!ctx) {
      throw new Error('No command context available in this render mode');
    }
    return ctx;
  }

  get realm(): string | undefined {
    return this.args.model?.[realmURL]?.href;
  }
  get realms(): string[] {
    return this.realm ? [this.realm] : [];
  }

  private liveQuery(cardClass: typeof CardDef) {
    return this.args.context?.getCards(
      this,
      () => {
        let ref = identifyCard(cardClass);
        return ref ? { filter: { type: ref } } : undefined;
      },
      () => this.realms,
      { isLive: true },
    );
  }

  casesQuery = this.liveQuery(Case);
  slasQuery = this.liveQuery(Sla);
  escalationsQuery = this.liveQuery(Escalation);
  repliesQuery = this.liveQuery(CustomerReply);
  // The agent pool is the members of the live Role cards (a query on Role
  // includes subclasses), not the app card's hand-linked `candidatePool`
  // (kept in the schema, no longer read here) and not every Employee.
  rolesQuery = this.liveQuery(Role);

  get cases(): Case[] {
    return ((this.casesQuery?.instances ?? []) as Case[]).filter(Boolean);
  }
  get slas(): Sla[] {
    return ((this.slasQuery?.instances ?? []) as Sla[]).filter(Boolean);
  }
  get escalations(): Escalation[] {
    return ((this.escalationsQuery?.instances ?? []) as Escalation[]).filter(
      Boolean,
    );
  }
  get replies(): CustomerReply[] {
    return ((this.repliesQuery?.instances ?? []) as CustomerReply[]).filter(
      Boolean,
    );
  }

  // De-duplicated union of every loaded Role's members; unloaded or null
  // links are skipped. No Role with members means an empty pool.
  get agentPool(): Employee[] {
    let seen = new Set<string>();
    let pool: Employee[] = [];
    for (let role of (this.rolesQuery?.instances ?? []) as Role[]) {
      for (let m of (role?.members ?? []) as Employee[]) {
        if (m?.id && !seen.has(m.id)) {
          seen.add(m.id);
          pool.push(m);
        }
      }
    }
    return pool;
  }

  // ── agents tab: the pool, from the members of the live Roles ───────
  @tracked agentSearch = '';
  @tracked agentRole = 'all';
  @tracked agentStatus = 'all';
  @tracked agentView = 'grid';

  private debouncedSetAgentSearch = debounce((v: string) => {
    this.agentSearch = v;
  }, 250);
  setAgentSearch = (v: string) => this.debouncedSetAgentSearch(v);
  setAgentRole = (v: string) => (this.agentRole = v);
  setAgentStatus = (v: string) => (this.agentStatus = v);
  setAgentView = (v: string) => (this.agentView = v);

  get roleList(): Role[] {
    return ((this.rolesQuery?.instances ?? []) as Role[]).filter(Boolean);
  }
  roleName = (role: Role) => role.name ?? this.titleOf(role);
  get roleNames(): string[] {
    return [...new Set(this.roleList.map((r) => this.roleName(r)))];
  }
  get onDutyIds(): Set<string> {
    let ids = new Set<string>();
    for (let r of this.roleList) if (r.onDuty?.id) ids.add(r.onDuty.id);
    return ids;
  }
  private rolesOf(card: Employee): string[] {
    return [
      ...new Set(
        this.roleList
          .filter((r) => (r.members ?? []).some((m) => m?.id === card.id))
          .map((r) => this.roleName(r)),
      ),
    ];
  }
  get agentRoleOptions() {
    return [
      { value: 'all', label: 'All', count: this.agentPool.length },
      ...this.roleNames.map((n) => ({
        value: n,
        label: n,
        count: this.agentPool.filter((c) => this.rolesOf(c).includes(n)).length,
      })),
    ];
  }
  agentStatusOptions = [
    { value: 'all', label: 'All' },
    { value: 'on', label: 'On duty' },
    { value: 'off', label: 'Off duty' },
  ];
  agentViewOptions = [
    { value: 'grid', label: 'Grid' },
    { value: 'list', label: 'List' },
  ];
  get agentFiltersActive() {
    return (
      Boolean(this.agentSearch.trim()) ||
      this.agentRole !== 'all' ||
      this.agentStatus !== 'all'
    );
  }
  agentName = (c: Employee): string => c.name?.trim() || 'Unnamed employee';
  get agentTiles() {
    let q = this.agentSearch.trim().toLowerCase();
    let tiles = [];
    for (let card of this.agentPool) {
      let roles = this.rolesOf(card);
      let onDuty = this.onDutyIds.has(card.id as string);
      if (q && !this.agentName(card).toLowerCase().includes(q)) continue;
      if (this.agentRole !== 'all' && !roles.includes(this.agentRole)) continue;
      if (this.agentStatus === 'on' && !onDuty) continue;
      if (this.agentStatus === 'off' && onDuty) continue;
      tiles.push({
        card,
        id: card.id as string,
        name: this.agentName(card),
        role: roles.join(' · '),
        status: onDuty ? 'On duty' : 'Off duty',
        onDuty,
      });
    }
    // On duty first, then by name; an unnamed person last in their group.
    return tiles.sort(
      (a, b) =>
        Number(b.onDuty) - Number(a.onDuty) ||
        Number(!a.card.name?.trim()) - Number(!b.card.name?.trim()) ||
        a.name.localeCompare(b.name, undefined, { sensitivity: 'base' }),
    );
  }
  tileKeydown = (card: Employee, event: KeyboardEvent) => {
    if (event.target !== event.currentTarget) return;
    if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault();
      this.view(card);
    }
  };
  agentKey = (t: { id: string }) => t.id;
  openAgentRow = (t: { card: Employee }) => this.view(t.card);
  agentColumns: DataColumn<{
    name: string;
    role: string;
    status: string;
  }>[] = [
    { key: 'name', label: 'Name', value: (t) => t.name },
    { key: 'role', label: 'Role', value: (t) => t.role },
    { key: 'status', label: 'Status', value: (t) => t.status },
  ];

  // ── add agent: put an Employee on a Role's members ─────────────────
  employeesQuery = this.liveQuery(Employee);
  addTabs = [
    { value: 'existing', label: 'Existing employee' },
    { value: 'new', label: 'New employee' },
  ];
  @tracked addOpen = false;
  @tracked addTab = 'existing';
  @tracked addSearch = '';
  @tracked addEmployeeId: string | undefined;
  @tracked addRoleName: string | undefined;

  openAdd = () => {
    this.addTab = 'existing';
    this.addSearch = '';
    this.addEmployeeId = undefined;
    this.addRoleName = this.roleNames[0];
    this.addOpen = true;
    requestAnimationFrame(() =>
      document
        .querySelector<HTMLInputElement>('[data-agent-search] input')
        ?.focus(),
    );
  };
  closeAdd = () => (this.addOpen = false);
  setAddTab = (v: string) => (this.addTab = v);
  setAddSearch = (v: string) => (this.addSearch = v);
  pickAddEmployee = (e: Employee) => (this.addEmployeeId = e.id);
  setAddRole = (v: string) => {
    this.addRoleName = v;
    this.addEmployeeId = undefined;
  };
  private roleByName(name: string | undefined): Role | undefined {
    return this.roleList.find((r) => this.roleName(r) === name);
  }
  // People not already on the chosen role, by name.
  get addCandidates(): Employee[] {
    let role = this.roleByName(this.addRoleName);
    let onRole = new Set(
      (role?.members ?? []).filter(Boolean).map((m) => m.id),
    );
    let q = this.addSearch.trim().toLowerCase();
    return ((this.employeesQuery?.instances ?? []) as Employee[])
      .filter(
        (e) =>
          e?.id &&
          !onRole.has(e.id) &&
          (!q || this.agentName(e).toLowerCase().includes(q)),
      )
      .sort((a, b) => this.agentName(a).localeCompare(this.agentName(b)));
  }
  get addRoleOptions() {
    return this.roleNames.map((n) => ({ value: n, label: n }));
  }
  get canAddAgent() {
    return Boolean(
      this.addTab === 'existing' && this.addEmployeeId && this.addRoleName,
    );
  }
  get addConfirmLabel() {
    return `Add to ${this.addRoleName ?? 'role'}`;
  }
  addKeydown = (event: Event) => {
    if (
      event instanceof KeyboardEvent &&
      event.key === 'Enter' &&
      this.canAddAgent &&
      (event.target as HTMLElement).tagName === 'INPUT'
    ) {
      event.preventDefault();
      this.confirmAdd();
    }
  };
  private async addMember(role: Role, employee: Employee) {
    let members = (role.members ?? []).filter(Boolean);
    if (members.some((m) => m.id === employee.id)) {
      this.note(
        `${this.agentName(employee)} is already on ${this.roleName(role)}`,
      );
      return;
    }
    try {
      role.members = [...members, employee];
      await new SaveCardCommand(this.commandContext).execute({ card: role });
      this.note(`Added ${this.agentName(employee)} to ${this.roleName(role)}`);
    } catch (e: any) {
      role.members = members;
      this.note(e?.message ?? String(e));
    }
  }
  confirmAdd = async () => {
    let employee = this.addCandidates.find((e) => e.id === this.addEmployeeId);
    let role = this.roleByName(this.addRoleName);
    if (!employee || !role) return;
    this.addOpen = false;
    await this.addMember(role, employee);
  };
  // New employee: createCard opens the new card in its own edit format (the
  // delegated form); the returned id is then added to the chosen Role.
  createAgent = async () => {
    let createCard = (this.args as any).createCard as CreateCardFn | undefined;
    let ref = identifyCard(Employee);
    let role = this.roleByName(this.addRoleName);
    if (!createCard || !ref || !role) {
      this.note('Commands are unavailable in this mode');
      return;
    }
    this.addOpen = false;
    let realm = this.realm ? new URL(this.realm) : undefined;
    try {
      let id = await createCard(ref, realm, {
        realmURL: realm,
        doc: {
          data: { type: 'card', attributes: {}, meta: { adoptsFrom: ref } },
        },
      });
      let created = id ? await this.byId(id) : undefined;
      if (created instanceof Employee) await this.addMember(role, created);
    } catch (e: any) {
      this.note(e?.message ?? String(e));
    }
  };

  get escalationsLoading() {
    return (
      (this.escalationsQuery?.isLoading ?? false) &&
      this.escalations.length === 0
    );
  }
  // A count reads a dash until EVERY query it draws on has answered, never a
  // wrong 0.
  get isLoading(): boolean {
    return [
      this.casesQuery,
      this.slasQuery,
      this.escalationsQuery,
      this.repliesQuery,
      this.rolesQuery,
    ].some((q) => !q || q.isLoading);
  }
  count = (n: number): number | string => (this.isLoading ? '—' : n);

  // ── joins ──────────────────────────────────────────────────────────
  /** Re-fetch a card by id — the defensive-link-traversal rule: never trust
      the caller's (or the model's) load state. */
  byId = async (id?: string | null) =>
    id ? getCard(this.commandContext as any, id) : undefined;

  /** Ids may be absolute URLs or realm-relative ("../Employee/dana-kim");
      compare by the trailing type/name segments so both worlds match. */
  sameCard = (a?: string | null, b?: string | null): boolean => {
    if (!a || !b) return false;
    let tail = (x: string) =>
      x
        .replace(/\.json$/, '')
        .split('/')
        .slice(-2)
        .join('/');
    return tail(a) === tail(b);
  };

  /** Realm cards title via computed cardTitle; base title is often unset. */
  titleOf = (card: any): string =>
    (card?.cardTitle as string) || (card?.title as string) || 'untitled';

  /** Lane cards carry their state as a left stripe — the anchor. */
  slaFor = (card: any): Sla | undefined => {
    return this.slas.find((s) => this.sameCard(s.subjectId, card?.id));
  };

  /** The case's most urgent timer facts — one place decides "worst". */
  // An SLA timer: the shared timer facts plus which clock it is.
  worstFacts = (card: any): (TimerFacts & { kind?: string }) | undefined => {
    let sla = this.slaFor(card);
    let timers = (sla?.timers ?? []).filter((t: any) => !t.satisfiedAt);
    if (!timers.length) return undefined;
    return sortByUrgency(timers)[0] as
      | (TimerFacts & { kind?: string })
      | undefined;
  };

  repliesFor = (card: any): CustomerReply[] => {
    return this.replies.filter((r) => this.sameCard(r.caseRefId, card?.id));
  };

  get openCases() {
    return this.cases.filter(
      (c) => c.status !== 'resolved' && c.status !== 'closed',
    );
  }

  get breachRiskCases() {
    let rows = this.openCases.flatMap((c) => {
      let facts = this.worstFacts(c);
      return facts ? [{ card: c, facts }] : [];
    });
    return sortByUrgency(rows, (r) => r.facts);
  }

  get atRiskCount() {
    return this.breachRiskCases.filter((r) => {
      let s = timerSnapshot(r.facts).state;
      return s === 'urgent' || s === 'warning';
    }).length;
  }
  get breachedCount() {
    return this.breachRiskCases.filter(
      (r) => timerSnapshot(r.facts).state === 'breached',
    ).length;
  }
  get metTodayCount() {
    return this.slas.filter((s) =>
      (s.timers ?? []).some((t: any) => t.satisfiedAt),
    ).length;
  }
  get openEscalations() {
    return this.escalations.filter((e) => e.status === 'open');
  }
  get overdueAckCount() {
    return this.openEscalations.filter((e) => e.ackOverdue === 'yes').length;
  }

  // ── command center data ────────────────────────────────────────────
  get wallStats(): PageStat[] {
    return [
      { label: 'Open cases', value: this.count(this.openCases.length) },
      {
        label: '≥ 75% consumed',
        value: this.count(this.atRiskCount),
        hint: this.atRiskCount ? 'at risk' : undefined,
        hintTone: this.atRiskCount ? 'warning' : undefined,
      },
      {
        label: 'Breached',
        value: this.count(this.breachedCount),
        hint: 'clocks past target',
        hintTone: this.breachedCount ? 'danger' : undefined,
      },
      {
        label: 'Clocks met',
        value: this.count(this.metTodayCount),
        hint: `of ${plural(this.slas.length, 'clock')}`,
      },
      {
        label: 'Awaiting ack',
        value: this.count(this.openEscalations.length),
        hint: `${this.overdueAckCount} overdue`,
        hintTone: this.overdueAckCount ? 'danger' : undefined,
      },
    ];
  }

  get wallBreachRows(): BreachRiskRow[] {
    return this.breachRiskCases.slice(0, 8).map(({ card, facts }) => ({
      card,
      label: `${card.caseId?.value ? card.caseId.value + ' · ' : ''}${this.titleOf(card)}`,
      timerFacts: facts,
      chipLabel: card.severity ?? '',
      chipHue: SEVERITY_HUES[card.severity ?? 'low'] ?? 'slate',
      ownerName: card.ownership?.ownerName,
      clockKind: facts?.kind,
      onAssign: card.ownership?.ownerName
        ? undefined
        : () => this.assignToOperator(card),
    }));
  }

  get nearestBreach(): BreachRiskRow | undefined {
    return this.wallBreachRows[0];
  }

  /** "CASE-2026-0142" → "0142"; anything without a dash stays whole. */
  shortId = (id: unknown) =>
    String(id ?? '—')
      .split('-')
      .pop();

  openBreachRow = (row: BreachRiskRow) => this.openCard(row.card);

  breachKey = (row: BreachRiskRow) => row.card?.id as string;

  /** Share of the running clock already used, 0–100. */
  consumedOf = (row: BreachRiskRow): number => {
    let left = timerSnapshot(row.timerFacts).percentRemaining;
    return left == null ? 0 : 100 - left;
  };

  severityTone = (severity?: string) =>
    severity === 'critical'
      ? 'danger'
      : severity === 'high'
        ? 'warning'
        : 'neutral';

  get agentsOnDuty() {
    return this.agentPool.length;
  }

  get wallQueues() {
    // Queue load derived from ownership team names on open cases.
    let byTeam = new Map<string, number>();
    for (let c of this.openCases) {
      let team = c.ownership?.teamName ?? 'Unrouted';
      byTeam.set(team, (byTeam.get(team) ?? 0) + 1);
    }
    let agents = Math.max(1, this.agentPool.length);
    return [...byTeam.entries()].map(([name, open]) => ({
      name,
      open,
      agents,
      overloaded: open > agents * 4,
      oldestLabel: open > agents * 4 ? 'heavy' : 'ok',
      onOpen: () => this.goTab('queues'),
    }));
  }

  get queueLoad() {
    return this.wallQueues.map((q) => ({
      name: q.name,
      value: q.open,
      hue: q.overloaded ? 'var(--warning)' : undefined,
    }));
  }

  wallColumns: DataColumn<BreachRiskRow>[] = [
    {
      key: 'case',
      label: 'Case',
      mono: true,
      value: (r) => r.card?.caseId?.value ?? '—',
    },
    { key: 'subject', label: 'Subject', value: (r) => this.titleOf(r.card) },
    { key: 'severity', label: 'Severity', value: (r) => r.chipLabel },
    { key: 'clock', label: 'Clock', value: (r) => r.clockKind ?? '—' },
    {
      key: 'consumed',
      label: 'Consumed',
      align: 'end',
      value: (r) => this.consumedOf(r),
    },
    {
      key: 'owner',
      label: 'Owner',
      value: (r) => r.ownerName ?? 'Unassigned',
    },
    {
      key: 'left',
      label: 'Time left',
      align: 'end',
      value: (r) => timerSnapshot(r.timerFacts).shortLabel,
    },
  ];

  // Awaiting-acknowledgement rows: the escalation's level and subject.
  ackTitle = (e: Escalation) =>
    `${(e.toLevel?.key as string) ?? '?'} escalation`;
  ackDescription = (e: Escalation) => e.subjectTitle ?? e.title ?? '?';
  ackDue = (e: Escalation) =>
    e.ackOverdue === 'yes'
      ? 'overdue'
      : e.toLevel?.ackTargetMinutes
        ? `${e.toLevel.ackTargetMinutes}m target`
        : 'no target';
  ackTone = (e: Escalation) => (e.ackOverdue === 'yes' ? 'danger' : 'neutral');

  // ── cases tab: the collection shell ────────────────────────────────
  get caseRef() {
    return identifyCard(Case);
  }

  get statusBadges() {
    // 'all' is index 0, always.
    let counts = new Map<string, number>();
    for (let c of this.cases)
      counts.set(c.status ?? 'open', (counts.get(c.status ?? 'open') ?? 0) + 1);
    return [
      { id: 'all', label: 'All', count: this.cases.length },
      ...CASE_STATUSES.map((s) => ({
        id: s,
        label: CASE_STATUS_LABELS[s] ?? s,
        count: counts.get(s) ?? 0,
      })),
    ];
  }

  get filteredCases(): Case[] {
    // Deliberate MIRROR of `caseWireQuery` (grid/list) so toggling views
    // never changes the row set: text approximates the wire `matches`
    // over the fields a table reader scans.
    let q = this.caseSearch.trim().toLowerCase();
    return this.cases.filter((c) => {
      let statusOk =
        this.caseStatusFilter === 'all' ||
        (c.status ?? 'open') === this.caseStatusFilter;
      let textOk =
        !q ||
        c.subject?.toLowerCase().includes(q) ||
        c.caseId?.value?.toLowerCase().includes(q) ||
        c.ownership?.ownerName?.toLowerCase().includes(q);
      return statusOk && Boolean(textOk);
    });
  }

  get caseQuery(): Query | undefined {
    let ref = this.caseRef;
    if (!ref) return undefined;
    let q = this.caseSearch.trim();
    let base =
      this.caseStatusFilter === 'all'
        ? { type: ref }
        : { on: ref, eq: { status: this.caseStatusFilter } };
    if (!q) return { filter: base as any };
    return {
      filter: {
        every: [
          base,
          { any: [{ matches: q }, { contains: { cardTitle: q } }] },
        ],
      } as any,
    };
  }

  get caseWireQuery(): SearchEntryWireQuery | undefined {
    let query = this.caseQuery;
    if (!query || !this.realms.length) return undefined;
    return { ...searchEntryWireQueryFromQuery(query), realms: this.realms };
  }

  caseKey = (c: any) => c.id as string;

  caseColumns: DataColumn<any>[] = [
    {
      key: 'caseId',
      label: 'Case',
      mono: true,
      value: (c: any) => c.caseId?.value ?? '—',
    },
    { key: 'subject', label: 'Subject', value: (c: any) => c.subject },
    {
      key: 'severity',
      label: 'Severity',
      value: (c: any) => c.severity,
    },
    {
      key: 'status',
      label: 'Status',
      value: (c: any) => CASE_STATUS_LABELS[c.status] ?? c.status,
    },
    {
      key: 'owner',
      label: 'Owner',
      value: (c: any) => c.ownership?.ownerName ?? 'unassigned',
    },
    {
      key: 'state',
      label: 'Workflow',
      value: (c: any) => c.workflowState?.label ?? '—',
    },
  ];

  private debouncedSetCaseSearch = debounce((value: string) => {
    this.caseSearch = value;
  }, 250);
  setCaseSearch = (value: string) => {
    this.debouncedSetCaseSearch(value);
  };
  setStatusFilter = (id: string) => (this.caseStatusFilter = id);
  setCaseView = (id: string) => (this.caseView = id as CaseView);

  // ── queue rows ─────────────────────────────────────────────────────
  @cached
  get queueRows(): QueueRow[] {
    return this.openCases.map((c) => ({
      card: c,
      label: `${c.caseId?.value ? c.caseId.value + ' · ' : ''}${this.titleOf(c)}`,
      timerFacts: this.worstFacts(c),
      chipLabel: c.severity ?? '',
      chipHue: SEVERITY_HUES[c.severity ?? 'low'] ?? 'slate',
      ownerName: c.ownership?.ownerName,
    }));
  }

  // ── queue collection shell state ──
  private debouncedSetQueueSearch = debounce(
    (v: string) => (this.queueSearch = v),
    250,
  );
  setQueueSearch = (v: string) => this.debouncedSetQueueSearch(v);
  setQueueSeverity = (id: string) => (this.queueSeverity = id);
  get queueChipOptions() {
    return this.queueBadges.map((b) => ({
      value: b.id,
      label: b.label,
      count: b.count,
    }));
  }
  get caseChipOptions() {
    return this.statusBadges.map((b) => ({
      value: b.id,
      label: b.label,
      count: b.count,
    }));
  }
  get queueBadges() {
    let sev = ['critical', 'high', 'medium', 'low'];
    let counts = new Map<string, number>();
    for (let r of this.queueRows)
      counts.set(
        r.card.severity ?? 'low',
        (counts.get(r.card.severity ?? 'low') ?? 0) + 1,
      );
    return [
      { id: 'all', label: 'All', count: this.queueRows.length },
      {
        id: 'unassigned',
        label: 'Unassigned',
        count: this.queueRows.filter((r) => !r.ownerName).length,
      },
      ...sev.map((x) => ({
        id: x,
        label: x[0]!.toUpperCase() + x.slice(1),
        count: counts.get(x) ?? 0,
      })),
    ];
  }
  /** The row set both queue views draw — one filter, two drawings. */
  get filteredQueueRows(): QueueRow[] {
    let q = this.queueSearch.trim().toLowerCase();
    return this.queueRows.filter((r) => {
      let c: any = r.card;
      let sevOk =
        this.queueSeverity === 'all' ||
        (this.queueSeverity === 'unassigned'
          ? !r.ownerName
          : (c.severity ?? 'low') === this.queueSeverity);
      let textOk =
        !q ||
        c.subject?.toLowerCase().includes(q) ||
        c.caseId?.value?.toLowerCase().includes(q) ||
        r.ownerName?.toLowerCase().includes(q) ||
        c.ownership?.teamName?.toLowerCase().includes(q);
      return sevOk && Boolean(textOk);
    });
  }

  /** Queues as a kanban (shared Board block): one column per owning team, Unrouted first. */
  queueKeyFor = (item: any) =>
    (item?.ownership?.teamName as string) ?? 'Unrouted';
  get app() {
    return this.args.model as SupportCaseApp;
  }
  caseLabel = (item: any): string | undefined => item?.caseId?.value;
  @cached
  get queueRowsById(): Map<string, QueueRow> {
    return new Map(this.queueRows.map((r) => [r.card?.id as string, r]));
  }
  queueRowFor = (item: any): QueueRow | undefined =>
    this.queueRowsById.get(item?.id);
  get queueItems() {
    return sortByUrgency(this.filteredQueueRows, (r) => r.timerFacts).map(
      (r) => r.card,
    );
  }
  get queueColumns(): BoardColumn[] {
    let keys = new Set<string>(['Unrouted']);
    for (let r of this.filteredQueueRows) keys.add(this.queueKeyFor(r.card));
    let ordered = [...keys].sort((a, b) =>
      a === 'Unrouted' ? -1 : b === 'Unrouted' ? 1 : a.localeCompare(b),
    );
    return ordered.map((key) => {
      let rows = this.filteredQueueRows.filter(
        (r) => this.queueKeyFor(r.card) === key && r.timerFacts,
      );
      let nearest = rows.length
        ? timerSnapshot(sortByUrgency(rows, (r) => r.timerFacts)[0].timerFacts)
            .shortLabel
        : undefined;
      return {
        key,
        label: nearest ? `${key} · ${nearest}` : key,
        color: key === 'Unrouted' ? 'var(--warning)' : 'var(--primary)',
      };
    });
  }
  setQueueView = (v: string) => (this.queueView = v as 'lanes' | 'list');

  // ── board rows ─────────────────────────────────────────────────────
  get boardCards(): BoardCard[] {
    // The board is the whole lifecycle — resolved cases stay visible in the
    // terminal column (that is where Archive lives); closed ones leave.
    return this.cases
      .filter((c) => c.status !== 'closed')
      .map((c) => ({
        card: c,
        label: c.caseId?.value,
        title: this.titleOf(c),
        chipLabel: c.severity ?? '',
        chipHue: SEVERITY_HUES[c.severity ?? 'low'] ?? 'slate',
        ownerName: c.ownership?.ownerName,
        stateKey: c.workflowState?.key,
        timerFacts: this.worstFacts(c),
      }));
  }

  // ── home rails ─────────────────────────────────────────────────────
  get operatorName() {
    return (
      (this.args.model.operator?.title as string) ??
      (this.args.model.operatorTitle as string) ??
      'operator'
    );
  }
  get myCases() {
    return this.openCases.filter((c) =>
      this.sameCard(
        c.owner?.id ?? c.ownership?.ownerId,
        this.args.model.operator?.id,
      ),
    );
  }
  get homeRails(): HomeRail[] {
    return [
      {
        title: 'Awaiting acknowledgement',
        emptyLabel: '✓ Every escalation acknowledged.',
        items: this.openEscalations.map((e) => ({
          label: e.subjectTitle ?? e.title ?? '?',
          meta: e.toLevel?.ackTargetMinutes
            ? `${e.toLevel.ackTargetMinutes}m target`
            : undefined,
          onOpen: () => this.openCard(e),
          action: { label: 'Acknowledge', run: () => this.acknowledge(e) },
        })),
      },
      {
        title: 'Breaching soon',
        emptyLabel: '✓ No clocks at risk.',
        items: this.breachRiskCases.slice(0, 4).map(({ card, facts }) => ({
          label: this.titleOf(card),
          meta: timerSnapshot(facts).shortLabel,
          onOpen: () => this.openCard(card),
        })),
      },
      {
        title: `Owned by ${this.operatorName}`,
        emptyLabel: 'Nothing assigned.',
        items: this.myCases.map((c) => ({
          label: this.titleOf(c),
          meta: c.workflowState?.label ?? c.status,
          onOpen: () => this.openCard(c),
        })),
      },
    ];
  }

  get showsAddCase() {
    return ['cases', 'queues', 'board'].includes(this.currentTab);
  }
  get appTitle(): string {
    return this.args.model.cardTitle ?? 'Support Ops';
  }

  // ── shell: rail, page header, stats ────────────────────────────────
  get navItems() {
    let badges: Record<string, number> = {
      queues: this.openCases.length,
      cases: this.openCases.length,
      escalations: this.openEscalations.length,
      agents: this.agentPool.length,
      home: this.myCases.length,
    };
    let loading = this.isLoading;
    return NAV.map((n) => ({
      ...n,
      badge:
        n.id in badges ? (loading ? '—' : String(badges[n.id])) : undefined,
    }));
  }
  get navGroups() {
    return NAV_GROUPS.map((g) => ({
      label: g.label,
      items: this.navItems.filter((n) => g.ids.includes(n.id)),
    }));
  }

  get pageTitle() {
    return NAV.find((n) => n.id === this.currentTab)!.label;
  }

  get pageSubtitle(): string {
    switch (this.currentTab) {
      case 'wall':
        return this.isLoading
          ? 'Loading…'
          : `${plural(this.agentsOnDuty, 'agent')} on duty · ${plural(this.openCases.length, 'open case')}`;
      case 'queues':
        return this.isLoading
          ? 'Loading…'
          : `${plural(this.openCases.length, 'open case')} across ${plural(this.wallQueues.length, 'queue')}`;
      case 'escalations':
        return this.isLoading
          ? 'Loading…'
          : `${plural(this.openEscalations.length, 'escalation')} awaiting acknowledgement`;
      case 'agents':
        return this.isLoading
          ? 'Loading…'
          : this.agentFiltersActive
            ? `Showing ${this.agentTiles.length} of ${this.agentPool.length}`
            : `${plural(this.agentPool.length, 'agent')} · ${this.onDutyIds.size} on duty`;
      case 'home':
        return this.isLoading
          ? 'Loading…'
          : `${plural(this.myCases.length, 'case')} owned by ${this.operatorName}`;
      default:
        return '';
    }
  }

  get stats(): PageStat[] {
    return this.currentTab === 'wall' ? this.wallStats : [];
  }

  // ── actions ────────────────────────────────────────────────────────
  goTab = (id: string) => {
    this.currentTab = id;
    this.actionNote = null;
  };

  // The Board takes pointer capture on pointerdown, which redirects a
  // control's click to the board and opens the card instead. Stopping
  // pointerdown on the control keeps its own click.
  shield = (e: Event) => e.stopPropagation();

  // `viewCard` takes a card OBJECT or a URL. Card ids here are
  // `@cardstack/catalog/...` identifiers, not absolute URLs, so `new URL(id)`
  // throws; the object also avoids a fetch that outruns indexing.
  private view(card: any, format: Format = 'isolated') {
    let viewCard = (this.args as any).viewCard as ViewCardFn | undefined;
    if (card && viewCard) viewCard(card, format);
  }
  // The card's own component (SupportCase or plain Case), drawn as fitted.
  faceFor = (card: any) =>
    card ? (card.constructor as typeof CardDef).getComponent(card) : undefined;
  openCard = (card: any) => this.view(card);
  // Every "add" on the desk lands the operator in the edit form of the new
  // record, not its isolated view; a freshly minted card has nothing to read.
  editCard = (card: any) => this.view(card, 'edit');
  // DataTable's @onRowActivate passes (row, index); drop the index.
  openRowCard = (row: any) => this.view(row);
  openEntry = (id: string) => {
    let card = [...this.cases, ...this.escalations].find((c) => c.id === id);
    if (card) return this.view(card);
    let viewCard = (this.args as any).viewCard as ViewCardFn | undefined;
    try {
      viewCard?.(new URL(id));
    } catch {
      // not an absolute URL and not a loaded card: nothing to open
    }
  };

  createCase = async () => {
    // The number is claimed before the save, so a failed save skips a number
    // rather than reusing one, and any id already on a case is passed over.
    let cfg = this.args.model.config;
    let seq = (cfg?.identifierSeq ?? 0) + 1;
    let pattern = cfg?.idPattern;
    if (pattern) {
      let used = new Set(
        this.cases.map((c) => c.caseId?.value).filter(Boolean),
      );
      while (used.has(mintIdentifier(pattern, seq))) {
        seq++;
      }
    }
    if (cfg) cfg.identifierSeq = seq;
    let createCard = (this.args as any).createCard as CreateCardFn | undefined;
    let ref = this.caseRef;
    if (!createCard || !ref) {
      this.note('Commands are unavailable in this mode');
      return;
    }
    let realm = this.realm ? new URL(this.realm) : undefined;
    let doc: LooseSingleCardDocument = {
      data: {
        type: 'card',
        attributes: {
          subject: 'New case',
          status: 'open',
          openedOn: new Date().toISOString(),
          ...(pattern
            ? {
                caseId: {
                  value: mintIdentifier(pattern, seq),
                  pattern,
                  issuedAt: new Date().toISOString(),
                },
              }
            : {}),
        },
        meta: { adoptsFrom: ref },
      },
    };
    // createCard opens the new card in the stack itself, in edit format.
    try {
      await createCard(ref, realm, { realmURL: realm, doc });
    } catch (err: any) {
      this.note(err?.message ?? String(err));
    }
  };

  note = (msg: string) => {
    this.actionNote = msg;
  };

  /** Keep the linked `owner` in step with the ownership text the command
      wrote: resolve ownerId to an Employee we hold, set the link, save. */
  private syncOwner = async (card: Case) => {
    let id = card.ownership?.ownerId;
    if (!id || this.sameCard(card.owner?.id, id)) return;
    let employee =
      this.agentPool.find((e) => this.sameCard(e.id, id)) ??
      (this.sameCard(this.args.model.operator?.id, id)
        ? this.args.model.operator
        : undefined);
    if (!employee) return;
    card.owner = employee;
    await new SaveCardCommand(this.commandContext).execute({ card });
  };

  assignToOperator = async (card: any) => {
    try {
      let operator = await this.byId(this.args.model.operatorId);
      let result = await new AssignOwnerCommand(this.commandContext).execute({
        card,
        owner: operator,
        strategy: 'assigned',
      } as any);
      await this.syncOwner(card);
      this.note((result as any).message);
    } catch (e: any) {
      this.note(e?.message ?? String(e));
    }
  };

  claim = async (card: any) => {
    try {
      let operator = await this.byId(this.args.model.operatorId);
      let result = await new AssignOwnerCommand(this.commandContext).execute({
        card,
        owner: operator,
        strategy: 'claimed',
      } as any);
      await this.syncOwner(card);
      this.note((result as any).message);
    } catch (e: any) {
      this.note(e?.message ?? String(e));
    }
  };

  batch = async (operation: string, cards: any[]) => {
    try {
      // Desk rule (the generic Archive command stays domain-neutral): only
      // terminal cases may leave the working set. Refusals are reported
      // per item, never silently dropped.
      let refusedLines: string[] = [];
      if (operation === 'archive') {
        let keep: any[] = [];
        for (let c of cards) {
          if (c?.status === 'resolved' || c?.status === 'closed') keep.push(c);
          else
            refusedLines.push(
              `refused ${this.titleOf(c)}: not terminal (status ${c?.status ?? 'unknown'}) — resolve it first`,
            );
        }
        cards = keep;
        if (!cards.length) {
          this.note(
            `Batch: 0 ok, ${refusedLines.length} refused — ${refusedLines.join(' · ')}`,
          );
          return;
        }
      }
      let pool: any[] = [...this.agentPool];
      if (operation === 'assign-owner' && !pool.length) {
        // links may be unloaded — fall back to the operator by id
        let op = await this.byId(this.args.model.operatorId);
        pool = op ? [op] : [];
      }
      let result = await new BatchTransformCommand(this.commandContext).execute(
        {
          cards,
          operation,
          strategy: operation === 'assign-owner' ? 'round-robin' : undefined,
          candidates: operation === 'assign-owner' ? pool : undefined,
          workflow:
            operation === 'run-workflow'
              ? await this.byId(this.args.model.workflowId)
              : undefined,
          toStateKey: operation === 'run-workflow' ? 'working' : undefined,
          actorName: this.operatorName,
        } as any,
      );
      let r = result as any;
      if (operation === 'assign-owner') {
        for (let c of cards) await this.syncOwner(c);
      }
      let refused = Number(r.refusedCount ?? 0) + refusedLines.length;
      this.note(
        `Batch: ${r.okCount} ok, ${refused} refused — ${[...(r.results ?? []), ...refusedLines].join(' · ')}`,
      );
    } catch (e: any) {
      this.note(e?.message ?? String(e));
    }
  };

  moveOnBoard = async (card: any, toStateKey: string, note?: string) => {
    // Refusals propagate: the board shows the guard's message and snaps back.
    await new RunWorkflowCommand(this.commandContext).execute({
      card,
      workflow: await this.byId(this.args.model.workflowId),
      toStateKey,
      note,
      actorName: this.operatorName,
      sla: this.slaFor(card),
    } as any);
  };

  /** Drag on the Queues lanes = route between queues (owner kept). */
  routeToQueue = async (card: any, teamName: string) => {
    this.laneRefusal = null;
    try {
      let result = await new AssignOwnerCommand(this.commandContext).execute({
        card,
        strategy: 'routed',
        teamName,
      } as any);
      this.note((result as any).message);
    } catch (e: any) {
      this.laneRefusal = e?.message ?? String(e);
      return false;
    }
    return undefined;
  };

  /** Drag on the ladder = raise the same subject one rung up. Down is not
      a move — the command's guard and this check both say so. */
  // ── raise an escalation from the tab (same command as the drag) ────
  @tracked raiseOpen = false;
  @tracked raiseSearch = '';
  @tracked raiseCaseId: string | undefined;
  @tracked raiseLevelKey: string | undefined;
  @tracked raiseNote = '';

  /** The case's current ladder level, or undefined when never escalated. */
  caseLevel = (card: Case): string | undefined => {
    let best: string | undefined;
    for (let e of this.escalations) {
      let key = e.toLevel?.key as string | undefined;
      if (
        this.sameCard(e.subjectId, card.id) &&
        key &&
        (!best || levelRank(key) > levelRank(best))
      )
        best = key;
    }
    return best;
  };
  levelLabel = (key?: string) => (key === 'exec' ? 'Exec' : (key ?? ''));
  get raiseCandidates(): Case[] {
    let q = this.raiseSearch.trim().toLowerCase();
    return this.openCases.filter(
      (c) =>
        c.id &&
        levelRank(this.caseLevel(c)) < levelRank('exec') &&
        (!q ||
          this.titleOf(c).toLowerCase().includes(q) ||
          (c.caseId?.value ?? '').toLowerCase().includes(q)),
    );
  }
  get raiseSelected(): Case | undefined {
    return this.raiseCandidates.find((c) => c.id === this.raiseCaseId);
  }
  get raiseFromLabel() {
    let c = this.raiseSelected;
    return (c && this.levelLabel(this.caseLevel(c))) || 'Not escalated';
  }
  // Only the rungs above the current one are offered.
  get raiseLevelOptions() {
    let c = this.raiseSelected;
    let from = c ? this.caseLevel(c) : undefined;
    return ESCALATION_LEVELS.filter((l) => levelRank(l) > levelRank(from)).map(
      (l) => ({ value: l, label: this.levelLabel(l) }),
    );
  }
  /** What a level means, from the ladder's own data on existing escalations. */
  get raiseLevelHelp(): string | undefined {
    let key = this.raiseLevelKey;
    let e = this.escalations.find((x) => x.toLevel?.key === key);
    return e?.toLevel?.label || e?.toLevel?.targetRoleName || undefined;
  }
  get canRaise() {
    return Boolean(this.raiseSelected && this.raiseLevelKey);
  }
  get raiseConfirmLabel() {
    return this.raiseLevelKey
      ? `Raise to ${this.levelLabel(this.raiseLevelKey)}`
      : 'Raise';
  }
  get escalationsEmpty() {
    return !this.escalationsLoading && this.escalations.length === 0;
  }
  get casesEmpty() {
    return !this.isLoading && this.cases.length === 0;
  }
  openRaise = () => {
    this.raiseSearch = '';
    this.raiseCaseId = undefined;
    this.raiseLevelKey = undefined;
    this.raiseNote = '';
    this.raiseOpen = true;
    requestAnimationFrame(() =>
      document
        .querySelector<HTMLInputElement>('[data-raise-search] input')
        ?.focus(),
    );
  };
  closeRaise = () => (this.raiseOpen = false);
  setRaiseSearch = (v: string) => (this.raiseSearch = v);
  pickRaiseCase = (c: Case) => {
    this.raiseCaseId = c.id;
    this.raiseLevelKey = this.raiseLevelOptions[0]?.value;
  };
  setRaiseLevel = (v: string) => (this.raiseLevelKey = v);
  setRaiseNote = (v: string) => (this.raiseNote = v);
  raiseKeydown = (event: Event) => {
    if (
      event instanceof KeyboardEvent &&
      event.key === 'Enter' &&
      this.canRaise &&
      (event.target as HTMLElement).tagName === 'INPUT'
    ) {
      event.preventDefault();
      this.confirmRaise();
    }
  };
  confirmRaise = async () => {
    let subject = this.raiseSelected;
    let toLevelKey = this.raiseLevelKey;
    if (!subject || !toLevelKey) return;
    let note =
      this.raiseNote.trim() ||
      `Raised from the Escalations tab by ${this.operatorName}`;
    this.raiseOpen = false;
    let raisedBy = await this.byId(this.args.model.operatorId);
    try {
      let result = await new EscalateCaseCommand(this.commandContext).execute({
        subject: await this.byId(subject.id),
        fromLevelKey: this.caseLevel(subject) ?? 'L1',
        toLevelKey,
        reason: 'agent-request',
        note,
        raisedBy: raisedBy instanceof Employee ? raisedBy : undefined,
        realm: this.realm,
      });
      this.note(result.message);
    } catch (err: any) {
      this.note(err?.message ?? String(err));
    }
  };

  escalateByDrag = async (e: Escalation, toLevelKey: string) => {
    this.laneRefusal = null;
    let from = (e.toLevel?.key as string) ?? 'L1';
    if (levelRank(toLevelKey) <= levelRank(from)) {
      this.laneRefusal = `De-escalation is not a move — resolve or cancel the ${from} escalation instead.`;
      return false;
    }
    try {
      let result = await new EscalateCaseCommand(this.commandContext).execute({
        subject: await this.byId(e.subjectId),
        fromLevelKey: from,
        toLevelKey,
        reason: 'agent-request',
        note: `Raised from the ladder by ${this.operatorName}`,
        raisedBy: await this.byId(this.args.model.operatorId),
        realm: this.realm,
      } as any);
      this.note((result as any).message);
    } catch (err: any) {
      this.laneRefusal = err?.message ?? String(err);
    }
    // Raising files a new escalation one rung up; the dragged one stays at
    // its level, so the board puts it back.
    return false;
  };

  acknowledge = async (e: Escalation) => {
    // Direct, attributed write: acknowledgement is the receiving human's own
    // act (not a lifecycle command's), stamped with the desk operator.
    (e as any).acknowledgedByName = this.operatorName;
    (e as any).acknowledgedAt = new Date();
    (e as any).status = 'acknowledged';
    await new SaveCardCommand(this.commandContext).execute({
      card: e,
    } as any);
    this.note(`${e.title} acknowledged by ${this.operatorName}`);
  };

  get setupIncomplete() {
    return !this.args.model.config?.setupCompletedAt;
  }

  <template>
    <Sidebar
      class='desk-shell'
      @label='Support Ops'
      @collapsible='offcanvas'
      @width='16rem'
      @mobileBreakpoint={{760}}
      @shortcut={{false}}
    >
      <:header>
        <div class='desk-brand'>
          <Avatar
            @name={{this.appTitle}}
            @shape='rounded'
            @size={{32}}
            aria-hidden='true'
          />
          <div class='desk-brand-text'>
            <p class='desk-kicker'>Support Case</p>
            <h1 class='desk-title'>{{this.appTitle}}</h1>
          </div>
        </div>
      </:header>
      <:nav>
        {{#each this.navGroups as |group|}}
          <SidebarGroup @label={{group.label}}>
            {{#each group.items as |item|}}
              <SidebarItem
                @label={{item.label}}
                @badge={{item.badge}}
                @active={{eq this.currentTab item.id}}
                @onClick={{fn this.goTab item.id}}
              />
            {{/each}}
          </SidebarGroup>
        {{/each}}
      </:nav>
      <:footer>
        <div class='desk-account'>
          <Avatar @name={{this.operatorName}} @size={{24}} />
          <p class='desk-account-text'>
            {{this.operatorName}}
            <small>At the desk</small>
          </p>
        </div>
      </:footer>
      <:default as |bar|>
        <main class='desk-main'>
          <div class='desk-topbar'>
            <SidebarTrigger
              @open={{bar.open}}
              @onToggle={{bar.toggle}}
              @controls={{bar.controls}}
              @label='navigation'
            />
          </div>
          <PageScaffold
            @title={{this.pageTitle}}
            @subtitle={{this.pageSubtitle}}
            @stats={{this.stats}}
          >
            <:actions>
              {{#if (eq this.currentTab 'agents')}}
                <Button
                  @tone='primary'
                  @appearance='accent'
                  {{on 'click' this.openAdd}}
                >+ Add agent</Button>
              {{else if (eq this.currentTab 'escalations')}}
                <Button
                  @tone='primary'
                  @appearance='accent'
                  {{on 'click' this.openRaise}}
                >+ Raise escalation</Button>
              {{else if this.showsAddCase}}
                <Button
                  @tone='primary'
                  @appearance='accent'
                  {{on 'click' this.createCase}}
                >+ Add case</Button>
              {{/if}}
            </:actions>
            <:alerts>
              {{#if this.setupIncomplete}}
                <Alert @tone='warning' class='desk-banner'>
                  Setup is not finished: the desk works, but ids, hours and
                  workflow come from defaults.
                  <Button
                    @tone='primary'
                    @appearance='link'
                    @size='s'
                    {{on 'click' (fn this.goTab 'setup')}}
                  >Continue setup</Button>
                </Alert>
              {{/if}}
              {{#if this.actionNote}}
                <p class='desk-note' role='status'>{{this.actionNote}}</p>
              {{/if}}
            </:alerts>
            <:default>
              <div class='desk-body'>
                {{#if (eq this.currentTab 'wall')}}
                  {{#if this.isLoading}}
                    <p class='desk-loading' role='status'>Loading the wall…</p>
                  {{else}}
                    <div class='wall'>
                      <Panel>
                        <:header>
                          <div class='panel-head'>
                            <h2>Breach risk</h2>
                            <p class='panel-meta'>{{this.wallBreachRows.length}}
                              nearest running clocks</p>
                          </div>
                        </:header>
                        <:default>

                          {{#if this.nearestBreach}}
                            <div class='strip'>
                              <LiveClock
                                @facts={{this.nearestBreach.timerFacts}}
                                class='strip-clock'
                              />
                              <p class='strip-case'>
                                <button
                                  type='button'
                                  class='link-button'
                                  {{on
                                    'click'
                                    (fn this.openCard this.nearestBreach.card)
                                  }}
                                >{{this.nearestBreach.label}}</button>
                                <span>Nearest breach ·
                                  {{this.nearestBreach.clockKind}}
                                  clock ·
                                  {{if
                                    this.nearestBreach.ownerName
                                    this.nearestBreach.ownerName
                                    'unassigned'
                                  }}</span>
                              </p>
                              {{#if this.nearestBreach.chipLabel}}
                                <StatusChip
                                  @value={{this.nearestBreach.chipLabel}}
                                  @tone={{this.severityTone
                                    this.nearestBreach.chipLabel
                                  }}
                                  @appearance='soft'
                                  @shape='pill'
                                  @dot={{false}}
                                />
                              {{/if}}
                              {{#if this.nearestBreach.onAssign}}
                                <Button
                                  @tone='primary'
                                  @appearance='filled'
                                  @size='xs'
                                  @shape='pill'
                                  {{on 'click' this.nearestBreach.onAssign}}
                                >Assign to me</Button>
                              {{/if}}
                            </div>
                          {{/if}}

                          <div class='table-wrap'>
                            <DataTable
                              @columns={{this.wallColumns}}
                              @rows={{this.wallBreachRows}}
                              @key={{this.breachKey}}
                              @label='Open cases ordered by time left on their running clock'
                              @onRowActivate={{this.openBreachRow}}
                              @columnMenu={{false}}
                              @sortable={{false}}
                              @striped={{false}}
                              @flush={{true}}
                            >
                              <:empty><EmptyState
                                  @size='s'
                                  @texture={{false}}
                                  @title='No clocks running'
                                /></:empty>
                              <:cell as |text row col|>
                                {{#if (eq col.key 'case')}}
                                  <button
                                    type='button'
                                    class='link-button row-id'
                                    {{on 'click' (fn this.openCard row.card)}}
                                  >{{this.shortId text}}</button>
                                {{else if (eq col.key 'subject')}}
                                  <span class='row-subject'>{{text}}</span>
                                {{else if (eq col.key 'severity')}}
                                  {{#if row.chipLabel}}
                                    <StatusChip
                                      @value={{row.chipLabel}}
                                      @tone={{this.severityTone row.chipLabel}}
                                      @appearance='soft'
                                      @shape='pill'
                                      @dot={{false}}
                                    />
                                  {{/if}}
                                {{else if (eq col.key 'consumed')}}
                                  <ProgressBar
                                    @value={{this.consumedOf row}}
                                    @max={{100}}
                                    @valueText={{concat
                                      (this.consumedOf row)
                                      '%'
                                    }}
                                  />
                                {{else if (eq col.key 'owner')}}
                                  {{#if row.ownerName}}
                                    <span class='owner'>
                                      <Avatar
                                        @name={{row.ownerName}}
                                        @size={{20}}
                                      />
                                      {{row.ownerName}}
                                    </span>
                                  {{else}}
                                    <span class='unowned'>Unassigned</span>
                                  {{/if}}
                                {{else}}
                                  {{text}}
                                {{/if}}
                              </:cell>
                            </DataTable>
                          </div>
                        </:default>
                      </Panel>

                      <div class='wall-side'>
                        <Panel>
                          <:header>
                            <div class='panel-head'>
                              <h2>Queue load</h2>
                              <p class='panel-meta'>open per queue</p>
                            </div>
                          </:header>
                          <:default>
                            <div>
                              <BarList
                                @rows={{this.queueLoad}}
                                @ranked={{false}}
                                @layout='track'
                                @label='Open cases by queue'
                              >
                                <:empty><p class='desk-empty'>No open cases.</p></:empty>
                              </BarList>
                            </div>
                          </:default>
                        </Panel>

                        <Panel>
                          <:header>
                            <div class='panel-head'>
                              <h2>Awaiting acknowledgement</h2>
                              <p
                                class='panel-meta'
                              >{{this.openEscalations.length}}
                                awaiting</p>
                            </div>
                          </:header>
                          <:default>
                            <div>
                              <ul class='ack-list'>
                                {{#each this.openEscalations as |e|}}
                                  <li>
                                    <Item
                                      @title={{this.ackTitle e}}
                                      @description={{this.ackDescription e}}
                                    >
                                      <:trailing><StatusChip
                                          @value={{this.ackDue e}}
                                          @tone={{this.ackTone e}}
                                          @appearance='soft'
                                          @shape='pill'
                                          @dot={{false}}
                                        /></:trailing>
                                      <:actions><Button
                                          @tone='neutral'
                                          @appearance='outlined'
                                          @size='xs'
                                          @shape='pill'
                                          {{on 'click' (fn this.acknowledge e)}}
                                        >Acknowledge</Button></:actions>
                                    </Item>
                                  </li>
                                {{else}}
                                  <li class='desk-empty'>✓ Every escalation
                                    acknowledged.</li>
                                {{/each}}
                              </ul>
                            </div>
                          </:default>
                        </Panel>
                      </div>
                    </div>
                  {{/if}}
                {{/if}}

                {{#if (eq this.currentTab 'queues')}}
                  <div class='toolbar'>
                    <SearchInput
                      class='toolbar-search'
                      @value={{this.queueSearch}}
                      @placeholder='Search case id, subject, owner or team'
                      @label='Search queues'
                      @size='s'
                      @onInput={{this.setQueueSearch}}
                    />
                    <FilterChips
                      @options={{this.queueChipOptions}}
                      @value={{this.queueSeverity}}
                      @onValueChange={{this.setQueueSeverity}}
                      @label='Filter by severity'
                      @size='s'
                      @appearance='solid'
                    />
                    <SegmentedControl
                      class='toolbar-view'
                      @size='s'
                      @appearance='tinted'
                      @label='Queue view'
                      @options={{QUEUE_VIEWS}}
                      @value={{this.queueView}}
                      @onValueChange={{this.setQueueView}}
                    />
                  </div>
                  {{#if (eq this.queueView 'lanes')}}
                    {{#if this.laneRefusal}}<p
                        class='desk-refusal'
                        role='alert'
                      >{{this.laneRefusal}}</p>{{/if}}
                    <Board
                      @boardLabel='Queues'
                      @cardSize='regular-tile'
                      @items={{this.queueItems}}
                      @columns={{this.queueColumns}}
                      @columnKeyFor={{this.queueKeyFor}}
                      @onMove={{this.routeToQueue}}
                      @onOpen={{this.openCard}}
                    >
                      <:card as |item|>
                        {{#let (this.queueRowFor item) as |row|}}
                          <div class='lane-tile'>
                            {{! The card's own fitted format is the face; the
                              desk adds only its clock and Claim underneath. }}
                            {{#let (this.faceFor item) as |Face|}}
                              <div class='lane-face'>{{#if Face}}<Face
                                    @format='fitted'
                                  />{{/if}}</div>
                            {{/let}}
                            <div class='lane-foot'>
                              {{#if row.timerFacts}}<LiveClock
                                  @facts={{row.timerFacts}}
                                  class='lcard-clock'
                                />{{else}}<span></span>{{/if}}
                              {{#unless row.ownerName}}
                                {{! The board takes pointer capture on pointerdown, so the button stops it there to keep its own click. }}
                                {{! template-lint-disable no-pointer-down-event-binding }}
                                <Button
                                  @tone='neutral'
                                  @appearance='outlined'
                                  @size='xs'
                                  @shape='pill'
                                  {{on 'pointerdown' this.shield}}
                                  {{on 'click' (fn this.claim item)}}
                                >Claim</Button>
                                {{! template-lint-enable no-pointer-down-event-binding }}
                              {{/unless}}
                            </div>
                          </div>
                        {{/let}}
                      </:card>
                    </Board>
                  {{else}}
                    <SupportQueue
                      @rows={{this.filteredQueueRows}}
                      @onOpen={{this.openCard}}
                      @onClaim={{this.claim}}
                      @onBatch={{this.batch}}
                    />
                  {{/if}}
                {{/if}}

                {{#if (eq this.currentTab 'board')}}
                  {{#if @model.defaultWorkflow}}
                    <WorkflowBoard
                      @workflow={{@model.defaultWorkflow}}
                      @cards={{this.boardCards}}
                      @onMove={{this.moveOnBoard}}
                      @onOpen={{this.openCard}}
                    />
                  {{else}}
                    <p class='desk-empty'>No workflow linked — Setup step 4
                      creates one, or link an existing Workflow card in edit.</p>
                  {{/if}}
                {{/if}}

                {{#if (eq this.currentTab 'cases')}}
                  <div class='collection'>
                    {{#if this.casesEmpty}}
                      <EmptyState
                        @size='s'
                        @texture={{false}}
                        @title='No cases yet'
                        @message='Add the first case to start the queue.'
                      >
                        <:action><Button
                            @tone='primary'
                            @appearance='accent'
                            {{on 'click' this.createCase}}
                          >+ Add case</Button></:action>
                      </EmptyState>
                    {{else}}
                      <div class='toolbar'>
                        <SearchInput
                          class='toolbar-search'
                          @value={{this.caseSearch}}
                          @placeholder='Search case id, subject or owner'
                          @label='Search cases'
                          @size='s'
                          @onInput={{this.setCaseSearch}}
                        />
                        <FilterChips
                          @options={{this.caseChipOptions}}
                          @value={{this.caseStatusFilter}}
                          @onValueChange={{this.setStatusFilter}}
                          @label='Filter by status'
                          @size='s'
                          @appearance='solid'
                        />
                        <SegmentedControl
                          class='toolbar-view'
                          @size='s'
                          @appearance='tinted'
                          @label='Case view'
                          @options={{CASE_VIEWS}}
                          @value={{this.caseView}}
                          @onValueChange={{this.setCaseView}}
                        />
                      </div>

                      {{#if (eq this.caseView 'table')}}
                        {{! The table is fed the client-side MIRROR of the wire query
                        (filteredCases): same row set as grid/list, drawn as
                        fields. Toggling views never changes which rows exist. }}
                        <Panel>
                          <:header>
                            <div class='panel-head'>
                              <h2>All cases</h2>
                              <p
                                class='panel-meta'
                              >{{this.filteredCases.length}}
                                of
                                {{this.cases.length}}
                                shown</p>
                            </div>
                          </:header>
                          <:default>
                            <DataTable
                              @columns={{this.caseColumns}}
                              @rows={{this.filteredCases}}
                              @key={{this.caseKey}}
                              @onRowActivate={{this.openRowCard}}
                              @label='Cases'
                              @columnMenu={{false}}
                              @sortable={{false}}
                              @striped={{false}}
                              @flush={{true}}
                            >
                              <:empty><EmptyState
                                  @size='s'
                                  @texture={{false}}
                                  @title='No cases match'
                                  @message='Clear the search or the status filter.'
                                /></:empty>
                              <:cell as |text row col|>
                                {{#if (eq col.key 'caseId')}}
                                  <button
                                    type='button'
                                    class='link-button row-id'
                                    {{on 'click' (fn this.openCard row)}}
                                  >{{text}}</button>
                                {{else if (eq col.key 'subject')}}
                                  <span class='row-subject'>{{text}}</span>
                                {{else if (eq col.key 'severity')}}
                                  {{#if row.severity}}
                                    <StatusChip
                                      @value={{row.severity}}
                                      @tone={{this.severityTone row.severity}}
                                      @appearance='soft'
                                      @shape='pill'
                                      @dot={{false}}
                                    />
                                  {{/if}}
                                {{else if (eq col.key 'owner')}}
                                  {{#if row.ownership.ownerName}}
                                    <span class='owner'><Avatar
                                        @name={{row.ownership.ownerName}}
                                        @size={{20}}
                                      />{{row.ownership.ownerName}}</span>
                                  {{else}}
                                    <span class='unowned'>Unassigned</span>
                                  {{/if}}
                                {{else}}
                                  {{text}}
                                {{/if}}
                              </:cell>
                            </DataTable>
                          </:default>
                        </Panel>
                      {{else}}
                        {{#if @context.searchResultsComponent}}
                          {{#let
                            (component @context.searchResultsComponent)
                            as |SearchResults|
                          }}
                            <SearchResults
                              @query={{this.caseWireQuery}}
                              @mode='none'
                              as |results|
                            >
                              <ul class='case-{{this.caseView}}'>
                                {{#each results.entries key='id' as |entry|}}
                                  <li class='case-cell'>
                                    <button
                                      type='button'
                                      class='case-open'
                                      aria-label='Open case'
                                      {{on
                                        'click'
                                        (fn this.openEntry entry.id)
                                      }}
                                    >
                                      <entry.component class='case-face' />
                                    </button>
                                  </li>
                                {{else}}
                                  {{#if results.isLoading}}
                                    <li
                                      class='desk-loading'
                                      role='status'
                                    >Loading cases…</li>
                                  {{else}}
                                    <li class='desk-empty'>No cases match —
                                      clear the search or the status filter.</li>
                                  {{/if}}
                                {{/each}}
                              </ul>
                            </SearchResults>
                          {{/let}}
                        {{/if}}
                      {{/if}}

                      <DeskCopilot
                        @candidates={{this.breachRiskCases}}
                        @titleOf={{this.titleOf}}
                        @repliesFor={{this.repliesFor}}
                        @operator={{@model.operator}}
                        @operatorName={{this.operatorName}}
                        @context={{@context}}
                        @realm={{this.realm}}
                        @onNote={{this.note}}
                      />
                    {{/if}}
                  </div>
                {{/if}}

                {{#if (eq this.currentTab 'escalations')}}
                  {{#if this.escalationsEmpty}}
                    <EmptyState
                      @size='s'
                      @texture={{false}}
                      @title='No escalations yet'
                      @message='Raise one from an open case.'
                    >
                      <:action><Button
                          @tone='primary'
                          @appearance='accent'
                          {{on 'click' this.openRaise}}
                        >+ Raise escalation</Button></:action>
                    </EmptyState>
                  {{else}}
                    <DeskEscalations
                      @escalations={{this.escalations}}
                      @isLoading={{this.escalationsLoading}}
                      @refusal={{this.laneRefusal}}
                      @onOpen={{this.openCard}}
                      @onAcknowledge={{this.acknowledge}}
                      @onEscalate={{this.escalateByDrag}}
                      @titleOf={{this.titleOf}}
                    />
                  {{/if}}
                  <Dialog
                    @open={{this.raiseOpen}}
                    @onClose={{this.closeRaise}}
                    @size='s'
                  >
                    <:title>Raise escalation</:title>
                    <:default>
                      {{! template-lint-disable no-invalid-interactive }}
                      <div class='add-agent' {{on 'keydown' this.raiseKeydown}}>
                        <h3 class='dlg-h'>Case</h3>
                        <div data-raise-search>
                          <SearchInput
                            @value={{this.raiseSearch}}
                            @placeholder='Search open cases'
                            @label='Search open cases'
                            @size='s'
                            @onInput={{this.setRaiseSearch}}
                          />
                        </div>
                        {{#if this.raiseCandidates.length}}
                          <ul class='pick-list' aria-label='Open cases'>
                            {{#each this.raiseCandidates as |c|}}
                              <li>
                                <button
                                  type='button'
                                  class='pick-row'
                                  aria-pressed={{if
                                    (eq c.id this.raiseCaseId)
                                    'true'
                                    'false'
                                  }}
                                  {{on 'click' (fn this.pickRaiseCase c)}}
                                >
                                  <StatusChip
                                    @value={{c.severity}}
                                    @tone={{this.severityTone c.severity}}
                                    @appearance='soft'
                                    @shape='pill'
                                    @dot={{false}}
                                  />
                                  {{#if c.caseId.value}}
                                    <span class='pick-id'>{{this.shortId
                                        c.caseId.value
                                      }}</span>
                                  {{else}}
                                    <span class='pick-id'>No ID yet</span>
                                  {{/if}}
                                  <span class='pick-name'>{{this.titleOf
                                      c
                                    }}</span>
                                  {{#if (this.caseLevel c)}}<StatusChip
                                      @value={{this.levelLabel
                                        (this.caseLevel c)
                                      }}
                                      @tone='neutral'
                                      @appearance='soft'
                                      @shape='pill'
                                      @dot={{false}}
                                    />{{/if}}
                                </button>
                              </li>
                            {{/each}}
                          </ul>
                        {{else}}
                          <p class='desk-empty'>No open cases to escalate.</p>
                        {{/if}}
                        {{#if this.raiseSelected}}
                          <h3 class='dlg-h'>Escalate to</h3>
                          <div class='to-row'>
                            <StatusChip
                              @value={{this.raiseFromLabel}}
                              @tone='neutral'
                              @appearance='soft'
                              @shape='pill'
                              @dot={{false}}
                            />
                            <ArrowRightIcon
                              width='16'
                              height='16'
                              aria-hidden='true'
                            />
                            <SegmentedControl
                              @size='s'
                              @appearance='tinted'
                              @label='Escalate to'
                              @options={{this.raiseLevelOptions}}
                              @value={{this.raiseLevelKey}}
                              @onValueChange={{this.setRaiseLevel}}
                            />
                          </div>
                          {{#if this.raiseLevelHelp}}<p
                              class='dlg-hint'
                            >{{this.raiseLevelHelp}}</p>{{/if}}
                          <h3 class='dlg-h'>Note (optional)</h3>
                          <Input
                            @value={{this.raiseNote}}
                            @placeholder='Raised from the Escalations tab by {{this.operatorName}}'
                            @onInput={{this.setRaiseNote}}
                            aria-label='Note'
                          />
                        {{/if}}
                      </div>
                    </:default>
                    <:footer>
                      <Button
                        @tone='neutral'
                        @appearance='outlined'
                        {{on 'click' this.closeRaise}}
                      >Cancel</Button>
                      <Button
                        @tone='primary'
                        @appearance='accent'
                        @disabled={{not this.canRaise}}
                        {{on 'click' this.confirmRaise}}
                      ><SirenIcon
                          width='14'
                          height='14'
                          aria-hidden='true'
                        />{{this.raiseConfirmLabel}}</Button>
                    </:footer>
                  </Dialog>
                {{/if}}

                {{#if (eq this.currentTab 'agents')}}
                  <div class='toolbar'>
                    <SearchInput
                      class='toolbar-search'
                      @value={{this.agentSearch}}
                      @placeholder='Search agents'
                      @label='Search agents'
                      @size='s'
                      @onInput={{this.setAgentSearch}}
                    />
                    <FilterChips
                      @options={{this.agentRoleOptions}}
                      @value={{this.agentRole}}
                      @onValueChange={{this.setAgentRole}}
                      @label='Filter by role'
                      @size='s'
                      @appearance='solid'
                    />
                    <SegmentedControl
                      @size='s'
                      @appearance='tinted'
                      @label='Duty status'
                      @options={{this.agentStatusOptions}}
                      @value={{this.agentStatus}}
                      @onValueChange={{this.setAgentStatus}}
                    />
                    <SegmentedControl
                      class='toolbar-view'
                      @size='s'
                      @appearance='tinted'
                      @label='Agent view'
                      @options={{this.agentViewOptions}}
                      @value={{this.agentView}}
                      @onValueChange={{this.setAgentView}}
                    />
                  </div>
                  {{#if this.isLoading}}
                    <p class='desk-loading' role='status'>Loading agents…</p>
                  {{else if this.agentTiles.length}}
                    {{#if (eq this.agentView 'list')}}
                      <Panel>
                        <:default>
                          <DataTable
                            @columns={{this.agentColumns}}
                            @rows={{this.agentTiles}}
                            @key={{this.agentKey}}
                            @onRowActivate={{this.openAgentRow}}
                            @label='Agents'
                            @columnMenu={{false}}
                            @sortable={{false}}
                            @striped={{false}}
                            @flush={{true}}
                          >
                            <:cell as |text row col|>
                              {{#if (eq col.key 'name')}}
                                <Button
                                  type='button'
                                  @tone='neutral'
                                  @appearance='plain'
                                  class='agent-person'
                                  {{on 'click' (fn this.openCard row.card)}}
                                >{{#let (this.faceFor row.card) as |Atom|}}{{#if
                                      Atom
                                    }}<Atom
                                        @format='atom'
                                        @displayContainer={{false}}
                                      />{{/if}}{{/let}}</Button>
                              {{else if (eq col.key 'status')}}
                                <StatusChip
                                  @value={{text}}
                                  @tone={{if row.onDuty 'success' 'neutral'}}
                                  @appearance='soft'
                                  @shape='pill'
                                  @dot={{false}}
                                />
                              {{else}}
                                {{text}}
                              {{/if}}
                            </:cell>
                          </DataTable>
                        </:default>
                      </Panel>
                    {{else}}
                      <Grid
                        @items={{this.agentTiles}}
                        @size='regular-tile'
                        as |tile Item|
                      >
                        <Item>
                          <div class='agent-cell'>
                            {{#let (this.faceFor tile.card) as |Face|}}
                              <div
                                class='agent-tile'
                                role='button'
                                tabindex='0'
                                {{on 'click' (fn this.openCard tile.card)}}
                                {{on 'keydown' (fn this.tileKeydown tile.card)}}
                              >{{#if Face}}<Face
                                    @format='fitted'
                                  />{{/if}}</div>
                            {{/let}}
                          </div>
                        </Item>
                      </Grid>
                    {{/if}}
                  {{else}}
                    <EmptyState
                      @size='s'
                      @texture={{false}}
                      @title={{if
                        this.agentFiltersActive
                        'No agents match'
                        'No agents yet'
                      }}
                      @message={{if
                        this.agentFiltersActive
                        'Clear the search or the filters.'
                        'Add members to a Role.'
                      }}
                    >
                      <:action>{{#unless this.agentFiltersActive}}<Button
                            @tone='primary'
                            @appearance='accent'
                            {{on 'click' this.openAdd}}
                          >+ Add agent</Button>{{/unless}}</:action>
                    </EmptyState>
                  {{/if}}
                  <Dialog
                    @open={{this.addOpen}}
                    @onClose={{this.closeAdd}}
                    @size='s'
                  >
                    <:title>Add agent</:title>
                    <:default>
                      {{! template-lint-disable no-invalid-interactive }}
                      <div class='add-agent' {{on 'keydown' this.addKeydown}}>
                        <h3 class='dlg-h'>Role</h3>
                        <RadioGroup
                          @options={{this.addRoleOptions}}
                          @value={{this.addRoleName}}
                          @onValueChange={{this.setAddRole}}
                          aria-label='Role'
                        />
                        <p class='dlg-hint'>They join this role and appear in
                          the agent pool.</p>
                        <SegmentedControl
                          @size='s'
                          @appearance='tinted'
                          @label='How to add'
                          @options={{this.addTabs}}
                          @value={{this.addTab}}
                          @onValueChange={{this.setAddTab}}
                        />
                        {{#if (eq this.addTab 'existing')}}
                          <div data-agent-search>
                            <SearchInput
                              @value={{this.addSearch}}
                              @placeholder='Search employees'
                              @label='Search employees'
                              @size='s'
                              @onInput={{this.setAddSearch}}
                            />
                          </div>
                          {{#if this.addCandidates.length}}
                            <ul class='pick-list' aria-label='Employees'>
                              {{#each this.addCandidates as |emp|}}
                                <li>
                                  <button
                                    type='button'
                                    class='pick-row'
                                    aria-pressed={{if
                                      (eq emp.id this.addEmployeeId)
                                      'true'
                                      'false'
                                    }}
                                    {{on 'click' (fn this.pickAddEmployee emp)}}
                                  >{{#let (this.faceFor emp) as |Atom|}}{{#if
                                        Atom
                                      }}<Atom
                                          @format='atom'
                                          @displayContainer={{false}}
                                        />{{/if}}{{/let}}</button>
                                </li>
                              {{/each}}
                            </ul>
                          {{else}}
                            <p class='desk-empty'>No other employees to add.</p>
                          {{/if}}
                        {{else}}
                          <p class='dlg-hint'>Create the employee, then fill in
                            their name, email, title and department on the card
                            that opens. They are added to this role right away.</p>
                        {{/if}}
                      </div>
                    </:default>
                    <:footer>
                      <Button
                        @tone='neutral'
                        @appearance='outlined'
                        {{on 'click' this.closeAdd}}
                      >Cancel</Button>
                      {{#if (eq this.addTab 'existing')}}
                        <Button
                          @tone='primary'
                          @appearance='accent'
                          @disabled={{not this.canAddAgent}}
                          {{on 'click' this.confirmAdd}}
                        >{{this.addConfirmLabel}}</Button>
                      {{else}}
                        <Button
                          @tone='primary'
                          @appearance='accent'
                          {{on 'click' this.createAgent}}
                        >Create employee</Button>
                      {{/if}}
                    </:footer>
                  </Dialog>
                {{/if}}

                {{#if (eq this.currentTab 'home')}}
                  <div class='home'>
                    <header class='home-head'>
                      <Avatar @name={{this.operatorName}} @size={{40}} />
                      <div>
                        <h2 class='home-greeting'>Morning,
                          {{this.operatorName}}</h2>
                        <p class='home-identity'>on duty</p>
                      </div>
                    </header>
                    <div class='home-rails'>
                      {{#each this.homeRails as |rail|}}
                        <Panel>
                          <:header>
                            <div class='panel-head'>
                              <h2>{{rail.title}}</h2>
                              <p class='panel-meta'>{{rail.items.length}}</p>
                            </div>
                          </:header>
                          <:default>
                            <ul class='ack-list'>
                              {{#each rail.items as |item|}}
                                <li>
                                  {{#if item.action}}
                                    <Item
                                      @title={{item.label}}
                                      @description={{item.meta}}
                                    >
                                      <:actions><Button
                                          @tone='neutral'
                                          @appearance='outlined'
                                          @size='xs'
                                          @shape='pill'
                                          {{on 'click' item.action.run}}
                                        >{{item.action.label}}</Button></:actions>
                                    </Item>
                                  {{else}}
                                    <button
                                      type='button'
                                      class='link-button home-row'
                                      {{on 'click' item.onOpen}}
                                    >
                                      <span>{{item.label}}</span>
                                      <span
                                        class='home-meta'
                                      >{{item.meta}}</span>
                                    </button>
                                  {{/if}}
                                </li>
                              {{else}}
                                <li class='desk-empty'>{{rail.emptyLabel}}</li>
                              {{/each}}
                            </ul>
                          </:default>
                        </Panel>
                      {{/each}}
                    </div>
                  </div>
                {{/if}}

                {{#if (eq this.currentTab 'setup')}}
                  <DeskSetup
                    @model={{this.app}}
                    @context={{@context}}
                    @onNote={{this.note}}
                    @roleCount={{this.count this.roleList.length}}
                    @agentCount={{this.count this.agentPool.length}}
                  />
                {{/if}}
              </div>
            </:default>
          </PageScaffold>
        </main>
      </:default>
    </Sidebar>
    <style scoped>
      @layer PretComponent {
        .desk-shell {
          height: 100%;
          background: var(--canvas);
          color: var(--foreground);
        }
        .desk-main {
          display: flex;
          flex-direction: column;
          height: 100%;
          min-width: 0;
        }
        .desk-brand {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-sm) var(--boxel-sp-sm) 0;
          color: var(--primary-ink);
        }
        .desk-brand-text {
          min-inline-size: 0;
        }
        .desk-kicker {
          margin: 0;
          font-size: var(--boxel-font-size-xs);
          font-weight: 600;
        }
        .desk-title {
          margin: 0;
          font-size: var(--boxel-font-size);
          font-weight: 600;
          line-height: 1.25;
        }
        .desk-topbar {
          display: flex;
          align-items: center;
          padding: var(--boxel-sp-xs) var(--boxel-sp-lg) 0;
        }
        /* the rail is always open from this width, so the trigger is only for offcanvas */
        @media (min-width: 760px) {
          .desk-topbar {
            display: none;
          }
        }
        .desk-account {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          font-size: var(--boxel-font-size-sm);
        }
        .desk-account-text {
          margin: 0;
        }
        .desk-account-text small {
          display: block;
          color: var(--muted-foreground);
          font-size: var(--boxel-font-size-xs);
        }
        .desk-body {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp);
          min-width: 0;
        }
        .desk-banner {
          margin: 0;
        }
        .desk-loading,
        .desk-empty {
          margin: 0;
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
        }
        .desk-note {
          margin: 0;
          padding: var(--boxel-sp-4xs) var(--boxel-sp-sm);
          border-left: 0.1875rem solid var(--primary);
          border-radius: 0 var(--radius) var(--radius) 0;
          background: color-mix(in oklab, var(--primary) 7%, var(--card));
          font-size: var(--boxel-font-size-xs);
          animation: note-in 260ms cubic-bezier(0.22, 1, 0.36, 1) both;
        }
        .desk-refusal {
          margin: 0;
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          border-left: 0.1875rem solid var(--destructive);
          border-radius: 0 var(--radius) var(--radius) 0;
          background: color-mix(in oklab, var(--destructive) 8%, var(--card));
          font-size: var(--boxel-font-size-sm);
        }

        /* ── Command Center: breach panel beside a side stack ── */
        .wall {
          display: grid;
          grid-template-columns: minmax(0, 1fr) 20rem;
          gap: var(--boxel-sp);
          align-items: start;
        }
        .wall-side {
          display: grid;
          gap: var(--boxel-sp);
          min-width: 0;
        }
        .panel-head {
          display: flex;
          align-items: center;
          justify-content: space-between;
          flex-wrap: wrap;
          gap: var(--boxel-sp-xs);
        }
        .panel-head h2 {
          margin: 0;
          font-size: var(--boxel-font-size);
          font-weight: 600;
        }
        .panel-meta {
          margin: 0;
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        .strip {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          gap: var(--boxel-sp-xs) var(--boxel-sp-sm);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          border-bottom: 1px solid var(--border);
          background: color-mix(in oklab, var(--muted) 60%, transparent);
        }
        .strip-clock {
          font-family: var(--font-mono);
          font-size: var(--boxel-font-size-lg);
          font-weight: 600;
          font-variant-numeric: tabular-nums;
          color: var(--destructive);
        }
        .strip-case {
          flex: 1;
          min-width: 12rem;
          display: grid;
          margin: 0;
          font-size: var(--boxel-font-size-sm);
        }
        .strip-case span {
          color: var(--muted-foreground);
          font-size: var(--boxel-font-size-xs);
        }
        .link-button {
          border: 0;
          background: none;
          padding: 0;
          font: inherit;
          font-weight: 600;
          color: var(--foreground);
          text-align: start;
          cursor: pointer;
        }
        .link-button:hover {
          color: var(--primary);
        }
        .link-button:focus-visible {
          outline: 2px solid var(--ring);
          outline-offset: 2px;
        }
        .home {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp);
        }
        .home-head {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
        }
        .home-greeting {
          margin: 0;
          font-size: var(--boxel-font-size-lg);
          font-weight: 600;
        }
        .home-identity {
          margin: 0;
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
        }
        .home-row {
          display: flex;
          justify-content: space-between;
          gap: var(--boxel-sp-xs);
          width: 100%;
        }
        .home-meta {
          flex: 0 1 40%;
          text-align: end;
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
        }
        .home-rails {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(16rem, 1fr));
          gap: var(--boxel-sp);
          align-items: start;
        }
        /* the name cell is the row's open control; the atom carries the look */
        .agent-person {
          --pretui-button-px: 0;
          --employee-atom-avatar-size: 2.25rem;
          max-width: 100%;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .dlg-h {
          margin: 0;
          font-size: var(--boxel-font-size-sm);
          font-weight: 600;
        }
        .dlg-hint {
          margin: 0;
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
        }
        .to-row {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
        }
        .pick-list {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-4xs);
          max-height: 14rem;
          overflow-y: auto;
          margin: 0;
          padding: 0;
          list-style: none;
        }
        .pick-row {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          width: 100%;
          margin: 0;
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          background: var(--card);
          color: inherit;
          font: inherit;
          text-align: start;
          cursor: pointer;
        }
        .pick-row:hover {
          background: var(--muted);
        }
        .pick-row[aria-pressed='true'] {
          border-color: var(--primary);
          background: var(--muted);
        }
        .pick-row:focus-visible {
          outline: 0.125rem solid var(--ring);
          outline-offset: 0.125rem;
        }
        .pick-id {
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
        }
        .pick-name {
          flex: 1;
          min-width: 0;
          font-weight: 600;
        }
        .add-agent {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp);
        }
        .agent-cell {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-4xs);
          height: 100%;
        }
        .agent-tile {
          /* one fixed fitted size (regular-tile, 250 x 170) so rows stay level */
          flex: none;
          height: 10.625rem;
          border-radius: var(--radius);
          overflow: hidden;
          box-shadow: var(--shadow-md);
          cursor: pointer;
        }
        .agent-tile:hover {
          box-shadow: var(--shadow-lg);
        }
        .agent-tile:focus-visible {
          outline: 0.125rem solid var(--ring);
          outline-offset: 0.125rem;
        }
        .toolbar {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          gap: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .toolbar-search {
          flex: 1 1 auto;
          min-width: 12rem;
          max-width: 24rem;
        }
        .toolbar-view {
          --pretui-seg-radius: var(--boxel-border-radius-pill);
        }
        .toolbar > :last-child {
          margin-left: auto;
        }
        .table-wrap {
          overflow-x: auto;
        }
        .owner {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-4xs);
          white-space: nowrap;
        }
        .unowned {
          color: var(--warning-ink);
          font-weight: 600;
          white-space: nowrap;
        }
        .row-id {
          white-space: nowrap;
          font-weight: 400;
          color: var(--muted-foreground);
        }
        .row-subject {
          font-weight: 600;
        }
        .ack-list {
          margin: 0;
          padding: 0;
          list-style: none;
          display: grid;
        }
        .ack-list li {
          padding: var(--boxel-sp-xs) 0;
          border-top: 1px solid var(--border);
        }
        .ack-list li:first-child {
          padding-top: 0;
          border-top: 0;
        }
        .ack-list li:last-child {
          padding-bottom: 0;
        }
        @container (width < 60rem) {
          .wall {
            grid-template-columns: minmax(0, 1fr);
          }
        }

        /* ── collection shell ── */
        .collection {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-xs);
        }
        .lane-tile {
          display: flex;
          flex-direction: column;
          height: 100%;
          min-height: 0;
        }
        .lane-face {
          flex: 1;
          min-height: 0;
        }
        .lane-foot {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: var(--boxel-sp-xs);
          box-sizing: border-box;
          min-height: 2.5rem;
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .lcard-unowned {
          color: var(--warning-ink);
          font-weight: 600;
        }
        .lcard-clock {
          font-size: var(--boxel-font-size-sm);
          font-weight: 600;
        }
        .case-grid {
          margin: 0;
          padding: 0;
          list-style: none;
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(15rem, 1fr));
          gap: var(--boxel-sp-xs);
        }
        .case-list {
          margin: 0;
          padding: 0;
          list-style: none;
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-4xs);
        }
        .case-grid .case-cell {
          height: 6.75rem;
        }
        .case-list .case-cell {
          height: 3.25rem;
        }
        .case-open {
          display: block;
          width: 100%;
          height: 100%;
          padding: 0;
          border: 1px solid var(--border);
          border-radius: var(--radius);
          background: var(--card);
          color: inherit;
          text-align: start;
          cursor: pointer;
          overflow: hidden;
        }
        .case-open:hover {
          border-color: var(--primary);
        }
        .case-open:focus-visible {
          outline: 2px solid var(--ring);
          outline-offset: 2px;
        }
        .case-face {
          width: 100%;
          height: 100%;
          pointer-events: none;
        }
        @keyframes note-in {
          from {
            opacity: 0;
            transform: translateY(-4px);
          }
          to {
            opacity: 1;
            transform: none;
          }
        }
        @media (prefers-reduced-motion: reduce) {
          .desk-note {
            animation: none;
          }
        }
      }
    </style>
  </template>

  subjectTitle = (e: Escalation) => e.subjectTitle ?? '?';
}
