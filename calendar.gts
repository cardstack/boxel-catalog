// ═══ [EDIT TRACKING: ON] Mark all changes with ⁿ ═══
import {
  CardDef,
  field,
  contains,
  linksToMany,
  Component,
} from 'https://cardstack.com/base/card-api'; // ¹
import StringField from 'https://cardstack.com/base/string'; // ²
import NumberField from 'https://cardstack.com/base/number'; // ³
import CalendarIcon from '@cardstack/boxel-icons/calendar'; // ⁴
import { tracked } from '@glimmer/tracking'; // ⁵
import { on } from '@ember/modifier'; // ⁶
import { fn } from '@ember/helper'; // ⁷
import { CalendarEvent } from './calendar-event'; // ⁸
import { Button } from '@cardstack/boxel-ui/components'; // ⁹ For styled buttons

export class Calendar extends CardDef { // ¹⁰
  static displayName = 'Calendar';
  static icon = CalendarIcon;
  static prefersWideFormat = true;

  @field calendarName = contains(StringField);
  @field events = linksToMany(CalendarEvent);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: Calendar) {
      return this.calendarName ?? 'My Calendar';
    },
  });

  // ¹¹ Isolated format with event creation attempt
  static isolated = class Isolated extends Component<typeof Calendar> {
    @tracked currentDate = new Date();
    @tracked selectedDate: Date | null = null;

    // ¹² New: Event creation form state
    @tracked showEventForm = false;
    @tracked newEventTitle = '';
    @tracked newEventTime = '';
    @tracked newEventLocation = '';
    @tracked creationStatus = ''; // To show what happens
    @tracked creationError = '';

    get currentYear() {
      return this.currentDate.getFullYear();
    }

    get currentMonth() {
      return this.currentDate.getMonth();
    }

    get monthName() {
      return this.currentDate.toLocaleDateString('en-US', { month: 'long' });
    }

    get daysInMonth() {
      return new Date(this.currentYear, this.currentMonth + 1, 0).getDate();
    }

    get firstDayOfMonth() {
      return new Date(this.currentYear, this.currentMonth, 1).getDay();
    }

    get calendarDays() {
      const days: Array<{ day: number | null; isToday: boolean; events: typeof this.args.model.events }> = [];
      const today = new Date();

      for (let i = 0; i < this.firstDayOfMonth; i++) {
        days.push({ day: null, isToday: false, events: [] });
      }

      for (let day = 1; day <= this.daysInMonth; day++) {
        const isToday =
          today.getDate() === day &&
          today.getMonth() === this.currentMonth &&
          today.getFullYear() === this.currentYear;

        const dayEvents = this.getEventsForDay(day);
        days.push({ day, isToday, events: dayEvents });
      }

      return days;
    }

    get selectedDateEvents() {
      if (!this.selectedDate) return [];
      const day = this.selectedDate.getDate();
      return this.getEventsForDay(day);
    }

    get selectedDateFormatted() {
      if (!this.selectedDate) return '';
      return this.selectedDate.toLocaleDateString('en-US', {
        weekday: 'long',
        month: 'long',
        day: 'numeric',
      });
    }

    getEventsForDay(day: number) {
      try {
        const events = this.args.model?.events;
        if (!Array.isArray(events)) return [];

        return events.filter((event) => {
          if (!event?.startTime) return false;
          const eventDate = new Date(event.startTime);
          return (
            eventDate.getDate() === day &&
            eventDate.getMonth() === this.currentMonth &&
            eventDate.getFullYear() === this.currentYear
          );
        });
      } catch {
        return [];
      }
    }

    previousMonth = () => {
      this.currentDate = new Date(this.currentYear, this.currentMonth - 1, 1);
      this.selectedDate = null;
    };

    nextMonth = () => {
      this.currentDate = new Date(this.currentYear, this.currentMonth + 1, 1);
      this.selectedDate = null;
    };

    goToToday = () => {
      this.currentDate = new Date();
      this.selectedDate = new Date();
    };

    selectDate = (day: number | null) => {
      if (day) {
        this.selectedDate = new Date(this.currentYear, this.currentMonth, day);
        this.showEventForm = false;
        this.creationStatus = '';
        this.creationError = '';
      }
    };

    isSelected = (day: number) => {
      if (!this.selectedDate) return false;
      return (
        this.selectedDate.getDate() === day &&
        this.selectedDate.getMonth() === this.currentMonth &&
        this.selectedDate.getFullYear() === this.currentYear
      );
    };

    // ¹³ Open event creation form
    openEventForm = () => {
      this.showEventForm = true;
      this.newEventTitle = '';
      this.newEventTime = '09:00';
      this.newEventLocation = '';
      this.creationStatus = '';
      this.creationError = '';
    };

    cancelEventForm = () => {
      this.showEventForm = false;
      this.creationStatus = '';
      this.creationError = '';
    };

    updateTitle = (event: Event) => {
      this.newEventTitle = (event.target as HTMLInputElement).value;
    };

    updateTime = (event: Event) => {
      this.newEventTime = (event.target as HTMLInputElement).value;
    };

    updateLocation = (event: Event) => {
      this.newEventLocation = (event.target as HTMLInputElement).value;
    };

    // ¹⁴ ATTEMPT: Create event - trying multiple approaches
    createEvent = async () => {
      if (!this.selectedDate || !this.newEventTitle.trim()) {
        this.creationError = 'Please enter an event title';
        return;
      }

      this.creationStatus = 'Attempting to create event...';
      this.creationError = '';

      // Build the datetime
      const [hours, minutes] = this.newEventTime.split(':').map(Number);
      const eventDateTime = new Date(this.selectedDate);
      eventDateTime.setHours(hours || 9, minutes || 0, 0, 0);

      // ═══════════════════════════════════════════════════════════════
      // ATTEMPT 1: Check what @context provides
      // ═══════════════════════════════════════════════════════════════
      try {
        const context = this.args.context;
        this.creationStatus = `Context available: ${!!context}`;

        if (context) {
          // Log what methods are available on context
          const contextKeys = Object.keys(context || {});
          this.creationStatus = `Context keys: ${contextKeys.join(', ') || 'none enumerable'}`;

          // Check for common creation patterns
          const possibleMethods = [
            'createCard',
            'saveCard',
            'newCard',
            'addCard',
            'create',
            'commandContext'
          ];

          for (const method of possibleMethods) {
            if (typeof (context as any)[method] === 'function') {
              this.creationStatus = `Found method: ${method}`;
              break;
            }
          }
        }
      } catch (e) {
        this.creationError = `Context check failed: ${e}`;
      }

      // ═══════════════════════════════════════════════════════════════
      // ATTEMPT 2: Try direct array manipulation (expected to fail)
      // ═══════════════════════════════════════════════════════════════
      try {
        const eventData = {
          eventTitle: this.newEventTitle,
          startTime: eventDateTime.toISOString(),
          location: this.newEventLocation || null,
          color: '#3b82f6',
        };

        this.creationStatus = 'Attempting direct array push...';

        // This will likely fail with validation error
        const currentEvents = this.args.model?.events || [];
        (this.args.model as any).events = [...currentEvents, eventData];

        this.creationStatus = 'Direct push succeeded (unexpected!)';
        this.showEventForm = false;
      } catch (e: any) {
        this.creationError = `Direct push failed: ${e?.message || e}`;

        // ═══════════════════════════════════════════════════════════════
        // ATTEMPT 3: Try instantiating CalendarEvent directly
        // ═══════════════════════════════════════════════════════════════
        try {
          this.creationStatus = 'Trying to instantiate CalendarEvent...';

          // Try creating instance - this likely needs owner context
          const newEvent = new (CalendarEvent as any)();
          newEvent.eventTitle = this.newEventTitle;
          newEvent.startTime = eventDateTime;
          newEvent.location = this.newEventLocation;

          const currentEvents = this.args.model?.events || [];
          (this.args.model as any).events = [...currentEvents, newEvent];

          this.creationStatus = 'CalendarEvent instantiation succeeded!';
          this.showEventForm = false;
        } catch (e2: any) {
          this.creationError = `All attempts failed. Last error: ${e2?.message || e2}`;
          this.creationStatus = 'CONCLUSION: Cannot create CardDef instances at runtime without platform API';
        }
      }
    };

    <template>
      <div class="calendar-isolated">
        <header class="calendar-header">
          <h1 class="calendar-title">{{if @model.calendarName @model.calendarName "My Calendar"}}</h1>
          <div class="month-nav">
            <button class="nav-btn" type="button" {{on "click" this.previousMonth}}>
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <polyline points="15,18 9,12 15,6"/>
              </svg>
            </button>
            <div class="current-month">
              <span class="month">{{this.monthName}}</span>
              <span class="year">{{this.currentYear}}</span>
            </div>
            <button class="nav-btn" type="button" {{on "click" this.nextMonth}}>
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <polyline points="9,18 15,12 9,6"/>
              </svg>
            </button>
            <button class="today-btn" type="button" {{on "click" this.goToToday}}>Today</button>
          </div>
        </header>

        <div class="calendar-body">
          <div class="calendar-grid">
            <div class="weekday-header">
              <span>Sun</span>
              <span>Mon</span>
              <span>Tue</span>
              <span>Wed</span>
              <span>Thu</span>
              <span>Fri</span>
              <span>Sat</span>
            </div>
            <div class="days-grid">
              {{#each this.calendarDays as |dayInfo|}}
                {{#if dayInfo.day}}
                  <button
                    class="day-cell {{if dayInfo.isToday 'is-today'}} {{if (this.isSelected dayInfo.day) 'is-selected'}} {{if dayInfo.events.length 'has-events'}}"
                    type="button"
                    {{on "click" (fn this.selectDate dayInfo.day)}}
                  >
                    <span class="day-number">{{dayInfo.day}}</span>
                    {{#if dayInfo.events.length}}
                      <div class="event-dots">
                        {{#each dayInfo.events as |event|}}
                          <span class="dot" style="background: {{if event.color event.color 'var(--primary)'}}"></span>
                        {{/each}}
                      </div>
                    {{/if}}
                  </button>
                {{else}}
                  <div class="day-cell empty"></div>
                {{/if}}
              {{/each}}
            </div>
          </div>

          <aside class="event-panel">
            {{#if this.selectedDate}}
              <div class="panel-header">
                <h2 class="panel-title">{{this.selectedDateFormatted}}</h2>
                {{#unless this.showEventForm}}
                  <Button
                    @kind="primary"
                    @size="small"
                    class="add-event-btn"
                    {{on "click" this.openEventForm}}
                  >
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="btn-icon">
                      <line x1="12" y1="5" x2="12" y2="19"/>
                      <line x1="5" y1="12" x2="19" y2="12"/>
                    </svg>
                    Add Event
                  </Button>
                {{/unless}}
              </div>

              {{!-- ¹⁵ Event Creation Form --}}
              {{#if this.showEventForm}}
                <div class="event-form">
                  <h3 class="form-title">New Event</h3>

                  <div class="form-field">
                    <label for="event-title">Title</label>
                    <input
                      type="text"
                      id="event-title"
                      placeholder="Event title..."
                      value={{this.newEventTitle}}
                      {{on "input" this.updateTitle}}
                    />
                  </div>

                  <div class="form-field">
                    <label for="event-time">Time</label>
                    <input
                      type="time"
                      id="event-time"
                      value={{this.newEventTime}}
                      {{on "input" this.updateTime}}
                    />
                  </div>

                  <div class="form-field">
                    <label for="event-location">Location (optional)</label>
                    <input
                      type="text"
                      id="event-location"
                      placeholder="Location..."
                      value={{this.newEventLocation}}
                      {{on "input" this.updateLocation}}
                    />
                  </div>

                  {{!-- Status/Error Display --}}
                  {{#if this.creationStatus}}
                    <div class="status-message">
                      <strong>Status:</strong> {{this.creationStatus}}
                    </div>
                  {{/if}}

                  {{#if this.creationError}}
                    <div class="error-message">
                      <strong>Error:</strong> {{this.creationError}}
                    </div>
                  {{/if}}

                  <div class="form-actions">
                    <Button
                      @kind="secondary-light"
                      @size="small"
                      {{on "click" this.cancelEventForm}}
                    >
                      Cancel
                    </Button>
                    <Button
                      @kind="primary"
                      @size="small"
                      {{on "click" this.createEvent}}
                    >
                      Create Event
                    </Button>
                  </div>
                </div>
              {{else}}
                {{#if this.selectedDateEvents.length}}
                  <div class="event-list">
                    <@fields.events @format="embedded" />
                  </div>
                {{else}}
                  <p class="no-events">No events scheduled</p>
                {{/if}}
              {{/if}}
            {{else}}
              <div class="panel-placeholder">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
                  <rect x="3" y="4" width="18" height="18" rx="2"/>
                  <line x1="16" y1="2" x2="16" y2="6"/>
                  <line x1="8" y1="2" x2="8" y2="6"/>
                  <line x1="3" y1="10" x2="21" y2="10"/>
                </svg>
                <p>Select a date to view events</p>
              </div>
            {{/if}}
          </aside>
        </div>
      </div>

      <style scoped>
        .calendar-isolated {
          display: flex;
          flex-direction: column;
          height: 100%;
          min-height: 500px;
          background: var(--background, #fafafa);
          color: var(--foreground, #1a1a1a);
          font-family: var(--font-sans, 'Inter', -apple-system, sans-serif);
        }

        .calendar-header {
          display: flex;
          justify-content: space-between;
          align-items: center;
          padding: var(--boxel-sp, 1rem) var(--boxel-sp-lg, 1.5rem);
          background: var(--card, #fff);
          border-bottom: 1px solid var(--border, #e5e5e5);
          flex-wrap: wrap;
          gap: var(--boxel-sp, 1rem);
        }

        .calendar-title {
          font-size: var(--boxel-font-size-lg, 1.25rem);
          font-weight: 600;
          margin: 0;
        }

        .month-nav {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs, 0.5rem);
        }

        .nav-btn {
          display: flex;
          align-items: center;
          justify-content: center;
          width: 32px;
          height: 32px;
          border: 1px solid var(--border, #e5e5e5);
          border-radius: var(--boxel-border-radius-sm, 0.25rem);
          background: var(--card, #fff);
          color: var(--foreground, #1a1a1a);
          cursor: pointer;
          transition: all 0.15s ease;
        }

        .nav-btn:hover {
          background: var(--muted, #f5f5f5);
        }

        .nav-btn svg {
          width: 16px;
          height: 16px;
        }

        .current-month {
          display: flex;
          align-items: baseline;
          gap: var(--boxel-sp-2xs, 0.25rem);
          min-width: 140px;
          justify-content: center;
        }

        .current-month .month {
          font-size: var(--boxel-font-size, 1rem);
          font-weight: 600;
        }

        .current-month .year {
          font-size: var(--boxel-font-size-sm, 0.875rem);
          color: var(--muted-foreground, #6b7280);
        }

        .today-btn {
          padding: var(--boxel-sp-2xs, 0.25rem) var(--boxel-sp-sm, 0.75rem);
          border: 1px solid var(--primary, #3b82f6);
          border-radius: var(--boxel-border-radius-sm, 0.25rem);
          background: transparent;
          color: var(--primary, #3b82f6);
          font-size: var(--boxel-font-size-sm, 0.875rem);
          font-weight: 500;
          cursor: pointer;
          transition: all 0.15s ease;
        }

        .today-btn:hover {
          background: var(--primary, #3b82f6);
          color: var(--primary-foreground, #fff);
        }

        .calendar-body {
          display: grid;
          grid-template-columns: 1fr 320px;
          flex: 1;
          overflow: hidden;
        }

        @media (max-width: 768px) {
          .calendar-body {
            grid-template-columns: 1fr;
            grid-template-rows: 1fr auto;
          }
        }

        .calendar-grid {
          padding: var(--boxel-sp, 1rem);
          display: flex;
          flex-direction: column;
          overflow: auto;
        }

        .weekday-header {
          display: grid;
          grid-template-columns: repeat(7, 1fr);
          gap: 4px;
          margin-bottom: var(--boxel-sp-xs, 0.5rem);
        }

        .weekday-header span {
          text-align: center;
          font-size: var(--boxel-font-size-xs, 0.75rem);
          font-weight: 600;
          color: var(--muted-foreground, #6b7280);
          text-transform: uppercase;
          letter-spacing: 0.05em;
          padding: var(--boxel-sp-2xs, 0.25rem);
        }

        .days-grid {
          display: grid;
          grid-template-columns: repeat(7, 1fr);
          gap: 4px;
          flex: 1;
        }

        .day-cell {
          aspect-ratio: 1;
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          gap: 4px;
          border: 1px solid transparent;
          border-radius: var(--boxel-border-radius-sm, 0.25rem);
          background: var(--card, #fff);
          cursor: pointer;
          transition: all 0.15s ease;
          padding: 4px;
          min-height: 60px;
        }

        .day-cell:hover:not(.empty) {
          border-color: var(--primary, #3b82f6);
        }

        .day-cell.empty {
          background: transparent;
          cursor: default;
        }

        .day-cell.is-today {
          background: var(--primary, #3b82f6);
          color: var(--primary-foreground, #fff);
        }

        .day-cell.is-today .day-number {
          color: var(--primary-foreground, #fff);
        }

        .day-cell.is-selected {
          border-color: var(--primary, #3b82f6);
          box-shadow: 0 0 0 2px var(--primary, #3b82f6);
        }

        .day-number {
          font-size: var(--boxel-font-size-sm, 0.875rem);
          font-weight: 500;
          color: var(--foreground, #1a1a1a);
        }

        .event-dots {
          display: flex;
          gap: 3px;
          flex-wrap: wrap;
          justify-content: center;
          max-width: 100%;
        }

        .dot {
          width: 6px;
          height: 6px;
          border-radius: 50%;
        }

        .event-panel {
          background: var(--card, #fff);
          border-left: 1px solid var(--border, #e5e5e5);
          padding: var(--boxel-sp, 1rem);
          overflow-y: auto;
        }

        @media (max-width: 768px) {
          .event-panel {
            border-left: none;
            border-top: 1px solid var(--border, #e5e5e5);
            max-height: 300px;
          }
        }

        .panel-header {
          display: flex;
          justify-content: space-between;
          align-items: center;
          margin-bottom: var(--boxel-sp, 1rem);
          gap: var(--boxel-sp-xs, 0.5rem);
        }

        .panel-title {
          font-size: var(--boxel-font-size, 1rem);
          font-weight: 600;
          margin: 0;
          color: var(--foreground, #1a1a1a);
        }

        .add-event-btn {
          display: flex;
          align-items: center;
          gap: 4px;
        }

        .btn-icon {
          width: 14px;
          height: 14px;
        }

        /* ¹⁶ Event Form Styles */
        .event-form {
          background: var(--muted, #f5f5f5);
          border-radius: var(--boxel-border-radius, 0.5rem);
          padding: var(--boxel-sp, 1rem);
        }

        .form-title {
          font-size: var(--boxel-font-size-sm, 0.875rem);
          font-weight: 600;
          margin: 0 0 var(--boxel-sp, 1rem) 0;
          color: var(--foreground, #1a1a1a);
        }

        .form-field {
          margin-bottom: var(--boxel-sp-sm, 0.75rem);
        }

        .form-field label {
          display: block;
          font-size: var(--boxel-font-size-xs, 0.75rem);
          font-weight: 500;
          color: var(--muted-foreground, #6b7280);
          margin-bottom: 4px;
        }

        .form-field input {
          width: 100%;
          padding: var(--boxel-sp-xs, 0.5rem);
          border: 1px solid var(--border, #e5e5e5);
          border-radius: var(--boxel-border-radius-sm, 0.25rem);
          font-size: var(--boxel-font-size-sm, 0.875rem);
          background: var(--card, #fff);
          color: var(--foreground, #1a1a1a);
        }

        .form-field input:focus {
          outline: none;
          border-color: var(--primary, #3b82f6);
          box-shadow: 0 0 0 2px rgba(59, 130, 246, 0.2);
        }

        .form-actions {
          display: flex;
          gap: var(--boxel-sp-xs, 0.5rem);
          justify-content: flex-end;
          margin-top: var(--boxel-sp, 1rem);
        }

        .status-message {
          background: var(--secondary, #e0f2fe);
          color: var(--secondary-foreground, #0369a1);
          padding: var(--boxel-sp-xs, 0.5rem);
          border-radius: var(--boxel-border-radius-sm, 0.25rem);
          font-size: var(--boxel-font-size-xs, 0.75rem);
          margin-top: var(--boxel-sp-sm, 0.75rem);
          word-break: break-word;
        }

        .error-message {
          background: #fef2f2;
          color: #dc2626;
          padding: var(--boxel-sp-xs, 0.5rem);
          border-radius: var(--boxel-border-radius-sm, 0.25rem);
          font-size: var(--boxel-font-size-xs, 0.75rem);
          margin-top: var(--boxel-sp-sm, 0.75rem);
          word-break: break-word;
        }

        .event-list {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-xs, 0.5rem);
        }

        .event-list > .linksToMany-field {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-xs, 0.5rem);
        }

        .no-events {
          color: var(--muted-foreground, #6b7280);
          font-size: var(--boxel-font-size-sm, 0.875rem);
          font-style: italic;
        }

        .panel-placeholder {
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          height: 100%;
          color: var(--muted-foreground, #6b7280);
          text-align: center;
          gap: var(--boxel-sp, 1rem);
        }

        .panel-placeholder svg {
          width: 48px;
          height: 48px;
          opacity: 0.5;
        }

        .panel-placeholder p {
          margin: 0;
          font-size: var(--boxel-font-size-sm, 0.875rem);
        }
      </style>
    </template>
  };

  // ¹⁷ Embedded format - compact view
  static embedded = class Embedded extends Component<typeof Calendar> {
    get todayDate() {
      const today = new Date();
      return today.toLocaleDateString('en-US', {
        month: 'short',
        day: 'numeric',
      });
    }

    get upcomingEvents() {
      try {
        const events = this.args.model?.events;
        if (!Array.isArray(events)) return [];

        const now = new Date();
        return events
          .filter((event) => {
            if (!event?.startTime) return false;
            return new Date(event.startTime) >= now;
          })
          .slice(0, 3);
      } catch {
        return [];
      }
    }

    <template>
      <div class="calendar-embedded">
        <div class="header">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <rect x="3" y="4" width="18" height="18" rx="2"/>
            <line x1="16" y1="2" x2="16" y2="6"/>
            <line x1="8" y1="2" x2="8" y2="6"/>
            <line x1="3" y1="10" x2="21" y2="10"/>
          </svg>
          <span class="name">{{if @model.calendarName @model.calendarName "Calendar"}}</span>
        </div>
        <div class="today">{{this.todayDate}}</div>
        {{#if this.upcomingEvents.length}}
          <div class="upcoming">
            {{this.upcomingEvents.length}} upcoming event{{if (this.isPlural this.upcomingEvents.length) "s" ""}}
          </div>
        {{/if}}
      </div>

      <style scoped>
        .calendar-embedded {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-2xs, 0.25rem);
          padding: var(--boxel-sp-sm, 0.75rem);
          background: var(--card, #fff);
          border-radius: var(--boxel-border-radius, 0.5rem);
          font-family: var(--font-sans, 'Inter', -apple-system, sans-serif);
        }

        .header {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs, 0.5rem);
        }

        .header svg {
          width: 16px;
          height: 16px;
          color: var(--primary, #3b82f6);
        }

        .name {
          font-weight: 600;
          font-size: var(--boxel-font-size-sm, 0.875rem);
          color: var(--foreground, #1a1a1a);
        }

        .today {
          font-size: var(--boxel-font-size-lg, 1.25rem);
          font-weight: 700;
          color: var(--foreground, #1a1a1a);
        }

        .upcoming {
          font-size: var(--boxel-font-size-xs, 0.75rem);
          color: var(--muted-foreground, #6b7280);
        }
      </style>
    </template>

    isPlural = (count: number) => count !== 1;
  };

  // ¹⁸ Fitted format
  static fitted = class Fitted extends Component<typeof Calendar> {
    get todayDay() {
      return new Date().getDate();
    }

    get todayMonth() {
      return new Date().toLocaleDateString('en-US', { month: 'short' });
    }

    get eventCount() {
      try {
        return this.args.model?.events?.length ?? 0;
      } catch {
        return 0;
      }
    }

    <template>
      <div class="calendar-fitted">
        <div class="badge">
          <span class="day">{{this.todayDay}}</span>
        </div>
        <div class="strip">
          <div class="date-block">
            <span class="day">{{this.todayDay}}</span>
            <span class="month">{{this.todayMonth}}</span>
          </div>
          <span class="name">{{if @model.calendarName @model.calendarName "Calendar"}}</span>
        </div>
        <div class="tile">
          <div class="date-block">
            <span class="month">{{this.todayMonth}}</span>
            <span class="day">{{this.todayDay}}</span>
          </div>
          <div class="info">
            <span class="name">{{if @model.calendarName @model.calendarName "Calendar"}}</span>
            <span class="count">{{this.eventCount}} events</span>
          </div>
        </div>
        <div class="card">
          <div class="date-block">
            <span class="month">{{this.todayMonth}}</span>
            <span class="day">{{this.todayDay}}</span>
          </div>
          <div class="info">
            <span class="name">{{if @model.calendarName @model.calendarName "Calendar"}}</span>
            <span class="count">{{this.eventCount}} events</span>
          </div>
        </div>
      </div>

      <style scoped>
        .calendar-fitted {
          container-type: size;
          width: 100%;
          height: 100%;
          font-family: var(--font-sans, 'Inter', -apple-system, sans-serif);
        }

        .badge, .strip, .tile, .card { display: none; }

        @container (max-width: 150px) and (max-height: 169px) {
          .badge {
            display: flex;
            align-items: center;
            justify-content: center;
            height: 100%;
            background: var(--primary, #3b82f6);
            color: var(--primary-foreground, #fff);
            border-radius: var(--boxel-border-radius-sm, 0.25rem);
          }
          .badge .day {
            font-size: 1.5rem;
            font-weight: 700;
          }
        }

        @container (min-width: 151px) and (max-height: 169px) {
          .strip {
            display: flex;
            align-items: center;
            gap: var(--boxel-sp-sm, 0.75rem);
            height: 100%;
            padding: var(--boxel-sp-xs, 0.5rem);
            background: var(--card, #fff);
          }
          .strip .date-block {
            display: flex;
            flex-direction: column;
            align-items: center;
            background: var(--primary, #3b82f6);
            color: var(--primary-foreground, #fff);
            padding: 4px 8px;
            border-radius: var(--boxel-border-radius-sm, 0.25rem);
          }
          .strip .day {
            font-size: 1rem;
            font-weight: 700;
            line-height: 1;
          }
          .strip .month {
            font-size: 0.625rem;
            text-transform: uppercase;
          }
          .strip .name {
            font-size: 0.875rem;
            font-weight: 500;
            color: var(--foreground, #1a1a1a);
          }
        }

        @container (max-width: 399px) and (min-height: 170px) {
          .tile {
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            gap: var(--boxel-sp-xs, 0.5rem);
            height: 100%;
            padding: var(--boxel-sp, 1rem);
            background: var(--card, #fff);
          }
          .tile .date-block {
            display: flex;
            flex-direction: column;
            align-items: center;
            background: var(--primary, #3b82f6);
            color: var(--primary-foreground, #fff);
            padding: 8px 16px;
            border-radius: var(--boxel-border-radius, 0.5rem);
          }
          .tile .month {
            font-size: 0.75rem;
            text-transform: uppercase;
          }
          .tile .day {
            font-size: 1.5rem;
            font-weight: 700;
            line-height: 1;
          }
          .tile .info {
            text-align: center;
          }
          .tile .name {
            display: block;
            font-size: 0.875rem;
            font-weight: 600;
            color: var(--foreground, #1a1a1a);
          }
          .tile .count {
            font-size: 0.75rem;
            color: var(--muted-foreground, #6b7280);
          }
        }

        @container (min-width: 400px) and (min-height: 170px) {
          .card {
            display: flex;
            align-items: center;
            gap: var(--boxel-sp, 1rem);
            height: 100%;
            padding: var(--boxel-sp, 1rem);
            background: var(--card, #fff);
          }
          .card .date-block {
            display: flex;
            flex-direction: column;
            align-items: center;
            background: var(--primary, #3b82f6);
            color: var(--primary-foreground, #fff);
            padding: 12px 20px;
            border-radius: var(--boxel-border-radius, 0.5rem);
          }
          .card .month {
            font-size: 0.875rem;
            text-transform: uppercase;
          }
          .card .day {
            font-size: 2rem;
            font-weight: 700;
            line-height: 1;
          }
          .card .info {
            display: flex;
            flex-direction: column;
            gap: 4px;
          }
          .card .name {
            font-size: 1rem;
            font-weight: 600;
            color: var(--foreground, #1a1a1a);
          }
          .card .count {
            font-size: 0.875rem;
            color: var(--muted-foreground, #6b7280);
          }
        }
      </style>
    </template>
  };
}
