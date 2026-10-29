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
import { on } from '@ember/modifier';
import { tracked } from '@glimmer/tracking';
import { Alert } from '../../ui-component/components/alert';
import { Button } from '../../ui-component/components/button';
import { EmptyState } from '../../ui-component/components/empty-state';
import { Avatar } from '../../ui-component/components/avatar';
import { FitTile } from '../../ui-component/components/fit-tile';
import {
  KeyValue,
  type KeyValueItem,
} from '../../ui-component/components/key-value';
import { Stat } from '../../ui-component/components/stat';
import { FittedExtras } from '../procurement/vendor';
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
import {
  LatePolicyField,
  describeLatePolicy,
  shortLatePolicy,
} from './late-policy-field';
import { GradeScaleField, sortedBands } from './grade-scale-field';
import { Module, minutesLabel } from './course-module';
import { Employee } from '../hr/employee';
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
  get bands() {
    return sortedBands(this.args.model?.gradeScale);
  }
  get subtitle() {
    let m = this.args.model;
    return [m?.code, m?.levelLabel, formatCreditHours(m?.creditHours)]
      .filter(Boolean)
      .join(' · ');
  }
  get moduleChip() {
    let n = this.args.model?.moduleCount ?? 0;
    return `${n} ${n === 1 ? 'module' : 'modules'}`;
  }
  get lessonHint() {
    let n = this.args.model?.lessonCount ?? 0;
    return `${n} ${n === 1 ? 'lesson' : 'lessons'}`;
  }
  get details(): KeyValueItem[] {
    let m = this.args.model;
    return [
      { key: 'Code', value: m?.code || '—' },
      { key: 'Level', value: m?.levelLabel || '—' },
      { key: 'Credit', value: formatCreditHours(m?.creditHours) },
      { key: 'Modules', value: String(m?.moduleCount ?? 0) },
      { key: 'Lessons', value: String(m?.lessonCount ?? 0) },
      { key: 'Late penalty', value: shortLatePolicy(m?.latePolicy) },
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
    <article class='course'>
      <header class='iso-head'>
        <Avatar
          @name='C o'
          @hue='var(--muted-foreground)'
          @size={{48}}
          aria-hidden='true'
        />
        <div class='iso-id'>
          <h1>{{@model.cardTitle}}</h1>
          <p class='iso-sub'>{{this.subtitle}}</p>
        </div>
        <div class='iso-chips'>
          <StatePill @label={{this.statusLabel}} @hue={{this.hue}} />
          <StatePill @label={{this.moduleChip}} @hue='slate' />
        </div>
        {{#if this.canPublish}}
          <div class='iso-actions'>
            <Button
              @tone='primary'
              @appearance='accent'
              @busy={{this.busy}}
              @busyLabel='Publishing'
              @disabled={{this.busy}}
              {{on 'click' this.publish}}
            >Publish course</Button>
          </div>
        {{/if}}
      </header>
      {{#if this.error}}
        <Alert @tone='danger' @title='Not published'>{{this.error}}</Alert>
      {{/if}}
      {{#if this.notice}}
        <Alert @tone='success'>{{this.notice}}</Alert>
      {{/if}}

      <div class='stat-row'>
        <Stat
          @label='Modules'
          @value={{if @model.moduleCount @model.moduleCount 0}}
          @hint={{this.lessonHint}}
          @roll={{false}}
        />
        <Stat
          @label='Material'
          @value={{minutesLabel @model.totalMinutes}}
          @roll={{false}}
        />
        <Stat
          @label='Credit'
          @value={{formatCreditHours @model.creditHours short=true}}
          @hint={{@model.levelLabel}}
          @roll={{false}}
        />
      </div>

      <div class='iso-body'>
        <div class='iso-col'>
          {{#if @model.summary}}
            <section class='iso-card'>
              <h2>Summary</h2>
              <div class='summary'><@fields.summary /></div>
            </section>
          {{/if}}
          <section class='iso-card'>
            <h2>Outline</h2>
            <CourseOutline @modules={{@model.modules}} />
          </section>
          <section class='iso-card'>
            <h2>Completion rule</h2>
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
          </section>
          <section class='iso-card'>
            <h2>Late policy</h2>
            <p>{{describeLatePolicy @model.latePolicy}}</p>
          </section>
          <section class='iso-card'>
            <h2>Grade scale</h2>
            <div class='tag-row'>
              {{#each this.bands as |b|}}
                <StatePill @label='{{b.letter}} ≥ {{b.minPct}}%' @hue='slate' />
              {{/each}}
            </div>
          </section>
        </div>
        <div class='iso-col'>
          <section class='iso-card'>
            <h2>Linked</h2>
            <dl class='rels'>
              <div><dt>Owner</dt><dd>{{#if @model.owner}}<@fields.owner
                      @format='atom'
                    />{{else}}—{{/if}}</dd></div>
            </dl>
          </section>
          <section class='iso-card'>
            <h2>Details</h2>
            <KeyValue @items={{this.details}} @rows='ruled' />
          </section>
        </div>
      </div>
    </article>
    <style scoped>
      @layer PretComponent {
        .course {
          max-width: 60rem;
          margin: 0 auto;
          container-type: inline-size;
          padding: var(--boxel-sp-xl) var(--boxel-sp-lg);
          display: grid;
          gap: var(--boxel-sp-lg);
          color: var(--foreground);
          background: var(--background);
        }
        .iso-head {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          gap: var(--boxel-sp-xs) var(--boxel-sp);
        }
        .iso-id {
          flex: 1 1 14rem;
          min-width: 0;
        }
        h1 {
          margin: 0;
          font-size: var(--boxel-font-size-xl);
          font-weight: 600;
          line-height: 1.25;
        }
        .iso-sub {
          margin: 0;
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
        }
        .iso-chips {
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-4xs);
        }
        .stat-row {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(10.5rem, 1fr));
          gap: var(--boxel-sp);
        }
        .iso-body {
          display: grid;
          grid-template-columns: minmax(0, 2fr) minmax(16rem, 1fr);
          gap: var(--boxel-sp-lg);
          align-items: start;
        }
        .iso-col {
          display: grid;
          gap: var(--boxel-sp-lg);
          min-width: 0;
        }
        .iso-card {
          padding: var(--boxel-sp-lg);
          border-radius: var(--radius);
          background: var(--card);
          box-shadow: var(--shadow-sm);
          min-width: 0;
        }
        h2 {
          margin: 0 0 var(--boxel-sp);
          font-size: var(--boxel-font-size);
          font-weight: 600;
        }
        .summary {
          color: var(--muted-foreground);
          line-height: 1.55;
        }
        .iso-card ul {
          margin: 0;
          padding-left: var(--boxel-sp);
          font-size: var(--boxel-font-size-sm);
        }
        .iso-card p {
          margin: 0;
          font-size: var(--boxel-font-size-sm);
        }
        .tag-row {
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-4xs);
        }
        .rels {
          margin: 0;
          display: grid;
          gap: var(--boxel-sp-xs);
        }
        .rels div {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          gap: var(--boxel-sp-xs);
        }
        .rels dt {
          min-width: 4rem;
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
        }
        .rels dd {
          margin: 0;
          min-width: 0;
        }
        @container (width <= 43.75rem) {
          .iso-body {
            grid-template-columns: minmax(0, 1fr);
          }
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
    get subtitle() {
      let m = this.args.model;
      return [m?.code, m?.levelLabel, formatCreditHours(m?.creditHours)]
        .filter(Boolean)
        .join(' · ');
    }
    get moduleChip() {
      let n = this.args.model?.moduleCount ?? 0;
      return `${n} ${n === 1 ? 'module' : 'modules'}`;
    }
    get fact() {
      let m = this.args.model;
      let n = m?.lessonCount ?? 0;
      return `${n} ${n === 1 ? 'lesson' : 'lessons'} · ${minutesLabel(m?.totalMinutes)} of material`;
    }
    get facts() {
      let m = this.args.model;
      return [
        { key: 'Code', value: m?.code || '—' },
        { key: 'Level', value: m?.levelLabel || '—' },
        { key: 'Credit', value: formatCreditHours(m?.creditHours) },
        { key: 'Modules', value: String(m?.moduleCount ?? 0) },
      ];
    }
    <template>
      <article class='emb'>
        <header class='emb-head'>
          <Avatar
            @name='C o'
            @hue='var(--muted-foreground)'
            @size={{40}}
            aria-hidden='true'
          />
          <div class='emb-id'>
            <h4 class='emb-title'>{{@model.cardTitle}}</h4>
            <p class='emb-sub'>{{this.subtitle}}</p>
          </div>
          <div class='emb-chips'>
            <StatePill
              @label={{courseStatusLabel @model.status}}
              @hue={{this.hue}}
            />
            <StatePill @label={{this.moduleChip}} @hue='slate' />
          </div>
        </header>
        <p class='emb-fact'>{{this.fact}}</p>
        <dl class='emb-kv'>
          {{#each this.facts as |f|}}
            <div><dt>{{f.key}}</dt><dd>{{f.value}}</dd></div>
          {{/each}}
        </dl>
        {{#if @model.owner}}
          <div class='emb-rels'><span class='emb-rel'>Owner
              <@fields.owner @format='atom' /></span></div>
        {{/if}}
      </article>
      <style scoped>
        @layer PretComponent {
          .emb {
            display: flex;
            flex-direction: column;
            gap: var(--boxel-sp-sm);
            padding: var(--boxel-sp-sm);
            font-size: var(--boxel-font-size-sm);
          }
          .emb-head {
            display: flex;
            flex-wrap: wrap;
            align-items: center;
            gap: var(--boxel-sp-xs) var(--boxel-sp-sm);
          }
          .emb-id {
            flex: 1 1 12rem;
            min-width: 0;
          }
          .emb-title {
            margin: 0;
            font-size: var(--boxel-font-size-sm);
            font-weight: 600;
          }
          .emb-sub {
            margin: 0;
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          .emb-chips {
            display: flex;
            flex-wrap: wrap;
            gap: var(--boxel-sp-4xs);
          }
          .emb-fact {
            margin: 0;
            color: var(--muted-foreground);
          }
          .emb-kv {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(8rem, 1fr));
            gap: var(--boxel-sp-xs) var(--boxel-sp-sm);
            margin: 0;
          }
          .emb-kv dt {
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          .emb-kv dd {
            margin: 0;
            font-weight: 600;
            font-variant-numeric: tabular-nums;
          }
          .emb-rels {
            display: flex;
            flex-wrap: wrap;
            gap: var(--boxel-sp-xs) var(--boxel-sp-sm);
          }
          .emb-rel {
            display: inline-flex;
            flex-wrap: wrap;
            align-items: center;
            gap: var(--boxel-sp-4xs);
            min-width: 0;
            color: var(--muted-foreground);
          }
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    get hue() {
      return statusHue(CourseStatusField, this.args.model?.status);
    }
    <template>
      <span class='course-atom'>
        <Avatar
          @name='C o'
          @hue='var(--muted-foreground)'
          @size={{20}}
          aria-hidden='true'
        />
        <span class='course-atom-name'>{{@model.cardTitle}}</span>
        {{#if @model.status}}<span class='course-atom-chip'><StatePill
              @label={{courseStatusLabel @model.status}}
              @hue={{this.hue}}
            /></span>{{/if}}
      </span>
      <style scoped>
        @layer PretComponent {
          .course-atom {
            display: inline-flex;
            align-items: center;
            gap: var(--boxel-sp-4xs);
            max-width: 100%;
            min-width: 0;
            /* a chip that cannot fit whole wraps onto a clipped second line
               instead of showing half a word */
            flex-wrap: wrap;
            align-content: flex-start;
            block-size: 1.5rem;
            row-gap: 1.5rem;
            overflow: hidden;
            vertical-align: middle;
            font-size: var(--boxel-font-size-sm);
            font-weight: 600;
            line-height: 1.5;
            color: var(--foreground);
            white-space: nowrap;
          }
          .course-atom-name {
            flex: 1 1 4rem;
            min-width: 0;
            overflow: hidden;
            text-overflow: ellipsis;
          }
          .course-atom-chip {
            flex: none;
          }
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get hue() {
      return statusHue(CourseStatusField, this.args.model?.status);
    }
    get subtitle() {
      let m = this.args.model;
      return [m?.code, m?.levelLabel, formatCreditHours(m?.creditHours)]
        .filter(Boolean)
        .join(' · ');
    }
    get moduleChip() {
      let n = this.args.model?.moduleCount ?? 0;
      return `${n} ${n === 1 ? 'module' : 'modules'}`;
    }
    get fact() {
      let m = this.args.model;
      let n = m?.lessonCount ?? 0;
      return `${n} ${n === 1 ? 'lesson' : 'lessons'} · ${minutesLabel(m?.totalMinutes)} of material`;
    }
    get facts(): KeyValueItem[] {
      let m = this.args.model;
      return [
        { key: 'Level', value: m?.levelLabel || '—' },
        { key: 'Credit', value: formatCreditHours(m?.creditHours) },
        { key: 'Material', value: minutesLabel(m?.totalMinutes) },
        { key: 'Owner', value: m?.ownerName || '—' },
      ];
    }
    <template>
      {{! Owner is a fact, not a relation atom: the Employee atom (shared hr module) is taller than a FitTile relations line and half-cuts at 400x105 }}
      <FittedExtras @facts={{this.facts}}>
        <:default>
          <FitTile>
            <:avatar>
              <Avatar
                @name='C o'
                @hue='var(--muted-foreground)'
                @size={{32}}
                aria-hidden='true'
              />
            </:avatar>
            <:title><span
                class='fit-title'
                role='heading'
                aria-level='3'
              >{{@model.cardTitle}}</span></:title>
            <:subtitle>{{this.subtitle}}</:subtitle>
            <:status>
              <StatePill
                @label={{courseStatusLabel @model.status}}
                @hue={{this.hue}}
              />
              <StatePill @label={{this.moduleChip}} @hue='slate' />
            </:status>
            <:fact>{{this.fact}}</:fact>
          </FitTile>
        </:default>
      </FittedExtras>
      <style scoped>
        @layer PretComponent {
          .fit-title {
            display: block;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
          }
        }
      </style>
    </template>
  };
}

export default Course;
