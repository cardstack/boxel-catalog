import {
  CardDef,
  FieldDef,
  Component,
  field,
  contains,
  containsMany,
  linksTo,
  StringField,
  type BaseDefComponent,
} from '@cardstack/base/card-api';
import DateField from '@cardstack/base/date';
import TextAreaField from '@cardstack/base/text-area';
import enumField from '@cardstack/base/enum';
import ChecklistIcon from '@cardstack/boxel-icons/checklist';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { ProgressBar } from '@cardstack/pretui/components/progress-bar';

import { Employee } from '@cardstack/catalog/cards/hr/employee';
import { Contractor } from './contractor';
import { OnboardingTemplate } from './onboarding-template';
import { StatePill, type Hue } from '@cardstack/catalog/components/state-pill';
import { COMPACT_EMPTY_STYLE } from '@cardstack/catalog/components/pretui-helpers';
import { AVATAR_HUE, QUIET_AVATAR_HUE, hueOf, stateColorsOf } from './hr-ui';

export const ONBOARDING_CHECKLIST_STATUSES = [
  'not-started',
  'in-progress',
  'complete',
];

export const ONBOARDING_CHECKLIST_STATUS_LABELS: Record<string, string> = {
  'not-started': 'Not Started',
  'in-progress': 'In Progress',
  complete: 'Complete',
};

export const ONBOARDING_CHECKLIST_STATUS_HUES: Record<string, Hue> = {
  'not-started': 'slate',
  'in-progress': 'amber',
  complete: 'green',
};

export const ONBOARDING_CHECKLIST_STATUS_COLORS = stateColorsOf(
  ONBOARDING_CHECKLIST_STATUS_HUES,
);

const TASK_STATUS_OPTIONS = [
  { value: 'pending', label: 'Pending' },
  { value: 'in-progress', label: 'In progress' },
  { value: 'complete', label: 'Complete' },
];

const TASK_STATUS_HUES: Record<string, Hue> = {
  pending: 'slate',
  'in-progress': 'amber',
  complete: 'green',
};

function taskStatusLabel(status?: string | null): string {
  return (
    TASK_STATUS_OPTIONS.find((o) => o.value === status)?.label ?? status ?? ''
  );
}

export const OnboardingChecklistStatusField = enumField(StringField, {
  options: ONBOARDING_CHECKLIST_STATUSES.map((status) => ({
    value: status,
    label: ONBOARDING_CHECKLIST_STATUS_LABELS[status],
  })),
  displayName: 'Onboarding Checklist Status',
});

// One task in an OnboardingChecklist — tracking completion state for a
// templated task instance. The dueDate is computed ONCE, at checklist
// creation time, from the template's duration offset + checklist.createdDate
// (see create-onboarding-checklist-command.gts) — it is stored, not
// computeVia, because a FieldDef cannot see its containing checklist.
export class OnboardingChecklistTaskField extends FieldDef {
  static displayName = 'Onboarding Checklist Task';

  @field title = contains(StringField);
  @field dueDate = contains(DateField, {
    description:
      'Due date, computed once at checklist creation from the template task offset + checklist creation date',
  });
  @field assignee = linksTo(() => Employee);
  @field status = contains(
    enumField(StringField, {
      options: TASK_STATUS_OPTIONS,
      displayName: 'Task Status',
    }),
  );
  @field completedDate = contains(DateField);
  @field notes = contains(TextAreaField);

  static embedded: BaseDefComponent = class Embedded extends Component<
    typeof this
  > {
    <template>
      <div class='task-card'>
        <div class='task-top'>
          <span class='task-title'>{{@model.title}}</span>
          {{#if @model.status}}
            <StatePill
              @label={{taskStatusLabel @model.status}}
              @hue={{hueOf TASK_STATUS_HUES @model.status}}
              @dot={{true}}
            />
          {{/if}}
        </div>
        {{#if @model.assignee}}
          <div class='task-meta'>
            <span class='meta-label'>Assigned to:</span>
            <@fields.assignee @format='atom' @displayContainer={{false}} />
          </div>
        {{/if}}
        {{#if @model.dueDate}}
          <div class='task-meta'>
            <span class='meta-label'>Due:</span>
            <@fields.dueDate @format='atom' @displayContainer={{false}} />
          </div>
        {{/if}}
        {{#if @model.notes}}
          <p class='task-notes'>{{@model.notes}}</p>
        {{/if}}
      </div>
      <style scoped>
        .task-card {
          display: flex;
          flex-direction: column;
          gap: 0.5rem;
          padding: var(--boxel-sp-sm);
          border: 1px solid var(--border);
          border-radius: var(--boxel-border-radius);
          background: var(--card);
        }
        .task-top {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: var(--boxel-sp-xs);
        }
        .task-title {
          font-weight: 600;
          font-size: var(--boxel-font-size-sm);
          flex: 1;
          min-width: 0;
        }
        .task-meta {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          font-size: var(--boxel-font-size-xs);
        }
        .meta-label {
          color: var(--muted-foreground);
          font-weight: 600;
          flex: none;
        }
        .task-notes {
          margin: 0;
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
          line-height: 1.5;
        }
      </style>
    </template>
  };
}

// Instance of an onboarding checklist — tracks completion status for tasks
// from a template, linked to either an Employee or Contractor.
function statusLabel(status?: string | null) {
  return ONBOARDING_CHECKLIST_STATUS_LABELS[status ?? ''] ?? status;
}

export class OnboardingChecklist extends CardDef {
  static displayName = 'Onboarding Checklist';
  static icon = ChecklistIcon;

  // One-directional by design — a deliberate live-query choice over a
  // linksToMany back-reference on Employee, matching PtoRequest's employee link.
  @field employee = linksTo(() => Employee);
  @field contractor = linksTo(() => Contractor);
  @field template = linksTo(() => OnboardingTemplate);
  @field tasks = containsMany(OnboardingChecklistTaskField);
  @field status = contains(OnboardingChecklistStatusField, {
    computeVia: function (this: OnboardingChecklist) {
      let taskList = this.tasks ?? [];
      let completedCount = taskList.filter(
        (t) => t && t.status === 'complete',
      ).length;
      if (taskList.length === 0) {
        return 'not-started';
      }
      if (completedCount === taskList.length) {
        return 'complete';
      }
      return 'in-progress';
    },
  });
  @field createdDate = contains(DateField);
  @field completedDate = contains(DateField);

  // Denormalized for fitted — prerendered fitted does not resolve linksTo,
  // so the fitted view reads this instead of walking employee/contractor.
  // (computeVia runs at index time, when the links ARE loaded.)
  @field personName = contains(StringField, {
    computeVia: function (this: OnboardingChecklist) {
      return this.employee?.name ?? this.contractor?.name ?? '';
    },
  });

  @field title = contains(StringField, {
    computeVia: function (this: OnboardingChecklist) {
      let person = this.employee || this.contractor;
      if (person) {
        return `${person.name}'s Onboarding`;
      }
      if (this.createdDate) {
        let date = new Date(this.createdDate);
        let formatted = date.toLocaleDateString('en-US', {
          month: 'short',
          day: 'numeric',
        });
        return `Team Onboarding — Started ${formatted}`;
      }
      return 'Unnamed Onboarding';
    },
  });

  static isolated: BaseDefComponent = class Isolated extends Component<
    typeof this
  > {
    get personName() {
      return (
        this.args.model?.employee?.name ||
        this.args.model?.contractor?.name ||
        'Unknown'
      );
    }

    get hasPerson() {
      return Boolean(this.args.model?.employee || this.args.model?.contractor);
    }

    get personPhoto() {
      return (
        this.args.model?.employee?.photo?.resolvedUrl ??
        this.args.model?.contractor?.photo?.resolvedUrl
      );
    }

    get progressCount() {
      return `${this.completedTaskCount} of ${this.args.model?.tasks?.length ?? 0} tasks`;
    }

    get completedTaskCount(): number {
      let tasks = this.args.model?.tasks ?? [];
      return tasks.filter((t) => t && t.status === 'complete').length;
    }

    <template>
      <article class='checklist-isolated'>
        <header class='header'>
          <div class='header-top'>
            {{#if this.hasPerson}}
              <Avatar
                @name={{this.personName}}
                @src={{this.personPhoto}}
                @hue={{AVATAR_HUE}}
                @size={{52}}
                aria-hidden='true'
              />
            {{/if}}
            <div class='header-text'>
              <h1>{{this.personName}}</h1>
              <StatePill
                @label={{statusLabel @model.status}}
                @hue={{hueOf ONBOARDING_CHECKLIST_STATUS_HUES @model.status}}
                @dot={{true}}
              />
            </div>
          </div>
        </header>

        <div class='body'>
          {{#if @model.tasks.length}}
            <ProgressBar
              class='progress-section'
              @value={{this.completedTaskCount}}
              @max={{@model.tasks.length}}
              @label='Progress'
              @count={{this.progressCount}}
              @hue='var(--success)'
            />

            <div class='tasks-section'>
              <h2 class='section-title'>Tasks</h2>
              <ul class='tasks-list'>
                <@fields.tasks @format='embedded' />
              </ul>
            </div>
          {{else}}
            <EmptyState
              @title='No tasks in this checklist'
              @texture={{false}}
              style={{COMPACT_EMPTY_STYLE}}
            />
          {{/if}}
        </div>
      </article>
      <style scoped>
        .checklist-isolated {
          height: 100%;
          display: flex;
          flex-direction: column;
          background: var(--background);
          color: var(--foreground);
        }
        .header {
          flex: none;
          padding: var(--boxel-sp-lg);
          border-bottom: 1px solid var(--border);
        }
        .header-top {
          display: flex;
          align-items: flex-start;
          gap: var(--boxel-sp-sm);
        }
        .header-text {
          flex: 1;
          min-width: 0;
          display: flex;
          flex-direction: column;
          align-items: flex-start;
          gap: 0.5rem;
        }
        h1 {
          margin: 0;
          font-size: var(--boxel-font-size-xl);
          font-weight: 750;
          line-height: 1.2;
          overflow-wrap: anywhere;
        }
        .body {
          flex: 1;
          padding: var(--boxel-sp-lg);
          min-width: 0;
          overflow-y: auto;
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-lg);
        }
        .progress-section {
          padding: var(--boxel-sp-sm);
          background: var(--card);
          border: 1px solid var(--border);
          border-radius: var(--boxel-border-radius);
        }
        .tasks-section {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-sm);
        }
        .section-title {
          margin: 0;
          font-size: var(--boxel-font-size-sm);
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.05em;
          color: var(--muted-foreground);
        }
        .tasks-list {
          list-style: none;
          margin: 0;
          padding: 0;
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-sm);
        }
      </style>
    </template>
  };

  static embedded: BaseDefComponent = class Embedded extends Component<
    typeof this
  > {
    get personName() {
      return (
        this.args.model?.employee?.name ||
        this.args.model?.contractor?.name ||
        'Unknown'
      );
    }

    get completionPercentage(): number {
      let tasks = this.args.model?.tasks ?? [];
      if (tasks.length === 0) return 0;
      let completed = tasks.filter((t) => t && t.status === 'complete').length;
      return Math.round((completed / tasks.length) * 100);
    }

    get hasPerson() {
      return Boolean(this.args.model?.employee || this.args.model?.contractor);
    }

    get personPhoto() {
      return (
        this.args.model?.employee?.photo?.resolvedUrl ??
        this.args.model?.contractor?.photo?.resolvedUrl
      );
    }

    <template>
      <div class='checklist-embedded'>
        {{#if this.hasPerson}}
          <Avatar
            @name={{this.personName}}
            @src={{this.personPhoto}}
            @hue={{QUIET_AVATAR_HUE}}
            @size={{32}}
            aria-hidden='true'
          />
        {{/if}}
        <div class='content'>
          <span class='person-name'>{{this.personName}}</span>
          <div class='progress'>
            <ProgressBar
              class='progress-rail'
              @value={{this.completionPercentage}}
              @hue='var(--success)'
              aria-label='Onboarding progress'
            />
            <span class='progress-text'>{{this.completionPercentage}}%</span>
          </div>
        </div>
      </div>
      <style scoped>
        .checklist-embedded {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-sm);
          padding: var(--boxel-sp-sm);
          border: 1px solid var(--border);
          border-radius: var(--boxel-border-radius);
          background: var(--card);
        }
        .content {
          flex: 1;
          min-width: 0;
          display: flex;
          flex-direction: column;
          gap: 0.25rem;
        }
        .person-name {
          font-weight: 600;
          font-size: var(--boxel-font-size-sm);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .progress {
          display: flex;
          align-items: center;
          gap: 0.3rem;
        }
        .progress-rail {
          flex: 1;
          min-width: 0;
        }
        .progress-text {
          font-size: var(--boxel-font-size-xs);
          font-weight: 700;
          color: var(--muted-foreground);
          flex: none;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static fitted: BaseDefComponent = class Fitted extends Component<
    typeof this
  > {
    // Reads the denormalized personName own-attribute — prerendered fitted
    // does not resolve linksTo, so walking employee/contractor here would
    // always render "Unknown".
    get personName() {
      return this.args.model?.personName || 'Onboarding';
    }

    // tasks is containsMany — its data lives on the instance itself, so it
    // is safe to read in prerendered fitted (unlike linksTo/linksToMany).
    get completedTaskCount(): number {
      let tasks = this.args.model?.tasks ?? [];
      return tasks.filter((t) => t && t.status === 'complete').length;
    }

    get completionPercentage(): number {
      let tasks = this.args.model?.tasks ?? [];
      if (tasks.length === 0) return 0;
      return Math.round((this.completedTaskCount / tasks.length) * 100);
    }

    // First few task rows for tall cells — same containsMany-preview
    // treatment onboarding-template's fitted uses.
    get previewTasks() {
      return (this.args.model?.tasks ?? []).slice(0, 4);
    }

    get moreCount(): number {
      let n = this.args.model?.tasks?.length ?? 0;
      return Math.max(0, n - 4);
    }

    <template>
      <article class='fit'>
        <div class='fit-top'>
          <div class='fit-head'>
            <h3 class='fit-name'>{{this.personName}}</h3>
          </div>
          <span class='fit-pct'>{{this.completionPercentage}}%</span>
          {{#if @model.status}}
            <StatePill
              class='fit-pill'
              @label={{statusLabel @model.status}}
              @hue={{hueOf ONBOARDING_CHECKLIST_STATUS_HUES @model.status}}
              @dot={{true}}
            />
          {{/if}}
        </div>

        <div class='fit-mid'>
          <span class='fit-sub'>{{this.completedTaskCount}}
            of
            {{@model.tasks.length}}
            tasks complete</span>
        </div>

        {{#if this.previewTasks.length}}
          <ul class='fit-tasks'>
            {{#each this.previewTasks as |task|}}
              <li
                class='fit-task {{if (eq task.status "complete") "done"}}'
              ><span class='fit-tick'>{{if
                    (eq task.status 'complete')
                    '✓'
                    '○'
                  }}</span>{{task.title}}</li>
            {{/each}}
            {{#if this.moreCount}}
              <li class='fit-task fit-more'>+{{this.moreCount}} more</li>
            {{/if}}
          </ul>
        {{/if}}

        <div class='fit-add'>
          <ProgressBar
            @value={{this.completionPercentage}}
            @hue='var(--success)'
            aria-label='Onboarding progress'
          />
        </div>
      </article>
      <style scoped>
        /* Four tiers, each ADDING content. 11px floor. Percent never hidden. */
        .fit {
          height: 100%;
          display: flex;
          flex-direction: column;
          gap: 0.28rem;
          padding: 0.55rem 0.6rem;
          overflow: hidden;
          background: var(--card);
          color: var(--card-foreground);
          font-family: var(--font-sans);
          --fit-name: clamp(11px, 3.2cqi, 15px);
          --fit-small: clamp(11px, 2.6cqi, 12px);
        }
        .fit > * {
          min-height: 0;
          overflow: hidden;
        }
        .fit-top {
          flex: none;
          display: flex;
          align-items: flex-start;
          gap: 0.4rem;
          flex-wrap: wrap;
        }
        .fit-head {
          flex: 1;
          min-width: 0;
        }
        .fit-name {
          margin: 0;
          font-size: var(--fit-name);
          font-weight: 700;
          line-height: 1.25;
          letter-spacing: -0.01em;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
          overflow: hidden;
        }
        .fit-pct {
          flex: none;
          font-size: var(--fit-name);
          font-weight: 800;
          letter-spacing: -0.02em;
          font-variant-numeric: tabular-nums;
          color: var(--card-foreground);
        }
        .fit-pill {
          flex: none;
          align-self: flex-start;
          display: none;
        }
        .fit-mid {
          flex: none;
          display: none;
          flex-direction: column;
          gap: 1px;
        }
        .fit-sub {
          font-size: var(--fit-small);
          color: var(--muted-foreground);
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .fit-tasks {
          display: none;
          list-style: none;
          margin: 0;
          padding: 0.3rem 0 0;
          border-top: 1px dashed var(--border);
        }
        .fit-task {
          font-size: var(--fit-small);
          font-weight: 600;
          line-height: 1.5;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .fit-tick {
          margin-right: 0.35em;
          color: var(--muted-foreground);
        }
        .fit-task.done .fit-tick {
          color: var(--card-foreground);
        }
        .fit-more {
          font-weight: 400;
          color: var(--muted-foreground);
        }
        .fit-add {
          display: none;
          margin-top: auto;
          padding-top: 0.3rem;
        }
        /* Same bar style the embedded format uses. */

        /* TIER 2 — status pill joins above the 50px strip. */
        @container fitted-card (height > 50px) {
          .fit-pill {
            display: inline-flex;
          }
        }
        /* TIER 3 — task tally line. */
        @container fitted-card (height > 80px) {
          .fit-mid {
            display: flex;
          }
        }
        @container fitted-card (width > 240px) and (height > 50px) {
          .fit-mid {
            display: flex;
          }
        }
        /* TIER 4 — progress bar pinned to the bottom edge. */
        @container fitted-card (height > 130px) and (width >= 170px) {
          .fit-add {
            display: block;
          }
        }
        /* TIER 5 — first task rows on tall cells (Full Card, Expanded). */
        @container fitted-card (height >= 170px) and (width >= 170px) {
          .fit-tasks {
            display: block;
          }
        }
        /* Short strip: horizontal, single-line name. */
        @container fitted-card (height <= 90px) {
          .fit-top {
            align-items: center;
            flex-wrap: nowrap;
          }
          .fit-pill {
            align-self: center;
          }
          .fit-name {
            -webkit-line-clamp: 1;
          }
        }
      </style>
    </template>
  };

  static atom: BaseDefComponent = class Atom extends Component<typeof this> {
    get personName() {
      return (
        this.args.model?.employee?.name ||
        this.args.model?.contractor?.name ||
        'Unknown'
      );
    }

    <template>
      <span class='checklist-atom'>
        <span class='atom-name'>{{this.personName}}</span>
        <StatePill
          @label={{statusLabel @model.status}}
          @hue={{hueOf ONBOARDING_CHECKLIST_STATUS_HUES @model.status}}
        />
      </span>
      <style scoped>
        .checklist-atom {
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
          font-size: 0.8125rem;
          font-weight: 500;
          color: var(--foreground);
        }
        .atom-name {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };
}
