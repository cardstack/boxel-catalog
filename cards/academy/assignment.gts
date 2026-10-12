import {
  CardDef,
  Component,
  StringField,
  contains,
  field,
  linksTo,
} from '@cardstack/base/card-api';
import BooleanField from '@cardstack/base/boolean';
import NumberField from '@cardstack/base/number';
import { RichMarkdownField } from '@cardstack/base/rich-markdown';
import ClipboardListIcon from '@cardstack/boxel-icons/clipboard-list';
import { FieldContainer } from '@cardstack/boxel-ui/components';

import { SectionedEdit } from '@cardstack/catalog/components/sectioned-edit';

import {
  DueWindowField,
  dueWindowState,
  dueWindowLabel,
  DUE_WINDOW_HUES,
} from '@cardstack/catalog/fields/due-window/due-window-field';
import { Rubric } from './rubric';
import { Module } from './course-module';
import { StatePill } from '@cardstack/catalog/components/state-pill';

/**
 * A piece of work a learner hands in. Owns the brief and the timing; borrows
 * its scoring from a Rubric so the same grid can grade three assignments.
 * `maxPoints` defaults to the rubric total but can be set lower to scale the
 * assignment's weight in the gradebook. Submissions link back here.
 */
export class Assignment extends CardDef {
  static displayName = 'Assignment';
  static icon = ClipboardListIcon;

  @field title = contains(StringField);
  @field code = contains(StringField, {
    description: 'Short label used in the gradebook header, e.g. A2.',
  });
  @field brief = contains(RichMarkdownField);
  @field dueWindow = contains(DueWindowField);
  @field required = contains(BooleanField, {
    description: 'Required assignments count toward completion.',
  });
  @field allowResubmission = contains(BooleanField);
  @field maxPoints = contains(NumberField, {
    description: 'Leave empty to use the rubric total.',
  });
  @field rubric = linksTo(() => Rubric);
  @field module = linksTo(() => Module as any);

  @field effectiveMaxPoints = contains(NumberField, {
    computeVia: function (this: Assignment) {
      return this.maxPoints ?? this.rubric?.totalPoints ?? 0;
    },
  });
  @field dueLabel = contains(StringField, {
    computeVia: function (this: Assignment) {
      return this.dueWindow?.summary ?? 'No due date';
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: Assignment) {
      let t = this.title?.trim() || 'Untitled assignment';
      return this.code ? `${this.code} · ${t}` : t;
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    get state() {
      return dueWindowState(this.args.model?.dueWindow);
    }
    <template>
      <article class='assignment'>
        <header class='hero'>
          <div class='hero-text'>
            <span class='eyebrow'>
              Assignment{{#if @model.code}} {{@model.code}}{{/if}}
              {{#if @model.required}}<span class='req'>Required</span>{{/if}}
              {{#if @model.module}} · <@fields.module @format='atom' />{{/if}}
            </span>
            <h1>{{if @model.title @model.title 'Untitled assignment'}}</h1>
          </div>
          <div class='side'>
            <div class='pts'><span
                class='pts-n'
              >{{@model.effectiveMaxPoints}}</span><span
                class='pts-l'
              >points</span></div>
            <StatePill
              @label={{dueWindowLabel this.state}}
              @hue={{hueFor this.state}}
              @dot={{true}}
            />
          </div>
        </header>
        <section class='timing'>
          <@fields.dueWindow @format='embedded' />
          {{#if @model.allowResubmission}}<span class='note'>Resubmission
              allowed</span>{{/if}}
        </section>
        <section class='brief'>
          <h2>Brief</h2>
          {{#if @model.brief}}
            <@fields.brief />
          {{else}}
            <p class='empty'>No brief yet. Learners will see this text first —
              say what to hand in and how it is judged.</p>
          {{/if}}
        </section>
        <section>
          <h2>Rubric</h2>
          {{#if @model.rubric}}
            <@fields.rubric @format='embedded' />
          {{else}}
            <p class='empty'>No rubric linked. Grade Submission will refuse
              until one is.</p>
          {{/if}}
        </section>
      </article>
      <style scoped>
        .assignment {
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
          display: flex;
          justify-content: space-between;
          gap: var(--boxel-sp);
          align-items: flex-start;
        }
        .eyebrow {
          display: inline-flex;
          gap: var(--boxel-sp-xs);
          align-items: center;
          font-size: var(--boxel-font-size-xs);
          text-transform: uppercase;
          letter-spacing: 0.06em;
          color: var(--muted-foreground, var(--boxel-450));
        }
        .req {
          padding: 1px var(--boxel-sp-xs);
          border-radius: 999px;
          background: color-mix(
            in oklab,
            var(--boxel-warning) 14%,
            var(--card, var(--boxel-light))
          );
          color: color-mix(
            in oklab,
            var(--boxel-warning) 45%,
            var(--card-foreground, var(--boxel-dark))
          );
          font-weight: 600;
        }
        h1 {
          margin: var(--boxel-sp-4xs) 0 0;
          font: 700 var(--boxel-font-size-xl) / 1.15
            var(--font-heading, var(--boxel-font-family));
        }
        .side {
          flex: none;
          display: grid;
          gap: var(--boxel-sp-xs);
          justify-items: end;
        }
        .pts {
          display: grid;
          justify-items: center;
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          border-radius: var(--radius, var(--boxel-border-radius));
          background: color-mix(
            in oklab,
            var(--primary, var(--boxel-highlight)) 14%,
            var(--card, var(--boxel-light))
          );
        }
        .pts-n {
          font-size: var(--boxel-font-size-lg);
          font-weight: 700;
          font-variant-numeric: tabular-nums;
          line-height: 1;
        }
        .pts-l {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
        }
        .timing {
          display: flex;
          gap: var(--boxel-sp);
          align-items: center;
          flex-wrap: wrap;
          padding: var(--boxel-sp-sm) var(--boxel-sp);
          border: 1px solid var(--border, var(--boxel-200));
          border-radius: var(--radius, var(--boxel-border-radius));
          background: var(--card, var(--boxel-light));
        }
        .note {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
        }
        h2 {
          margin: 0 0 var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-sm);
          text-transform: uppercase;
          letter-spacing: 0.06em;
          color: var(--muted-foreground, var(--boxel-450));
        }
        .brief {
          line-height: 1.6;
        }
        .empty {
          color: var(--muted-foreground, var(--boxel-450));
          font-style: italic;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    get state() {
      return dueWindowState(this.args.model?.dueWindow);
    }
    <template>
      <div class='row'>
        <span class='code'>{{if @model.code @model.code 'A'}}</span>
        <div class='text'>
          <span class='title'>{{if
              @model.title
              @model.title
              'Untitled assignment'
            }}</span>
          <span class='sub'>{{@model.dueLabel}}{{#if @model.required}}
              · required{{/if}}</span>
        </div>
        <StatePill
          @label={{dueWindowLabel this.state}}
          @hue={{hueFor this.state}}
        />
        <span class='pts'>{{@model.effectiveMaxPoints}} pts</span>
      </div>
      <style scoped>
        .row {
          display: grid;
          grid-template-columns: auto 1fr auto 4.5rem;
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
            var(--boxel-warning) 14%,
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
        .sub {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
        }
        .pts {
          text-align: end;
          font-variant-numeric: tabular-nums;
          font-weight: 600;
          font-size: var(--boxel-font-size-sm);
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
      { id: 'brief', label: 'Brief' },
      { id: 'timing', label: 'Timing' },
      { id: 'grading', label: 'Grading' },
    ];
    <template>
      <SectionedEdit
        @sections={{this.sections}}
        @ariaLabel='Assignment sections'
        as |e|
      >
        <e.Section @id='identity' @title='Identity' @cols={{3}}>
          <FieldContainer @label='Title' @vertical={{true}}><@fields.title
            /></FieldContainer>
          <FieldContainer @label='Code' @vertical={{true}}><@fields.code
            /></FieldContainer>
          <FieldContainer @label='Module' @vertical={{true}}><@fields.module
            /></FieldContainer>
          <FieldContainer
            @label='Required for completion'
            @vertical={{true}}
          ><@fields.required /></FieldContainer>
          <FieldContainer
            @label='Allow resubmission'
            @vertical={{true}}
          ><@fields.allowResubmission /></FieldContainer>
        </e.Section>
        <e.Section
          @id='brief'
          @title='Brief'
          @hint='what to hand in and how it is judged'
          @cols={{1}}
        >
          <FieldContainer @label='Brief' @vertical={{true}}><@fields.brief
            /></FieldContainer>
        </e.Section>
        <e.Section
          @id='timing'
          @title='Timing'
          @hint='leave hard close empty to use the course late policy'
          @cols={{1}}
        >
          <FieldContainer
            @label='Due window'
            @vertical={{true}}
          ><@fields.dueWindow /></FieldContainer>
        </e.Section>
        <e.Section @id='grading' @title='Grading' @cols={{2}}>
          <FieldContainer @label='Rubric' @vertical={{true}}><@fields.rubric
            /></FieldContainer>
          <FieldContainer
            @label='Max points (empty = rubric total)'
            @vertical={{true}}
          ><@fields.maxPoints /></FieldContainer>
        </e.Section>
      </SectionedEdit>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get state() {
      return dueWindowState(this.args.model?.dueWindow);
    }
    <template>
      <article class='fit'>
        <div class='fit-top'>
          <span class='code'>{{if @model.code @model.code 'A'}}</span>
          <div class='fit-head'>
            <h3 class='fit-name'>{{if
                @model.title
                @model.title
                'Untitled assignment'
              }}</h3>
            <span class='fit-eb'>{{@model.effectiveMaxPoints}}
              pts{{#if @model.required}} · required{{/if}}</span>
          </div>
          <span class='fit-pill'><StatePill
              @label={{dueWindowLabel this.state}}
              @hue={{hueFor this.state}}
            /></span>
        </div>
        <span class='fit-due'>{{@model.dueLabel}}</span>
        <dl class='fit-add'>
          {{#if @model.rubric}}<div><dt>Rubric</dt><dd
              >{{@model.rubric.cardTitle}}</dd></div>{{/if}}
          <div><dt>Resubmit</dt><dd>{{if
                @model.allowResubmission
                'Allowed'
                'No'
              }}</dd></div>
        </dl>
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
            var(--boxel-warning) 14%,
            var(--card, var(--boxel-light))
          );
          font: 700 var(--boxel-font-size-xs)
            var(--font-mono, ui-monospace, monospace);
        }
        .fit-head {
          min-width: 0;
          flex: 1;
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
        .fit-pill {
          flex: none;
        }
        .fit-due {
          display: none;
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
        }
        .fit-add {
          display: none;
          margin: 0;
          font-size: var(--boxel-font-size-xs);
        }
        .fit-add div {
          display: flex;
          justify-content: space-between;
          gap: var(--boxel-sp-xs);
          padding: 2px 0;
          border-top: 1px solid var(--border, var(--boxel-200));
        }
        dt {
          color: var(--muted-foreground, var(--boxel-450));
        }
        dd {
          margin: 0;
          font-weight: 600;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        @container fitted-card (height <= 80px) {
          .fit-top {
            align-items: center;
          }
          .fit-name {
            -webkit-line-clamp: 1;
          }
        }
        @container fitted-card (width <= 220px) {
          .fit-pill {
            display: none;
          }
        }
        @container fitted-card (min-height: 120px) {
          .fit-due {
            display: block;
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
          .fit-add {
            display: block;
            margin-top: auto;
          }
        }
      </style>
    </template>
  };
}

function hueFor(state: ReturnType<typeof dueWindowState>) {
  return DUE_WINDOW_HUES[state];
}

export default Assignment;
