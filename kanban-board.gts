// ═══ [EDIT TRACKING: ON] Mark all changes with ⁿ ═══
import {
  CardDef,
  Component,
  field,
  contains,
  linksToMany,
} from 'https://cardstack.com/base/card-api'; // ¹
import StringField from 'https://cardstack.com/base/string'; // ²
import { tracked } from '@glimmer/tracking'; // ³
import { on } from '@ember/modifier'; // ⁴
import { fn, get } from '@ember/helper'; // ⁵
import { gt, lt, subtract, add } from '@cardstack/boxel-ui/helpers'; // ⁵ᵇ
import ColumnsIcon from '@cardstack/boxel-icons/columns'; // ⁶
import { KanbanColumn } from './kanban-column'; // ⁷
import { KanbanTask } from './kanban-task'; // ⁸

export class KanbanBoard extends CardDef { // ⁹
  static displayName = 'Kanban Board';
  static icon = ColumnsIcon;
  static prefersWideFormat = true;

  @field boardName = contains(StringField); // ¹⁰
  @field description = contains(StringField); // ¹¹
  @field columns = linksToMany(KanbanColumn); // ¹² KEY CHANGE: CardDef with linksToMany!

  @field cardTitle = contains(StringField, { // ¹³
    computeVia: function (this: KanbanBoard) {
      return this.boardName ?? 'Kanban Board';
    },
  });

  // ¹⁴ Isolated - Full interactive board
  static isolated = class Isolated extends Component<typeof KanbanBoard> {
    @tracked newColumnName = '';
    @tracked newTaskName: Record<number, string> = {};
    @tracked creationStatus = '';

    get columns() {
      return this.args.model?.columns ?? [];
    }

    get totalTasks() {
      let count = 0;
      for (const col of this.columns) {
        count += col.tasks?.length ?? 0;
      }
      return count;
    }

    get columnCount() {
      return this.columns.length;
    }

    get hasColumns() {
      return this.columnCount > 0;
    }

    updateColumnName = (event: Event) => {
      this.newColumnName = (event.target as HTMLInputElement).value;
    };

    updateTaskName = (colIndex: number, event: Event) => {
      this.newTaskName = {
        ...this.newTaskName,
        [colIndex]: (event.target as HTMLInputElement).value,
      };
    };

    // ¹⁵ ADD COLUMN - Now works because columns is linksToMany(CardDef)!
    // NOTE: Don't include nested linksToMany fields (like 'tasks') - they can't be auto-coerced
    addColumn = () => {
      const name = this.newColumnName.trim() || `Column ${this.columnCount + 1}`;

      try {
        const newColumn = {
          columnName: name,
          // Don't include 'tasks' - nested linksToMany can't be created inline
        };

        const currentColumns = this.args.model?.columns ?? [];
        (this.args.model as any).columns = [...currentColumns, newColumn];

        this.newColumnName = '';
        this.creationStatus = `Column "${name}" created!`;
        setTimeout(() => { this.creationStatus = ''; }, 2000);
      } catch (e: any) {
        this.creationStatus = `Error: ${e?.message || e}`;
      }
    };

    // ¹⁶ Quick setup with default columns
    // NOTE: Don't include nested linksToMany fields (like 'tasks') - they can't be auto-coerced
    initializeBoard = () => {
      try {
        const defaultColumns = [
          { columnName: 'To Do', taskLimit: 0 },
          { columnName: 'In Progress', taskLimit: 3 },
          { columnName: 'Done', taskLimit: 0 },
        ];

        (this.args.model as any).columns = defaultColumns;
        this.creationStatus = 'Board initialized with 3 columns!';
        setTimeout(() => { this.creationStatus = ''; }, 2000);
      } catch (e: any) {
        this.creationStatus = `Error: ${e?.message || e}`;
      }
    };

    // ¹⁷ ADD TASK to column - Also works!
    addTask = (colIndex: number) => {
      const taskName = this.newTaskName[colIndex]?.trim();
      if (!taskName) return;

      try {
        const column = this.columns[colIndex];
        if (!column) return;

        const newTask = {
          taskName,
          priority: 'medium',
          completed: false,
          assignee: null,
          description: null,
        };

        const currentTasks = column.tasks ?? [];
        (column as any).tasks = [...currentTasks, newTask];

        this.newTaskName = { ...this.newTaskName, [colIndex]: '' };
        this.creationStatus = `Task "${taskName}" added!`;
        setTimeout(() => { this.creationStatus = ''; }, 1500);
      } catch (e: any) {
        this.creationStatus = `Error: ${e?.message || e}`;
      }
    };

    handleTaskKeydown = (colIndex: number, event: KeyboardEvent) => {
      if (event.key === 'Enter') {
        this.addTask(colIndex);
      }
    };

    handleColumnKeydown = (event: KeyboardEvent) => {
      if (event.key === 'Enter') {
        this.addColumn();
      }
    };

    // ¹⁸ Move task between columns
    moveTask = (fromCol: number, taskIndex: number, toCol: number) => {
      try {
        const sourceColumn = this.columns[fromCol];
        const targetColumn = this.columns[toCol];
        if (!sourceColumn?.tasks || !targetColumn) return;

        const tasks = [...sourceColumn.tasks];
        const [task] = tasks.splice(taskIndex, 1);

        (sourceColumn as any).tasks = tasks;
        (targetColumn as any).tasks = [...(targetColumn.tasks ?? []), task];
      } catch (e) {
        console.error('Move failed:', e);
      }
    };

    // ¹⁹ Toggle task completion
    toggleComplete = (colIndex: number, taskIndex: number) => {
      try {
        const column = this.columns[colIndex];
        const task = column?.tasks?.[taskIndex];
        if (task) {
          (task as any).completed = !task.completed;
        }
      } catch (e) {
        console.error('Toggle failed:', e);
      }
    };

    <template>
      <article class="kanban-board">
        <header class="board-header">
          <div class="header-info">
            <h1>{{if @model.boardName @model.boardName "Kanban Board"}}</h1>
            {{#if @model.description}}
              <p class="description">{{@model.description}}</p>
            {{/if}}
          </div>
          <div class="header-actions">
            <div class="add-column-form">
              <input
                type="text"
                placeholder="New column name..."
                value={{this.newColumnName}}
                {{on "input" this.updateColumnName}}
                {{on "keydown" this.handleColumnKeydown}}
              />
              <button class="add-btn" type="button" {{on "click" this.addColumn}}>
                + Column
              </button>
            </div>
            <div class="header-stats">
              <div class="stat">
                <span class="stat-value">{{this.columnCount}}</span>
                <span class="stat-label">Columns</span>
              </div>
              <div class="stat">
                <span class="stat-value">{{this.totalTasks}}</span>
                <span class="stat-label">Tasks</span>
              </div>
            </div>
          </div>
        </header>

        {{#if this.creationStatus}}
          <div class="status-bar">{{this.creationStatus}}</div>
        {{/if}}

        <div class="board-content">
          {{#if this.hasColumns}}
            {{#each this.columns as |column colIndex|}}
              <div class="column">
                <header class="column-header">
                  <h3 class="column-title">{{if column.columnName column.columnName "Untitled"}}</h3>
                  <span class="count">{{if column.tasks column.tasks.length 0}}</span>
                </header>

                <div class="tasks-area">
                  {{#each column.tasks as |task taskIndex|}}
                    <div class="task-item {{if task.completed 'completed'}}">
                      {{#if (gt colIndex 0)}}
                        <button
                          class="move-btn"
                          type="button"
                          {{on "click" (fn this.moveTask colIndex taskIndex (subtract colIndex 1))}}
                        >◀</button>
                      {{/if}}

                      <div class="task-main" role="button" {{on "click" (fn this.toggleComplete colIndex taskIndex)}}>
                        <div class="complete-box">
                          {{#if task.completed}}✓{{/if}}
                        </div>
                        <div class="task-info">
                          {{#if task.priority}}
                            <span class="priority priority-{{task.priority}}"></span>
                          {{/if}}
                          <span class="task-name">{{task.taskName}}</span>
                          {{#if task.assignee}}
                            <span class="task-assignee">{{task.assignee}}</span>
                          {{/if}}
                        </div>
                      </div>

                      {{#if (lt colIndex (subtract this.columnCount 1))}}
                        <button
                          class="move-btn"
                          type="button"
                          {{on "click" (fn this.moveTask colIndex taskIndex (add colIndex 1))}}
                        >▶</button>
                      {{/if}}
                    </div>
                  {{else}}
                    <div class="empty-tasks">No tasks yet</div>
                  {{/each}}
                </div>

                <div class="quick-add">
                  <input
                    type="text"
                    placeholder="+ Add task, press Enter"
                    value={{get this.newTaskName colIndex}}
                    {{on "input" (fn this.updateTaskName colIndex)}}
                    {{on "keydown" (fn this.handleTaskKeydown colIndex)}}
                  />
                </div>
              </div>
            {{/each}}
          {{else}}
            <div class="empty-board">
              <div class="empty-icon">☰</div>
              <h2>No columns yet</h2>
              <p>Start by adding columns to organize your tasks</p>
              <div class="empty-actions">
                <button class="primary-btn" type="button" {{on "click" this.initializeBoard}}>
                  Quick Setup (To Do → In Progress → Done)
                </button>
              </div>
            </div>
          {{/if}}
        </div>
      </article>

      <style scoped>
        .kanban-board {
          height: 100%;
          display: flex;
          flex-direction: column;
          background: var(--background, #fafafa);
          font-family: var(--font-sans, 'Inter', -apple-system, sans-serif);
        }

        .board-header {
          display: flex;
          justify-content: space-between;
          align-items: flex-start;
          padding: var(--boxel-sp-lg, 1.5rem);
          background: var(--card, #fff);
          border-bottom: 1px solid var(--border, #e5e5e5);
          flex-wrap: wrap;
          gap: var(--boxel-sp, 1rem);
        }

        .header-info h1 {
          margin: 0;
          font-size: var(--boxel-font-size-lg, 1.25rem);
          font-weight: 700;
          color: var(--foreground, #1a1a1a);
        }

        .description {
          margin: 4px 0 0;
          font-size: var(--boxel-font-size-sm, 0.875rem);
          color: var(--muted-foreground, #6b7280);
        }

        .header-actions {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp, 1rem);
          flex-wrap: wrap;
        }

        .add-column-form {
          display: flex;
          gap: var(--boxel-sp-xs, 0.5rem);
        }

        .add-column-form input {
          padding: var(--boxel-sp-xs, 0.5rem) var(--boxel-sp-sm, 0.75rem);
          border: 1px solid var(--border, #e5e5e5);
          border-radius: var(--boxel-border-radius, 0.5rem);
          font-size: var(--boxel-font-size-sm, 0.875rem);
          width: 150px;
        }

        .add-column-form input:focus {
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

        .header-stats {
          display: flex;
          gap: var(--boxel-sp, 1rem);
        }

        .stat {
          text-align: center;
          padding: var(--boxel-sp-xs, 0.5rem) var(--boxel-sp, 1rem);
          background: var(--muted, #f5f5f5);
          border-radius: var(--boxel-border-radius, 0.5rem);
        }

        .stat-value {
          display: block;
          font-size: var(--boxel-font-size-lg, 1.25rem);
          font-weight: 700;
          color: var(--primary, #3b82f6);
        }

        .stat-label {
          font-size: var(--boxel-font-size-xs, 0.75rem);
          color: var(--muted-foreground, #6b7280);
          text-transform: uppercase;
        }

        .status-bar {
          padding: var(--boxel-sp-xs, 0.5rem) var(--boxel-sp-lg, 1.5rem);
          background: var(--secondary, #e0f2fe);
          color: var(--secondary-foreground, #0369a1);
          font-size: var(--boxel-font-size-sm, 0.875rem);
          text-align: center;
        }

        .board-content {
          flex: 1;
          display: flex;
          gap: var(--boxel-sp, 1rem);
          padding: var(--boxel-sp-lg, 1.5rem);
          overflow-x: auto;
        }

        .empty-board {
          flex: 1;
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          text-align: center;
          padding: var(--boxel-sp-2xl, 3rem);
          background: var(--card, #fff);
          border: 2px dashed var(--border, #e5e5e5);
          border-radius: var(--boxel-border-radius-lg, 1rem);
          margin: auto;
          max-width: 500px;
        }

        .empty-icon {
          font-size: 3rem;
          color: var(--muted-foreground, #6b7280);
          margin-bottom: var(--boxel-sp, 1rem);
        }

        .empty-board h2 {
          margin: 0 0 var(--boxel-sp-xs, 0.5rem);
          font-size: var(--boxel-font-size-lg, 1.25rem);
          color: var(--foreground, #1a1a1a);
        }

        .empty-board p {
          margin: 0 0 var(--boxel-sp-lg, 1.5rem);
          color: var(--muted-foreground, #6b7280);
        }

        .primary-btn {
          padding: var(--boxel-sp-sm, 0.75rem) var(--boxel-sp-lg, 1.5rem);
          background: var(--primary, #3b82f6);
          color: var(--primary-foreground, #fff);
          border: none;
          border-radius: var(--boxel-border-radius, 0.5rem);
          font-size: var(--boxel-font-size-sm, 0.875rem);
          font-weight: 600;
          cursor: pointer;
        }

        .primary-btn:hover {
          filter: brightness(1.1);
        }

        .column {
          flex-shrink: 0;
          width: 300px;
          background: var(--card, #fff);
          border: 1px solid var(--border, #e5e5e5);
          border-radius: var(--boxel-border-radius-lg, 1rem);
          display: flex;
          flex-direction: column;
          max-height: 100%;
        }

        .column-header {
          display: flex;
          justify-content: space-between;
          align-items: center;
          padding: var(--boxel-sp-sm, 0.75rem) var(--boxel-sp, 1rem);
          border-bottom: 1px solid var(--border, #e5e5e5);
        }

        .column-title {
          margin: 0;
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
          background: var(--muted, #f5f5f5);
          padding: 2px 8px;
          border-radius: 10px;
        }

        .tasks-area {
          flex: 1;
          padding: var(--boxel-sp-sm, 0.75rem);
          overflow-y: auto;
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-xs, 0.5rem);
        }

        .empty-tasks {
          text-align: center;
          padding: var(--boxel-sp-lg, 1.5rem);
          color: var(--muted-foreground, #6b7280);
          font-size: var(--boxel-font-size-sm, 0.875rem);
        }

        .task-item {
          display: flex;
          align-items: stretch;
          gap: 4px;
          background: var(--muted, #f5f5f5);
          border-radius: var(--boxel-border-radius, 0.5rem);
          overflow: hidden;
        }

        .task-item.completed {
          opacity: 0.5;
        }

        .task-item.completed .task-name {
          text-decoration: line-through;
        }

        .move-btn {
          padding: var(--boxel-sp-xs, 0.5rem);
          background: transparent;
          border: none;
          color: var(--muted-foreground, #6b7280);
          cursor: pointer;
          font-size: 12px;
          transition: all 0.15s;
        }

        .move-btn:hover {
          background: var(--primary, #3b82f6);
          color: var(--primary-foreground, #fff);
        }

        .task-main {
          flex: 1;
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs, 0.5rem);
          padding: var(--boxel-sp-xs, 0.5rem);
          cursor: pointer;
        }

        .complete-box {
          width: 18px;
          height: 18px;
          border: 2px solid var(--border, #e5e5e5);
          border-radius: 4px;
          background: var(--card, #fff);
          display: flex;
          align-items: center;
          justify-content: center;
          font-size: 10px;
          color: var(--primary, #3b82f6);
          flex-shrink: 0;
        }

        .task-info {
          flex: 1;
          min-width: 0;
        }

        .priority {
          display: inline-block;
          width: 6px;
          height: 6px;
          border-radius: 50%;
          margin-right: 6px;
          vertical-align: middle;
        }

        .priority-high { background: var(--destructive, #dc2626); }
        .priority-medium { background: var(--chart-4, #f59e0b); }
        .priority-low { background: var(--chart-3, #22c55e); }

        .task-name {
          font-size: var(--boxel-font-size-sm, 0.875rem);
          color: var(--foreground, #1a1a1a);
        }

        .task-assignee {
          display: block;
          font-size: var(--boxel-font-size-xs, 0.75rem);
          color: var(--muted-foreground, #6b7280);
          margin-top: 2px;
        }

        .quick-add {
          padding: var(--boxel-sp-sm, 0.75rem);
          border-top: 1px solid var(--border, #e5e5e5);
        }

        .quick-add input {
          width: 100%;
          padding: var(--boxel-sp-xs, 0.5rem) var(--boxel-sp-sm, 0.75rem);
          border: 1px dashed var(--border, #e5e5e5);
          border-radius: var(--boxel-border-radius, 0.5rem);
          font-size: var(--boxel-font-size-sm, 0.875rem);
          background: transparent;
          color: var(--foreground, #1a1a1a);
        }

        .quick-add input:focus {
          outline: none;
          border-style: solid;
          border-color: var(--primary, #3b82f6);
          background: var(--card, #fff);
        }
      </style>
    </template>

  };

  // ²⁰ Embedded view
  static embedded = class Embedded extends Component<typeof KanbanBoard> {
    get totalTasks() {
      let count = 0;
      for (const col of this.args.model?.columns ?? []) {
        count += col.tasks?.length ?? 0;
      }
      return count;
    }

    <template>
      <div class="embedded">
        <span class="icon">☰</span>
        <span class="name">{{if @model.boardName @model.boardName "Kanban Board"}}</span>
        <span class="meta">{{this.totalTasks}} tasks</span>
      </div>

      <style scoped>
        .embedded {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs, 0.5rem);
          padding: var(--boxel-sp-xs, 0.5rem);
          font-family: var(--font-sans, 'Inter', -apple-system, sans-serif);
        }
        .icon { color: var(--primary, #3b82f6); }
        .name { font-weight: 500; color: var(--foreground, #1a1a1a); }
        .meta { font-size: var(--boxel-font-size-xs, 0.75rem); color: var(--muted-foreground, #6b7280); }
      </style>
    </template>
  };

  // ²¹ Fitted view
  static fitted = class Fitted extends Component<typeof KanbanBoard> {
    get totalTasks() {
      let count = 0;
      for (const col of this.args.model?.columns ?? []) {
        count += col.tasks?.length ?? 0;
      }
      return count;
    }

    get columnCount() {
      return this.args.model?.columns?.length ?? 0;
    }

    <template>
      <div class="fitted">
        <div class="fitted-icon">☰</div>
        <h3 class="fitted-title">{{if @model.boardName @model.boardName "Kanban"}}</h3>
        <div class="fitted-stats">
          <span>{{this.columnCount}} cols</span>
          <span>{{this.totalTasks}} tasks</span>
        </div>
      </div>

      <style scoped>
        .fitted {
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          height: 100%;
          padding: var(--boxel-sp, 1rem);
          text-align: center;
          background: var(--card, #fff);
          font-family: var(--font-sans, 'Inter', -apple-system, sans-serif);
        }
        .fitted-icon {
          font-size: 2rem;
          color: var(--primary, #3b82f6);
          margin-bottom: var(--boxel-sp-xs, 0.5rem);
        }
        .fitted-title {
          margin: 0;
          font-size: var(--boxel-font-size, 1rem);
          font-weight: 600;
        }
        .fitted-stats {
          display: flex;
          gap: var(--boxel-sp-sm, 0.75rem);
          margin-top: var(--boxel-sp-xs, 0.5rem);
          font-size: var(--boxel-font-size-xs, 0.75rem);
          color: var(--muted-foreground, #6b7280);
        }
      </style>
    </template>
  };
}
// touched for re-index
