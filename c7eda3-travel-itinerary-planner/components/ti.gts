import { cached, tracked } from '@glimmer/tracking';
import { modifier } from 'ember-modifier';
import { on } from '@ember/modifier';
import { array, fn } from '@ember/helper';

import ChevronDownIcon from '@cardstack/boxel-icons/chevron-down';
import CopyIcon from '@cardstack/boxel-icons/copy';
import EyeIcon from '@cardstack/boxel-icons/eye';
import GripIcon from '@cardstack/boxel-icons/grip-vertical';
import MapPinIcon from '@cardstack/boxel-icons/map-pin';
import PencilIcon from '@cardstack/boxel-icons/pencil';
import PlaneIcon from '@cardstack/boxel-icons/plane';
import SendIcon from '@cardstack/boxel-icons/send';
import ShareIcon from '@cardstack/boxel-icons/share-2';
import SparklesIcon from '@cardstack/boxel-icons/sparkles';
import TrashIcon from '@cardstack/boxel-icons/trash';
import XIcon from '@cardstack/boxel-icons/x';

import { TravelPlannerCommand } from '../commands/travel-planner-command';
import { Button, DateRangePicker } from '@cardstack/boxel-ui/components';
import { add, eq, not } from '@cardstack/boxel-ui/helpers';
import { Component, getComponent } from 'https://cardstack.com/base/card-api';
import DateRangeField from 'https://cardstack.com/base/date-range-field';
import TimeField from 'https://cardstack.com/base/time';

import {
  MapRender,
  type Coordinate,
  type Route,
} from '@cardstack/catalog/components/map-render';
import GeoSearchPointField from '@cardstack/catalog/fields/geo-search-point/geo-search-point';

import Popover from '@cardstack/catalog/46f065-popover/popover';

import AiChatPanel from './ti-ai-chat-panel';
import { ItineraryStop } from '../travel-itinerary';
import type { TravelItinerary } from '../travel-itinerary';
import {
  addHours,
  categoryStyle,
  formatShortDate,
  geocodePlannedStops,
  matchCategory,
  parsePlanJson,
  CATEGORY_NAMES,
  TRIP_CATEGORIES,
  OTHER_DESTINATION,
} from '../utils/index';
import type {
  ChatMessage,
  ChipOption,
  PlannedStop,
  PlannerAnswers,
  PlannerStep,
} from '../utils/index';

// Trip-category chips for the vibe step — derived from the fixed category
// enum so the chips, the `category` field options, and the list handed to
// the LLM all stay in lockstep.
const CATEGORY_CHIPS: ChipOption[] = TRIP_CATEGORIES.map((c) => ({
  label: c.label,
  value: c.value,
}));

export class TravelItineraryIsolated extends Component<typeof TravelItinerary> {
  @tracked selectedIndex = -1;
  @tracked editingIndex = -1;
  @tracked collapsedDays: number[] = [];
  @tracked draggingIndex = -1;
  @tracked dragOverIndex = -1;
  @tracked mapDay: number | null = null;
  @tracked showShare = false;
  @tracked copied = false;
  @tracked showAiPlanner = false;
  @tracked aiStatus: 'chat' | 'loading' | 'preview' | 'success' | 'error' =
    'chat';
  @tracked outOfCredits = false;
  @tracked chatMessages: ChatMessage[] = [];
  @tracked plannerStep: PlannerStep = 'destination';
  @tracked chatInput = '';
  @tracked selectedVibes: ChipOption[] = [];
  @tracked pendingStops: ItineraryStop[] | null = null;
  @tracked pendingTitle: string | null = null;
  @tracked expandedStopIndex: number | null = null;
  @tracked wantsCustomDestination = false;
  @tracked reviseInput = '';
  @tracked isEditingCurrentTrip = false;
  // Recap of the just-generated/revised plan, shown as a caption BELOW the
  // preview list (so it's visible without scrolling up to the chat).
  @tracked planRecap: string | null = null;
  // Local edit buffer for the planner's date step — the card's own dateRange
  // is not touched until the plan is applied.
  @tracked plannerDateRange: DateRangeField | null = null;
  initialPlanSignature: string | null = null;
  // Category names the traveller picked in the vibe step; drives the pool of
  // categories the LLM may assign to stops.
  chosenCategories: string[] = [];
  plannerAnswers: PlannerAnswers = {};
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
      // High-contrast violet so the route line stands apart from the
      // green/blue/red stop pins and the map tiles underneath.
      routeColor: '#555555',
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

  // --- One-shot AI planner (chat-style popover) ---
  get planDayCount() {
    return this.tripDays || this.dayCount || 3;
  }

  // The fixed trip-category chips shown in the vibe step.
  get categoryChips(): ChipOption[] {
    return CATEGORY_CHIPS;
  }

  private pushChatMessage(role: 'ai' | 'user', text: string, kind?: 'error') {
    this.chatMessages = [...this.chatMessages, { role, text, kind }];
  }

  toggleAiPlanner = () => {
    this.showAiPlanner = !this.showAiPlanner;
    if (this.showAiPlanner && this.aiStatus !== 'loading') {
      this.startPlannerChat();
    }
  };

  closeAiPlanner = () => {
    this.showAiPlanner = false;
  };

  // Build the planner's local date buffer, seeded from the card's current
  // dates when it already has them. Editing this buffer never touches the
  // card — the dates land on the card only when the plan is applied.
  private seedPlannerDateRange() {
    let start = this.args.model?.dateRange?.start;
    let end = this.args.model?.dateRange?.end;
    this.plannerDateRange = new DateRangeField(
      start && end ? { start, end } : {},
    );
  }

  private startPlannerChat() {
    this.aiStatus = 'chat';
    this.outOfCredits = false;
    this.chatMessages = [];
    this.chatInput = '';
    this.selectedVibes = [];
    this.chosenCategories = [];
    this.pendingStops = null;
    this.pendingTitle = null;
    this.expandedStopIndex = null;
    this.wantsCustomDestination = false;
    this.reviseInput = '';
    this.isEditingCurrentTrip = false;
    this.planRecap = null;
    this.initialPlanSignature = null;
    this.plannerAnswers = {};
    this.seedPlannerDateRange();
    if (this.destinationLabel) {
      this.plannerAnswers.destination = this.destinationLabel;
    }
    if (this.tripDays) {
      this.plannerAnswers.days = this.tripDays;
      let start = this.args.model?.dateRange?.start;
      let end = this.args.model?.dateRange?.end;
      if (start && end) {
        this.plannerAnswers.dates = { start, end };
      }
    }
    // With a trip already on the card, skip the wizard: open straight into
    // an editable CLONE of the current trip plus the AI prompt box. Edits
    // stay local until Apply.
    if (this.stops.length) {
      this.pendingStops = this.buildStops(this.toPlainStops([...this.stops]));
      this.initialPlanSignature = this.planSignature(this.pendingStops);
      this.planRecap =
        "Here's your current trip 👆 Edit any stop directly, or tell me below what you'd like changed — change day 2, fewer stops, a different vibe, add famous cafés…";
      this.isEditingCurrentTrip = true;
      this.aiStatus = 'preview';
      return;
    }
    this.pushChatMessage('ai', "Hi! Let's plan your trip together.");
    this.askNextQuestion();
  }

  // Abandon the current trip in the planner and walk the wizard from the
  // top; the card itself is only replaced if the new plan gets applied.
  startFresh = () => {
    this.pendingStops = null;
    this.pendingTitle = null;
    this.expandedStopIndex = null;
    this.reviseInput = '';
    this.isEditingCurrentTrip = false;
    this.planRecap = null;
    this.initialPlanSignature = null;
    this.wantsCustomDestination = false;
    this.chosenCategories = [];
    this.selectedVibes = [];
    this.plannerAnswers = {};
    this.plannerDateRange = new DateRangeField({});
    this.aiStatus = 'chat';
    this.pushChatMessage(
      'ai',
      "Fresh start it is — let's plan from scratch. Your current trip stays untouched until you apply a new plan.",
    );
    this.askNextQuestion();
  };

  private nextPlannerStep(): PlannerStep {
    if (!this.plannerAnswers.destination) return 'destination';
    if (!this.plannerAnswers.days) return 'days';
    if (!this.plannerAnswers.vibe) return 'vibe';
    return 'ready';
  }

  private askNextQuestion() {
    let step = this.nextPlannerStep();
    this.plannerStep = step;
    let questions: Record<PlannerStep, string> = {
      destination: 'First things first — where do you want to go?',
      days: `When do you plan to be in ${
        this.plannerAnswers.destination ?? 'your destination'
      }? Pick your dates below.`,
      vibe: "Last one — what's the vibe you're after? Pick as many as you like.",
      ready:
        "Perfect, that's everything I need. Hit Generate whenever you're ready ✨",
    };
    this.pushChatMessage('ai', questions[step]);
  }

  get stepChips(): ChipOption[] {
    switch (this.plannerStep) {
      case 'destination':
        // Always lead with suggested picks; "Somewhere else…" reveals the
        // free-text input instead of answering directly.
        return [
          { label: 'Tokyo, Japan 🇯🇵', value: 'Tokyo, Japan' },
          { label: 'Paris, France 🇫🇷', value: 'Paris, France' },
          { label: 'Bali, Indonesia 🇮🇩', value: 'Bali, Indonesia' },
          { label: 'Somewhere else…', value: OTHER_DESTINATION },
        ];
      case 'vibe':
        return CATEGORY_CHIPS;
      default:
        return [];
    }
  }

  get showVibeConfirm() {
    return this.plannerStep === 'vibe' && this.selectedVibes.length > 0;
  }

  // Where the input shows: days is a plain typed answer; destination only
  // after "Somewhere else…"; vibe is pick-only (no inventing new categories);
  // preview accepts free-form revision requests.
  // The single-line input only serves the custom-destination answer; dates
  // use the embedded DateRangeField editor and revisions use the textarea.
  get showChatInput() {
    return (
      this.aiStatus === 'chat' &&
      this.plannerStep === 'destination' &&
      this.wantsCustomDestination
    );
  }

  get chatInputPlaceholder() {
    return 'Type a city or region — e.g. Lisbon, Portugal';
  }

  get showDatePicker() {
    return this.aiStatus === 'chat' && this.plannerStep === 'days';
  }

  get datesChosen() {
    return Boolean(this.plannerDateRange?.start && this.plannerDateRange?.end);
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

  // The planner's date step can't reach before today. The @field dateRange
  // gets this from its `minDate: 'today'` configuration; the planner drives
  // the boxel-ui DateRangePicker directly, so the floor is set here.
  get plannerMinDate(): Date {
    let today = new Date();
    today.setHours(0, 0, 0, 0);
    return today;
  }

  // Current planner selection in the shape DateRangePicker expects.
  get plannerRange(): { start: Date | null; end: Date | null } {
    return {
      start: this.plannerDateRange?.start ?? null,
      end: this.plannerDateRange?.end ?? null,
    };
  }

  onPlannerDateSelect = (selected: { date: { start?: Date; end?: Date } }) => {
    if (!this.plannerDateRange) return;
    // start/end are typed Date but the field accepts undefined at runtime to
    // clear (as the base editor's reset does); cast so partial selections
    // (start picked, end not yet) type-check.
    this.plannerDateRange.start = selected?.date?.start as Date;
    this.plannerDateRange.end = selected?.date?.end as Date;
  };

  confirmDates = () => {
    let start = this.plannerDateRange?.start;
    let end = this.plannerDateRange?.end;
    if (!start || !end) return;
    if (end < start) {
      [start, end] = [end, start];
    }
    let today = new Date();
    today.setHours(0, 0, 0, 0);
    if (end < today) {
      this.pushChatMessage(
        'ai',
        'Those dates are already in the past — pick upcoming dates 🙂',
      );
      return;
    }
    this.plannerAnswers.dates = { start, end };
    this.plannerAnswers.days = Math.min(
      30,
      Math.max(1, Math.round((end.getTime() - start.getTime()) / 86400000) + 1),
    );
    this.pushChatMessage(
      'user',
      `${formatShortDate(start)} – ${formatShortDate(end)}`,
    );
    this.askNextQuestion();
  };

  updateChatInput = (event: Event) => {
    this.chatInput = (event.target as HTMLInputElement).value;
  };

  submitChatInput = (event: Event) => {
    event.preventDefault();
    let text = this.chatInput.trim();
    if (!text) return;
    this.chatInput = '';
    this.applyPlannerAnswer(text, text);
  };

  updateReviseInput = (event: Event) => {
    this.reviseInput = (event.target as HTMLTextAreaElement).value;
  };

  submitRevise = () => {
    let text = this.reviseInput.trim();
    if (!text) return;
    this.reviseInput = '';
    this.revisePlan(text);
  };

  // The vibe step is multi-select: chips toggle, then Continue confirms.
  // Every other step treats a chip tap as the final answer.
  answerChip = (chip: ChipOption) => {
    if (this.plannerStep === 'vibe') {
      this.selectedVibes = this.isChipSelected(chip)
        ? this.selectedVibes.filter((c) => c.value !== chip.value)
        : [...this.selectedVibes, chip];
      return;
    }
    if (
      this.plannerStep === 'destination' &&
      chip.value === OTHER_DESTINATION
    ) {
      this.wantsCustomDestination = true;
      this.pushChatMessage('ai', 'Sure — type your destination below 👇');
      return;
    }
    this.applyPlannerAnswer(chip.label, chip.value);
  };

  isChipSelected = (chip: ChipOption) => {
    return this.selectedVibes.some((c) => c.value === chip.value);
  };

  confirmVibes = () => {
    this.confirmVibeSelection();
  };

  private confirmVibeSelection(extraText?: string) {
    let labels: string[] = [];
    let values: string[] = [];
    for (let chip of this.selectedVibes) {
      labels.push(chip.label);
      values.push(chip.value);
    }
    // Remember the picked categories so the LLM assigns from just these.
    this.chosenCategories = this.selectedVibes.map((c) => c.value);
    if (extraText) {
      labels.push(extraText);
      values.push(extraText);
    }
    if (!labels.length) return;
    this.selectedVibes = [];
    this.applyPlannerAnswer(labels.join(' + '), values.join(', '));
  }

  private applyPlannerAnswer(label: string, value: string) {
    this.pushChatMessage('user', label);
    let step = this.plannerStep;
    if (step === 'destination') {
      // Re-ask on abstract answers — a place needs at least one real word
      // and shouldn't be just a number.
      let cleaned = value.trim();
      if (!/\p{L}{2,}/u.test(cleaned) || /^\d+$/.test(cleaned)) {
        this.pushChatMessage(
          'ai',
          "Hmm, that doesn't look like a place I can plan around — give me a city or region, like 'Tokyo, Japan'.",
        );
        return;
      }
      this.plannerAnswers.destination = cleaned;
      this.wantsCustomDestination = false;
      // The answer stays in planner state only — the card's destination is
      // not touched until the plan is applied.
    } else if (step === 'vibe') {
      this.plannerAnswers.vibe = value;
    }
    this.askNextQuestion();
  }

  // The category pool the LLM may assign from: the traveller's picks, or
  // every category when none were picked.
  private get categoryPool(): string[] {
    return this.chosenCategories.length
      ? this.chosenCategories
      : CATEGORY_NAMES;
  }

  private pushAiError(error: any) {
    console.error('Error planning trip:', error);
    // The realm-server proxy rejects with 403 Forbidden when the user's
    // AI credits are exhausted — that's the only credit signal a card sees.
    if (/forbidden|credit/i.test(error?.message ?? '')) {
      this.outOfCredits = true;
      this.pushChatMessage(
        'ai',
        "I'd love to keep planning, but you're out of AI credits 😔 Top up your plan and come back — your answers are saved on this card.",
        'error',
      );
    } else {
      this.pushChatMessage(
        'ai',
        `Something went wrong while planning: ${
          error?.message ?? 'unknown error'
        } — want to try again?`,
        'error',
      );
    }
    this.aiStatus = 'error';
  }

  private buildPlanUserPrompt(): string | null {
    let destination = this.plannerAnswers.destination ?? this.destinationLabel;
    if (!destination) return null;
    let days = this.plannerAnswers.days ?? this.planDayCount;
    let dates = this.plannerAnswers.dates;
    let categoryNames = this.categoryPool;
    return [
      `Destination: ${destination}`,
      `Trip length: ${days} days`,
      dates
        ? `Travel dates: ${formatShortDate(dates.start)} – ${formatShortDate(
            dates.end,
          )} (plan for the season/weekday context)`
        : '',
      this.plannerAnswers.vibe
        ? `Traveller preferences: ${this.plannerAnswers.vibe}`
        : '',
      categoryNames.length ? `Category list: ${categoryNames.join(', ')}` : '',
    ]
      .filter(Boolean)
      .join('\n');
  }

  private async requestPlan(userPrompt: string) {
    let commandContext = this.args.context?.commandContext;
    if (!commandContext) {
      throw new Error('Switch to Interact mode to plan with AI.');
    }
    let command = new TravelPlannerCommand(commandContext);
    let result = await command.execute({
      userPrompt,
      llmModel: 'anthropic/claude-sonnet-4.6',
    });
    let raw = (result as any)?.output ?? '';
    let planned = parsePlanJson(String(raw));
    if (!planned) {
      throw new Error(
        'Could not read an itinerary from the AI response. Please try again.',
      );
    }
    // The model is unreliable at exact coordinates, so resolve real ones from
    // the place names (its strong suit), disambiguated by the trip destination.
    // Geocoding degrades to the model's own coordinates per-stop on failure, so
    // this never blocks a plan.
    let destination = this.plannerAnswers.destination ?? this.destinationLabel;
    let stops = await geocodePlannedStops(
      planned.stops,
      destination ?? undefined,
    );
    return { ...planned, stops };
  }

  generatePlan = async () => {
    if (this.aiStatus === 'loading') return;
    let basePrompt = this.buildPlanUserPrompt();
    if (!basePrompt) {
      this.pushAiError(new Error('Set a destination first.'));
      return;
    }
    this.aiStatus = 'loading';
    this.outOfCredits = false;
    this.pendingStops = null;
    this.pendingTitle = null;
    this.planRecap = null;
    this.expandedStopIndex = null;
    this.isEditingCurrentTrip = false;
    try {
      let planned = await this.requestPlan(basePrompt);
      this.pendingStops = this.buildStops(planned.stops);
      this.pendingTitle = planned.tripTitle ?? null;
      let planDays = new Set(planned.stops.map((p) => p.day)).size;
      let recap = `Here's what I've planned — ${planned.stops.length} stops across ${planDays} ${
        planDays === 1 ? 'day' : 'days'
      }.`;
      if (planned.summary) recap += ` ${planned.summary}`;
      this.planRecap = `${recap} Happy with it? Tell me any changes below, or apply it.`;
      this.aiStatus = 'preview';
    } catch (error: any) {
      this.pushAiError(error);
    }
  };

  // Free-form revision while previewing: "less packed", "add a famous café",
  // "remove a few stops but keep the museum" — the current pending plan goes
  // back to the LLM with the request and the whole preview is replaced.
  revisePlan = async (feedback: string) => {
    if (this.aiStatus === 'loading' || !this.pendingStops) return;
    let basePrompt = this.buildPlanUserPrompt() ?? '';
    this.pushChatMessage('user', feedback);
    let currentPlan = JSON.stringify({
      stops: this.toPlainStops(this.pendingStops),
    });
    this.aiStatus = 'loading';
    this.expandedStopIndex = null;
    try {
      let planned = await this.requestPlan(
        [
          basePrompt,
          `Current plan JSON:\n${currentPlan}`,
          `Revision request from the traveller: ${feedback}`,
          'Apply the revision request to the current plan — keep everything the traveller did not ask to change — and return the COMPLETE revised itinerary. If the traveller names a category for a specific stop (e.g. "sightseeing for day 2 first stop"), set that stop\'s "category" to exactly that name from the Category list. Make sure EVERY stop has a "category" from the list.',
        ].join('\n'),
      );
      this.pendingStops = this.buildStops(planned.stops);
      if (planned.tripTitle) this.pendingTitle = planned.tripTitle;
      let recap =
        planned.summary ??
        `Updated the plan — ${planned.stops.length} stops now.`;
      this.planRecap = `${recap} Better? You can keep tweaking, or apply it.`;
      this.aiStatus = 'preview';
    } catch (error: any) {
      this.pushAiError(error);
    }
  };

  get pendingPlanByDay() {
    let plan = this.pendingStops ?? [];
    let byDay = new Map<number, { stop: ItineraryStop; index: number }[]>();
    plan.forEach((stop, index) => {
      let day = stop.day ?? 1;
      if (!byDay.has(day)) byDay.set(day, []);
      byDay.get(day)!.push({ stop, index });
    });
    return [...byDay.keys()]
      .sort((a, b) => a - b)
      .map((day) => ({ day, stops: byDay.get(day)! }));
  }

  // Bumps whenever new content lands at the bottom of the panel — a chat
  // message, the preview list, or the recap caption — so it auto-scrolls.
  get scrollKey(): string {
    return `${this.chatMessages.length}-${this.pendingStops?.length ?? 0}-${
      this.planRecap ? 1 : 0
    }-${this.aiStatus}`;
  }

  get userIsTyping() {
    if (this.aiStatus === 'chat') {
      return this.chatInput.trim().length > 0;
    }
    if (this.aiStatus === 'preview') {
      return this.reviseInput.trim().length > 0;
    }
    return false;
  }

  toggleExpandStop = (index: number) => {
    this.expandedStopIndex = this.expandedStopIndex === index ? null : index;
  };

  closeStopPopover = () => {
    this.expandedStopIndex = null;
  };

  // The stop whose edit popover is open (null when none). Drives a single
  // shared <Popover> anchored to the open row's view button.
  get expandedPendingStop(): ItineraryStop | null {
    if (this.expandedStopIndex == null) return null;
    return this.pendingStops?.[this.expandedStopIndex] ?? null;
  }

  // CSS selector for the open row's view button — each row tags its button
  // with data-ti-stop-anchor=<index> so the popover velcros to the right one.
  get stopPopoverAnchor(): string {
    return `[data-ti-stop-anchor='${this.expandedStopIndex}']`;
  }

  removePendingStop = (index: number) => {
    if (!this.pendingStops) return;
    this.expandedStopIndex = null;
    this.pendingStops = this.pendingStops.filter((_, i) => i !== index);
  };

  // Remove whichever stop's edit popover is currently open.
  removeExpandedStop = () => {
    if (this.expandedStopIndex == null) return;
    this.removePendingStop(this.expandedStopIndex);
  };

  // Build real ItineraryStop instances from the LLM's plan so the preview
  // can use each field's own edit component.
  private buildStops(planned: PlannedStop[]): ItineraryStop[] {
    return planned.map(
      (p) =>
        new ItineraryStop({
          day: p.day,
          location: new GeoSearchPointField({
            searchKey: p.name,
            ...(p.lat != null && p.lon != null
              ? { lat: p.lat, lon: p.lon }
              : {}),
          }),
          startTime: new TimeField({ value: p.startTime }),
          endTime: new TimeField({ value: p.endTime }),
          notes: p.notes,
          // Tolerant mapping back to a canonical enum value — handles case,
          // accents, emoji, and common synonyms so near-misses still stick.
          category: matchCategory(p.category),
        }),
    );
  }

  private toPlainStops(stops: ItineraryStop[]): PlannedStop[] {
    return stops.map((s) => ({
      day: s.day ?? 1,
      name: s.location?.searchKey?.trim() || 'Untitled stop',
      lat: s.location?.lat ?? null,
      lon: s.location?.lon ?? null,
      startTime: s.startTime?.value?.trim() || '09:00',
      endTime: s.endTime?.value?.trim() || '11:00',
      notes: s.notes ?? undefined,
      category: s.category?.trim() || undefined,
    }));
  }

  private planSignature(stops: ItineraryStop[]): string {
    return JSON.stringify(this.toPlainStops(stops));
  }

  // Applying is pointless until something differs from the card: a field
  // edit, a removal, or an AI revision all change the signature.
  get applyDisabled() {
    if (!this.isEditingCurrentTrip) return false;
    if (!this.pendingStops) return true;
    return this.planSignature(this.pendingStops) === this.initialPlanSignature;
  }

  // Confirming the preview is the only point the card gets patched: the
  // edited stop instances move onto the card wholesale, category links
  // included.
  applyPendingPlan = () => {
    if (!this.pendingStops) return;
    this.args.model.stops = this.pendingStops;
    // A wizard-built plan also carries the destination + dates the traveller
    // chose in the planner — commit them now. (Editing an existing trip leaves
    // the card's Where/When untouched; those aren't edited in the planner.)
    if (!this.isEditingCurrentTrip) {
      if (this.plannerAnswers.destination) {
        this.args.model.destination = new GeoSearchPointField({
          searchKey: this.plannerAnswers.destination,
        });
      }
      let dates = this.plannerAnswers.dates;
      if (dates?.start && dates?.end) {
        this.args.model.dateRange = new DateRangeField({
          start: dates.start,
          end: dates.end,
        });
      }
    }
    // tripTitle and the card's own name (cardInfo.name) are the same thing —
    // patch both so the card stops reading "Untitled Travel Itinerary".
    if (this.pendingTitle) {
      this.args.model.tripTitle = this.pendingTitle;
      if (this.args.model.cardInfo) {
        this.args.model.cardInfo.name = this.pendingTitle;
      }
    }
    this.selectedIndex = -1;
    this.editingIndex = -1;
    this.mapDay = null;
    this.pendingTitle = null;
    this.expandedStopIndex = null;
    // Keep the chat open for continued planning: re-seed the preview from the
    // just-applied trip so the revise textarea stays available. Nothing more is
    // written to the card until the traveller applies again (Apply stays
    // disabled until the plan actually differs).
    this.pendingStops = this.buildStops(this.toPlainStops([...this.stops]));
    this.initialPlanSignature = this.planSignature(this.pendingStops);
    this.isEditingCurrentTrip = true;
    // Shown as a caption BELOW the preview list, so it stays in view when the
    // panel auto-scrolls to the bottom (a chat message would render above the
    // preview and scroll out of sight).
    this.planRecap =
      '🎉 Done — changes applied! Have an amazing trip ✈️ Want to keep tweaking? Tell me below, or close the chat when you’re done.';
    this.aiStatus = 'preview';
  };

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
          <AiChatPanel
            @open={{this.showAiPlanner}}
            @onToggle={{this.toggleAiPlanner}}
            @onClose={{this.closeAiPlanner}}
            @triggerLabel={{if
              (eq this.aiStatus 'loading')
              'Planning…'
              'Plan with AI'
            }}
            @title='Trip Planner'
            @subtitle='Powered by AI'
            @scrollKey={{this.scrollKey}}
            @isAssistantTyping={{eq this.aiStatus 'loading'}}
            @isUserTyping={{this.userIsTyping}}
          >
            <:messages as |Chat|>
              {{#each this.chatMessages as |m|}}
                <Chat.Message
                  @role={{m.role}}
                  @kind={{m.kind}}
                >{{m.text}}</Chat.Message>
              {{/each}}
              {{#if this.pendingStops}}
                <div class='ti-ai-preview'>
                  {{#each this.pendingPlanByDay as |group|}}
                    <div class='ti-ai-preview-day'>
                      <span class='ti-ai-preview-badge'>Day
                        {{group.day}}</span>
                      <ul class='ti-ai-preview-stops'>
                        {{#each group.stops as |entry|}}
                          <li
                            class='ti-ai-preview-stop
                              {{if
                                (eq entry.index this.expandedStopIndex)
                                "is-open"
                              }}'
                          >
                            <div class='ti-ai-preview-row'>
                              {{#if entry.stop.startTime.value}}
                                <span
                                  class='ti-ai-preview-time'
                                >{{entry.stop.startTime.value}}</span>
                              {{/if}}
                              <span class='ti-ai-preview-name'>{{if
                                  entry.stop.location.searchKey
                                  entry.stop.location.searchKey
                                  'Untitled stop'
                                }}</span>
                              {{#if entry.stop.category}}
                                <span
                                  class='ti-ai-preview-cat'
                                >{{entry.stop.category}}</span>
                              {{/if}}
                              <button
                                type='button'
                                class='ti-ai-preview-view'
                                data-ti-stop-anchor={{entry.index}}
                                data-bx-popover-anchor
                                aria-label='View & edit this stop'
                                {{on
                                  'click'
                                  (fn this.toggleExpandStop entry.index)
                                }}
                              >
                                <EyeIcon width='14' height='14' />
                              </button>
                            </div>
                          </li>
                        {{/each}}
                      </ul>
                    </div>
                  {{/each}}
                </div>
                {{#if this.planRecap}}
                  <Chat.Message @role='ai'>{{this.planRecap}}</Chat.Message>
                {{/if}}
                {{#let this.expandedPendingStop as |expandedStop|}}
                  {{#if expandedStop}}
                    <Popover
                      @anchor={{this.stopPopoverAnchor}}
                      @open={{true}}
                      @kind='edit'
                      @anchoring='beside'
                      @placement='left'
                      @size='spacious'
                      @backdrop='dim'
                      @elevation='floating'
                      @trapFocus={{true}}
                      @keyboardModel='edit'
                      @label='Edit stop'
                    >
                      <:edit>
                        <div class='ti-ai-stop-pop'>
                          <div class='ti-ai-stop-head'>
                            <span class='ti-ai-stop-head-title'>Edit</span>
                            <div class='ti-ai-stop-head-actions'>
                              <button
                                type='button'
                                class='ti-ai-preview-remove'
                                {{on 'click' this.removeExpandedStop}}
                              >
                                <TrashIcon width='12' height='12' />
                                Remove this stop
                              </button>
                              <button
                                type='button'
                                class='ti-ai-stop-close'
                                aria-label='Close'
                                {{on 'click' this.closeStopPopover}}
                              ><XIcon width='15' height='15' /></button>
                            </div>
                          </div>
                          <div class='ti-ai-stop-body'>
                            {{#let (getComponent expandedStop) as |StopEdit|}}
                              <div class='ti-ai-stop-edit'>
                                <StopEdit @format='edit' />
                              </div>
                            {{/let}}
                          </div>
                        </div>
                      </:edit>
                    </Popover>
                  {{/if}}
                {{/let}}
              {{/if}}
              {{#if (eq this.aiStatus 'chat')}}
                {{#if this.showDatePicker}}
                  {{#if this.plannerDateRange}}
                    <div class='ti-ai-daterange'>
                      <DateRangePicker
                        @start={{this.plannerRange.start}}
                        @end={{this.plannerRange.end}}
                        @selected={{this.plannerRange}}
                        @minDate={{this.plannerMinDate}}
                        @onSelect={{this.onPlannerDateSelect}}
                      />
                    </div>
                  {{/if}}
                {{/if}}
              {{/if}}
            </:messages>
            <:footer>
              {{#if (eq this.aiStatus 'chat')}}
                {{#if this.stepChips.length}}
                  <div class='ti-ai-chips'>
                    {{#each this.stepChips as |chip|}}
                      <button
                        type='button'
                        class='ti-ai-chip
                          {{if (this.isChipSelected chip) "is-selected"}}'
                        {{on 'click' (fn this.answerChip chip)}}
                      >{{chip.label}}</button>
                    {{/each}}
                  </div>
                {{/if}}
                {{#if this.showVibeConfirm}}
                  <button
                    type='button'
                    class='ti-ai-chip-confirm'
                    {{on 'click' this.confirmVibes}}
                  >Continue →</button>
                {{/if}}
              {{/if}}
              {{#if this.showChatInput}}
                <form
                  class='ti-ai-inputrow'
                  {{on 'submit' this.submitChatInput}}
                >
                  <input
                    class='ti-ai-input'
                    aria-label='Your answer'
                    placeholder={{this.chatInputPlaceholder}}
                    value={{this.chatInput}}
                    {{on 'input' this.updateChatInput}}
                  />
                  <button
                    type='submit'
                    class='ti-ai-send'
                    aria-label='Send answer'
                    disabled={{not this.chatInput}}
                  ><SendIcon width='14' height='14' /></button>
                </form>
              {{/if}}
              {{#if (eq this.aiStatus 'chat')}}
                {{#if this.showDatePicker}}
                  <button
                    type='button'
                    class='ti-ai-generate'
                    disabled={{not this.datesChosen}}
                    {{on 'click' this.confirmDates}}
                  >Confirm dates →</button>
                {{/if}}
                {{#if (eq this.plannerStep 'ready')}}
                  <button
                    type='button'
                    class='ti-ai-generate'
                    {{on 'click' this.generatePlan}}
                  >
                    <SparklesIcon width='14' height='14' />
                    Generate itinerary
                  </button>
                {{/if}}
              {{else if (eq this.aiStatus 'loading')}}
                <button type='button' class='ti-ai-generate is-busy' disabled>
                  <SparklesIcon width='14' height='14' />
                  Generating…
                </button>
              {{else if (eq this.aiStatus 'preview')}}
                <textarea
                  class='ti-ai-textarea'
                  rows='2'
                  aria-label='Tell the AI what to change'
                  placeholder='Tell me what to change — change day 2, fewer stops, a different vibe, add famous cafés…'
                  value={{this.reviseInput}}
                  {{on 'input' this.updateReviseInput}}
                ></textarea>
                {{#if this.reviseInput}}
                  <button
                    type='button'
                    class='ti-ai-generate'
                    {{on 'click' this.submitRevise}}
                  >
                    <SparklesIcon width='14' height='14' />
                    Revise with AI
                  </button>
                {{else}}
                  <button
                    type='button'
                    class='ti-ai-generate'
                    disabled={{this.applyDisabled}}
                    {{on 'click' this.applyPendingPlan}}
                  >
                    {{if
                      this.isEditingCurrentTrip
                      'Apply changes'
                      'Looks good — add to my trip'
                    }}
                  </button>
                {{/if}}
                {{#if this.isEditingCurrentTrip}}
                  <button
                    type='button'
                    class='ti-ai-chip-confirm is-secondary'
                    {{on 'click' this.startFresh}}
                  >Start fresh</button>
                {{/if}}
              {{else if (eq this.aiStatus 'success')}}
                <button
                  type='button'
                  class='ti-ai-generate'
                  {{on 'click' this.closeAiPlanner}}
                >Done</button>
              {{else if (eq this.aiStatus 'error')}}
                {{#if this.outOfCredits}}
                  <button
                    type='button'
                    class='ti-ai-chip-confirm is-secondary'
                    {{on 'click' this.closeAiPlanner}}
                  >Close</button>
                {{else}}
                  <button
                    type='button'
                    class='ti-ai-generate'
                    {{on 'click' this.generatePlan}}
                  >Try again</button>
                {{/if}}
              {{/if}}
            </:footer>
          </AiChatPanel>
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
        /* Brand palette, resolved theme-first: a public --ti-* override wins,
           else the active design-system theme token (--primary, --foreground,
           …), else the literal brand default. (--accent-dark / --accent-bg have
           no semantic slot, so they theme only via their --ti-* override.) */
        --c-accent: var(--ti-accent, var(--primary, #ff385c));
        --c-accent-dark: var(--ti-accent-dark, #e00b41);
        --c-accent-bg: var(--ti-accent-bg, #fff0f3);
        --c-text: var(--ti-text, var(--foreground, #222222));
        --c-text-light: var(
          --ti-text-light,
          var(--primary-foreground, #ffffff)
        );
        --c-muted: var(--ti-muted, var(--muted-foreground, #717171));
        --c-border: var(--ti-border, var(--border, #dddddd));
        --c-border-light: var(--ti-border-light, var(--border, #ebebeb));
        --c-bg: var(--ti-bg, var(--muted, #f7f7f7));
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
        --c-accent: var(--ti-accent, var(--primary, #ff385c));
        --c-accent-dark: var(--ti-accent-dark, #e00b41);
        --c-accent-bg: var(--ti-accent-bg, #fff0f3);
        --c-text: var(--ti-text, var(--foreground, #222222));
        --c-muted: var(--ti-muted, var(--muted-foreground, #717171));
        --c-border: var(--ti-border, var(--border, #dddddd));
        --c-border-light: var(--ti-border-light, var(--border, #ebebeb));
        --c-bg: var(--ti-bg, var(--muted, #f7f7f7));
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
        --c-accent: var(--ti-accent, var(--primary, #ff385c));
        --c-accent-dark: var(--ti-accent-dark, #e00b41);
        --c-accent-bg: var(--ti-accent-bg, #fff0f3);
        --c-text: var(--ti-text, var(--foreground, #222222));
        --c-text-light: var(
          --ti-text-light,
          var(--primary-foreground, #ffffff)
        );
        --c-muted: var(--ti-muted, var(--muted-foreground, #717171));
        --c-border-light: var(--ti-border-light, var(--border, #ebebeb));
        --c-bg: var(--ti-bg, var(--muted, #f7f7f7));
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
        /* See TravelItineraryIsolated above for the theme-first --ti-* / semantic chain. */
        --c-accent: var(--ti-accent, var(--primary, #ff385c));
        --c-accent-dark: var(--ti-accent-dark, #b8003e);
        --c-accent-bg: var(--ti-accent-bg, #fff0f3);
        --c-text: var(--ti-text, var(--foreground, #222222));
        --c-text-light: var(
          --ti-text-light,
          var(--primary-foreground, #ffffff)
        );
        --c-muted: var(--ti-muted, var(--muted-foreground, #717171));
        --c-bg: var(--ti-bg, var(--muted, #f7f7f7));
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
