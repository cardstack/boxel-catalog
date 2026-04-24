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
import LayoutListIcon from '@cardstack/boxel-icons/layout-list'; // ⁴
import { tracked } from '@glimmer/tracking'; // ⁵
import { on } from '@ember/modifier'; // ⁶
import { KanbanTask } from './kanban-task'; // ⁷

export class KanbanColumn extends CardDef { // ⁸
  static displayName = 'Kanban Column';
  static icon = LayoutListIcon;

  @field columnName = contains(StringField); // ⁹
  @field tasks = linksToMany(KanbanTask); // ¹⁰ KEY: CardDef with linksToMany!
  @field taskLimit = contains(NumberField); // ¹¹ WIP limit

  @field cardTitle = contains(StringField, { // ¹²
    computeVia: function (this: KanbanColumn) {
      return this.columnName ?? 'Untitled Column';
    },
  });

  // ¹³ Isolated - full column view with task management
  static isolated = class Isolated extends Component<typeof KanbanColumn> {
    @tracked newTaskName = '';
    @tracked creationStatus = '';

    get taskCount() {
      return this.args.model?.tasks?.length ?? 0;
    }

    get isOverLimit() {
      const limit = this.args.model?.taskLimit;
      return limit && limit > 0 && this.taskCount > limit;
    }

    get limitDisplay() {
      const limit = this.args.model?.taskLimit;
      if (!limit || limit <= 0) return null;
      return `${this.taskCount}/${limit}`;
    }

    updateTaskName = (event: Event) => {
      this.newTaskName = (event.target as HTMLInputElement).value;
    };

    // ¹⁴ Runtime task creation - THIS NOW WORKS because tasks is linksToMany(CardDef)
    addTask = () => {
      if (!this.newTaskName.trim()) return;

      this.creationStatus = 'Creating task...';

      try {
        const newTask = {
          taskName: this.newTaskName,
          priority: 'medium',
          completed: false,
        };

        const currentTasks = this.args.model?.tasks ?? [];
        (this.args.model as any).tasks = [...currentTasks, newTask];

        this.newTaskName = '';
        this.creationStatus = 'Task created!';
        setTimeout(() => { this.creationStatus = ''; }, 1500);
      } catch (e: any) {
        this.creationStatus = `Error: ${e?.message || e}`;
      }
    };

    handleKeydown = (event: KeyboardEvent) => {
      if (event.key === 'Enter') {
        this.addTask();
      }
    };

    <template>
      <article class="column-isolated {{if this.isOverLimit 'over-limit'}}">
        <header class="column-header">
          <h1 class="column-name">{{if @model.columnName @model.columnName "Untitled Column"}}</h1>
          <span class="task-count {{if this.isOverLimit 'over'}}">
            {{if this.limitDisplay this.limitDisplay this.taskCount}}
          </span>
        </header>

        <div class="tasks-section">
          {{#if @model.tasks.length}}
            <div class="tasks-list">
              <@fields.tasks @format="embedded" />
            </div>
          {{else}}
            <div class="empty-tasks">
              <p>No tasks in this column</p>
            </div>
          {{/if}}
        </div>

        <div class="add-task-section">
          <input
            type="text"
            class="task-input"
            placeholder="New task name..."
            value={{this.newTaskName}}
            {{on "input" this.updateTaskName}}
            {{on "keydown" this.handleKeydown}}
          />
          <button class="add-btn" type="button" {{on "click" this.addTask}}>
            Add Task
          </button>
        </div>

        {{#if this.creationStatus}}
          <div class="status">{{this.creationStatus}}</div>
        {{/if}}
      </article>

      <style scoped>
        .column-isolated {
          display: flex;
          flex-direction: column;
          height: 100%;
          background: var(--muted, #f5f5f5);
          font-family: var(--font-sans, 'Inter', -apple-system, sans-serif);
        }

        .column-isolated.over-limit {
          background: hsl(0 84% 95%);
        }

        .column-header {
          display: flex;
          justify-content: space-between;
          align-items: center;
          padding: var(--boxel-sp, 1rem);
          background: var(--card, #fff);
          border-bottom: 1px solid var(--border, #e5e5e5);
        }

        .column-name {
          margin: 0;
          font-size: var(--boxel-font-size-lg, 1.25rem);
          font-weight: 600;
          color: var(--foreground, #1a1a1a);
        }

        .task-count {
          padding: 4px 12px;
          background: var(--secondary, #e5e5e5);
          border-radius: var(--boxel-border-radius, 0.5rem);
          font-size: var(--boxel-font-size-sm, 0.875rem);
          font-weight: 600;
          color: var(--muted-foreground, #6b7280);
        }

        .task-count.over {
          background: var(--destructive, #dc2626);
          color: var(--destructive-foreground, #fff);
        }

        .tasks-section {
          flex: 1;
          padding: var(--boxel-sp, 1rem);
          overflow-y: auto;
        }

        .tasks-list {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-xs, 0.5rem);
        }

        .tasks-list > .linksToMany-field {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-xs, 0.5rem);
        }

        .empty-tasks {
          text-align: center;
          padding: var(--boxel-sp-xl, 2rem);
          color: var(--muted-foreground, #6b7280);
        }

        .add-task-section {
          display: flex;
          gap: var(--boxel-sp-xs, 0.5rem);
          padding: var(--boxel-sp, 1rem);
          background: var(--card, #fff);
          border-top: 1px solid var(--border, #e5e5e5);
        }

        .task-input {
          flex: 1;
          padding: var(--boxel-sp-xs, 0.5rem) var(--boxel-sp-sm, 0.75rem);
          border: 1px solid var(--border, #e5e5e5);
          border-radius: var(--boxel-border-radius, 0.5rem);
          font-size: var(--boxel-font-size-sm, 0.875rem);
          background: var(--card, #fff);
          color: var(--foreground, #1a1a1a);
        }

        .task-input:focus {
          outline: none;
          border-color: var(--primary, #3b82f6);
        }

        .add-btn {
          padding: var(--boxel-sp-xs, 0.5rem) var(--boxel-sp, 1rem);
          background: var(--primary, #3b82f6);
          color: var(--primary-foreground, #fff);
          border: none;
          border-radius: var(--boxel-border-radius, 0.5rem);
          font-size: var(--boxel-font-size-sm, 0.875rem);
          font-weight: 600;
          cursor: pointer;
          transition: all 0.15s;
        }

        .add-btn:hover {
          filter: brightness(1.1);
        }

        .status {
          padding: var(--boxel-sp-xs, 0.5rem);
          margin: 0 var(--boxel-sp, 1rem) var(--boxel-sp, 1rem);
          background: var(--secondary, #e0f2fe);
          border-radius: var(--boxel-border-radius-sm, 0.25rem);
          font-size: var(--boxel-font-size-xs, 0.75rem);
          color: var(--secondary-foreground, #0369a1);
          text-align: center;
        }
      </style>
    </template>
  };

  // ¹⁵ Embedded - compact column view
  static embedded = class Embedded extends Component<typeof KanbanColumn> {
    get taskCount() {
      return this.args.model?.tasks?.length ?? 0;
    }

    <template>
      <div class="column-embedded">
        <div class="header">
          <span class="name">{{if @model.columnName @model.columnName "Column"}}</span>
          <span class="count">{{this.taskCount}}</span>
        </div>
        {{#if @model.tasks.length}}
          <div class="tasks-preview">
            <@fields.tasks @format="embedded" />
          </div>
        {{else}}
          <div class="empty">No tasks</div>
        {{/if}}
      </div>

      <style scoped>
        .column-embedded {
          background: var(--muted, #f5f5f5);
          border-radius: var(--boxel-border-radius, 0.5rem);
          padding: var(--boxel-sp-sm, 0.75rem);
          font-family: var(--font-sans, 'Inter', -apple-system, sans-serif);
        }

        .header {
          display: flex;
          justify-content: space-between;
          align-items: center;
          margin-bottom: var(--boxel-sp-xs, 0.5rem);
        }

        .name {
          font-size: var(--boxel-font-size-sm, 0.875rem);
          font-weight: 600;
          color: var(--foreground, #1a1a1a);
          text-transform: uppercase;
          letter-spacing: 0.02em;
        }

        .count {
          font-size: var(--boxel-font-size-xs, 0.75rem);
          font-weight: 600;
          color: var(--muted-foreground, #6b7280);
          background: var(--card, #fff);
          padding: 2px 8px;
          border-radius: 10px;
        }

        .tasks-preview {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-2xs, 0.25rem);
        }

        .tasks-preview > .linksToMany-field {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-2xs, 0.25rem);
        }

        .empty {
          text-align: center;
          padding: var(--boxel-sp-sm, 0.75rem);
          color: var(--muted-foreground, #6b7280);
          font-size: var(--boxel-font-size-xs, 0.75rem);
        }
      </style>
    </template>
  };

  // ¹⁶ Fitted
  static fitted = class Fitted extends Component<typeof KanbanColumn> {
    get taskCount() {
      return this.args.model?.tasks?.length ?? 0;
    }

    <template>
      <div class="column-fitted">
        <div class="badge">
          <span class="count">{{this.taskCount}}</span>
        </div>
        <div class="strip">
          <span class="name">{{if @model.columnName @model.columnName "Column"}}</span>
          <span class="count">{{this.taskCount}} tasks</span>
        </div>
        <div class="tile">
          <span class="name">{{if @model.columnName @model.columnName "Column"}}</span>
          <span class="count">{{this.taskCount}} tasks</span>
        </div>
      </div>

      <style scoped>
        .column-fitted {
          container-type: size;
          width: 100%;
          height: 100%;
          font-family: var(--font-sans, 'Inter', -apple-system, sans-serif);
        }

        .badge, .strip, .tile { display: none; }

        @container (max-width: 150px) and (max-height: 169px) {
          .badge {
            display: flex;
            align-items: center;
            justify-content: center;
            height: 100%;
            background: var(--muted, #f5f5f5);
          }
          .badge .count {
            font-size: 1.5rem;
            font-weight: 700;
            color: var(--primary, #3b82f6);
          }
        }

        @container (min-width: 151px) and (max-height: 169px) {
          .strip {
            display: flex;
            align-items: center;
            justify-content: space-between;
            height: 100%;
            padding: 8px 12px;
            background: var(--muted, #f5f5f5);
          }
          .strip .name {
            font-size: 0.875rem;
            font-weight: 600;
          }
          .strip .count {
            font-size: 0.75rem;
            color: var(--muted-foreground, #6b7280);
          }
        }

        @container (min-height: 170px) {
          .tile {
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            gap: 8px;
            height: 100%;
            padding: 16px;
            background: var(--muted, #f5f5f5);
          }
          .tile .name {
            font-size: 1rem;
            font-weight: 600;
          }
          .tile .count {
            font-size: 0.875rem;
            color: var(--muted-foreground, #6b7280);
          }
        }
      </style>
    </template>
  };
}
