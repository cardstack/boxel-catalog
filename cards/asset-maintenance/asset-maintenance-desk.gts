import type { AssetMaintenanceApp } from './asset-maintenance-app';
import {
  CardDef,
  Component,
  realmURL,
  type Format,
} from '@cardstack/base/card-api';
import {
  identifyCard,
  type getCards,
  type LooseSingleCardDocument,
  type ResolvedCodeRef,
} from '@cardstack/runtime-common';
import { tracked } from '@glimmer/tracking';
import { action } from '@ember/object';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import type Owner from '@ember/owner';
import { htmlSafe } from '@ember/template';
import { isDestroyed, isDestroying } from '@ember/destroyable';
import { restartableTask } from 'ember-concurrency';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import { isValidIdentifierPattern } from '@cardstack/catalog/fields/record-identifier/record-identifier-field';

import { Alert } from '@cardstack/pretui/components/alert';
import { Button } from '@cardstack/pretui/components/button';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { Field } from '@cardstack/pretui/components/field';
import { FilterChips } from '@cardstack/pretui/components/filter-chips';
import { Input } from '@cardstack/pretui/components/input';
import { LayoutControl } from '@cardstack/pretui/components/layout-control';
import { SearchInput } from '@cardstack/pretui/components/search-input';
import { SegmentedControl } from '@cardstack/pretui/components/segmented-control';
import {
  Sidebar,
  SidebarGroup,
  SidebarItem,
  SidebarTrigger,
} from '@cardstack/pretui/components/sidebar';
import { Stat } from '@cardstack/pretui/components/stat';
import { Table } from '@cardstack/pretui/components/table';
import { Wizard, type WizardStep } from '@cardstack/pretui/components/wizard';

import HomeIcon from '@cardstack/boxel-icons/home';
import BoxIcon from '@cardstack/boxel-icons/box';
import CalendarIcon from '@cardstack/boxel-icons/calendar';
import ClipboardListIcon from '@cardstack/boxel-icons/clipboard-list';
import SettingsIcon from '@cardstack/boxel-icons/settings';
import PlusIcon from '@cardstack/boxel-icons/plus';

import { Asset } from '../maintenance/asset';
import { AssetCategory } from '../maintenance/asset-category';
import { MaintenancePlan } from '../maintenance/maintenance-plan';
import { WorkOrder } from '../maintenance/work-order';
import { SparePart } from '../maintenance/spare-part';
import { Meter } from '../maintenance/meter';
import {
  WO_TERMINAL,
  WORK_ORDER_KINDS,
  WO_KIND_LABEL,
} from '../maintenance/maintenance-vocabulary';
import { MaintenanceCalendar } from '../maintenance/components/maintenance-calendar';
import { WorkOrderBoard } from '../maintenance/components/work-order-board';
import { dayKey } from '../maintenance/utils/recurrence';
import { matchesSearch } from '../maintenance/utils/display';
import {
  isPlanOccurrenceRaised,
  raisedPlanOccurrences,
} from '../maintenance/utils/maintenance';
import {
  ADD_FORMS,
  CHIP_FORMS,
  HORIZON_DAYS,
  MS_PER_DAY,
  SEARCH_FORMS,
  SEQ_SLOT,
  VIEW_FORMS,
  assetDot,
  assetLabel,
  daysOut,
  dot,
  dueText,
  eq,
  nextIdentifier,
  startOfDay,
  woDot,
  woLabel,
} from './desk-helpers';
import { money } from '../maintenance/card-ui';

type Tab = 'home' | 'assets' | 'work' | 'plans' | 'setup';

const TABS: { key: Tab; label: string; icon: any }[] = [
  { key: 'home', label: 'Home', icon: HomeIcon },
  { key: 'assets', label: 'Assets', icon: BoxIcon },
  { key: 'work', label: 'Work', icon: CalendarIcon },
  { key: 'plans', label: 'Plans & Parts', icon: ClipboardListIcon },
  { key: 'setup', label: 'Setup', icon: SettingsIcon },
];

const SETUP_STEPS: WizardStep[] = [
  { id: 'desk', label: 'Desk', detail: 'Name and time zone' },
  {
    id: 'identifiers',
    label: 'Identifiers',
    detail: 'Asset and work order ids',
  },
  { id: 'money', label: 'Money', detail: 'Currency and approval threshold' },
];

const HOME_CHIPS = [
  { value: 'all', label: 'All' },
  { value: 'late', label: 'Late' },
  { value: 'week', label: 'This week' },
];

const WORK_VIEWS = [
  { value: 'calendar', label: 'Calendar' },
  { value: 'board', label: 'Board' },
];

const KIND_OPTIONS = [
  { value: 'all', label: 'All kinds' },
  ...WORK_ORDER_KINDS.map((k) => ({ value: k, label: WO_KIND_LABEL[k] ?? k })),
];

// The load band starts a few days back so late work has somewhere to sit.
const LOAD_BACK_DAYS = 3;
const LOAD_STACK_CAP = 4;

const DATE_LINE = new Intl.DateTimeFormat('en-US', {
  weekday: 'short',
  month: 'short',
  day: 'numeric',
});
const MONTH_LINE = new Intl.DateTimeFormat('en-US', {
  month: 'long',
  year: 'numeric',
});

type Attention = {
  id: string;
  card: CardDef;
  label: string;
  detail: string;
  tag: string;
  tone: string;
};
type LoadColumn = {
  key: string;
  tick: string;
  late: number[];
  due: number[];
  planned: number[];
};

export class AssetMaintenanceDesk extends Component<
  typeof AssetMaintenanceApp
> {
  @tracked tab: Tab = 'home';
  @tracked homeSearch = '';
  @tracked homeFilter = 'all';
  @tracked assetSearch = '';
  @tracked workView = 'calendar';
  @tracked workKind = 'all';
  @tracked collection = 'plans';
  @tracked planSearch = '';
  @tracked planFilter = 'all';
  @tracked partFilter = 'all';
  @tracked deskError: string | undefined;
  // The day currently minting a Work Order; the calendar shows a spinner there.
  @tracked addingWorkOrderOn: Date | undefined;
  @tracked private queriesStarted = false;

  private assetQuery: ReturnType<getCards> | undefined;
  private categoryQuery: ReturnType<getCards> | undefined;
  private planQuery: ReturnType<getCards> | undefined;
  private workOrderQuery: ReturnType<getCards> | undefined;
  private partQuery: ReturnType<getCards> | undefined;
  private meterQuery: ReturnType<getCards> | undefined;
  // A card's realm never changes, so the query realms are read once; reading
  // them per render would re-run every live query whenever the desk saves.
  private realms: string[] | undefined;

  constructor(owner: Owner, args: any) {
    super(owner, args);
    let url = this.args.model?.[realmURL];
    this.realms = url ? [url.href] : undefined;
    this.assetQuery = this.liveQuery(Asset);
    this.categoryQuery = this.liveQuery(AssetCategory);
    this.planQuery = this.liveQuery(MaintenancePlan);
    this.workOrderQuery = this.liveQuery(WorkOrder);
    this.partQuery = this.liveQuery(SparePart);
    this.meterQuery = this.liveQuery(Meter);
    // Queries start outside a render: two first runs in one render re-run
    // each other mid-render.
    void Promise.resolve().then(() => {
      if (isDestroying(this) || isDestroyed(this)) return;
      for (let q of [
        this.assetQuery,
        this.categoryQuery,
        this.planQuery,
        this.workOrderQuery,
        this.partQuery,
        this.meterQuery,
      ]) {
        void q?.isLoading;
      }
      this.queriesStarted = true;
    });
  }

  // The query object is built once: a new one per call re-derives the search
  // as a tracked write that can land mid-render.
  private liveQuery(type: typeof CardDef) {
    let ref = identifyCard(type);
    let query = ref ? { filter: { type: ref } } : undefined;
    return this.args.context?.getCards(
      this,
      () => query,
      () => this.realms,
      { isLive: true },
    );
  }

  private instancesOf<T>(query: ReturnType<getCards> | undefined): T[] {
    if (!this.queriesStarted) return [];
    return ((query?.instances ?? []) as T[]).filter(Boolean);
  }

  get assets() {
    return this.instancesOf<Asset>(this.assetQuery);
  }
  get plans() {
    return this.instancesOf<MaintenancePlan>(this.planQuery);
  }
  get workOrders() {
    return this.instancesOf<WorkOrder>(this.workOrderQuery);
  }
  get parts() {
    return this.instancesOf<SparePart>(this.partQuery);
  }
  get meters() {
    return this.instancesOf<Meter>(this.meterQuery);
  }
  get loading() {
    return !this.queriesStarted || Boolean(this.workOrderQuery?.isLoading);
  }

  get currency() {
    return this.args.model.currency || 'USD';
  }
  get threshold() {
    return this.args.model.costApprovalThreshold ?? undefined;
  }

  // ── derived collections ───────────────────────────────────────────────
  get openWorkOrders() {
    return this.workOrders.filter((wo) => !WO_TERMINAL.has(wo.status ?? ''));
  }
  get lateWorkOrders() {
    return this.openWorkOrders.filter((wo) => wo.isOverdue);
  }
  get awaitingApproval() {
    let limit = this.threshold;
    if (limit == null) return [];
    return this.openWorkOrders.filter(
      (wo) => wo.status === 'requested' && (wo.totalCost ?? 0) > limit,
    );
  }
  get lowParts() {
    return this.parts.filter((p) => p.belowReorderPoint);
  }
  get unraisedPlans() {
    let raised = raisedPlanOccurrences(this.workOrders);
    return this.plans.filter(
      (p) =>
        p.active &&
        p.nextDueAt &&
        !isPlanOccurrenceRaised(raised, p.id, p.nextDueAt),
    );
  }
  private within(d: Date | string | null | undefined, days: number) {
    let n = daysOut(d);
    return n != null && n >= 0 && n <= days;
  }
  get dueSoonWorkOrders() {
    return this.openWorkOrders.filter((wo) =>
      this.within(wo.dueBy ?? wo.scheduledFor, HORIZON_DAYS),
    );
  }
  get dueSoonPlans() {
    return this.unraisedPlans.filter((p) =>
      this.within(p.nextDueAt, HORIZON_DAYS),
    );
  }

  get stats() {
    let known = !this.loading;
    let v = (n: number) => (known ? n : '—');
    return [
      {
        label: 'Late work orders',
        value: v(this.lateWorkOrders.length),
        hint: 'past their due day',
        tone: 'destructive',
      },
      {
        label: `Due next ${HORIZON_DAYS} days`,
        value: v(this.dueSoonWorkOrders.length + this.dueSoonPlans.length),
        hint: `${this.dueSoonPlans.length} from plans`,
        tone: 'warning',
      },
      {
        label: 'Open work',
        value: v(this.openWorkOrders.length),
        hint: 'not closed or canceled',
        tone: 'info',
      },
      {
        label: 'Awaiting approval',
        value: v(this.awaitingApproval.length),
        hint:
          this.threshold == null
            ? 'no threshold set'
            : `over ${money(this.threshold, this.currency, 0)}`,
        tone: 'warning',
      },
      {
        label: 'Parts below reorder',
        value: v(this.lowParts.length),
        hint: `of ${this.parts.length} parts`,
        tone: 'destructive',
      },
    ];
  }

  get navItems() {
    let setupStep = Math.min(
      (this.args.model.config?.setupStep ?? 0) + 1,
      SETUP_STEPS.length,
    );
    let badges: Record<Tab, string | undefined> = {
      home: undefined,
      assets: String(this.assets.length),
      work: String(this.openWorkOrders.length),
      plans: this.lowParts.length ? `${this.lowParts.length} low` : undefined,
      setup: this.isSetUp ? undefined : `${setupStep}/${SETUP_STEPS.length}`,
    };
    return TABS.map((t) => ({
      ...t,
      badge: this.loading ? undefined : badges[t.key],
    }));
  }

  get currentTab() {
    return TABS.find((t) => t.key === this.tab)!;
  }

  get dateLine() {
    let tz = this.args.model.timeZone;
    let opts = tz ? { timeZone: tz } : {};
    let day: string;
    try {
      day = new Intl.DateTimeFormat('en-US', {
        ...opts,
        weekday: 'short',
        month: 'short',
        day: 'numeric',
      }).format(new Date());
    } catch {
      day = DATE_LINE.format(new Date());
    }
    return tz ? `${day} · ${tz}` : day;
  }

  get isSetUp() {
    return Boolean(this.args.model.config?.setupCompletedAt);
  }

  // ── home ──────────────────────────────────────────────────────────────
  get homeRows() {
    return this.openWorkOrders
      .filter((wo) => {
        let n = daysOut(wo.dueBy ?? wo.scheduledFor);
        if (this.homeFilter === 'late' && !wo.isOverdue) return false;
        if (this.homeFilter === 'week' && !(n != null && n <= 7)) return false;
        return matchesSearch(
          this.homeSearch,
          wo.title,
          wo.identifier?.value,
          wo.assetName,
          wo.assetTag,
        );
      })
      .sort(
        (a, b) =>
          startOfDay(a.dueBy ?? a.scheduledFor ?? 8.64e15) -
          startOfDay(b.dueBy ?? b.scheduledFor ?? 8.64e15),
      );
  }

  isLate = (wo: WorkOrder) => Boolean(wo.isOverdue);
  woDue = (wo: WorkOrder) => dueText(wo.dueBy ?? wo.scheduledFor);
  woCost = (wo: WorkOrder) => money(wo.totalCost, this.currency, 0);

  get attention(): Attention[] {
    let out: Attention[] = [];
    for (let wo of this.awaitingApproval) {
      out.push({
        id: wo.id,
        card: wo,
        label: `${wo.identifier?.value ?? ''} ${wo.title ?? ''}`.trim(),
        detail: `${money(wo.totalCost, this.currency, 0)} is over the ${money(this.threshold, this.currency, 0)} threshold`,
        tag: 'Approval',
        tone: 'var(--warning)',
      });
    }
    for (let part of this.lowParts) {
      out.push({
        id: part.id,
        card: part,
        label: part.name ?? part.partNumber ?? 'Spare part',
        detail: `${part.onHand ?? 0} on hand, reorder at ${part.reorderPoint ?? 0}`,
        tag: 'Low stock',
        tone: 'var(--destructive)',
      });
    }
    for (let meter of this.meters) {
      if (!meter.isWarning) continue;
      out.push({
        id: meter.id,
        card: meter,
        label: `${meter.assetName ?? 'Asset'} ${meter.name ?? ''}`.trim(),
        detail: `${meter.currentLabel ?? ''} · ${meter.isWarning} threshold`,
        tag: 'Meter',
        tone: 'var(--warning)',
      });
    }
    for (let asset of this.assets) {
      if (asset.status !== 'out-of-service') continue;
      out.push({
        id: asset.id,
        card: asset,
        label: asset.cardTitle ?? 'Asset',
        detail: asset.locationName ?? 'Out of service',
        tag: 'Down',
        tone: 'var(--destructive)',
      });
    }
    return out;
  }

  get statusRows() {
    let counts = new Map<string, number>();
    for (let wo of this.openWorkOrders) {
      let s = wo.status ?? 'requested';
      counts.set(s, (counts.get(s) ?? 0) + 1);
    }
    let max = Math.max(1, ...counts.values());
    return [...counts.entries()]
      .sort((a, b) => b[1] - a[1])
      .map(([status, count]) => ({
        status,
        label: woLabel(status),
        count,
        fill: htmlSafe(`inline-size: ${Math.round((count / max) * 100)}%`),
      }));
  }

  // Each day is one column of up to four blocks: late, due, then planned.
  get loadColumns(): LoadColumn[] {
    let today = startOfDay(new Date());
    let cols: LoadColumn[] = [];
    let idx = new Map<number, LoadColumn>();
    for (let d = -LOAD_BACK_DAYS; d <= HORIZON_DAYS; d++) {
      let date = new Date(today + d * MS_PER_DAY);
      let tick =
        d === -LOAD_BACK_DAYS || d === HORIZON_DAYS
          ? new Intl.DateTimeFormat('en-US', {
              month: 'short',
              day: 'numeric',
            }).format(date)
          : d === 0
            ? 'Now'
            : '';
      let col = {
        key: String(d),
        tick,
        late: [],
        due: [],
        planned: [],
      } as LoadColumn;
      cols.push(col);
      idx.set(d, col);
    }
    let put = (n: number | undefined, kind: 'late' | 'due' | 'planned') => {
      if (n == null) return;
      let col = idx.get(Math.max(-LOAD_BACK_DAYS, Math.min(HORIZON_DAYS, n)));
      if (!col) return;
      let used = col.late.length + col.due.length + col.planned.length;
      if (used < LOAD_STACK_CAP) col[kind].push(used);
    };
    for (let wo of this.openWorkOrders) {
      let n = daysOut(wo.dueBy ?? wo.scheduledFor);
      if (n == null || n > HORIZON_DAYS) continue;
      put(n, wo.isOverdue ? 'late' : 'due');
    }
    for (let p of this.unraisedPlans) {
      let n = daysOut(p.nextDueAt);
      if (n == null || n > HORIZON_DAYS || n < 0) continue;
      put(n, 'planned');
    }
    return cols;
  }

  // ── assets / plans / parts ────────────────────────────────────────────
  get assetRows() {
    return this.assets.filter((a) =>
      matchesSearch(
        this.assetSearch,
        a.cardTitle,
        a.tag,
        a.categoryName,
        a.locationName,
      ),
    );
  }

  get planCounts() {
    let active = this.plans.filter((p) => p.active).length;
    return {
      all: this.plans.length,
      active,
      inactive: this.plans.length - active,
    };
  }
  get planChips() {
    let c = this.planCounts;
    return [
      { value: 'all', label: 'All', count: c.all },
      { value: 'active', label: 'Active', count: c.active },
      { value: 'inactive', label: 'Inactive', count: c.inactive },
    ];
  }
  get partChips() {
    return [
      { value: 'all', label: 'All', count: this.parts.length },
      { value: 'reorder', label: 'Below reorder', count: this.lowParts.length },
    ];
  }
  get collectionOptions() {
    let low = this.lowParts.length;
    return [
      { value: 'plans', label: `Plans · ${this.plans.length}` },
      {
        value: 'parts',
        label: low
          ? `Parts · ${this.parts.length} (${low} low)`
          : `Parts · ${this.parts.length}`,
      },
    ];
  }
  get planRows() {
    return this.plans
      .filter((p) => {
        if (this.planFilter === 'active' && !p.active) return false;
        if (this.planFilter === 'inactive' && p.active) return false;
        return matchesSearch(this.planSearch, p.name, p.assetTag);
      })
      .sort(
        (a, b) =>
          (a.nextDueAt ? startOfDay(a.nextDueAt) : Infinity) -
          (b.nextDueAt ? startOfDay(b.nextDueAt) : Infinity),
      );
  }
  get partRows() {
    return this.parts.filter((p) => {
      if (this.partFilter === 'reorder' && !p.belowReorderPoint) return false;
      return matchesSearch(this.planSearch, p.partNumber, p.name);
    });
  }
  planUrgency = (p: MaintenancePlan) => {
    if (p.isOverdue) return 'neg';
    let n = daysOut(p.nextDueAt);
    let lead = p.trigger?.leadDays ?? HORIZON_DAYS;
    return n != null && n <= lead ? 'warn' : '';
  };
  activeDot = (on: boolean | null | undefined) =>
    dot(on ? 'var(--success)' : undefined);
  stockDot = (low: boolean | null | undefined) =>
    dot(low ? 'var(--warning)' : 'var(--success)');

  get monthLine() {
    return MONTH_LINE.format(new Date());
  }

  // ── setup ─────────────────────────────────────────────────────────────
  get setupIndex() {
    let step = this.args.model.config?.setupStep ?? 0;
    return Math.min(step, SETUP_STEPS.length - 1);
  }
  get setupLine() {
    return `Step ${this.setupIndex + 1} of ${SETUP_STEPS.length} · Money settings and id patterns are set here; the desk is ready once every step is saved.`;
  }
  get idPatternValid() {
    return isValidIdentifierPattern(this.args.model.config?.idPattern);
  }
  // Work order numbers run on one counter across years, so a sequence slot is
  // all their pattern needs.
  get workOrderPatternValid() {
    return SEQ_SLOT.test(this.args.model.workOrderPattern ?? '');
  }
  get thresholdText() {
    let n = this.args.model.costApprovalThreshold;
    return n == null ? '' : String(n);
  }

  // ── actions ───────────────────────────────────────────────────────────
  setTab = (t: Tab) => (this.tab = t);
  setHomeSearch = (v: string) => (this.homeSearch = v);
  setHomeFilter = (v: string) => (this.homeFilter = v);
  setAssetSearch = (v: string) => (this.assetSearch = v);
  setWorkView = (v: string) => (this.workView = v);
  setWorkKind = (v: string) => (this.workKind = v);
  setCollection = (v: string) => (this.collection = v);
  setPlanSearch = (v: string) => (this.planSearch = v);
  setPlanFilter = (v: string) => (this.planFilter = v);
  setPartFilter = (v: string) => (this.partFilter = v);

  @action openCard(card: unknown, format: Format = 'isolated') {
    this.args.viewCard?.(card as CardDef, format);
  }

  @action setSetupStep(index: number) {
    let config = this.args.model.config;
    if (config) config.setupStep = index;
  }
  @action completeSetup() {
    let config = this.args.model.config;
    if (config) config.setupCompletedAt = new Date();
  }
  @action updateName(v: string) {
    this.args.model.name = v;
  }
  @action updateTimeZone(v: string) {
    this.args.model.timeZone = v;
  }
  @action updateCurrency(v: string) {
    this.args.model.currency = v;
  }
  @action updateThreshold(v: string) {
    let n = Number(v);
    if (v.trim() !== '' && Number.isFinite(n)) {
      this.args.model.costApprovalThreshold = n;
    }
  }
  @action updateIdPattern(v: string) {
    if (this.args.model.config) this.args.model.config.idPattern = v;
  }
  @action updateWorkOrderPattern(v: string) {
    this.args.model.workOrderPattern = v;
  }

  // Every "Add" opens the new card through `createCard`; each live query picks
  // it up once it indexes.
  private async createRecord(
    type: typeof CardDef,
    attributes: Record<string, unknown>,
  ): Promise<boolean> {
    this.deskError = undefined;
    let createCard = this.args.createCard;
    let ref = identifyCard(type) as ResolvedCodeRef | undefined;
    if (!createCard || !ref) {
      this.deskError = 'Adding records is unavailable in this view.';
      return false;
    }
    try {
      let realmHref = this.realms?.[0];
      let realm = realmHref ? new URL(realmHref) : undefined;
      let doc: LooseSingleCardDocument = {
        data: { type: 'card', attributes, meta: { adoptsFrom: ref } },
      };
      await createCard(ref, realm, { realmURL: realm, doc });
      return true;
    } catch (error: any) {
      this.deskError = error?.message ?? String(error);
      return false;
    }
  }

  // Each mint advances the desk's own counter, so a second add before the
  // first record indexes still gets the next number.
  private mintAssetIdentifier() {
    let config = this.args.model.config;
    if (!config || !this.idPatternValid) return undefined;
    let now = new Date();
    let minted = nextIdentifier(
      config.idPattern,
      config.identifierSeq,
      this.assets.map((a) => a.identifier?.value),
      now,
    );
    if (!minted) return undefined;
    config.identifierSeq = minted.seq;
    return {
      value: minted.value,
      pattern: config.idPattern ?? '',
      issuedAt: now.toISOString(),
    };
  }
  private mintWorkOrderIdentifier() {
    let model = this.args.model;
    if (!this.workOrderPatternValid) return undefined;
    let now = new Date();
    let minted = nextIdentifier(
      model.workOrderPattern,
      model.workOrderSeq,
      this.workOrders.map((wo) => wo.identifier?.value),
      now,
    );
    if (!minted) return undefined;
    model.workOrderSeq = minted.seq;
    return {
      value: minted.value,
      pattern: model.workOrderPattern ?? '',
      issuedAt: now.toISOString(),
    };
  }

  @action async addAsset() {
    let config = this.args.model.config;
    let previousSeq = config?.identifierSeq;
    let identifier = this.mintAssetIdentifier();
    if (!identifier) {
      this.deskError =
        'Set an asset id pattern such as AST-{yyyy}-{seq4} in Setup.';
      return;
    }
    let created = await this.createRecord(Asset, {
      name: 'New Asset',
      identifier,
    });
    // A failed create gives its number back.
    if (!created && config) config.identifierSeq = previousSeq ?? 0;
  }
  @action addPlan() {
    void this.createRecord(MaintenancePlan, { name: 'New Maintenance Plan' });
  }
  @action addPart() {
    void this.createRecord(SparePart, { name: 'New Spare Part' });
  }
  @action addWorkOrderToday() {
    void this.addWorkOrderTask.perform(new Date());
  }
  selectDay = (date: Date) => {
    void this.addWorkOrderTask.perform(date);
  };

  private addWorkOrderTask = restartableTask(async (date: Date) => {
    this.addingWorkOrderOn = date;
    try {
      let previousSeq = this.args.model.workOrderSeq;
      let identifier = this.mintWorkOrderIdentifier();
      if (!identifier) {
        this.deskError =
          'Set a work order id pattern with a sequence, such as WO-{seq4}, in Setup.';
        return;
      }
      let created = await this.createRecord(WorkOrder, {
        title: 'New Work Order',
        kind: 'corrective',
        status: 'requested',
        scheduledFor: dayKey(date),
        identifier,
      });
      if (!created) this.args.model.workOrderSeq = previousSeq;
    } finally {
      this.addingWorkOrderOn = undefined;
    }
  });

  // Drag-to-reschedule on the calendar and drag-to-status on the board hand
  // over a Work Order to save.
  @action async saveWorkOrder(wo: WorkOrder) {
    let commandContext = this.args.context?.commandContext;
    if (!wo || !commandContext) return;
    try {
      await new SaveCardCommand(commandContext).execute({ card: wo } as any);
    } catch (error: any) {
      this.deskError = error?.message ?? String(error);
    }
  }

  <template>
    <Sidebar
      class='am-shell'
      @label='Asset & Maintenance'
      @collapsible='rail'
      @railBreakpoint={{1100}}
      @mobileBreakpoint={{720}}
      @scroll='content'
      @resizable={{true}}
      @width='13.5rem'
      @shortcut={{false}}
    >
      <:header as |bar|>
        <div class='am-brand'>
          <span class='am-mark' aria-hidden='true'>AM</span>
          {{#unless bar.collapsed}}
            <p class='am-brand-text'>
              <span class='eyebrow'>Facilities</span>
              Asset & Maintenance
            </p>
          {{/unless}}
        </div>
      </:header>
      <:nav as |bar|>
        <SidebarGroup @label='Desk'>
          {{#each this.navItems as |item|}}
            <SidebarItem
              @label={{item.label}}
              @icon={{item.icon}}
              @badge={{unless bar.collapsed item.badge}}
              @active={{eq this.tab item.key}}
              @collapsed={{bar.collapsed}}
              @onClick={{fn this.setTab item.key}}
            />
          {{/each}}
        </SidebarGroup>
      </:nav>
      <:footer as |bar|>
        {{#unless bar.collapsed}}
          <p class='am-foot mono'>{{@model.timeZone}} · {{this.currency}}</p>
        {{/unless}}
      </:footer>
      <:default as |bar|>
        <div class='am-layout {{if (eq this.tab "home") "has-aside"}}'>
          <main class='am-main'>
            {{#if bar.mobile}}
              <SidebarTrigger
                @open={{bar.open}}
                @onToggle={{bar.toggle}}
                @controls={{bar.controls}}
                @label='navigation'
              />
            {{/if}}
            <header class='am-head'>
              <p class='eyebrow'>Asset & Maintenance ·
                {{this.currentTab.label}}</p>
              <h1 class='am-h1'>{{@model.cardTitle}}</h1>
              <p class='am-sub mono'>{{this.dateLine}}</p>
            </header>

            <section class='am-stats' aria-label='Desk totals'>
              <div class='am-stat-cells'>
                {{#each this.stats as |st|}}
                  <div class='am-stat'>
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

            {{#if this.deskError}}
              <Alert @tone='danger'>{{this.deskError}}</Alert>
            {{/if}}

            {{#if (eq this.tab 'home')}}
              {{#unless this.isSetUp}}
                <div class='block am-setup-line'>
                  <span class='status'><span
                      class='dot'
                      style={{dot 'var(--warning)'}}
                    ></span>Setup is still in progress.</span>
                  <Button
                    @size='s'
                    @appearance='plain'
                    class='push'
                    {{on 'click' (fn this.setTab 'setup')}}
                  >Finish setup</Button>
                </div>
              {{/unless}}
              <section class='block'>
                <div class='block-head'>
                  <h2>Open work orders</h2>
                  <p class='block-meta mono'>{{this.homeRows.length}}</p>
                </div>
                <div class='block-tools'>
                  <LayoutControl
                    @label='Work order tools'
                    @controlHeight='1.625rem'
                    as |lc|
                  >
                    <lc.Slot
                      @id='search'
                      @priority={{2}}
                      @forms={{SEARCH_FORMS}}
                      @label='Search'
                    >
                      <div class='am-search'><SearchInput
                          @value={{this.homeSearch}}
                          @placeholder='Search work orders'
                          @onInput={{this.setHomeSearch}}
                        /></div>
                    </lc.Slot>
                    <lc.Slot
                      @id='filter'
                      @priority={{3}}
                      @forms={{CHIP_FORMS}}
                      @label='Show'
                    >
                      <FilterChips
                        @options={{HOME_CHIPS}}
                        @value={{this.homeFilter}}
                        @onValueChange={{this.setHomeFilter}}
                        @label='Show'
                      />
                    </lc.Slot>
                    <lc.Slot
                      @id='add'
                      @priority={{0}}
                      @pinned={{true}}
                      @forms={{ADD_FORMS}}
                      @label='Add work order'
                      as |form|
                    >
                      <Button
                        class='push'
                        @icon={{PlusIcon}}
                        @tone='primary'
                        @size='s'
                        @display={{if (eq form 'icon') 'icon' 'label'}}
                        @label='Add work order'
                        {{on 'click' this.addWorkOrderToday}}
                      >Add work order</Button>
                    </lc.Slot>
                  </LayoutControl>
                </div>
                <div class='tbl-wrap'>
                  <Table class='tbl' @framed={{false}} @striped={{false}}>
                    <:head>
                      <tr>
                        <th>ID</th>
                        <th class='wide'>Work · Asset</th>
                        <th>Team</th>
                        <th>Status</th>
                        <th class='num'>Est. cost</th>
                        <th class='num'>Due</th>
                      </tr>
                    </:head>
                    <:body>
                      {{#each this.homeRows key='id' as |wo|}}
                        <tr>
                          <td class='strong'>
                            <Button
                              class='link'
                              @tone='neutral'
                              @appearance='link'
                              @size='s'
                              {{on 'click' (fn this.openCard wo)}}
                            >{{wo.identifier.value}}</Button>
                          </td>
                          <td class='wide'>
                            <span class='strong'>{{wo.title}}</span>
                            <span class='muted'>{{wo.assetName}}</span>
                          </td>
                          <td class='muted'>{{if
                              wo.ownership.teamName
                              wo.ownership.teamName
                              '—'
                            }}</td>
                          <td><span class='status'><span
                                class='dot'
                                style={{woDot wo.status}}
                              ></span>{{woLabel wo.status}}</span></td>
                          <td class='num mono'>{{this.woCost wo}}</td>
                          <td
                            class='num mono {{if (this.isLate wo) "neg"}}'
                          >{{this.woDue wo}}</td>
                        </tr>
                      {{else}}
                        <tr>
                          <td colspan='6'>
                            <EmptyState
                              @size='s'
                              @texture={{false}}
                              @title={{if
                                this.loading
                                'Loading work orders…'
                                'No open work orders match'
                              }}
                            />
                          </td>
                        </tr>
                      {{/each}}
                    </:body>
                  </Table>
                </div>
              </section>

            {{else if (eq this.tab 'assets')}}
              <section class='block'>
                <div class='block-head'>
                  <h2>Asset register</h2>
                  <p class='block-meta mono'>{{this.assets.length}}</p>
                  <p class='block-meta'>Open an asset to see its category,
                    location, custody and warranty.</p>
                </div>
                <div class='block-tools'>
                  <LayoutControl
                    @label='Asset tools'
                    @controlHeight='1.625rem'
                    as |lc|
                  >
                    <lc.Slot
                      @id='search'
                      @priority={{2}}
                      @forms={{SEARCH_FORMS}}
                      @label='Search'
                    >
                      <div class='am-search'><SearchInput
                          @value={{this.assetSearch}}
                          @placeholder='Search assets'
                          @onInput={{this.setAssetSearch}}
                        /></div>
                    </lc.Slot>
                    <lc.Slot
                      @id='add'
                      @priority={{0}}
                      @pinned={{true}}
                      @forms={{ADD_FORMS}}
                      @label='Add asset'
                      as |form|
                    >
                      <Button
                        class='push'
                        @icon={{PlusIcon}}
                        @tone='primary'
                        @size='s'
                        @display={{if (eq form 'icon') 'icon' 'label'}}
                        @label='Add asset'
                        {{on 'click' this.addAsset}}
                      >Add asset</Button>
                    </lc.Slot>
                  </LayoutControl>
                </div>
                <div class='tbl-wrap'>
                  <Table class='tbl' @framed={{false}} @striped={{false}}>
                    <:head>
                      <tr>
                        <th>ID</th>
                        <th class='wide'>Asset</th>
                        <th>Category</th>
                        <th>Location</th>
                        <th>Status</th>
                        <th>Next due</th>
                      </tr>
                    </:head>
                    <:body>
                      {{#each this.assetRows key='id' as |a|}}
                        <tr>
                          <td class='strong'>{{if a.tag a.tag '—'}}</td>
                          <td class='wide'>
                            <Button
                              class='link'
                              @tone='neutral'
                              @appearance='link'
                              @size='s'
                              {{on 'click' (fn this.openCard a)}}
                            >{{if a.name a.name a.cardTitle}}</Button>
                          </td>
                          <td class='muted'>{{if
                              a.categoryName
                              a.categoryName
                              '—'
                            }}</td>
                          <td class='muted'>{{if
                              a.locationName
                              a.locationName
                              '—'
                            }}</td>
                          <td><span class='status'><span
                                class='dot'
                                style={{assetDot a.status}}
                              ></span>{{assetLabel a.status}}</span></td>
                          <td>{{if a.nextDueLabel a.nextDueLabel '—'}}</td>
                        </tr>
                      {{else}}
                        <tr>
                          <td colspan='6'>
                            <EmptyState
                              @size='s'
                              @texture={{false}}
                              @title={{if
                                this.loading
                                'Loading assets…'
                                'No assets match'
                              }}
                            />
                          </td>
                        </tr>
                      {{/each}}
                    </:body>
                  </Table>
                </div>
              </section>

            {{else if (eq this.tab 'work')}}
              <section class='block'>
                <div class='block-head'>
                  <h2>Work</h2>
                  <p class='block-meta'>{{this.monthLine}}</p>
                </div>
                <div class='block-tools'>
                  <LayoutControl
                    @label='Work tools'
                    @controlHeight='1.625rem'
                    as |lc|
                  >
                    <lc.Slot
                      @id='kind'
                      @priority={{2}}
                      @forms={{VIEW_FORMS}}
                      @label='Kind'
                    >
                      <SegmentedControl
                        @label='Kind'
                        @options={{KIND_OPTIONS}}
                        @value={{this.workKind}}
                        @onValueChange={{this.setWorkKind}}
                      />
                    </lc.Slot>
                    <lc.Slot
                      @id='view'
                      @priority={{1}}
                      @pinned={{true}}
                      @forms={{VIEW_FORMS}}
                      @label='View'
                    >
                      <SegmentedControl
                        class='push'
                        @label='View'
                        @options={{WORK_VIEWS}}
                        @value={{this.workView}}
                        @onValueChange={{this.setWorkView}}
                      />
                    </lc.Slot>
                  </LayoutControl>
                </div>
                <div class='block-body'>
                  {{#if (eq this.workView 'board')}}
                    <WorkOrderBoard
                      @workOrders={{this.workOrders}}
                      @onOpen={{this.openCard}}
                      @onChange={{this.saveWorkOrder}}
                    />
                  {{else}}
                    <MaintenanceCalendar
                      @workOrders={{this.workOrders}}
                      @plans={{this.plans}}
                      @kind={{this.workKind}}
                      @onOpenWorkOrder={{this.openCard}}
                      @onSelectDay={{this.selectDay}}
                      @addingDate={{this.addingWorkOrderOn}}
                      @onChange={{this.saveWorkOrder}}
                    />
                  {{/if}}
                </div>
                {{#unless (eq this.workView 'board')}}
                  <p class='block-foot legend muted'>
                    <span class='status'><span
                        class='dot'
                        style={{dot 'var(--muted-foreground)'}}
                      ></span>Work order</span>
                    <span class='status'><span
                        class='dot dot-open'
                      ></span>Planned, not yet raised</span>
                    <span class='status'><span
                        class='dot'
                        style={{dot 'var(--destructive)'}}
                      ></span>Late</span>
                    <span class='status'><span
                        class='dot'
                        style={{dot 'var(--warning)'}}
                      ></span>On hold</span>
                  </p>
                {{/unless}}
              </section>

            {{else if (eq this.tab 'plans')}}
              <section class='block'>
                <div class='block-head'>
                  <h2>Plans & Parts</h2>
                  <p class='block-meta'>{{if
                      (eq this.collection 'plans')
                      'Plans view'
                      'Parts view'
                    }}</p>
                </div>
                <div class='block-tools'>
                  <LayoutControl
                    @label='Plans and parts tools'
                    @controlHeight='1.625rem'
                    as |lc|
                  >
                    <lc.Slot
                      @id='search'
                      @priority={{2}}
                      @forms={{SEARCH_FORMS}}
                      @label='Search'
                    >
                      <div class='am-search'><SearchInput
                          @value={{this.planSearch}}
                          @placeholder={{if
                            (eq this.collection 'plans')
                            'Search plans'
                            'Search parts'
                          }}
                          @onInput={{this.setPlanSearch}}
                        /></div>
                    </lc.Slot>
                    <lc.Slot
                      @id='filter'
                      @priority={{3}}
                      @forms={{CHIP_FORMS}}
                      @label='Show'
                    >
                      {{#if (eq this.collection 'plans')}}
                        <FilterChips
                          @options={{this.planChips}}
                          @value={{this.planFilter}}
                          @onValueChange={{this.setPlanFilter}}
                          @label='Show'
                        />
                      {{else}}
                        <FilterChips
                          @options={{this.partChips}}
                          @value={{this.partFilter}}
                          @onValueChange={{this.setPartFilter}}
                          @label='Show'
                        />
                      {{/if}}
                    </lc.Slot>
                    <lc.Slot
                      @id='collection'
                      @priority={{1}}
                      @forms={{VIEW_FORMS}}
                      @label='Collection'
                    >
                      <SegmentedControl
                        class='push'
                        @label='Collection'
                        @options={{this.collectionOptions}}
                        @value={{this.collection}}
                        @onValueChange={{this.setCollection}}
                      />
                    </lc.Slot>
                    <lc.Slot
                      @id='add'
                      @priority={{0}}
                      @pinned={{true}}
                      @forms={{ADD_FORMS}}
                      @label={{if
                        (eq this.collection 'plans')
                        'Add plan'
                        'Add part'
                      }}
                      as |form|
                    >
                      {{#if (eq this.collection 'plans')}}
                        <Button
                          @icon={{PlusIcon}}
                          @tone='primary'
                          @size='s'
                          @display={{if (eq form 'icon') 'icon' 'label'}}
                          @label='Add plan'
                          {{on 'click' this.addPlan}}
                        >Add plan</Button>
                      {{else}}
                        <Button
                          @icon={{PlusIcon}}
                          @tone='primary'
                          @size='s'
                          @display={{if (eq form 'icon') 'icon' 'label'}}
                          @label='Add part'
                          {{on 'click' this.addPart}}
                        >Add part</Button>
                      {{/if}}
                    </lc.Slot>
                  </LayoutControl>
                </div>
                <div class='tbl-wrap'>
                  {{#if (eq this.collection 'plans')}}
                    <Table class='tbl' @framed={{false}} @striped={{false}}>
                      <:head>
                        <tr>
                          <th>Plan</th>
                          <th>Asset</th>
                          <th class='wide'>Next due</th>
                          <th>Status</th>
                        </tr>
                      </:head>
                      <:body>
                        {{#each this.planRows key='id' as |p|}}
                          <tr>
                            <td><Button
                                class='link'
                                @tone='neutral'
                                @appearance='link'
                                @size='s'
                                {{on 'click' (fn this.openCard p)}}
                              >{{p.name}}</Button></td>
                            <td class='mono muted'>{{if
                                p.assetTag
                                p.assetTag
                                '—'
                              }}</td>
                            <td class='wide'>
                              <span class={{this.planUrgency p}}>{{if
                                  p.dueLabel
                                  p.dueLabel
                                  'No rhythm set'
                                }}</span>
                            </td>
                            <td><span class='status'><span
                                  class='dot'
                                  style={{this.activeDot p.active}}
                                ></span>{{if
                                  p.active
                                  'Active'
                                  'Inactive'
                                }}</span></td>
                          </tr>
                        {{else}}
                          <tr><td colspan='4'><EmptyState
                                @size='s'
                                @texture={{false}}
                                @title='No maintenance plans match'
                              /></td></tr>
                        {{/each}}
                      </:body>
                    </Table>
                  {{else}}
                    <Table class='tbl' @framed={{false}} @striped={{false}}>
                      <:head>
                        <tr>
                          <th>Part #</th>
                          <th class='wide'>Name</th>
                          <th class='num'>On hand</th>
                          <th>Stock</th>
                        </tr>
                      </:head>
                      <:body>
                        {{#each this.partRows key='id' as |p|}}
                          <tr>
                            <td class='strong'>{{p.partNumber}}</td>
                            <td class='wide'><Button
                                class='link'
                                @tone='neutral'
                                @appearance='link'
                                @size='s'
                                {{on 'click' (fn this.openCard p)}}
                              >{{p.name}}</Button></td>
                            <td class='num mono'>{{p.onHand}}</td>
                            <td><span class='status'><span
                                  class='dot'
                                  style={{this.stockDot p.belowReorderPoint}}
                                ></span>{{if
                                  p.belowReorderPoint
                                  'Reorder'
                                  'OK'
                                }}</span></td>
                          </tr>
                        {{else}}
                          <tr><td colspan='4'><EmptyState
                                @size='s'
                                @texture={{false}}
                                @title='No spare parts match'
                              /></td></tr>
                        {{/each}}
                      </:body>
                    </Table>
                  {{/if}}
                </div>
              </section>

            {{else if (eq this.tab 'setup')}}
              <section class='block'>
                <div class='block-head'>
                  <h2>Desk setup</h2>
                  <p class='block-meta'>{{this.setupLine}}</p>
                </div>
                <div class='block-body'>
                  <Wizard
                    @steps={{SETUP_STEPS}}
                    @activeIndex={{this.setupIndex}}
                    @onStepChange={{this.setSetupStep}}
                    @onComplete={{this.completeSetup}}
                    @label='Desk setup'
                    @completeLabel='Finish setup'
                  >
                    <:step as |_step index|>
                      <div class='am-form'>
                        {{#if (eq index 0)}}
                          <Field @label='Desk name' as |id|>
                            <Input
                              @controlId={{id}}
                              @value={{@model.name}}
                              @onInput={{this.updateName}}
                            />
                          </Field>
                          <Field @label='Time zone' as |id|>
                            <Input
                              @controlId={{id}}
                              @value={{@model.timeZone}}
                              @onInput={{this.updateTimeZone}}
                            />
                          </Field>
                        {{else if (eq index 1)}}
                          <Field @label='Asset id pattern' as |id|>
                            <Input
                              @controlId={{id}}
                              @value={{@model.config.idPattern}}
                              @onInput={{this.updateIdPattern}}
                              @invalid={{unless this.idPatternValid true}}
                              @errorMessage={{unless
                                this.idPatternValid
                                'Use a pattern such as AST-{yyyy}-{seq4}.'
                              }}
                            />
                          </Field>
                          <Field @label='Work order id pattern' as |id|>
                            <Input
                              @controlId={{id}}
                              @value={{@model.workOrderPattern}}
                              @onInput={{this.updateWorkOrderPattern}}
                              @invalid={{unless
                                this.workOrderPatternValid
                                true
                              }}
                              @errorMessage={{unless
                                this.workOrderPatternValid
                                'Use a pattern such as WO-{seq4}.'
                              }}
                            />
                          </Field>
                        {{else}}
                          <Field @label='Currency' as |id|>
                            <Input
                              @controlId={{id}}
                              @value={{@model.currency}}
                              @onInput={{this.updateCurrency}}
                            />
                          </Field>
                          <Field
                            @label='Cost approval threshold'
                            @hint='Work orders above this estimated cost wait for approval.'
                            as |id|
                          >
                            <Input
                              @controlId={{id}}
                              @value={{this.thresholdText}}
                              @onInput={{this.updateThreshold}}
                              inputmode='decimal'
                            />
                          </Field>
                        {{/if}}
                      </div>
                    </:step>
                  </Wizard>
                </div>
              </section>
            {{/if}}
          </main>

          {{#if (eq this.tab 'home')}}
            <aside class='am-aside' aria-label='What needs attention'>
              <section class='aside-sec'>
                <div class='aside-head'>
                  <h2>Load</h2>
                  <p class='block-meta'>{{this.lateWorkOrders.length}}
                    late, next
                    {{HORIZON_DAYS}}
                    days</p>
                </div>
                <div
                  class='load'
                  role='img'
                  aria-label='Open work and planned work by day'
                >
                  {{#each this.loadColumns key='key' as |col|}}
                    <div class='load-col'>
                      <span class='load-stack'>
                        {{#each col.late}}<span
                            class='blk blk-late'
                          ></span>{{/each}}
                        {{#each col.due}}<span
                            class='blk blk-due'
                          ></span>{{/each}}
                        {{#each col.planned}}<span
                            class='blk blk-plan'
                          ></span>{{/each}}
                      </span>
                      <span class='load-tick mono'>{{col.tick}}</span>
                    </div>
                  {{/each}}
                </div>
                <p class='legend muted'>
                  <span class='status'><span
                      class='dot'
                      style={{dot 'var(--destructive)'}}
                    ></span>Late</span>
                  <span class='status'><span
                      class='dot'
                      style={{dot 'var(--foreground)'}}
                    ></span>Due</span>
                  <span class='status'><span
                      class='dot dot-open'
                    ></span>Planned</span>
                </p>
              </section>
              <section class='aside-sec'>
                <div class='aside-head'>
                  <h2>Needs attention</h2>
                  <p class='block-meta mono'>{{this.attention.length}}</p>
                </div>
                <ul class='rows'>
                  {{#each this.attention key='id' as |a|}}
                    <li>
                      <button
                        type='button'
                        class='att'
                        {{on 'click' (fn this.openCard a.card)}}
                      >
                        <span class='att-text'>
                          <span class='strong'>{{a.label}}</span>
                          <span class='muted'>{{a.detail}}</span>
                        </span>
                        <span class='status'><span
                            class='dot'
                            style={{dot a.tone}}
                          ></span>{{a.tag}}</span>
                      </button>
                    </li>
                  {{else}}
                    <li class='att muted'>Nothing needs you right now.</li>
                  {{/each}}
                </ul>
              </section>
              <section class='aside-sec'>
                <div class='aside-head'>
                  <h2>Open work by status</h2>
                  <p class='block-meta'>{{this.openWorkOrders.length}} open</p>
                </div>
                <ul class='rows'>
                  {{#each this.statusRows key='status' as |s|}}
                    <li class='bar-row'>
                      <span>{{s.label}}</span>
                      <span class='bar' aria-hidden='true'><span
                          class='bar-fill'
                          style={{s.fill}}
                        ></span></span>
                      <span class='mono num'>{{s.count}}</span>
                    </li>
                  {{/each}}
                </ul>
              </section>
            </aside>
          {{/if}}
        </div>
      </:default>
    </Sidebar>

    <style scoped>
      .am-shell {
        container-type: inline-size;
        block-size: 100%;
        min-block-size: 0;
        background: var(--background);
        color: var(--foreground);
        font-family: var(--font-sans);
        font-size: var(--boxel-font-size-xs);
      }
      .eyebrow {
        font-family: var(--font-mono);
        font-size: var(--boxel-eyebrow-font-size);
        font-weight: var(--boxel-eyebrow-font-weight);
        line-height: var(--boxel-eyebrow-line-height);
        letter-spacing: var(--boxel-eyebrow-letter-spacing);
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .am-brand {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
      }
      .am-mark {
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
      .am-brand-text {
        display: grid;
        min-inline-size: 0;
        font-weight: 700;
        line-height: 1.2;
      }
      .am-foot {
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        color: var(--muted-foreground);
      }

      /* main column + a side column docked flush right on Home */
      .am-layout {
        display: grid;
        grid-template-columns: minmax(0, 1fr);
        min-block-size: 100%;
      }
      .am-layout.has-aside {
        grid-template-columns: minmax(0, 1fr) 18.75rem;
      }
      .am-main {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
        min-inline-size: 0;
        padding: var(--boxel-sp-lg) var(--boxel-sp-lg) var(--boxel-sp-xl);
      }
      .am-aside {
        min-inline-size: 0;
        border-inline-start: 1px solid var(--border);
        background: var(--card);
        color: var(--card-foreground);
      }
      @container (width < 60rem) {
        .am-layout.has-aside {
          grid-template-columns: minmax(0, 1fr);
        }
        .am-aside {
          border-inline-start: 0;
          border-block-start: 1px solid var(--border);
        }
      }

      .am-head {
        display: grid;
        gap: var(--boxel-sp-4xs);
      }
      .am-h1 {
        font-family: var(--boxel-heading-font-family);
        font-weight: 400;
        font-size: var(--boxel-font-size-2xl);
        line-height: 1;
        text-transform: uppercase;
      }
      .am-sub {
        color: var(--muted-foreground);
      }
      .am-search {
        inline-size: 13.75rem;
      }
      .push {
        margin-inline-start: auto;
      }

      /* stat strip: each cell draws its right and bottom line and the frame
         clips the overhang, so a wrapped row keeps all its dividers */
      .am-stats {
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
        overflow: hidden;
      }
      .am-stat-cells {
        --text-stat: var(--boxel-font-size-lg);
        display: grid;
        grid-template-columns: repeat(var(--cols, 5), minmax(0, 1fr));
        margin: 0 -1px -1px 0;
      }
      .am-stat {
        min-inline-size: 0;
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        box-shadow:
          1px 0 0 var(--border),
          0 1px 0 var(--border);
      }
      @container (width <= 48rem) {
        .am-stat-cells {
          --cols: 3;
        }
      }
      @container (width <= 30rem) {
        .am-stat-cells {
          --cols: 2;
        }
      }

      /* one flat block: radius outside only, hairline sections inside */
      .block {
        min-inline-size: 0;
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
        color: var(--card-foreground);
        overflow: hidden;
      }
      .block-head,
      .aside-head {
        display: flex;
        align-items: baseline;
        flex-wrap: wrap;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm) 0;
      }
      .block-head h2,
      .aside-head h2 {
        font-size: var(--boxel-font-size-xs);
        font-weight: 700;
      }
      .block-meta {
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
      }
      .block-tools {
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        border-block-end: 1px solid var(--border);
      }
      .block-body {
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        border-block-start: 1px solid var(--border);
      }
      .block-tools + .block-body {
        border-block-start: 0;
      }
      .block-foot {
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        border-block-start: 1px solid var(--border);
      }
      .am-setup-line {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp-4xs) var(--boxel-sp-sm);
      }

      /* ruled table: equal rows, one hairline between, mono caps head */
      .tbl-wrap {
        overflow-x: auto;
      }
      .tbl th {
        padding: var(--boxel-sp-5xs) var(--boxel-sp-sm);
        border-block-end: 1px solid var(--border);
        text-align: start;
        white-space: nowrap;
        font-family: var(--font-mono);
        font-size: var(--boxel-eyebrow-font-size);
        font-weight: var(--boxel-eyebrow-font-weight);
        line-height: var(--boxel-eyebrow-line-height);
        letter-spacing: var(--boxel-eyebrow-letter-spacing);
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .tbl td {
        block-size: 1.75rem;
        /* Pret UI cells default to the top; a fixed row height needs the middle */
        vertical-align: middle;
        padding: 0 var(--boxel-sp-sm);
        border-block-start: 1px solid var(--border);
        white-space: nowrap;
      }
      .tbl tbody tr:first-child td {
        border-block-start: 0;
      }
      .tbl .num {
        text-align: end;
      }
      .tbl .wide {
        inline-size: 100%;
      }

      .mono {
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-2xs);
        font-variant-numeric: tabular-nums;
      }
      .strong {
        font-weight: 600;
      }
      .muted {
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
      }
      .neg {
        color: var(--destructive-ink);
        font-weight: 600;
      }
      .warn {
        color: var(--warning-ink);
        font-weight: 600;
      }
      .status {
        display: inline-flex;
        align-items: center;
        gap: var(--boxel-sp-5xs);
        font-weight: 600;
        white-space: nowrap;
      }
      .dot {
        flex: none;
        inline-size: 0.375rem;
        block-size: 0.375rem;
        border-radius: 50%;
        background: var(--dot);
      }
      .dot-open {
        background: none;
        border: 1px solid var(--muted-foreground);
      }
      .legend {
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp-sm);
      }
      .legend .status {
        font-weight: 400;
      }
      .link {
        --pretui-button-h: auto;
        color: inherit;
        text-align: start;
      }
      .att:focus-visible {
        outline: 2px solid var(--ring);
        outline-offset: 1px;
      }

      /* docked side column on Home */
      .aside-sec {
        display: grid;
        gap: var(--boxel-sp-xs);
        padding-block-end: var(--boxel-sp-xs);
        border-block-end: 1px solid var(--border);
      }
      .aside-sec > .legend,
      .load {
        padding-inline: var(--boxel-sp-sm);
      }
      .load {
        display: flex;
        align-items: flex-end;
        gap: var(--boxel-sp-6xs);
        block-size: 4.5rem;
      }
      .load-col {
        flex: 1;
        display: grid;
        grid-template-rows: 1fr auto;
        block-size: 100%;
        min-inline-size: 0;
      }
      .load-stack {
        display: flex;
        flex-direction: column-reverse;
        justify-content: flex-start;
        gap: var(--boxel-sp-6xs);
        align-self: end;
      }
      .load-tick {
        font-size: var(--boxel-font-size-2xs);
        white-space: nowrap;
        overflow: visible;
        color: var(--muted-foreground);
      }
      .blk {
        display: block;
        block-size: 0.375rem;
      }
      .blk-late {
        background: var(--destructive);
      }
      .blk-due {
        background: var(--foreground);
      }
      .blk-plan {
        background: var(--muted-foreground);
        opacity: 0.5;
      }
      .rows {
        display: grid;
        margin: 0;
        padding: 0;
        list-style: none;
      }
      .rows > li + li {
        border-block-start: 1px solid var(--border);
      }
      .rows > li:first-child {
        border-block-start: 1px solid var(--border);
      }
      .att {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        inline-size: 100%;
        padding: var(--boxel-sp-4xs) var(--boxel-sp-sm);
        border: 0;
        background: none;
        color: inherit;
        font-family: inherit;
        font-size: inherit;
        font-weight: inherit;
        line-height: inherit;
        text-align: start;
      }
      @media (hover: hover) {
        .att:hover {
          background: var(--muted);
        }
      }
      .att-text {
        display: grid;
        flex: 1;
        min-inline-size: 0;
      }
      .bar-row {
        display: grid;
        grid-template-columns: 6rem 1fr 1.5rem;
        align-items: center;
        gap: var(--boxel-sp-xs);
        block-size: 1.75rem;
        padding-inline: var(--boxel-sp-sm);
      }
      .bar {
        display: block;
        block-size: 0.25rem;
        border-radius: var(--radius);
        background: var(--muted);
      }
      .bar-fill {
        display: block;
        block-size: 100%;
        border-radius: inherit;
        background: var(--foreground);
      }
      .bar-row .num {
        text-align: end;
      }
      .am-form {
        display: grid;
        gap: var(--boxel-sp-sm);
        max-inline-size: 28rem;
      }
    </style>
  </template>
}
