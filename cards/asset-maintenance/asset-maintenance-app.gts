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
  type ViewCardFn,
  type CreateCardFn,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import { tracked } from '@glimmer/tracking';
import { action } from '@ember/object';
import { on } from '@ember/modifier';
import { fn, get } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import { themeScope } from '@cardstack/boxel-ui/helpers';
import {
  TabbedHeader,
  BoxelInput,
  CardContainer,
  ViewSelector,
  Button,
} from '@cardstack/boxel-ui/components';
import PlusIcon from '@cardstack/boxel-icons/plus';
import { Table, type TableColumn } from '../../components/table';
import { StatePill } from '../../components/state-pill';
import {
  CollectionToolbar,
  type ToolbarBadge,
} from '../../components/collection-toolbar';
import {
  identifyCard,
  codeRef,
  type getCards,
  type LooseSingleCardDocument,
} from '@cardstack/runtime-common';
import { restartableTask } from 'ember-concurrency';
import { dayKey } from '../maintenance/utils/recurrence';
import { matchesSearch } from '../maintenance/utils/display';
import type Owner from '@ember/owner';
import WrenchIcon from '@cardstack/boxel-icons/wrench';
import CalendarDaysIcon from '@cardstack/boxel-icons/calendar-days';
import KanbanIcon from '@cardstack/boxel-icons/layout-kanban';
import LayoutGridIcon from '@cardstack/boxel-icons/layout-grid';
import LayoutListIcon from '@cardstack/boxel-icons/layout-list';
import TableIcon from '@cardstack/boxel-icons/table';

import { AppConfigurationField } from '../../fields/app-configuration/app-configuration-field';
import { Location } from '../events/location';
import { Schedule } from '../service-desk/schedule';
import { Asset } from '../maintenance/asset';
import { AssetCategory } from '../maintenance/asset-category';
import { MaintenancePlan } from '../maintenance/maintenance-plan';
import { WorkOrder } from '../maintenance/work-order';
import { SparePart } from '../maintenance/spare-part';
import { Meter } from '../maintenance/meter';
import { isValidIdentifierPattern } from '../../fields/record-identifier/record-identifier-field';

import { AssetRegister } from '../maintenance/components/asset-register';
import { MaintenanceCalendar } from '../maintenance/components/maintenance-calendar';
import { SegmentedControl } from '@cardstack/pretui/components/segmented-control';
import { WorkOrderBoard } from '../maintenance/components/work-order-board';
import { MaintenanceHome } from '../maintenance/components/maintenance-home';
import { SetupWizard, type WizardStep } from './components/setup-wizard';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';

const here: string = import.meta.url;
const workOrderRef = codeRef(here, '../maintenance/work-order', 'WorkOrder');
const assetRef = codeRef(here, '../maintenance/asset', 'Asset');
const maintenancePlanRef = codeRef(here, '../maintenance/maintenance-plan', 'MaintenancePlan');
const sparePartRef = codeRef(here, '../maintenance/spare-part', 'SparePart');

const MS_PER_DAY = 24 * 60 * 60 * 1000;
// Fallback "due soon" window for a plan whose trigger has no leadDays set —
// matches the domain's own default raise-ahead lead time convention.
const DUE_SOON_FALLBACK_DAYS = 14;

// Plans with no computed nextDueAt (e.g. a template with no rhythm) sort
// last, after every plan that actually has a date.
function dueTimestamp(plan: MaintenancePlan): number {
  let due = plan.nextDueAt;
  return due ? new Date(due).getTime() : Infinity;
}

/**
 * The Asset & Maintenance Desk — Facilities & Assets Domain Kit's composing
 * app. Owns the desk-level settings (two id patterns: assets use the
 * generic `config.idPattern`, Work Orders keep their own `workOrderPattern`
 * — matrix rows never sharing a mint counter) and the five live collections
 * every tab reads from. Every collection is a live query against this
 * card's own realm (`getCards`) — never a maintained `linksToMany` — so a
 * Work Order raised from any tab shows up in every other tab without a
 * reload.
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

  static isolated = class Isolated extends Component<typeof this> {
    @tracked activeTabId: string = TABS[0].tabId;
    @tracked workView: string = 'calendar';
    @tracked workbenchError: string | undefined;
    // The day currently minting a Work Order — Calendar swaps that day's +
    // for a spinner and disables it, so a slow create doesn't invite repeat
    // clicks (the four-cards-on-one-day failure mode).
    @tracked addingWorkOrderOn: Date | undefined;
    @tracked planSearch = '';
    @tracked partSearch = '';
    @tracked planBadge = 'all';
    @tracked partBadge = 'all';
    @tracked planView = 'table';
    @tracked partView = 'table';
    /** Which collection the Plans & Parts tab is showing. */
    @tracked collection: 'plans' | 'parts' = 'plans';

    private get realms(): string[] | undefined {
      let url = (this.args.model as any)?.[realmURL];
      return url ? [url.href] : undefined;
    }

    assetQuery: ReturnType<getCards> | undefined;
    categoryQuery: ReturnType<getCards> | undefined;
    locationQuery: ReturnType<getCards> | undefined;
    planQuery: ReturnType<getCards> | undefined;
    workOrderQuery: ReturnType<getCards> | undefined;
    partQuery: ReturnType<getCards> | undefined;
    meterQuery: ReturnType<getCards> | undefined;

    constructor(owner: Owner, args: any) {
      super(owner, args);
      this.assetQuery = this.args.context?.getCards(
        this,
        () => {
          let ref = identifyCard(Asset);
          return ref ? { filter: { type: ref } } : undefined;
        },
        () => this.realms,
        { isLive: true },
      );
      this.categoryQuery = this.args.context?.getCards(
        this,
        () => {
          let ref = identifyCard(AssetCategory);
          return ref ? { filter: { type: ref } } : undefined;
        },
        () => this.realms,
        { isLive: true },
      );
      this.locationQuery = this.args.context?.getCards(
        this,
        () => {
          let ref = identifyCard(Location);
          return ref ? { filter: { type: ref } } : undefined;
        },
        () => this.realms,
        { isLive: true },
      );
      this.planQuery = this.args.context?.getCards(
        this,
        () => {
          let ref = identifyCard(MaintenancePlan);
          return ref ? { filter: { type: ref } } : undefined;
        },
        () => this.realms,
        { isLive: true },
      );
      this.workOrderQuery = this.args.context?.getCards(
        this,
        () => {
          let ref = identifyCard(WorkOrder);
          return ref ? { filter: { type: ref } } : undefined;
        },
        () => this.realms,
        { isLive: true },
      );
      this.partQuery = this.args.context?.getCards(
        this,
        () => {
          let ref = identifyCard(SparePart);
          return ref ? { filter: { type: ref } } : undefined;
        },
        () => this.realms,
        { isLive: true },
      );
      // Home is the only surface that answers "what needs me now" across every
      // collection, so it needs the meters too — nowhere else in the desk
      // surfaces a threshold crossing outside the individual Asset.
      this.meterQuery = this.args.context?.getCards(
        this,
        () => {
          let ref = identifyCard(Meter);
          return ref ? { filter: { type: ref } } : undefined;
        },
        () => this.realms,
        { isLive: true },
      );
    }

    get assets(): Asset[] {
      return ((this.assetQuery?.instances ?? []) as Asset[]).filter(Boolean);
    }
    get categories(): AssetCategory[] {
      return ((this.categoryQuery?.instances ?? []) as AssetCategory[]).filter(
        Boolean,
      );
    }
    get locations(): Location[] {
      let all = ((this.locationQuery?.instances ?? []) as Location[]).filter(
        Boolean,
      );
      // Location is a shared card — other desks' sites live in the same
      // realm and would otherwise leak into this estate's tree. Scope to
      // the estateRoot subtree by walking each location's `parent` chain.
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
      return ((this.planQuery?.instances ?? []) as MaintenancePlan[]).filter(
        Boolean,
      );
    }
    get workOrders(): WorkOrder[] {
      return ((this.workOrderQuery?.instances ?? []) as WorkOrder[]).filter(
        Boolean,
      );
    }
    get parts(): SparePart[] {
      return ((this.partQuery?.instances ?? []) as SparePart[]).filter(
        Boolean,
      );
    }
    get meters(): Meter[] {
      return ((this.meterQuery?.instances ?? []) as Meter[]).filter(Boolean);
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
    @action setPlanView(id: string) {
      this.planView = id;
    }
    @action setPartView(id: string) {
      this.partView = id;
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

    /**
     * The collection switch. Counts ride on the segments so switching does
     * not cost the glance the stacked layout gave for free — and the Parts
     * count carries the reorder hue whenever stock is short, which is the one
     * thing a supervisor needs to see while looking at Plans.
     */
    // A low-stock count rides in the label: a segment has no badge slot.
    get collectionSegments(): { value: string; label: string }[] {
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

    @action setCollection(id: string) {
      this.collection = id === 'parts' ? 'parts' : 'plans';
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

    // Overdue is red; "due soon" is amber, using the plan's own raise-ahead
    // lead time (trigger.leadDays — the domain's "raise N days ahead"
    // convention) rather than a made-up global threshold, so a plan raised
    // 30 days ahead and one raised 3 days ahead each light up at the moment
    // a work order would actually be raised for them.
    urgencyClass = (plan: MaintenancePlan): string => {
      if (plan.isOverdue) return 'amd-overdue';
      let due = plan.nextDueAt ? new Date(plan.nextDueAt) : undefined;
      if (!due) return '';
      let leadDays = plan.trigger?.leadDays ?? DUE_SOON_FALLBACK_DAYS;
      let daysUntil = (due.getTime() - Date.now()) / MS_PER_DAY;
      return daysUntil <= leadDays ? 'amd-due-soon' : '';
    };

    get filteredParts(): SparePart[] {
      return this.parts.filter((p) => {
        if (this.partBadge === 'reorder' && !p.belowReorderPoint) return false;
        return matchesSearch(this.partSearch, p.partNumber, p.name);
      });
    }

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

    // This card writes its own custom isolated template, so it does not get
    // the default template's automatic Theme wiring for free — a linked
    // `cardInfo.theme` (read via the base `cardTheme` computed) has to be
    // forwarded into a CardContainer here, same as field-component.gts does.
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

    get wizardSteps(): WizardStep[] {
      return SETUP_STEPS;
    }

    // Clamped: a completed setup can have `setupStep` persisted one past
    // the last real step (`steps.length`, not `steps.length - 1`) — SetupWizard
    // has no branch for that index, so its own `isLast` check disagrees with
    // itself between the initial render and the first "Back" click (the
    // button flips from "Next" to "Finish setup" without the step content
    // changing, since both indices fall into the same template fallback).
    get wizardCurrentStep(): number {
      let step = this.args.model.config?.setupStep ?? 0;
      return Math.min(step, SETUP_STEPS.length - 1);
    }

    @action setActiveTab(tabId: string) {
      this.activeTabId = tabId;
    }

    @action setWorkView(viewId: string) {
      this.workView = viewId;
    }

    // Same convention as openAsset / openCard below: `viewCard` is a
    // top-level component arg (SignatureFor<CardT> in base/card-api.gts),
    // never on `context` — `context.actions.viewCard` silently no-ops. Opens
    // the Work Order in the right stack instead of rendering it inline at
    // the bottom of the Work tab.
    @action openWorkOrder(wo: WorkOrder, format: Format = 'isolated') {
      let viewCard = (this.args as any).viewCard as ViewCardFn | undefined;
      viewCard?.(wo, format);
    }

    @action openAsset(asset: Asset) {
      this.args.viewCard?.(asset);
    }

    @action openCard(card: unknown) {
      this.args.viewCard?.(card as CardDef);
    }

    // The day currently minting a card swaps its + for a spinner (see
    // addingWorkOrderOn) and is disabled meanwhile, so a slow create can't
    // be double-clicked into two Work Orders on the same day.
    selectDay = (date: Date) => {
      void this.addWorkOrderTask.perform(date);
    };

    // createCard (also a top-level arg, not on context) opens the new card
    // in the stack in edit format in one round trip — same primitive the
    // blog-app "New Post" button and the Talent Tracker's addMeetingTask
    // use, instead of a manual SaveCardCommand-then-openCard pair. The
    // Calendar/Board pick the new Work Order up through the live
    // workOrderQuery the moment it indexes.
    private addWorkOrderTask = restartableTask(async (date: Date) => {
      this.addingWorkOrderOn = date;
      try {
        await this.createRecord(workOrderRef, {
          title: 'New Work Order',
          kind: 'corrective',
          status: 'requested',
          scheduledFor: dayKey(date),
        });
      } finally {
        this.addingWorkOrderOn = undefined;
      }
    });

    // Shared by every "+ Add <Noun>" action (Work Order, Asset, Maintenance
    // Plan, Spare Part): createCard (a top-level arg, not on context) opens
    // the new card in the stack in edit format in one round trip — same
    // primitive the blog-app "New Post" button and the Talent Tracker's
    // addMeetingTask use, instead of a manual SaveCardCommand-then-openCard
    // pair. Each collection's own live query picks the new card up the
    // moment it indexes — no linking step.
    private async createRecord(
      ref: { module: string; name: string },
      attributes: Record<string, unknown>,
    ): Promise<void> {
      this.workbenchError = undefined;
      let createCard = (this.args as any).createCard as
        | CreateCardFn
        | undefined;
      if (!createCard) {
        this.workbenchError = 'Commands are unavailable in this mode';
        return;
      }
      try {
        let realmHref = (this.args.model as any)?.[realmURL]?.href;
        let realm = realmHref ? new URL(realmHref) : undefined;
        let doc: LooseSingleCardDocument = {
          data: {
            type: 'card',
            attributes,
            meta: { adoptsFrom: ref },
          },
        };
        await createCard(ref, realm, { realmURL: realm, doc });
      } catch (error: any) {
        this.workbenchError = error?.message ?? String(error);
      }
    }

    @action addAsset() {
      void this.createRecord(assetRef, { name: 'New Asset' });
    }
    @action addPlan() {
      void this.createRecord(maintenancePlanRef, { name: 'New Maintenance Plan' });
    }
    @action addPart() {
      void this.createRecord(sparePartRef, { name: 'New Spare Part' });
    }

    // Start/Hold/Resume/Complete now live on WorkOrder's own isolated
    // component (work-order.gts) — opening a Work Order via viewCard is the
    // full technician workbench, not a read-only summary. This app-level
    // save remains for callers that hand over a work order they already
    // have (the calendar's drag-reschedule, the board's drag-status-change)
    // rather than the card's own current selection.
    @action async saveAnyWorkOrder(wo: WorkOrder) {
      if (!wo) return;
      await new SaveCardCommand(this.args.context?.commandContext).execute({
        card: wo,
      } as any);
    }

    @action advanceSetup(nextStep: number) {
      let config = this.args.model.config;
      if (!config) return;
      if (nextStep < 0) {
        config.setupCompletedAt = new Date();
      } else {
        config.setupStep = nextStep;
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
      this.args.model.costApprovalThreshold = Number.isFinite(n)
        ? n
        : this.args.model.costApprovalThreshold;
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

    <template>
      <CardContainer
        @cssImports={{this.themeCssImports}}
        @themeCss={{this.themeCss}}
        @themeScope={{this.themeScopeId}}
        class='amd-shell'
      >
      <div class='amd'>
        <TabbedHeader
          class='amd-header'
          @headerTitle={{@model.cardTitle}}
          @tabs={{TABS}}
          @activeTabId={{this.activeTabId}}
          @setActiveTab={{this.setActiveTab}}
        />
        {{#unless this.isSetUp}}
          <div class='amd-setup-banner'>
            Setup is still in progress — finish it on the Setup tab.
          </div>
        {{/unless}}
        <main class='amd-body'>
          {{#if (eq this.activeTabId 'Home')}}
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
          {{else if (eq this.activeTabId 'Assets')}}
            <AssetRegister
              @assets={{this.assets}}
              @locations={{this.locations}}
              @categories={{this.categories}}
              @onOpen={{this.openAsset}}
              @onAdd={{this.addAsset}}
            />
          {{else if (eq this.activeTabId 'Work')}}
            <div class='amd-work'>
              <h3 class='amd-visually-hidden'>{{if (eq this.workView 'board') 'Work Order Board' 'Maintenance Calendar'}}</h3>
              <ViewSelector @items={{WORK_VIEW_ITEMS}} @selectedId={{this.workView}} @onChange={{this.setWorkView}} />
              {{#if this.workbenchError}}
                <p class='amd-error' role='alert'>{{this.workbenchError}}</p>
              {{/if}}
              {{#if (eq this.workView 'board')}}
                <WorkOrderBoard
                  @workOrders={{this.workOrders}}
                  @onOpen={{this.openWorkOrder}}
                  @onChange={{this.saveAnyWorkOrder}}
                />
              {{else}}
                <MaintenanceCalendar
                  @workOrders={{this.workOrders}}
                  @plans={{this.plans}}
                  @onOpenWorkOrder={{this.openWorkOrder}}
                  @onSelectDay={{this.selectDay}}
                  @addingDate={{this.addingWorkOrderOn}}
                  @onChange={{this.saveAnyWorkOrder}}
                />
              {{/if}}
            </div>
          {{else if (eq this.activeTabId 'Plans & Parts')}}
            <div class='amd-plans'>
              <div class='amd-collection-head'>
                <SegmentedControl
                  @options={{this.collectionSegments}}
                  @value={{this.collection}}
                  @onValueChange={{this.setCollection}}
                  aria-label='Collection'
                />
                {{#if (eq this.collection 'plans')}}
                  <Button @kind='primary' @size='small' {{on 'click' this.addPlan}}>
                    <PlusIcon width='16' height='16' role='presentation' />
                    Add plan
                  </Button>
                {{else}}
                  <Button @kind='primary' @size='small' {{on 'click' this.addPart}}>
                    <PlusIcon width='16' height='16' role='presentation' />
                    Add part
                  </Button>
                {{/if}}
              </div>
              {{#if (eq this.collection 'plans')}}
              <section>
                <h3 class='amd-visually-hidden'>Maintenance Plans</h3>
                <CollectionToolbar
                  @search={{this.planSearch}}
                  @onSearch={{this.setPlanSearch}}
                  @placeholder='Search plans…'
                  @badges={{this.planBadges}}
                  @activeBadge={{this.planBadge}}
                  @onBadge={{this.setPlanBadge}}
                >
                  <:right>
                    <ViewSelector @items={{LIST_VIEW_ITEMS}} @selectedId={{this.planView}} @onChange={{this.setPlanView}} />
                  </:right>
                </CollectionToolbar>
                {{#if (eq this.planView 'table')}}
                  <Table
                    @items={{this.filteredPlans}}
                    @columns={{this.planColumns}}
                    @onRowClick={{this.openCard}}
                    @caption='Maintenance Plans'
                    @emptyMessage='No maintenance plans yet — add one from an Asset Category.'
                    @pageSize={{25}}
                  >
                    <:cell as |plan col|>
                      {{#if (eq col.key 'active')}}
                        <StatePill @label={{if plan.active 'active' 'inactive'}} @hue={{if plan.active 'green' 'slate'}} @dot={{true}} />
                      {{else if (eq col.key 'dueLabel')}}
                        <span class='{{this.urgencyClass plan}}'>{{plan.dueLabel}}</span>
                      {{else}}
                        {{get plan col.key}}
                      {{/if}}
                    </:cell>
                  </Table>
                {{else}}
                  <ul class='amd-rows amd-rows--{{this.planView}}'>
                    {{#each this.filteredPlans as |plan|}}
                      <li>
                        <button type='button' class='amd-row' {{on 'click' (fn this.openCard plan)}}>
                          <span class='amd-row-name'>{{plan.name}}</span>
                          <span class='amd-row-meta'>{{plan.assetTag}}</span>
                          <span class='{{this.urgencyClass plan}}'>{{plan.dueLabel}}</span>
                          <StatePill @label={{if plan.active 'active' 'inactive'}} @hue={{if plan.active 'green' 'slate'}} @dot={{true}} />
                        </button>
                      </li>
                    {{else}}
                      <li class='amd-row-empty'>No maintenance plans yet — add one from an Asset Category.</li>
                    {{/each}}
                  </ul>
                {{/if}}
              </section>
              {{else}}
              <section>
                <h3 class='amd-visually-hidden'>Spare Parts</h3>
                <CollectionToolbar
                  @search={{this.partSearch}}
                  @onSearch={{this.setPartSearch}}
                  @placeholder='Search parts…'
                  @badges={{this.partBadges}}
                  @activeBadge={{this.partBadge}}
                  @onBadge={{this.setPartBadge}}
                >
                  <:right>
                    <ViewSelector @items={{LIST_VIEW_ITEMS}} @selectedId={{this.partView}} @onChange={{this.setPartView}} />
                  </:right>
                </CollectionToolbar>
                {{#if (eq this.partView 'table')}}
                  <Table
                    @items={{this.filteredParts}}
                    @columns={{this.partColumns}}
                    @onRowClick={{this.openCard}}
                    @caption='Spare Parts'
                    @emptyMessage='No spare parts yet — add one to track stock and reorder points.'
                    @pageSize={{25}}
                  >
                    <:cell as |part col|>
                      {{#if (eq col.key 'belowReorderPoint')}}
                        <StatePill @label={{if part.belowReorderPoint 'reorder' 'ok'}} @hue={{if part.belowReorderPoint 'orange' 'green'}} @dot={{true}} />
                      {{else}}
                        {{get part col.key}}
                      {{/if}}
                    </:cell>
                  </Table>
                {{else}}
                  <ul class='amd-rows amd-rows--{{this.partView}}'>
                    {{#each this.filteredParts as |part|}}
                      <li>
                        <button type='button' class='amd-row' {{on 'click' (fn this.openCard part)}}>
                          <code class='amd-row-tag'>{{part.partNumber}}</code>
                          <span class='amd-row-name'>{{part.name}}</span>
                          <span class='amd-row-meta'>on hand {{part.onHand}}</span>
                          <StatePill @label={{if part.belowReorderPoint 'reorder' 'ok'}} @hue={{if part.belowReorderPoint 'orange' 'green'}} @dot={{true}} />
                        </button>
                      </li>
                    {{else}}
                      <li class='amd-row-empty'>No spare parts yet — add one to track stock and reorder points.</li>
                    {{/each}}
                  </ul>
                {{/if}}
              </section>
              {{/if}}
            </div>
          {{else if (eq this.activeTabId 'Setup')}}
            <SetupWizard
              @steps={{this.wizardSteps}}
              @currentStep={{this.wizardCurrentStep}}
              @onAdvance={{this.advanceSetup}}
            >
              <:step as |index|>
                {{#if (eq index 0)}}
                  <div class='amd-form'>
                    <label>Desk name
                      <BoxelInput @value={{@model.name}} @onInput={{this.updateName}} />
                    </label>
                    <label>Time zone
                      <BoxelInput @value={{@model.timeZone}} @onInput={{this.updateTimeZone}} />
                    </label>
                  </div>
                {{else if (eq index 1)}}
                  <div class='amd-form'>
                    <label>Asset id pattern
                      <BoxelInput
                        @value={{@model.config.idPattern}}
                        @onInput={{this.updateIdPattern}}
                        @invalid={{unless this.idPatternValid true}}
                      />
                    </label>
                    <label>Work Order id pattern
                      <BoxelInput
                        @value={{@model.workOrderPattern}}
                        @onInput={{this.updateWorkOrderPattern}}
                        @invalid={{unless this.workOrderPatternValid true}}
                      />
                    </label>
                  </div>
                {{else}}
                  <div class='amd-form'>
                    <label>Currency
                      <BoxelInput @value={{@model.currency}} @onInput={{this.updateCurrency}} />
                    </label>
                    <label>Cost approval threshold
                      <BoxelInput
                        @value={{@model.costApprovalThreshold}}
                        @onInput={{this.updateThreshold}}
                      />
                    </label>
                  </div>
                {{/if}}
              </:step>
            </SetupWizard>
          {{/if}}
        </main>
      </div>
      </CardContainer>
      <style scoped>
        .amd-shell {
          display: contents;
        }
        .amd {
          container-type: inline-size;
          container-name: amd;
          display: flex;
          flex-direction: column;
          height: 100%;
          min-height: 0;
          background: var(--card);
          color: var(--foreground);
        }
        .amd-setup-banner {
          padding: var(--boxel-sp-xs) var(--boxel-sp);
          background: color-mix(in oklab, var(--primary) 10%, var(--card));
          color: var(--foreground);
          font-size: var(--boxel-font-size-sm);
          border-bottom: 1px solid var(--border);
        }
        .amd-body {
          flex: 1;
          min-height: 0;
          overflow-y: auto;
          padding: var(--boxel-sp);
        }
        .amd-work {
          display: grid;
          gap: var(--boxel-sp);
        }
        .amd-empty {
          color: var(--muted-foreground);
          font-size: var(--boxel-font-size-sm);
        }
        .amd-error {
          margin: 0;
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          border: 1px solid var(--destructive, var(--boxel-danger));
          border-radius: var(--radius, var(--boxel-border-radius));
          background: color-mix(in oklab, var(--destructive, var(--boxel-danger)) 10%, var(--card));
          color: var(--destructive, var(--boxel-danger));
          font-size: var(--boxel-font-size-sm);
        }
        .amd-visually-hidden {
          position: absolute;
          width: 1px;
          height: 1px;
          padding: 0;
          margin: -1px;
          overflow: hidden;
          clip: rect(0, 0, 0, 0);
          white-space: nowrap;
          border: 0;
        }
        .amd-overdue {
          color: var(--destructive, var(--boxel-danger));
          font-weight: 600;
        }
        .amd-due-soon {
          /* the raw warning hue is a light highlight tone (meant for chip
             fills/dots), not text-safe on its own — self-dilute into the
             foreground for AA contrast, matching state-pill.gts's stateColor() */
          color: color-mix(in oklab, var(--warning, var(--boxel-warning)) 55%, var(--foreground));
          font-weight: 600;
        }
        .amd-plans {
          display: grid;
          gap: var(--boxel-sp);
        }
        /* One header row: which collection on the left, its create action on
           the right. The collection's own search, filter badges and view
           switcher live in the single toolbar below — never two of each. */
        .amd-collection-head {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: var(--boxel-sp-sm);
          flex-wrap: wrap;
        }
        .amd-plans section {
          display: grid;
          gap: var(--boxel-sp-xs);
        }
        .amd-plans h3 {
          font-size: var(--boxel-font-size-sm);
          text-transform: uppercase;
          letter-spacing: 0.04em;
          color: var(--muted-foreground);
          margin: 0;
        }
        /* Same row/tile language as Asset Register's grid/list rows, so
           switching view in any of the three tabs feels like one control. */
        .amd-rows {
          list-style: none;
          margin: 0;
          padding: 0;
          display: grid;
          gap: var(--boxel-sp-4xs);
        }
        .amd-rows--grid {
          grid-template-columns: repeat(auto-fill, minmax(15rem, 1fr));
          gap: var(--boxel-sp-sm);
        }
        .amd-rows--grid .amd-row {
          flex-direction: column;
          align-items: flex-start;
          min-height: 5rem;
        }
        .amd-row {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          width: 100%;
          min-height: 2.75rem;
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          border: 1px solid var(--border);
          border-radius: var(--boxel-border-radius);
          background: var(--card);
          color: inherit;
          font: inherit;
          text-align: left;
          cursor: pointer;
        }
        .amd-row:hover {
          background: var(--muted);
        }
        .amd-row-tag {
          font-family: var(--boxel-monospace-font-family, ui-monospace, monospace);
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        .amd-row-name {
          font-weight: 600;
          flex: 1;
          min-width: 8rem;
        }
        .amd-row-meta {
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
          flex: 1;
          min-width: 6rem;
        }
        .amd-row-empty {
          padding: var(--boxel-sp);
          border: 1px dashed var(--border);
          border-radius: var(--boxel-border-radius);
          color: var(--muted-foreground);
          font-style: italic;
        }
        .amd-form {
          display: grid;
          gap: var(--boxel-sp);
          max-width: 28rem;
        }
        .amd-form label {
          display: grid;
          gap: var(--boxel-sp-4xs);
          font-size: var(--boxel-font-size-sm);
          font-weight: 600;
          color: var(--foreground);
        }
      </style>
    </template>
  };
}

const TABS = [
  { tabId: 'Home', displayName: 'Home' },
  { tabId: 'Assets', displayName: 'Assets' },
  { tabId: 'Work', displayName: 'Work' },
  { tabId: 'Plans & Parts', displayName: 'Plans & Parts' },
  { tabId: 'Setup', displayName: 'Setup' },
];

const WORK_VIEW_ITEMS = [
  { id: 'calendar', icon: CalendarDaysIcon },
  { id: 'board', icon: KanbanIcon },
];

// Same three-icon switcher as Asset Register's — grid/list/table read as the
// same kind of control everywhere they appear, not a different pattern per tab.
const LIST_VIEW_ITEMS = [
  { id: 'grid', icon: LayoutGridIcon },
  { id: 'list', icon: LayoutListIcon },
  { id: 'table', icon: TableIcon },
];

const SETUP_STEPS: WizardStep[] = [
  { title: 'Desk' },
  { title: 'Identifiers' },
  { title: 'Money' },
];

export default AssetMaintenanceApp;
