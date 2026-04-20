// ═══ [EDIT TRACKING: ON] Mark all changes with ⁿ ═══
import {
  // ¹ Core imports
  CardDef,
  Component,
  field,
  contains,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string'; // ²
import BooleanField from 'https://cardstack.com/base/boolean'; // ³
import DateField from 'https://cardstack.com/base/date'; // ⁴
import TextAreaField from 'https://cardstack.com/base/text-area'; // ⁵
import enumField from 'https://cardstack.com/base/enum'; // ⁶
import { formatDateTime } from '@cardstack/boxel-ui/helpers'; // ⁷
import { eq } from '@cardstack/boxel-ui/helpers'; // ⁸
import CheckSquareIcon from '@cardstack/boxel-icons/square-check'; // ⁹

// ¹⁰ Priority enum field
const PriorityField = enumField(StringField, {
  options: [
    { value: 'low', label: 'Low' },
    { value: 'medium', label: 'Medium' },
    { value: 'high', label: 'High' },
  ],
});

// ¹¹ Status enum field
const StatusField = enumField(StringField, {
  options: [
    { value: 'todo', label: 'To Do' },
    { value: 'in-progress', label: 'In Progress' },
    { value: 'done', label: 'Done' },
  ],
});

export class Todo extends CardDef {
  // ¹²
  static displayName = 'Todo';
  static icon = CheckSquareIcon;

  @field title = contains(StringField); // ¹³
  @field description = contains(TextAreaField); // ¹⁴
  @field status = contains(StatusField); // ¹⁵
  @field priority = contains(PriorityField); // ¹⁶
  @field dueDate = contains(DateField); // ¹⁷
  @field completed = contains(BooleanField); // ¹⁸

  @field cardTitle = contains(StringField, {
    // ¹⁹
    computeVia: function (this: Todo) {
      return this.cardInfo?.name ?? this.title ?? 'Untitled Todo';
    },
  });

  static isolated = class Isolated extends Component<typeof Todo> {
    // ²⁰
    get statusLabel() {
      const s = this.args.model?.status;
      if (s === 'done') return 'Done';
      if (s === 'in-progress') return 'In Progress';
      return 'To Do';
    }

    get priorityLabel() {
      const p = this.args.model?.priority;
      if (p === 'high') return 'High';
      if (p === 'medium') return 'Medium';
      return 'Low';
    }

    get priorityClass() {
      const p = this.args.model?.priority;
      if (p === 'high') return 'priority-high';
      if (p === 'medium') return 'priority-medium';
      return 'priority-low';
    }

    get statusClass() {
      const s = this.args.model?.status;
      if (s === 'done') return 'status-done';
      if (s === 'in-progress') return 'status-in-progress';
      return 'status-todo';
    }

    <template>
      <article class='todo-isolated'>
        <header class='todo-header'>
          <div class='header-top'>
            <span class='badge status-badge {{this.statusClass}}'>
              {{this.statusLabel}}
            </span>
            <span class='badge priority-badge {{this.priorityClass}}'>
              {{this.priorityLabel}}
              Priority
            </span>
          </div>
          <h1 class='todo-title'>
            {{if @model.title @model.title 'Untitled Todo'}}
          </h1>
          {{#if @model.dueDate}}
            <div class='due-date'>
              <svg
                width='14'
                height='14'
                viewBox='0 0 24 24'
                fill='none'
                stroke='currentColor'
                stroke-width='2'
                class='icon'
              >
                <rect x='3' y='4' width='18' height='18' rx='2' ry='2' />
                <line x1='16' y1='2' x2='16' y2='6' />
                <line x1='8' y1='2' x2='8' y2='6' />
                <line x1='3' y1='10' x2='21' y2='10' />
              </svg>
              Due:
              {{formatDateTime @model.dueDate format='MMMM D, YYYY'}}
            </div>
          {{/if}}
        </header>

        <section class='todo-body'>
          {{#if @model.description}}
            <div class='description-section'>
              <h2 class='section-label'>Description</h2>
              <div class='description-text'>
                <@fields.description />
              </div>
            </div>
          {{else}}
            <p class='empty-description'>No description provided.</p>
          {{/if}}
        </section>

        <footer class='todo-footer'>
          <div class='completion-row'>
            {{#if (eq @model.completed true)}}
              <span class='completed-badge'>
                <svg
                  width='14'
                  height='14'
                  viewBox='0 0 24 24'
                  fill='none'
                  stroke='currentColor'
                  stroke-width='2.5'
                >
                  <polyline points='20 6 9 17 4 12' />
                </svg>
                Completed
              </span>
            {{else}}
              <span class='not-completed-badge'>Not yet completed</span>
            {{/if}}
          </div>
        </footer>
      </article>
      <style scoped>
        /* ²¹ Isolated styles */
        .todo-isolated {
          container-type: inline-size;
          height: 100%;
          overflow-y: auto;
          padding: var(--boxel-sp-xl);
          background-color: var(--background);
          color: var(--foreground);
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-lg);
          box-sizing: border-box;
          font-family: var(--font-sans);
        }

        .todo-header {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-sm);
          border-bottom: 1px solid var(--border);
          padding-bottom: var(--boxel-sp-lg);
        }

        .header-top {
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-xs);
          align-items: center;
        }

        .todo-title {
          font-size: var(--boxel-font-size-xl);
          font-weight: 700;
          margin: 0;
          line-height: 1.2;
        }

        .due-date {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-2xs);
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
        }

        .badge {
          display: inline-flex;
          align-items: center;
          gap: 4px;
          padding: 3px 10px;
          border-radius: 999px;
          font-size: var(--boxel-font-size-xs);
          font-weight: 600;
          letter-spacing: 0.03em;
        }

        .status-todo {
          background: #e8f4fd;
          color: #2563eb;
        }
        .status-in-progress {
          background: #fff7ed;
          color: #c2410c;
        }
        .status-done {
          background: #f0fdf4;
          color: #16a34a;
        }

        .priority-high {
          background: #fef2f2;
          color: #dc2626;
        }
        .priority-medium {
          background: #fffbeb;
          color: #d97706;
        }
        .priority-low {
          background: #f0fdf4;
          color: #16a34a;
        }

        .todo-body {
          flex: 1;
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp);
        }

        .section-label {
          font-size: var(--boxel-font-size-xs);
          font-weight: 600;
          text-transform: uppercase;
          letter-spacing: 0.08em;
          color: var(--muted-foreground);
          margin: 0 0 var(--boxel-sp-xs) 0;
        }

        .description-text {
          font-size: var(--boxel-font-size-sm);
          line-height: 1.6;
          color: var(--foreground);
        }

        .empty-description {
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
          font-style: italic;
          margin: 0;
        }

        .todo-footer {
          border-top: 1px solid var(--border);
          padding-top: var(--boxel-sp-sm);
        }

        .completed-badge {
          display: inline-flex;
          align-items: center;
          gap: 6px;
          background: #f0fdf4;
          color: #16a34a;
          padding: 4px 12px;
          border-radius: 999px;
          font-size: var(--boxel-font-size-sm);
          font-weight: 600;
        }

        .not-completed-badge {
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
          font-style: italic;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof Todo> {
    // ²²
    get statusClass() {
      const s = this.args.model?.status;
      if (s === 'done') return 'status-done';
      if (s === 'in-progress') return 'status-in-progress';
      return 'status-todo';
    }

    get statusLabel() {
      const s = this.args.model?.status;
      if (s === 'done') return 'Done';
      if (s === 'in-progress') return 'In Progress';
      return 'To Do';
    }

    get priorityClass() {
      const p = this.args.model?.priority;
      if (p === 'high') return 'priority-high';
      if (p === 'medium') return 'priority-medium';
      return 'priority-low';
    }

    get priorityLabel() {
      const p = this.args.model?.priority;
      if (p === 'high') return 'High';
      if (p === 'medium') return 'Medium';
      return 'Low';
    }

    <template>
      <div class='todo-embedded'>
        <div class='embedded-left'>
          <div class='embedded-title'>
            {{if @model.title @model.title 'Untitled Todo'}}
          </div>
          {{#if @model.dueDate}}
            <div class='embedded-due'>
              Due:
              {{formatDateTime @model.dueDate format='MMM D, YYYY'}}
            </div>
          {{/if}}
        </div>
        <div class='embedded-right'>
          <span class='badge {{this.statusClass}}'>{{this.statusLabel}}</span>
          <span
            class='badge {{this.priorityClass}}'
          >{{this.priorityLabel}}</span>
        </div>
      </div>
      <style scoped>
        /* ²³ Embedded styles */
        .todo-embedded {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: var(--boxel-sp-sm);
          padding: var(--boxel-sp-sm) var(--boxel-sp);
          background-color: var(--card);
          color: var(--card-foreground);
          border: 1px solid var(--border);
          border-radius: var(--boxel-border-radius);
          font-family: var(--font-sans);
        }

        .embedded-left {
          display: flex;
          flex-direction: column;
          gap: 2px;
          min-width: 0;
        }

        .embedded-title {
          font-size: var(--boxel-font-size-sm);
          font-weight: 600;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }

        .embedded-due {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }

        .embedded-right {
          display: flex;
          gap: var(--boxel-sp-xs);
          flex-shrink: 0;
        }

        .badge {
          display: inline-flex;
          align-items: center;
          padding: 2px 8px;
          border-radius: 999px;
          font-size: 11px;
          font-weight: 600;
        }

        .status-todo {
          background: #e8f4fd;
          color: #2563eb;
        }
        .status-in-progress {
          background: #fff7ed;
          color: #c2410c;
        }
        .status-done {
          background: #f0fdf4;
          color: #16a34a;
        }

        .priority-high {
          background: #fef2f2;
          color: #dc2626;
        }
        .priority-medium {
          background: #fffbeb;
          color: #d97706;
        }
        .priority-low {
          background: #f0fdf4;
          color: #16a34a;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof Todo> {
    // ²⁴
    get statusClass() {
      const s = this.args.model?.status;
      if (s === 'done') return 'status-done';
      if (s === 'in-progress') return 'status-in-progress';
      return 'status-todo';
    }

    get statusLabel() {
      const s = this.args.model?.status;
      if (s === 'done') return 'Done';
      if (s === 'in-progress') return 'In Progress';
      return 'To Do';
    }

    get priorityLabel() {
      const p = this.args.model?.priority;
      if (p === 'high') return 'High';
      if (p === 'medium') return 'Medium';
      return 'Low';
    }

    get priorityClass() {
      const p = this.args.model?.priority;
      if (p === 'high') return 'priority-high';
      if (p === 'medium') return 'priority-medium';
      return 'priority-low';
    }

    get priorityDot() {
      const p = this.args.model?.priority;
      if (p === 'high') return '🔴';
      if (p === 'medium') return '🟡';
      return '🟢';
    }

    <template>
      <div class='fitted-root'>
        {{! Badge format }}
        <div class='badge-view'>
          <span class='badge-dot {{this.statusClass}}'></span>
          <span class='badge-title'>{{if
              @model.title
              @model.title
              'Todo'
            }}</span>
        </div>

        {{! Strip format }}
        <div class='strip-view'>
          <span class='strip-title'>{{if
              @model.title
              @model.title
              'Untitled Todo'
            }}</span>
          <span class='pill {{this.statusClass}}'>{{this.statusLabel}}</span>
        </div>

        {{! Tile format }}
        <div class='tile-view'>
          <div class='tile-top'>
            <span class='pill {{this.statusClass}}'>{{this.statusLabel}}</span>
          </div>
          <div class='tile-title'>{{if
              @model.title
              @model.title
              'Untitled Todo'
            }}</div>
          {{#if @model.dueDate}}
            <div class='tile-due'>Due:
              {{formatDateTime @model.dueDate format='MMM D'}}</div>
          {{/if}}
        </div>

        {{! Card format }}
        <div class='card-view'>
          <div class='card-header'>
            <span class='pill {{this.statusClass}}'>{{this.statusLabel}}</span>
            <span class='pill {{this.priorityClass}}'>{{this.priorityLabel}}
              Priority</span>
          </div>
          <div class='card-title'>{{if
              @model.title
              @model.title
              'Untitled Todo'
            }}</div>
          {{#if @model.description}}
            <div class='card-desc'>{{@model.description}}</div>
          {{/if}}
          {{#if @model.dueDate}}
            <div class='card-due'>
              <svg
                width='12'
                height='12'
                viewBox='0 0 24 24'
                fill='none'
                stroke='currentColor'
                stroke-width='2'
              >
                <rect x='3' y='4' width='18' height='18' rx='2' ry='2' />
                <line x1='16' y1='2' x2='16' y2='6' />
                <line x1='8' y1='2' x2='8' y2='6' />
                <line x1='3' y1='10' x2='21' y2='10' />
              </svg>
              Due:
              {{formatDateTime @model.dueDate format='MMM D, YYYY'}}
            </div>
          {{/if}}
        </div>
      </div>
      <style scoped>
        /* ²⁵ Fitted styles — hide all sub-views by default */
        .badge-view,
        .strip-view,
        .tile-view,
        .card-view {
          display: none;
          box-sizing: border-box;
          width: 100%;
          height: 100%;
          padding: clamp(0.25rem, 2cqmin, 0.5rem);
          font-family: var(--font-sans);
          overflow: hidden;
        }

        /* Badge: ≤150px wide AND <170px tall */
        @container fitted-card (max-width: 150px) and (max-height: 169px) {
          .badge-view {
            display: flex;
            align-items: center;
            gap: 4px;
            justify-content: center;
          }

          .badge-dot {
            width: 8px;
            height: 8px;
            border-radius: 50%;
            flex-shrink: 0;
          }

          .status-todo .badge-dot,
          .badge-dot.status-todo {
            background: #2563eb;
          }
          .status-in-progress .badge-dot,
          .badge-dot.status-in-progress {
            background: #c2410c;
          }
          .status-done .badge-dot,
          .badge-dot.status-done {
            background: #16a34a;
          }

          .badge-title {
            font-size: 10px;
            font-weight: 600;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
          }
        }

        /* Strip: >150px wide AND <170px tall */
        @container fitted-card (min-width: 151px) and (max-height: 169px) {
          .strip-view {
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: 8px;
            padding: 0 var(--boxel-sp-sm);
          }

          .strip-title {
            font-size: var(--boxel-font-size-sm);
            font-weight: 600;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
            flex: 1;
          }
        }

        /* Tile: <400px wide AND ≥170px tall */
        @container fitted-card (max-width: 399px) and (min-height: 170px) {
          .tile-view {
            display: flex;
            flex-direction: column;
            gap: var(--boxel-sp-xs);
            padding: var(--boxel-sp-sm);
          }

          .tile-top {
            display: flex;
          }

          .tile-title {
            font-size: var(--boxel-font-size-sm);
            font-weight: 700;
            line-height: 1.3;
            overflow: hidden;
            display: -webkit-box;
            -webkit-line-clamp: 2;
            -webkit-box-orient: vertical;
          }

          .tile-due {
            font-size: 11px;
            color: var(--muted-foreground);
            margin-top: auto;
          }
        }

        /* Card: ≥400px wide AND ≥170px tall */
        @container fitted-card (min-width: 400px) and (min-height: 170px) {
          .card-view {
            display: flex;
            flex-direction: column;
            gap: var(--boxel-sp-xs);
            padding: var(--boxel-sp);
          }

          .card-header {
            display: flex;
            gap: var(--boxel-sp-xs);
            flex-wrap: wrap;
          }

          .card-title {
            font-size: var(--boxel-font-size);
            font-weight: 700;
            line-height: 1.3;
            overflow: hidden;
            display: -webkit-box;
            -webkit-line-clamp: 2;
            -webkit-box-orient: vertical;
          }

          .card-desc {
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
            overflow: hidden;
            display: -webkit-box;
            -webkit-line-clamp: 2;
            -webkit-box-orient: vertical;
            line-height: 1.4;
          }

          .card-due {
            display: flex;
            align-items: center;
            gap: 4px;
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
            margin-top: auto;
          }
        }

        /* Shared pill styles */
        .pill {
          display: inline-flex;
          align-items: center;
          padding: 2px 8px;
          border-radius: 999px;
          font-size: 11px;
          font-weight: 600;
          white-space: nowrap;
        }

        .status-todo {
          background: #e8f4fd;
          color: #2563eb;
        }
        .status-in-progress {
          background: #fff7ed;
          color: #c2410c;
        }
        .status-done {
          background: #f0fdf4;
          color: #16a34a;
        }

        .priority-high {
          background: #fef2f2;
          color: #dc2626;
        }
        .priority-medium {
          background: #fffbeb;
          color: #d97706;
        }
        .priority-low {
          background: #f0fdf4;
          color: #16a34a;
        }
      </style>
    </template>
  };
}
