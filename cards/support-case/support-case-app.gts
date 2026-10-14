import {
  CardDef,
  Component,
  field,
  contains,
  linksTo,
  linksToMany,
  StringField,
  realmURL,
} from '@cardstack/base/card-api';
import {
  type Query,
  identifyCard,
  searchEntryWireQueryFromQuery,
  type SearchEntryWireQuery,
} from '@cardstack/runtime-common';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { debounce } from 'lodash';
import { eq } from '@cardstack/boxel-ui/helpers';
import {
  BoxelInput,
  Button,
  ViewSelector,
  FieldContainer,
} from '@cardstack/boxel-ui/components';
import HeadsetIcon from '@cardstack/boxel-icons/headset';
import LayoutGrid from '@cardstack/boxel-icons/layout-grid';
import LayoutList from '@cardstack/boxel-icons/layout-list';
import TableIcon from '@cardstack/boxel-icons/table';
import PlusIcon from '@cardstack/boxel-icons/plus';

import { AppConfigurationField } from '../../fields/app-configuration/app-configuration-field';
import { Case, CASE_STATUSES, CASE_STATUS_LABELS, SEVERITY_HUES } from '../service-desk/case';
import { CustomerReply } from '../service-desk/customer-reply';
import { Employee } from '../hr/employee';
import { Escalation, escalationStatusHue } from '../service-desk/escalation';
import { Role } from '../service-desk/role';
import { Sla } from '../service-desk/sla';
import { Workflow } from '../service-desk/workflow';
import { CsvFileDef } from '@cardstack/base/csv-file-def';
import { CommandCenter, type BreachRiskRow } from '../service-desk/components/command-center';
import { type DashboardTile } from '../../components/dashboard';
import { SupportQueue, type QueueRow } from '../service-desk/components/support-queue';
import { WorkflowBoard, type BoardCard } from '../service-desk/components/workflow-board';
import { WorkspaceHome, type HomeRail } from '../../components/workspace-home';
import { SetupWizard, type WizardStep } from './components/setup-wizard';
import { CrossRecordTimeline } from '../service-desk/components/cross-record-timeline';
import { Board, type BoardColumn } from '../../components/board';
import { CollectionToolbar } from '../../components/collection-toolbar';
import { BreachRing } from '../service-desk/components/breach-ring';
import { LiveClock } from '../service-desk/components/live-clock';
import { StatePill } from '../../components/state-pill';
import { Table } from '../../components/table';
import {
  timerSnapshot,
  sortByUrgency,
} from '../service-desk/utils/sla';
import { stateColor } from '../../components/state-pill';
import { getCard } from '../../utils/find-card';
import {
  isValidIdentifierPattern,
  mintIdentifier,
  RecordIdentifierField,
} from '../../fields/record-identifier/record-identifier-field';
import AssignOwnerCommand from '../service-desk/commands/assign-owner-command';
import BatchTransformCommand from '../service-desk/commands/batch-transform-command';
import RunWorkflowCommand from '../service-desk/commands/run-workflow-command';
import ImportLegacyDataCommand from '../service-desk/commands/import-legacy-data-command';
import AiCopilotCommand from '../../commands/ai-copilot-command';
import EscalateCaseCommand from '../service-desk/commands/escalate-case-command';
import { levelRank } from '../../fields/escalation-level/escalation-level-field';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import WriteTextFileCommand from '@cardstack/boxel-host/commands/write-text-file';
import { EditSectionNav } from '../../components/edit-section-nav';

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

/**
 * Support Ops Command Center — the operations layer ABOVE the ServiceDesk
 * agent kit. The agent works one ticket in `service-desk`; the ops lead runs
 * fifty here: clocks, ladders, ownership, workflow, automation.
 *
 * `operator` is the acting person: the platform has no current-user concept,
 * so who is claiming/acknowledging is DECLARED on the desk, honestly, rather
 * than inferred. Every collection is a live query (membership is derived,
 * never a maintained linksToMany).
 */
export class SupportCaseApp extends CardDef {
  static displayName = 'Support Case App';
  static icon = HeadsetIcon;
  static prefersWideFormat = true;

  @field appName = contains(StringField);
  @field config = contains(AppConfigurationField);
  @field defaultWorkflow = linksTo(() => Workflow);
  @field operator = linksTo(() => Employee, {
    description: 'Who is at the desk — claims and acks are attributed to them.',
  });
  @field roles = linksToMany(() => Role);
  @field candidatePool = linksToMany(() => Employee, {
    description: 'Round-robin pool: commands take caller-loaded lists.',
  });

  @field title = contains(StringField, {
    computeVia: function (this: SupportCaseApp) {
      return this.appName ?? 'Support Ops';
    },
  });

  // Denormalized link ids: linksTo fields load lazily on the client, so an
  // action fired before the link resolves would see undefined. These computeds
  // are produced at index time (link traversal works in computeVia) and are
  // always present on the loaded instance — the actions re-fetch by id.
  @field operatorId = contains(StringField, {
    computeVia: function (this: SupportCaseApp) {
      return this.operator?.id;
    },
  });
  @field operatorTitle = contains(StringField, {
    computeVia: function (this: SupportCaseApp) {
      return this.operator?.title as string | undefined;
    },
  });
  @field workflowId = contains(StringField, {
    computeVia: function (this: SupportCaseApp) {
      return this.defaultWorkflow?.id;
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    @tracked currentTab: string = 'wall';
    @tracked caseView: CaseView = 'list';
    @tracked caseSearch = '';
    @tracked caseStatusFilter = 'all';
    @tracked copilotDraft: string | null = null;
    @tracked copilotCitations: string[] = [];
    @tracked copilotBusy = false;
    @tracked copilotCaseId: string | null = null;
    @tracked actionNote: string | null = null;
    @tracked importCsv = '';
    @tracked importReport: string[] = [];
    /** The chosen CSV file card (preferred); paste is the fallback. */
    @tracked importFileId: string | null = null;
    @tracked importBusy = false;
    @tracked uploadBusy = false;
    @tracked uploadNote: string | null = null;
    @tracked wizardPattern = '';
    @tracked queueView: 'lanes' | 'list' = 'lanes';
    @tracked escView: 'lanes' | 'list' = 'lanes';
    @tracked queueSearch = '';
    @tracked queueSeverity = 'all';
    @tracked escSearch = '';
    @tracked laneRefusal: string | null = null;
    @tracked escStatus = 'all';

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
    accentStyle = (hue?: string) =>
      `--lcard-accent: ${stateColor((hue as any) ?? 'slate').ring};`;

    slaFor = (card: any): Sla | undefined => {
      return this.slas.find((s) => this.sameCard(s.subjectId, card?.id));
    };

    /** The case's most urgent timer facts — one place decides "worst". */
    worstFacts = (card: any) => {
      let sla = this.slaFor(card);
      let timers = (sla?.timers ?? []).filter((t: any) => !t.satisfiedAt);
      if (!timers.length) return undefined;
      return sortByUrgency(timers)[0];
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
      let rows = this.openCases
        .map((c) => ({ card: c, facts: this.worstFacts(c) }))
        .filter((r) => r.facts);
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
        counts.set(
          c.status ?? 'open',
          (counts.get(c.status ?? 'open') ?? 0) + 1,
        );
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
    caseViewItems = [
      { id: 'grid', icon: LayoutGrid },
      { id: 'list', icon: LayoutList },
      { id: 'table', icon: TableIcon },
    ];
    setCaseView = (id: string) => (this.caseView = id as CaseView);

    // ── queue rows ─────────────────────────────────────────────────────
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
    queueRowFor = (item: any): QueueRow | undefined =>
      this.queueRows.find((r) => r.card?.id === item?.id);
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
          ? timerSnapshot(
              sortByUrgency(rows, (r) => r.timerFacts)[0].timerFacts,
            ).shortLabel
          : undefined;
        return {
          key,
          label: nearest ? `${key} · ${nearest}` : key,
          color:
            key === 'Unrouted'
              ? 'var(--boxel-warning)'
              : 'var(--primary, var(--boxel-highlight))',
        };
      });
    }
    setQueueView = (v: 'lanes' | 'list') => (this.queueView = v);

    /** Escalations as a kanban by receiving level — the ladder, drawn with the shared Board. */
    escalationColumns: BoardColumn[] = [
      {
        key: 'L1',
        label: 'L1',
        color: 'var(--muted-foreground, var(--boxel-450))',
      },
      {
        key: 'L2',
        label: 'L2',
        color: 'var(--primary, var(--boxel-highlight))',
      },
      { key: 'L3', label: 'L3', color: 'var(--boxel-warning)' },
      { key: 'exec', label: 'Exec', color: 'var(--boxel-danger)' },
    ];
    escalationKeyFor = (e: any) => (e?.toLevel?.key as string) ?? 'L1';
    private debouncedSetEscSearch = debounce(
      (v: string) => (this.escSearch = v),
      250,
    );
    setEscSearch = (v: string) => this.debouncedSetEscSearch(v);
    setEscStatus = (id: string) => (this.escStatus = id);
    get escBadges() {
      let st = ['open', 'acknowledged', 'resolved', 'cancelled'];
      return [
        { id: 'all', label: 'All', count: this.escalations.length },
        ...st.map((x) => ({
          id: x,
          label: x[0]!.toUpperCase() + x.slice(1),
          count: this.escalations.filter((e) => e.status === x).length,
        })),
      ];
    }
    get escalationItems() {
      let q = this.escSearch.trim().toLowerCase();
      return this.escalations.filter((e) => {
        let statusOk =
          this.escStatus === 'all'
            ? e.status !== 'cancelled'
            : e.status === this.escStatus;
        let textOk =
          !q ||
          this.subjectTitle(e).toLowerCase().includes(q) ||
          (e.reason ?? '').toLowerCase().includes(q) ||
          (e.raisedByName ?? '').toLowerCase().includes(q) ||
          (e.toLevel?.key ?? '').toLowerCase().includes(q);
        return statusOk && Boolean(textOk);
      });
    }
    setEscView = (v: 'lanes' | 'list') => (this.escView = v);
    ackDue = (e: Escalation) =>
      e.toLevel?.ackTargetMinutes
        ? `${e.toLevel.ackTargetMinutes}m ack target`
        : 'no ack target';

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

    // The kanban engine takes pointer capture on pointerdown, which redirects
    // the click to the board and opens the card instead. Stopping pointerdown
    // on the control keeps its own click (same workaround the Talent tracker
    // carries) until the catalog Board ships the shield itself.
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
      // Mint the identifier at create time; the desk owns the counter.
      let cfg = this.args.model.config;
      let seq = (cfg?.identifierSeq ?? 0) + 1;
      let kase = new Case({
        subject: 'New case',
        status: 'open',
        openedOn: new Date(),
        caseId: cfg?.idPattern
          ? new RecordIdentifierField({
              value: mintIdentifier(cfg.idPattern, seq),
              pattern: cfg.idPattern,
              issuedAt: new Date(),
            } as any)
          : undefined,
      } as any);
      await new SaveCardCommand(this.commandContext).execute({
        card: kase,
        realm: this.realm,
      } as any);
      if (cfg) cfg.identifierSeq = seq;
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
            if (c?.status === 'resolved' || c?.status === 'closed')
              keep.push(c);
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
        let pool = (this.args.model.candidatePool ?? []).filter(Boolean);
        if (operation === 'assign-owner' && !pool.length) {
          // links may be unloaded — fall back to the operator by id
          let op = await this.byId(this.args.model.operatorId);
          pool = op ? [op] : [];
        }
        let result = await new BatchTransformCommand(
          this.commandContext,
        ).execute({
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
        } as any);
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
        let result = await new EscalateCaseCommand(this.commandContext).execute(
          {
            subject: await this.byId(e.subjectId),
            fromLevelKey: from,
            toLevelKey,
            reason: 'agent-request',
            note: `Raised from the ladder by ${this.operatorName}`,
            raisedBy: await this.byId(this.args.model.operatorId),
            realm: this.realm,
          } as any,
        );
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

    // ── copilot (drafts only) ──────────────────────────────────────────
    copilot = async (card: any) => {
      this.copilotBusy = true;
      this.copilotDraft = null;
      this.copilotCaseId = card?.id ?? null;
      try {
        let result = await new AiCopilotCommand(this.commandContext).execute({
          case: card,
          intent: 'draft-reply',
          replies: this.repliesFor(card),
        } as any);
        this.copilotDraft = (result as any).draft;
        this.copilotCitations = [...((result as any).citations ?? [])];
      } catch (e: any) {
        this.note(e?.message ?? String(e));
      } finally {
        this.copilotBusy = false;
      }
    };

    acceptDraft = async () => {
      // Accepting is a separate, ATTRIBUTED act: the draft becomes the
      // operator's own outbound reply; the draft object disappears.
      let target = this.cases.find((c) => c.id === this.copilotCaseId);
      if (!target || !this.copilotDraft) return;
      let reply = new CustomerReply({
        case: target,
        direction: 'outbound',
        channel: 'portal',
        body: this.copilotDraft,
        author: this.args.model.operator,
        sentAt: new Date(),
      } as any);
      await new SaveCardCommand(this.commandContext).execute({
        card: reply,
        realm: this.realm,
      } as any);
      this.copilotDraft = null;
      this.note(`Sent as outbound reply, attributed to ${this.operatorName}.`);
    };
    discardDraft = () => {
      this.copilotDraft = null;
    };

    // ── import ─────────────────────────────────────────────────────────
    setImportCsv = (v: string) => (this.importCsv = v);
    /** The import function proper: a CSV from the user's machine becomes a
        CSV file card in the desk's realm (provenance), then is pre-selected. */
    uploadCsv = async (ev: Event) => {
      let input = ev.target as HTMLInputElement;
      let file = input.files?.[0];
      input.value = '';
      if (!file || !this.realm) return;
      this.uploadBusy = true;
      this.uploadNote = null;
      try {
        let content = await file.text();
        let header = (content.split(/\r?\n/)[0] ?? '').toLowerCase();
        if (!header.includes('subject') || !header.includes('legacy_id')) {
          throw new Error(
            `${file.name}: header must include subject, status, opened and legacy_id (got "${header.slice(0, 80)}")`,
          );
        }
        let safeName =
          file.name.replace(/[^A-Za-z0-9._-]+/g, '-').replace(/\.csv$/i, '') +
          '.csv';
        let result = await new WriteTextFileCommand(
          this.commandContext,
        ).execute({
          realm: this.realm,
          path: `imports/${safeName}`,
          content,
          useNonConflictingFilename: true,
        } as any);
        let url = (result as any).fileIdentifier as string;
        this.importFileId = url;
        this.importReport = [];
        this.uploadNote = `Uploaded ${file.name} — pick it below if it is not highlighted yet, then Import rows.`;
      } catch (e: any) {
        this.uploadNote = e?.message ?? String(e);
      } finally {
        this.uploadBusy = false;
      }
    };
    openFilePicker = (ev: Event) => {
      let root = (ev.currentTarget as HTMLElement).closest('.wiz-import');
      (
        root?.querySelector('input[type=file]') as HTMLInputElement | null
      )?.click();
    };
    pickImportFile = (id: string) => {
      this.importFileId = this.importFileId === id ? null : id;
      this.importReport = [];
    };
    private fileKey = (id?: string | null) => (id ?? '').replace(/\.csv$/i, '');
    isPickedFile = (id: string) =>
      Boolean(this.importFileId) &&
      this.fileKey(this.importFileId) === this.fileKey(id);
    get importFileName() {
      return this.importFileId?.split('/').pop() ?? null;
    }
    get canImport() {
      return (
        !this.importBusy && Boolean(this.importFileId || this.importCsv.trim())
      );
    }
    /** Every CSV file card in the desk's realms — the import picks from these. */
    get csvWireQuery(): SearchEntryWireQuery | undefined {
      let ref = identifyCard(CsvFileDef);
      if (!ref || !this.realms.length) return undefined;
      // Only files that CAN be imported are offered: the index knows each
      // CSV's header (CsvFileDef.columns), so fixtures with other columns
      // never reach the picker and "missing column" is no longer a click away.
      // One distinctive header name tells an export apart (`status` is also a
      // reserved search_doc member on file rows, so eq on it never matches).
      // The filter stays FLAT: the host binds its htmlQuery into the filter's
      // top-level `eq`, and an `every` wrapper returned zero rows (verified
      // against _federated-search directly).
      return {
        ...searchEntryWireQueryFromQuery(
          {
            filter: { type: ref, eq: { columns: 'legacy_id' } } as any,
            // file rows carry `name`, not cardTitle — sorting on cardTitle drops them all
            sort: [{ by: 'name', on: ref, direction: 'asc' }],
          } as any,
          { scope: 'files' },
        ),
        realms: this.realms,
      };
    }
    runImport = async () => {
      if (!this.canImport) return;
      this.importBusy = true;
      try {
        let cfg = this.args.model.config;
        let result = await new ImportLegacyDataCommand(
          this.commandContext,
        ).execute({
          sourceUrl: this.importFileId ?? undefined,
          csvText: this.importFileId ? undefined : this.importCsv,
          idPattern: cfg?.idPattern ?? 'CASE-{yyyy}-{seq4}',
          startSeq: (cfg?.identifierSeq ?? 0) + 1,
          systemName: 'legacy helpdesk',
          realm: this.realm,
        } as any);
        let r = result as any;
        this.importReport = [...(r.results ?? [])];
        if (cfg && typeof r.nextSeq === 'number') {
          cfg.identifierSeq = r.nextSeq - 1;
        }
      } catch (e: any) {
        this.importReport = [e?.message ?? String(e)];
      } finally {
        this.importBusy = false;
      }
    };

    // ── setup wizard ───────────────────────────────────────────────────
    get wizardSteps(): WizardStep[] {
      return [
        { title: 'Business hours' },
        {
          title: 'Case ID pattern',
          validate: () =>
            isValidIdentifierPattern(this.args.model.config?.idPattern)
              ? undefined
              : 'The pattern needs {yyyy} and {seqN} — e.g. CASE-{yyyy}-{seq4}.',
        },
        { title: 'Roles & pool' },
        { title: 'Workflow' },
        { title: 'Sample import' },
      ];
    }
    get wizardStep() {
      return this.args.model.config?.setupStep ?? 0;
    }
    advanceWizard = (next: number) => {
      let cfg = this.args.model.config;
      if (!cfg) return;
      if (next === -1) {
        cfg.setupCompletedAt = new Date();
        cfg.setupStep = this.wizardSteps.length;
        this.note('Setup complete — the desk is live.');
      } else if (next > (cfg.setupStep ?? 0)) {
        cfg.setupStep = next;
      }
    };
    setIdPattern = (v: string) => {
      let cfg = this.args.model.config;
      if (cfg) cfg.idPattern = v;
    };
    setTimeZone = (v: string) => {
      let w = this.args.model.config?.defaultSlaWindow;
      if (w) (w as any).timeZone = v;
    };
    get patternPreview() {
      return mintIdentifier(this.args.model.config?.idPattern, 1);
    }
    get patternValid() {
      return isValidIdentifierPattern(this.args.model.config?.idPattern);
    }

    get setupIncomplete() {
      return !this.args.model.config?.setupCompletedAt;
    }

    // escalation timeline events for the escalations tab
    get escalationEvents() {
      return this.escalations.map((e) => ({
        at: e.raisedAt,
        label: `${e.title} · ${e.reason} on ${this.subjectTitle(e)}`,
        by: e.raisedByName,
        intent:
          e.status === 'open'
            ? ('amber' as const)
            : e.status === 'cancelled'
              ? ('slate' as const)
              : ('green' as const),
      }));
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
          <nav
            class='desk-tabs'
            role='tablist'
            aria-label='Support Ops sections'
          >
            {{#each this.deskTabs as |tab|}}
              <button
                type='button'
                role='tab'
                class='desk-tab
                  {{if (eq this.currentTab tab.id) "desk-tab-on"}}'
                aria-selected='{{eq this.currentTab tab.id}}'
                {{on 'click' (fn this.goTab tab.id)}}
              >{{tab.label}}</button>
            {{/each}}
          </nav>
          {{#if @model.operator}}
            <span class='desk-operator'>at the desk:
              {{this.operatorName}}</span>
          {{/if}}
        </header>

        {{#if this.setupIncomplete}}
          <button
            type='button'
            class='desk-banner'
            {{on 'click' (fn this.goTab 'setup')}}
          >
            Setup is not finished — the desk works, but ids, hours and workflow
            come from defaults. Continue setup →
          </button>
        {{/if}}

        {{#if this.actionNote}}
          <p class='desk-note' role='status'>{{this.actionNote}}</p>
        {{/if}}

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
                <div class='view-toggle' role='tablist' aria-label='Queue view'>
                  <button
                    type='button'
                    role='tab'
                    class='vt hit-ext
                      {{if (eq this.queueView "lanes") "vt-on"}}'
                    aria-selected='{{eq this.queueView "lanes"}}'
                    {{on 'click' (fn this.setQueueView 'lanes')}}
                  >By queue</button>
                  <button
                    type='button'
                    role='tab'
                    class='vt hit-ext {{if (eq this.queueView "list") "vt-on"}}'
                    aria-selected='{{eq this.queueView "list"}}'
                    {{on 'click' (fn this.setQueueView 'list')}}
                  >Nearest breach · bulk</button>
                </div>
                <Button
                  @kind='primary'
                  @size='small'
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
                    <div class='lcard' style={{this.accentStyle row.chipHue}}>
                      <span class='lcard-top'>
                        {{#if row.timerFacts}}<BreachRing
                            @facts={{row.timerFacts}}
                            @size={{26}}
                          />{{/if}}
                        <span class='lcard-id'>{{item.caseId.value}}</span>
                        {{#if row.chipLabel}}<StatePill
                            @label={{row.chipLabel}}
                            @hue={{row.chipHue}}
                          />{{/if}}
                      </span>
                      <span class='lcard-title'>{{this.titleOf item}}</span>
                      <span class='lcard-foot'>
                        <span
                          class='{{unless row.ownerName "lcard-unowned"}}'
                        >{{if row.ownerName row.ownerName 'unassigned'}}</span>
                        {{#if row.timerFacts}}<LiveClock
                            @facts={{row.timerFacts}}
                            class='lcard-clock'
                          />{{/if}}
                      </span>
                      {{#unless row.ownerName}}
                        <Button
                          @size='extra-small'
                          class='lcard-claim hit-ext'
                          {{on 'pointerdown' this.shield}}
                          {{on 'click' (fn this.claim item)}}
                        >Claim</Button>
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
                  <ViewSelector
                    @items={{this.caseViewItems}}
                    @selectedId={{this.caseView}}
                    @onChange={{this.setCaseView}}
                  />
                  <Button
                    @kind='primary'
                    @size='small'
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
                            {{! prerendered tiles carry no click of their own —
                                the wrapper owns it (run-12 lesson). }}
                            <button
                              type='button'
                              class='case-open'
                              {{on 'click' (fn this.openEntry entry.id)}}
                            >
                              <entry.component />
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

              <section class='copilot'>
                <h3 class='copilot-title'>Copilot — drafts only, never sends</h3>
                {{#if this.copilotBusy}}
                  <p class='desk-loading' role='status'>Drafting…</p>
                {{else if this.copilotDraft}}
                  <div class='copilot-draft'>
                    <span class='copilot-tag'>DRAFT{{#if
                        this.copilotCitations.length
                      }} · cites {{this.copilotCitations}}{{/if}}</span>
                    <p class='copilot-text'>{{this.copilotDraft}}</p>
                    <div class='copilot-actions'>
                      <Button
                        @kind='primary'
                        @size='small'
                        {{on 'click' this.acceptDraft}}
                      >Send as my reply</Button>
                      <Button
                        @size='small'
                        {{on 'click' this.discardDraft}}
                      >Discard</Button>
                    </div>
                  </div>
                {{else}}
                  <div class='copilot-pick'>
                    {{#each this.breachRiskCases as |r|}}
                      <Button
                        @size='extra-small'
                        {{on 'click' (fn this.copilot r.card)}}
                      >✦ Draft for {{this.titleOf r.card}}</Button>
                    {{else}}
                      <p class='desk-empty'>No at-risk case to draft for.</p>
                    {{/each}}
                  </div>
                {{/if}}
              </section>
            </div>
          {{/if}}

          {{#if (eq this.currentTab 'escalations')}}
            <div class='esc-tab'>
              <CollectionToolbar
                @search={{this.escSearch}}
                @onSearch={{this.setEscSearch}}
                @placeholder='Search subject, reason, level or who raised it'
                @badges={{this.escBadges}}
                @activeBadge={{this.escStatus}}
                @onBadge={{this.setEscStatus}}
              >
                <:right>
                  <div
                    class='view-toggle'
                    role='tablist'
                    aria-label='Escalation view'
                  >
                    <button
                      type='button'
                      role='tab'
                      class='vt hit-ext
                        {{if (eq this.escView "lanes") "vt-on"}}'
                      aria-selected='{{eq this.escView "lanes"}}'
                      {{on 'click' (fn this.setEscView 'lanes')}}
                    >The ladder</button>
                    <button
                      type='button'
                      role='tab'
                      class='vt hit-ext {{if (eq this.escView "list") "vt-on"}}'
                      aria-selected='{{eq this.escView "list"}}'
                      {{on 'click' (fn this.setEscView 'list')}}
                    >Awaiting ack</button>
                  </div>
                </:right>
              </CollectionToolbar>
              {{#if (eq this.escView 'lanes')}}
                {{#if this.laneRefusal}}<p
                    class='desk-refusal'
                    role='alert'
                  >{{this.laneRefusal}}</p>{{/if}}
                <Board
                  @boardLabel='Escalation ladder'
                  @cardSize='regular-tile'
                  @items={{this.escalationItems}}
                  @columns={{this.escalationColumns}}
                  @columnKeyFor={{this.escalationKeyFor}}
                  @onMove={{this.escalateByDrag}}
                  @onOpen={{this.openCard}}
                >
                  <:card as |e|>
                    <div
                      class='lcard'
                      style={{this.accentStyle (escalationStatusHue e.status)}}
                    >
                      <span class='lcard-top'>
                        <span class='lcard-id'>{{e.fromLevel.key}}
                          →
                          {{e.toLevel.key}}</span>
                        <StatePill
                          @label={{e.status}}
                          @hue={{escalationStatusHue e.status}}
                        />
                      </span>
                      <span class='lcard-title'>{{this.subjectTitle e}}</span>
                      <span class='lcard-foot'><span>{{e.reason}}
                          ·
                          {{this.ackDue e}}
                          · by
                          {{e.raisedByName}}</span>{{#if
                          (eq e.ackOverdue 'yes')
                        }}<b class='lcard-overdue'>ack overdue</b>{{/if}}</span>
                      {{#if (eq e.status 'open')}}
                        <Button
                          @kind='primary'
                          @size='extra-small'
                          class='lcard-claim hit-ext'
                          {{on 'pointerdown' this.shield}}
                          {{on 'click' (fn this.acknowledge e)}}
                        >Acknowledge</Button>
                      {{/if}}
                    </div>
                  </:card>
                </Board>
              {{else}}
                {{#each this.escalationItems as |e|}}
                  <div class='esc-line'>
                    <button
                      type='button'
                      class='esc-open'
                      {{on 'click' (fn this.openCard e)}}
                    >
                      {{this.titleOf e}}
                      ·
                      {{e.reason}}
                      · on
                      {{this.subjectTitle e}}
                    </button>
                    <Button
                      @kind='primary'
                      @size='extra-small'
                      class='hit-ext'
                      {{on 'click' (fn this.acknowledge e)}}
                    >Acknowledge</Button>
                  </div>
                {{else}}
                  <p class='desk-empty'>✓ Every escalation acknowledged.</p>
                {{/each}}
              {{/if}}
              <section class='esc-history'>
                <h3 class='esc-history-title'>History</h3>
                <CrossRecordTimeline
                  @events={{this.escalationEvents}}
                  @emptyLabel='No escalations yet — a quiet ladder is a good ladder.'
                />
              </section>
            </div>
          {{/if}}

          {{#if (eq this.currentTab 'home')}}
            <WorkspaceHome
              @greeting='Morning, {{this.operatorName}}'
              @identity='on duty'
              @rails={{this.homeRails}}
            />
          {{/if}}

          {{#if (eq this.currentTab 'setup')}}
            <SetupWizard
              @steps={{this.wizardSteps}}
              @currentStep={{this.wizardStep}}
              @onAdvance={{this.advanceWizard}}
            >
              <:step as |i|>
                {{#if (eq i 0)}}
                  <h3 class='wiz-h'>Business hours</h3>
                  <label class='wiz-label' for='tz'>Timezone (IANA)</label>
                  <BoxelInput
                    id='tz'
                    @value={{@model.config.defaultSlaWindow.timeZone}}
                    @onInput={{this.setTimeZone}}
                    @placeholder='Asia/Kuala_Lumpur'
                  />
                  <p class='wiz-hint'>Working windows and holidays are edited on
                    the desk's edit view — this step sets the zone every clock
                    runs in. Empty windows mean always-on (24/7).</p>
                {{/if}}
                {{#if (eq i 1)}}
                  <h3 class='wiz-h'>Case ID pattern</h3>
                  <BoxelInput
                    @value={{@model.config.idPattern}}
                    @onInput={{this.setIdPattern}}
                    @placeholder='CASE-(yyyy)-(seq4)'
                  />
                  <p class='wiz-preview'>Preview:
                    <code>{{this.patternPreview}}</code>
                    {{#if this.patternValid}}<span class='wiz-ok'>✓ valid</span>{{else}}<span
                        class='wiz-bad'
                      >needs (yyyy) and (seqN)</span>{{/if}}
                  </p>
                  <p class='wiz-hint'>Ids are minted at create time and never
                    edited or recycled.</p>
                {{/if}}
                {{#if (eq i 2)}}
                  <h3 class='wiz-h'>Roles & round-robin pool</h3>
                  <p class='wiz-hint'>Link Roles and the candidate pool on the
                    desk's edit view. Currently linked:
                    {{@model.roles.length}}
                    role(s),
                    {{@model.candidatePool.length}}
                    in the pool. The escalation ladder assigns toward a role's
                    on-duty member.</p>
                {{/if}}
                {{#if (eq i 3)}}
                  <h3 class='wiz-h'>Workflow</h3>
                  {{#if @model.defaultWorkflow}}
                    <p class='wiz-hint'>Linked:
                      {{@model.defaultWorkflow.title}}
                      —
                      {{@model.defaultWorkflow.states.length}}
                      states. Waiting-kind states pause SLA clocks.</p>
                  {{else}}
                    <p class='wiz-hint'>No workflow linked yet — create a
                      Workflow card and link it on the desk's edit view, then
                      return here.</p>
                  {{/if}}
                {{/if}}
                {{#if (eq i 4)}}
                  <div class='wiz-import'>
                    <h3 class='wiz-h'>Import legacy cases</h3>
                    <p class='wiz-hint'>Upload the old helpdesk's CSV export
                      (columns: subject, status, opened, legacy_id). It is kept
                      in this workspace as the import's provenance, so it can be
                      re-run; earlier uploads are listed below. Per-row results
                      — failures are reported, never skipped.</p>
                    <div class='wiz-row wiz-upload'>
                      <input
                        type='file'
                        accept='.csv,text/csv'
                        class='boxel-sr-only'
                        aria-label='Choose a CSV file'
                        {{on 'change' this.uploadCsv}}
                      />
                      <Button
                        @kind='primary'
                        @size='small'
                        @loading={{this.uploadBusy}}
                        {{on 'click' this.openFilePicker}}
                      >
                        <PlusIcon width='16' height='16' role='presentation' />
                        Upload CSV
                      </Button>
                      {{#if this.uploadNote}}<span
                          class='wiz-picked'
                        >{{this.uploadNote}}</span>{{/if}}
                    </div>
                    {{#if @context.searchResultsComponent}}
                      {{#let
                        (component @context.searchResultsComponent)
                        as |SearchResults|
                      }}
                        <SearchResults
                          @query={{this.csvWireQuery}}
                          @mode='none'
                          as |results|
                        >
                          <ul
                            class='csv-picker'
                            aria-label='CSV files in this workspace'
                          >
                            {{#each results.entries key='id' as |entry|}}
                              <li class='csv-cell'>
                                <button
                                  type='button'
                                  class='csv-pick
                                    {{if
                                      (this.isPickedFile entry.id)
                                      "csv-pick-on"
                                    }}'
                                  aria-pressed='{{this.isPickedFile entry.id}}'
                                  {{on
                                    'click'
                                    (fn this.pickImportFile entry.id)
                                  }}
                                >
                                  <entry.component />
                                </button>
                              </li>
                            {{else}}
                              {{#if results.isLoading}}
                                <li class='desk-loading' role='status'>Looking
                                  for CSV files…</li>
                              {{else}}
                                <li class='desk-empty'>No importable CSV in this
                                  workspace yet — upload the export with columns
                                  subject, status, opened, legacy_id and it
                                  appears here.</li>
                              {{/if}}
                            {{/each}}
                          </ul>
                        </SearchResults>
                      {{/let}}
                    {{/if}}
                    <details class='wiz-alt'>
                      <summary>No file at hand? Paste CSV rows instead</summary>
                      <BoxelInput
                        @type='textarea'
                        @value={{this.importCsv}}
                        @onInput={{this.setImportCsv}}
                        @placeholder='subject,status,opened,legacy_id'
                      />
                    </details>
                    <div class='wiz-row'>
                      <span class='wiz-picked'>{{#if
                          this.importFileName
                        }}Source: <code>{{this.importFileName}}</code>{{else if
                          this.importCsv
                        }}Source: pasted rows{{else}}Pick a file or paste rows
                          to enable import{{/if}}</span>
                      <Button
                        @size='small'
                        @kind='primary'
                        @disabled={{unless this.canImport true}}
                        @loading={{this.importBusy}}
                        {{on 'click' this.runImport}}
                      >Import rows</Button>
                    </div>
                    {{#if this.importReport.length}}
                      <ul class='import-report'>
                        {{#each this.importReport as |line|}}<li><code
                            >{{line}}</code></li>{{/each}}
                      </ul>
                    {{/if}}
                  </div>
                {{/if}}
              </:step>
            </SetupWizard>
          {{/if}}
        </div>
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
              color-mix(
                in oklab,
                var(--primary, var(--boxel-highlight)) 7%,
                transparent
              ),
              transparent 70%
            ),
            var(--background, var(--boxel-light));
          color: var(--foreground, var(--boxel-dark));
          display: flex;
          flex-direction: column;
        }
        .desk-bar {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          flex-wrap: wrap;
          padding: var(--boxel-sp-xs) var(--boxel-sp);
          border-bottom: 1px solid var(--border, var(--boxel-border-color));
          background: color-mix(
            in oklab,
            var(--card, var(--boxel-light)) 88%,
            transparent
          );
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
        .desk-tabs {
          display: flex;
          gap: var(--boxel-sp-5xs);
          flex-wrap: wrap;
        }
        .desk-tab {
          position: relative;
          border: none;
          background: none;
          font: inherit;
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground, var(--boxel-450));
          padding: var(--boxel-sp-4xs) var(--boxel-sp-xs);
          border-radius: var(--boxel-border-radius-sm);
          cursor: pointer;
          transition: color 160ms ease-out;
        }
        /* underline indicator grows from the centre — the tab's own motion */
        .desk-tab::after {
          content: '';
          position: absolute;
          left: var(--boxel-sp-xs);
          right: var(--boxel-sp-xs);
          bottom: -0.125rem;
          height: 2px;
          border-radius: 1px;
          background: var(--primary, var(--boxel-highlight));
          transform: scaleX(0);
          transition: transform 220ms cubic-bezier(0.22, 1, 0.36, 1);
        }
        .desk-tab:hover {
          color: var(--foreground, var(--boxel-dark));
        }
        .desk-tab:focus-visible {
          outline: 2px solid var(--ring, var(--boxel-highlight));
          outline-offset: 1px;
        }
        .desk-tab-on {
          color: var(--foreground, var(--boxel-dark));
          font-weight: 600;
        }
        .desk-tab-on::after {
          transform: scaleX(1);
        }
        .desk-operator {
          margin-left: auto;
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
        }
        .desk-banner {
          text-align: left;
          border: none;
          border-left: 3px solid var(--boxel-warning);
          background: color-mix(
            in oklab,
            var(--boxel-warning) 8%,
            var(--card, var(--boxel-light))
          );
          color: var(--foreground, var(--boxel-dark));
          padding: var(--boxel-sp-4xs) var(--boxel-sp);
          font: inherit;
          font-size: var(--boxel-font-size-xs);
          cursor: pointer;
        }
        .desk-note {
          margin: var(--boxel-sp-xs) var(--boxel-sp) 0;
          padding: var(--boxel-sp-4xs) var(--boxel-sp-sm);
          border-left: 3px solid var(--primary, var(--boxel-highlight));
          border-radius: 0 var(--boxel-border-radius-sm)
            var(--boxel-border-radius-sm) 0;
          background: color-mix(
            in oklab,
            var(--primary, var(--boxel-highlight)) 7%,
            var(--card, var(--boxel-light))
          );
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
          color: var(--muted-foreground, var(--boxel-450));
        }
        /* ── view toggle + lane cards ── */
        .view-toggle {
          display: inline-flex;
          gap: 0.125rem;
          padding: 0.125rem;
          border-radius: 999px;
          background: var(--muted, var(--boxel-200));
          align-self: flex-start;
        }
        /* WCAG 2.5.8: the drawn control stays compact, the hit area is ~44px tall. */
        .hit-ext {
          position: relative;
        }
        .hit-ext::after {
          content: '';
          position: absolute;
          inset: -0.625rem 0;
        }
        .vt {
          border: none;
          background: none;
          font: inherit;
          font-size: var(--boxel-font-size-xs);
          font-weight: 500;
          color: var(--muted-foreground, var(--boxel-450));
          padding: 0.25rem 0.75rem;
          border-radius: 999px;
          cursor: pointer;
          transition:
            background 160ms ease-out,
            color 160ms ease-out;
        }
        .vt-on {
          background: var(--card, var(--boxel-light));
          color: var(--foreground, var(--boxel-dark));
          box-shadow: 0 1px 2px
            color-mix(
              in oklab,
              var(--foreground, var(--boxel-dark)) 12%,
              transparent
            );
        }
        .vt:focus-visible {
          outline: 2px solid var(--ring, var(--boxel-highlight));
          outline-offset: 1px;
        }
        /* card FACE inside the shared Board's card chrome — the Board owns
           hover, drag and selection; this only lays out the facts */
        .lcard {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-4xs);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm) var(--boxel-sp-xs)
            calc(var(--boxel-sp-sm) + 0.125rem);
          min-width: 0;
          height: 100%;
          border-left: 0.1875rem solid var(--lcard-accent, transparent);
          border-radius: 0 var(--boxel-border-radius-sm)
            var(--boxel-border-radius-sm) 0;
        }
        .lcard-top {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-4xs);
          min-width: 0;
        }
        .lcard-id {
          font-family: var(--font-mono, var(--boxel-monospace-font-family));
          font-size: var(--boxel-font-size-sm);
          font-weight: 600;
          flex: 1;
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .lcard-title {
          font-size: var(--boxel-font-size);
          line-height: 1.35;
          font-weight: 500;
          flex: 1;
          overflow: hidden;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
        }
        .lcard-foot {
          display: flex;
          justify-content: space-between;
          gap: var(--boxel-sp-4xs);
          margin-top: auto;
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground, var(--boxel-450));
        }
        .lcard-unowned {
          color: var(--boxel-warning);
          font-style: italic;
        }
        .lcard-clock {
          font-size: var(--boxel-font-size-sm);
        }
        .lcard-overdue {
          color: var(--boxel-danger);
        }
        .lcard-claim {
          align-self: flex-end;
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
          border: 1px solid transparent;
          border-radius: var(--boxel-border-radius);
          background: var(--card, var(--boxel-light));
          box-shadow: 0 1px 0
            color-mix(
              in oklab,
              var(--foreground, var(--boxel-dark)) 5%,
              transparent
            );
          cursor: pointer;
          overflow: hidden;
          text-align: left;
          font: inherit;
          color: inherit;
          transition:
            transform 160ms cubic-bezier(0.22, 1, 0.36, 1),
            border-color 160ms ease-out,
            box-shadow 160ms ease-out;
        }
        .case-open:hover,
        .case-open:focus-visible {
          transform: translateY(-1px);
          border-color: color-mix(
            in oklab,
            var(--primary, var(--boxel-highlight)) 40%,
            transparent
          );
          box-shadow: 0 8px 20px -12px
            color-mix(
              in oklab,
              var(--foreground, var(--boxel-dark)) 45%,
              transparent
            );
        }
        .case-open:focus-visible {
          outline: 2px solid var(--ring, var(--boxel-highlight));
          outline-offset: 2px;
        }
        .case-open > :deep(*) {
          width: 100%;
          height: 100%;
        }
        .table-wrap {
          overflow-x: auto;
          border: 1px solid var(--border, var(--boxel-border-color));
          border-radius: var(--boxel-border-radius);
        }
        /* ── copilot ── */
        .copilot {
          border: 1px solid transparent;
          box-shadow: 0 1px 0
            color-mix(
              in oklab,
              var(--foreground, var(--boxel-dark)) 5%,
              transparent
            );
          border-radius: var(--boxel-border-radius);
          background: var(--card, var(--boxel-light));
          padding: var(--boxel-sp-sm);
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-xs);
        }
        .copilot-title {
          margin: 0;
          font-size: var(--boxel-font-size-xs);
          letter-spacing: 0.1em;
          text-transform: uppercase;
          color: var(--muted-foreground, var(--boxel-450));
        }
        .copilot-pick {
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-4xs);
        }
        .copilot-draft {
          border: 1.5px dashed var(--primary, var(--boxel-highlight));
          border-radius: var(--boxel-border-radius);
          padding: var(--boxel-sp-sm);
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-4xs);
          background: color-mix(
            in oklab,
            var(--primary, var(--boxel-highlight)) 6%,
            var(--card, var(--boxel-light))
          );
        }
        .copilot-tag {
          font-size: var(--boxel-font-size-xs);
          letter-spacing: 0.1em;
          font-weight: 600;
          color: color-mix(
            in oklab,
            var(--primary, var(--boxel-highlight)) 38%,
            var(--card-foreground, var(--boxel-dark))
          );
        }
        .copilot-text {
          margin: 0;
          white-space: pre-wrap;
          font-size: var(--boxel-font-size-sm);
          max-width: 70ch;
        }
        .copilot-actions {
          display: flex;
          gap: var(--boxel-sp-4xs);
        }
        /* ── escalations tab ── */
        /* kanban planes scroll sideways by design; say so with a visible thin bar */
        .desk-body :deep(.kanban-plane) {
          scrollbar-width: thin;
        }
        .desk-refusal {
          margin: 0;
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          border-left: 3px solid var(--boxel-danger);
          border-radius: 0 var(--boxel-border-radius-sm)
            var(--boxel-border-radius-sm) 0;
          background: color-mix(
            in oklab,
            var(--boxel-danger) 8%,
            var(--card, var(--boxel-light))
          );
          font-size: var(--boxel-font-size-sm);
        }
        .esc-tab {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp);
        }
        .esc-history {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-xs);
        }
        .esc-line {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
        }
        .esc-open {
          flex: 1;
          text-align: left;
          border: 1px solid var(--border, var(--boxel-border-color));
          border-radius: var(--boxel-border-radius-sm);
          background: var(--card, var(--boxel-light));
          color: inherit;
          font: inherit;
          font-size: var(--boxel-font-size-sm);
          padding: var(--boxel-sp-4xs) var(--boxel-sp-xs);
          cursor: pointer;
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          transition: border-color 120ms ease-out;
        }
        .esc-open:hover,
        .esc-open:focus-visible {
          border-color: var(--primary, var(--boxel-highlight));
        }
        .esc-history-title {
          margin: 0;
          font-size: var(--boxel-font-size-xs);
          letter-spacing: 0.1em;
          text-transform: uppercase;
          color: var(--muted-foreground, var(--boxel-450));
        }
        /* ── wizard bodies ── */
        .wiz-h {
          margin: 0;
          font-size: var(--boxel-font-size);
          font-weight: 600;
        }
        .wiz-label {
          font-size: var(--boxel-font-size-xs);
          letter-spacing: 0.08em;
          text-transform: uppercase;
          color: var(--muted-foreground, var(--boxel-450));
        }
        .wiz-hint {
          margin: 0;
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground, var(--boxel-450));
          max-width: 60ch;
        }
        .wiz-preview {
          margin: 0;
          font-size: var(--boxel-font-size-sm);
        }
        .wiz-row {
          display: flex;
          justify-content: flex-end;
        }
        .wiz-preview code {
          font-family: var(--font-mono, var(--boxel-monospace-font-family));
          background: var(--muted, var(--boxel-200));
          border-radius: var(--boxel-border-radius-sm);
          padding: 0.125rem 0.5rem;
        }
        .wiz-ok {
          color: var(--boxel-success);
          margin-left: var(--boxel-sp-4xs);
        }
        .wiz-bad {
          color: var(--boxel-danger);
          margin-left: var(--boxel-sp-4xs);
        }
        .wiz-import {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-xs);
        }
        .wiz-upload {
          justify-content: flex-start;
        }
        .csv-picker {
          list-style: none;
          margin: 0;
          padding: 0;
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(15.625rem, 1fr));
          gap: var(--boxel-sp-xs);
        }
        .csv-cell {
          container-name: fitted-card;
          container-type: size;
          height: 4.0625rem;
        }
        .csv-pick {
          display: block;
          width: 100%;
          height: 100%;
          padding: 0;
          border: 2px solid var(--border, var(--boxel-border-color));
          border-radius: var(--boxel-border-radius);
          background: var(--card, var(--boxel-light));
          text-align: left;
          cursor: pointer;
          overflow: hidden;
          transition:
            border-color 120ms ease-out,
            box-shadow 120ms ease-out;
        }
        .csv-pick:hover,
        .csv-pick:focus-visible {
          border-color: color-mix(
            in oklab,
            var(--primary, var(--boxel-highlight)) 50%,
            transparent
          );
        }
        .csv-pick:focus-visible {
          outline: 2px solid var(--ring, var(--boxel-highlight));
          outline-offset: 2px;
        }
        .csv-pick-on {
          border-color: var(--primary, var(--boxel-highlight));
          box-shadow: 0 0 0 3px
            color-mix(
              in oklab,
              var(--primary, var(--boxel-highlight)) 18%,
              transparent
            );
        }
        .csv-pick > :deep(*) {
          pointer-events: none;
        }
        .wiz-alt {
          font-size: var(--boxel-font-size-sm);
        }
        .wiz-alt summary {
          cursor: pointer;
          color: var(--muted-foreground, var(--boxel-450));
          margin-bottom: var(--boxel-sp-4xs);
        }
        .wiz-picked {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
          margin-right: auto;
        }
        .import-report {
          margin: 0;
          padding-left: 1.2em;
          font-size: var(--boxel-font-size-xs);
          max-height: 12rem;
          overflow: auto;
        }
        @media (prefers-reduced-motion: reduce) {
          .desk-tab,
          .desk-tab::after,
          .case-open,
          .esc-open {
            transition: none;
          }
          .desk-note,
          .desk-body {
            animation: none;
          }
        }
      </style>
    </template>

    deskTabs = TABS;
    subjectTitle = (e: Escalation) => e.subjectTitle ?? '?';
  };
  static edit = class Edit extends Component<typeof this> {
    @tracked activeSection = 'identity';

    sections = [
      { id: 'identity', label: 'Desk' },
      { id: 'config', label: 'Configuration' },
      { id: 'links', label: 'Process & people' },
    ];

    goTo = (id: string, event: Event) => {
      this.activeSection = id;
      let root = (event.currentTarget as HTMLElement).closest('.desk-edit');
      root
        ?.querySelector(`[data-sect='${id}']`)
        ?.scrollIntoView({ block: 'start', behavior: 'smooth' });
    };

    <template>
      <div class='desk-edit'>
        <div class='edit-body'>
          <EditSectionNav
            @sections={{this.sections}}
            @activeId={{this.activeSection}}
            @onSelect={{this.goTo}}
            class='sect-nav'
          />
          <div class='sects'>
            <section
              class='sect {{if (eq this.activeSection "identity") "focused"}}'
              data-sect='identity'
            >
              <h3>Desk</h3>
              <FieldContainer @label='Name' @vertical={{true}}>
                <@fields.appName />
              </FieldContainer>
              <FieldContainer
                @label='Operator (who is at the desk)'
                @vertical={{true}}
              >
                <@fields.operator />
              </FieldContainer>
            </section>
            <section
              class='sect {{if (eq this.activeSection "config") "focused"}}'
              data-sect='config'
            >
              <h3>Configuration
                <span class='sect-hint'>the Setup tab edits this step by step</span></h3>
              <FieldContainer @label='Configuration' @vertical={{true}}>
                <@fields.config />
              </FieldContainer>
            </section>
            <section
              class='sect {{if (eq this.activeSection "links") "focused"}}'
              data-sect='links'
            >
              <h3>Process & people</h3>
              <FieldContainer @label='Default workflow' @vertical={{true}}>
                <@fields.defaultWorkflow />
              </FieldContainer>
              <FieldContainer @label='Roles' @vertical={{true}}>
                <@fields.roles />
              </FieldContainer>
              <FieldContainer @label='Round-robin pool' @vertical={{true}}>
                <@fields.candidatePool />
              </FieldContainer>
            </section>
          </div>
        </div>
      </div>
      <style scoped>
        /* Same edit shell as Case / Escalation in this kit (edit-card Rule 1):
           the root is the named container AND the scroller, so the rail can
           be sticky and the query below can actually fire. */
        .desk-edit {
          container-type: inline-size;
          container-name: edit;
          height: 100%;
          overflow-y: auto;
          padding: var(--boxel-sp);
          background: var(--background, var(--boxel-light));
          color: var(--foreground, var(--boxel-dark));
          --desk-ink: var(--foreground, var(--boxel-dark));
        }
        .edit-body {
          display: grid;
          grid-template-columns: 9.5rem minmax(0, 1fr);
          gap: var(--boxel-sp);
          align-items: start;
        }
        .sect-nav {
          position: sticky;
          top: 0;
        }
        @container edit (width < 640px) {
          .edit-body {
            grid-template-columns: 1fr;
          }
          .sect-nav {
            position: static;
          }
        }
        .sects {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp);
          min-width: 0;
        }
        .sect {
          display: grid;
          gap: var(--boxel-sp-sm);
          border: 1px solid var(--border, var(--boxel-200));
          border-radius: var(--radius, var(--boxel-border-radius));
          background: var(--card, var(--boxel-light));
          padding: var(--boxel-sp);
          scroll-margin-top: var(--boxel-sp);
          outline: 2px solid transparent;
          outline-offset: 2px;
          transition:
            outline-color 160ms ease,
            box-shadow 160ms ease;
        }
        /* the section the rail points at mirrors the rail's active state */
        .sect.focused {
          outline-color: var(--desk-ink);
          box-shadow: 0 0 0 4px
            color-mix(in oklch, var(--desk-ink) 12%, transparent);
        }
        .sect h3 {
          margin: 0;
          font-size: 0.8125rem;
          letter-spacing: 0.08em;
          text-transform: uppercase;
          color: var(--muted-foreground, var(--boxel-450));
          display: flex;
          align-items: baseline;
          gap: var(--boxel-sp-xs);
          flex-wrap: wrap;
        }
        .sect-hint {
          text-transform: none;
          letter-spacing: normal;
          font-size: 0.75rem;
          font-weight: 400;
          font-style: italic;
        }
      </style>
    </template>
  };
}

export default SupportCaseApp;
