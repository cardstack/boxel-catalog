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
import { EmptyState } from '@cardstack/pretui/components/empty-state';

import { ReleaseRuleField, describeReleaseRule } from './release-rule-field';
import { Lesson, lessonMinutes, glyphFor } from './lesson';
import { Assignment } from './assignment';
import { Quiz } from './quiz';
import { Course } from './course';
import { Mark } from './components/record-sheet';
import { RichFittedCard, Detail, Metric } from '../shared/rich-fitted-card';
import { IsoFrame } from '../shared/compact-sheet';

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
    <template>
      <IsoFrame>
        <article class='module'>
          <header class='hero'>
            <span class='code'>{{if
                @model.code
                @model.code
                (orderLabel @model.order)
              }}</span>
            <div class='hero-text'>
              <span class='eyebrow'>Module{{#if @model.course}}
                  of
                  <@fields.course @format='atom' />{{/if}}</span>
              <h1>{{@model.cardTitle}}</h1>
              {{#if @model.summary}}<p
                  class='summary'
                >{{@model.summary}}</p>{{/if}}
              <p class='meta'>{{@model.lessonCount}}
                lessons ·
                {{minutesLabel @model.totalMinutes}}
                ·
                {{@model.releaseLabel}}</p>
            </div>
          </header>
          <section>
            <h2>Lessons</h2>
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
          </section>
          {{#if @model.assignments.length}}
            <section>
              <h2>Assignments</h2>
              <div class='stack'><@fields.assignments
                  @format='embedded'
                /></div>
            </section>
          {{/if}}
          {{#if @model.quizzes.length}}
            <section>
              <h2>Quizzes</h2>
              <div class='stack'><@fields.quizzes @format='embedded' /></div>
            </section>
          {{/if}}
        </article>
      </IsoFrame>
      <style scoped>
        .module {
          background: var(--card);
          color: var(--card-foreground);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          max-width: 52rem;
          margin: 0 auto;
          inline-size: 100%;
          container-type: inline-size;
          padding: var(--boxel-sp-xl) var(--boxel-sp-lg);
          display: grid;
          gap: var(--boxel-sp-lg);
          color: var(--foreground);
        }
        .hero {
          display: grid;
          grid-template-columns: auto minmax(0, 1fr);
          gap: var(--boxel-sp);
          align-items: start;
        }
        .code {
          min-width: 3.25rem;
          height: 3.25rem;
          padding: 0 var(--boxel-sp-xs);
          display: grid;
          place-items: center;
          border-radius: var(--radius);
          background: color-mix(in oklab, var(--primary) 14%, var(--card));
          font-size: var(--boxel-font-size);
          font-weight: 700;
          font-family: var(--font-mono);
        }
        .eyebrow {
          display: block;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          font-size: var(--boxel-font-size-xs);
          text-transform: uppercase;
          letter-spacing: 0.06em;
          color: var(--muted-foreground);
        }
        h1 {
          margin: var(--boxel-sp-4xs) 0 0;
          font-size: var(--boxel-font-size-xl);
          font-weight: 700;
          line-height: 1.15;
        }
        .summary {
          margin: var(--boxel-sp-xs) 0 0;
        }
        .meta {
          margin: var(--boxel-sp-xs) 0 0;
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
        }
        h2 {
          margin: 0 0 var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-sm);
          text-transform: uppercase;
          letter-spacing: 0.06em;
          color: var(--muted-foreground);
        }
        .lessons {
          list-style: none;
          margin: 0;
          padding: 0;
          border: 1px solid var(--border);
          border-radius: var(--radius);
          background: var(--card);
        }
        .lessons li {
          display: grid;
          grid-template-columns: auto minmax(0, 1fr) auto 5rem;
          gap: var(--boxel-sp-xs);
          align-items: center;
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
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
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='row'>
        <span class='code'>{{if
            @model.code
            @model.code
            (orderLabel @model.order)
          }}</span>
        <div class='text'>
          <span class='title'>{{@model.cardTitle}}</span>
          <span class='sub'>{{@model.lessonCount}}
            lessons ·
            {{minutesLabel @model.totalMinutes}}</span>
        </div>
        <span class='rel'>{{@model.releaseLabel}}</span>
      </div>
      <style scoped>
        .row {
          display: grid;
          grid-template-columns: auto minmax(0, 1fr) auto;
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
        .sub,
        .rel {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        .rel {
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='atom'>{{#if @model.code}}{{@model.code}}
          ·
        {{/if}}{{@model.cardTitle}}</span>
      <style scoped>
        .atom {
          font-size: var(--boxel-font-size-sm);
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <RichFittedCard>
        <:avatar><Mark @text='Md' /></:avatar>
        <:title>{{@model.cardTitle}}</:title>
        <:subtitle>{{if @model.code @model.code (orderLabel @model.order)}}
          ·
          {{@model.lessonCount}}
          lessons ·
          {{minutesLabel @model.totalMinutes}}</:subtitle>
        <:fact>{{@model.releaseLabel}}</:fact>
        <:metric><Metric
            @value={{minutesLabel @model.totalMinutes}}
            @label='Duration'
          /></:metric>
        <:details>
          {{#if @model.course}}<Detail @label='Course'><@fields.course
                @format='atom'
                @displayContainer={{false}}
              /></Detail>{{/if}}
          {{#if @model.liveLessonCount}}<Detail
              @label='Live lessons'
              @value='{{@model.liveLessonCount}}'
            />{{/if}}
          {{#if @model.assignments.length}}<Detail
              @label='Assignments'
              @value='{{@model.assignments.length}}'
            />{{/if}}
          {{#if @model.quizzes.length}}<Detail
              @label='Quizzes'
              @value='{{@model.quizzes.length}}'
            />{{/if}}
        </:details>
      </RichFittedCard>
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
