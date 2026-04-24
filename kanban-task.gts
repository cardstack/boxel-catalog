// ═══ [EDIT TRACKING: ON] Mark all changes with ⁿ ═══
import { CardDef, field, contains, Component } from 'https://cardstack.com/base/card-api'; // ¹
import StringField from 'https://cardstack.com/base/string'; // ²
import BooleanField from 'https://cardstack.com/base/boolean'; // ³
import CheckIcon from '@cardstack/boxel-icons/check'; // ⁴

export class KanbanTask extends CardDef { // ⁵
  static displayName = 'Kanban Task';
  static icon = CheckIcon;

  @field taskName = contains(StringField); // ⁶
  @field description = contains(StringField); // ⁷
  @field priority = contains(StringField); // ⁸ 'high' | 'medium' | 'low'
  @field assignee = contains(StringField); // ⁹
  @field completed = contains(BooleanField); // ¹⁰

  @field cardTitle = contains(StringField, { // ¹¹
    computeVia: function (this: KanbanTask) {
      return this.taskName ?? 'Untitled Task';
    },
  });

  // ¹² Isolated - full task view
  static isolated = class Isolated extends Component<typeof KanbanTask> {
    get priorityLabel() {
      const p = this.args.model?.priority;
      if (p === 'high') return 'High Priority';
      if (p === 'medium') return 'Medium Priority';
      if (p === 'low') return 'Low Priority';
      return 'No Priority';
    }

    get priorityColor() {
      const p = this.args.model?.priority;
      if (p === 'high') return 'var(--destructive, #dc2626)';
      if (p === 'medium') return 'var(--chart-4, #f59e0b)';
      return 'var(--chart-3, #22c55e)';
    }

    <template>
      <article class="task-isolated">
        <header>
          <div class="priority-badge" style="background: {{this.priorityColor}}">
            {{this.priorityLabel}}
          </div>
          {{#if @model.completed}}
            <span class="completed-badge">Completed</span>
          {{/if}}
        </header>

        <h1 class="task-title">{{if @model.taskName @model.taskName "Untitled Task"}}</h1>

        {{#if @model.description}}
          <p class="description">{{@model.description}}</p>
        {{/if}}

        {{#if @model.assignee}}
          <div class="assignee">
            <span class="label">Assigned to:</span>
            <span class="value">{{@model.assignee}}</span>
          </div>
        {{/if}}
      </article>

      <style scoped>
        .task-isolated {
          padding: var(--boxel-sp-lg, 1.5rem);
          background: var(--card, #fff);
          color: var(--card-foreground, #1a1a1a);
          font-family: var(--font-sans, 'Inter', -apple-system, sans-serif);
        }

        header {
          display: flex;
          gap: var(--boxel-sp-xs, 0.5rem);
          margin-bottom: var(--boxel-sp, 1rem);
        }

        .priority-badge {
          padding: 4px 12px;
          border-radius: var(--boxel-border-radius, 0.5rem);
          font-size: var(--boxel-font-size-xs, 0.75rem);
          font-weight: 600;
          color: white;
          text-transform: uppercase;
        }

        .completed-badge {
          padding: 4px 12px;
          border-radius: var(--boxel-border-radius, 0.5rem);
          font-size: var(--boxel-font-size-xs, 0.75rem);
          font-weight: 600;
          background: var(--primary, #3b82f6);
          color: var(--primary-foreground, #fff);
        }

        .task-title {
          margin: 0 0 var(--boxel-sp, 1rem) 0;
          font-size: var(--boxel-font-size-xl, 1.5rem);
          font-weight: 600;
        }

        .description {
          color: var(--muted-foreground, #6b7280);
          line-height: 1.6;
          margin: 0 0 var(--boxel-sp, 1rem) 0;
        }

        .assignee {
          display: flex;
          gap: var(--boxel-sp-xs, 0.5rem);
        }

        .assignee .label {
          color: var(--muted-foreground, #6b7280);
        }

        .assignee .value {
          font-weight: 500;
        }
      </style>
    </template>
  };

  // ¹³ Embedded - compact task card
  static embedded = class Embedded extends Component<typeof KanbanTask> {
    get priorityColor() {
      const p = this.args.model?.priority;
      if (p === 'high') return 'var(--destructive, #dc2626)';
      if (p === 'medium') return 'var(--chart-4, #f59e0b)';
      return 'var(--chart-3, #22c55e)';
    }

    <template>
      <div class="task-embedded {{if @model.completed 'completed'}}">
        {{#if @model.priority}}
          <div class="priority-dot" style="background: {{this.priorityColor}}"></div>
        {{/if}}
        <div class="task-content">
          <span class="task-name">{{if @model.taskName @model.taskName "Untitled"}}</span>
          {{#if @model.assignee}}
            <span class="assignee">{{@model.assignee}}</span>
          {{/if}}
        </div>
        {{#if @model.completed}}
          <span class="check">✓</span>
        {{/if}}
      </div>

      <style scoped>
        .task-embedded {
          display: flex;
          align-items: flex-start;
          gap: var(--boxel-sp-xs, 0.5rem);
          padding: var(--boxel-sp-sm, 0.75rem);
          background: var(--card, #fff);
          border: 1px solid var(--border, #e5e5e5);
          border-radius: var(--boxel-border-radius, 0.5rem);
          font-family: var(--font-sans, 'Inter', -apple-system, sans-serif);
          transition: all 0.15s ease;
        }

        .task-embedded:hover {
          border-color: var(--primary, #3b82f6);
          box-shadow: var(--shadow-sm, 0 1px 3px rgba(0,0,0,0.1));
        }

        .task-embedded.completed {
          opacity: 0.6;
        }

        .task-embedded.completed .task-name {
          text-decoration: line-through;
        }

        .priority-dot {
          width: 8px;
          height: 8px;
          border-radius: 50%;
          flex-shrink: 0;
          margin-top: 6px;
        }

        .task-content {
          flex: 1;
          min-width: 0;
        }

        .task-name {
          display: block;
          font-size: var(--boxel-font-size-sm, 0.875rem);
          font-weight: 500;
          color: var(--foreground, #1a1a1a);
          line-height: 1.4;
        }

        .assignee {
          display: block;
          font-size: var(--boxel-font-size-xs, 0.75rem);
          color: var(--muted-foreground, #6b7280);
          margin-top: 2px;
        }

        .check {
          color: var(--primary, #3b82f6);
          font-weight: 600;
        }
      </style>
    </template>
  };

  // ¹⁴ Fitted - for grids
  static fitted = class Fitted extends Component<typeof KanbanTask> {
    get priorityColor() {
      const p = this.args.model?.priority;
      if (p === 'high') return 'var(--destructive, #dc2626)';
      if (p === 'medium') return 'var(--chart-4, #f59e0b)';
      return 'var(--chart-3, #22c55e)';
    }

    <template>
      <div class="task-fitted">
        <div class="badge">
          <div class="dot" style="background: {{this.priorityColor}}"></div>
        </div>
        <div class="strip">
          <div class="dot" style="background: {{this.priorityColor}}"></div>
          <span class="name">{{if @model.taskName @model.taskName "Task"}}</span>
        </div>
        <div class="tile">
          <div class="dot" style="background: {{this.priorityColor}}"></div>
          <span class="name">{{if @model.taskName @model.taskName "Task"}}</span>
          {{#if @model.assignee}}
            <span class="assignee">{{@model.assignee}}</span>
          {{/if}}
        </div>
      </div>

      <style scoped>
        .task-fitted {
          container-type: size;
          width: 100%;
          height: 100%;
          font-family: var(--font-sans, 'Inter', -apple-system, sans-serif);
        }

        .badge, .strip, .tile { display: none; }

        .dot {
          width: 8px;
          height: 8px;
          border-radius: 50%;
          flex-shrink: 0;
        }

        @container (max-width: 150px) and (max-height: 169px) {
          .badge {
            display: flex;
            align-items: center;
            justify-content: center;
            height: 100%;
            background: var(--card, #fff);
          }
        }

        @container (min-width: 151px) and (max-height: 169px) {
          .strip {
            display: flex;
            align-items: center;
            gap: 8px;
            height: 100%;
            padding: 8px;
            background: var(--card, #fff);
          }
          .strip .name {
            font-size: 0.75rem;
            font-weight: 500;
          }
        }

        @container (min-height: 170px) {
          .tile {
            display: flex;
            flex-direction: column;
            gap: 4px;
            padding: 12px;
            height: 100%;
            background: var(--card, #fff);
          }
          .tile .name {
            font-size: 0.875rem;
            font-weight: 500;
          }
          .tile .assignee {
            font-size: 0.75rem;
            color: var(--muted-foreground, #6b7280);
          }
        }
      </style>
    </template>
  };
}
