import {
  CardDef,
  Component,
  field,
  contains,
  containsMany,
  FieldDef,
  StringField,
  type BaseDefComponent,
} from '@cardstack/base/card-api';
import TextAreaField from '@cardstack/base/text-area';
import ChecklistIcon from '@cardstack/boxel-icons/checklist';

import { DurationField, durationLabel } from './duration-field';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { IsoFrame } from '../shared/compact-sheet';
import { RichFittedCard, Detail, Metric } from '../shared/rich-fitted-card';

// containsMany takes a FieldDef, never a CardDef: this type's data lives inline
// on the OnboardingTemplate instance and it is never addressable on its own, so
// CardDef's identity apparatus (cardInfo, thumbnailURL, its own URL) was never
// used and never serialized. Its sibling OnboardingChecklistTaskField was
// already declared correctly; this one was the outlier.
export class OnboardingTemplateTaskField extends FieldDef {
  static displayName = 'Onboarding Template Task';

  @field title = contains(StringField);
  @field description = contains(TextAreaField);
  @field dueDate = contains(DurationField, {
    description: 'How long after the start date the task is due',
  });
  @field assigneeRole = contains(StringField, {
    description: 'e.g. "Engineering Manager", "HR"',
  });
  @field notes = contains(TextAreaField);

  static embedded: BaseDefComponent = class Embedded extends Component<
    typeof this
  > {
    <template>
      <li class='task-row'>
        <span class='task-title'>{{@model.title}}</span>
        {{#if @model.assigneeRole}}
          <span class='task-role'>{{@model.assigneeRole}}</span>
        {{/if}}
        {{#if @model.dueDate.value}}
          <span class='task-due'>Due
            {{durationLabel @model.dueDate.value @model.dueDate.unit}}
            after start</span>
        {{/if}}
      </li>
      <style scoped>
        .task-row {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-sm);
          border-bottom: 1px solid var(--border);
          list-style: none;
        }
        .task-row:last-child {
          border-bottom: 0;
        }
        .task-title {
          flex: 1;
          font-weight: 600;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .task-role {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
          white-space: nowrap;
        }
        .task-due {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
          white-space: nowrap;
        }
      </style>
    </template>
  };
}

export class OnboardingTemplate extends CardDef {
  static displayName = 'Onboarding Template';
  static icon = ChecklistIcon;

  @field name = contains(StringField);
  @field description = contains(TextAreaField);
  @field tasks = containsMany(OnboardingTemplateTaskField);

  @field title = contains(StringField, {
    computeVia: function (this: OnboardingTemplate) {
      return this.name?.trim() || 'Unnamed Template';
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    <template>
      <IsoFrame>
        <article class='template-isolated'>
          <header class='header'>
            <div class='header-content'>
              <h1>{{@model.title}}</h1>
              {{#if @model.description}}
                <p class='description'>{{@model.description}}</p>
              {{/if}}
            </div>
          </header>

          <div class='body'>
            <h2 class='section-title'>Tasks ({{@model.tasks.length}})</h2>
            {{#if @model.tasks.length}}
              <ul class='task-list'>
                <@fields.tasks @format='embedded' />
              </ul>
            {{else}}
              <EmptyState
                @title='No tasks defined yet'
                @texture={{false}}
                @size='s'
              />
            {{/if}}
          </div>
        </article>
      </IsoFrame>
      <style scoped>
        .template-isolated {
          height: 100%;
          overflow-y: auto;
          display: flex;
          flex-direction: column;
          background: var(--card);
          color: var(--card-foreground);
        }
        .header {
          flex: none;
          padding: var(--boxel-sp-lg);
          border-bottom: 1px solid var(--border);
        }
        .header-content {
          max-width: 100%;
        }
        h1 {
          font-size: var(--boxel-font-size-xl);
          font-weight: 750;
          letter-spacing: -0.02em;
          line-height: 1.2;
          overflow-wrap: break-word;
        }
        .description {
          margin: var(--boxel-sp-xs) 0 0;
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
          line-height: 1.6;
        }
        .body {
          flex: 1;
          padding: var(--boxel-sp-lg);
          min-width: 0;
          overflow-y: auto;
        }
        .section-title {
          margin: 0 0 var(--boxel-sp-sm);
          font-size: var(--boxel-font-size-sm);
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.05em;
          color: var(--muted-foreground);
        }
        .task-list {
          list-style: none;
          margin: 0;
          padding: 0;
          border: 1px solid var(--border);
          border-radius: var(--boxel-border-radius);
          overflow: hidden;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='template-embedded'>
        <span class='template-name'>{{@model.title}}</span>
        {{#if @model.tasks.length}}
          <span class='template-count'>{{@model.tasks.length}} tasks</span>
        {{/if}}
      </div>
      <style scoped>
        .template-embedded {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          font-size: var(--boxel-font-size-xs);
          border: 1px solid var(--border);
          border-radius: var(--boxel-border-radius);
          background: var(--card);
        }
        .template-name {
          font-weight: 600;
          flex: 1;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .template-count {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
      </style>
    </template>
  };

  // tasks is containsMany, so it is safe to read in prerendered fitted
  static fitted = class Fitted extends Component<typeof this> {
    get taskCount() {
      let n = this.args.model?.tasks?.length ?? 0;
      return n === 1 ? '1 task' : `${n} tasks`;
    }
    <template>
      <RichFittedCard>
        <:avatar><ChecklistIcon class='mark' aria-hidden='true' /></:avatar>
        <:title>{{@model.title}}</:title>
        <:subtitle>{{this.taskCount}}</:subtitle>
        <:fact>{{@model.description}}</:fact>
        <:metric><Metric
            @value='{{@model.tasks.length}}'
            @label='Tasks'
          /></:metric>
        <:details>
          {{#each @model.tasks as |task|}}<Detail
              @label={{if task.assigneeRole task.assigneeRole 'Task'}}
              @value={{task.title}}
            />{{/each}}
        </:details>
      </RichFittedCard>
      <style scoped>
        .mark {
          inline-size: var(--pretui-avatar-size);
          block-size: var(--pretui-avatar-size);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='template-atom'>
        <span class='template-atom-name'>{{@model.title}}</span>
      </span>
      <style scoped>
        .template-atom {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-2xs);
          font-size: var(--boxel-font-size-xs);
          font-weight: 500;
          color: var(--foreground);
        }
        .template-atom-name {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };
}
