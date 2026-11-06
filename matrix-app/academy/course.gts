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
import NumberField from '@cardstack/base/number';
import enumField from '@cardstack/base/enum';
import BookIcon from '@cardstack/boxel-icons/book';
import type Owner from '@ember/owner';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';

import { Button } from '@cardstack/pretui/components/button';
import { Alert } from '@cardstack/pretui/components/alert';

import PublishCourseCommand from './commands/publish-course-command';

import {
  statusField,
  statusHue,
  type StatusOption,
} from '@cardstack/catalog/fields/status/status';
import { CreditHoursField, formatCreditHours } from './credit-hours-field';
import { CompletionRuleField } from './completion-rule-field';
import { LatePolicyField, shortLatePolicy } from './late-policy-field';
import { GradeScaleField, sortedBands } from './grade-scale-field';
import { Module, minutesLabel } from './course-module';
import { Employee } from '../hr/employee';
import {
  AtomChip,
  Dot,
  Embed,
  Kv,
  Mark,
  Section,
  Sheet,
  Stat,
} from './components/record-sheet';
import { FitTile } from '../shared/fit-tile';
import { DeskRow, KvList, cardsLinkedTo } from './components/desk-status';

export const COURSE_STATUSES: StatusOption[] = [
  {
    value: 'draft',
    label: 'Draft',
    hue: 'slate',
    meaning: 'Being written. No cohort can be scheduled against it yet.',
  },
  {
    value: 'published',
    label: 'Published',
    hue: 'green',
    meaning: 'Ready to run. Cohorts may be created from it.',
  },
  {
    value: 'archived',
    label: 'Archived',
    hue: 'slate',
    meaning: 'Kept for the record; new cohorts are not offered.',
    terminal: true,
  },
];

export function courseStatusLabel(v?: string | null): string {
  return COURSE_STATUSES.find((s) => s.value === v)?.label ?? 'Draft';
}

export const CourseStatusField = statusField({
  displayName: 'Course Status',
  options: COURSE_STATUSES,
  transitions: {
    draft: ['published'],
    published: ['archived', 'draft'],
    archived: ['published'],
  },
});

export const COURSE_LEVELS = [
  { value: 'intro', label: 'Introductory' },
  { value: 'intermediate', label: 'Intermediate' },
  { value: 'advanced', label: 'Advanced' },
];

export const CourseLevelField = enumField(StringField, {
  displayName: 'Course Level',
  options: COURSE_LEVELS,
});

function hueOf(m: any) {
  return statusHue(CourseStatusField, m?.status);
}

function metaLine(m: any): string {
  return [
    m?.code,
    m?.levelLabel,
    m?.creditHours ? formatCreditHours(m.creditHours) : '',
  ]
    .filter(Boolean)
    .join(' · ');
}

function factLine(m: any): string {
  return `${m?.moduleCount ?? 0} modules · ${m?.lessonCount ?? 0} lessons · ${minutesLabel(m?.totalMinutes)}`;
}

function courseItems(m: any) {
  return [
    { key: 'Code', value: m?.code },
    { key: 'Level', value: m?.levelLabel },
    {
      key: 'Credit',
      value: formatCreditHours(m?.creditHours, { short: true }),
    },
    { key: 'Modules', value: String(m?.moduleCount ?? 0) },
    { key: 'Lessons', value: String(m?.lessonCount ?? 0) },
    { key: 'Owner', value: m?.ownerName },
    { key: 'Late penalty', value: shortLatePolicy(m?.latePolicy) },
  ];
}

function moduleMeta(mod: any): string {
  return [
    `${mod?.lessonCount ?? 0} lessons`,
    minutesLabel(mod?.totalMinutes),
    mod?.summary,
  ]
    .filter(Boolean)
    .join(' · ');
}

function pctText(n?: number | null) {
  return n != null ? `${n}%` : '';
}

function ruleItems(r: any) {
  return [
    { key: 'Min attendance', value: pctText(r?.minAttendancePct) },
    {
      key: 'Assignments',
      value: r?.requireAllRequiredAssignments ? 'all required' : '',
    },
    {
      key: 'Quizzes passed',
      value: r?.minQuizPassCount ? `at least ${r.minQuizPassCount}` : '',
    },
    { key: 'Minimum grade', value: r?.minGradeLetter },
  ];
}

function lateItems(p: any) {
  return [
    {
      key: 'Penalty',
      value:
        p?.penaltyPctPerDay != null ? `${p.penaltyPctPerDay}% per day` : '',
    },
    { key: 'Cap', value: pctText(p?.capPct) },
    {
      key: 'Grace',
      value: p?.graceHours != null ? `${p.graceHours} hours` : '',
    },
    {
      key: 'Hard close',
      value:
        p?.hardCloseDays != null ? `${p.hardCloseDays} days after due` : '',
    },
  ];
}

function bandsLine(scale: any): string {
  return sortedBands(scale)
    .map((b: any) => `${b.letter} ≥ ${b.minPct ?? 0}%`)
    .join('  ');
}

// Cohort imports Course, so the search names it by module, not class.
const COHORT_REF = {
  // @ts-expect-error TS1470 -- import.meta is valid in realm-served modules; only the CommonJS type-check rejects it
  module: new URL('./cohort', import.meta.url).href,
  name: 'Cohort',
};

function cohortHue(status?: string | null) {
  return status === 'running' || status === 'closed' ? 'green' : undefined;
}

/**
 * The reusable curriculum: what is taught, in what order, and what "done"
 * means. A Course is run many times; each run is a Cohort. Everything a run
 * inherits — completion rule, late policy, grade scale — is declared here
 * once. Publish Course is the single writer of `status`.
 */
class CourseIsolated extends Component<typeof Course> {
  private cohortsQ: ReturnType<typeof cardsLinkedTo>;

  constructor(owner: Owner, args: any) {
    super(owner, args);
    this.cohortsQ = cardsLinkedTo(
      this,
      this.args.context,
      this.args.model,
      COHORT_REF,
      'course.id',
    );
  }

  get cohorts(): any[] {
    return ((this.cohortsQ?.instances ?? []) as any[]).filter(Boolean);
  }
  get cohortHint() {
    let by = (s: string) => this.cohorts.filter((c) => c.status === s).length;
    return `${by('running')} running, ${by('planned')} planned`;
  }
  get statusLabel() {
    return courseStatusLabel(this.args.model?.status);
  }
  get moduleLabel() {
    let n = this.args.model?.moduleCount ?? 0;
    return `${n} module${n === 1 ? '' : 's'}`;
  }
  get stats(): {
    label: string;
    value?: string | null;
    hint?: string | null;
  }[] {
    let m = this.args.model;
    return [
      {
        label: 'Modules',
        value: String(m?.moduleCount ?? 0),
        hint: `${m?.lessonCount ?? 0} lessons`,
      },
      {
        label: 'Material',
        value: minutesLabel(m?.totalMinutes),
        hint: 'total time',
      },
      {
        label: 'Credit',
        value: formatCreditHours(m?.creditHours, { short: true }),
        hint: m?.levelLabel,
      },
      {
        label: 'Cohorts',
        value: String(this.cohorts.length),
        hint: this.cohortHint,
      },
    ];
  }
  @tracked busy = false;
  @tracked error: string | undefined;
  @tracked notice: string | undefined;
  get canPublish() {
    return (
      this.args.model?.status !== 'published' &&
      !!this.args.context?.commandContext
    );
  }
  publish = async () => {
    let ctx = this.args.context?.commandContext;
    if (!ctx) return;
    this.busy = true;
    this.error = undefined;
    this.notice = undefined;
    try {
      let res = (await new PublishCourseCommand(ctx).execute({
        course: this.args.model,
      } as any)) as any;
      this.notice = res?.message;
    } catch (e: any) {
      this.error = e?.message ?? String(e);
    } finally {
      this.busy = false;
    }
  };
  <template>
    <Sheet @mark='Co' @title={{@model.cardTitle}} @meta={{metaLine @model}}>
      <:status>
        <Dot @hue={{hueOf @model}}>{{this.statusLabel}}</Dot>
        <Dot>{{this.moduleLabel}}</Dot>
      </:status>
      <:actions>
        {{#if this.canPublish}}
          <Button
            type='button'
            @size='xs'
            @tone='primary'
            @appearance='accent'
            @loading={{this.busy}}
            @disabled={{this.busy}}
            {{on 'click' this.publish}}
          >Publish course</Button>
        {{/if}}
      </:actions>
      <:stats>{{#each this.stats as |st|}}<Stat
            @label={{st.label}}
            @value={{st.value}}
            @sub={{st.hint}}
          />{{/each}}</:stats>
      <:main>
        {{#if this.error}}
          <Alert @tone='danger' @title='Not published'>{{this.error}}</Alert>
        {{/if}}
        {{#if this.notice}}<Alert @tone='success'>{{this.notice}}</Alert>{{/if}}

        {{#if @model.summary}}
          <Section @title='Summary'><div class='summary'><@fields.summary
              /></div></Section>
        {{/if}}
        <Section @title='Outline'>
          {{#each @model.modules as |mod|}}
            <DeskRow @title={{mod.cardTitle}} @meta={{moduleMeta mod}}>
              <Dot @hue='blue'>{{mod.releaseLabel}}</Dot>
            </DeskRow>
          {{else}}
            <DeskRow @title='No modules yet' @meta='Add modules to publish.' />
          {{/each}}
        </Section>
        <Section @title='Completion rule'><KvList
            @items={{ruleItems @model.completionRule}}
          /></Section>
        <Section @title='Late policy'><KvList
            @items={{lateItems @model.latePolicy}}
          /></Section>
        <Section @title='Grade scale'><p class='bands'>{{bandsLine
              @model.gradeScale
            }}</p></Section>
      </:main>
      <:side>
        <Section @title='Linked'>
          <Kv @label='Owner'>{{#if @model.owner}}<@fields.owner
                @format='atom'
                @displayContainer={{false}}
              />{{else}}—{{/if}}</Kv>
          {{#each this.cohorts as |c|}}
            <Kv @label='Cohort'><AtomChip @mark='Ch' @title={{c.cardTitle}}><Dot
                  @hue={{cohortHue c.status}}
                >{{c.status}}</Dot></AtomChip></Kv>
          {{/each}}
        </Section>
        <Section @title='Details'>
          <KvList @items={{courseItems @model}} /></Section>
      </:side></Sheet>
    <style scoped>
      .summary,
      .bands {
        margin: 0;
        padding: var(--boxel-sp-4xs) var(--boxel-sp-xs) var(--boxel-sp-xs);
        font-size: 0.75rem;
      }
      .bands {
        padding-block-start: var(--boxel-sp-xs);
        border-top: 1px solid var(--border);
        font-family: var(--font-mono);
        white-space: pre-wrap;
      }
    </style>
  </template>
}

export class Course extends CardDef {
  static displayName = 'Course';
  static icon = BookIcon;

  @field title = contains(StringField);
  @field code = contains(StringField, {
    description: 'Catalog code, e.g. PAF-101.',
  });
  @field level = contains(CourseLevelField);
  @field summary = contains(MarkdownField);
  @field creditHours = contains(CreditHoursField);
  @field status = contains(CourseStatusField);
  @field completionRule = contains(CompletionRuleField);
  @field latePolicy = contains(LatePolicyField);
  @field gradeScale = contains(GradeScaleField);
  @field owner = linksTo(() => Employee);
  @field modules = linksToMany(() => Module);

  @field moduleCount = contains(NumberField, {
    computeVia: function (this: Course) {
      return (this.modules ?? []).length;
    },
  });
  @field lessonCount = contains(NumberField, {
    computeVia: function (this: Course) {
      return (this.modules ?? []).reduce(
        (n: number, m: any) => n + (m?.lessonCount ?? 0),
        0,
      );
    },
  });
  @field totalMinutes = contains(NumberField, {
    computeVia: function (this: Course) {
      return (this.modules ?? []).reduce(
        (n: number, m: any) => n + (m?.totalMinutes ?? 0),
        0,
      );
    },
  });
  @field ownerName = contains(StringField, {
    computeVia: function (this: Course) {
      return this.owner?.name ?? '';
    },
  });
  @field levelLabel = contains(StringField, {
    computeVia: function (this: Course) {
      return COURSE_LEVELS.find((l) => l.value === this.level)?.label ?? '';
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: Course) {
      return this.title?.trim() || 'Untitled course';
    },
  });

  static isolated = CourseIsolated;

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <Embed @mark='Co' @title={{@model.cardTitle}} @meta={{metaLine @model}}>
        <:status><Dot @hue={{hueOf @model}}>{{courseStatusLabel
              @model.status
            }}</Dot></:status>
        <:fact>{{factLine @model}}</:fact>
        <:default>
          <KvList @items={{courseItems @model}} />
          {{#if @model.owner}}
            <Kv @label='Owner'><@fields.owner
                @format='atom'
                @displayContainer={{false}}
              /></Kv>
          {{/if}}
        </:default>
      </Embed>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <AtomChip @mark='Co' @title={{@model.cardTitle}}><Dot
          @hue={{hueOf @model}}
        >{{courseStatusLabel @model.status}}</Dot></AtomChip>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <FitTile>
        <:avatar><Mark @text='Co' /></:avatar>
        <:title>{{@model.cardTitle}}</:title>
        <:subtitle>{{metaLine @model}}</:subtitle>
        <:status><Dot @hue={{hueOf @model}}>{{courseStatusLabel
              @model.status
            }}</Dot></:status>
        <:fact>{{factLine @model}}</:fact>
        <:relations>{{#if @model.owner}}<@fields.owner
              @format='atom'
              @displayContainer={{false}}
            />{{/if}}</:relations>
      </FitTile>
    </template>
  };
}

export default Course;
