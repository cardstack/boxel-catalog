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
import type { TemplateOnlyComponent } from '@ember/component/template-only';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Avatar } from '../../ui-component/components/avatar';
import {
  Descriptions,
  type DescriptionsItem,
} from '../../ui-component/components/descriptions';
import { EmptyState } from '../../ui-component/components/empty-state';
import { Panel } from '../../ui-component/components/panel';
import { Stat } from '../../ui-component/components/stat';

import { Employee } from './employee';
import { Contractor } from './contractor';
import { OnboardingTemplate } from './onboarding-template';
import { StatePill, type Hue } from '@cardstack/catalog/components/state-pill';
import type { PretuiToneArg } from '../../ui-component/pretui-primitives';
import { FitTile } from '../../ui-component/components/fit-tile';
import {
  AVATAR_HUE,
  COMPACT_EMPTY_STYLE,
} from '@cardstack/catalog/components/pretui-helpers';
import { hueOf, stateColorsOf } from './hr-ui';

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

const ONBOARDING_CHECKLIST_STATUS_TONES: Record<string, PretuiToneArg> = {
  'not-started': 'neutral',
  'in-progress': 'warning',
  complete: 'success',
};

export function statusTone(status?: string | null): PretuiToneArg {
  return (status && ONBOARDING_CHECKLIST_STATUS_TONES[status]) || 'neutral';
}

export function statusLabel(status?: string | null): string {
  return (status && ONBOARDING_CHECKLIST_STATUS_LABELS[status]) || '—';
}

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

type DateLike = Date | string | null | undefined;

/** "Aug 6" */
function shortDate(date: DateLike): string {
  return date
    ? new Date(date).toLocaleDateString('en-US', {
        month: 'short',
        day: 'numeric',
      })
    : '';
}

/** "Aug 6, 2026" */
function longDate(date: DateLike): string {
  return date
    ? new Date(date).toLocaleDateString('en-US', {
        month: 'short',
        day: 'numeric',
        year: 'numeric',
      })
    : '';
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

  // One list row: title, "Due Aug 2 · done Aug 4 · <assignee>", state.
  static embedded: BaseDefComponent = class Embedded extends Component<
    typeof this
  > {
    get dateLine() {
      let { dueDate, completedDate } = this.args.model ?? {};
      return [
        dueDate && `Due ${shortDate(dueDate)}`,
        completedDate && `done ${shortDate(completedDate)}`,
      ]
        .filter(Boolean)
        .join(' · ');
    }

    <template>
      <div class='task-row'>
        <div class='task-text'>
          <span class='task-title'>{{@model.title}}</span>
          <span class='task-sub'>{{this.dateLine}}{{#if @model.assignee}}{{#if
                this.dateLine
              }} · {{/if}}<@fields.assignee
                @format='atom'
                @displayContainer={{false}}
              />{{/if}}</span>
        </div>
        {{#if @model.status}}
          <StatePill
            @label={{taskStatusLabel @model.status}}
            @hue={{hueOf TASK_STATUS_HUES @model.status}}
            @dot={{true}}
          />
        {{/if}}
      </div>
      <style scoped>
        @layer PretComponent {
          .task-row {
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: var(--boxel-sp-sm);
          }
          .task-text {
            flex: 1;
            min-width: 0;
            display: flex;
            flex-direction: column;
            gap: var(--boxel-sp-6xs);
          }
          .task-title {
            font-size: var(--boxel-font-size-sm);
            font-weight: 600;
            overflow-wrap: anywhere;
          }
          .task-sub {
            display: flex;
            flex-wrap: wrap;
            align-items: center;
            gap: 0 var(--boxel-sp-4xs);
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
        }
      </style>
    </template>
  };
}

// Every format reads the same counts off `tasks`. tasks is containsMany, so
// its data lives on the instance and is safe to read in prerendered fitted.
function summarize(tasks?: (OnboardingChecklistTaskField | null)[] | null) {
  let list = (tasks ?? []).filter((t): t is OnboardingChecklistTaskField =>
    Boolean(t),
  );
  let done = list.filter((t) => t.status === 'complete').length;
  let inProgress = list.filter((t) => t.status === 'in-progress').length;
  return {
    total: list.length,
    done,
    inProgress,
    pending: list.length - done - inProgress,
    pct: list.length ? Math.round((done / list.length) * 100) : 0,
    next: list.find((t) => t.status !== 'complete'),
    progress: `${done} / ${list.length}`,
  };
}

/** "Engineering Onboarding · started Aug 1" */
function subline(templateTitle?: string | null, createdDate?: DateLike) {
  return [templateTitle, createdDate && `started ${shortDate(createdDate)}`]
    .filter(Boolean)
    .join(' · ');
}

type ChecklistSummary = ReturnType<typeof summarize>;

interface FitPillsSignature {
  Args: { status?: string | null; summary: ChecklistSummary };
}

// The fitted views' state: the checklist status, then "3 / 7 done". Under
// 250 wide only the status keeps its place.
const FitPills: TemplateOnlyComponent<FitPillsSignature> = <template>
  {{#if @status}}
    <StatePill
      @label={{statusLabel @status}}
      @hue={{hueOf ONBOARDING_CHECKLIST_STATUS_HUES @status}}
      @dot={{true}}
    />
  {{/if}}
  {{#if @summary.total}}
    <span class='progress-pill'><StatePill
        @label='{{@summary.progress}} done'
      /></span>
  {{/if}}
  <style scoped>
    @layer PretComponent {
      .progress-pill {
        display: inline-flex;
        min-width: 0;
      }
      @container fitted-card (width < 250px) or (height < 65px) {
        .progress-pill {
          display: none;
        }
      }
    }
  </style>
</template>;

interface NextFactSignature {
  Args: { summary: ChecklistSummary };
}

function allDone(summary: ChecklistSummary) {
  return summary.total > 0 && summary.done === summary.total;
}

/** "Next: First sprint planning · due Aug 6" */
const NextFact: TemplateOnlyComponent<NextFactSignature> = <template>
  {{#if @summary.next}}Next:
    <strong class='fact-strong'>{{@summary.next.title}}</strong>{{#if
      @summary.next.dueDate
    }}
      · due
      {{shortDate @summary.next.dueDate}}{{/if}}{{else if
    (allDone @summary)
  }}All tasks complete{{/if}}
  <style scoped>
    @layer PretComponent {
      .fact-strong {
        font-weight: 600;
        color: var(--foreground);
      }
    }
  </style>
</template>;

// Instance of an onboarding checklist — tracks completion status for tasks
// from a template, linked to either an Employee or Contractor.
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
      let taskList = (this.tasks ?? []).filter(Boolean);
      let completedCount = taskList.filter(
        (t) => t.status === 'complete',
      ).length;
      if (taskList.length && completedCount === taskList.length) {
        return 'complete';
      }
      let started =
        completedCount > 0 || taskList.some((t) => t.status === 'in-progress');
      return started ? 'in-progress' : 'not-started';
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
        return `Team Onboarding — Started ${shortDate(this.createdDate)}`;
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

    get personPhoto() {
      return (
        this.args.model?.employee?.photo?.resolvedUrl ??
        this.args.model?.contractor?.photo?.resolvedUrl
      );
    }

    get summary() {
      return summarize(this.args.model?.tasks);
    }

    get subline() {
      return subline(
        this.args.model?.template?.title,
        this.args.model?.createdDate,
      );
    }

    get linked(): DescriptionsItem[] {
      let m = this.args.model;
      return [
        m?.employee && { label: 'Employee', key: 'employee' },
        m?.contractor && { label: 'Contractor', key: 'contractor' },
        m?.template && { label: 'Template', key: 'template' },
      ].filter((i): i is { label: string; key: string } => Boolean(i));
    }

    get details(): DescriptionsItem[] {
      let s = this.summary;
      let m = this.args.model;
      return [
        { label: 'Progress', value: `${s.done} of ${s.total} tasks` },
        { label: 'Next task', value: s.next?.title ?? undefined },
        { label: 'Due', value: longDate(s.next?.dueDate) || undefined },
        { label: 'Created', value: longDate(m?.createdDate) || undefined },
        { label: 'Template', value: m?.template?.title ?? undefined },
        { label: 'In progress', value: String(s.inProgress) },
        { label: 'Pending', value: String(s.pending) },
      ];
    }

    get startedYear() {
      let d = this.args.model?.createdDate;
      return d ? String(new Date(d).getFullYear()) : undefined;
    }

    <template>
      <article class='checklist-isolated'>
        <header class='iso-head'>
          <Avatar
            @name={{this.personName}}
            @src={{this.personPhoto}}
            @hue={{AVATAR_HUE}}
            @size={{48}}
            aria-hidden='true'
          />
          <div class='iso-id'>
            <h1>{{@model.title}}</h1>
            {{#if this.subline}}<p class='iso-sub'>{{this.subline}}</p>{{/if}}
          </div>
          <div class='chips'>
            <StatePill
              @label={{statusLabel @model.status}}
              @hue={{hueOf ONBOARDING_CHECKLIST_STATUS_HUES @model.status}}
              @dot={{true}}
            />
            {{#if this.summary.total}}
              <StatePill @label='{{this.summary.progress}} done' />
            {{/if}}
          </div>
        </header>

        {{#if this.summary.total}}
          <div class='stat-row'>
            <div class='stat-tile'><Stat
                @label='Progress'
                @value={{this.summary.progress}}
                @hint='{{this.summary.pct}}% complete'
                @roll={{false}}
              /></div>
            <div class='stat-tile'><Stat
                @label='Next due'
                @value={{if
                  this.summary.next.dueDate
                  (shortDate this.summary.next.dueDate)
                  '—'
                }}
                @hint={{if
                  this.summary.next
                  this.summary.next.title
                  'All tasks complete'
                }}
                @roll={{false}}
              /></div>
            <div class='stat-tile'><Stat
                @label='Started'
                @value={{if
                  @model.createdDate
                  (shortDate @model.createdDate)
                  '—'
                }}
                @hint={{this.startedYear}}
                @roll={{false}}
              /></div>
          </div>
        {{/if}}

        <div class='iso-body'>
          <Panel @title='Tasks'>
            {{#if this.summary.total}}
              <ul class='task-list'>
                {{#each @fields.tasks as |Task|}}
                  <li><Task @format='embedded' /></li>
                {{/each}}
              </ul>
            {{else}}
              <EmptyState
                @title='No tasks in this checklist'
                @texture={{false}}
                style={{COMPACT_EMPTY_STYLE}}
              />
            {{/if}}
          </Panel>
          <div class='iso-side'>
            {{#if this.linked.length}}
              <Panel @title='Linked'>
                <Descriptions
                  @items={{this.linked}}
                  @columns={{1}}
                  @layout='horizontal'
                >
                  <:value as |item|>
                    {{#if (eq item.key 'employee')}}
                      <@fields.employee
                        @format='atom'
                        @displayContainer={{false}}
                      />
                    {{else if (eq item.key 'contractor')}}
                      <@fields.contractor
                        @format='atom'
                        @displayContainer={{false}}
                      />
                    {{else}}
                      <@fields.template
                        @format='atom'
                        @displayContainer={{false}}
                      />
                    {{/if}}
                  </:value>
                </Descriptions>
              </Panel>
            {{/if}}
            <Panel @title='Details'>
              <Descriptions
                class='details'
                @items={{this.details}}
                @columns={{1}}
                @layout='horizontal'
              />
            </Panel>
          </div>
        </div>
      </article>
      <style scoped>
        @layer PretComponent {
          .checklist-isolated {
            container-type: inline-size;
            min-height: 100%;
            display: flex;
            flex-direction: column;
            gap: var(--boxel-sp-lg);
            padding: var(--boxel-sp-lg);
            background: var(--background);
            color: var(--foreground);
          }
          .iso-head {
            display: flex;
            align-items: center;
            flex-wrap: wrap;
            gap: var(--boxel-sp);
          }
          .iso-id {
            flex: 1 1 0;
            min-width: 0;
          }
          h1 {
            margin: 0;
            font-size: var(--boxel-font-size-lg);
            font-weight: 600;
            line-height: 1.25;
            color: var(--primary);
            overflow-wrap: anywhere;
          }
          .iso-sub {
            margin: var(--boxel-sp-6xs) 0 0;
            font-size: var(--boxel-font-size-sm);
            color: var(--muted-foreground);
          }
          .chips {
            display: flex;
            flex-wrap: wrap;
            gap: var(--boxel-sp-4xs);
          }
          .stat-row {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(10.5rem, 1fr));
            gap: var(--boxel-sp);
          }
          .stat-tile {
            padding: var(--boxel-sp);
            border-radius: var(--boxel-border-radius);
            background: var(--card);
            box-shadow: var(--shadow-md);
          }
          .iso-body {
            display: grid;
            grid-template-columns: minmax(0, 2fr) minmax(15rem, 1fr);
            align-items: start;
            gap: var(--boxel-sp-lg);
          }
          .iso-side {
            display: flex;
            flex-direction: column;
            gap: var(--boxel-sp-lg);
            min-width: 0;
          }
          .task-list {
            list-style: none;
            margin: 0;
            padding: 0;
          }
          .task-list > li {
            padding-block: var(--boxel-sp-sm);
          }
          .task-list > li + li {
            border-top: 1px solid var(--border);
          }
          .task-list > li:first-child {
            padding-top: 0;
          }
          .task-list > li:last-child {
            padding-bottom: 0;
          }
          .details {
            font-weight: 600;
            font-variant-numeric: tabular-nums;
          }
          @container (width < 45rem) {
            .iso-body {
              grid-template-columns: minmax(0, 1fr);
            }
          }
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

    get personPhoto() {
      return (
        this.args.model?.employee?.photo?.resolvedUrl ??
        this.args.model?.contractor?.photo?.resolvedUrl
      );
    }

    get summary() {
      return summarize(this.args.model?.tasks);
    }

    get subline() {
      return subline(
        this.args.model?.template?.title,
        this.args.model?.createdDate,
      );
    }

    get facts(): DescriptionsItem[] {
      let s = this.summary;
      let m = this.args.model;
      return [
        { label: 'Progress', value: `${s.done} of ${s.total} tasks` },
        { label: 'Next task', value: s.next?.title ?? undefined },
        { label: 'Due', value: longDate(s.next?.dueDate) || undefined },
        { label: 'Created', value: longDate(m?.createdDate) || undefined },
        { label: 'Template', value: m?.template?.title ?? undefined },
        { label: 'In progress', value: String(s.inProgress) },
      ];
    }

    <template>
      <article class='checklist-embedded'>
        <div class='emb'>
          <header class='emb-head'>
            <Avatar
              @name={{this.personName}}
              @src={{this.personPhoto}}
              @hue={{AVATAR_HUE}}
              @size={{40}}
              aria-hidden='true'
            />
            <div class='emb-id'>
              <h3 class='emb-title'>{{@model.title}}</h3>
              {{#if this.subline}}<p class='emb-sub'>{{this.subline}}</p>{{/if}}
            </div>
            <div class='emb-chips'>
              <StatePill
                @label={{statusLabel @model.status}}
                @hue={{hueOf ONBOARDING_CHECKLIST_STATUS_HUES @model.status}}
                @dot={{true}}
              />
              {{#if this.summary.total}}
                <StatePill @label='{{this.summary.progress}} done' />
              {{/if}}
            </div>
          </header>
          {{#if this.summary.next}}
            <p class='emb-fact'>Next:
              <strong>{{this.summary.next.title}}</strong>{{#if
                this.summary.next.dueDate
              }}
                · due
                {{shortDate this.summary.next.dueDate}}{{/if}}</p>
          {{/if}}
          {{#if this.summary.total}}
            <Descriptions
              class='emb-kv'
              @items={{this.facts}}
              @columns={{3}}
              @layout='vertical'
            />
          {{/if}}
          <div class='emb-rels'>
            {{#if @model.employee}}
              <span class='rel'>Employee
                <@fields.employee
                  @format='atom'
                  @displayContainer={{false}}
                /></span>
            {{/if}}
            {{#if @model.contractor}}
              <span class='rel'>Contractor
                <@fields.contractor
                  @format='atom'
                  @displayContainer={{false}}
                /></span>
            {{/if}}
            {{#if @model.template}}
              <span class='rel'>Template
                <@fields.template
                  @format='atom'
                  @displayContainer={{false}}
                /></span>
            {{/if}}
          </div>
        </div>
      </article>
      <style scoped>
        @layer PretComponent {
          .checklist-embedded {
            container-type: inline-size;
          }
          .emb {
            display: flex;
            flex-direction: column;
            gap: var(--boxel-sp-sm);
            padding: var(--boxel-sp);
            background: var(--card);
            color: var(--card-foreground);
          }
          .emb-head {
            display: flex;
            align-items: center;
            gap: var(--boxel-sp-sm);
          }
          .emb-id {
            flex: 1 1 0;
            min-width: 0;
          }
          .emb-title {
            margin: 0;
            font-size: var(--boxel-font-size-sm);
            font-weight: 600;
            line-height: 1.25;
            overflow-wrap: anywhere;
          }
          .emb-sub {
            margin: var(--boxel-sp-6xs) 0 0;
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          .emb-chips {
            display: flex;
            flex-wrap: wrap;
            justify-content: flex-end;
            gap: var(--boxel-sp-4xs);
          }
          .emb-fact {
            margin: 0;
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          .emb-fact strong {
            font-weight: 600;
            color: var(--foreground);
          }
          .emb-kv {
            padding-top: var(--boxel-sp-sm);
            border-top: 1px solid var(--border);
            font-weight: 600;
            font-variant-numeric: tabular-nums;
          }
          .emb-rels {
            display: flex;
            flex-wrap: wrap;
            gap: var(--boxel-sp-xs) var(--boxel-sp);
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          .emb-rels:empty {
            display: none;
          }
          .rel {
            display: inline-flex;
            align-items: center;
            gap: var(--boxel-sp-xs);
            min-width: 0;
            max-width: 100%;
          }
          @container (width < 25rem) {
            .emb-head {
              flex-wrap: wrap;
            }
            .emb-chips {
              flex-basis: 100%;
              justify-content: flex-start;
            }
          }
        }
      </style>
    </template>
  };

  // Under 170 tall the rows are FitTile's. From 170 tall the mockup's extra
  // rows (key facts, one relation per line, the stat strip) need a layout of
  // their own, so the tall view replaces FitTile there.
  static fitted: BaseDefComponent = class Fitted extends Component<
    typeof this
  > {
    // Reads the denormalized personName own-attribute — prerendered fitted
    // does not resolve linksTo, so walking employee/contractor here would
    // always render "Unknown".
    get personName() {
      return this.args.model?.personName || 'Onboarding';
    }

    get summary() {
      return summarize(this.args.model?.tasks);
    }

    get subline() {
      return subline(
        this.args.model?.template?.title,
        this.args.model?.createdDate,
      );
    }

    get startedLabel() {
      let d = this.args.model?.createdDate;
      return d ? shortDate(d) : '—';
    }

    get nextDueLabel() {
      let d = this.summary.next?.dueDate;
      return d ? shortDate(d) : '—';
    }

    // Each key fact names the sizes that show it: `narrow` is the 250-wide
    // large tile, `two` the 400 × 275 card's two columns; 445 tall shows all.
    get keyFacts() {
      let s = this.summary;
      let m = this.args.model;
      return [
        {
          key: 'Progress',
          value: `${s.done} of ${s.total} tasks`,
          narrow: true,
          two: true,
        },
        { key: 'Next task', value: s.next?.title || '—', narrow: true },
        { key: 'Due', value: longDate(s.next?.dueDate) || '—', two: true },
        { key: 'Created', value: longDate(m?.createdDate) || '—', two: true },
        { key: 'Template', value: m?.template?.title || '—' },
        { key: 'In progress', value: String(s.inProgress), two: true },
        { key: 'Pending', value: String(s.pending), two: true },
        {
          key: 'Completed',
          value: longDate(m?.completedDate) || '—',
          two: true,
        },
      ];
    }

    <template>
      <div class='fit-short'>
        <FitTile>
          <:avatar>
            <Avatar
              @name={{this.personName}}
              @hue={{AVATAR_HUE}}
              @size={{32}}
              aria-hidden='true'
            />
          </:avatar>
          <:title><span
              class='fit-title'
              role='heading'
              aria-level='3'
            >{{@model.title}}</span></:title>
          <:subtitle>{{this.subline}}</:subtitle>
          <:status><FitPills
              @status={{@model.status}}
              @summary={{this.summary}}
            /></:status>
          <:fact><NextFact @summary={{this.summary}} /></:fact>
          <:relations><@fields.employee @format='atom' />{{#if
              @model.contractor
            }}<@fields.contractor @format='atom' />{{/if}}<@fields.template
              @format='atom'
            /></:relations>
        </FitTile>
      </div>

      <article class='fit-tall'>
        <div class='who'>
          <span class='who-av'><Avatar
              @name={{this.personName}}
              @hue={{AVATAR_HUE}}
              aria-hidden='true'
            /></span>
          <div class='who-id'>
            <div class='line1'>
              <span
                class='fit-title'
                role='heading'
                aria-level='3'
              >{{@model.title}}</span>
              <span class='pills pills-inline'><FitPills
                  @status={{@model.status}}
                  @summary={{this.summary}}
                /></span>
            </div>
            {{#if this.subline}}
              <span class='sub'>{{this.subline}}</span>
            {{/if}}
          </div>
        </div>
        <div class='pills pills-row'><FitPills
            @status={{@model.status}}
            @summary={{this.summary}}
          /></div>
        <p class='fact'><NextFact @summary={{this.summary}} /></p>
        {{#if this.summary.total}}
          <div class='stats'>
            <Stat
              @label='Progress'
              @value={{this.summary.progress}}
              @roll={{false}}
            />
            <Stat
              @label='Next due'
              @value={{this.nextDueLabel}}
              @roll={{false}}
            />
            <Stat
              @label='Started'
              @value={{this.startedLabel}}
              @roll={{false}}
            />
          </div>
          <dl class='kv'>
            {{#each this.keyFacts as |f|}}
              <div
                class='kv-i {{if f.narrow "in-narrow"}} {{if f.two "in-two"}}'
              >
                <dt>{{f.key}}</dt>
                <dd>{{f.value}}</dd>
              </div>
            {{/each}}
          </dl>
        {{/if}}
        <ul class='rels'>
          {{#if @model.contractor}}
            <li><span class='k'>Contractor</span><@fields.contractor
                @format='atom'
              /></li>
          {{else}}
            <li><span class='k'>Employee</span><@fields.employee
                @format='atom'
              /></li>
          {{/if}}
          <li class='rel-2'><span class='k'>Template</span><@fields.template
              @format='atom'
            /></li>
        </ul>
      </article>
      <style scoped>
        @layer PretComponent {
          .fit-short {
            block-size: 100%;
          }
          .fit-title {
            display: block;
            margin: 0;
            min-width: 0;
            font-size: inherit;
            font-weight: inherit;
            line-height: inherit;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
          }

          /* ── 170 tall and up ─────────────────────────────────────── */
          .fit-tall {
            display: none;
            flex-direction: column;
            gap: var(--boxel-sp-xs);
            block-size: 100%;
            box-sizing: border-box;
            padding: var(--boxel-sp-sm);
            overflow: hidden;
            font-size: var(--boxel-font-size-xs);
            line-height: 1.5;
            color: var(--card-foreground);
          }
          .fit-tall > * {
            flex: none;
            min-width: 0;
          }
          .who {
            display: flex;
            align-items: center;
            gap: var(--boxel-sp-sm);
          }
          .who-av {
            --pretui-avatar-size: 2rem;
            display: inline-flex;
            flex: none;
          }
          .who-id {
            flex: 1 1 auto;
            min-width: 0;
            display: flex;
            flex-direction: column;
            gap: var(--boxel-sp-6xs);
          }
          .line1 {
            display: flex;
            align-items: center;
            gap: var(--boxel-sp-xs);
            min-width: 0;
          }
          .line1 .fit-title {
            flex: 1 1 auto;
            min-width: 7rem;
            font-size: var(--boxel-font-size-sm);
            font-weight: 600;
          }
          .sub {
            color: var(--muted-foreground);
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
          }
          .pills {
            display: flex;
            flex-wrap: wrap;
            align-items: center;
            gap: var(--boxel-sp-4xs);
            min-width: 0;
            max-block-size: 1.375rem;
            overflow: hidden;
          }
          .pills-inline {
            display: none;
            flex: 0 1 auto;
          }
          .fact {
            margin: 0;
            color: var(--muted-foreground);
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
          }
          .stats {
            display: none;
            grid-template-columns: repeat(3, minmax(0, 1fr));
            gap: var(--boxel-sp-sm);
            overflow: hidden;
          }
          .kv {
            display: none;
            grid-template-columns: minmax(0, 1fr);
            gap: var(--boxel-sp-4xs) var(--boxel-sp-sm);
            margin: 0;
          }
          .kv-i {
            display: none;
            justify-content: space-between;
            gap: var(--boxel-sp-xs);
            min-width: 0;
          }
          .kv-i dt {
            flex: none;
            color: var(--muted-foreground);
          }
          .kv-i dd {
            margin: 0;
            min-width: 0;
            font-weight: 600;
            text-align: right;
            font-variant-numeric: tabular-nums;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
          }
          .rels {
            list-style: none;
            margin: 0;
            padding: 0;
            display: flex;
            flex-direction: column;
            gap: var(--boxel-sp-4xs);
          }
          .rels li {
            display: flex;
            align-items: center;
            gap: var(--boxel-sp-xs);
            min-width: 0;
            max-block-size: 1.375rem;
            line-height: 1.375rem;
            overflow: hidden;
          }
          .rels .k {
            flex: none;
            color: var(--muted-foreground);
          }
          .rels .rel-2 {
            display: none;
          }

          @container fitted-card (height >= 170px) {
            .fit-short {
              display: none;
            }
            .fit-tall {
              display: flex;
            }
          }
          /* under 250 wide: no avatar, no relation labels */
          @container fitted-card (width < 250px) {
            .who-av,
            .rels .k {
              display: none;
            }
          }
          /* 400 wide: state beside the title, two relations */
          @container fitted-card (width >= 400px) {
            .pills-inline {
              display: flex;
            }
            .pills-row {
              display: none;
            }
          }
          @container fitted-card (height >= 250px) or (width >= 400px) {
            .rels .rel-2 {
              display: flex;
            }
          }
          /* the template chip cannot shrink or ellipsise, so it stays out of
             tiles narrower than 250 rather than show half of it */
          @container fitted-card (width < 250px) {
            .rels .rel-2 {
              display: none;
            }
          }
          /* 250 tall and up: roomier padding, a 40 avatar; narrow tiles
             stack it above the title */
          @container fitted-card (height >= 250px) {
            .fit-tall {
              padding: var(--boxel-sp);
            }
            .who-av {
              --pretui-avatar-size: 2.5rem;
              display: inline-flex;
            }
          }
          @container fitted-card (height >= 250px) and (width < 250px) {
            .who {
              flex-direction: column;
              align-items: flex-start;
              gap: var(--boxel-sp-xs);
            }
            .who-id {
              align-self: stretch;
            }
          }
          /* key facts from 275 tall: two on a 250 tile, six in two
             columns on a 400 card, all of them from 445 tall */
          @container fitted-card (height >= 275px) and (width >= 250px) {
            .kv {
              display: grid;
            }
          }
          @container fitted-card (height >= 275px) and (250px <= width < 400px) {
            .kv-i.in-narrow {
              display: flex;
            }
          }
          @container fitted-card (height >= 275px) and (width >= 400px) {
            .kv {
              grid-template-columns: repeat(2, minmax(0, 1fr));
            }
            .kv-i.in-two {
              display: flex;
            }
          }
          @container fitted-card (height >= 445px) and (width >= 400px) {
            .stats {
              display: grid;
            }
            .kv {
              grid-template-columns: minmax(0, 1fr);
            }
            .kv-i {
              display: flex;
            }
          }
        }
      </style>
    </template>
  };

  static atom: BaseDefComponent = class Atom extends Component<typeof this> {
    get summary() {
      return summarize(this.args.model?.tasks);
    }

    <template>
      <span class='checklist-atom'>
        <ChecklistIcon class='atom-icon' aria-hidden='true' />
        <span class='atom-name'>{{@model.title}}</span>
        {{#if this.summary.total}}
          <StatePill
            @label={{this.summary.progress}}
            @hue={{hueOf ONBOARDING_CHECKLIST_STATUS_HUES @model.status}}
            @dot={{false}}
          />
        {{/if}}
      </span>
      <style scoped>
        @layer PretComponent {
          .checklist-atom {
            display: inline-flex;
            align-items: center;
            gap: var(--boxel-sp-4xs);
            max-width: 100%;
            vertical-align: middle;
            font-size: var(--boxel-font-size-xs);
            font-weight: 600;
            color: var(--foreground);
            white-space: nowrap;
          }
          .atom-icon {
            flex: none;
            width: var(--boxel-icon-xs);
            height: var(--boxel-icon-xs);
            color: var(--muted-foreground);
          }
          .atom-name {
            min-width: 0;
            overflow: hidden;
            text-overflow: ellipsis;
          }
        }
      </style>
    </template>
  };
}
