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
import { AtomChip, Dot, Mark } from './components/record-sheet';
import { RichFittedCard } from '../shared/rich-fitted-card';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { Stat } from '@cardstack/pretui/components/stat';

import {
  DueWindowField,
  dueWindowState,
  dueWindowLabel,
  DUE_WINDOW_HUES,
} from '@cardstack/catalog/fields/due-window/due-window-field';
import { Rubric } from './rubric';
import { Module } from './course-module';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import { IsoFrame } from '../shared/compact-sheet';

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
      return this.title?.trim() || 'Untitled assignment';
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    get state() {
      return dueWindowState(this.args.model?.dueWindow);
    }
    <template>
      <IsoFrame>
        <article class='assignment'>
          <header class='hero'>
            <div class='hero-text'>
              <span class='eyebrow'>
                Assignment{{#if @model.code}} {{@model.code}}{{/if}}
                {{#if @model.required}}<StatePill
                    @label='Required'
                    @hue='amber'
                  />{{/if}}
                {{#if @model.module}} · <@fields.module @format='atom' />{{/if}}
              </span>
              <h1>{{@model.cardTitle}}</h1>
            </div>
            <div class='side'>
              <Stat
                @label='Points'
                @value={{orZero @model.effectiveMaxPoints}}
              />
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
            {{#if @model.brief.content}}
              <@fields.brief />
            {{else}}
              <EmptyState
                @size='s'
                @title='No brief yet'
                @message='Learners see this first: say what to hand in and how it is judged.'
              />
            {{/if}}
          </section>
          <section>
            <h2>Rubric</h2>
            {{#if @model.rubric}}
              <@fields.rubric @format='embedded' />
            {{else}}
              <EmptyState
                @size='s'
                @title='No rubric linked'
                @message='Submissions cannot be graded until one is.'
              />
            {{/if}}
          </section>
        </article>
      </IsoFrame>
      <style scoped>
        .assignment {
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
          color: var(--muted-foreground);
        }
        h1 {
          margin: var(--boxel-sp-4xs) 0 0;
          font-size: var(--boxel-font-size-xl);
          font-weight: 700;
          line-height: 1.15;
        }
        .side {
          flex: none;
          display: grid;
          gap: var(--boxel-sp-xs);
          justify-items: end;
        }
        .timing {
          display: flex;
          gap: var(--boxel-sp);
          align-items: center;
          flex-wrap: wrap;
          padding: var(--boxel-sp-sm) var(--boxel-sp);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          background: var(--card);
        }
        .note {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        h2 {
          margin: 0 0 var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-sm);
          text-transform: uppercase;
          letter-spacing: 0.06em;
          color: var(--muted-foreground);
        }
        .brief {
          line-height: 1.6;
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
          <span class='title'>{{@model.cardTitle}}</span>
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
          background: var(--muted);
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
      <AtomChip
        @mark={{if @model.code @model.code 'As'}}
        @title={{@model.cardTitle}}
      />
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get state() {
      return dueWindowState(this.args.model?.dueWindow);
    }
    <template>
      <RichFittedCard>
        <:avatar><Mark @text='As' /></:avatar>
        <:title>{{@model.cardTitle}}</:title>
        <:subtitle>{{if @model.code @model.code 'Assignment'}}
          ·
          {{@model.effectiveMaxPoints}}
          pts</:subtitle>
        <:status><Dot @hue={{hueFor this.state}}>{{dueWindowLabel
              this.state
            }}</Dot></:status>
        <:fact>{{@model.dueLabel}}</:fact>
      </RichFittedCard>
    </template>
  };
}

function hueFor(state: ReturnType<typeof dueWindowState>) {
  return DUE_WINDOW_HUES[state];
}

function orZero(n?: number | null): number {
  return n ?? 0;
}

export default Assignment;
