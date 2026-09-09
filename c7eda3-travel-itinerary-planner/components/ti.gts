import { cached, tracked } from '@glimmer/tracking';
import { modifier } from 'ember-modifier';
import { on } from '@ember/modifier';
import { array, fn } from '@ember/helper';

import ChevronDownIcon from '@cardstack/boxel-icons/chevron-down';
import CopyIcon from '@cardstack/boxel-icons/copy';
import GripIcon from '@cardstack/boxel-icons/grip-vertical';
import MapPinIcon from '@cardstack/boxel-icons/map-pin';
import PencilIcon from '@cardstack/boxel-icons/pencil';
import PlaneIcon from '@cardstack/boxel-icons/plane';
import ShareIcon from '@cardstack/boxel-icons/share-2';
import SparklesIcon from '@cardstack/boxel-icons/sparkles';
import TrashIcon from '@cardstack/boxel-icons/trash';
import XIcon from '@cardstack/boxel-icons/x';

import { Button } from '@cardstack/boxel-ui/components';
import { add, eq } from '@cardstack/boxel-ui/helpers';
import { Component } from '@cardstack/base/card-api';
import TimeField from '@cardstack/base/time';

import {
  MapRender,
  type Coordinate,
  type Route,
} from '@cardstack/catalog/components/map-render';

import Popover from '@cardstack/catalog/46f065-popover/popover';

import UseAiAssistantCommand from '@cardstack/boxel-host/commands/ai-assistant';
import { ItineraryStop } from '../travel-itinerary';
import type { TravelItinerary } from '../travel-itinerary';
import { addHours, categoryStyle, formatCost } from '../utils/index';

export class TravelItineraryIsolated extends Component<typeof TravelItinerary> {
  get hasLinkedTheme(): boolean {
    return Boolean((this.args.model as any)?.cardInfo?.theme);
  }

  @tracked selectedIndex = -1;
  @tracked editingIndex = -1;
  @tracked collapsedDays: number[] = [];
  @tracked draggingIndex = -1;
  @tracked dragOverIndex = -1;
  @tracked mapDay: number | null = null;
  @tracked showShare = false;
  @tracked copied = false;
  // True while the AI Assistant room is being opened from the "Plan with AI"
  // button, so the trigger can show a brief busy label.
  @tracked aiLaunching = false;
  scrollerEl: HTMLElement | null = null;

  registerScroller = modifier((element: HTMLElement) => {
    this.scrollerEl = element;
  });

  private scrollToBottom = () => {
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        if (this.scrollerEl) {
          this.scrollerEl.scrollTo({
            top: this.scrollerEl.scrollHeight,
            behavior: 'smooth',
          });
        }
      });
    });
  };

  get stops() {
    return this.args.model?.stops ?? [];
  }

  // --- Share this trip ---
  // The share value is whatever the traveller manually entered into the
  // shareTripCode QR field (a card instance id / URL).
  get shareUrl() {
    return this.args.model?.shareTripCode?.data ?? '';
  }

  toggleShare = () => {
    this.showShare = !this.showShare;
    this.copied = false;
  };

  closeShare = () => {
    this.showShare = false;
    this.copied = false;
  };

  copyShareLink = async () => {
    let url = this.shareUrl;
    if (!url) return;
    try {
      await navigator.clipboard.writeText(url);
      this.copied = true;
      setTimeout(() => (this.copied = false), 1500);
    } catch (e) {
      console.warn('Could not copy share link', e);
    }
  };

  get destinationLabel() {
    let d = this.args.model?.destination;
    if (!d) return null;
    if (d.searchKey && d.searchKey.trim() !== '') return d.searchKey;
    if (d.lat != null && d.lon != null) return `${d.lat}, ${d.lon}`;
    return null;
  }

  get groupedStops() {
    let byDay = new Map<number, { stop: ItineraryStop; index: number }[]>();
    this.stops.forEach((stop, index) => {
      let day = stop.day ?? 1;
      if (!byDay.has(day)) byDay.set(day, []);
      byDay.get(day)!.push({ stop, index });
    });
    return [...byDay.keys()]
      .sort((a, b) => a - b)
      .map((day) => ({ day, stops: byDay.get(day)! }));
  }

  get mapDays() {
    return this.groupedStops.map((g) => g.day);
  }

  get activeMapDay() {
    return this.mapDay != null && this.mapDays.includes(this.mapDay)
      ? this.mapDay
      : null;
  }

  get routeCoordinates(): Coordinate[] {
    let active = this.activeMapDay;
    let result: Coordinate[] = [];
    this.groupedStops.forEach((group) => {
      if (active != null && group.day !== active) return;
      group.stops.forEach(({ stop, index }) => {
        let loc = stop.location;
        if (typeof loc?.lat === 'number' && typeof loc?.lon === 'number') {
          let label = loc.searchKey?.trim() || 'Stop';
          // The popup shows the place's real-world detail (open-now hours,
          // website) via the map's showLocationDetails enrichment — the
          // itinerary's planned start/end time stays in the list row, not here.
          result.push({
            id: index,
            lat: loc.lat,
            lng: loc.lon,
            name: label,
            address: `<strong>${label}</strong>`,
          });
        }
      });
    });
    return result;
  }

  get focusedStopId() {
    return this.selectedIndex >= 0 ? this.selectedIndex : null;
  }

  get selectedDay() {
    let s = this.stops[this.editingIndex];
    return s?.day ?? null;
  }

  setMapDay = (day: number | null) => {
    this.mapDay = day;
  };

  @cached
  get routes(): Route[] | undefined {
    let coords = this.routeCoordinates;
    if (!coords.length) return undefined;
    return [{ name: this.destinationLabel ?? 'Trip', coordinates: coords }];
  }

  // Opt into the shared map's Google-style enrichment: a Wikipedia photo +
  // nearby recommendations on each stop popup (with clickable nearby markers),
  // plus a "View on Google Maps" link per stop. routeStyle 'road' follows real
  // roads (OSRM); 'straight' connects stops directly with no routing API call.
  get mapConfig() {
    return {
      showLocationImage: true,
      showNearbyPlaces: true,
      showGoogleMapsLink: true,
      showFitButton: true,
      // Reserve room at the top so popups auto-pan clear of the floating
      // day-filter bar (sits at top:14px, ~40px tall).
      popupTopInset: 64,
      routeStyle: 'road' as const,
      // High-contrast dark slate so the route line stands apart from the
      // colourful stop pins and the light map tiles underneath.
      routeColor: '#1f2937',
    };
  }

  get dayCount() {
    let days = this.stops.map((s) => s.day ?? 0).filter((d) => d > 0);
    return days.length ? Math.max(...days) : 0;
  }

  get tripDays() {
    let start = this.args.model?.dateRange?.start;
    let end = this.args.model?.dateRange?.end;
    if (start && end) {
      let ms = end.getTime() - start.getTime();
      return Math.max(1, Math.round(ms / 86400000) + 1);
    }
    return 0;
  }

  get headerDays() {
    return this.tripDays || this.dayCount;
  }

  isDayCollapsed = (day: number) => this.collapsedDays.includes(day);

  toggleDay = (day: number) => {
    if (this.collapsedDays.includes(day)) {
      this.collapsedDays = this.collapsedDays.filter((d) => d !== day);
    } else {
      this.collapsedDays = [...this.collapsedDays, day];
    }
  };

  // Clicking a row only focuses the stop on the map (opens its pin popup); it
  // does not open the editor. Use the pencil icon to edit.
  selectStop = (index: number) => {
    this.selectedIndex = index;
    // If the map is filtered to a different day, switch to this stop's day so
    // its pin is visible, then its popup can open.
    let stop = this.stops[index];
    let day = stop?.day ?? 1;
    if (this.mapDay != null && this.mapDay !== day) {
      this.mapDay = day;
    }
  };

  editStop = (index: number) => {
    this.selectStop(index);
    this.editingIndex = index;
  };

  closeEditor = () => {
    this.editingIndex = -1;
  };

  private appendStop = (day: number, startVal: string) => {
    let stop = new ItineraryStop({
      day,
      startTime: new TimeField({ value: startVal }),
      endTime: new TimeField({ value: addHours(startVal, 2) }),
    });
    let arr = [...this.stops];
    let lastIdx = -1;
    arr.forEach((s, i) => {
      if ((s.day ?? 1) === day) lastIdx = i;
    });
    let insertAt = lastIdx === -1 ? arr.length : lastIdx + 1;
    arr.splice(insertAt, 0, stop);
    this.args.model.stops = arr;
    this.selectedIndex = insertAt;
    this.editingIndex = insertAt;
  };

  addDay = () => {
    this.appendStop((this.dayCount || 0) + 1, '09:00');
    this.scrollToBottom();
  };

  addStopToDay = (day: number) => {
    let dayStops = this.stops.filter((s) => (s.day ?? 1) === day);
    let last = dayStops[dayStops.length - 1];
    this.appendStop(day, last?.endTime?.value || '09:00');
  };

  removeStop = (index: number) => {
    this.args.model.stops = this.stops.filter((_, i) => i !== index);
    this.selectedIndex = -1;
    this.editingIndex = -1;
  };

  // --- drag & drop reorder ---
  dragStart = (index: number) => {
    this.draggingIndex = index;
    // Close the editor while reordering so it can't point at a stale index.
    this.editingIndex = -1;
  };

  dragOverStop = (index: number, event: DragEvent) => {
    event.preventDefault();
    this.dragOverIndex = index;
  };

  dragOverDay = (_day: number, event: DragEvent) => {
    event.preventDefault();
  };

  dropOnStop = (index: number, event: DragEvent) => {
    event.preventDefault();
    let from = this.draggingIndex;
    if (from < 0 || from === index) return this.resetDrag();
    let arr = [...this.stops];
    let item = arr[from];
    let target = arr[index];
    if (!item || !target) return this.resetDrag();
    item.day = target.day ?? item.day;
    arr.splice(from, 1);
    let ti = arr.indexOf(target);
    arr.splice(ti, 0, item);
    this.args.model.stops = arr;
    this.selectedIndex = arr.indexOf(item);
    this.resetDrag();
  };

  dropOnDay = (day: number, event: DragEvent) => {
    event.preventDefault();
    let from = this.draggingIndex;
    if (from < 0) return this.resetDrag();
    let arr = [...this.stops];
    let item = arr[from];
    if (!item) return this.resetDrag();
    item.day = day;
    arr.splice(from, 1);
    let lastIdx = -1;
    arr.forEach((s, i) => {
      if ((s.day ?? 1) === day) lastIdx = i;
    });
    arr.splice(lastIdx + 1, 0, item);
    this.args.model.stops = arr;
    this.selectedIndex = arr.indexOf(item);
    this.resetDrag();
  };

  dragEnd = () => this.resetDrag();

  resetDrag = () => {
    this.draggingIndex = -1;
    this.dragOverIndex = -1;
  };

  // Open the real Boxel AI Assistant on this trip: attach the travel-planner
  // skill + this card as context, in 'act' mode so the assistant applies its
  // plan by calling the Apply Itinerary command (which patches this card).
  planWithAssistant = async () => {
    let commandContext = this.args.context?.commandContext;
    let model = this.args.model;
    if (!commandContext || !model?.id) {
      return;
    }
    this.aiLaunching = true;
    try {
      // @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
      let here: string = import.meta.url;
      let skillCardId = new URL('../Skill/travel-planner-skill', here).href;
      await new UseAiAssistantCommand(commandContext).execute({
        roomName: model.tripTitle || model.title || 'Plan this trip',
        openRoom: true,
        llmModel: 'anthropic/claude-sonnet-4.6',
        // 'ask' so the assistant proposes the Apply Itinerary command and the
        // traveller approves it before the card changes (paired with the
        // command's requiresApproval: true in the skill).
        llmMode: 'ask',
        skillCardIds: [skillCardId],
        attachedCardIds: [model.id],
        openCardIds: [model.id],
        prompt: this.buildAssistantPrompt(),
      });
    } finally {
      this.aiLaunching = false;
    }
  };

  // A short, natural opening message — this shows in the chat as the
  // traveller's own message, so it must NOT contain steering. All the
  // behaviour (summarise + ask revise/start-fresh, or run the intake) lives in
  // the skill instructions instead.
  private buildAssistantPrompt(): string {
    let dest = this.destinationLabel;
    if (this.stops.length) {
      return `Let's review my current trip${dest ? ` to ${dest}` : ''}.`;
    }
    return dest ? `Help me plan a trip to ${dest}.` : 'Help me plan a trip.';
  }

  // Identity for the sidebar dateRange editor. When the plan apply replaces
  // model.dateRange, the field editor is reused (same component, swapped
  // @model) and its display, seeded once, would go stale. Keying the field on
  // the current dates forces a fresh editor so the sidebar reflects them
  // immediately.
  get dateRangeKey(): string {
    let s = this.args.model?.dateRange?.start;
    let e = this.args.model?.dateRange?.end;
    return `${s ? s.getTime() : ''}-${e ? e.getTime() : ''}`;
  }

  <template>
    <article class='ti-app {{unless this.hasLinkedTheme "ti-default-theme"}}'>
      <header class='ti-top'>
        <div class='ti-brand'>
          <div class='ti-brand-icon'><PlaneIcon width='20' height='20' /></div>
          <div>
            <h1 class='ti-title'>{{if
                @model.tripTitle
                @model.tripTitle
                'Travel Itinerary'
              }}</h1>
            <p class='ti-sub'>{{if
                this.destinationLabel
                this.destinationLabel
                'Plan your trip'
              }}
              {{#if this.headerDays}}
                ·
                {{this.headerDays}}
                {{if (eq this.headerDays 1) 'day' 'days'}}
              {{/if}}
            </p>
          </div>
        </div>
        <div class='ti-top-actions'>
          {{#if this.shareUrl}}
            <div class='ti-share'>
              <Button
                @kind='text-only'
                @size='auto'
                class='ti-share-btn {{if this.showShare "is-open"}}'
                aria-label='Share this trip'
                data-bx-popover-anchor
                data-ti-share-anchor
                {{on 'click' this.toggleShare}}
              ><ShareIcon width='16' height='16' /></Button>
              <Popover
                @anchor='[data-ti-share-anchor]'
                @open={{this.showShare}}
                @kind='details'
                @anchoring='beside'
                @placement='bottom-end'
                @size='auto'
                @elevation='floating'
                @label='Share this trip'
                @onDismiss={{this.closeShare}}
              >
                <:details>
                  <div class='ti-share-pop'>
                    <p class='ti-share-title'>Share this trip</p>
                    <div class='ti-share-qr'><@fields.shareTripCode /></div>
                    <Button
                      @kind='text-only'
                      @size='auto'
                      class='ti-share-copy'
                      {{on 'click' this.copyShareLink}}
                    >
                      <CopyIcon width='14' height='14' />
                      {{if this.copied 'Copied!' 'Copy link'}}
                    </Button>
                  </div>
                </:details>
              </Popover>
            </div>
          {{/if}}
          <Button
            class='ti-ai-trigger'
            data-test-plan-with-ai
            {{on 'click' this.planWithAssistant}}
          >
            <SparklesIcon width='16' height='16' />
            {{if this.aiLaunching 'Opening…' 'Plan with AI'}}
          </Button>
        </div>
      </header>

      <div class='ti-body'>
        <aside
          class='ti-panel'
          aria-label='Itinerary'
          {{this.registerScroller}}
        >
          <div class='ti-frame'>
            <label class='ti-frame-field'>
              <span class='ti-frame-label'>Where</span>
              <@fields.destination @format='edit' />
            </label>
            <label class='ti-frame-field'>
              <span class='ti-frame-label'>When</span>
              {{! Keyed remount so the editor refreshes when an applied plan
                  replaces dateRange (the reused editor would otherwise show
                  stale dates). }}
              {{#each (array this.dateRangeKey) key='@identity' as |_k|}}
                <@fields.dateRange @format='edit' />
              {{/each}}
            </label>
          </div>

          {{#if @model.estimatedTotalCost}}
            <div class='ti-budget-bar'>
              <span class='ti-budget-head'>
                <span class='ti-budget-label'>Trip budget</span>
                <span class='ti-budget-sub'>estimated total</span>
              </span>
              <span
                class='ti-budget-amount'
                title='Estimated trip total, summed from every stop with a cost'
              >{{formatCost
                  @model.estimatedTotalCost
                  @model.currencySymbol
                }}</span>
              <div
                class='ti-budget-currency'
                title='Budget currency — every stop cost is quoted in this'
              >
                <@fields.currency @format='edit' />
              </div>
            </div>
          {{/if}}

          <div class='ti-list-head'>
            <h2 class='ti-list-title'>Itinerary
              <span class='ti-list-count'>{{this.stops.length}}</span>
            </h2>
            <Button
              class='ti-add-day'
              @kind='secondary'
              @size='small'
              {{on 'click' this.addDay}}
            >+ Add day</Button>
          </div>

          {{#if this.stops.length}}
            <div class='ti-days'>
              {{#each this.groupedStops as |group|}}
                <section class='ti-day-group'>
                  <Button
                    @kind='text-only'
                    @size='auto'
                    class='ti-day-head'
                    {{on 'click' (fn this.toggleDay group.day)}}
                    {{on 'dragover' (fn this.dragOverDay group.day)}}
                    {{on 'drop' (fn this.dropOnDay group.day)}}
                  >
                    <ChevronDownIcon
                      class='ti-day-chevron
                        {{if (this.isDayCollapsed group.day) "is-collapsed"}}'
                      width='14'
                      height='14'
                    />
                    <span class='ti-day-label'>Day {{group.day}}</span>
                    <span class='ti-day-count'>{{group.stops.length}}</span>
                    <span class='ti-day-rule'></span>
                  </Button>
                  {{#unless (this.isDayCollapsed group.day)}}
                    <ul class='ti-stops'>
                      {{#each group.stops as |entry|}}
                        <li
                          class='ti-stop
                            {{if (eq entry.index this.selectedIndex) "is-sel"}}
                            {{if
                              (eq entry.index this.draggingIndex)
                              "is-dragging"
                            }}
                            {{if
                              (eq entry.index this.dragOverIndex)
                              "is-dragover"
                            }}'
                          style={{categoryStyle entry.stop.category}}
                          draggable='true'
                          {{on 'dragstart' (fn this.dragStart entry.index)}}
                          {{on 'dragover' (fn this.dragOverStop entry.index)}}
                          {{on 'drop' (fn this.dropOnStop entry.index)}}
                          {{on 'dragend' this.dragEnd}}
                        >
                          <span class='ti-grip' aria-hidden='true'>
                            <GripIcon width='14' height='14' />
                          </span>
                          <Button
                            @kind='text-only'
                            @size='auto'
                            class='ti-stop-row'
                            {{on 'click' (fn this.selectStop entry.index)}}
                          >
                            <span class='ti-stop-dot'></span>
                            {{#if entry.stop.startTime.value}}
                              <span
                                class='ti-stop-time'
                              >{{entry.stop.startTime.value}}</span>
                            {{/if}}
                            <span class='ti-stop-name'>{{if
                                entry.stop.location.searchKey
                                entry.stop.location.searchKey
                                'Untitled stop'
                              }}</span>
                            {{#if entry.stop.estimatedCost}}
                              <span class='ti-stop-cost'>{{formatCost
                                  entry.stop.estimatedCost
                                  @model.currencySymbol
                                }}</span>
                            {{/if}}
                          </Button>
                          <Button
                            @kind='text-only'
                            @size='auto'
                            class='ti-icon-btn
                              {{if
                                (eq entry.index this.editingIndex)
                                "is-editing"
                              }}'
                            aria-label='Edit stop'
                            {{on 'click' (fn this.editStop entry.index)}}
                          ><PencilIcon width='13' height='13' /></Button>
                          <Button
                            @kind='text-only'
                            @size='auto'
                            class='ti-icon-btn ti-danger'
                            aria-label='Remove stop'
                            {{on 'click' (fn this.removeStop entry.index)}}
                          ><TrashIcon width='13' height='13' /></Button>
                        </li>
                      {{/each}}
                    </ul>
                    <Button
                      @kind='text-only'
                      @size='auto'
                      class='ti-add-stop'
                      {{on 'click' (fn this.addStopToDay group.day)}}
                    >+ Add stop</Button>
                  {{/unless}}
                </section>
              {{/each}}
            </div>
          {{else}}
            <div class='ti-empty'>
              <MapPinIcon width='26' height='26' />
              <p class='ti-empty-title'>No stops yet</p>
              <p class='ti-empty-hint'>Set your destination and dates above,
                then add a day — or use
                <em>Plan with AI</em>.</p>
              <Button
                class='ti-empty-btn'
                @kind='primary'
                @size='small'
                {{on 'click' this.addDay}}
              >+ Add day 1</Button>
            </div>
          {{/if}}
        </aside>

        <div class='ti-map'>
          {{#if this.mapDays.length}}
            <div class='ti-map-filter'>
              <Button
                @kind='text-only'
                @size='auto'
                class='ti-chip {{unless this.activeMapDay "is-active"}}'
                {{on 'click' (fn this.setMapDay null)}}
              >All days</Button>
              {{#each this.mapDays as |d|}}
                <Button
                  @kind='text-only'
                  @size='auto'
                  class='ti-chip {{if (eq this.activeMapDay d) "is-active"}}'
                  {{on 'click' (fn this.setMapDay d)}}
                >Day {{d}}</Button>
              {{/each}}
            </div>
          {{/if}}
          {{#if this.routes}}
            <MapRender
              @routes={{this.routes}}
              @selectedId={{this.focusedStopId}}
              @mapConfig={{this.mapConfig}}
            />
          {{else}}
            <div class='ti-map-empty'>
              <MapPinIcon width='30' height='30' />
              <p>{{if
                  this.activeMapDay
                  'No mapped stops for this day yet.'
                  'Add stops with a location to see them on the map.'
                }}</p>
            </div>
          {{/if}}
        </div>

        {{#unless (eq this.editingIndex -1)}}
          {{#each @fields.stops as |StopField i|}}
            {{#if (eq i this.editingIndex)}}
              <aside class='ti-edit-panel' aria-label='Stop editor'>
                <div class='ti-editor-bar'>
                  <div class='ti-editor-heading'>
                    <h3 class='ti-editor-title'>Edit stop {{add i 1}}</h3>
                    {{#if this.selectedDay}}
                      <span class='ti-editor-day'>Day
                        {{this.selectedDay}}</span>
                    {{/if}}
                  </div>
                  <Button
                    @kind='text-only'
                    @size='auto'
                    class='ti-editor-close'
                    aria-label='Close editor'
                    {{on 'click' this.closeEditor}}
                  ><XIcon width='18' height='18' /></Button>
                </div>
                <div class='ti-editor-body'>
                  <StopField @format='edit' />
                </div>
              </aside>
            {{/if}}
          {{/each}}
        {{/unless}}
      </div>
    </article>

    <style scoped>
      /* Default palette when NO theme is linked — pins the semantic tokens
         to the Airbnb look so app-level defaults (e.g. a mint --primary)
         can't restyle the card arbitrarily. A linked theme omits this
         class, so its tokens win. */
      .ti-default-theme {
        color: var(--card-foreground);
      }
      .ti-app {
        /* Brand palette: each token resolves to the active design-system
           theme token (--primary, --foreground, …) so a linked brand-guide
           Theme (cardInfo.theme) can re-skin the card, else the literal
           Airbnb brand default (rausch accent, charcoal text, warm neutrals).
           (--accent-dark / --accent-bg have no semantic slot, so they stay at
           the literal Airbnb value regardless of theme.) */
        --c-accent-bg: color-mix(in oklch, var(--primary) 10%, var(--card));
        height: 100%;
        min-height: 100%;
        display: flex;
        flex-direction: column;
        /* No `overflow: hidden` here: it would make .ti-app the scroll
           container and trap the sticky header against itself. Leaving it
           visible lets the header stick to whichever ancestor actually
           scrolls — the inner .ti-body still owns the internal scroll. */
        background-color: var(--muted);
        font-family:
          -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica,
          Arial, sans-serif;
        color: var(--foreground);
      }
      .ti-top {
        position: sticky;
        top: 0;
        z-index: 5;
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: var(--boxel-sp);
        background-color: var(--card);
        color: var(--card-foreground);
        border-bottom: 1px solid var(--border);
        padding: 1rem 1.5rem;
        flex-shrink: 0;
      }
      .ti-brand {
        display: flex;
        align-items: center;
        gap: 0.75rem;
      }
      .ti-brand-icon {
        width: 2.5rem;
        height: 2.5rem;
        border-radius: 0.75rem;
        background-color: var(--primary);
        color: var(--primary-foreground);
        display: flex;
        align-items: center;
        justify-content: center;
        box-shadow: 0 4px 10px
          color-mix(in oklch, var(--destructive) 30%, transparent);
      }
      .ti-title {
        font-size: 1.125rem;
        font-weight: 800;
        margin: 0;
        letter-spacing: -0.02em;
        color: var(--foreground);
      }
      .ti-sub {
        font-size: 0.8125rem;
        margin: 0;
        color: var(--muted-foreground);
      }
      @keyframes ti-msg-in {
        from {
          opacity: 0;
          transform: translateY(4px);
        }
        to {
          opacity: 1;
          transform: translateY(0);
        }
      }
      .ti-ai-chips {
        display: grid;
        grid-template-rows: repeat(2, auto);
        grid-auto-flow: column;
        grid-auto-columns: max-content;
        justify-content: start;
        gap: 0.375rem;
        overflow-x: auto;
        padding-bottom: 0.25rem;
      }
      .ti-ai-chip {
        border: 1px solid var(--border);
        background-color: var(--card);
        color: var(--foreground);
        border-radius: 62.4375rem;
        padding: 0.4375rem 0.8125rem;
        font-size: 0.75rem;
        font-weight: 600;
        cursor: pointer;
        transition:
          border-color 0.12s ease,
          background 0.12s ease;
      }
      .ti-ai-chip:hover {
        border-color: var(--foreground);
        background-color: var(--muted);
        color: var(--muted-foreground);
      }
      .ti-ai-chip.is-selected {
        border-color: var(--foreground);
        background-color: var(--primary);
        color: var(--primary-foreground);
      }
      .ti-ai-chip-confirm {
        align-self: flex-end;
        border: none;
        background-color: var(--primary);
        color: var(--primary-foreground);
        border-radius: 62.4375rem;
        padding: 0.5rem 1rem;
        font-size: 0.75rem;
        font-weight: 700;
        cursor: pointer;
        transition: background 0.12s ease;
      }
      .ti-ai-chip-confirm:hover {
        background-color: var(--attention);
        color: var(--attention-foreground);
      }
      .ti-ai-chip-confirm.is-secondary {
        align-self: stretch;
        background-color: transparent;
        border: 1px solid var(--border);
        color: var(--foreground);
        text-align: center;
      }
      .ti-ai-chip-confirm.is-secondary:hover {
        border-color: var(--foreground);
        background-color: var(--muted);
        color: var(--muted-foreground);
      }
      .ti-ai-chip.is-cat {
        padding: 0.25rem 0.375rem;
        display: inline-flex;
        align-items: center;
      }
      .ti-ai-chip.is-cat.is-selected {
        background-color: var(--muted);
        color: inherit;
        border-color: var(--foreground);
        box-shadow: 0 0 0 1px var(--foreground);
      }
      .ti-ai-preview {
        display: flex;
        flex-direction: column;
        gap: 0.625rem;
        align-self: stretch;
        padding: 0.75rem;
        border: 1px solid var(--border);
        border-radius: 0.875rem;
        background-color: var(--card);
        color: var(--card-foreground);
        box-shadow: 0 1px 3px
          color-mix(in oklch, var(--foreground) 6%, transparent);
        animation: ti-msg-in 0.18s ease both;
      }
      .ti-ai-preview-day {
        display: flex;
        flex-direction: column;
        gap: 0.3125rem;
      }
      .ti-ai-preview-badge {
        align-self: flex-start;
        font-size: 0.625rem;
        font-weight: 800;
        color: var(--primary-ink);
        background-color: var(--c-accent-bg);
        border-radius: 62.4375rem;
        padding: 2px 0.5625rem;
      }
      .ti-ai-preview-stops {
        list-style: none;
        margin: 0;
        padding: 0;
        display: flex;
        flex-direction: column;
        gap: 0.1875rem;
      }
      .ti-ai-preview-stop {
        display: flex;
        flex-direction: column;
        min-width: 0;
        border-radius: 0.5rem;
      }
      .ti-ai-preview-stop.is-open {
        background-color: var(--muted);
        color: var(--muted-foreground);
        padding: 0.375rem 0.5rem;
      }
      .ti-ai-preview-row {
        display: flex;
        align-items: baseline;
        gap: 0.4375rem;
        width: 100%;
        min-width: 0;
        padding: 2px 0;
      }
      /* View button — opens the per-stop edit popover. */
      .ti-ai-preview-view {
        flex-shrink: 0;
        align-self: center;
        margin-left: auto;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        width: 1.5rem;
        height: 1.5rem;
        border: 1px solid var(--border);
        border-radius: 0.4375rem;
        background-color: var(--card);
        color: var(--muted-foreground);
        cursor: pointer;
        transition:
          border-color 0.12s ease,
          color 0.12s ease,
          background 0.12s ease;
      }
      .ti-ai-preview-view:hover {
        border-color: var(--primary);
        color: var(--primary-ink);
      }
      .ti-ai-preview-stop.is-open .ti-ai-preview-view {
        border-color: var(--primary);
        background-color: var(--c-accent-bg);
        color: var(--primary-ink);
      }
      /* The stop edit popover portals to document.body, OUTSIDE the host
         card, so the --c-* palette must be re-declared here or every var()
         resolves to nothing. Same design-system-token contract as the host. */
      .ti-ai-stop-pop {
        --c-accent-bg: color-mix(in oklch, var(--primary) 10%, var(--card));
        display: flex;
        flex-direction: column;
        width: 20rem;
        max-width: 100%;
        box-sizing: border-box;
        font-family:
          -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica,
          Arial, sans-serif;
        color: var(--foreground);
      }
      /* Scrolling body — ONLY this scrolls; the header is a static flex
         sibling above it (same model as the first-level .ai-chat-body /
         .ai-chat-head). The header never moves, so there is no sticky
         repaint flicker while scrolling the form. The cap mirrors the
         popover's spacious max-height minus the header so the popover's
         own outer scroll container never engages (which would otherwise
         scroll the header away with it). */
      .ti-ai-stop-body {
        flex: 1;
        min-height: 0;
        max-height: calc(
          min(31.25rem, 80vh, var(--bx-popover-avail-h, 100vh)) - 3.5rem
        );
        overflow-y: auto;
        scroll-behavior: smooth;
        padding: 1rem;
        box-sizing: border-box;
      }
      /* The expanded editor is the ItineraryStop field's own edit
         component — full editors for location/day/times/category/notes. */
      .ti-ai-stop-edit {
        width: 100%;
        min-width: 0;
        font-size: 0.75rem;
        background-color: var(--card);
        color: var(--card-foreground);
        border: 1px solid var(--border);
        border-radius: 0.625rem;
        padding: 0.625rem;
        box-sizing: border-box;
      }
      /* Static header — a flex sibling sitting ABOVE the scrolling body
         (not sticky), exactly like the first-level .ai-chat-head. It never
         scrolls, so the form scrolls under a fixed header with no flicker.
         Padding + border-bottom match .ai-chat-head for a consistent look. */
      .ti-ai-stop-head {
        flex-shrink: 0;
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 0.5rem;
        padding: 0.875rem 1rem;
        border-bottom: 1px solid var(--border);
      }
      .ti-ai-stop-head-title {
        font-size: 0.875rem;
        font-weight: 800;
        color: var(--foreground);
      }
      .ti-ai-stop-head-actions {
        display: flex;
        align-items: center;
        gap: 0.5rem;
      }
      .ti-ai-stop-close {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        width: 1.875rem;
        height: 1.875rem;
        flex-shrink: 0;
        border: 1px solid var(--border);
        border-radius: 50%;
        background-color: var(--card);
        color: var(--muted-foreground);
        cursor: pointer;
        transition:
          border-color 0.12s ease,
          color 0.12s ease,
          background 0.12s ease;
      }
      .ti-ai-stop-close:hover {
        border-color: var(--foreground);
        color: var(--foreground);
        background-color: var(--muted);
      }
      .ti-ai-preview-remove {
        display: inline-flex;
        align-items: center;
        gap: 0.3125rem;
        border: none;
        background-color: transparent;
        padding: 0.1875rem 0;
        font-size: 0.6875rem;
        font-weight: 700;
        color: var(--attention-ink);
        cursor: pointer;
      }
      .ti-ai-preview-remove:hover {
        text-decoration: underline;
      }
      .ti-ai-preview-time {
        flex-shrink: 0;
        font-size: 0.6875rem;
        font-weight: 700;
        color: var(--primary-ink);
        font-variant-numeric: tabular-nums;
      }
      .ti-ai-preview-name {
        font-size: 0.75rem;
        font-weight: 600;
        color: var(--foreground);
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .ti-ai-preview-cat {
        flex-shrink: 0;
        font-size: 0.625rem;
        font-weight: 700;
        color: var(--muted-foreground);
        text-transform: uppercase;
        letter-spacing: 0.04em;
      }
      .ti-ai-inputrow {
        display: flex;
        align-items: center;
        gap: 0.5rem;
        margin: 0;
      }
      .ti-ai-input {
        flex: 1;
        min-width: 0;
        font: inherit;
        font-size: 0.8125rem;
        color: var(--foreground);
        background-color: var(--card);
        border: 1px solid var(--border);
        border-radius: 62.4375rem;
        padding: 0.5625rem 0.875rem;
      }
      .ti-ai-input:focus {
        outline: none;
        border-color: var(--foreground);
      }
      .ti-ai-input::placeholder {
        color: var(--muted-foreground);
      }
      .ti-ai-send {
        display: flex;
        align-items: center;
        justify-content: center;
        width: 2.25rem;
        height: 2.25rem;
        flex-shrink: 0;
        border-radius: 50%;
        border: none;
        background-color: var(--primary);
        color: var(--primary-foreground);
        cursor: pointer;
        transition: background 0.12s ease;
      }
      .ti-ai-send:hover:not(:disabled) {
        background-color: var(--attention);
        color: var(--attention-foreground);
      }
      .ti-ai-send:disabled {
        opacity: 0.4;
        cursor: not-allowed;
      }
      .ti-ai-generate {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        gap: 0.375rem;
        width: 100%;
        padding: 0.6875rem 0.875rem;
        border-radius: 0.75rem;
        border: none;
        background-color: var(--primary);
        color: var(--primary-foreground);
        font-size: 0.8125rem;
        font-weight: 700;
        cursor: pointer;
        transition:
          transform 0.1s ease,
          box-shadow 0.12s ease;
      }
      .ti-ai-generate:hover:not(:disabled) {
        box-shadow: 0 4px 14px
          color-mix(in oklch, var(--primary) 45%, transparent);
        transform: translateY(-1px);
      }
      .ti-ai-generate:disabled {
        opacity: 0.55;
        cursor: not-allowed;
      }
      .ti-ai-generate.is-busy {
        opacity: 1;
        cursor: progress;
        animation: ti-generating 1.4s ease-in-out infinite;
      }
      .ti-ai-textarea {
        width: 100%;
        box-sizing: border-box;
        resize: vertical;
        min-height: 3.25rem;
        font: inherit;
        font-size: 0.8125rem;
        color: var(--foreground);
        background-color: var(--card);
        border: 1px solid var(--border);
        border-radius: 0.75rem;
        padding: 0.5625rem 0.75rem;
      }
      .ti-ai-textarea:focus {
        outline: none;
        border-color: var(--foreground);
      }
      .ti-ai-textarea::placeholder {
        color: var(--muted-foreground);
      }
      .ti-ai-daterange {
        width: 100%;
        flex-shrink: 0;
        overflow-x: auto;
      }
      @keyframes ti-generating {
        0%,
        100% {
          opacity: 1;
        }
        50% {
          opacity: 0.65;
        }
      }
      .ti-body {
        flex: 1;
        display: flex;
        min-height: 0;
        overflow: hidden;
      }
      .ti-panel {
        width: 21.25rem;
        flex-shrink: 0;
        background-color: var(--card);
        color: var(--card-foreground);
        border-right: 1px solid var(--border);
        display: flex;
        flex-direction: column;
        gap: 1.125rem;
        padding: 1.25rem;
        min-height: 0;
        overflow-y: auto;
      }

      /* Trip setup frame */
      .ti-frame {
        display: flex;
        flex-direction: column;
        gap: 0.75rem;
        padding: 1rem;
        border: 1px solid var(--border);
        border-radius: 1rem;
        box-shadow: 0 2px 8px
          color-mix(in oklch, var(--foreground) 5%, transparent);
      }
      .ti-frame-field {
        display: flex;
        flex-direction: column;
        gap: 0.3125rem;
      }
      .ti-frame-label {
        font-size: 0.6875rem;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.06em;
        color: var(--foreground);
      }

      /* Header actions + share popover */
      .ti-top-actions {
        display: flex;
        align-items: center;
        gap: 0.5rem;
        position: relative;
      }
      .ti-ai-trigger {
        display: inline-flex;
        align-items: center;
        gap: 0.375rem;
      }
      .ti-share-btn {
        display: flex;
        align-items: center;
        justify-content: center;
        width: 2.25rem;
        height: 2.25rem;
        border-radius: 50%;
        border: 1px solid var(--border);
        background-color: var(--card);
        color: var(--foreground);
        cursor: pointer;
        transition:
          background 0.12s ease,
          border-color 0.12s ease;
      }
      .ti-share-btn:hover,
      .ti-share-btn.is-open {
        background-color: var(--c-accent-bg);
        border-color: var(--primary);
        color: var(--attention-ink);
      }
      .ti-share {
        position: relative;
        display: flex;
      }
      /* Rendered inside <Popover>, which portals OUTSIDE the host card and
         owns the surface (background, border, radius, shadow, z-index, and
         placement). So this only styles the inner content layout — and must
         re-declare the --c-* palette, since the portaled node no longer
         inherits it from .ti-app. */
      .ti-share-pop {
        --c-accent-bg: color-mix(in oklch, var(--primary) 10%, var(--card));
        width: 12.5rem;
        max-width: 100%;
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 0.625rem;
        padding: 1rem;
        box-sizing: border-box;
        font-family:
          -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica,
          Arial, sans-serif;
      }
      .ti-share-title {
        font-size: 0.8125rem;
        font-weight: 800;
        color: var(--foreground);
        margin: 0;
      }
      .ti-share-qr {
        width: 9.375rem;
        height: 9.375rem;
      }
      .ti-share-copy {
        display: inline-flex;
        align-items: center;
        gap: 0.375rem;
        width: 100%;
        justify-content: center;
        padding: 0.5rem 0.75rem;
        border-radius: 0.625rem;
        border: none;
        background-color: var(--primary);
        color: var(--primary-foreground);
        font-size: 0.75rem;
        font-weight: 700;
        cursor: pointer;
      }
      .ti-share-copy:hover {
        background-color: var(--card);
        color: var(--card-foreground);
      }

      .ti-list-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: var(--boxel-sp-sm);
      }
      .ti-list-title {
        display: flex;
        align-items: center;
        gap: 0.5rem;
        font-size: 0.9375rem;
        font-weight: 800;
        letter-spacing: -0.01em;
        color: var(--foreground);
        margin: 0;
      }
      .ti-list-count {
        font-size: 0.6875rem;
        font-weight: 700;
        color: var(--primary-foreground);
        background-color: var(--primary);
        border-radius: 62.4375rem;
        padding: 1px 0.5625rem;
      }
      .ti-currency {
        margin-left: auto;
        flex-shrink: 0;
      }
      .ti-budget-bar {
        display: flex;
        align-items: center;
        gap: 0.625rem;
        margin-top: 0.625rem;
        padding: 0.625rem 0.875rem;
        border-radius: 0.75rem;
        /* inverted receipt-style total strip: foreground as fill, background
           as text, so it stays paired under any linked theme */
        background-color: var(--tooltip);
        color: var(--tooltip-foreground);
      }
      .ti-budget-head {
        display: flex;
        flex-direction: column;
        gap: 1px;
      }
      .ti-budget-label {
        font-size: 0.6875rem;
        font-weight: 700;
        letter-spacing: 0.08em;
        text-transform: uppercase;
      }
      .ti-budget-sub {
        font-size: 0.625rem;
        opacity: 0.6;
      }
      .ti-budget-amount {
        font-size: 0.9375rem;
        font-weight: 800;
        font-variant-numeric: tabular-nums;
      }
      .ti-budget-currency {
        margin-left: auto;
        flex-shrink: 0;
      }
      .ti-budget-currency :deep(.currency-field-edit) {
        min-width: 5.25rem;
        font-size: 0.75rem;
      }
      .ti-add-day {
        --boxel-button-border-radius: 62.4375rem;
        --boxel-button-border-color: var(--foreground);
        --boxel-button-text-color: var(--foreground);
        font-weight: 700;
        white-space: nowrap;
        flex-shrink: 0;
      }

      .ti-days {
        display: flex;
        flex-direction: column;
        gap: 1.125rem;
      }
      .ti-day-group {
        display: flex;
        flex-direction: column;
        gap: 0.375rem;
      }
      .ti-day-head {
        display: flex;
        align-items: center;
        gap: 0.5rem;
        width: 100%;
        border: none;
        padding: 0.375rem 2px;
        cursor: pointer;
        text-align: left;
        position: sticky;
        top: 0;
        background-color: var(--card);
        color: var(--card-foreground);
        z-index: 2;
        border-radius: 0.5rem;
      }
      .ti-day-head.is-droptarget {
        background-color: var(--c-accent-bg);
      }
      .ti-day-chevron {
        color: var(--muted-foreground);
        transition: transform 0.15s ease;
        flex-shrink: 0;
      }
      .ti-day-chevron.is-collapsed {
        transform: rotate(-90deg);
      }
      .ti-day-label {
        font-size: 0.9375rem;
        font-weight: 800;
        color: var(--foreground);
        white-space: nowrap;
        letter-spacing: -0.01em;
      }
      .ti-day-count {
        font-size: 0.6875rem;
        font-weight: 700;
        color: var(--muted-foreground);
        background-color: var(--muted);
        border-radius: 62.4375rem;
        padding: 1px 0.5rem;
      }
      .ti-day-rule {
        flex: 1;
        height: 1px;
        background-color: var(--border);
      }

      .ti-stops {
        position: relative;
        list-style: none;
        margin: 0;
        padding: 2px 0;
        display: flex;
        flex-direction: column;
        gap: 0.375rem;
      }
      .ti-stop {
        --stop-color: var(--primary);
        position: relative;
        display: flex;
        align-items: center;
        gap: 2px;
        background-color: var(--card);
        color: var(--card-foreground);
        border: 1px solid var(--border);
        border-radius: 0.875rem;
        box-shadow: 0 1px 2px
          color-mix(in oklch, var(--foreground) 4%, transparent);
        animation: ti-stop-in 0.35s cubic-bezier(0.22, 1, 0.36, 1) both;
        transition:
          box-shadow 0.15s ease,
          border-color 0.15s ease,
          transform 0.1s ease;
      }
      @keyframes ti-stop-in {
        from {
          opacity: 0;
          transform: translateY(8px);
        }
        to {
          opacity: 1;
          transform: translateY(0);
        }
      }
      .ti-stop:nth-child(2) {
        animation-delay: 0.04s;
      }
      .ti-stop:nth-child(3) {
        animation-delay: 0.08s;
      }
      .ti-stop:nth-child(4) {
        animation-delay: 0.12s;
      }
      .ti-stop:nth-child(n + 5) {
        animation-delay: 0.16s;
      }
      .ti-stop:hover {
        box-shadow: 0 4px 12px
          color-mix(in oklch, var(--foreground) 10%, transparent);
        border-color: var(--border);
      }
      .ti-stop.is-sel {
        border-color: var(--stop-color);
        box-shadow: 0 0 0 2px
          color-mix(in oklch, var(--stop-color) 30%, transparent);
      }
      .ti-stop.is-dragging {
        opacity: 0.45;
      }
      .ti-stop.is-dragover {
        border-color: var(--stop-color);
        transform: translateY(1px);
      }
      .ti-grip {
        display: flex;
        align-items: center;
        justify-content: center;
        padding-left: 0.4375rem;
        color: var(--subtle-foreground);
        cursor: grab;
        flex-shrink: 0;
      }
      .ti-stop:hover .ti-grip {
        color: var(--muted-foreground);
      }
      .ti-stop-row {
        flex: 1;
        display: flex;
        align-items: center;
        gap: 0.5625rem;
        background-color: transparent;
        border: none;
        padding: 0.6875rem 0.25rem 0.6875rem 0.375rem;
        cursor: pointer;
        text-align: left;
        min-width: 0;
      }
      .ti-stop-dot {
        width: 0.625rem;
        height: 0.625rem;
        border-radius: 50%;
        background-color: var(--stop-color);
        flex-shrink: 0;
      }
      .ti-stop-time {
        font-size: 0.75rem;
        font-weight: 700;
        color: color-mix(
          in oklch,
          var(--stop-color) 62%,
          var(--foreground) 38%
        );
        font-variant-numeric: tabular-nums;
        flex-shrink: 0;
      }
      .ti-stop-cost {
        font-size: 0.6875rem;
        font-weight: 700;
        color: var(--muted-foreground);
        font-variant-numeric: tabular-nums;
        flex-shrink: 0;
        margin-left: auto;
        padding-right: 0.25rem;
      }
      .ti-stop-name {
        font-size: 0.875rem;
        font-weight: 500;
        color: var(--foreground);
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .ti-icon-btn {
        background-color: transparent;
        border: none;
        padding: 0.5rem 0.625rem;
        cursor: pointer;
        color: var(--muted-foreground);
        border-radius: 0.5rem;
        display: flex;
        align-items: center;
        justify-content: center;
        flex-shrink: 0;
        opacity: 0;
        transition:
          opacity 0.12s ease,
          color 0.12s ease,
          background 0.12s ease;
      }
      .ti-stop:hover .ti-icon-btn,
      .ti-stop.is-sel .ti-icon-btn {
        opacity: 1;
      }
      .ti-icon-btn:hover {
        color: var(--primary-ink);
        background-color: var(--c-accent-bg);
      }
      .ti-icon-btn.is-editing {
        opacity: 1;
        color: var(--primary-ink);
        background-color: var(--c-accent-bg);
      }
      .ti-icon-btn.ti-danger:hover {
        color: var(--destructive-ink);
        background-color: var(--card);
      }
      .ti-add-stop {
        align-self: flex-start;
        margin-left: 0.5rem;
        background-color: transparent;
        border: none;
        padding: 0.25rem 2px;
        cursor: pointer;
        font-size: 0.8125rem;
        font-weight: 700;
        color: var(--primary-ink);
      }
      .ti-add-stop:hover {
        color: var(--attention-ink);
        text-decoration: underline;
      }

      .ti-empty {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 0.5rem;
        text-align: center;
        color: var(--muted-foreground);
        padding: 2.5rem 1rem;
        border: 1px dashed var(--border);
        border-radius: 1rem;
      }
      .ti-empty-title {
        font-size: 1rem;
        font-weight: 800;
        color: var(--foreground);
        margin: 0;
      }
      .ti-empty-hint {
        font-size: 0.8125rem;
        margin: 0;
        line-height: 1.5;
      }
      .ti-empty-btn {
        --boxel-button-color: var(--primary);
        --boxel-button-text-color: var(--primary-foreground);
        --boxel-button-border-color: var(--primary);
        --boxel-button-border-radius: 0.625rem;
        margin-top: 0.25rem;
        font-weight: 700;
      }

      /* Right-side edit panel (slides in) */
      .ti-edit-panel {
        width: 22.5rem;
        flex-shrink: 0;
        display: flex;
        flex-direction: column;
        background-color: var(--card);
        color: var(--card-foreground);
        border-left: 1px solid var(--border);
        box-shadow: -8px 0 24px
          color-mix(in oklch, var(--foreground) 8%, transparent);
        z-index: 1100;
        animation: ti-slide-in 0.22s cubic-bezier(0.22, 1, 0.36, 1) both;
      }
      @keyframes ti-slide-in {
        from {
          transform: translateX(16px);
          opacity: 0;
        }
        to {
          transform: translateX(0);
          opacity: 1;
        }
      }
      .ti-editor-bar {
        flex-shrink: 0;
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: var(--boxel-sp-sm);
        padding: 1rem 1.25rem;
        border-bottom: 1px solid var(--border);
      }
      .ti-editor-heading {
        display: flex;
        align-items: center;
        gap: 0.5rem;
      }
      .ti-editor-title {
        font-size: 0.9375rem;
        font-weight: 800;
        letter-spacing: -0.01em;
        color: var(--foreground);
        margin: 0;
      }
      .ti-editor-day {
        font-size: 0.6875rem;
        font-weight: 700;
        color: var(--primary-foreground);
        background-color: var(--primary);
        border-radius: 62.4375rem;
        padding: 2px 0.5625rem;
      }
      .ti-editor-close {
        display: flex;
        align-items: center;
        justify-content: center;
        width: 2rem;
        height: 2rem;
        border-radius: 50%;
        border: none;
        background-color: transparent;
        color: var(--foreground);
        cursor: pointer;
        transition: background 0.12s ease;
      }
      .ti-editor-close:hover {
        background-color: var(--muted);
        color: var(--muted-foreground);
      }
      .ti-editor-body {
        flex: 1;
        min-height: 0;
        overflow-y: auto;
        padding: 1.25rem;
      }

      .ti-map {
        flex: 1;
        min-width: 0;
        display: flex;
        position: relative;
      }
      .ti-map-filter {
        position: absolute;
        top: 0.875rem;
        left: 50%;
        transform: translateX(-50%);
        z-index: 1000;
        display: flex;
        gap: 0.25rem;
        max-width: calc(100% - 1.75rem);
        overflow-x: auto;
        padding: 0.3125rem;
        background-color: var(--card);
        color: var(--card-foreground);
        border-radius: 62.4375rem;
        box-shadow: 0 2px 12px
          color-mix(in oklch, var(--foreground) 18%, transparent);
      }
      .ti-chip {
        flex-shrink: 0;
        border: none;
        background-color: transparent;
        color: var(--foreground);
        font-size: 0.75rem;
        font-weight: 700;
        padding: 0.375rem 0.875rem;
        border-radius: 62.4375rem;
        cursor: pointer;
        white-space: nowrap;
        transition:
          background 0.12s ease,
          color 0.12s ease;
      }
      .ti-chip:hover {
        background-color: var(--muted);
        color: var(--muted-foreground);
      }
      .ti-chip.is-active {
        background-color: var(--primary);
        color: var(--primary-foreground);
      }
      .ti-map-empty {
        flex: 1;
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 0.5rem;
        color: var(--muted-foreground);
        text-align: center;
        padding: var(--boxel-sp);
        background-color: var(--muted);
      }
      .ti-map-empty p {
        margin: 0;
        font-size: 0.875rem;
        max-width: 28ch;
      }
    </style>
  </template>
}

export class TravelItineraryFitted extends Component<typeof TravelItinerary> {
  get hasLinkedTheme(): boolean {
    return Boolean((this.args.model as any)?.cardInfo?.theme);
  }

  get title() {
    return (
      this.args.model?.tripTitle?.trim() ||
      this.args.model?.destination?.searchKey?.trim() ||
      'Travel Itinerary'
    );
  }

  get stopCount() {
    return this.args.model?.stops?.length ?? 0;
  }

  get dayCount() {
    let start = this.args.model?.dateRange?.start;
    let end = this.args.model?.dateRange?.end;
    if (start && end) {
      return Math.max(
        1,
        Math.round((end.getTime() - start.getTime()) / 86400000) + 1,
      );
    }
    let days = (this.args.model?.stops ?? [])
      .map((s) => s.day ?? 0)
      .filter((d) => d > 0);
    return days.length ? Math.max(...days) : 0;
  }

  get metaText() {
    let parts: string[] = [];
    if (this.dayCount) {
      parts.push(`${this.dayCount} ${this.dayCount === 1 ? 'day' : 'days'}`);
    }
    parts.push(`${this.stopCount} ${this.stopCount === 1 ? 'stop' : 'stops'}`);
    return parts.join(' · ');
  }

  get shareUrl() {
    return this.args.model?.shareTripCode?.data ?? '';
  }

  get hasShareUrl() {
    return this.shareUrl !== '';
  }

  get destinationLabel() {
    let d = this.args.model?.destination;
    if (!d) return null;
    if (d.searchKey && d.searchKey.trim() !== '') return d.searchKey;
    if (d.lat != null && d.lon != null) return `${d.lat}, ${d.lon}`;
    return null;
  }

  get dateLabel() {
    let s = this.args.model?.dateRange?.start;
    let e = this.args.model?.dateRange?.end;
    if (!s || !e) return null;
    let fmt = (d: Date) =>
      d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
    return `${fmt(s)} – ${fmt(e)}`;
  }

  get subLine() {
    let parts: string[] = [];
    if (this.destinationLabel) parts.push(this.destinationLabel);
    if (this.dateLabel) parts.push(this.dateLabel);
    return parts.join(' · ');
  }

  get daySummaries() {
    let byDay = new Map<number, ItineraryStop[]>();
    (this.args.model?.stops ?? []).forEach((s) => {
      let day = s.day ?? 1;
      if (!byDay.has(day)) byDay.set(day, []);
      byDay.get(day)!.push(s);
    });
    return [...byDay.keys()]
      .sort((a, b) => a - b)
      .map((day) => {
        let stops = byDay.get(day)!;
        let names = stops
          .map((s) => s.location?.searchKey?.trim())
          .filter(Boolean);
        return {
          day,
          count: stops.length,
          preview: names.slice(0, 4).join(' · '),
        };
      });
  }

  <template>
    <div class='fitted-trip {{unless this.hasLinkedTheme "ti-default-theme"}}'>
      <div class='badge'>
        <span class='ft-icon'><PlaneIcon width='16' height='16' /></span>
        <span class='ft-title'>{{this.title}}</span>
      </div>

      <div class='strip'>
        <span class='ft-icon'><PlaneIcon width='18' height='18' /></span>
        <span class='ft-info'>
          <span class='ft-title'>{{this.title}}</span>
          <span class='ft-meta'>{{this.metaText}}</span>
        </span>
      </div>

      <div class='tile'>
        <div class='t-hero'>
          <span class='ft-icon ft-icon-lg t-hero-icon'><PlaneIcon
              width='20'
              height='20'
            /></span>
          <span class='t-head-text'>
            <h3 class='ft-title'>{{this.title}}</h3>
            {{#if this.subLine}}
              <span class='t-sub'>{{this.subLine}}</span>
            {{/if}}
          </span>
        </div>
        <span class='t-meta-row'>{{this.metaText}}</span>
        {{#if this.daySummaries.length}}
          <div class='t-days'>
            {{#each this.daySummaries as |d|}}
              <div class='t-day'>
                <span class='t-day-badge'>Day {{d.day}}</span>
                {{#if d.preview}}
                  <span class='t-day-preview'>{{d.preview}}</span>
                {{else}}
                  <span class='t-day-preview'>{{d.count}}
                    {{if (eq d.count 1) 'stop' 'stops'}}</span>
                {{/if}}
              </div>
            {{/each}}
          </div>
        {{/if}}
      </div>

      <div class='card'>
        <div class='c-hero'>
          <span class='ft-icon ft-icon-lg c-hero-icon'><PlaneIcon
              width='26'
              height='26'
            /></span>
          <span class='c-head-text'>
            <h3 class='c-hero-title'>{{this.title}}</h3>
            {{#if this.subLine}}
              <span class='c-hero-sub'>{{this.subLine}}</span>
            {{/if}}
            <span class='c-hero-meta'>{{this.metaText}}</span>
          </span>
          {{#if this.hasShareUrl}}
            <span class='c-qr'>
              <span class='c-qr-svg'><@fields.shareTripCode /></span>
              <span class='c-qr-cap'>Scan to view</span>
            </span>
          {{/if}}
        </div>

        <div class='c-content'>
          {{#if this.daySummaries.length}}
            <div class='c-days'>
              {{#each this.daySummaries as |d|}}
                <div class='c-day'>
                  <span class='c-day-badge'>Day {{d.day}}</span>
                  <span class='c-day-text'>
                    <span class='c-day-count'>{{d.count}}
                      {{if (eq d.count 1) 'stop' 'stops'}}</span>
                    {{#if d.preview}}
                      <span class='c-day-preview'>{{d.preview}}</span>
                    {{/if}}
                  </span>
                </div>
              {{/each}}
            </div>
          {{/if}}
        </div>
      </div>
    </div>

    <style scoped>
      .ti-default-theme {
        color: var(--card-foreground);
      }
      .fitted-trip {
        /* See TravelItineraryIsolated above for the design-system-token / literal palette. */
        --c-accent-bg: color-mix(in oklch, var(--primary) 10%, var(--card));
        width: 100%;
        height: 100%;
        font-family:
          -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica,
          Arial, sans-serif;
        color: var(--foreground);
      }
      .badge,
      .strip,
      .tile,
      .card {
        display: none;
        box-sizing: border-box;
        width: 100%;
        height: 100%;
        padding: clamp(0.25rem, 2cqmin, 0.5rem);
      }
      .ft-icon {
        flex-shrink: 0;
        display: flex;
        align-items: center;
        justify-content: center;
        border-radius: 0.5625rem;
        background-color: var(--primary);
        color: var(--primary-foreground);
        width: 1.75rem;
        height: 1.75rem;
      }
      .ft-icon-lg {
        width: 2.5rem;
        height: 2.5rem;
        border-radius: 0.75rem;
      }
      .ft-title {
        font-weight: 800;
        letter-spacing: -0.01em;
        color: var(--foreground);
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        margin: 0;
      }
      .ft-meta {
        font-size: 0.75rem;
        font-weight: 600;
        color: var(--muted-foreground);
      }
      .ft-info,
      .ft-body {
        display: flex;
        flex-direction: column;
        gap: 2px;
        min-width: 0;
      }

      /* Badge — small */
      @container fitted-card (max-width: 150px) and (max-height: 169px) {
        .badge {
          display: flex;
          flex-direction: column;
          align-items: flex-start;
          justify-content: center;
          gap: 0.375rem;
        }
        .badge .ft-title {
          font-size: 0.8125rem;
          white-space: normal;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
        }
      }

      /* Strip — wide and short */
      @container fitted-card (min-width: 151px) and (max-height: 169px) {
        .strip {
          display: flex;
          flex-direction: row;
          align-items: center;
          gap: 0.625rem;
        }
        .strip .ft-title {
          font-size: 0.875rem;
        }
      }

      /* Tile — narrow and tall */
      @container fitted-card (max-width: 399px) and (min-height: 170px) {
        .tile {
          display: flex;
          flex-direction: column;
          align-items: stretch;
          gap: 0;
          padding: 0;
          overflow: hidden;
        }
        .t-hero {
          display: flex;
          align-items: center;
          gap: 0.625rem;
          padding: 0.75rem 0.875rem;
          background-color: var(--card);
          color: var(--card-foreground);
        }
        .t-hero-icon {
          width: 2.125rem;
          height: 2.125rem;
          border-radius: 0.625rem;
          background-color: color-mix(in oklch, var(--card) 22%, transparent);
          color: var(--primary-foreground);
        }
        .t-head-text {
          display: flex;
          flex-direction: column;
          gap: 1px;
          min-width: 0;
        }
        .tile .ft-title {
          font-size: 0.9375rem;
          color: var(--primary-foreground);
          white-space: normal;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
        }
        .t-sub {
          font-size: 0.6875rem;
          font-weight: 600;
          color: color-mix(in oklch, var(--card-foreground) 85%, transparent);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .t-meta-row {
          flex-shrink: 0;
          padding: 0.5625rem 0.875rem 0.3125rem;
          font-size: 0.625rem;
          font-weight: 800;
          text-transform: uppercase;
          letter-spacing: 0.05em;
          color: var(--muted-foreground);
        }
        .t-days {
          flex: 1;
          min-height: 0;
          display: flex;
          flex-direction: column;
          gap: 0.375rem;
          padding: 0.1875rem 0.75rem 0.75rem;
          overflow: hidden;
        }
        .t-day {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          min-width: 0;
        }
        .t-day-badge {
          flex-shrink: 0;
          font-size: 0.625rem;
          font-weight: 800;
          color: var(--primary-ink);
          background-color: var(--c-accent-bg);
          border-radius: 62.4375rem;
          padding: 2px 0.5625rem;
        }
        .t-day-preview {
          font-size: 0.75rem;
          color: var(--muted-foreground);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      }

      /* Card — large */
      @container fitted-card (min-width: 400px) and (min-height: 170px) {
        .card {
          display: flex;
          flex-direction: column;
          align-items: stretch;
          gap: 0;
          padding: 0;
          overflow: hidden;
        }
        .c-hero {
          display: flex;
          align-items: flex-start;
          gap: 0.875rem;
          padding: 1.125rem 1.25rem;
          background-color: var(--card);
          color: var(--card-foreground);
        }
        .c-hero-icon {
          background-color: color-mix(in oklch, var(--card) 22%, transparent);
          color: var(--primary-foreground);
        }
        .c-head-text {
          flex: 1;
          display: flex;
          flex-direction: column;
          gap: 2px;
          min-width: 0;
        }
        .c-hero-title {
          font-size: 1.1875rem;
          font-weight: 800;
          letter-spacing: -0.01em;
          color: var(--primary-foreground);
          margin: 0;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
          overflow: hidden;
        }
        .c-hero-sub {
          font-size: 0.8125rem;
          font-weight: 600;
          color: color-mix(in oklch, var(--card-foreground) 92%, transparent);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .c-hero-meta {
          font-size: 0.75rem;
          font-weight: 600;
          color: color-mix(in oklch, var(--card-foreground) 78%, transparent);
          margin-top: 2px;
        }
        .c-qr {
          flex-shrink: 0;
          display: flex;
          flex-direction: column;
          align-items: center;
          gap: 0.3125rem;
        }
        .c-qr-svg {
          width: 4.125rem;
          height: 4.125rem;
          padding: 0.375rem;
          background-color: var(--primary-foreground);
          border-radius: 0.625rem;
          box-shadow: 0 4px 12px
            color-mix(in oklch, var(--foreground) 18%, transparent);
        }
        .c-qr-cap {
          font-size: 0.5625rem;
          font-weight: 800;
          text-transform: uppercase;
          letter-spacing: 0.06em;
          color: color-mix(in oklch, var(--card-foreground) 95%, transparent);
        }
        .c-content {
          flex: 1;
          min-height: 0;
          display: flex;
          flex-direction: column;
          gap: 0.75rem;
          padding: 1rem 1.25rem;
          overflow: hidden;
        }
        .c-days {
          flex: 1;
          min-height: 0;
          display: flex;
          flex-direction: column;
          gap: 0.5rem;
          overflow: hidden;
        }
        .c-day {
          display: flex;
          align-items: flex-start;
          gap: 0.625rem;
          padding: 0.5625rem 0.75rem;
          background-color: var(--muted);
          color: var(--muted-foreground);
          border-radius: 0.75rem;
        }
        .c-day-badge {
          flex-shrink: 0;
          font-size: 0.6875rem;
          font-weight: 800;
          color: var(--primary-foreground);
          background-color: var(--primary);
          border-radius: 62.4375rem;
          padding: 0.1875rem 0.625rem;
        }
        .c-day-text {
          display: flex;
          flex-direction: column;
          gap: 1px;
          min-width: 0;
        }
        .c-day-count {
          font-size: 0.75rem;
          font-weight: 700;
          color: var(--foreground);
        }
        .c-day-preview {
          font-size: 0.75rem;
          color: var(--muted-foreground);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      }
    </style>
  </template>
}
