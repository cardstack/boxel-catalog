import { markDefinition } from '@cardstack/base/mark-definition';
import {
  CardDef,
  Component,
  StringField,
  contains,
  field,
  linksTo,
  linksToMany,
} from '@cardstack/base/card-api';
import MarkdownField from '@cardstack/base/markdown';
import Tag from '@cardstack/base/tag';
import SquareCheckIcon from '@cardstack/boxel-icons/square-check';

import { statusField } from '@cardstack/catalog/fields/status/status';
import PriorityField from '@cardstack/catalog/fields/priority/priority';
import DueDateField from '@cardstack/catalog/fields/due-date/due-date';
import CreatedAtField from '@cardstack/catalog/fields/created-at/created-at';
import { User } from '../crm/user';
import { IsoFrame } from '../shared/compact-sheet';
import { RichFittedCard, Detail, Metric } from '../shared/rich-fitted-card';

/**
 * The generic actionable item, not any app's version of one. Composed from
 * the catalog's field blocks (status, priority, due date, created at) instead
 * of hand-rolling its own compounds.
 *
 * Nesting is modeled as `subtasks: linksToMany(Task)` on the parent: the set
 * is bounded, the rollup ("3 of 5 done") belongs on
 * the card itself, and one editor maintains the list. There is no parentTask
 * back-pointer; two stored sources of the same fact drift.
 *
 * Domain specifics stay with the consumer: an app extends Task additively
 * (a project link, completion criteria, a sprint) and never overrides the
 * lifecycle — a task that needs a different lifecycle is a different card.
 */
export const TaskStatusField = markDefinition(
  statusField({
    displayName: 'Task Status',
    options: [
      {
        value: 'Not Started',
        hue: 'slate',
        meaning: 'Captured but nobody has begun.',
      },
      {
        value: 'In Progress',
        hue: 'blue',
        meaning: 'Someone is actively on it.',
      },
      {
        value: 'Blocked',
        hue: 'red',
        holds: true,
        meaning: 'Cannot proceed until something outside this task clears.',
      },
      {
        value: 'Done',
        hue: 'green',
        terminal: true,
        holds: true,
        meaning: 'The person doing it says it is complete.',
      },
    ],
    transitions: {
      'Not Started': ['In Progress', 'Done'],
      'In Progress': ['Blocked', 'Done', 'Not Started'],
      Blocked: ['In Progress'],
      Done: ['In Progress'],
    },
  }),
);

function subtaskList(model: Partial<Task> | undefined): Task[] {
  return ((model?.subtasks ?? []) as Task[]).filter(Boolean);
}

function doneCount(model: Partial<Task> | undefined): number {
  return subtaskList(model).filter((t) => t.status === 'Done').length;
}

export class Task extends CardDef {
  static displayName = 'Task';
  static icon = SquareCheckIcon;

  @field title = contains(StringField);
  @field details = contains(MarkdownField);
  @field status = contains(TaskStatusField);
  @field priority = contains(PriorityField);
  @field dueDate = contains(DueDateField);
  @field createdAt = contains(CreatedAtField);
  @field assignee = linksTo(() => User, { searchable: true });
  @field tags = linksToMany(Tag);
  @field subtasks = linksToMany(() => Task);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: Task) {
      return this.title?.trim()?.length ? this.title : 'Untitled task';
    },
  });

  static embedded = class Embedded extends Component<typeof Task> {
    get done() {
      return doneCount(this.args.model);
    }
    get total() {
      return subtaskList(this.args.model).length;
    }
    <template>
      <div class='task-row'>
        <span class='t-status'><@fields.status @format='atom' /></span>
        <span class='t-title'>{{@model.cardTitle}}</span>
        {{#if this.total}}
          <span class='t-subs'>{{this.done}}/{{this.total}}</span>
        {{/if}}
        <span class='t-due'>{{#if @model.dueDate}}<@fields.dueDate
              @format='atom'
            />{{else}}<span class='t-empty'>—</span>{{/if}}</span>
        <span class='t-priority'>{{#if @model.priority}}<@fields.priority
              @format='atom'
            />{{else}}<span class='t-empty'>—</span>{{/if}}</span>
      </div>
      <style scoped>
        .task-row {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          font-size: var(--boxel-font-size-sm);
        }
        .t-title {
          font-weight: 600;
          color: var(--foreground);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          flex: 1;
          min-width: 0;
        }
        .t-subs {
          font-variant-numeric: tabular-nums;
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
          white-space: nowrap;
        }
        /* Trailing data slots stay constant-width and always render, so a
           consumer's task list column-aligns regardless of per-row gaps. */
        .t-due {
          min-width: 4.5rem;
          text-align: right;
          flex-shrink: 0;
        }
        .t-priority {
          min-width: 4rem;
          text-align: right;
          flex-shrink: 0;
        }
        .t-empty {
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof Task> {
    <template>
      <span class='task-atom'>
        <@fields.status @format='atom' />
        <span class='ta-title'>{{@model.cardTitle}}</span>
      </span>
      <style scoped>
        .task-atom {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-4xs);
          font-size: var(--boxel-font-size-xs);
        }
        .ta-title {
          font-weight: 600;
          color: var(--foreground);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static isolated = class Isolated extends Component<typeof Task> {
    get done() {
      return doneCount(this.args.model);
    }
    get total() {
      return subtaskList(this.args.model).length;
    }
    <template>
      <IsoFrame>
        <article class='task-page'>
          <header>
            <div class='head-row'>
              <@fields.status @format='embedded' />
              {{#if @model.priority}}
                <@fields.priority @format='embedded' />
              {{/if}}
            </div>
            <h1>{{@model.cardTitle}}</h1>
            <div class='meta'>
              {{#if @model.dueDate}}
                <span class='meta-item'><@fields.dueDate
                    @format='embedded'
                  /></span>
              {{/if}}
              {{#if @model.assignee}}
                <span class='meta-item'><@fields.assignee
                    @format='atom'
                  /></span>
              {{/if}}
              {{#if @model.createdAt}}
                <span class='meta-item muted'>created
                  <@fields.createdAt @format='atom' /></span>
              {{/if}}
            </div>
            {{#if @model.tags.length}}
              <div class='tags'><@fields.tags @format='atom' /></div>
            {{/if}}
          </header>
          {{#if @model.details}}
            <section class='panel details'><@fields.details /></section>
          {{/if}}
          <section class='panel'>
            <h2>Subtasks
              {{#if this.total}}<span class='progress'>{{this.done}}
                  of
                  {{this.total}}
                  done</span>{{/if}}</h2>
            {{#if this.total}}
              <div class='subtask-list'>
                {{#each @fields.subtasks as |Subtask|}}
                  <Subtask
                    class='subtask'
                    @format='embedded'
                    @displayContainer={{false}}
                  />
                {{/each}}
              </div>
            {{else}}
              <p class='empty'>No subtasks — this task stands alone.</p>
            {{/if}}
          </section>
        </article>
      </IsoFrame>
      <style scoped>
        .task-page {
          background: var(--card);
          color: var(--card-foreground);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          max-width: 44rem;
          margin: 0 auto;
          inline-size: 100%;
          padding: var(--boxel-sp-xl) var(--boxel-sp-lg);
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-lg);
        }
        header {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-xs);
          border-bottom: 0.125rem solid var(--foreground);
          padding-bottom: var(--boxel-sp-lg);
        }
        .head-row {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
        }
        h1 {
          margin: 0;
          font-size: var(--boxel-font-size-lg);
          line-height: 1.15;
        }
        .meta {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-sm);
          flex-wrap: wrap;
          font-size: var(--boxel-font-size-sm);
        }
        .meta-item {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-4xs);
        }
        .muted {
          color: var(--muted-foreground);
        }
        .tags {
          display: flex;
          gap: var(--boxel-sp-4xs);
          flex-wrap: wrap;
        }
        .panel {
          border: 1px solid var(--border);
          border-radius: var(--radius);
          padding: var(--boxel-sp) var(--boxel-sp-lg);
          background-color: var(--card);
        }
        h2 {
          margin: 0 0 var(--boxel-sp-sm);
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
          display: flex;
          align-items: baseline;
          gap: var(--boxel-sp-xs);
        }
        .progress {
          text-transform: none;
          letter-spacing: normal;
          font-weight: 600;
          font-variant-numeric: tabular-nums;
        }
        .subtask-list {
          display: flex;
          flex-direction: column;
        }
        .subtask {
          border-top: 1px solid var(--border);
        }
        .subtask + .subtask {
          margin-top: var(--boxel-sp);
        }
        .empty {
          margin: 0;
          color: var(--muted-foreground);
          font-size: var(--boxel-font-size-sm);
        }
        .details :deep(p:first-child) {
          margin-top: 0;
        }
        .details :deep(p:last-child) {
          margin-bottom: 0;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof Task> {
    get done() {
      return doneCount(this.args.model);
    }
    get total() {
      return subtaskList(this.args.model).length;
    }
    <template>
      <RichFittedCard>
        <:title>{{@model.cardTitle}}</:title>
        <:status><@fields.status @format='atom' />{{#if
            @model.priority
          }}<@fields.priority @format='atom' />{{/if}}</:status>
        <:metric>{{#if this.total}}<Metric
              @value='{{this.done}}/{{this.total}}'
              @label='Subtasks done'
            />{{/if}}</:metric>
        <:details>
          {{#if @model.dueDate}}<Detail @label='Due'><@fields.dueDate
                @format='atom'
              /></Detail>{{/if}}
          {{#if @model.assignee.name}}<Detail
              @label='Assignee'
              @value={{@model.assignee.name}}
            />{{/if}}
        </:details>
      </RichFittedCard>
    </template>
  };
}

export default Task;
