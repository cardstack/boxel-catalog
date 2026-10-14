import {
  CardDef,
  Component,
  field,
  contains,
  containsMany,
  linksTo,
  StringField,
  realmURL,
  type Format,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import { tracked } from '@glimmer/tracking';
import { action } from '@ember/object';
import { on } from '@ember/modifier';
import { fn, get } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import { themeScope } from '@cardstack/boxel-ui/helpers';
import { CardContainer, FittedCard } from '@cardstack/boxel-ui/components';
import { Alert } from '@cardstack/pretui/components/alert';
import { Button } from '@cardstack/pretui/components/button';
import { Field } from '@cardstack/pretui/components/field';
import { Input } from '@cardstack/pretui/components/input';
import { SegmentedControl } from '@cardstack/pretui/components/segmented-control';
import { Tabs } from '@cardstack/pretui/components/tabs';
import { VisuallyHidden } from '@cardstack/pretui/components/visually-hidden';
import {
  Wizard,
  type WizardStep,
} from '@cardstack/pretui/components/wizard';
import PlusIcon from '@cardstack/boxel-icons/plus';
import WrenchIcon from '@cardstack/boxel-icons/wrench';
import {
  identifyCard,
  type getCards,
  type LooseSingleCardDocument,
  type ResolvedCodeRef,
} from '@cardstack/runtime-common';
import { restartableTask } from 'ember-concurrency';
import type Owner from '@ember/owner';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';

import { Table, type TableColumn } from '../../components/table';
import { StatePill } from '../../components/state-pill';
import {
  CollectionToolbar,
  type ToolbarBadge,
} from '../../components/collection-toolbar';
import { AppConfigurationField } from '../../fields/app-configuration/app-configuration-field';
import { isValidIdentifierPattern } from '../../fields/record-identifier/record-identifier-field';
import { Location } from '../events/location';
import { Schedule } from '../service-desk/schedule';
import { Asset } from '../maintenance/asset';
import { AssetCategory } from '../maintenance/asset-category';
import { MaintenancePlan } from '../maintenance/maintenance-plan';
import { WorkOrder } from '../maintenance/work-order';
import { SparePart } from '../maintenance/spare-part';
import { Meter } from '../maintenance/meter';
import { AssetRegister } from '../maintenance/components/asset-register';
import { MaintenanceCalendar } from '../maintenance/components/maintenance-calendar';
import { WorkOrderBoard } from '../maintenance/components/work-order-board';
import { MaintenanceHome } from '../maintenance/components/maintenance-home';
import {
  dayKey,
  daysBetweenDays,
  toDay,
} from '../maintenance/utils/recurrence';
import { matchesSearch } from '../maintenance/utils/display';

// Fallback "due soon" window for a plan whose trigger sets no lead days,
// matching the domain's default raise-ahead lead time.
const DUE_SOON_FALLBACK_DAYS = 14;

// Plans with no next due day (a template with no rhythm) sort last.
function dueTimestamp(plan: MaintenancePlan): number {
  return toDay(plan.nextDueAt as any)?.getTime() ?? Infinity;
}

const TABS = [
  { value: 'home', label: 'Home' },
  { value: 'assets', label: 'Assets' },
  { value: 'work', label: 'Work' },
  { value: 'plans', label: 'Plans & Parts' },
  { value: 'setup', label: 'Setup' },
];

const WORK_VIEWS = [
  { value: 'calendar', label: 'Calendar' },
  { value: 'board', label: 'Board' },
];

const LIST_VIEWS = [
  { value: 'grid', label: 'Grid' },
  { value: 'list', label: 'List' },
  { value: 'table', label: 'Table' },
];

const SETUP_STEPS: WizardStep[] = [
  { id: 'desk', label: 'Desk', detail: 'Name and time zone' },
  { id: 'identifiers', label: 'Identifiers', detail: 'Asset and work order ids' },
  { id: 'money', label: 'Money', detail: 'Currency and approval threshold' },
];

// The desk's isolated view, hoisted out of the card class so its fields can
// be @tracked. Every collection is a live query against the card's own realm,
// so a Work Order raised on one tab appears on every other tab without a
// reload.
class AssetMaintenanceIsolated extends Component<typeof AssetMaintenanceApp> {
  @tracked activeTab = 'home';
  @tracked workView = 'calendar';
  @tracked workbenchError: string | undefined;
  // The day currently minting a Work Order. The calendar swaps that day's +
  // for a spinner, so a slow create doesn't invite repeat clicks.
  @tracked addingWorkOrderOn: Date | undefined;
  @tracked planSearch = '';
  @tracked partSearch = '';
  @tracked planBadge = 'all';
  @tracked partBadge = 'all';
  @tracked planView = 'table';
  @tracked partView = 'table';
  @tracked collection: 'plans' | 'parts' = 'plans';

  private assetQuery: ReturnType<getCards> | undefined;
  private categoryQuery: ReturnType<getCards> | undefined;
  private locationQuery: ReturnType<getCards> | undefined;
  private planQuery: ReturnType<getCards> | undefined;
  private workOrderQuery: ReturnType<getCards> | undefined;
  private partQuery: ReturnType<getCards> | undefined;
  private meterQuery: ReturnType<getCards> | undefined;

  constructor(owner: Owner, args: any) {
    super(owner, args);
    this.assetQuery = this.liveQuery(Asset);
    this.categoryQuery = this.liveQuery(AssetCategory);
    this.locationQuery = this.liveQuery(Location);
    this.planQuery = this.liveQuery(MaintenancePlan);
    this.workOrderQuery = this.liveQuery(WorkOrder);
    this.partQuery = this.liveQuery(SparePart);
    // Home answers "what needs me now" across every collection, so it also
    // reads the meters for threshold crossings.
    this.meterQuery = this.liveQuery(Meter);
  }

  private liveQuery(type: typeof CardDef) {
    return this.args.context?.getCards(
      this,
      () => {
        let ref = identifyCard(type);
        return ref ? { filter: { type: ref } } : undefined;
      },
      () => this.realms,
      { isLive: true },
    );
  }

  private get realms(): string[] | undefined {
    let url = this.args.model?.[realmURL];
    return url ? [url.href] : undefined;
  }

  private instancesOf<T>(query: ReturnType<getCards> | undefined): T[] {
    return ((query?.instances ?? []) as T[]).filter(Boolean);
  }

  get assets(): Asset[] {
    return this.instancesOf<Asset>(this.assetQuery);
  }
  get categories(): AssetCategory[] {
    return this.instancesOf<AssetCategory>(this.categoryQuery);
  }
  get locations(): Location[] {
    let all = this.instancesOf<Location>(this.locationQuery);
    // Location is shared, so other estates' sites live in the same realm.
    // Keep only the estate root's subtree by walking each `parent` chain.
    let root = this.args.model.estateRoot;
    if (!root) return all;
    return all.filter((loc) => {
      let node: Location | undefined = loc;
      let hops = 0;
      while (node && hops++ < 20) {
        if (node.id === root.id) return true;
        node = node.parent ?? undefined;
      }
      return false;
    });
  }
  get plans(): MaintenancePlan[] {
    return this.instancesOf<MaintenancePlan>(this.planQuery);
  }
  get workOrders(): WorkOrder[] {
    return this.instancesOf<WorkOrder>(this.workOrderQuery);
  }
  get parts(): SparePart[] {
    return this.instancesOf<SparePart>(this.partQuery);
  }
  get meters(): Meter[] {
    return this.instancesOf<Meter>(this.meterQuery);
  }

  get plansLoading(): boolean {
    return Boolean(this.planQuery?.isLoading);
  }
  get partsLoading(): boolean {
    return Boolean(this.partQuery?.isLoading);
  }
  get planEmptyMessage(): string {
    return this.plansLoading
      ? 'Loading maintenance plans…'
      : 'No maintenance plans yet. Add one from an Asset Category.';
  }
  get partEmptyMessage(): string {
    return this.partsLoading
      ? 'Loading spare parts…'
      : 'No spare parts yet. Add one to track stock and reorder points.';
  }

  @action setActiveTab(value: string) {
    this.activeTab = value;
  }
  @action setWorkView(value: string) {
    this.workView = value;
  }
  @action setPlanSearch(v: string) {
    this.planSearch = v;
  }
  @action setPartSearch(v: string) {
    this.partSearch = v;
  }
  @action setPlanBadge(id: string) {
    this.planBadge = id;
  }
  @action setPartBadge(id: string) {
    this.partBadge = id;
  }
  @action setPlanView(value: string) {
    this.planView = value;
  }
  @action setPartView(value: string) {
    this.partView = value;
  }
  @action setCollection(value: string) {
    this.collection = value === 'parts' ? 'parts' : 'plans';
  }

  get planBadges(): ToolbarBadge[] {
    let active = this.plans.filter((p) => p.active).length;
    return [
      { id: 'all', label: 'All', count: this.plans.length },
      { id: 'active', label: 'Active', count: active },
      { id: 'inactive', label: 'Inactive', count: this.plans.length - active },
    ];
  }

  get partBadges(): ToolbarBadge[] {
    let below = this.parts.filter((p) => p.belowReorderPoint).length;
    return [
      { id: 'all', label: 'All', count: this.parts.length },
      { id: 'reorder', label: 'Below reorder', count: below },
    ];
  }

  // The counts ride in the segment labels, so switching collection keeps the
  // glance; the Parts label names the low-stock count, which is what a
  // supervisor needs to see while looking at Plans.
  get collectionSegments() {
    let below = this.parts.filter((p) => p.belowReorderPoint).length;
    return [
      { value: 'plans', label: `Plans · ${this.plans.length}` },
      {
        value: 'parts',
        label: below
          ? `Parts · ${this.parts.length} (${below} low)`
          : `Parts · ${this.parts.length}`,
      },
    ];
  }

  get filteredPlans(): MaintenancePlan[] {
    return this.plans
      .filter((p) => {
        if (this.planBadge === 'active' && !p.active) return false;
        if (this.planBadge === 'inactive' && p.active) return false;
        return matchesSearch(this.planSearch, p.name, (p as any).assetTag);
      })
      .slice()
      .sort((a, b) => dueTimestamp(a) - dueTimestamp(b));
  }

  get filteredParts(): SparePart[] {
    return this.parts.filter((p) => {
      if (this.partBadge === 'reorder' && !p.belowReorderPoint) return false;
      return matchesSearch(this.partSearch, p.partNumber, p.name);
    });
  }

  // Overdue reads as destructive; "due soon" uses the plan's own raise-ahead
  // lead days, so each plan lights up when a work order would be raised for
  // it. Days are compared as local calendar days.
  urgencyClass = (plan: MaintenancePlan): string => {
    if (plan.isOverdue) return 'overdue';
    let due = toDay(plan.nextDueAt as any);
    let today = toDay(new Date());
    if (!due || !today) return '';
    let leadDays = plan.trigger?.leadDays ?? DUE_SOON_FALLBACK_DAYS;
    return daysBetweenDays(today, due) <= leadDays ? 'due-soon' : '';
  };

  planColumns: TableColumn[] = [
    { key: 'name', label: 'Plan' },
    { key: 'assetTag', label: 'Asset' },
    { key: 'dueLabel', label: 'Next due' },
    { key: 'active', label: 'Status' },
  ];

  partColumns: TableColumn[] = [
    { key: 'partNumber', label: 'Part #' },
    { key: 'name', label: 'Name' },
    { key: 'onHand', label: 'On hand' },
    { key: 'belowReorderPoint', label: 'Stock' },
  ];

  get isSetUp(): boolean {
    return Boolean(this.args.model.config?.setupCompletedAt);
  }

  // A custom isolated template doesn't get the default template's Theme
  // wiring, so a linked `cardInfo.theme` is forwarded into CardContainer.
  get themeCss(): string | null | undefined {
    return (this.args.model as any).cardTheme?.cssVariables;
  }
  get themeCssImports(): string[] | undefined {
    return (this.args.model as any).cardTheme?.cssImports;
  }
  get themeScopeId(): string | undefined {
    let theme = (this.args.model as any).cardTheme;
    return themeScope(theme?.id, theme?.cssVariables) ?? undefined;
  }

  get setupSteps(): WizardStep[] {
    return SETUP_STEPS;
  }

  // A completed setup can persist `setupStep` one past the last step, so the
  // index is clamped.
  get setupIndex(): number {
    let step = this.args.model.config?.setupStep ?? 0;
    return Math.min(step, SETUP_STEPS.length - 1);
  }

  @action setSetupStep(index: number) {
    let config = this.args.model.config;
    if (config) {
      config.setupStep = index;
    }
  }

  @action completeSetup() {
    let config = this.args.model.config;
    if (config) {
      config.setupCompletedAt = new Date();
    }
  }

  @action openWorkOrder(wo: WorkOrder, format: Format = 'isolated') {
    this.args.viewCard?.(wo, format);
  }

  @action openCard(card: unknown) {
    this.args.viewCard?.(card as CardDef);
  }

  selectDay = (date: Date) => {
    void this.addWorkOrderTask.perform(date);
  };

  private addWorkOrderTask = restartableTask(async (date: Date) => {
    this.addingWorkOrderOn = date;
    try {
      await this.createRecord(WorkOrder, {
        title: 'New Work Order',
        kind: 'corrective',
        status: 'requested',
        scheduledFor: dayKey(date),
      });
    } finally {
      this.addingWorkOrderOn = undefined;
    }
  });

  // Every "Add" action opens the new card in edit format through
  // `createCard`; each collection's live query picks it up once it indexes.
  private async createRecord(
    type: typeof CardDef,
    attributes: Record<string, unknown>,
  ): Promise<void> {
    this.workbenchError = undefined;
    let createCard = this.args.createCard;
    let ref = identifyCard(type) as ResolvedCodeRef | undefined;
    if (!createCard || !ref) {
      this.workbenchError = 'Adding records is unavailable in this view.';
      return;
    }
    try {
      let realmHref = this.realms?.[0];
      let realm = realmHref ? new URL(realmHref) : undefined;
      let doc: LooseSingleCardDocument = {
        data: { type: 'card', attributes, meta: { adoptsFrom: ref } },
      };
      await createCard(ref, realm, { realmURL: realm, doc });
    } catch (error: any) {
      this.workbenchError = error?.message ?? String(error);
    }
  }

  @action addAsset() {
    void this.createRecord(Asset, { name: 'New Asset' });
  }
  @action addPlan() {
    void this.createRecord(MaintenancePlan, { name: 'New Maintenance Plan' });
  }
  @action addPart() {
    void this.createRecord(SparePart, { name: 'New Spare Part' });
  }

  // Drag-to-reschedule on the calendar and drag-to-status on the board hand
  // over a Work Order to save. Start, Hold and Complete live on the Work
  // Order card itself.
  @action async saveWorkOrder(wo: WorkOrder) {
    let commandContext = this.args.context?.commandContext;
    if (!wo || !commandContext) return;
    try {
      await new SaveCardCommand(commandContext).execute({ card: wo } as any);
    } catch (error: any) {
      this.workbenchError = error?.message ?? String(error);
    }
  }

  @action updateName(value: string) {
    this.args.model.name = value;
  }
  @action updateTimeZone(value: string) {
    this.args.model.timeZone = value;
  }
  @action updateCurrency(value: string) {
    this.args.model.currency = value;
  }
  @action updateThreshold(value: string) {
    let n = Number(value);
    if (value.trim() !== '' && Number.isFinite(n)) {
      this.args.model.costApprovalThreshold = n;
    }
  }
  @action updateIdPattern(value: string) {
    if (this.args.model.config) {
      this.args.model.config.idPattern = value;
    }
  }
  @action updateWorkOrderPattern(value: string) {
    this.args.model.workOrderPattern = value;
  }

  get idPatternValid(): boolean {
    return isValidIdentifierPattern(this.args.model.config?.idPattern);
  }
  get workOrderPatternValid(): boolean {
    return isValidIdentifierPattern(this.args.model.workOrderPattern);
  }
  get thresholdText(): string {
    let n = this.args.model.costApprovalThreshold;
    return n == null ? '' : String(n);
  }

  <template>
    <CardContainer
      @cssImports={{this.themeCssImports}}
      @themeCss={{this.themeCss}}
      @themeScope={{this.themeScopeId}}
      class='shell'
    >
      <article class='desk'>
        <header class='desk-head'>
          <p class='kicker'>Facilities · Maintenance desk</p>
          <h1>{{@model.cardTitle}}</h1>
          <Tabs
            class='desk-tabs'
            @options={{TABS}}
            @value={{this.activeTab}}
            @onValueChange={{this.setActiveTab}}
          />
        </header>
        {{#unless this.isSetUp}}
          <Alert @tone='info' class='setup-banner'>
            Setup is still in progress. Finish it on the Setup tab.
          </Alert>
        {{/unless}}
        <main class='desk-body'>
          {{#if (eq this.activeTab 'home')}}
            <MaintenanceHome
              @assets={{this.assets}}
              @workOrders={{this.workOrders}}
              @plans={{this.plans}}
              @parts={{this.parts}}
              @meters={{this.meters}}
              @teams={{@model.teamNames}}
              @locations={{this.locations}}
              @onOpen={{this.openCard}}
            />
          {{else if (eq this.activeTab 'assets')}}
            <AssetRegister
              @assets={{this.assets}}
              @locations={{this.locations}}
              @categories={{this.categories}}
              @onOpen={{this.openCard}}
              @onAdd={{this.addAsset}}
            />
          {{else if (eq this.activeTab 'work')}}
            <div class='stack'>
              <VisuallyHidden><h2>{{if
                    (eq this.workView 'board')
                    'Work Order Board'
                    'Maintenance Calendar'
                  }}</h2></VisuallyHidden>
              <SegmentedControl
                @options={{WORK_VIEWS}}
                @value={{this.workView}}
                @onValueChange={{this.setWorkView}}
                @label='Work view'
              />
              {{#if this.workbenchError}}
                <Alert @tone='danger'>{{this.workbenchError}}</Alert>
              {{/if}}
              {{#if (eq this.workView 'board')}}
                <WorkOrderBoard
                  @workOrders={{this.workOrders}}
                  @onOpen={{this.openWorkOrder}}
                  @onChange={{this.saveWorkOrder}}
                />
              {{else}}
                <MaintenanceCalendar
                  @workOrders={{this.workOrders}}
                  @plans={{this.plans}}
                  @onOpenWorkOrder={{this.openWorkOrder}}
                  @onSelectDay={{this.selectDay}}
                  @addingDate={{this.addingWorkOrderOn}}
                  @onChange={{this.saveWorkOrder}}
                />
              {{/if}}
            </div>
          {{else if (eq this.activeTab 'plans')}}
            <div class='stack'>
              <div class='collection-head'>
                <SegmentedControl
                  @options={{this.collectionSegments}}
                  @value={{this.collection}}
                  @onValueChange={{this.setCollection}}
                  @label='Collection'
                />
                {{#if (eq this.collection 'plans')}}
                  <Button
                    @tone='primary'
                    @appearance='accent'
                    {{on 'click' this.addPlan}}
                  >
                    <PlusIcon width='16' height='16' role='presentation' />
                    Add plan
                  </Button>
                {{else}}
                  <Button
                    @tone='primary'
                    @appearance='accent'
                    {{on 'click' this.addPart}}
                  >
                    <PlusIcon width='16' height='16' role='presentation' />
                    Add part
                  </Button>
                {{/if}}
              </div>
              {{#if this.workbenchError}}
                <Alert @tone='danger'>{{this.workbenchError}}</Alert>
              {{/if}}
              {{#if (eq this.collection 'plans')}}
                <section class='collection'>
                  <VisuallyHidden><h2>Maintenance Plans</h2></VisuallyHidden>
                  <CollectionToolbar
                    @search={{this.planSearch}}
                    @onSearch={{this.setPlanSearch}}
                    @placeholder='Search plans…'
                    @badges={{this.planBadges}}
                    @activeBadge={{this.planBadge}}
                    @onBadge={{this.setPlanBadge}}
                  >
                    <:right>
                      <SegmentedControl
                        @options={{LIST_VIEWS}}
                        @value={{this.planView}}
                        @onValueChange={{this.setPlanView}}
                        @label='Plan view'
                      />
                    </:right>
                  </CollectionToolbar>
                  {{#if (eq this.planView 'table')}}
                    <Table
                      @items={{this.filteredPlans}}
                      @columns={{this.planColumns}}
                      @onRowClick={{this.openCard}}
                      @caption='Maintenance Plans'
                      @emptyMessage={{this.planEmptyMessage}}
                      @pageSize={{25}}
                    >
                      <:cell as |plan col|>
                        {{#if (eq col.key 'active')}}
                          <StatePill
                            @label={{if plan.active 'active' 'inactive'}}
                            @hue={{if plan.active 'green' 'slate'}}
                            @dot={{true}}
                          />
                        {{else if (eq col.key 'dueLabel')}}
                          <span
                            class={{this.urgencyClass plan}}
                          >{{plan.dueLabel}}</span>
                        {{else}}
                          {{get plan col.key}}
                        {{/if}}
                      </:cell>
                    </Table>
                  {{else}}
                    <ul class='rows rows--{{this.planView}}'>
                      {{#each this.filteredPlans as |plan|}}
                        <li>
                          {{! Native: the row holds a name, asset, due day and status pill. }}
                          <button
                            type='button'
                            class='row'
                            {{on 'click' (fn this.openCard plan)}}
                          >
                            <span class='row-name'>{{plan.name}}</span>
                            <span class='row-meta'>{{plan.assetTag}}</span>
                            <span
                              class={{this.urgencyClass plan}}
                            >{{plan.dueLabel}}</span>
                            <StatePill
                              @label={{if plan.active 'active' 'inactive'}}
                              @hue={{if plan.active 'green' 'slate'}}
                              @dot={{true}}
                            />
                          </button>
                        </li>
                      {{else}}
                        <li class='row-empty'>{{this.planEmptyMessage}}</li>
                      {{/each}}
                    </ul>
                  {{/if}}
                </section>
              {{else}}
                <section class='collection'>
                  <VisuallyHidden><h2>Spare Parts</h2></VisuallyHidden>
                  <CollectionToolbar
                    @search={{this.partSearch}}
                    @onSearch={{this.setPartSearch}}
                    @placeholder='Search parts…'
                    @badges={{this.partBadges}}
                    @activeBadge={{this.partBadge}}
                    @onBadge={{this.setPartBadge}}
                  >
                    <:right>
                      <SegmentedControl
                        @options={{LIST_VIEWS}}
                        @value={{this.partView}}
                        @onValueChange={{this.setPartView}}
                        @label='Part view'
                      />
                    </:right>
                  </CollectionToolbar>
                  {{#if (eq this.partView 'table')}}
                    <Table
                      @items={{this.filteredParts}}
                      @columns={{this.partColumns}}
                      @onRowClick={{this.openCard}}
                      @caption='Spare Parts'
                      @emptyMessage={{this.partEmptyMessage}}
                      @pageSize={{25}}
                    >
                      <:cell as |part col|>
                        {{#if (eq col.key 'belowReorderPoint')}}
                          <StatePill
                            @label={{if part.belowReorderPoint 'reorder' 'ok'}}
                            @hue={{if part.belowReorderPoint 'orange' 'green'}}
                            @dot={{true}}
                          />
                        {{else}}
                          {{get part col.key}}
                        {{/if}}
                      </:cell>
                    </Table>
                  {{else}}
                    <ul class='rows rows--{{this.partView}}'>
                      {{#each this.filteredParts as |part|}}
                        <li>
                          {{! Native: the row holds a part number, name, stock and status pill. }}
                          <button
                            type='button'
                            class='row'
                            {{on 'click' (fn this.openCard part)}}
                          >
                            <code class='row-tag'>{{part.partNumber}}</code>
                            <span class='row-name'>{{part.name}}</span>
                            <span class='row-meta'>on hand {{part.onHand}}</span>
                            <StatePill
                              @label={{if part.belowReorderPoint 'reorder' 'ok'}}
                              @hue={{if part.belowReorderPoint 'orange' 'green'}}
                              @dot={{true}}
                            />
                          </button>
                        </li>
                      {{else}}
                        <li class='row-empty'>{{this.partEmptyMessage}}</li>
                      {{/each}}
                    </ul>
                  {{/if}}
                </section>
              {{/if}}
            </div>
          {{else if (eq this.activeTab 'setup')}}
            <Wizard
              @steps={{this.setupSteps}}
              @activeIndex={{this.setupIndex}}
              @onStepChange={{this.setSetupStep}}
              @onComplete={{this.completeSetup}}
              @label='Desk setup'
              @completeLabel='Finish setup'
            >
              <:step as |_step index|>
                <div class='form'>
                  {{#if (eq index 0)}}
                    <Field @label='Desk name' as |controlId|>
                      <Input
                        @controlId={{controlId}}
                        @value={{@model.name}}
                        @onInput={{this.updateName}}
                      />
                    </Field>
                    <Field @label='Time zone' as |controlId|>
                      <Input
                        @controlId={{controlId}}
                        @value={{@model.timeZone}}
                        @onInput={{this.updateTimeZone}}
                      />
                    </Field>
                  {{else if (eq index 1)}}
                    <Field
                      @label='Asset id pattern'
                      @error={{unless
                        this.idPatternValid
                        'Use a pattern such as AST-{yyyy}-{seq4}.'
                      }}
                      as |controlId|
                    >
                      <Input
                        @controlId={{controlId}}
                        @value={{@model.config.idPattern}}
                        @onInput={{this.updateIdPattern}}
                        @invalid={{unless this.idPatternValid true}}
                      />
                    </Field>
                    <Field
                      @label='Work order id pattern'
                      @error={{unless
                        this.workOrderPatternValid
                        'Use a pattern such as WO-{seq4}.'
                      }}
                      as |controlId|
                    >
                      <Input
                        @controlId={{controlId}}
                        @value={{@model.workOrderPattern}}
                        @onInput={{this.updateWorkOrderPattern}}
                        @invalid={{unless this.workOrderPatternValid true}}
                      />
                    </Field>
                  {{else}}
                    <Field @label='Currency' as |controlId|>
                      <Input
                        @controlId={{controlId}}
                        @value={{@model.currency}}
                        @onInput={{this.updateCurrency}}
                      />
                    </Field>
                    <Field @label='Cost approval threshold' as |controlId|>
                      <Input
                        @controlId={{controlId}}
                        @value={{this.thresholdText}}
                        @onInput={{this.updateThreshold}}
                        inputmode='decimal'
                      />
                    </Field>
                  {{/if}}
                </div>
              </:step>
            </Wizard>
          {{/if}}
        </main>
      </article>
    </CardContainer>
    <style scoped>
      .shell {
        display: contents;
      }
      .desk {
        container-type: inline-size;
        display: flex;
        flex-direction: column;
        height: 100%;
        min-height: 0;
        background: var(--background);
        color: var(--foreground);
        font-family: var(--font-sans);
      }
      .desk-head {
        padding: var(--boxel-sp) var(--boxel-sp-lg) 0;
        border-bottom: 1px solid var(--border);
        background: var(--card);
      }
      .kicker {
        font-size: var(--boxel-font-size-xs);
        letter-spacing: 0.12em;
        text-transform: uppercase;
        color: var(--primary-ink);
      }
      .desk-head h1 {
        margin-block: var(--boxel-sp-5xs) var(--boxel-sp-xs);
      }
      .desk-tabs {
        overflow-x: auto;
      }
      .setup-banner {
        margin: var(--boxel-sp-sm) var(--boxel-sp-lg) 0;
      }
      .desk-body {
        flex: 1;
        min-height: 0;
        overflow-y: auto;
        padding: var(--boxel-sp) var(--boxel-sp-lg);
      }
      .stack {
        display: grid;
        gap: var(--boxel-sp);
      }
      .collection-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: var(--boxel-sp-sm);
        flex-wrap: wrap;
      }
      .collection {
        display: grid;
        gap: var(--boxel-sp-xs);
      }
      .overdue {
        color: var(--destructive-ink);
        font-weight: 600;
      }
      .due-soon {
        color: var(--attention-ink);
        font-weight: 600;
      }
      .rows {
        list-style: none;
        margin: 0;
        padding: 0;
        display: grid;
        gap: var(--boxel-sp-4xs);
      }
      .rows--grid {
        grid-template-columns: repeat(auto-fill, minmax(15rem, 1fr));
        gap: var(--boxel-sp-sm);
      }
      .rows--grid .row {
        flex-direction: column;
        align-items: flex-start;
        min-height: 5rem;
      }
      .row {
        display: flex;
        align-items: center;
        flex-wrap: wrap;
        gap: var(--boxel-sp-xs);
        width: 100%;
        min-height: 2.75rem;
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
        color: inherit;
        font-family: inherit;
        font-size: inherit;
        font-weight: inherit;
        line-height: inherit;
        text-align: left;
        cursor: pointer;
      }
      .row:hover {
        background: var(--muted);
        border-color: var(--primary-ink);
      }
      .row:focus-visible {
        outline: 2px solid var(--ring);
        outline-offset: 2px;
      }
      .row-tag {
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
      .row-name {
        font-weight: 600;
        flex: 1;
        min-width: 8rem;
      }
      .row-meta {
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground);
        flex: 1;
        min-width: 6rem;
      }
      .row-empty {
        padding: var(--boxel-sp);
        border: 1px dashed var(--border);
        border-radius: var(--radius);
        color: var(--muted-foreground);
      }
      .form {
        display: grid;
        gap: var(--boxel-sp);
        max-width: 28rem;
      }
      @container (width < 36rem) {
        .desk-head,
        .desk-body {
          padding-inline: var(--boxel-sp);
        }
        .setup-banner {
          margin-inline: var(--boxel-sp);
        }
      }
    </style>
  </template>
}

/**
 * One estate's maintenance desk. It owns the desk-level settings: Assets mint
 * ids from the App Configuration field's `idPattern`, and Work Orders keep
 * their own `workOrderPattern` and counter, since the two never share a
 * sequence. Every tab reads live queries against the card's own realm.
 */
export class AssetMaintenanceApp extends CardDef {
  static displayName = 'Asset & Maintenance Desk';
  static icon = WrenchIcon;
  static prefersWideFormat = true;

  @field name = contains(StringField);
  @field config = contains(AppConfigurationField, {
    description: 'Asset Record Identifier pattern + setup progress.',
  });
  @field workOrderPattern = contains(StringField, {
    description: 'Work Order Record Identifier pattern, e.g. WO-{seq4}.',
  });
  @field workOrderSeq = contains(NumberField, {
    description: 'Mint counter for Work Order identifiers.',
  });
  @field timeZone = contains(StringField);
  @field schedule = linksTo(() => Schedule);
  @field estateRoot = linksTo(() => Location);
  @field teamNames = containsMany(StringField);
  @field costApprovalThreshold = contains(NumberField, {
    description: 'Work Orders above this total cost need approval before close.',
  });
  @field currency = contains(StringField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: AssetMaintenanceApp) {
      return this.name ?? 'Asset & Maintenance Desk';
    },
  });

  static isolated = AssetMaintenanceIsolated;

  static fitted = class Fitted extends Component<typeof AssetMaintenanceApp> {
    <template>
      <FittedCard @titleTag='h3'>
        <:eyebrow><span class='fit-eyebrow'>Facilities</span></:eyebrow>
        <:title>{{@model.cardTitle}}</:title>
        <:subtitle>assets · work orders · plans · parts</:subtitle>
      </FittedCard>
      <style scoped>
        .fit-eyebrow {
          color: var(--primary-ink);
        }
      </style>
    </template>
  };
}

export default AssetMaintenanceApp;
