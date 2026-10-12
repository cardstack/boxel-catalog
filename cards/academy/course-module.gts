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
import { FieldContainer } from '@cardstack/boxel-ui/components';

import { SectionedEdit } from '@cardstack/catalog/components/sectioned-edit';

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
      let t = this.title?.trim() || 'Untitled module';
      return this.code ? `${this.code} · ${t}` : t;
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    <template>
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
            <h1>{{if @model.title @model.title 'Untitled module'}}</h1>
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
            <p class='empty'>No lessons linked yet.</p>
          {{/if}}
        </section>
        {{#if @model.assignments.length}}
          <section>
            <h2>Assignments</h2>
            <div class='stack'><@fields.assignments @format='embedded' /></div>
          </section>
        {{/if}}
        {{#if @model.quizzes.length}}
          <section>
            <h2>Quizzes</h2>
            <div class='stack'><@fields.quizzes @format='embedded' /></div>
          </section>
        {{/if}}
      </article>
      <style scoped>
        .module {
          max-width: 52rem;
          margin: 0 auto;
          container-type: inline-size;
          padding: var(--boxel-sp-xl) var(--boxel-sp-lg);
          display: grid;
          gap: var(--boxel-sp-lg);
          color: var(--foreground, var(--boxel-dark));
          background: var(--background, var(--boxel-light));
        }
        .hero {
          display: grid;
          grid-template-columns: auto 1fr;
          gap: var(--boxel-sp);
          align-items: start;
        }
        .code {
          min-width: 3.25rem;
          height: 3.25rem;
          padding: 0 var(--boxel-sp-xs);
          display: grid;
          place-items: center;
          border-radius: var(--radius, var(--boxel-border-radius));
          background: color-mix(
            in oklab,
            var(--primary, var(--boxel-highlight)) 14%,
            var(--card, var(--boxel-light))
          );
          font: 700 var(--boxel-font-size)
            var(--font-mono, ui-monospace, monospace);
        }
        .eyebrow {
          font-size: var(--boxel-font-size-xs);
          text-transform: uppercase;
          letter-spacing: 0.06em;
          color: var(--muted-foreground, var(--boxel-450));
        }
        h1 {
          margin: var(--boxel-sp-4xs) 0 0;
          font: 700 var(--boxel-font-size-xl) / 1.15
            var(--font-heading, var(--boxel-font-family));
        }
        .summary {
          margin: var(--boxel-sp-xs) 0 0;
        }
        .meta {
          margin: var(--boxel-sp-xs) 0 0;
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground, var(--boxel-450));
        }
        h2 {
          margin: 0 0 var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-sm);
          text-transform: uppercase;
          letter-spacing: 0.06em;
          color: var(--muted-foreground, var(--boxel-450));
        }
        .lessons {
          list-style: none;
          margin: 0;
          padding: 0;
          border: 1px solid var(--border, var(--boxel-200));
          border-radius: var(--radius, var(--boxel-border-radius));
          background: var(--card, var(--boxel-light));
        }
        .lessons li {
          display: grid;
          grid-template-columns: auto 1fr auto 5rem;
          gap: var(--boxel-sp-xs);
          align-items: center;
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .lessons li + li {
          border-top: 1px solid var(--border, var(--boxel-200));
        }
        .glyph {
          width: 1.5rem;
          height: 1.5rem;
          display: grid;
          place-items: center;
          border-radius: var(--boxel-border-radius-sm);
          background: var(--muted, var(--boxel-100));
          font-size: var(--boxel-font-size-xs);
        }
        .l-title {
          font-weight: 600;
        }
        .l-kind,
        .l-dur {
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground, var(--boxel-450));
        }
        .l-dur {
          text-align: end;
          font-variant-numeric: tabular-nums;
        }
        .stack {
          display: grid;
          gap: var(--boxel-sp-xs);
        }
        .empty {
          color: var(--muted-foreground, var(--boxel-450));
          font-style: italic;
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
          <span class='title'>{{if
              @model.title
              @model.title
              'Untitled module'
            }}</span>
          <span class='sub'>{{@model.lessonCount}}
            lessons ·
            {{minutesLabel @model.totalMinutes}}</span>
        </div>
        <span class='rel'>{{@model.releaseLabel}}</span>
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
          background: color-mix(
            in oklab,
            var(--primary, var(--boxel-highlight)) 14%,
            var(--card, var(--boxel-light))
          );
          font: 700 var(--boxel-font-size-xs)
            var(--font-mono, ui-monospace, monospace);
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
          color: var(--muted-foreground, var(--boxel-450));
        }
        .rel {
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='atom'>{{@model.cardTitle}}</span>
      <style scoped>
        .atom {
          font-size: var(--boxel-font-size-sm);
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static edit = class Edit extends Component<typeof this> {
    sections = [
      { id: 'identity', label: 'Identity' },
      { id: 'release', label: 'Release' },
      { id: 'contents', label: 'Contents' },
    ];
    <template>
      <SectionedEdit
        @sections={{this.sections}}
        @ariaLabel='Module sections'
        as |e|
      >
        <e.Section @id='identity' @title='Identity' @cols={{3}}>
          <FieldContainer @label='Title' @vertical={{true}}><@fields.title
            /></FieldContainer>
          <FieldContainer @label='Code' @vertical={{true}}><@fields.code
            /></FieldContainer>
          <FieldContainer @label='Order' @vertical={{true}}><@fields.order
            /></FieldContainer>
          <FieldContainer @label='Course' @vertical={{true}}><@fields.course
            /></FieldContainer>
          <FieldContainer @label='Summary' @vertical={{true}}><@fields.summary
            /></FieldContainer>
        </e.Section>
        <e.Section
          @id='release'
          @title='Release'
          @hint='the plan; releases themselves are recorded on the cohort'
          @cols={{1}}
        >
          <FieldContainer
            @label='Release rule'
            @vertical={{true}}
          ><@fields.releaseRule /></FieldContainer>
        </e.Section>
        <e.Section @id='contents' @title='Contents' @cols={{1}}>
          <FieldContainer
            @label='Lessons (in order)'
            @vertical={{true}}
          ><@fields.lessons /></FieldContainer>
          <FieldContainer
            @label='Assignments'
            @vertical={{true}}
          ><@fields.assignments /></FieldContainer>
          <FieldContainer @label='Quizzes' @vertical={{true}}><@fields.quizzes
            /></FieldContainer>
        </e.Section>
      </SectionedEdit>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <article class='fit'>
        <div class='fit-top'>
          <span class='code'>{{if
              @model.code
              @model.code
              (orderLabel @model.order)
            }}</span>
          <div class='fit-head'>
            <h3 class='fit-name'>{{if
                @model.title
                @model.title
                'Untitled module'
              }}</h3>
            <span class='fit-eb'>{{@model.lessonCount}}
              lessons ·
              {{minutesLabel @model.totalMinutes}}</span>
          </div>
        </div>
        {{#if @model.summary}}<p class='fit-sum'>{{@model.summary}}</p>{{/if}}
        <span class='fit-foot'>{{@model.releaseLabel}}</span>
      </article>
      <style scoped>
        .fit {
          height: 100%;
          padding: var(--boxel-sp-xs);
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-4xs);
          overflow: hidden;
        }
        .fit-top {
          display: flex;
          gap: var(--boxel-sp-xs);
          align-items: flex-start;
          min-width: 0;
        }
        .code {
          flex: none;
          min-width: 2rem;
          height: 2rem;
          padding: 0 var(--boxel-sp-4xs);
          display: grid;
          place-items: center;
          border-radius: var(--boxel-border-radius-sm);
          background: color-mix(
            in oklab,
            var(--primary, var(--boxel-highlight)) 14%,
            var(--card, var(--boxel-light))
          );
          font: 700 var(--boxel-font-size-xs)
            var(--font-mono, ui-monospace, monospace);
        }
        .fit-head {
          min-width: 0;
        }
        .fit-name {
          margin: 0;
          font-size: var(--boxel-font-size-sm);
          font-weight: 700;
          line-height: 1.2;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
          overflow: hidden;
        }
        .fit-eb {
          font-size: 11px;
          color: var(--muted-foreground, var(--boxel-450));
        }
        .fit-sum,
        .fit-foot {
          display: none;
          margin: 0;
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
        }
        @container fitted-card (height <= 80px) {
          .fit-top {
            align-items: center;
          }
          .fit-name {
            -webkit-line-clamp: 1;
          }
        }
        @container fitted-card (width <= 150px) {
          .fit-eb {
            display: none;
          }
        }
        @container fitted-card (width <= 120px) {
          .fit-top {
            flex-direction: column;
            align-items: flex-start;
          }
          .fit-eb {
            display: none;
          }
        }
        @container fitted-card (min-width: 250px) and (min-height: 120px) {
          .fit-add {
            display: block;
            margin-top: auto;
          }
        }
        @container fitted-card (min-width: 150px) and (min-height: 190px) {
          .fit-sum {
            display: -webkit-box;
            -webkit-line-clamp: 3;
            -webkit-box-orient: vertical;
            overflow: hidden;
          }
          .fit-foot {
            display: block;
            margin-top: auto;
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
