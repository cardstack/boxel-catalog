import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { cached, tracked } from '@glimmer/tracking';
import { htmlSafe } from '@ember/template';
import { modifier } from 'ember-modifier';
import cssUrl from 'ember-css-url';

import MapPinIcon from '@cardstack/boxel-icons/map-pin';
import PlaneIcon from '@cardstack/boxel-icons/plane';
import SparklesIcon from '@cardstack/boxel-icons/sparkles';
import TrashIcon from '@cardstack/boxel-icons/trash';
import ChevronDownIcon from '@cardstack/boxel-icons/chevron-down';
import CopyIcon from '@cardstack/boxel-icons/copy';
import GripIcon from '@cardstack/boxel-icons/grip-vertical';
import PencilIcon from '@cardstack/boxel-icons/pencil';
import ShareIcon from '@cardstack/boxel-icons/share-2';
import TagIcon from '@cardstack/boxel-icons/tag';
import XIcon from '@cardstack/boxel-icons/x';
import UseAiAssistantCommand from '@cardstack/boxel-host/commands/ai-assistant';
import SetActiveLLMCommand from '@cardstack/boxel-host/commands/set-active-llm';
import { Button } from '@cardstack/boxel-ui/components';
import { add, eq } from '@cardstack/boxel-ui/helpers';
import {
  CardDef,
  Component,
  contains,
  containsMany,
  field,
  FieldDef,
  linksTo,
} from 'https://cardstack.com/base/card-api';
import ColorField from 'https://cardstack.com/base/color';
import DateRangeField from 'https://cardstack.com/base/date-range-field';
import NumberField from 'https://cardstack.com/base/number';
import { Skill } from 'https://cardstack.com/base/skill';
import StringField from 'https://cardstack.com/base/string';
import TextAreaField from 'https://cardstack.com/base/text-area';
import TimeField from 'https://cardstack.com/base/time';

import {
  MapRender,
  type Coordinate,
  type Route,
} from '@cardstack/catalog/components/map-render';
import GeoSearchPointField from '@cardstack/catalog/fields/geo-search-point/geo-search-point';
import QRField from '@cardstack/catalog/fields/qr-code/qr-code';

const DEFAULT_STOP_COLOR = '#ff385c';

function accentStyle(color: string | undefined | null) {
  return htmlSafe(`--stop-color:${color || DEFAULT_STOP_COLOR}`);
}

function addHours(time: string | undefined, hours: number) {
  let [hh, mm] = (time || '09:00').split(':').map(Number);
  let total = Math.min(23 * 60 + 59, (hh || 0) * 60 + (mm || 0) + hours * 60);
  let nh = Math.floor(total / 60);
  let nm = total % 60;
  return `${String(nh).padStart(2, '0')}:${String(nm).padStart(2, '0')}`;
}

export class TripItineraryCategory extends CardDef {
  static displayName = 'Trip Itinerary Category';
  static icon = TagIcon;

  @field name = contains(StringField);
  @field color = contains(ColorField);
  @field title = contains(StringField, {
    computeVia: function (this: TripItineraryCategory) {
      return this.name?.trim() || 'Category';
    },
  });

  static atom = class Atom extends Component<typeof TripItineraryCategory> {
    <template>
      <span class='cat-pill' style={{accentStyle @model.color}}>
        <span class='cat-dot'></span>
        <span class='cat-label'>{{if @model.name @model.name 'Category'}}</span>
      </span>
      <style scoped>
        .cat-pill {
          --cat-color: var(--stop-color, #ff385c);
          display: inline-flex;
          align-items: center;
          gap: 6px;
          max-width: 100%;
          font-size: var(--boxel-font-size-xs, 12px);
          font-weight: 700;
          color: var(--cat-color);
          background: color-mix(in srgb, var(--cat-color) 14%, #fff);
          border-radius: 999px;
          padding: 3px 10px;
        }
        .cat-dot {
          width: 8px;
          height: 8px;
          border-radius: 50%;
          background: var(--cat-color);
          flex-shrink: 0;
        }
        .cat-label {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<
    typeof TripItineraryCategory
  > {
    <template>
      <div class='cat-embedded' style={{accentStyle @model.color}}>
        {{#if @model.cardThumbnailURL}}
          <span
            class='cat-swatch has-img'
            style={{cssUrl 'background-image' @model.cardThumbnailURL}}
            role='img'
            aria-label={{@model.name}}
          ></span>
        {{else}}
          <span class='cat-swatch'><TagIcon width='16' height='16' /></span>
        {{/if}}
        <span class='cat-text'>
          <span class='cat-name'>{{if
              @model.name
              @model.name
              'Untitled category'
            }}</span>
          <span class='cat-sub'>Itinerary category</span>
        </span>
      </div>
      <style scoped>
        .cat-embedded {
          --cat-color: var(--stop-color, #ff385c);
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs, 8px);
          padding: var(--boxel-sp-xs, 8px);
        }
        .cat-swatch {
          width: 32px;
          height: 32px;
          flex-shrink: 0;
          display: flex;
          align-items: center;
          justify-content: center;
          border-radius: 8px;
          background: var(--cat-color);
          color: #fff;
        }
        .cat-swatch.has-img {
          background-size: cover;
          background-position: center;
          background-repeat: no-repeat;
          box-shadow: inset 0 0 0 2px
            color-mix(in srgb, var(--cat-color) 55%, transparent);
        }
        .cat-text {
          display: flex;
          flex-direction: column;
          min-width: 0;
        }
        .cat-name {
          font-size: var(--boxel-font-size-sm, 13px);
          font-weight: 700;
          color: var(--boxel-800, #222);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .cat-sub {
          font-size: var(--boxel-font-size-xs, 11px);
          color: var(--boxel-450, #717171);
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof TripItineraryCategory> {
    <template>
      <div class='cat-fitted' style={{accentStyle @model.color}}>
        <div class='badge'>
          {{#if @model.cardThumbnailURL}}
            <span
              class='cat-thumb sm'
              style={{cssUrl 'background-image' @model.cardThumbnailURL}}
            ></span>
          {{else}}
            <span class='cat-dot'></span>
          {{/if}}
          <span class='cat-name'>{{if
              @model.name
              @model.name
              'Category'
            }}</span>
        </div>
        <div class='strip'>
          {{#if @model.cardThumbnailURL}}
            <span
              class='cat-thumb'
              style={{cssUrl 'background-image' @model.cardThumbnailURL}}
            ></span>
          {{else}}
            <span class='cat-swatch'><TagIcon width='15' height='15' /></span>
          {{/if}}
          <span class='cat-name'>{{if
              @model.name
              @model.name
              'Category'
            }}</span>
        </div>
        <div
          class='tile {{if @model.cardThumbnailURL "has-img"}}'
          style={{if
            @model.cardThumbnailURL
            (cssUrl 'background-image' @model.cardThumbnailURL)
          }}
        >
          {{#unless @model.cardThumbnailURL}}
            <span class='cat-swatch lg'><TagIcon
                width='18'
                height='18'
              /></span>
          {{/unless}}
          <span class='cat-name'>{{if
              @model.name
              @model.name
              'Category'
            }}</span>
          <span class='cat-sub'>Itinerary category</span>
        </div>
        <div
          class='card {{if @model.cardThumbnailURL "has-img"}}'
          style={{if
            @model.cardThumbnailURL
            (cssUrl 'background-image' @model.cardThumbnailURL)
          }}
        >
          {{#unless @model.cardThumbnailURL}}
            <span class='cat-swatch lg'><TagIcon
                width='20'
                height='20'
              /></span>
          {{/unless}}
          <span class='cat-text'>
            <span class='cat-name'>{{if
                @model.name
                @model.name
                'Category'
              }}</span>
            <span class='cat-sub'>Itinerary category</span>
          </span>
        </div>
      </div>
      <style scoped>
        .cat-fitted {
          --cat-color: var(--stop-color, #ff385c);
          width: 100%;
          height: 100%;
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
          font-family: var(--boxel-font-family, sans-serif);
        }
        .cat-dot {
          width: 10px;
          height: 10px;
          border-radius: 50%;
          background: var(--cat-color);
          flex-shrink: 0;
        }
        .cat-swatch {
          flex-shrink: 0;
          display: flex;
          align-items: center;
          justify-content: center;
          border-radius: 7px;
          background: var(--cat-color);
          color: #fff;
          width: 26px;
          height: 26px;
        }
        .cat-swatch.lg {
          width: 34px;
          height: 34px;
          border-radius: 9px;
        }
        .cat-thumb {
          flex-shrink: 0;
          border-radius: 7px;
          background-color: var(--cat-color);
          background-size: cover;
          background-position: center;
          background-repeat: no-repeat;
          width: 26px;
          height: 26px;
          box-shadow: inset 0 0 0 2px
            color-mix(in srgb, var(--cat-color) 55%, transparent);
        }
        .cat-thumb.sm {
          width: 18px;
          height: 18px;
          border-radius: 5px;
        }
        .cat-name {
          font-weight: 800;
          color: var(--boxel-800, #222);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .cat-sub {
          font-size: 11px;
          font-weight: 600;
          color: var(--boxel-450, #717171);
        }
        .cat-text {
          display: flex;
          flex-direction: column;
          gap: 1px;
          min-width: 0;
        }

        @container fitted-card (max-width: 150px) and (max-height: 169px) {
          .badge {
            display: flex;
            flex-direction: row;
            align-items: center;
            gap: 6px;
          }
          .badge .cat-name {
            font-size: 12px;
          }
        }
        @container fitted-card (min-width: 151px) and (max-height: 169px) {
          .strip {
            display: flex;
            flex-direction: row;
            align-items: center;
            gap: 8px;
          }
          .strip .cat-name {
            font-size: 14px;
          }
        }
        @container fitted-card (max-width: 399px) and (min-height: 170px) {
          .tile {
            display: flex;
            flex-direction: column;
            align-items: flex-start;
            justify-content: center;
            gap: 8px;
            background: linear-gradient(
              135deg,
              var(--cat-color) 0%,
              color-mix(in srgb, var(--cat-color) 70%, #000) 100%
            );
          }
          .tile .cat-swatch {
            background: rgba(255, 255, 255, 0.24);
          }
          .tile .cat-name {
            font-size: 17px;
            color: #fff;
          }
          .tile .cat-sub {
            color: rgba(255, 255, 255, 0.85);
          }
          .tile.has-img {
            position: relative;
            justify-content: flex-end;
            padding: clamp(10px, 4cqmin, 18px);
            background-size: cover;
            background-position: center;
            background-repeat: no-repeat;
            border-bottom: 4px solid var(--cat-color);
            overflow: hidden;
          }
          .tile.has-img::before {
            content: '';
            position: absolute;
            inset: 0;
            background: linear-gradient(
              180deg,
              rgba(0, 0, 0, 0.05) 0%,
              rgba(0, 0, 0, 0.65) 100%
            );
          }
          .tile.has-img .cat-name,
          .tile.has-img .cat-sub {
            position: relative;
            z-index: 1;
          }
        }
        @container fitted-card (min-width: 400px) and (min-height: 170px) {
          .card {
            display: flex;
            flex-direction: row;
            align-items: center;
            gap: 14px;
            background: linear-gradient(
              135deg,
              var(--cat-color) 0%,
              color-mix(in srgb, var(--cat-color) 70%, #000) 100%
            );
          }
          .card .cat-swatch {
            background: rgba(255, 255, 255, 0.24);
          }
          .card .cat-name {
            font-size: 20px;
            color: #fff;
          }
          .card .cat-sub {
            color: rgba(255, 255, 255, 0.85);
          }
          .card.has-img {
            position: relative;
            align-items: flex-end;
            padding: clamp(14px, 4cqmin, 22px);
            background-size: cover;
            background-position: center;
            background-repeat: no-repeat;
            border-bottom: 5px solid var(--cat-color);
            overflow: hidden;
          }
          .card.has-img::before {
            content: '';
            position: absolute;
            inset: 0;
            background: linear-gradient(
              180deg,
              rgba(0, 0, 0, 0) 35%,
              rgba(0, 0, 0, 0.7) 100%
            );
          }
          .card.has-img .cat-text {
            position: relative;
            z-index: 1;
          }
        }
      </style>
    </template>
  };

  static isolated = class Isolated extends Component<
    typeof TripItineraryCategory
  > {
    <template>
      <section class='cat-iso' style={{accentStyle @model.color}}>
        <div
          class='cat-hero {{if @model.cardThumbnailURL "has-img"}}'
          style={{if
            @model.cardThumbnailURL
            (cssUrl 'background-image' @model.cardThumbnailURL)
          }}
          role={{if @model.cardThumbnailURL 'img'}}
          aria-label={{if @model.cardThumbnailURL @model.name}}
        >
          {{#unless @model.cardThumbnailURL}}
            <span class='cat-hero-icon'><TagIcon
                width='40'
                height='40'
              /></span>
          {{/unless}}
        </div>
        <div class='cat-iso-body'>
          <span class='cat-eyebrow'>Itinerary Category</span>
          <h1 class='cat-iso-name'>{{if
              @model.name
              @model.name
              'Untitled Category'
            }}</h1>
          {{#if @model.color}}
            <span class='cat-hex'>
              <span class='cat-hex-dot'></span>
              {{@model.color}}
            </span>
          {{/if}}
        </div>
      </section>
      <style scoped>
        .cat-iso {
          --cat-color: var(--stop-color, #ff385c);
          min-height: 100%;
          display: flex;
          flex-direction: column;
          background: #fff;
          font-family: var(--boxel-font-family, sans-serif);
          color: var(--boxel-800, #222);
        }
        .cat-hero {
          height: 160px;
          display: flex;
          align-items: center;
          justify-content: center;
          background: linear-gradient(
            135deg,
            var(--cat-color) 0%,
            color-mix(in srgb, var(--cat-color) 70%, #000) 100%
          );
        }
        .cat-hero.has-img {
          height: 240px;
          background-size: cover;
          background-position: center;
          background-repeat: no-repeat;
          border-bottom: 4px solid var(--cat-color);
        }
        .cat-hero-icon {
          display: flex;
          align-items: center;
          justify-content: center;
          width: 76px;
          height: 76px;
          border-radius: 20px;
          background: rgba(255, 255, 255, 0.22);
          color: #fff;
        }
        .cat-iso-body {
          display: flex;
          flex-direction: column;
          gap: 8px;
          padding: var(--boxel-sp-lg, 24px);
        }
        .cat-eyebrow {
          font-size: 11px;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.08em;
          color: var(--cat-color);
        }
        .cat-iso-name {
          font-size: 28px;
          font-weight: 800;
          letter-spacing: -0.02em;
          margin: 0;
        }
        .cat-hex {
          display: inline-flex;
          align-items: center;
          gap: 8px;
          width: fit-content;
          font-size: 13px;
          font-weight: 600;
          color: var(--boxel-450, #717171);
          font-variant-numeric: tabular-nums;
          text-transform: uppercase;
        }
        .cat-hex-dot {
          width: 14px;
          height: 14px;
          border-radius: 50%;
          background: var(--cat-color);
          border: 1px solid rgba(0, 0, 0, 0.12);
        }
      </style>
    </template>
  };
}

export class ItineraryStop extends FieldDef {
  static displayName = 'Itinerary Stop';

  @field location = contains(GeoSearchPointField, {
    configuration: {
      options: {
        showTopSearchResults: true,
        topSearchResultsLimit: 5,
        showRecentSearches: false,
        placeholder: 'Search for a place…',
        mapHeight: '220px',
      },
    },
  });
  @field day = contains(NumberField);
  @field startTime = contains(TimeField);
  @field endTime = contains(TimeField);
  @field category = linksTo(() => TripItineraryCategory);
  @field notes = contains(TextAreaField);

  static embedded = class Embedded extends Component<typeof ItineraryStop> {
    get timeRange() {
      let start = this.args.model?.startTime?.value?.trim();
      let end = this.args.model?.endTime?.value?.trim();
      if (start && end) return `${start} – ${end}`;
      return start || end || '';
    }

    get locationLabel() {
      let loc = this.args.model?.location;
      if (!loc) return null;
      if (loc.searchKey && loc.searchKey.trim() !== '') return loc.searchKey;
      if (loc.lat != null && loc.lon != null) return `${loc.lat}, ${loc.lon}`;
      return null;
    }

    <template>
      <div class='stop' style={{accentStyle @model.category.color}}>
        <div class='stop-head'>
          <span class='stop-dot'></span>
          <span class='stop-name'>{{if
              this.locationLabel
              this.locationLabel
              'Untitled stop'
            }}</span>
        </div>
        <div class='stop-meta'>
          {{#if @model.day}}
            <span class='stop-day'>Day {{@model.day}}</span>
          {{/if}}
          {{#if this.timeRange}}
            <span class='stop-time'>{{this.timeRange}}</span>
          {{/if}}
          {{#if @model.category}}
            <span class='stop-cat'>{{@model.category.title}}</span>
          {{/if}}
        </div>
        {{#if this.locationLabel}}
          <span class='stop-addr'>{{this.locationLabel}}</span>
        {{/if}}
      </div>
      <style scoped>
        .stop {
          --stop-color: #ff385c;
          display: flex;
          flex-direction: column;
          gap: 4px;
          border-left: 3px solid var(--stop-color);
          padding-left: var(--boxel-sp-xs);
        }
        .stop-head {
          display: flex;
          align-items: center;
          gap: 6px;
        }
        .stop-dot {
          width: 9px;
          height: 9px;
          border-radius: 50%;
          background: var(--stop-color);
          flex-shrink: 0;
        }
        .stop-name {
          font-weight: 600;
          font-size: var(--boxel-font-size-sm);
        }
        .stop-meta {
          display: flex;
          flex-wrap: wrap;
          gap: 6px;
          align-items: center;
        }
        .stop-day,
        .stop-time {
          font-size: var(--boxel-font-size-xs);
          font-weight: 700;
          color: var(--stop-color);
        }
        .stop-cat {
          font-size: var(--boxel-font-size-xs);
          color: #717171;
          text-transform: uppercase;
          letter-spacing: 0.05em;
        }
        .stop-addr {
          font-size: var(--boxel-font-size-xs);
          color: #717171;
        }
      </style>
    </template>
  };
}

class TravelItineraryIsolated extends Component<typeof TravelItinerary> {
  @tracked selectedIndex = -1;
  @tracked editingIndex = -1;
  @tracked isPlanning = false;
  @tracked collapsedDays: number[] = [];
  @tracked draggingIndex = -1;
  @tracked dragOverIndex = -1;
  @tracked mapDay: number | null = null;
  @tracked showShare = false;
  @tracked copied = false;
  roomId: string | null = null;
  _poller: ReturnType<typeof setInterval> | null = null;
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

  willDestroy() {
    super.willDestroy();
    if (this._poller) {
      clearInterval(this._poller);
      this._poller = null;
    }
  }

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
          let start = stop.startTime?.value?.trim();
          let end = stop.endTime?.value?.trim();
          let timeRange =
            start && end ? `${start} – ${end}` : start || end || '';
          let popup = `<strong>${label}</strong>`;
          if (timeRange) popup += `<br>${timeRange}`;
          result.push({
            id: index,
            lat: loc.lat,
            lng: loc.lon,
            address: popup,
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

  setupRoom = async () => {
    let commandContext = this.args.context?.commandContext;
    if (!commandContext) throw new Error('In wrong mode');
    if (!this.args.model.planSkill) throw new Error('No plan skill is linked');
    let useAiAssistantCommand = new UseAiAssistantCommand(commandContext);
    let result = await useAiAssistantCommand.execute({
      roomName: `Trip plan: ${this.destinationLabel ?? 'Trip'}`,
      openRoom: true,
      skillCards: [this.args.model.planSkill],
      attachedCards: [this.args.model as CardDef],
      prompt:
        "Help me plan this trip. You can see my destination, dates, and any stops I've already planned on the card. First check what's already there — if I've already planned some days, tell me what you see and ask whether to replan everything, add more days, or refine what I have. Otherwise just confirm how many days and ask what kind of trip experience I want, then propose the itinerary.",
    });
    this.roomId = result.roomId;
    let setActiveLLMCommand = new SetActiveLLMCommand(commandContext);
    await setActiveLLMCommand.execute({ roomId: this.roomId, mode: 'ask' });
    return this.roomId;
  };

  planWithAi = async () => {
    if (this.isPlanning) return;
    this.isPlanning = true;
    const prevCount = this.stops.length;
    try {
      let commandContext = this.args.context?.commandContext;
      if (!commandContext)
        throw new Error('Switch to Interact Mode to plan with AI');
      await this.setupRoom();
      if (this._poller) clearInterval(this._poller);
      let attempts = 0;
      this._poller = setInterval(() => {
        attempts++;
        if (
          (this.args.model?.stops?.length ?? 0) !== prevCount ||
          attempts > 240
        ) {
          clearInterval(this._poller!);
          this._poller = null;
        }
      }, 500);
    } catch (error) {
      console.error('Error planning trip:', error);
      alert('There was an error planning this trip. Please try again.');
    } finally {
      this.isPlanning = false;
    }
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
                {{on 'click' this.toggleShare}}
              ><ShareIcon width='16' height='16' /></button>
              {{#if this.showShare}}
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
              {{/if}}
            </div>
          {{/if}}
          {{#if @model.planSkill}}
            <Button
              class='ti-ai-btn {{if this.isPlanning "is-loading"}}'
              @kind='primary'
              @size='small'
              @disabled={{this.isPlanning}}
              {{on 'click' this.planWithAi}}
            >
              <SparklesIcon width='15' height='15' />
              {{if this.isPlanning 'Planning…' 'Plan with AI'}}
            </Button>
          {{/if}}
        </div>
      </header>

      <div class='ti-body'>
        <aside class='ti-panel' {{this.registerScroller}}>
          <div class='ti-frame'>
            <label class='ti-frame-field'>
              <span class='ti-frame-label'>Where</span>
              <@fields.destination @format='edit' />
            </label>
            <label class='ti-frame-field'>
              <span class='ti-frame-label'>When</span>
              <@fields.dateRange @format='edit' />
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
                          style={{accentStyle entry.stop.category.color}}
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
              <aside class='ti-edit-panel'>
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
        --c-accent: #ff385c;
        --c-accent-dark: #e00b41;
        --c-accent-bg: #fff0f3;
        --c-text: #222222;
        --c-text-light: #ffffff;
        --c-muted: #717171;
        --c-border: #dddddd;
        --c-border-light: #ebebeb;
        --c-bg: #f7f7f7;
        height: 100%;
        min-height: 100%;
        display: flex;
        flex-direction: column;
        overflow: hidden;
        background: var(--c-bg);
        font-family:
          -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica,
          Arial, sans-serif;
        color: var(--c-text);
      }
      .ti-top {
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
        color: #fff;
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
      .ti-ai-btn {
        --boxel-button-color: var(--c-accent);
        --boxel-button-text-color: var(--c-text-light);
        --boxel-button-border-color: var(--c-accent);
        --boxel-button-border-radius: 10px;
        gap: 6px;
        font-weight: 700;
        white-space: nowrap;
      }
      .ti-ai-btn.is-loading {
        opacity: 0.85;
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
      .ti-share-pop {
        position: absolute;
        top: calc(100% + 10px);
        right: 0;
        z-index: 1200;
        width: 200px;
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 10px;
        padding: 16px;
        background: #fff;
        border: 1px solid var(--c-border-light);
        border-radius: 16px;
        box-shadow: 0 12px 32px rgba(0, 0, 0, 0.16);
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
        color: #fff;
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
        color: #fff;
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
        transition:
          box-shadow 0.15s ease,
          border-color 0.15s ease,
          transform 0.1s ease;
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
        color: var(--c-border);
        display: flex;
        align-items: center;
        justify-content: center;
        flex-shrink: 0;
        opacity: 0;
        transition:
          opacity 0.12s ease,
          color 0.12s ease;
      }
      .ti-stop:hover .ti-icon-btn,
      .ti-stop.is-sel .ti-icon-btn {
        opacity: 1;
      }
      .ti-icon-btn:hover {
        color: var(--c-accent-dark);
      }
      .ti-icon-btn.is-editing {
        opacity: 1;
        color: var(--c-accent);
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
        color: #fff;
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
        color: #fff;
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

class TravelItineraryFitted extends Component<typeof TravelItinerary> {
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
        --c-accent: #ff385c;
        --c-accent-dark: #b8003e;
        --c-accent-bg: #fff0f3;
        --c-text: #222222;
        --c-text-light: #ffffff;
        --c-muted: #717171;
        --c-bg: #f7f7f7;
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

export class TravelItinerary extends CardDef {
  static displayName = 'Travel Itinerary Planner';
  static icon = PlaneIcon;
  static prefersWideFormat = true;

  @field tripTitle = contains(StringField);
  @field destination = contains(GeoSearchPointField, {
    configuration: {
      options: {
        showTopSearchResults: true,
        topSearchResultsLimit: 5,
        showRecentSearches: false,
        placeholder: 'Where to?',
        mapHeight: '200px',
      },
    },
  });
  @field dateRange = contains(DateRangeField);
  @field stops = containsMany(ItineraryStop);
  @field planSkill = linksTo(() => Skill);

  // A QR code for sharing this trip. Not computed — the traveller manually
  // enters the card instance id / URL into the field's `data` in edit mode.
  @field shareTripCode = contains(QRField);

  @field title = contains(StringField, {
    computeVia: function (this: TravelItinerary) {
      return (
        this.tripTitle?.trim() ||
        this.destination?.searchKey?.trim() ||
        'Travel Itinerary Planner'
      );
    },
  });

  static isolated = TravelItineraryIsolated;
  static embedded = TravelItineraryIsolated;
  static fitted = TravelItineraryFitted;
}
