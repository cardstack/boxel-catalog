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
  resolveRRIReference,
  searchEntryWireQueryFromQuery,
  type RealmResourceIdentifier,
  type SearchEntryWireQuery,
} from '@cardstack/runtime-common';
import { cached, tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { debounce } from 'lodash';
import { eq, not } from '@cardstack/boxel-ui/helpers';
import { Alert } from '@cardstack/pretui/components/alert';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { Button } from '@cardstack/pretui/components/button';
import {
  DataTable,
  type DataColumn,
} from '@cardstack/pretui/components/data-table';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { Item } from '@cardstack/pretui/components/item';
import { LayoutControl } from '@cardstack/pretui/components/layout-control';
import { Stat } from '@cardstack/pretui/components/stat';
import { ProgressBar } from '@cardstack/pretui/components/progress-bar';
import {
  Sidebar,
  SidebarGroup,
  SidebarItem,
  SidebarTrigger,
} from '@cardstack/pretui/components/sidebar';
import { SegmentedControl } from '@cardstack/pretui/components/segmented-control';
import { StatusChip } from '@cardstack/pretui/components/status-chip';

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
import { type HomeRail } from '@cardstack/catalog/components/workspace-home';
import { Board, type BoardColumn } from '@cardstack/catalog/components/board';
import ArrowRightIcon from '@cardstack/boxel-icons/arrow-right';
import SirenIcon from '@cardstack/boxel-icons/siren';
import PlusIcon from '@cardstack/boxel-icons/plus';
import LayoutGridIcon from '@cardstack/boxel-icons/layout-grid';
import ListIcon from '@cardstack/boxel-icons/list';
import KanbanIcon from '@cardstack/boxel-icons/kanban';
import TableIcon from '@cardstack/boxel-icons/table';
import UsersIcon from '@cardstack/boxel-icons/users';
import HouseIcon from '@cardstack/boxel-icons/house';
import SlidersHorizontalIcon from '@cardstack/boxel-icons/sliders-horizontal';
import { Input } from '@cardstack/pretui/components/input';
import { Dialog } from '@cardstack/pretui/components/dialog';
import { RadioGroup } from '@cardstack/pretui/components/radio-group';
import { Grid } from '@cardstack/pretui/components/grid';
import { FilterChips } from '@cardstack/pretui/components/filter-chips';
import { SearchInput } from '@cardstack/pretui/components/search-input';
import {
  timerSnapshot,
  sortByUrgency,
  type TimerFacts,
} from '../../service-desk/utils/sla';
import { getCard } from '@cardstack/catalog/utils/find-card';
import { mintIdentifier } from '@cardstack/catalog/fields/record-identifier/record-identifier-field';
import AssignOwnerCommand from '../../service-desk/commands/assign-owner-command';
import BatchTransformCommand from '../../service-desk/commands/batch-transform-command';
import RunWorkflowCommand from '../../service-desk/commands/run-workflow-command';
import EscalateCaseCommand from '../../service-desk/commands/escalate-case-command';
import {
  ESCALATION_LEVELS,
  levelRank,
} from '@cardstack/catalog/fields/escalation-level/escalation-level-field';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';

import { DeskSetup } from './desk-setup';
import { DeskCopilot } from './desk-copilot';
import { DeskEscalations } from './desk-escalations';
import type { SupportCaseApp } from '../support-case-app';

import { F, SEARCH_FORMS, VIEW_FORMS, shield } from './desk-forms';

// The rail, in the mock's order. `wall` is the Command Center.
const NAV = [
  { id: 'wall', label: 'Command Center', icon: LayoutGridIcon },
  { id: 'queues', label: 'Queues', icon: ListIcon },
  { id: 'board', label: 'Board', icon: KanbanIcon },
  { id: 'cases', label: 'Cases', icon: TableIcon },
  { id: 'escalations', label: 'Escalations', icon: SirenIcon },
  { id: 'agents', label: 'Agents', icon: UsersIcon },
  { id: 'home', label: 'My Desk', icon: HouseIcon },
  { id: 'setup', label: 'Setup', icon: SlidersHorizontalIcon },
] as const;

// Tabs whose secondary panels dock to the right edge.
const ASIDE_TABS = ['wall', 'cases', 'home'];

const CHIP_FORMS = F(['chips', 24], ['menu', 0]);
const ADD_FORMS = F(['label', 7], ['icon', 2]);

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
  // and not every Employee.
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
  agentKey = (t: { id: string }) => t.id;
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

  /** Stored ids may be absolute or realm-relative ("../Employee/dana-kim");
      resolve the relative one against the other and compare the results. */
  sameCard = (a?: string | null, b?: string | null): boolean => {
    if (!a || !b) return false;
    return (
      a === b ||
      resolveRRIReference(a, b as RealmResourceIdentifier) === b ||
      resolveRRIReference(b, a as RealmResourceIdentifier) === a
    );
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
  get wallStats() {
    return [
      {
        label: 'Open cases',
        value: this.count(this.openCases.length),
        tone: 'neutral' as const,
        hint: `across ${plural(this.wallQueues.length, 'queue')}`,
      },
      {
        label: '≥ 75% consumed',
        value: this.count(this.atRiskCount),
        tone: 'warning' as const,
        hint: this.atRiskCount ? 'at risk' : 'none at risk',
      },
      {
        label: 'Breached',
        value: this.count(this.breachedCount),
        tone: 'danger' as const,
        hint: 'clocks past target',
      },
      {
        label: 'Clocks met',
        value: this.count(this.metTodayCount),
        tone: 'success' as const,
        hint: `of ${plural(this.slas.length, 'clock')}`,
      },
      {
        label: 'Awaiting ack',
        value: this.count(this.openEscalations.length),
        tone: 'warning' as const,
        hint: `${this.overdueAckCount} overdue`,
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
    let max = Math.max(1, ...this.wallQueues.map((q) => q.open));
    return this.wallQueues.map((q) => ({
      ...q,
      max,
      hue: q.overloaded ? 'var(--warning)' : 'var(--foreground)',
      meta: `${q.open} · ${plural(q.agents, 'agent')}`,
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
  caseIdOf = (item: CardDef) => (item as Case).caseId?.value;
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
        emptyLabel: 'Every escalation acknowledged.',
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
        emptyLabel: 'No clocks at risk.',
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

  get appTitle(): string {
    return (
      this.args.model.appName ?? this.args.model.cardTitle ?? 'Support Ops'
    );
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

  get hasAside() {
    return ASIDE_TABS.includes(this.currentTab);
  }

  get hasFilters() {
    return ['queues', 'cases', 'agents'].includes(this.currentTab);
  }

  /** The tab's one primary action, pinned at the end of the toolbar. */
  get primaryAction() {
    switch (this.currentTab) {
      case 'agents':
        return { label: 'Add agent', run: this.openAdd };
      default:
        return { label: 'Add case', run: this.createCase };
    }
  }

  get homeMainRails() {
    return this.homeRails.slice(0, -1);
  }
  get homeAsideRail() {
    return this.homeRails[this.homeRails.length - 1];
  }

  // ── actions ────────────────────────────────────────────────────────
  goTab = (id: string) => {
    this.currentTab = id;
    this.actionNote = null;
  };

  // The Board takes pointer capture on pointerdown, which redirects a
  // control's click to the board and opens the card instead. Stopping
  // pointerdown on the control keeps its own click.
  shield = shield;

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
  openEntry = (id: string) => {
    let card = [...this.cases, ...this.escalations].find((c) => c.id === id);
    if (card) this.view(card);
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
      @collapsible='rail'
      @railBreakpoint={{1100}}
      @mobileBreakpoint={{720}}
      @scroll='content'
      @resizable={{true}}
      @width='13.5rem'
      @shortcut={{false}}
    >
      <:header as |bar|>
        <div class='desk-brand'>
          <span class='desk-mark' aria-hidden='true'>SC</span>
          {{#unless bar.collapsed}}
            <p class='desk-brand-text'>
              <small>Support Case</small>
              {{this.appTitle}}
            </p>
          {{/unless}}
        </div>
      </:header>
      <:nav as |bar|>
        <SidebarGroup>
          {{#each this.navItems as |item|}}
            <SidebarItem
              @label={{item.label}}
              @icon={{item.icon}}
              @badge={{unless bar.collapsed item.badge}}
              @active={{eq this.currentTab item.id}}
              @collapsed={{bar.collapsed}}
              @onClick={{fn this.goTab item.id}}
            />
          {{/each}}
        </SidebarGroup>
      </:nav>
      <:footer as |bar|>
        <div class='desk-account'>
          <Avatar @name={{this.operatorName}} @size={{24}} />
          {{#unless bar.collapsed}}
            <p class='desk-account-text'>
              {{this.operatorName}}
              <small>At the desk</small>
            </p>
          {{/unless}}
        </div>
      </:footer>
      <:default as |bar|>
        <div class='desk-layout {{if this.hasAside "has-aside"}}'>
          <div class='desk-main'>
            {{#if bar.mobile}}
              <SidebarTrigger
                @open={{bar.open}}
                @onToggle={{bar.toggle}}
                @controls={{bar.controls}}
                @label='navigation'
              />
            {{/if}}
            <header class='desk-head'>
              <p class='desk-eyebrow'>{{this.appTitle}} · Desk</p>
              <h2 class='desk-h1'>{{this.pageTitle}}</h2>
              {{#if this.pageSubtitle}}
                <p class='desk-sub'>{{this.pageSubtitle}}</p>
              {{/if}}
            </header>

            {{#if this.setupIncomplete}}
              <Alert @tone='warning' class='desk-banner'>
                <strong>Setup incomplete</strong>
                <span class='desk-banner-text'>Setup is not finished: the desk
                  works, but ids, hours and workflow come from defaults.</span>
                <Button
                  @tone='neutral'
                  @appearance='plain'
                  @size='s'
                  {{on 'click' (fn this.goTab 'setup')}}
                >Continue setup</Button>
              </Alert>
            {{/if}}
            <p class='desk-note' role='status'>{{this.actionNote}}</p>

            {{#if (eq this.currentTab 'wall')}}
              <section class='desk-stats' aria-label='Desk totals'>
                <div class='desk-stat-cells'>
                  {{#each this.wallStats as |st|}}
                    <div class='desk-stat'>
                      <Stat
                        @label={{st.label}}
                        @value={{st.value}}
                        @tone={{st.tone}}
                        @hint={{st.hint}}
                        @roll={{false}}
                      />
                    </div>
                  {{/each}}
                </div>
              </section>
            {{/if}}

            {{#unless (eq this.currentTab 'escalations')}}
              <LayoutControl
                @label='{{this.pageTitle}} tools'
                @controlHeight='1.625rem'
                as |lc|
              >
                {{#if (eq this.currentTab 'queues')}}
                  <lc.Slot
                    @id='search'
                    @priority={{2}}
                    @forms={{SEARCH_FORMS}}
                    @label='Search'
                    as |form|
                  >
                    <div class='desk-search'><SearchInput
                        @display={{if
                          (eq form 'collapsed')
                          'collapsed'
                          'field'
                        }}
                        @value={{this.queueSearch}}
                        @placeholder='Search case id, subject, owner or team'
                        @onInput={{this.setQueueSearch}}
                      /></div>
                  </lc.Slot>
                  <lc.Slot
                    @id='severity'
                    @priority={{3}}
                    @forms={{CHIP_FORMS}}
                    @label='Severity'
                  >
                    <FilterChips
                      @options={{this.queueChipOptions}}
                      @value={{this.queueSeverity}}
                      @onValueChange={{this.setQueueSeverity}}
                      @label='Filter by severity'
                    />
                  </lc.Slot>
                  <lc.Slot
                    @id='view'
                    @priority={{1}}
                    @forms={{VIEW_FORMS}}
                    @label='View'
                  >
                    <SegmentedControl
                      @label='Queue view'
                      @options={{QUEUE_VIEWS}}
                      @value={{this.queueView}}
                      @onValueChange={{this.setQueueView}}
                    />
                  </lc.Slot>
                {{else if (eq this.currentTab 'cases')}}
                  <lc.Slot
                    @id='search'
                    @priority={{2}}
                    @forms={{SEARCH_FORMS}}
                    @label='Search'
                    as |form|
                  >
                    <div class='desk-search'><SearchInput
                        @display={{if
                          (eq form 'collapsed')
                          'collapsed'
                          'field'
                        }}
                        @value={{this.caseSearch}}
                        @placeholder='Search case id, subject or owner'
                        @onInput={{this.setCaseSearch}}
                      /></div>
                  </lc.Slot>
                  <lc.Slot
                    @id='status'
                    @priority={{3}}
                    @forms={{CHIP_FORMS}}
                    @label='Status'
                  >
                    <FilterChips
                      @options={{this.caseChipOptions}}
                      @value={{this.caseStatusFilter}}
                      @onValueChange={{this.setStatusFilter}}
                      @label='Filter by status'
                    />
                  </lc.Slot>
                  <lc.Slot
                    @id='view'
                    @priority={{1}}
                    @forms={{VIEW_FORMS}}
                    @label='View'
                  >
                    <SegmentedControl
                      @label='Case view'
                      @options={{CASE_VIEWS}}
                      @value={{this.caseView}}
                      @onValueChange={{this.setCaseView}}
                    />
                  </lc.Slot>
                {{else if (eq this.currentTab 'agents')}}
                  <lc.Slot
                    @id='search'
                    @priority={{2}}
                    @forms={{SEARCH_FORMS}}
                    @label='Search'
                    as |form|
                  >
                    <div class='desk-search'><SearchInput
                        @display={{if
                          (eq form 'collapsed')
                          'collapsed'
                          'field'
                        }}
                        @value={{this.agentSearch}}
                        @placeholder='Search agents'
                        @onInput={{this.setAgentSearch}}
                      /></div>
                  </lc.Slot>
                  <lc.Slot
                    @id='role'
                    @priority={{3}}
                    @forms={{CHIP_FORMS}}
                    @label='Role'
                  >
                    <FilterChips
                      @options={{this.agentRoleOptions}}
                      @value={{this.agentRole}}
                      @onValueChange={{this.setAgentRole}}
                      @label='Filter by role'
                    />
                  </lc.Slot>
                  <lc.Slot
                    @id='duty'
                    @priority={{4}}
                    @forms={{VIEW_FORMS}}
                    @label='Duty'
                  >
                    <SegmentedControl
                      @label='Duty status'
                      @options={{this.agentStatusOptions}}
                      @value={{this.agentStatus}}
                      @onValueChange={{this.setAgentStatus}}
                    />
                  </lc.Slot>
                  <lc.Slot
                    @id='view'
                    @priority={{1}}
                    @forms={{VIEW_FORMS}}
                    @label='View'
                  >
                    <SegmentedControl
                      @label='Agent view'
                      @options={{this.agentViewOptions}}
                      @value={{this.agentView}}
                      @onValueChange={{this.setAgentView}}
                    />
                  </lc.Slot>
                {{/if}}
                <lc.Slot
                  @id='add'
                  @priority={{0}}
                  @pinned={{true}}
                  @forms={{ADD_FORMS}}
                  @label={{this.primaryAction.label}}
                  as |form|
                >
                  <Button
                    class='desk-add'
                    @icon={{PlusIcon}}
                    @tone='primary'
                    @appearance='accent'
                    @size='s'
                    @display={{if (eq form 'icon') 'icon' 'label'}}
                    @label={{this.primaryAction.label}}
                    {{on 'click' this.primaryAction.run}}
                  >{{this.primaryAction.label}}</Button>
                </lc.Slot>
              </LayoutControl>
            {{/unless}}

            <div class='desk-body'>
              {{#if (eq this.currentTab 'wall')}}
                {{#if this.isLoading}}
                  <p class='desk-loading' role='status'>Loading the wall…</p>
                {{else}}
                  <section class='desk-block' aria-labelledby='breach-h'>
                    <div class='block-head'>
                      <h2 id='breach-h'>Breach risk</h2>
                      <p class='block-meta'>{{this.wallBreachRows.length}}
                        nearest running clocks</p>
                    </div>
                    {{#if this.nearestBreach}}
                      <div class='strip'>
                        <LiveClock
                          @facts={{this.nearestBreach.timerFacts}}
                          class='strip-clock'
                        />
                        <p class='strip-case'>
                          <Button
                            class='link-button'
                            @tone='neutral'
                            @appearance='link'
                            @size='s'
                            {{on
                              'click'
                              (fn this.openCard this.nearestBreach.card)
                            }}
                          >{{this.nearestBreach.label}}</Button>
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
                            @appearance='plain'
                          />
                        {{/if}}
                        {{#if this.nearestBreach.onAssign}}
                          <Button
                            @tone='primary'
                            @appearance='accent'
                            @size='s'
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
                            <Button
                              class='link-button row-id'
                              @tone='neutral'
                              @appearance='link'
                              @size='s'
                              {{on 'click' (fn this.openCard row.card)}}
                            >{{this.shortId text}}</Button>
                          {{else if (eq col.key 'subject')}}
                            <span class='row-subject'>{{text}}</span>
                          {{else if (eq col.key 'severity')}}
                            {{#if row.chipLabel}}
                              <StatusChip
                                @value={{row.chipLabel}}
                                @tone={{this.severityTone row.chipLabel}}
                                @appearance='plain'
                              />
                            {{/if}}
                          {{else if (eq col.key 'consumed')}}
                            <ProgressBar
                              @value={{this.consumedOf row}}
                              @max={{100}}
                              @valueText={{concat (this.consumedOf row) '%'}}
                            />
                          {{else if (eq col.key 'owner')}}
                            {{#if row.ownerName}}
                              <span class='owner'>
                                <Avatar @name={{row.ownerName}} @size={{20}} />
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
                  </section>
                {{/if}}
              {{/if}}

              {{#if (eq this.currentTab 'queues')}}
                {{#if (eq this.queueView 'lanes')}}
                  {{#if this.laneRefusal}}<p
                      class='desk-refusal'
                      role='alert'
                    >{{this.laneRefusal}}</p>{{/if}}
                  <Board
                    @boardLabel='Queues'
                    @cardSize='double-strip'
                    @items={{this.queueItems}}
                    @columns={{this.queueColumns}}
                    @columnKeyFor={{this.queueKeyFor}}
                    @onMove={{this.routeToQueue}}
                    @onOpen={{this.openCard}}
                  >
                    <:card as |item|>
                      {{#let (this.queueRowFor item) as |row|}}
                        <div class='lane-row'>
                          <span class='lane-title'>{{this.titleOf item}}</span>
                          {{#if row.timerFacts}}<LiveClock
                              @facts={{row.timerFacts}}
                              class='lcard-clock'
                            />{{/if}}
                          <span class='lane-meta'>{{#if
                              row.chipLabel
                            }}<StatusChip
                                @value={{row.chipLabel}}
                                @tone={{this.severityTone row.chipLabel}}
                                @appearance='plain'
                              />{{/if}}{{if
                              (this.caseIdOf item)
                              (this.shortId (this.caseIdOf item))
                              'No ID'
                            }}
                            ·
                            {{if
                              row.ownerName
                              row.ownerName
                              'Unassigned'
                            }}</span>
                          {{#unless row.ownerName}}
                            {{! The board takes pointer capture on pointerdown, so the button stops it there to keep its own click. }}
                            {{! template-lint-disable no-pointer-down-event-binding }}
                            <Button
                              class='lane-claim'
                              @tone='neutral'
                              @appearance='plain'
                              @size='xs'
                              {{on 'pointerdown' this.shield}}
                              {{on 'click' (fn this.claim item)}}
                            >Claim</Button>
                            {{! template-lint-enable no-pointer-down-event-binding }}
                          {{/unless}}
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
                          @icon={{PlusIcon}}
                          {{on 'click' this.createCase}}
                        >Add case</Button></:action>
                    </EmptyState>
                  {{else}}

                    {{#if (eq this.caseView 'table')}}
                      {{! The table is fed the client-side MIRROR of the wire query
                        (filteredCases): same row set as grid/list, drawn as
                        fields. Toggling views never changes which rows exist. }}
                      <section class='desk-block'>
                        <div class='block-head'>
                          <h2>All cases</h2>
                          <p class='block-meta'>{{this.filteredCases.length}}
                            of
                            {{this.cases.length}}
                            shown</p>
                        </div>
                        <DataTable
                          @columns={{this.caseColumns}}
                          @rows={{this.filteredCases}}
                          @key={{this.caseKey}}
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
                              <Button
                                class='link-button row-id'
                                @tone='neutral'
                                @appearance='link'
                                @size='s'
                                {{on 'click' (fn this.openCard row)}}
                              >{{text}}</Button>
                            {{else if (eq col.key 'subject')}}
                              <span class='row-subject'>{{text}}</span>
                            {{else if (eq col.key 'severity')}}
                              {{#if row.severity}}
                                <StatusChip
                                  @value={{row.severity}}
                                  @tone={{this.severityTone row.severity}}
                                  @appearance='plain'
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
                      </section>
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
                                    {{on 'click' (fn this.openEntry entry.id)}}
                                  >
                                    <entry.component class='case-face' />
                                  </button>
                                </li>
                              {{else}}
                                {{#if results.isLoading}}
                                  <li class='desk-loading' role='status'>Loading
                                    cases…</li>
                                {{else}}
                                  <li class='desk-empty'>No cases match — clear
                                    the search or the status filter.</li>
                                {{/if}}
                              {{/each}}
                            </ul>
                          </SearchResults>
                        {{/let}}
                      {{/if}}
                    {{/if}}
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
                        @icon={{PlusIcon}}
                        {{on 'click' this.openRaise}}
                      >Raise escalation</Button></:action>
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
                    @onRaise={{this.openRaise}}
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
                                  @appearance='plain'
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
                                    @appearance='plain'
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
                            @appearance='plain'
                          />
                          <ArrowRightIcon
                            class='to-arrow'
                            width='16'
                            height='16'
                            aria-hidden='true'
                          />
                          <SegmentedControl
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
                      @icon={{SirenIcon}}
                      @disabled={{not this.canRaise}}
                      {{on 'click' this.confirmRaise}}
                    >{{this.raiseConfirmLabel}}</Button>
                  </:footer>
                </Dialog>
              {{/if}}

              {{#if (eq this.currentTab 'agents')}}
                {{#if this.isLoading}}
                  <p class='desk-loading' role='status'>Loading agents…</p>
                {{else if this.agentTiles.length}}
                  {{#if (eq this.agentView 'list')}}
                    <section class='desk-block'>
                      <DataTable
                        @columns={{this.agentColumns}}
                        @rows={{this.agentTiles}}
                        @key={{this.agentKey}}
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
                              @appearance='plain'
                            />
                          {{else}}
                            {{text}}
                          {{/if}}
                        </:cell>
                      </DataTable>
                    </section>
                  {{else}}
                    <Grid
                      @items={{this.agentTiles}}
                      @size='regular-tile'
                      as |tile Item|
                    >
                      <Item>
                        <div class='agent-cell'>
                          {{#let (this.faceFor tile.card) as |Face|}}
                            <button
                              type='button'
                              class='agent-tile'
                              {{on 'click' (fn this.openCard tile.card)}}
                            >{{#if Face}}<Face
                                  @format='fitted'
                                />{{/if}}</button>
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
                          @icon={{PlusIcon}}
                          {{on 'click' this.openAdd}}
                        >Add agent</Button>{{/unless}}</:action>
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
                      <p class='dlg-hint'>They join this role and appear in the
                        agent pool.</p>
                      <SegmentedControl
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
                  <div class='home-head'>
                    <Avatar @name={{this.operatorName}} @size={{40}} />
                    <div>
                      <h2 class='home-greeting'>Morning,
                        {{this.operatorName}}</h2>
                      <p class='home-identity'>on duty</p>
                    </div>
                  </div>
                  <div class='home-rails'>
                    {{#each this.homeMainRails as |rail|}}
                      <section class='desk-block'>
                        <div class='block-head'>
                          <h2>{{rail.title}}</h2>
                          <p class='block-meta'>{{rail.items.length}}</p>
                        </div>
                        <ul class='rows'>
                          {{#each rail.items as |item|}}
                            <li>
                              {{#if item.action}}
                                <Item
                                  @title={{item.label}}
                                  @description={{item.meta}}
                                >
                                  <:actions><Button
                                      @tone='neutral'
                                      @appearance='plain'
                                      @size='s'
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
                                  <span class='home-meta'>{{item.meta}}</span>
                                </button>
                              {{/if}}
                            </li>
                          {{else}}
                            <li class='desk-empty'>{{rail.emptyLabel}}</li>
                          {{/each}}
                        </ul>
                      </section>
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
          </div>
          {{#if this.hasAside}}
            <aside
              class='desk-aside'
              aria-label='{{this.pageTitle}} side panel'
            >
              {{#if (eq this.currentTab 'wall')}}
                <section class='aside-block' aria-labelledby='load-h'>
                  <div class='block-head'>
                    <h2 id='load-h'>Queue load</h2>
                    <p class='block-meta'>open per queue</p>
                  </div>
                  <ul class='rows'>
                    {{#each this.queueLoad as |q|}}
                      <li class='load-row'>
                        <span class='load-name'>{{q.name}}</span>
                        <span class='load-meta'>{{q.meta}}</span>
                        <ProgressBar
                          class='load-bar'
                          @value={{q.open}}
                          @max={{q.max}}
                          @hue={{q.hue}}
                          aria-label='{{q.name}} load'
                        />
                      </li>
                    {{else}}
                      <li class='desk-empty'>No open cases.</li>
                    {{/each}}
                  </ul>
                </section>
                <section class='aside-block' aria-labelledby='ack-h'>
                  <div class='block-head'>
                    <h2 id='ack-h'>Awaiting acknowledgement</h2>
                    <p class='block-meta'>{{plural
                        this.openEscalations.length
                        'escalation'
                      }}</p>
                  </div>
                  <ul class='rows'>
                    {{#each this.openEscalations as |e|}}
                      <li>
                        <Item
                          @title={{this.ackTitle e}}
                          @description={{this.ackDescription e}}
                        >
                          <:trailing><StatusChip
                              @value={{this.ackDue e}}
                              @tone={{this.ackTone e}}
                              @appearance='plain'
                            /></:trailing>
                          <:actions><Button
                              @tone='neutral'
                              @appearance='plain'
                              @size='s'
                              {{on 'click' (fn this.acknowledge e)}}
                            >Acknowledge</Button></:actions>
                        </Item>
                      </li>
                    {{else}}
                      <li class='desk-empty'>Every escalation acknowledged.</li>
                    {{/each}}
                  </ul>
                </section>
              {{else if (eq this.currentTab 'cases')}}
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
              {{else if (eq this.currentTab 'home')}}
                {{#let this.homeAsideRail as |rail|}}
                  <section class='aside-block' aria-labelledby='owned-h'>
                    <div class='block-head'>
                      <h2 id='owned-h'>{{rail.title}}</h2>
                      <p class='block-meta'>{{rail.items.length}}</p>
                    </div>
                    <ul class='rows'>
                      {{#each rail.items as |item|}}
                        <li>
                          <button
                            type='button'
                            class='link-button home-row'
                            {{on 'click' item.onOpen}}
                          >
                            <span>{{item.label}}</span>
                            <span class='home-meta'>{{item.meta}}</span>
                          </button>
                        </li>
                      {{else}}
                        <li class='desk-empty'>{{rail.emptyLabel}}</li>
                      {{/each}}
                    </ul>
                  </section>
                {{/let}}
              {{/if}}
            </aside>
          {{/if}}
        </div>
      </:default>
    </Sidebar>
    <style scoped>
      .desk-shell {
        container-type: inline-size;
        block-size: 100%;
        min-block-size: 0;
        background: var(--background);
        color: var(--foreground);
        font-family: var(--font-sans);
        font-size: var(--boxel-font-size-xs);
      }
      .desk-brand {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
      }
      .desk-mark {
        display: grid;
        place-items: center;
        flex: none;
        inline-size: 1.75rem;
        block-size: 1.75rem;
        border: 1px solid var(--border);
        border-radius: var(--radius);
        font-family: var(--font-mono);
        font-size: 0.5625rem; /* ladder 9px label: no Boxel token below 11px */
        font-weight: 600;
        line-height: 1;
      }
      .desk-brand-text {
        display: grid;
        min-inline-size: 0;
        font-weight: 700;
        line-height: 1.2;
      }
      .desk-brand-text small,
      .desk-eyebrow {
        font-family: var(--font-mono);
        font-size: 0.5625rem; /* ladder 9px label: no Boxel token below 11px */
        font-weight: 600;
        line-height: 1.3;
        letter-spacing: 0.13em;
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .desk-account {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
      }
      .desk-account-text {
        font-weight: 600;
      }
      .desk-account-text small {
        display: block;
        font-weight: 400;
        color: var(--muted-foreground);
      }

      /* main column + a right panel docked flush to the edge */
      .desk-layout {
        display: grid;
        grid-template-columns: minmax(0, 1fr);
        min-block-size: 100%;
      }
      .desk-layout.has-aside {
        grid-template-columns: minmax(0, 1fr) 18.75rem;
      }
      .desk-main {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
        min-inline-size: 0;
        padding: var(--boxel-sp-lg) var(--boxel-sp-lg) var(--boxel-sp-xl);
      }
      .desk-aside {
        min-inline-size: 0;
        border-inline-start: 1px solid var(--border);
        background: var(--card);
        color: var(--card-foreground);
      }
      @container (width < 60rem) {
        .desk-layout.has-aside {
          grid-template-columns: minmax(0, 1fr);
        }
        .desk-aside {
          border-inline-start: 0;
          border-block-start: 1px solid var(--border);
        }
      }

      .desk-head {
        display: grid;
        gap: var(--boxel-sp-4xs);
      }
      .desk-eyebrow,
      .desk-sub {
        margin: 0;
      }
      .desk-h1 {
        font-family: var(--boxel-heading-font-family);
        font-weight: 400;
        font-size: 2.5rem; /* ladder 40px page title: no Boxel display token */
        line-height: 1;
        text-transform: uppercase;
      }
      .desk-sub {
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
      }
      .desk-banner {
        margin: 0;
      }
      .desk-banner-text {
        flex: 1;
        min-inline-size: 0;
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
      }

      /* stat strip: every cell draws its right and bottom line and the frame
         clips the overhang, so a wrapped last row keeps all its dividers */
      .desk-stats {
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
        overflow: hidden;
      }
      .desk-stat-cells {
        --text-stat: 1.375rem;
        display: grid;
        grid-template-columns: repeat(5, minmax(0, 1fr));
        margin: 0 -1px -1px 0;
      }
      .desk-stat {
        min-inline-size: 0;
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        box-shadow:
          1px 0 0 var(--border),
          0 1px 0 var(--border);
      }
      @container (width <= 48rem) {
        .desk-stat-cells {
          grid-template-columns: repeat(3, minmax(0, 1fr));
        }
      }
      @container (width <= 30rem) {
        .desk-stat-cells {
          grid-template-columns: repeat(2, minmax(0, 1fr));
        }
      }
      .desk-search {
        inline-size: 15rem;
      }
      .desk-add {
        margin-inline-start: auto;
      }

      .desk-body {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
        min-inline-size: 0;
      }
      /* one flat block: radius on the outside only, hairline sections inside */
      .desk-block {
        min-inline-size: 0;
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
        color: var(--card-foreground);
        overflow: hidden;
      }
      .aside-block + .aside-block {
        border-block-start: 1px solid var(--border);
      }
      .block-head {
        display: flex;
        align-items: baseline;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        border-block-end: 1px solid var(--border);
      }
      .block-head h2 {
        margin: 0;
        font-size: var(--boxel-font-size-xs);
        font-weight: 700;
      }
      .block-meta {
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
      }
      .load-row {
        display: grid;
        grid-template-columns: minmax(0, 1fr) auto;
        align-items: baseline;
        gap: var(--boxel-sp-5xs) var(--boxel-sp-xs);
      }
      .load-meta {
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-2xs);
        font-variant-numeric: tabular-nums;
        color: var(--muted-foreground);
      }
      .load-bar {
        grid-column: 1 / -1;
      }
      .rows {
        display: grid;
        margin: 0;
        padding: 0;
        list-style: none;
      }
      .rows > li {
        padding: var(--boxel-sp-4xs) var(--boxel-sp-sm);
        border-block-start: 1px solid var(--border);
      }
      .rows > li:first-child {
        border-block-start: 0;
      }

      .desk-loading,
      .desk-empty {
        margin: 0;
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
      }
      .rows > .desk-empty {
        padding-block: var(--boxel-sp-xs);
      }
      .desk-note,
      .desk-refusal {
        margin: 0;
        padding: var(--boxel-sp-4xs) var(--boxel-sp-sm);
        border: 1px solid var(--border);
        border-inline-start: 0.1875rem solid var(--primary);
        border-radius: var(--radius);
        background: var(--card);
        font-size: var(--boxel-font-size-2xs);
      }
      .desk-note:empty {
        display: none;
      }
      .desk-note {
        animation: note-in 260ms cubic-bezier(0.22, 1, 0.36, 1) both;
      }
      .desk-refusal {
        border-inline-start-color: var(--destructive);
      }

      /* Command Center: nearest-breach strip over the breach table */
      .strip {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: var(--boxel-sp-xs) var(--boxel-sp-sm);
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        border-block-end: 1px solid var(--border);
      }
      .strip-clock {
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-lg);
        font-weight: 700;
        font-variant-numeric: tabular-nums;
      }
      .strip-case {
        flex: 1;
        min-inline-size: 12rem;
        display: grid;
      }
      .strip-case span {
        color: var(--muted-foreground);
        font-size: var(--boxel-font-size-2xs);
      }
      .table-wrap {
        overflow-x: auto;
      }
      .link-button {
        border: 0;
        background: none;
        padding: 0;
        font-family: inherit;
        font-size: inherit;
        font-weight: inherit;
        line-height: inherit;
        font-weight: 600;
        color: var(--foreground);
        text-align: start;
      }
      @media (hover: hover) {
        .link-button:hover {
          text-decoration: underline;
        }
      }
      .link-button:focus-visible,
      .case-open:focus-visible,
      .agent-tile:focus-visible,
      .pick-row:focus-visible {
        outline: 2px solid var(--ring);
        outline-offset: 2px;
      }
      .owner {
        display: inline-flex;
        align-items: center;
        gap: var(--boxel-sp-4xs);
        white-space: nowrap;
      }
      .unowned {
        color: var(--muted-foreground);
        white-space: nowrap;
      }
      .row-id {
        white-space: nowrap;
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-2xs);
        font-weight: 400;
        font-variant-numeric: tabular-nums;
        color: var(--muted-foreground);
      }
      .row-subject {
        font-weight: 600;
      }

      /* My Desk */
      .home {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
      }
      .home-head {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
      }
      .home-greeting {
        font-size: var(--boxel-font-size-xs);
        font-weight: 700;
      }
      .home-identity {
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
      }
      .home-rails {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(16rem, 1fr));
        gap: var(--boxel-sp-xs);
        align-items: stretch;
      }
      .home-row {
        display: flex;
        justify-content: space-between;
        gap: var(--boxel-sp-xs);
        inline-size: 100%;
      }
      .home-meta {
        flex: 0 1 40%;
        text-align: end;
        font-weight: 400;
        color: var(--muted-foreground);
      }

      /* Agents */
      .agent-person {
        --pretui-button-px: 0;
        max-inline-size: 100%;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .agent-cell {
        display: flex;
        flex-direction: column;
        block-size: 100%;
      }
      .agent-tile {
        /* one fixed fitted size (regular-tile, 250 x 170) so rows stay level */
        flex: none;
        display: block;
        inline-size: 100%;
        padding: 0;
        background: var(--card);
        color: inherit;
        text-align: start;
        block-size: 10.625rem;
        border: 1px solid var(--border);
        border-radius: var(--radius);
        overflow: hidden;
      }
      @media (hover: hover) {
        .agent-tile:hover {
          border-color: var(--foreground);
        }
      }

      /* dialogs */
      .dlg-h {
        margin: 0;
        font-size: var(--boxel-font-size-xs);
        font-weight: 700;
      }
      .dlg-hint {
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
      }
      .to-row {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
      }
      .to-arrow {
        flex: none;
      }
      .add-agent {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-sm);
      }
      .pick-list {
        display: grid;
        max-block-size: 14rem;
        overflow-y: auto;
        margin: 0;
        padding: 0;
        list-style: none;
        border: 1px solid var(--border);
        border-radius: var(--radius);
      }
      .pick-list > li + li {
        border-block-start: 1px solid var(--border);
      }
      .pick-row {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        inline-size: 100%;
        margin: 0;
        padding: var(--boxel-sp-4xs) var(--boxel-sp-sm);
        border: 0;
        background: var(--card);
        color: inherit;
        font-family: inherit;
        font-size: inherit;
        font-weight: inherit;
        line-height: inherit;
        text-align: start;
      }
      @media (hover: hover) {
        .pick-row:hover {
          background: var(--muted);
        }
      }
      .pick-row[aria-pressed='true'] {
        background: var(--muted);
      }
      .pick-id {
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
      }
      .pick-name {
        flex: 1;
        min-inline-size: 0;
        font-weight: 600;
      }

      /* Queues lanes and the case grid / list */
      .collection {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
      }
      .lane-row {
        display: grid;
        grid-template-columns: minmax(0, 1fr) auto;
        align-content: center;
        gap: 0 var(--boxel-sp-xs);
        block-size: 100%;
        padding: var(--boxel-sp-4xs) var(--boxel-sp-sm);
      }
      .lane-title {
        min-inline-size: 0;
        overflow: hidden;
        font-weight: 700;
        white-space: nowrap;
        text-overflow: ellipsis;
      }
      .lane-meta {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-4xs);
        min-inline-size: 0;
        overflow: hidden;
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
        white-space: nowrap;
        text-overflow: ellipsis;
      }
      .lane-title {
        grid-area: 1 / 1;
      }
      .lane-row .lcard-clock {
        grid-area: 1 / 2;
        justify-self: end;
      }
      .lane-meta {
        grid-area: 2 / 1;
      }
      .lane-claim {
        grid-area: 2 / 2;
        justify-self: end;
      }
      .lcard-clock {
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-2xs);
        font-weight: 600;
      }

      .case-grid,
      .case-list {
        display: grid;
        gap: var(--boxel-sp-xs);
        margin: 0;
        padding: 0;
        list-style: none;
      }
      .case-grid {
        grid-template-columns: repeat(auto-fill, minmax(15rem, 1fr));
      }
      .case-grid .case-cell {
        block-size: 6.75rem;
      }
      .case-list .case-cell {
        block-size: 3.25rem;
      }
      .case-open {
        display: block;
        inline-size: 100%;
        block-size: 100%;
        padding: 0;
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
        color: inherit;
        text-align: start;
        overflow: hidden;
      }
      @media (hover: hover) {
        .case-open:hover {
          border-color: var(--foreground);
        }
      }
      .case-face {
        inline-size: 100%;
        block-size: 100%;
        pointer-events: none;
      }
      @keyframes note-in {
        from {
          opacity: 0;
          transform: translateY(-0.25rem);
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
    </style>
  </template>

  subjectTitle = (e: Escalation) => e.subjectTitle ?? '?';
}
