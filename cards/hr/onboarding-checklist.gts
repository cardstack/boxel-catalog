import { markDefinition } from '@cardstack/base/mark-definition';
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
import { DotLabel, dotEnumField } from './dot-enum-field';
import ChecklistIcon from '@cardstack/boxel-icons/checklist';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { type DescriptionsItem } from '@cardstack/pretui/components/descriptions';

import { Employee } from './employee';
import { Contractor } from './contractor';
import { OnboardingTemplate } from './onboarding-template';
import { type Hue } from '@cardstack/catalog/components/state-pill';
import type { PretuiToneArg } from '@cardstack/pretui/pretui-primitives';
import { hueOf, stateColorsOf } from './hr-ui';
import {
  EmbCard,
  FitCard,
  FitRow,
  IsoHead,
  IsoPage,
  Kv,
  kv,
  Panel,
  SheetEmpty,
  SheetLine,
  StatStrip,
  type StripItem,
} from './compact-sheet';

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

export const OnboardingChecklistStatusField = markDefinition(
  dotEnumField(
    {
      options: ONBOARDING_CHECKLIST_STATUSES.map((status) => ({
        value: status,
        label: ONBOARDING_CHECKLIST_STATUS_LABELS[status],
      })),
      displayName: 'Onboarding Checklist Status',
    },
    ONBOARDING_CHECKLIST_STATUS_HUES,
  ),
);

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
          <DotLabel
            @label={{taskStatusLabel @model.status}}
            @hue={{hueOf TASK_STATUS_HUES @model.status}}
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
            font-size: var(--boxel-font-size-xs);
            font-weight: 700;
            overflow-wrap: break-word;
          }
          .task-sub {
            display: flex;
            flex-wrap: wrap;
            align-items: center;
            gap: 0 var(--boxel-sp-4xs);
            font-size: var(--boxel-font-size-2xs);
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

    get strip(): StripItem[] {
      let s = this.summary;
      let m = this.args.model;
      return [
        {
          label: 'Progress',
          value: s.progress,
          hint: s.pct + '% complete',
          tone: 'info',
        },
        {
          label: 'Next due',
          value: s.next?.dueDate ? shortDate(s.next.dueDate) : '—',
          hint: s.next ? s.next.title : 'All tasks complete',
          tone: 'warning',
        },
        {
          label: 'Started',
          value: m?.createdDate ? shortDate(m.createdDate) : '—',
          hint: this.startedYear,
        },
      ];
    }
    get taskCount(): string {
      return String(this.summary.total);
    }
    get linkRows() {
      return this.linked.map((l) => ({ key: String(l.key), value: '' }));
    }

    <template>
      <IsoPage>
        <:head>
          <IsoHead @title={{@model.title}} @meta={{this.subline}}>
            <:mark><Avatar
                @name='On'
                @hue='var(--muted)'
                @shape='rounded'
                @size={{36}}
                aria-hidden='true'
              /></:mark>
            <:aside><DotLabel
                @label={{statusLabel @model.status}}
                @hue={{hueOf ONBOARDING_CHECKLIST_STATUS_HUES @model.status}}
              /></:aside>
            <:stats><StatStrip @items={{this.strip}} /></:stats>
          </IsoHead>
        </:head>
        <:main>
          <Panel @title='Tasks' @meta={{this.taskCount}}>
            {{#each @fields.tasks as |Task|}}
              <SheetLine><span class='task'><Task
                    @format='embedded'
                  /></span></SheetLine>
            {{else}}
              <SheetEmpty @title='No tasks in this checklist' />
            {{/each}}
          </Panel>
        </:main>
        <:aside>
          {{#if this.linked.length}}
            <Panel @title='Linked'>
              <Kv @items={{this.linkRows}}>
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
              </Kv>
            </Panel>
          {{/if}}
          <Panel @title='Details'><Kv @items={{kv this.details}} /></Panel>
        </:aside>
      </IsoPage>
      <style scoped>
        .task {
          flex: 1;
          min-width: 0;
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

    get rows() {
      return [...kv(this.facts), { key: 'Employee', value: '' }];
    }
    <template>
      <EmbCard @title={{@model.title}} @meta={{this.subline}}>
        <:mark><Avatar
            @name='On'
            @hue='var(--muted)'
            @shape='rounded'
            @size={{24}}
            aria-hidden='true'
          /></:mark>
        <:aside><DotLabel
            @label={{statusLabel @model.status}}
            @hue={{hueOf ONBOARDING_CHECKLIST_STATUS_HUES @model.status}}
          /></:aside>
        <:default>
          <Kv @items={{this.rows}}>
            <:value as |row|>{{#if (eq row.key 'Employee')}}{{#if
                  @model.employee
                }}<@fields.employee
                    @format='atom'
                    @displayContainer={{false}}
                  />{{else}}{{this.personName}}{{/if}}{{else}}{{row.value}}{{/if}}</:value>
          </Kv>
        </:default>
      </EmbCard>
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

    // the head rows already say progress and the next task
    get moreFacts() {
      return this.keyFacts.slice(2);
    }
    get strip(): StripItem[] {
      return [
        { label: 'Progress', value: this.summary.progress },
        { label: 'Next due', value: this.nextDueLabel },
        { label: 'Started', value: this.startedLabel },
      ];
    }
    <template>
      <FitCard @title={{this.personName}}>
        <:mark><Avatar
            @name='On'
            @hue='var(--muted)'
            @shape='rounded'
            @size={{20}}
            aria-hidden='true'
          /></:mark>
        <:status><DotLabel
            @label={{statusLabel @model.status}}
            @hue={{hueOf ONBOARDING_CHECKLIST_STATUS_HUES @model.status}}
          /></:status>
        <:default>
          <FitRow @left={{true}}><span
              class='meta'
            >{{this.subline}}</span></FitRow>
          <FitRow @label='Progress'>{{this.summary.progress}} done</FitRow>
          <FitRow @label='Next'>{{if
              this.summary.next
              this.summary.next.title
              '—'
            }}</FitRow>
          <StatStrip @compact={{true}} @items={{this.strip}} />
          {{#each this.moreFacts as |f|}}
            <FitRow @label={{f.key}}>{{f.value}}</FitRow>
          {{/each}}
        </:default>
      </FitCard>
      <style scoped>
        .meta {
          overflow: hidden;
          text-overflow: ellipsis;
          font-size: var(--boxel-font-size-2xs);
          color: var(--muted-foreground);
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
          <DotLabel
            @label={{this.summary.progress}}
            @hue={{hueOf ONBOARDING_CHECKLIST_STATUS_HUES @model.status}}
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
