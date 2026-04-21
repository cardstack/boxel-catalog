// ═══ [EDIT TRACKING: ON] Mark all changes with ⁿ ═══
import { CardDef, field, contains, Component } from 'https://cardstack.com/base/card-api'; // ¹
import StringField from 'https://cardstack.com/base/string'; // ²
import DatetimeField from 'https://cardstack.com/base/datetime'; // ³
import TextAreaField from 'https://cardstack.com/base/text-area'; // ⁴
import CalendarIcon from '@cardstack/boxel-icons/calendar'; // ⁵

export class CalendarEvent extends CardDef { // ⁶
  static displayName = 'Calendar Event';
  static icon = CalendarIcon;

  @field eventTitle = contains(StringField); // ⁷
  @field startTime = contains(DatetimeField); // ⁸
  @field endTime = contains(DatetimeField); // ⁹
  @field location = contains(StringField); // ¹⁰
  @field notes = contains(TextAreaField); // ¹¹
  @field color = contains(StringField); // ¹² Event color tag

  @field cardTitle = contains(StringField, { // ¹³
    computeVia: function (this: CalendarEvent) {
      return this.eventTitle ?? 'Untitled Event';
    },
  });

  // ¹⁴ Isolated format - full event details
  static isolated = class Isolated extends Component<typeof CalendarEvent> {
    get formattedDate() {
      try {
        if (!this.args.model?.startTime) return 'Date not set';
        const date = new Date(this.args.model.startTime);
        return date.toLocaleDateString('en-US', {
          weekday: 'long',
          year: 'numeric',
          month: 'long',
          day: 'numeric',
        });
      } catch {
        return 'Invalid date';
      }
    }

    get formattedTime() {
      try {
        if (!this.args.model?.startTime) return '';
        const start = new Date(this.args.model.startTime);
        const startStr = start.toLocaleTimeString('en-US', {
          hour: 'numeric',
          minute: '2-digit',
        });

        if (this.args.model?.endTime) {
          const end = new Date(this.args.model.endTime);
          const endStr = end.toLocaleTimeString('en-US', {
            hour: 'numeric',
            minute: '2-digit',
          });
          return `${startStr} - ${endStr}`;
        }
        return startStr;
      } catch {
        return '';
      }
    }

    get eventColor() {
      return this.args.model?.color || 'var(--primary)';
    }

    <template>
      <article class="event-isolated">
        <div class="color-bar" style="background: {{this.eventColor}};"></div>
        <div class="event-content">
          <h1 class="event-title">{{if @model.eventTitle @model.eventTitle "Untitled Event"}}</h1>

          <div class="event-meta">
            <div class="meta-item">
              <svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <rect x="3" y="4" width="18" height="18" rx="2" ry="2"/>
                <line x1="16" y1="2" x2="16" y2="6"/>
                <line x1="8" y1="2" x2="8" y2="6"/>
                <line x1="3" y1="10" x2="21" y2="10"/>
              </svg>
              <span>{{this.formattedDate}}</span>
            </div>

            {{#if this.formattedTime}}
              <div class="meta-item">
                <svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                  <circle cx="12" cy="12" r="10"/>
                  <polyline points="12,6 12,12 16,14"/>
                </svg>
                <span>{{this.formattedTime}}</span>
              </div>
            {{/if}}

            {{#if @model.location}}
              <div class="meta-item">
                <svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                  <path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z"/>
                  <circle cx="12" cy="10" r="3"/>
                </svg>
                <span><@fields.location /></span>
              </div>
            {{/if}}
          </div>

          {{#if @model.notes}}
            <div class="event-notes">
              <h3>Notes</h3>
              <@fields.notes />
            </div>
          {{/if}}
        </div>
      </article>

      <style scoped>
        .event-isolated {
          display: flex;
          min-height: 100%;
          background: var(--card, #fff);
          color: var(--card-foreground, #1a1a1a);
          font-family: var(--font-sans, 'Inter', -apple-system, sans-serif);
        }

        .color-bar {
          width: 6px;
          flex-shrink: 0;
        }

        .event-content {
          flex: 1;
          padding: var(--boxel-sp-lg, 1.5rem);
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp, 1rem);
        }

        .event-title {
          font-size: var(--boxel-font-size-xl, 1.5rem);
          font-weight: 600;
          margin: 0;
          color: var(--foreground, #1a1a1a);
        }

        .event-meta {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-xs, 0.5rem);
        }

        .meta-item {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs, 0.5rem);
          color: var(--muted-foreground, #6b7280);
          font-size: var(--boxel-font-size-sm, 0.875rem);
        }

        .icon {
          width: 1rem;
          height: 1rem;
          flex-shrink: 0;
        }

        .event-notes {
          margin-top: var(--boxel-sp, 1rem);
          padding-top: var(--boxel-sp, 1rem);
          border-top: 1px solid var(--border, #e5e5e5);
        }

        .event-notes h3 {
          font-size: var(--boxel-font-size-sm, 0.875rem);
          font-weight: 600;
          margin: 0 0 var(--boxel-sp-xs, 0.5rem) 0;
          color: var(--muted-foreground, #6b7280);
          text-transform: uppercase;
          letter-spacing: 0.05em;
        }
      </style>
    </template>
  };

  // ¹⁵ Embedded format - compact event card
  static embedded = class Embedded extends Component<typeof CalendarEvent> {
    get formattedTime() {
      try {
        if (!this.args.model?.startTime) return '';
        const start = new Date(this.args.model.startTime);
        return start.toLocaleTimeString('en-US', {
          hour: 'numeric',
          minute: '2-digit',
        });
      } catch {
        return '';
      }
    }

    get eventColor() {
      return this.args.model?.color || 'var(--primary)';
    }

    <template>
      <div class="event-embedded">
        <div class="color-dot" style="background: {{this.eventColor}};"></div>
        <div class="event-info">
          <span class="event-title">{{if @model.eventTitle @model.eventTitle "Untitled"}}</span>
          {{#if this.formattedTime}}
            <span class="event-time">{{this.formattedTime}}</span>
          {{/if}}
        </div>
      </div>

      <style scoped>
        .event-embedded {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs, 0.5rem);
          padding: var(--boxel-sp-2xs, 0.25rem) var(--boxel-sp-xs, 0.5rem);
          background: var(--card, #fff);
          border-radius: var(--boxel-border-radius-sm, 0.25rem);
          font-family: var(--font-sans, 'Inter', -apple-system, sans-serif);
        }

        .color-dot {
          width: 8px;
          height: 8px;
          border-radius: 50%;
          flex-shrink: 0;
        }

        .event-info {
          display: flex;
          flex-direction: column;
          gap: 2px;
          min-width: 0;
        }

        .event-title {
          font-size: var(--boxel-font-size-sm, 0.875rem);
          font-weight: 500;
          color: var(--foreground, #1a1a1a);
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }

        .event-time {
          font-size: var(--boxel-font-size-xs, 0.75rem);
          color: var(--muted-foreground, #6b7280);
        }
      </style>
    </template>
  };

  // ¹⁶ Fitted format - for calendar grid cells
  static fitted = class Fitted extends Component<typeof CalendarEvent> {
    get eventColor() {
      return this.args.model?.color || 'var(--primary)';
    }

    <template>
      <div class="event-fitted">
        <div class="badge">
          <div class="color-indicator" style="background: {{this.eventColor}};"></div>
          <span class="title">{{if @model.eventTitle @model.eventTitle "Event"}}</span>
        </div>
        <div class="strip">
          <div class="color-indicator" style="background: {{this.eventColor}};"></div>
          <span class="title">{{if @model.eventTitle @model.eventTitle "Event"}}</span>
        </div>
        <div class="tile">
          <div class="color-bar" style="background: {{this.eventColor}};"></div>
          <div class="content">
            <span class="title">{{if @model.eventTitle @model.eventTitle "Event"}}</span>
            {{#if @model.location}}
              <span class="location">{{@model.location}}</span>
            {{/if}}
          </div>
        </div>
        <div class="card">
          <div class="color-bar" style="background: {{this.eventColor}};"></div>
          <div class="content">
            <span class="title">{{if @model.eventTitle @model.eventTitle "Event"}}</span>
            {{#if @model.location}}
              <span class="location">{{@model.location}}</span>
            {{/if}}
            {{#if @model.notes}}
              <p class="notes">{{@model.notes}}</p>
            {{/if}}
          </div>
        </div>
      </div>

      <style scoped>
        .event-fitted {
          container-type: size;
          width: 100%;
          height: 100%;
          font-family: var(--font-sans, 'Inter', -apple-system, sans-serif);
        }

        .badge, .strip, .tile, .card { display: none; }

        /* Badge: tiny */
        @container (max-width: 150px) and (max-height: 169px) {
          .badge {
            display: flex;
            align-items: center;
            gap: 4px;
            padding: 4px;
            height: 100%;
          }
          .badge .color-indicator {
            width: 6px;
            height: 6px;
            border-radius: 50%;
            flex-shrink: 0;
          }
          .badge .title {
            font-size: 0.625rem;
            font-weight: 500;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
            color: var(--foreground, #1a1a1a);
          }
        }

        /* Strip: wide but short */
        @container (min-width: 151px) and (max-height: 169px) {
          .strip {
            display: flex;
            align-items: center;
            gap: 8px;
            padding: 8px;
            height: 100%;
            background: var(--card, #fff);
          }
          .strip .color-indicator {
            width: 8px;
            height: 8px;
            border-radius: 50%;
            flex-shrink: 0;
          }
          .strip .title {
            font-size: 0.75rem;
            font-weight: 500;
            color: var(--foreground, #1a1a1a);
          }
        }

        /* Tile: medium */
        @container (max-width: 399px) and (min-height: 170px) {
          .tile {
            display: flex;
            height: 100%;
            background: var(--card, #fff);
          }
          .tile .color-bar {
            width: 4px;
            flex-shrink: 0;
          }
          .tile .content {
            padding: 8px;
            display: flex;
            flex-direction: column;
            gap: 4px;
          }
          .tile .title {
            font-size: 0.875rem;
            font-weight: 600;
            color: var(--foreground, #1a1a1a);
          }
          .tile .location {
            font-size: 0.75rem;
            color: var(--muted-foreground, #6b7280);
          }
        }

        /* Card: large */
        @container (min-width: 400px) and (min-height: 170px) {
          .card {
            display: flex;
            height: 100%;
            background: var(--card, #fff);
          }
          .card .color-bar {
            width: 6px;
            flex-shrink: 0;
          }
          .card .content {
            padding: 12px;
            display: flex;
            flex-direction: column;
            gap: 6px;
          }
          .card .title {
            font-size: 1rem;
            font-weight: 600;
            color: var(--foreground, #1a1a1a);
          }
          .card .location {
            font-size: 0.875rem;
            color: var(--muted-foreground, #6b7280);
          }
          .card .notes {
            font-size: 0.875rem;
            color: var(--muted-foreground, #6b7280);
            margin: 0;
            overflow: hidden;
            display: -webkit-box;
            -webkit-line-clamp: 2;
            -webkit-box-orient: vertical;
          }
        }
      </style>
    </template>
  };
}
