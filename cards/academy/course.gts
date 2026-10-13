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
import { FieldContainer, FittedCard } from '@cardstack/boxel-ui/components';
import { on } from '@ember/modifier';
import { tracked } from '@glimmer/tracking';

import { Alert } from '@cardstack/pretui/components/alert';
import { Button } from '@cardstack/pretui/components/button';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { KeyValue } from '@cardstack/pretui/components/key-value';

import { SectionedEdit } from '@cardstack/catalog/components/sectioned-edit';
import PublishCourseCommand from './commands/publish-course-command';

import {
  statusField,
  statusHue,
  type StatusOption,
} from '@cardstack/catalog/fields/status/status';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import { CreditHoursField, formatCreditHours } from './credit-hours-field';
import {
  CompletionRuleField,
  describeCompletionRule,
} from './completion-rule-field';
import { LatePolicyField, shortLatePolicy } from './late-policy-field';
import { GradeScaleField, scaleSummary } from './grade-scale-field';
import { Module, minutesLabel } from './course-module';
import { Employee } from '@cardstack/catalog/cards/hr/employee';
import { CourseOutline } from './components/course-outline';

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

/**
 * The reusable curriculum: what is taught, in what order, and what "done"
 * means. A Course is run many times; each run is a Cohort. Everything a run
 * inherits — completion rule, late policy, grade scale — is declared here
 * once. Publish Course is the single writer of `status`.
 */
class CourseIsolated extends Component<typeof Course> {
  get hue() {
    return statusHue(CourseStatusField, this.args.model?.status);
  }
  get statusLabel() {
    return courseStatusLabel(this.args.model?.status);
  }
  get ruleLines() {
    return describeCompletionRule(this.args.model?.completionRule);
  }
  get facts() {
    let m = this.args.model;
    let items = [
      {
        key: 'Credit',
        value: formatCreditHours(m?.creditHours, { short: true }),
      },
      { key: 'Modules', value: String(m?.moduleCount ?? 0) },
      { key: 'Lessons', value: String(m?.lessonCount ?? 0) },
      { key: 'Time', value: minutesLabel(m?.totalMinutes) },
    ];
    if (m?.ownerName) {
      items.push({ key: 'Owner', value: m.ownerName });
    }
    return items;
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
    <article class='course'>
      {{#if this.canPublish}}
        <div class='actions'>
          <Button
            @tone='primary'
            @appearance='accent'
            @busy={{this.busy}}
            @busyLabel='Publishing'
            @disabled={{this.busy}}
            {{on 'click' this.publish}}
          >Publish course</Button>
          <span class='act-hint'>Checks modules, lessons and the completion rule
            before opening the course to cohorts.</span>
        </div>
      {{/if}}
      {{#if this.error}}
        <Alert @tone='danger' @title='Not published'>{{this.error}}</Alert>
      {{/if}}
      {{#if this.notice}}
        <Alert @tone='success'>{{this.notice}}</Alert>
      {{/if}}
      <header class='hero'>
        <div class='hero-text'>
          <span class='eyebrow'>
            {{#if @model.code}}<span class='code'>{{@model.code}}</span>{{/if}}
            {{#if @model.levelLabel}}<span>{{@model.levelLabel}}</span>{{/if}}
            <StatePill
              @label={{this.statusLabel}}
              @hue={{this.hue}}
              @dot={{true}}
            />
          </span>
          <h1>{{@model.cardTitle}}</h1>
          {{#if @model.summary}}<div class='summary'><@fields.summary
              /></div>{{/if}}
        </div>
        <KeyValue class='facts' @items={{this.facts}} />
      </header>

      <section class='outline'>
        <h2>Outline</h2>
        <CourseOutline @modules={{@model.modules}} />
      </section>

      <section class='rules'>
        <div class='rule-card'>
          <h2>Completion</h2>
          {{#if this.ruleLines.length}}
            <ul>{{#each this.ruleLines as |line|}}<li
                >{{line}}</li>{{/each}}</ul>
          {{else}}
            <EmptyState
              @size='s'
              @title='No completion rule'
              @message='Every enrolment completes when its cohort closes.'
            />
          {{/if}}
        </div>
        <div class='rule-card'>
          <h2>Late work</h2>
          <p>{{shortLatePolicy @model.latePolicy}}</p>
        </div>
        <div class='rule-card'>
          <h2>Grade scale</h2>
          <p>{{scaleSummary @model.gradeScale}}</p>
        </div>
      </section>
    </article>
    <style scoped>
      .course {
        max-width: 60rem;
        margin: 0 auto;
        container-type: inline-size;
        padding: var(--boxel-sp-xl) var(--boxel-sp-lg);
        display: grid;
        gap: var(--boxel-sp-xl);
        color: var(--foreground);
        background: var(--background);
      }
      .hero {
        display: grid;
        grid-template-columns: minmax(0, 1fr) auto;
        gap: var(--boxel-sp-lg);
        align-items: start;
      }
      .eyebrow {
        display: inline-flex;
        gap: var(--boxel-sp-xs);
        align-items: center;
        font-size: var(--boxel-font-size-xs);
        text-transform: uppercase;
        letter-spacing: 0.06em;
        color: var(--muted-foreground);
      }
      .code {
        font-family: var(--font-mono);
        font-weight: 700;
        color: var(--primary-ink);
      }
      h1 {
        margin: var(--boxel-sp-xs) 0 0;
        font-size: var(--boxel-font-size-2xl);
        font-weight: 700;
        line-height: 1.1;
        letter-spacing: -0.015em;
      }
      .summary {
        margin-top: var(--boxel-sp-sm);
        max-width: 40rem;
        color: var(--muted-foreground);
        line-height: 1.55;
      }
      .facts {
        padding: var(--boxel-sp) var(--boxel-sp-lg);
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
      }
      h2 {
        margin: 0 0 var(--boxel-sp-xs);
        font-size: var(--boxel-font-size-sm);
        text-transform: uppercase;
        letter-spacing: 0.06em;
        color: var(--muted-foreground);
      }
      .actions {
        display: flex;
        gap: var(--boxel-sp-sm);
        align-items: center;
        flex-wrap: wrap;
        padding: var(--boxel-sp-sm) var(--boxel-sp);
        border: 1px solid var(--border);
        border-left: 0.25rem solid var(--primary);
        border-radius: var(--radius);
        background: var(--card);
      }
      .act-hint {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
      .rules {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(14rem, 1fr));
        gap: var(--boxel-sp-sm);
      }
      .rule-card {
        padding: var(--boxel-sp);
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
      }
      .rule-card ul {
        margin: 0;
        padding-left: var(--boxel-sp);
        font-size: var(--boxel-font-size-sm);
      }
      .rule-card p {
        margin: 0;
        font-size: var(--boxel-font-size-sm);
      }
      @container (width <= 43.75rem) {
        .hero {
          grid-template-columns: 1fr;
        }
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
    get hue() {
      return statusHue(CourseStatusField, this.args.model?.status);
    }
    <template>
      <div class='row'>
        <span class='code'>{{if @model.code @model.code 'C'}}</span>
        <div class='text'>
          <span class='title'>{{@model.cardTitle}}</span>
          <span class='sub'>{{@model.moduleCount}}
            modules ·
            {{@model.lessonCount}}
            lessons ·
            {{formatCreditHours @model.creditHours short=true}}</span>
        </div>
        <StatePill
          @label={{courseStatusLabel @model.status}}
          @hue={{this.hue}}
        />
      </div>
      <style scoped>
        .row {
          display: grid;
          grid-template-columns: auto 1fr auto;
          gap: var(--boxel-sp-xs);
          align-items: center;
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .code {
          min-width: 2.25rem;
          height: 2.25rem;
          padding: 0 var(--boxel-sp-4xs);
          display: grid;
          place-items: center;
          border-radius: var(--boxel-border-radius-sm);
          background: color-mix(in oklab, var(--primary) 14%, var(--card));
          font-size: var(--boxel-font-size-xs);
          font-weight: 700;
          font-family: var(--font-mono);
        }
        .text {
          display: grid;
          min-width: 0;
        }
        .title {
          font-weight: 600;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .sub {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        @container (width < 18rem) {
          .row {
            grid-template-columns: minmax(0, 1fr) auto;
          }
          .code {
            display: none;
          }
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='atom'>{{#if @model.code}}<span
            class='code'
          >{{@model.code}}</span>
        {{/if}}{{@model.cardTitle}}</span>
      <style scoped>
        .atom {
          font-size: var(--boxel-font-size-sm);
          white-space: nowrap;
        }
        .code {
          font-family: var(--font-mono);
          color: var(--primary-ink);
          font-weight: 700;
        }
      </style>
    </template>
  };

  static edit = class Edit extends Component<typeof this> {
    sections = [
      { id: 'identity', label: 'Identity' },
      { id: 'summary', label: 'Summary' },
      { id: 'rules', label: 'Rules' },
      { id: 'curriculum', label: 'Curriculum' },
    ];
    <template>
      <SectionedEdit
        @sections={{this.sections}}
        @ariaLabel='Course sections'
        as |e|
      >
        <e.Section @id='identity' @title='Identity' @cols={{2}}>
          <FieldContainer @label='Title' @vertical={{true}}><@fields.title
            /></FieldContainer>
          <FieldContainer @label='Code' @vertical={{true}}><@fields.code
            /></FieldContainer>
          <FieldContainer @label='Level' @vertical={{true}}><@fields.level
            /></FieldContainer>
          <FieldContainer @label='Status' @vertical={{true}}>
            <@fields.status @format='atom' />
            <p class='status-note'>Publish Course sets the status.</p>
          </FieldContainer>
        </e.Section>
        <e.Section
          @id='summary'
          @title='Summary'
          @hint='what a learner reads first'
          @cols={{1}}
        >
          <FieldContainer @label='Summary' @vertical={{true}}><@fields.summary
            /></FieldContainer>
          <FieldContainer
            @label='Credit hours'
            @vertical={{true}}
          ><@fields.creditHours /></FieldContainer>
        </e.Section>
        <e.Section
          @id='rules'
          @title='Rules'
          @hint='inherited by every cohort'
          @cols={{1}}
        >
          <FieldContainer
            @label='Completion rule'
            @vertical={{true}}
          ><@fields.completionRule /></FieldContainer>
          <FieldContainer
            @label='Late policy'
            @vertical={{true}}
          ><@fields.latePolicy /></FieldContainer>
          <FieldContainer
            @label='Grade scale'
            @vertical={{true}}
          ><@fields.gradeScale /></FieldContainer>
        </e.Section>
        <e.Section @id='curriculum' @title='Curriculum' @cols={{1}}>
          <FieldContainer
            @label='Modules (in order)'
            @vertical={{true}}
          ><@fields.modules /></FieldContainer>
          <FieldContainer @label='Owner' @vertical={{true}}><@fields.owner
            /></FieldContainer>
        </e.Section>
      </SectionedEdit>
      <style scoped>
        .status-note {
          margin-top: var(--boxel-sp-4xs);
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get hue() {
      return statusHue(CourseStatusField, this.args.model?.status);
    }
    <template>
      <FittedCard @titleTag='h3'>
        <:eyebrow>{{#if @model.code}}<span class='code'>{{@model.code}}</span>
            ·
          {{/if}}{{@model.levelLabel}}</:eyebrow>
        <:title>{{@model.cardTitle}}</:title>
        <:subtitle>{{@model.moduleCount}}
          modules ·
          {{@model.lessonCount}}
          lessons ·
          {{minutesLabel @model.totalMinutes}}</:subtitle>
        <:badgeRight><StatePill
            @label={{courseStatusLabel @model.status}}
            @hue={{this.hue}}
          /></:badgeRight>
        <:footer>{{formatCreditHours @model.creditHours short=true}}
          {{#if @model.ownerName}}· {{@model.ownerName}}{{/if}}</:footer>
      </FittedCard>
      <style scoped>
        .code {
          font-family: var(--font-mono);
          font-weight: 700;
          color: var(--primary-ink);
        }
      </style>
    </template>
  };
}

export default Course;
