import { CardDef, Component, realmURL } from '@cardstack/base/card-api';
import {
  type Query,
  identifyCard,
  searchEntryWireQueryFromQuery,
  type SearchEntryWireQuery,
} from '@cardstack/runtime-common';
import { cached, tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { debounce } from 'lodash';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Alert } from '@cardstack/pretui/components/alert';
import { Button } from '@cardstack/pretui/components/button';
import { SegmentedControl } from '@cardstack/pretui/components/segmented-control';
import { Tabs } from '@cardstack/pretui/components/tabs';
import HeadsetIcon from '@cardstack/boxel-icons/headset';
import PlusIcon from '@cardstack/boxel-icons/plus';

import {
  Case,
  CASE_STATUSES,
  CASE_STATUS_LABELS,
  SEVERITY_HUES,
} from '../../service-desk/case';
import { CustomerReply } from '../../service-desk/customer-reply';
import { Escalation } from '../../service-desk/escalation';
import { Sla } from '../../service-desk/sla';
import {
  CommandCenter,
  type BreachRiskRow,
} from '../../service-desk/components/command-center';
import { type DashboardTile } from '../../../components/dashboard';
import {
  SupportQueue,
  type QueueRow,
} from '../../service-desk/components/support-queue';
import {
  WorkflowBoard,
  type BoardCard,
} from '../../service-desk/components/workflow-board';
import {
  WorkspaceHome,
  type HomeRail,
} from '../../../components/workspace-home';
import { Board, type BoardColumn } from '../../../components/board';
import { CollectionToolbar } from '../../../components/collection-toolbar';
import { BreachRing } from '../../service-desk/components/breach-ring';
import { LiveClock } from '../../service-desk/components/live-clock';
import { Table } from '../../../components/table';
import {
  timerSnapshot,
  sortByUrgency,
  type TimerFacts,
} from '../../service-desk/utils/sla';
import { getCard } from '../../../utils/find-card';
import {
  mintIdentifier,
  RecordIdentifierField,
} from '../../../fields/record-identifier/record-identifier-field';
import AssignOwnerCommand from '../../service-desk/commands/assign-owner-command';
import BatchTransformCommand from '../../service-desk/commands/batch-transform-command';
import RunWorkflowCommand from '../../service-desk/commands/run-workflow-command';
import EscalateCaseCommand from '../../service-desk/commands/escalate-case-command';
import { levelRank } from '../../../fields/escalation-level/escalation-level-field';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';

import { DeskSetup } from './desk-setup';
import { DeskCopilot } from './desk-copilot';
import { DeskEscalations } from './desk-escalations';
import { DeskLaneCard } from './desk-lane-card';
import type { SupportCaseApp } from '../support-case-app';

const TABS = [
  { id: 'wall', label: 'Command Center' },
  { id: 'queues', label: 'Queues' },
  { id: 'board', label: 'Board' },
  { id: 'cases', label: 'Cases' },
  { id: 'escalations', label: 'Escalations' },
  { id: 'home', label: 'My Desk' },
  { id: 'setup', label: 'Setup' },
] as const;

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

/** The desk itself: the Support Case App's isolated view. */
export class SupportDesk extends Component<typeof SupportCaseApp> {
  @tracked currentTab: string = 'wall';
  @tracked caseView: CaseView = 'list';
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

  get escalationsLoading() {
    return (
      (this.escalationsQuery?.isLoading ?? false) &&
      this.escalations.length === 0
    );
  }
  get isLoading() {
    // Loading gates the wall only while there is NOTHING to show — once any
    // case is in the store the wall paints and refines as results land.
    return (this.casesQuery?.isLoading ?? false) && this.cases.length === 0;
  }

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

  // ── command center data ────────────────────────────────────────────
  get wallTiles(): DashboardTile[] {
    return [
      {
        label: 'open cases',
        value: this.openCases.length,
        onOpen: () => this.goTab('cases'),
      },
      {
        label: '≥ 75% consumed',
        value: this.atRiskCount,
        intent: this.atRiskCount ? 'amber' : 'neutral',
        onOpen: () => this.goTab('queues'),
      },
      {
        label: 'breached',
        value: this.breachedCount,
        intent: this.breachedCount ? 'red' : 'neutral',
        onOpen: () => this.goTab('queues'),
      },
      {
        label: 'clocks met',
        value: this.metTodayCount,
        intent: 'green',
        onOpen: () => this.goTab('cases'),
      },
      {
        label: 'awaiting ack',
        value: this.openEscalations.length,
        intent: this.openEscalations.length ? 'amber' : 'neutral',
        onOpen: () => this.goTab('escalations'),
      },
    ];
  }

  get wallBreachRows(): BreachRiskRow[] {
    return this.breachRiskCases.slice(0, 8).map(({ card, facts }) => ({
      card,
      label: `${card.caseId?.value ? card.caseId.value + ' · ' : ''}${this.titleOf(card)}`,
      timerFacts: facts,
      chipLabel: card.severity,
      chipHue: SEVERITY_HUES[card.severity ?? 'low'] ?? 'slate',
      ownerName: card.ownership?.ownerName,
      clockKind: facts?.kind,
      onAssign: card.ownership?.ownerName
        ? undefined
        : () => this.assignToOperator(card),
    }));
  }

  get agentsOnDuty() {
    return (this.args.model.candidatePool ?? []).filter(Boolean).length;
  }

  get wallQueues() {
    // Queue load derived from ownership team names on open cases.
    let byTeam = new Map<string, number>();
    for (let c of this.openCases) {
      let team = c.ownership?.teamName ?? 'Unrouted';
      byTeam.set(team, (byTeam.get(team) ?? 0) + 1);
    }
    let agents = Math.max(1, (this.args.model.candidatePool ?? []).length);
    return [...byTeam.entries()].map(([name, open]) => ({
      name,
      open,
      agents,
      overloaded: open > agents * 4,
      oldestLabel: open > agents * 4 ? 'heavy' : 'ok',
      onOpen: () => this.goTab('queues'),
    }));
  }

  get wallAcks() {
    return this.openEscalations.map((e) => ({
      levelKey: (e.toLevel?.key as string) ?? '?',
      label: e.subjectTitle ?? e.title ?? '?',
      ackDueLabel: e.toLevel?.ackTargetMinutes
        ? `${e.toLevel.ackTargetMinutes}m target`
        : 'no target',
      overdue: e.ackOverdue === 'yes',
      onOpen: () => this.openCard(e),
    }));
  }

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

  caseColumns = [
    {
      key: 'caseId',
      label: 'Case',
      width: '11rem',
      value: (c: any) => c.caseId?.value ?? '—',
    },
    { key: 'subject', label: 'Subject', value: (c: any) => c.subject },
    {
      key: 'severity',
      label: 'Severity',
      width: '7rem',
      value: (c: any) => c.severity,
    },
    {
      key: 'status',
      label: 'Status',
      width: '10rem',
      value: (c: any) => CASE_STATUS_LABELS[c.status] ?? c.status,
    },
    {
      key: 'owner',
      label: 'Owner',
      width: '9rem',
      value: (c: any) => c.ownership?.ownerName ?? 'unassigned',
    },
    {
      key: 'state',
      label: 'Workflow',
      width: '9rem',
      showAbove: 720 as const,
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
      chipLabel: c.severity,
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
        chipLabel: c.severity,
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
  get homeRails(): HomeRail[] {
    let mine = this.openCases.filter((c) =>
      this.sameCard(c.ownership?.ownerId, this.args.model.operator?.id),
    );
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
        items: mine.map((c) => ({
          label: this.titleOf(c),
          meta: c.workflowState?.label ?? c.status,
          onOpen: () => this.openCard(c),
        })),
      },
    ];
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

  openCard = (card: any) => {
    if (card?.id) {
      (this.args as any).viewCard?.(new URL(card.id));
    }
  };
  // Every "add" on the desk lands the operator in the edit form of the new
  // record, not its isolated view — a freshly minted card has nothing to read.
  editCard = (card: any) => {
    if (card?.id) {
      (this.args as any).viewCard?.(new URL(card.id), 'edit');
    }
  };
  openEntry = (id: string) => {
    if (id) (this.args as any).viewCard?.(new URL(id));
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
    let kase = new Case({
      subject: 'New case',
      status: 'open',
      openedOn: new Date(),
      caseId: pattern
        ? new RecordIdentifierField({
            value: mintIdentifier(pattern, seq),
            pattern,
            issuedAt: new Date(),
          } as any)
        : undefined,
    } as any);
    await new SaveCardCommand(this.commandContext).execute({
      card: kase,
      realm: this.realm,
    } as any);
    this.editCard(kase);
  };

  note = (msg: string) => {
    this.actionNote = msg;
  };

  assignToOperator = async (card: any) => {
    try {
      let operator = await this.byId(this.args.model.operatorId);
      let result = await new AssignOwnerCommand(this.commandContext).execute({
        card,
        owner: operator,
        strategy: 'assigned',
      } as any);
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
      let pool: any[] = (this.args.model.candidatePool ?? []).filter(Boolean);
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
    <article class='desk'>
      <header class='desk-bar'>
        <span class='desk-brand'><HeadsetIcon
            width='16'
            height='16'
            aria-hidden='true'
          />
          {{@model.title}}</span>
        {{#if @model.operator}}
          <span class='desk-operator'>at the desk:
            {{this.operatorName}}</span>
        {{/if}}
      </header>

      {{#if this.setupIncomplete}}
        <Alert @tone='warning' class='desk-banner'>
          Setup is not finished: the desk works, but ids, hours and workflow
          come from defaults.
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

      <Tabs
        class='desk-tabs'
        @options={{this.tabOptions}}
        @value={{this.currentTab}}
        @onChange={{this.goTab}}
      >
        <div class='desk-body'>
          {{#if (eq this.currentTab 'wall')}}
            {{#if this.isLoading}}
              <p class='desk-loading' role='status'>Loading the wall…</p>
            {{else}}
              <CommandCenter
                @tiles={{this.wallTiles}}
                @breachRows={{this.wallBreachRows}}
                @operatorName={{this.operatorName}}
                @agentsOnDuty={{this.agentsOnDuty}}
                @openCount={{this.openCases.length}}
                @queues={{this.wallQueues}}
                @escalations={{this.wallAcks}}
                @onOpenCard={{this.openCard}}
              />
            {{/if}}
          {{/if}}

          {{#if (eq this.currentTab 'queues')}}
            <CollectionToolbar
              @search={{this.queueSearch}}
              @onSearch={{this.setQueueSearch}}
              @placeholder='Search case id, subject, owner or team'
              @badges={{this.queueBadges}}
              @activeBadge={{this.queueSeverity}}
              @onBadge={{this.setQueueSeverity}}
            >
              <:right>
                <SegmentedControl
                  @label='Queue view'
                  @options={{QUEUE_VIEWS}}
                  @value={{this.queueView}}
                  @onChange={{this.setQueueView}}
                />
                <Button
                  @tone='primary'
                  @appearance='filled'
                  @size='s'
                  {{on 'click' this.createCase}}
                >
                  <PlusIcon width='16' height='16' role='presentation' />
                  Add Case
                </Button>
              </:right>
            </CollectionToolbar>
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
                    <DeskLaneCard
                      @label={{this.caseLabel item}}
                      @pillLabel={{row.chipLabel}}
                      @hue={{row.chipHue}}
                    >
                      <:lead>{{#if row.timerFacts}}<BreachRing
                            @facts={{row.timerFacts}}
                            @size={{26}}
                          />{{/if}}</:lead>
                      <:default>{{this.titleOf item}}</:default>
                      <:foot>
                        <span
                          class='{{unless row.ownerName "lcard-unowned"}}'
                        >{{if row.ownerName row.ownerName 'unassigned'}}</span>
                        {{#if row.timerFacts}}<LiveClock
                            @facts={{row.timerFacts}}
                            class='lcard-clock'
                          />{{/if}}
                      </:foot>
                      <:action>
                        {{#unless row.ownerName}}
                          {{! The board takes pointer capture on pointerdown, so the button stops it there to keep its own click. }}
                          {{! template-lint-disable no-pointer-down-event-binding }}
                          <Button
                            @tone='neutral'
                            @appearance='outlined'
                            @size='xs'
                            {{on 'pointerdown' this.shield}}
                            {{on 'click' (fn this.claim item)}}
                          >Claim</Button>
                          {{! template-lint-enable no-pointer-down-event-binding }}
                        {{/unless}}
                      </:action>
                    </DeskLaneCard>
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
              <p class='desk-empty'>No workflow linked — Setup step 4 creates
                one, or link an existing Workflow card in edit.</p>
            {{/if}}
          {{/if}}

          {{#if (eq this.currentTab 'cases')}}
            <div class='collection'>
              <CollectionToolbar
                @search={{this.caseSearch}}
                @onSearch={{this.setCaseSearch}}
                @placeholder='Search case id, subject or owner'
                @badges={{this.statusBadges}}
                @activeBadge={{this.caseStatusFilter}}
                @onBadge={{this.setStatusFilter}}
              >
                <:right>
                  <SegmentedControl
                    @label='Case view'
                    @options={{CASE_VIEWS}}
                    @value={{this.caseView}}
                    @onChange={{this.setCaseView}}
                  />
                  <Button
                    @tone='primary'
                    @appearance='filled'
                    @size='s'
                    {{on 'click' this.createCase}}
                  >
                    <PlusIcon width='16' height='16' role='presentation' />
                    Add Case
                  </Button>
                </:right>
              </CollectionToolbar>

              {{#if (eq this.caseView 'table')}}
                <div class='table-wrap'>
                  {{! The table is fed the client-side MIRROR of the wire query
                    (filteredCases) — same row set as grid/list, drawn as
                    fields. Toggling views never changes which rows exist. }}
                  <Table
                    @items={{this.filteredCases}}
                    @columns={{this.caseColumns}}
                    @onRowClick={{this.openCard}}
                    @rowKey='id'
                    @caption='Cases'
                    @emptyMessage='No cases match — clear the search or the status filter.'
                  />
                </div>
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
                            <li class='desk-empty'>No cases match — clear the
                              search or the status filter.</li>
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
            </div>
          {{/if}}

          {{#if (eq this.currentTab 'escalations')}}
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

          {{#if (eq this.currentTab 'home')}}
            <WorkspaceHome
              @greeting='Morning, {{this.operatorName}}'
              @identity='on duty'
              @rails={{this.homeRails}}
            />
          {{/if}}

          {{#if (eq this.currentTab 'setup')}}
            <DeskSetup
              @model={{this.app}}
              @context={{@context}}
              @onNote={{this.note}}
            />
          {{/if}}
        </div>
      </Tabs>
    </article>
    <style scoped>
      .desk {
        container-type: inline-size;
        min-height: 100%;
        /* ambient layer: a cool wash from the top-left + a faint grid, so
           the wall reads as a surface, not a blank */
        background:
          radial-gradient(
            90% 60% at 0% 0%,
            color-mix(in oklab, var(--primary) 7%, transparent),
            transparent 70%
          ),
          var(--background);
        color: var(--foreground);
        display: flex;
        flex-direction: column;
      }
      .desk-bar {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        flex-wrap: wrap;
        padding: var(--boxel-sp-xs) var(--boxel-sp);
        border-bottom: 1px solid var(--border);
        background: color-mix(in oklab, var(--card) 88%, transparent);
        backdrop-filter: blur(10px);
        -webkit-backdrop-filter: blur(10px);
        position: sticky;
        top: 0;
        z-index: 5;
      }
      .desk-brand {
        display: inline-flex;
        align-items: center;
        gap: var(--boxel-sp-4xs);
        font-weight: 600;
      }
      .desk-banner {
        margin: var(--boxel-sp-xs) var(--boxel-sp) 0;
      }
      .desk-operator {
        margin-left: auto;
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
      .desk-note {
        margin: var(--boxel-sp-xs) var(--boxel-sp) 0;
        padding: var(--boxel-sp-4xs) var(--boxel-sp-sm);
        border-left: 0.1875rem solid var(--primary);
        border-radius: 0 var(--radius) var(--radius) 0;
        background: color-mix(in oklab, var(--primary) 7%, var(--card));
        font-size: var(--boxel-font-size-xs);
        animation: note-in 260ms cubic-bezier(0.22, 1, 0.36, 1) both;
      }
      .desk-body {
        padding: var(--boxel-sp) var(--boxel-sp) var(--boxel-sp-xl);
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp);
        animation: body-in 300ms cubic-bezier(0.22, 1, 0.36, 1) both;
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
      @keyframes body-in {
        from {
          opacity: 0;
          transform: translateY(6px);
        }
        to {
          opacity: 1;
          transform: none;
        }
      }
      .desk-loading,
      .desk-empty {
        margin: 0;
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground);
      }
      .lcard-unowned {
        color: var(--warning-ink);
        font-style: italic;
      }
      .lcard-clock {
        font-size: var(--boxel-font-size-sm);
      }
      /* ── collection shell ── */
      .collection {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
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
      .table-wrap {
        overflow-x: auto;
        border: 1px solid var(--border);
        border-radius: var(--radius);
      }
      /* ── escalations tab ── */
      .desk-refusal {
        margin: 0;
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        border-left: 0.1875rem solid var(--destructive);
        border-radius: 0 var(--radius) var(--radius) 0;
        background: color-mix(in oklab, var(--destructive) 8%, var(--card));
        font-size: var(--boxel-font-size-sm);
      }
      @media (prefers-reduced-motion: reduce) {
        .desk-note,
        .desk-body {
          animation: none;
        }
      }
    </style>
  </template>

  tabOptions = TABS.map((t) => ({ value: t.id, label: t.label }));
  subjectTitle = (e: Escalation) => e.subjectTitle ?? '?';
}
