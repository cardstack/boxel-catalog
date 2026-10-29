import {
  CardDef,
  Component,
  StringField,
  contains,
  field,
  linksTo,
  linksToMany,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import NotebookIcon from '@cardstack/boxel-icons/notebook';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import { Avatar } from '../../ui-component/components/avatar';
import { FitTile } from '../../ui-component/components/fit-tile';
import {
  KeyValue,
  type KeyValueItem,
} from '../../ui-component/components/key-value';
import { Stat } from '../../ui-component/components/stat';
import { FittedExtras } from '../procurement/vendor';
import {
  AcademyAtom,
  AcademyEmbedded,
  AcademyIsolated,
  AcademyPanel,
  AcademyRel,
  AcademyRels,
  type FormatFact,
} from './components/card-formats';
import { EmptyState } from '../../ui-component/components/empty-state';
import { ReleaseRuleField, describeReleaseRule } from './release-rule-field';
import { Lesson, lessonMinutes, glyphFor } from './lesson';
import { Assignment } from './assignment';
import { Quiz } from './quiz';
import { Course } from './course';

/**
 * A week-or-so of a course: an ordered bundle of lessons with the assignments
 * and quizzes that check it. Modules are cards (not fields on Course) because
 * a Cohort releases them one at a time and an Attendance Record needs to say
 * which module's live lesson it belongs to. File is `course-module` to keep
 * clear of the Kernel's "Module Identifier"; the class is plain `Module`.
 */
export class Module extends CardDef {
  static displayName = 'Module';
  static icon = NotebookIcon;

  @field title = contains(StringField);
  @field code = contains(StringField, {
    description: 'Short code used in instructor assignments, e.g. M3.',
  });
  @field order = contains(NumberField);
  @field summary = contains(StringField);
  @field releaseRule = contains(ReleaseRuleField);
  @field course = linksTo(() => Course as any);
  @field lessons = linksToMany(() => Lesson);
  @field assignments = linksToMany(() => Assignment);
  @field quizzes = linksToMany(() => Quiz);

  @field lessonCount = contains(NumberField, {
    computeVia: function (this: Module) {
      return (this.lessons ?? []).length;
    },
  });
  @field liveLessonCount = contains(NumberField, {
    computeVia: function (this: Module) {
      return (this.lessons ?? []).filter((l: any) => l?.kind === 'live').length;
    },
  });
  @field totalMinutes = contains(NumberField, {
    computeVia: function (this: Module) {
      return (this.lessons ?? []).reduce(
        (n: number, l: any) => n + lessonMinutes(l?.duration),
        0,
      );
    },
  });
  @field releaseLabel = contains(StringField, {
    computeVia: function (this: Module) {
      return describeReleaseRule(this.releaseRule);
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: Module) {
      return this.title?.trim() || 'Untitled module';
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    get checks() {
      let m = this.args.model;
      return (m?.assignments ?? []).length + (m?.quizzes ?? []).length;
    }
    get details(): KeyValueItem[] {
      let m = this.args.model;
      return [
        { key: 'Code', value: m?.code || '—' },
        { key: 'Order', value: orderLabel(m?.order) },
        { key: 'Release', value: m?.releaseLabel || '—' },
        { key: 'Live lessons', value: String(m?.liveLessonCount ?? 0) },
      ];
    }
    <template>
      <AcademyIsolated
        @mark='Mo'
        @title={{@model.cardTitle}}
        @subtitle={{@model.summary}}
      >
        <:chips>
          <StatePill @label={{orderLabel @model.order}} @hue='slate' />
          <StatePill @label={{@model.releaseLabel}} @hue='blue' />
        </:chips>
        <:stats>
          <Stat
            @label='Lessons'
            @value={{if @model.lessonCount @model.lessonCount 0}}
            @hint='{{@model.liveLessonCount}} live'
            @roll={{false}}
          />
          <Stat
            @label='Time'
            @value={{minutesLabel @model.totalMinutes}}
            @hint='across all lessons'
            @roll={{false}}
          />
          <Stat
            @label='Checks'
            @value={{this.checks}}
            @hint='assignments and quizzes'
            @roll={{false}}
          />
        </:stats>
        <:main>
          <AcademyPanel @title='Lessons'>
            {{#if @model.lessons.length}}
              <ol class='lessons'>
                {{#each @model.lessons as |l|}}
                  <li>
                    <span class='glyph'>{{glyphFor l.kind}}</span>
                    <span class='l-title'>{{l.cardTitle}}</span>
                    <span class='l-kind'>{{l.kindLabel}}</span>
                    <span class='l-dur'>{{l.durationLabel}}</span>
                  </li>
                {{/each}}
              </ol>
            {{else}}
              <EmptyState
                @size='s'
                @title='No lessons linked yet'
                @message='Link lessons in edit mode, in the order a learner takes them.'
              />
            {{/if}}
          </AcademyPanel>
          {{#if @model.assignments.length}}
            <AcademyPanel @title='Assignments'>
              <div class='stack'><@fields.assignments
                  @format='embedded'
                /></div>
            </AcademyPanel>
          {{/if}}
          {{#if @model.quizzes.length}}
            <AcademyPanel @title='Quizzes'>
              <div class='stack'><@fields.quizzes @format='embedded' /></div>
            </AcademyPanel>
          {{/if}}
        </:main>
        <:side>
          <AcademyPanel @title='Linked'>
            <AcademyRels>
              <AcademyRel @label='Course'>{{#if @model.course}}<@fields.course
                    @format='atom'
                  />{{else}}—{{/if}}</AcademyRel>
            </AcademyRels>
          </AcademyPanel>
          <AcademyPanel @title='Details'>
            <KeyValue @items={{this.details}} @rows='ruled' />
          </AcademyPanel>
        </:side>
      </AcademyIsolated>
      <style scoped>
        @layer PretComponent {
          .lessons {
            list-style: none;
            margin: 0;
            padding: 0;
          }
          .lessons li {
            display: grid;
            grid-template-columns: auto minmax(0, 1fr) auto 5rem;
            gap: var(--boxel-sp-xs);
            align-items: center;
            padding: var(--boxel-sp-xs) 0;
          }
          .lessons li + li {
            border-top: 1px solid var(--border);
          }
          .glyph {
            width: 1.5rem;
            height: 1.5rem;
            display: grid;
            place-items: center;
            border-radius: var(--boxel-border-radius-sm);
            background: var(--muted);
            font-size: var(--boxel-font-size-xs);
          }
          .l-title {
            font-weight: 600;
            min-width: 0;
          }
          .l-kind,
          .l-dur {
            font-size: var(--boxel-font-size-sm);
            color: var(--muted-foreground);
          }
          .l-dur {
            text-align: end;
            font-variant-numeric: tabular-nums;
          }
          .stack {
            display: grid;
            gap: var(--boxel-sp-xs);
          }
          @container (width < 30rem) {
            .lessons li {
              grid-template-columns: auto minmax(0, 1fr) auto;
            }
            .l-kind {
              display: none;
            }
          }
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    get facts(): FormatFact[] {
      let m = this.args.model;
      return [
        { key: 'Order', value: orderLabel(m?.order) },
        { key: 'Lessons', value: String(m?.lessonCount ?? 0) },
        { key: 'Time', value: minutesLabel(m?.totalMinutes) },
        { key: 'Release', value: m?.releaseLabel || '—' },
      ];
    }
    <template>
      <AcademyEmbedded
        @mark='Mo'
        @title={{@model.cardTitle}}
        @subtitle={{@model.summary}}
        @facts={{this.facts}}
      >
        <:chips><StatePill
            @label={{if @model.code @model.code (orderLabel @model.order)}}
            @hue='slate'
          /></:chips>
        <:relations>
          {{#if @model.course}}<span>Course
              <@fields.course @format='atom' /></span>{{/if}}
        </:relations>
      </AcademyEmbedded>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <AcademyAtom @mark='Mo' @name={{@model.cardTitle}}>
        <StatePill
          @label={{if @model.code @model.code (orderLabel @model.order)}}
          @hue='slate'
        />
      </AcademyAtom>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get subtitle() {
      return this.args.model?.summary ?? '';
    }
    get fact() {
      return this.args.model?.releaseLabel ?? '';
    }
    get facts(): KeyValueItem[] {
      let m = this.args.model;
      return [
        { key: 'Lessons', value: String(m?.lessonCount ?? 0) },
        { key: 'Time', value: minutesLabel(m?.totalMinutes) },
        { key: 'Order', value: orderLabel(m?.order) },
      ];
    }
    get relations() {
      return this.args.model?.course ? ['Course'] : [];
    }
    <template>
      <FittedExtras @facts={{this.facts}} @relations={{this.relations}}>
        <:default>
          <FitTile>
            <:avatar>
              <Avatar
                @name='Mo'
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
            <:status><StatePill
                @label={{if @model.code @model.code (orderLabel @model.order)}}
                @hue='slate'
              /></:status>
            <:fact>{{this.fact}}</:fact>
          </FitTile>
        </:default>
        <:relation><@fields.course @format='atom' /></:relation>
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

export function orderLabel(order?: number | null): string {
  return order != null ? `M${order}` : 'M?';
}

export function minutesLabel(min?: number | null): string {
  if (!min) return '0 min';
  if (min < 60) return `${min} min`;
  let h = Math.floor(min / 60);
  let m = min % 60;
  return m ? `${h}h ${m}m` : `${h}h`;
}

export default Module;
