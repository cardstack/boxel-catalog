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
import { Component } from 'https://cardstack.com/base/card-api';
import TimeField from 'https://cardstack.com/base/time';

import {
  MapRender,
  type Coordinate,
  type Route,
} from '@cardstack/catalog/components/map-render';

import Popover from '@cardstack/catalog/46f065-popover/popover';

import UseAiAssistantCommand from '@cardstack/boxel-host/commands/ai-assistant';
import { ItineraryStop } from '../travel-itinerary';
import type { TravelItinerary } from '../travel-itinerary';
import { addHours, categoryStyle } from '../utils/index';

export class TravelItineraryIsolated extends Component<typeof TravelItinerary> {
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
    <article class='ti-app'>
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
              <button
                type='button'
                class='ti-share-btn {{if this.showShare "is-open"}}'
                aria-label='Share this trip'
                data-bx-popover-anchor
                data-ti-share-anchor
                {{on 'click' this.toggleShare}}
              ><ShareIcon width='16' height='16' /></button>
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
                    <button
                      type='button'
                      class='ti-share-copy'
                      {{on 'click' this.copyShareLink}}
                    >
                      <CopyIcon width='14' height='14' />
                      {{if this.copied 'Copied!' 'Copy link'}}
                    </button>
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

          <div class='ti-list-head'>
            <h2 class='ti-list-title'>Itinerary
              <span class='ti-list-count'>{{this.stops.length}}</span></h2>
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
                  <button
                    type='button'
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
                  </button>
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
                          <button
                            type='button'
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
                          </button>
                          <button
                            type='button'
                            class='ti-icon-btn
                              {{if
                                (eq entry.index this.editingIndex)
                                "is-editing"
                              }}'
                            aria-label='Edit stop'
                            {{on 'click' (fn this.editStop entry.index)}}
                          ><PencilIcon width='13' height='13' /></button>
                          <button
                            type='button'
                            class='ti-icon-btn ti-danger'
                            aria-label='Remove stop'
                            {{on 'click' (fn this.removeStop entry.index)}}
                          ><TrashIcon width='13' height='13' /></button>
                        </li>
                      {{/each}}
                    </ul>
                    <button
                      type='button'
                      class='ti-add-stop'
                      {{on 'click' (fn this.addStopToDay group.day)}}
                    >+ Add stop</button>
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
              <button
                type='button'
                class='ti-chip {{unless this.activeMapDay "is-active"}}'
                {{on 'click' (fn this.setMapDay null)}}
              >All days</button>
              {{#each this.mapDays as |d|}}
                <button
                  type='button'
                  class='ti-chip {{if (eq this.activeMapDay d) "is-active"}}'
                  {{on 'click' (fn this.setMapDay d)}}
                >Day {{d}}</button>
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
                  <button
                    type='button'
                    class='ti-editor-close'
                    aria-label='Close editor'
                    {{on 'click' this.closeEditor}}
                  ><XIcon width='18' height='18' /></button>
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
      .ti-app {
        /* Brand palette, Airbnb-first: the literal Airbnb brand values are the
           default look (rausch accent, charcoal text, warm neutrals), so the
           card reads as Airbnb regardless of any surrounding design-system
           theme. Only an explicit public --ti-* override changes them — the
           card intentionally does NOT defer to --primary/--foreground/etc. */
        --c-accent: var(--ti-accent, #ff385c);
        --c-accent-dark: var(--ti-accent-dark, #bd1e59);
        --c-accent-bg: var(
          --ti-accent-bg,
          color-mix(in srgb, var(--c-accent) 10%, #ffffff)
        );
        --c-text: var(--ti-text, #222222);
        --c-text-light: var(--ti-text-light, #ffffff);
        --c-muted: var(--ti-muted, #717171);
        --c-border: var(--ti-border, #dddddd);
        --c-border-light: var(--ti-border-light, #ebebeb);
        --c-bg: var(--ti-bg, #f7f7f7);
        height: 100%;
        min-height: 100%;
        display: flex;
        flex-direction: column;
        /* No `overflow: hidden` here: it would make .ti-app the scroll
           container and trap the sticky header against itself. Leaving it
           visible lets the header stick to whichever ancestor actually
           scrolls — the inner .ti-body still owns the internal scroll. */
        background: var(--c-bg);
        font-family:
          -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica,
          Arial, sans-serif;
        color: var(--c-text);
      }
      .ti-top {
        position: sticky;
        top: 0;
        z-index: 5;
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: var(--boxel-sp);
        background: #fff;
        border-bottom: 1px solid var(--c-border-light);
        padding: 16px 24px;
        flex-shrink: 0;
      }
      .ti-brand {
        display: flex;
        align-items: center;
        gap: 12px;
      }
      .ti-brand-icon {
        width: 40px;
        height: 40px;
        border-radius: 12px;
        background: var(--c-accent);
        color: var(--c-text-light);
        display: flex;
        align-items: center;
        justify-content: center;
        box-shadow: 0 4px 10px rgba(255, 56, 92, 0.3);
      }
      .ti-title {
        font-size: 18px;
        font-weight: 800;
        margin: 0;
        letter-spacing: -0.02em;
        color: var(--c-text);
      }
      .ti-sub {
        font-size: 13px;
        margin: 0;
        color: var(--c-muted);
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
        gap: 6px;
        overflow-x: auto;
        padding-bottom: 4px;
      }
      .ti-ai-chip {
        border: 1px solid var(--c-border);
        background: #fff;
        color: var(--c-text);
        border-radius: 999px;
        padding: 7px 13px;
        font-size: 12px;
        font-weight: 600;
        cursor: pointer;
        transition:
          border-color 0.12s ease,
          background 0.12s ease;
      }
      .ti-ai-chip:hover {
        border-color: var(--c-text);
        background: var(--c-bg);
      }
      .ti-ai-chip.is-selected {
        border-color: var(--c-text);
        background: var(--c-text);
        color: var(--c-text-light);
      }
      .ti-ai-chip-confirm {
        align-self: flex-end;
        border: none;
        background: var(--c-accent);
        color: var(--c-text-light);
        border-radius: 999px;
        padding: 8px 16px;
        font-size: 12px;
        font-weight: 700;
        cursor: pointer;
        transition: background 0.12s ease;
      }
      .ti-ai-chip-confirm:hover {
        background: var(--c-accent-dark);
      }
      .ti-ai-chip-confirm.is-secondary {
        align-self: stretch;
        background: transparent;
        border: 1px solid var(--c-border);
        color: var(--c-text);
        text-align: center;
      }
      .ti-ai-chip-confirm.is-secondary:hover {
        border-color: var(--c-text);
        background: var(--c-bg);
      }
      .ti-ai-chip.is-cat {
        padding: 4px 6px;
        display: inline-flex;
        align-items: center;
      }
      .ti-ai-chip.is-cat.is-selected {
        background: var(--c-bg);
        color: inherit;
        border-color: var(--c-text);
        box-shadow: 0 0 0 1px var(--c-text);
      }
      .ti-ai-preview {
        display: flex;
        flex-direction: column;
        gap: 10px;
        align-self: stretch;
        padding: 12px;
        border: 1px solid var(--c-border-light);
        border-radius: 14px;
        background: #fff;
        box-shadow: 0 1px 3px rgba(0, 0, 0, 0.06);
        animation: ti-msg-in 0.18s ease both;
      }
      .ti-ai-preview-day {
        display: flex;
        flex-direction: column;
        gap: 5px;
      }
      .ti-ai-preview-badge {
        align-self: flex-start;
        font-size: 10px;
        font-weight: 800;
        color: var(--c-accent);
        background: var(--c-accent-bg);
        border-radius: 999px;
        padding: 2px 9px;
      }
      .ti-ai-preview-stops {
        list-style: none;
        margin: 0;
        padding: 0;
        display: flex;
        flex-direction: column;
        gap: 3px;
      }
      .ti-ai-preview-stop {
        display: flex;
        flex-direction: column;
        min-width: 0;
        border-radius: 8px;
      }
      .ti-ai-preview-stop.is-open {
        background: var(--c-bg);
        padding: 6px 8px;
      }
      .ti-ai-preview-row {
        display: flex;
        align-items: baseline;
        gap: 7px;
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
        width: 24px;
        height: 24px;
        border: 1px solid var(--c-border-light);
        border-radius: 7px;
        background: #fff;
        color: var(--c-muted);
        cursor: pointer;
        transition:
          border-color 0.12s ease,
          color 0.12s ease,
          background 0.12s ease;
      }
      .ti-ai-preview-view:hover {
        border-color: var(--c-accent);
        color: var(--c-accent);
      }
      .ti-ai-preview-stop.is-open .ti-ai-preview-view {
        border-color: var(--c-accent);
        background: var(--c-accent-bg);
        color: var(--c-accent);
      }
      /* The stop edit popover portals to document.body, OUTSIDE the host
         card, so the --c-* palette must be re-declared here or every var()
         resolves to nothing. Same --ti-* override contract as the host. */
      .ti-ai-stop-pop {
        --c-accent: var(--ti-accent, #ff385c);
        --c-accent-dark: var(--ti-accent-dark, #bd1e59);
        --c-accent-bg: var(
          --ti-accent-bg,
          color-mix(in srgb, var(--c-accent) 10%, #ffffff)
        );
        --c-text: var(--ti-text, #222222);
        --c-muted: var(--ti-muted, #717171);
        --c-border: var(--ti-border, #dddddd);
        --c-border-light: var(--ti-border-light, #ebebeb);
        --c-bg: var(--ti-bg, #f7f7f7);
        display: flex;
        flex-direction: column;
        width: 320px;
        max-width: 100%;
        box-sizing: border-box;
        font-family:
          -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica,
          Arial, sans-serif;
        color: var(--c-text);
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
          min(500px, 80vh, var(--bx-popover-avail-h, 100vh)) - 56px
        );
        overflow-y: auto;
        scroll-behavior: smooth;
        padding: 16px;
        box-sizing: border-box;
      }
      /* The expanded editor is the ItineraryStop field's own edit
         component — full editors for location/day/times/category/notes. */
      .ti-ai-stop-edit {
        width: 100%;
        min-width: 0;
        font-size: 12px;
        background: #fff;
        border: 1px solid var(--c-border-light);
        border-radius: 10px;
        padding: 10px;
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
        gap: 8px;
        padding: 14px 16px;
        border-bottom: 1px solid var(--c-border-light);
      }
      .ti-ai-stop-head-title {
        font-size: 14px;
        font-weight: 800;
        color: var(--c-text);
      }
      .ti-ai-stop-head-actions {
        display: flex;
        align-items: center;
        gap: 8px;
      }
      .ti-ai-stop-close {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        width: 30px;
        height: 30px;
        flex-shrink: 0;
        border: 1px solid var(--c-border);
        border-radius: 50%;
        background: #fff;
        color: var(--c-muted);
        cursor: pointer;
        transition:
          border-color 0.12s ease,
          color 0.12s ease,
          background 0.12s ease;
      }
      .ti-ai-stop-close:hover {
        border-color: var(--c-text);
        color: var(--c-text);
        background: var(--c-bg);
      }
      .ti-ai-preview-remove {
        display: inline-flex;
        align-items: center;
        gap: 5px;
        border: none;
        background: transparent;
        padding: 3px 0;
        font-size: 11px;
        font-weight: 700;
        color: var(--c-accent-dark);
        cursor: pointer;
      }
      .ti-ai-preview-remove:hover {
        text-decoration: underline;
      }
      .ti-ai-preview-time {
        flex-shrink: 0;
        font-size: 11px;
        font-weight: 700;
        color: var(--c-accent);
        font-variant-numeric: tabular-nums;
      }
      .ti-ai-preview-name {
        font-size: 12px;
        font-weight: 600;
        color: var(--c-text);
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .ti-ai-preview-cat {
        flex-shrink: 0;
        font-size: 10px;
        font-weight: 700;
        color: var(--c-muted);
        text-transform: uppercase;
        letter-spacing: 0.04em;
      }
      .ti-ai-inputrow {
        display: flex;
        align-items: center;
        gap: 8px;
        margin: 0;
      }
      .ti-ai-input {
        flex: 1;
        min-width: 0;
        font: inherit;
        font-size: 13px;
        color: var(--c-text);
        background: #fff;
        border: 1px solid var(--c-border);
        border-radius: 999px;
        padding: 9px 14px;
      }
      .ti-ai-input:focus {
        outline: none;
        border-color: var(--c-text);
      }
      .ti-ai-input::placeholder {
        color: var(--c-muted);
      }
      .ti-ai-send {
        display: flex;
        align-items: center;
        justify-content: center;
        width: 36px;
        height: 36px;
        flex-shrink: 0;
        border-radius: 50%;
        border: none;
        background: var(--c-accent);
        color: var(--c-text-light);
        cursor: pointer;
        transition: background 0.12s ease;
      }
      .ti-ai-send:hover:not(:disabled) {
        background: var(--c-accent-dark);
      }
      .ti-ai-send:disabled {
        opacity: 0.4;
        cursor: not-allowed;
      }
      .ti-ai-generate {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        gap: 6px;
        width: 100%;
        padding: 11px 14px;
        border-radius: 12px;
        border: none;
        background: linear-gradient(
          90deg,
          var(--c-accent) 0%,
          var(--c-accent-dark) 100%
        );
        color: var(--c-text-light);
        font-size: 13px;
        font-weight: 700;
        cursor: pointer;
        transition:
          transform 0.1s ease,
          box-shadow 0.12s ease;
      }
      .ti-ai-generate:hover:not(:disabled) {
        box-shadow: 0 4px 14px
          color-mix(in srgb, var(--c-accent) 45%, transparent);
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
        min-height: 52px;
        font: inherit;
        font-size: 13px;
        color: var(--c-text);
        background: #fff;
        border: 1px solid var(--c-border);
        border-radius: 12px;
        padding: 9px 12px;
      }
      .ti-ai-textarea:focus {
        outline: none;
        border-color: var(--c-text);
      }
      .ti-ai-textarea::placeholder {
        color: var(--c-muted);
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
        width: 340px;
        flex-shrink: 0;
        background: #fff;
        border-right: 1px solid var(--c-border-light);
        display: flex;
        flex-direction: column;
        gap: 18px;
        padding: 20px;
        min-height: 0;
        overflow-y: auto;
      }

      /* Trip setup frame */
      .ti-frame {
        display: flex;
        flex-direction: column;
        gap: 12px;
        padding: 16px;
        border: 1px solid var(--c-border);
        border-radius: 16px;
        box-shadow: 0 2px 8px rgba(0, 0, 0, 0.05);
      }
      .ti-frame-field {
        display: flex;
        flex-direction: column;
        gap: 5px;
      }
      .ti-frame-label {
        font-size: 11px;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.06em;
        color: var(--c-text);
      }

      /* Header actions + share popover */
      .ti-top-actions {
        display: flex;
        align-items: center;
        gap: 8px;
        position: relative;
      }
      .ti-ai-trigger {
        display: inline-flex;
        align-items: center;
        gap: 6px;
      }
      .ti-share-btn {
        display: flex;
        align-items: center;
        justify-content: center;
        width: 36px;
        height: 36px;
        border-radius: 50%;
        border: 1px solid var(--c-border);
        background: #fff;
        color: var(--c-text);
        cursor: pointer;
        transition:
          background 0.12s ease,
          border-color 0.12s ease;
      }
      .ti-share-btn:hover,
      .ti-share-btn.is-open {
        background: var(--c-accent-bg);
        border-color: var(--c-accent);
        color: var(--c-accent-dark);
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
        --c-accent: var(--ti-accent, #ff385c);
        --c-accent-dark: var(--ti-accent-dark, #bd1e59);
        --c-accent-bg: var(
          --ti-accent-bg,
          color-mix(in srgb, var(--c-accent) 10%, #ffffff)
        );
        --c-text: var(--ti-text, #222222);
        --c-text-light: var(--ti-text-light, #ffffff);
        --c-muted: var(--ti-muted, #717171);
        --c-border-light: var(--ti-border-light, #ebebeb);
        --c-bg: var(--ti-bg, #f7f7f7);
        width: 200px;
        max-width: 100%;
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 10px;
        padding: 16px;
        box-sizing: border-box;
        font-family:
          -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica,
          Arial, sans-serif;
      }
      .ti-share-title {
        font-size: 13px;
        font-weight: 800;
        color: var(--c-text);
        margin: 0;
      }
      .ti-share-qr {
        width: 150px;
        height: 150px;
      }
      .ti-share-copy {
        display: inline-flex;
        align-items: center;
        gap: 6px;
        width: 100%;
        justify-content: center;
        padding: 8px 12px;
        border-radius: 10px;
        border: none;
        background: var(--c-text);
        color: var(--c-text-light);
        font-size: 12px;
        font-weight: 700;
        cursor: pointer;
      }
      .ti-share-copy:hover {
        background: #000;
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
        gap: 8px;
        font-size: 15px;
        font-weight: 800;
        letter-spacing: -0.01em;
        color: var(--c-text);
        margin: 0;
      }
      .ti-list-count {
        font-size: 11px;
        font-weight: 700;
        color: var(--c-text-light);
        background: var(--c-accent);
        border-radius: 999px;
        padding: 1px 9px;
      }
      .ti-add-day {
        --boxel-button-border-radius: 999px;
        --boxel-button-border-color: var(--c-text);
        --boxel-button-text-color: var(--c-text);
        font-weight: 700;
      }

      .ti-days {
        display: flex;
        flex-direction: column;
        gap: 18px;
      }
      .ti-day-group {
        display: flex;
        flex-direction: column;
        gap: 6px;
      }
      .ti-day-head {
        display: flex;
        align-items: center;
        gap: 8px;
        width: 100%;
        border: none;
        padding: 6px 2px;
        cursor: pointer;
        text-align: left;
        position: sticky;
        top: 0;
        background: #fff;
        z-index: 2;
        border-radius: 8px;
      }
      .ti-day-head.is-droptarget {
        background: var(--c-accent-bg);
      }
      .ti-day-chevron {
        color: var(--c-muted);
        transition: transform 0.15s ease;
        flex-shrink: 0;
      }
      .ti-day-chevron.is-collapsed {
        transform: rotate(-90deg);
      }
      .ti-day-label {
        font-size: 15px;
        font-weight: 800;
        color: var(--c-text);
        white-space: nowrap;
        letter-spacing: -0.01em;
      }
      .ti-day-count {
        font-size: 11px;
        font-weight: 700;
        color: var(--c-muted);
        background: var(--c-bg);
        border-radius: 999px;
        padding: 1px 8px;
      }
      .ti-day-rule {
        flex: 1;
        height: 1px;
        background: var(--c-border-light);
      }

      .ti-stops {
        position: relative;
        list-style: none;
        margin: 0;
        padding: 2px 0;
        display: flex;
        flex-direction: column;
        gap: 6px;
      }
      .ti-stop {
        --stop-color: var(--c-accent);
        position: relative;
        display: flex;
        align-items: center;
        gap: 2px;
        background: #fff;
        border: 1px solid var(--c-border-light);
        border-radius: 14px;
        box-shadow: 0 1px 2px rgba(0, 0, 0, 0.04);
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
        box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1);
        border-color: var(--c-border);
      }
      .ti-stop.is-sel {
        border-color: var(--stop-color);
        box-shadow: 0 0 0 2px
          color-mix(in srgb, var(--stop-color) 30%, transparent);
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
        padding-left: 7px;
        color: var(--c-border);
        cursor: grab;
        flex-shrink: 0;
      }
      .ti-stop:hover .ti-grip {
        color: var(--c-muted);
      }
      .ti-stop-row {
        flex: 1;
        display: flex;
        align-items: center;
        gap: 9px;
        background: transparent;
        border: none;
        padding: 11px 4px 11px 6px;
        cursor: pointer;
        text-align: left;
        min-width: 0;
      }
      .ti-stop-dot {
        width: 10px;
        height: 10px;
        border-radius: 50%;
        background: var(--stop-color);
        flex-shrink: 0;
      }
      .ti-stop-time {
        font-size: 12px;
        font-weight: 700;
        color: var(--stop-color);
        font-variant-numeric: tabular-nums;
        flex-shrink: 0;
      }
      .ti-stop-name {
        font-size: 14px;
        font-weight: 500;
        color: var(--c-text);
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .ti-icon-btn {
        background: transparent;
        border: none;
        padding: 8px 10px;
        cursor: pointer;
        color: var(--c-muted);
        border-radius: 8px;
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
        color: var(--c-accent);
        background: var(--c-accent-bg);
      }
      .ti-icon-btn.is-editing {
        opacity: 1;
        color: var(--c-accent);
        background: var(--c-accent-bg);
      }
      .ti-icon-btn.ti-danger:hover {
        color: #ef4444;
        background: #fee2e2;
      }
      .ti-add-stop {
        align-self: flex-start;
        margin-left: 8px;
        background: transparent;
        border: none;
        padding: 4px 2px;
        cursor: pointer;
        font-size: 13px;
        font-weight: 700;
        color: var(--c-accent);
      }
      .ti-add-stop:hover {
        color: var(--c-accent-dark);
        text-decoration: underline;
      }

      .ti-empty {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 8px;
        text-align: center;
        color: var(--c-muted);
        padding: 40px 16px;
        border: 1px dashed var(--c-border);
        border-radius: 16px;
      }
      .ti-empty-title {
        font-size: 16px;
        font-weight: 800;
        color: var(--c-text);
        margin: 0;
      }
      .ti-empty-hint {
        font-size: 13px;
        margin: 0;
        line-height: 1.5;
      }
      .ti-empty-btn {
        --boxel-button-color: var(--c-accent);
        --boxel-button-text-color: var(--c-text-light);
        --boxel-button-border-color: var(--c-accent);
        --boxel-button-border-radius: 10px;
        margin-top: 4px;
        font-weight: 700;
      }

      /* Right-side edit panel (slides in) */
      .ti-edit-panel {
        width: 360px;
        flex-shrink: 0;
        display: flex;
        flex-direction: column;
        background: #fff;
        border-left: 1px solid var(--c-border-light);
        box-shadow: -8px 0 24px rgba(0, 0, 0, 0.08);
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
        padding: 16px 20px;
        border-bottom: 1px solid var(--c-border-light);
      }
      .ti-editor-heading {
        display: flex;
        align-items: center;
        gap: 8px;
      }
      .ti-editor-title {
        font-size: 15px;
        font-weight: 800;
        letter-spacing: -0.01em;
        color: var(--c-text);
        margin: 0;
      }
      .ti-editor-day {
        font-size: 11px;
        font-weight: 700;
        color: var(--c-text-light);
        background: var(--c-accent);
        border-radius: 999px;
        padding: 2px 9px;
      }
      .ti-editor-close {
        display: flex;
        align-items: center;
        justify-content: center;
        width: 32px;
        height: 32px;
        border-radius: 50%;
        border: none;
        background: transparent;
        color: var(--c-text);
        cursor: pointer;
        transition: background 0.12s ease;
      }
      .ti-editor-close:hover {
        background: var(--c-bg);
      }
      .ti-editor-body {
        flex: 1;
        min-height: 0;
        overflow-y: auto;
        padding: 20px;
      }

      .ti-map {
        flex: 1;
        min-width: 0;
        display: flex;
        position: relative;
      }
      .ti-map-filter {
        position: absolute;
        top: 14px;
        left: 50%;
        transform: translateX(-50%);
        z-index: 1000;
        display: flex;
        gap: 4px;
        max-width: calc(100% - 28px);
        overflow-x: auto;
        padding: 5px;
        background: #fff;
        border-radius: 999px;
        box-shadow: 0 2px 12px rgba(0, 0, 0, 0.18);
      }
      .ti-chip {
        flex-shrink: 0;
        border: none;
        background: transparent;
        color: var(--c-text);
        font-size: 12px;
        font-weight: 700;
        padding: 6px 14px;
        border-radius: 999px;
        cursor: pointer;
        white-space: nowrap;
        transition:
          background 0.12s ease,
          color 0.12s ease;
      }
      .ti-chip:hover {
        background: var(--c-bg);
      }
      .ti-chip.is-active {
        background: var(--c-text);
        color: var(--c-text-light);
      }
      .ti-map-empty {
        flex: 1;
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 8px;
        color: var(--c-muted);
        text-align: center;
        padding: var(--boxel-sp);
        background: var(--c-bg);
      }
      .ti-map-empty p {
        margin: 0;
        font-size: 14px;
        max-width: 28ch;
      }
    </style>
  </template>
}

export class TravelItineraryFitted extends Component<typeof TravelItinerary> {
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
    <div class='fitted-trip'>
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
      .fitted-trip {
        /* See TravelItineraryIsolated above for the Airbnb-first --ti-* / literal palette. */
        --c-accent: var(--ti-accent, #ff385c);
        --c-accent-dark: var(--ti-accent-dark, #bd1e59);
        --c-accent-bg: var(
          --ti-accent-bg,
          color-mix(in srgb, var(--c-accent) 10%, #ffffff)
        );
        --c-text: var(--ti-text, #222222);
        --c-text-light: var(--ti-text-light, #ffffff);
        --c-muted: var(--ti-muted, #717171);
        --c-bg: var(--ti-bg, #f7f7f7);
        width: 100%;
        height: 100%;
        font-family:
          -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica,
          Arial, sans-serif;
        color: var(--c-text);
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
        border-radius: 9px;
        background: var(--c-accent);
        color: var(--c-text-light);
        width: 28px;
        height: 28px;
      }
      .ft-icon-lg {
        width: 40px;
        height: 40px;
        border-radius: 12px;
      }
      .ft-title {
        font-weight: 800;
        letter-spacing: -0.01em;
        color: var(--c-text);
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        margin: 0;
      }
      .ft-meta {
        font-size: 12px;
        font-weight: 600;
        color: var(--c-muted);
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
          gap: 6px;
        }
        .badge .ft-title {
          font-size: 13px;
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
          gap: 10px;
        }
        .strip .ft-title {
          font-size: 14px;
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
          gap: 10px;
          padding: 12px 14px;
          background: linear-gradient(
            135deg,
            var(--c-accent) 0%,
            var(--c-accent-dark) 100%
          );
          color: var(--c-text-light);
        }
        .t-hero-icon {
          width: 34px;
          height: 34px;
          border-radius: 10px;
          background: rgba(255, 255, 255, 0.22);
          color: var(--c-text-light);
        }
        .t-head-text {
          display: flex;
          flex-direction: column;
          gap: 1px;
          min-width: 0;
        }
        .tile .ft-title {
          font-size: 15px;
          color: var(--c-text-light);
          white-space: normal;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
        }
        .t-sub {
          font-size: 11px;
          font-weight: 600;
          color: rgba(255, 255, 255, 0.85);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .t-meta-row {
          flex-shrink: 0;
          padding: 9px 14px 5px;
          font-size: 10px;
          font-weight: 800;
          text-transform: uppercase;
          letter-spacing: 0.05em;
          color: var(--c-muted);
        }
        .t-days {
          flex: 1;
          min-height: 0;
          display: flex;
          flex-direction: column;
          gap: 6px;
          padding: 3px 12px 12px;
          overflow: hidden;
        }
        .t-day {
          display: flex;
          align-items: center;
          gap: 8px;
          min-width: 0;
        }
        .t-day-badge {
          flex-shrink: 0;
          font-size: 10px;
          font-weight: 800;
          color: var(--c-accent);
          background: var(--c-accent-bg);
          border-radius: 999px;
          padding: 2px 9px;
        }
        .t-day-preview {
          font-size: 12px;
          color: var(--c-muted);
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
          gap: 14px;
          padding: 18px 20px;
          background: linear-gradient(
            135deg,
            var(--c-accent) 0%,
            var(--c-accent-dark) 100%
          );
          color: var(--c-text-light);
        }
        .c-hero-icon {
          background: rgba(255, 255, 255, 0.22);
          color: var(--c-text-light);
        }
        .c-head-text {
          flex: 1;
          display: flex;
          flex-direction: column;
          gap: 2px;
          min-width: 0;
        }
        .c-hero-title {
          font-size: 19px;
          font-weight: 800;
          letter-spacing: -0.01em;
          color: var(--c-text-light);
          margin: 0;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
          overflow: hidden;
        }
        .c-hero-sub {
          font-size: 13px;
          font-weight: 600;
          color: rgba(255, 255, 255, 0.92);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .c-hero-meta {
          font-size: 12px;
          font-weight: 600;
          color: rgba(255, 255, 255, 0.78);
          margin-top: 2px;
        }
        .c-qr {
          flex-shrink: 0;
          display: flex;
          flex-direction: column;
          align-items: center;
          gap: 5px;
        }
        .c-qr-svg {
          width: 66px;
          height: 66px;
          padding: 6px;
          background: var(--c-text-light);
          border-radius: 10px;
          box-shadow: 0 4px 12px rgba(0, 0, 0, 0.18);
        }
        .c-qr-cap {
          font-size: 9px;
          font-weight: 800;
          text-transform: uppercase;
          letter-spacing: 0.06em;
          color: rgba(255, 255, 255, 0.95);
        }
        .c-content {
          flex: 1;
          min-height: 0;
          display: flex;
          flex-direction: column;
          gap: 12px;
          padding: 16px 20px;
          overflow: hidden;
        }
        .c-days {
          flex: 1;
          min-height: 0;
          display: flex;
          flex-direction: column;
          gap: 8px;
          overflow: hidden;
        }
        .c-day {
          display: flex;
          align-items: flex-start;
          gap: 10px;
          padding: 9px 12px;
          background: var(--c-bg);
          border-radius: 12px;
        }
        .c-day-badge {
          flex-shrink: 0;
          font-size: 11px;
          font-weight: 800;
          color: var(--c-text-light);
          background: var(--c-accent);
          border-radius: 999px;
          padding: 3px 10px;
        }
        .c-day-text {
          display: flex;
          flex-direction: column;
          gap: 1px;
          min-width: 0;
        }
        .c-day-count {
          font-size: 12px;
          font-weight: 700;
          color: var(--c-text);
        }
        .c-day-preview {
          font-size: 12px;
          color: var(--c-muted);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      }
    </style>
  </template>
}
