import {
  CardDef,
  Component,
  StringField,
  contains,
  containsMany,
  field,
} from '@cardstack/base/card-api';
import BooleanField from '@cardstack/base/boolean';
import NumberField from '@cardstack/base/number';
import PercentageField from '@cardstack/base/percentage';
import HelpCircleIcon from '@cardstack/boxel-icons/help-circle';
import { FieldContainer, FittedCard } from '@cardstack/boxel-ui/components';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { KeyValue } from '@cardstack/pretui/components/key-value';

import { SectionedEdit } from '@cardstack/catalog/components/sectioned-edit';

import { DurationField } from '../hr/duration-field';
import { QuizQuestionField, pointsOf } from './quiz-question-field';

/**
 * A scored, auto-marked check of understanding. Questions are contained (a
 * quiz owns its questions; nothing else links to one), attempts are separate
 * cards (Quiz Attempt) because they belong to an enrollment. `totalPoints` is
 * computed; `passMarkPct` is the one number an instructor sets.
 */
export class Quiz extends CardDef {
  static displayName = 'Quiz';
  static icon = HelpCircleIcon;

  @field title = contains(StringField);
  @field instructions = contains(StringField);
  @field questions = containsMany(QuizQuestionField);
  @field passMarkPct = contains(PercentageField);
  @field attemptsAllowed = contains(NumberField, {
    description: '0 or empty = unlimited.',
  });
  @field timeLimit = contains(DurationField);
  @field shuffleQuestions = contains(BooleanField);

  @field totalPoints = contains(NumberField, {
    computeVia: function (this: Quiz): number {
      return quizTotalPoints(this);
    },
  });
  @field questionCount = contains(NumberField, {
    computeVia: function (this: Quiz) {
      return (this.questions ?? []).length;
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: Quiz) {
      return this.title?.trim() || 'Untitled quiz';
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    get facts() {
      let m = this.args.model;
      return [
        { key: 'Pass mark', value: `${m?.passMarkPct ?? 0}%` },
        { key: 'Attempts', value: attemptsLabel(m?.attemptsAllowed) },
        {
          key: 'Time limit',
          value: m?.timeLimit?.value ? concatDuration(m.timeLimit) : 'None',
        },
      ];
    }
    <template>
      <article class='quiz'>
        <header class='hero'>
          <div>
            <span class='eyebrow'>Quiz ·
              {{@model.questionCount}}
              questions ·
              {{@model.totalPoints}}
              pts</span>
            <h1>{{@model.cardTitle}}</h1>
            {{#if @model.instructions}}<p
                class='instr'
              >{{@model.instructions}}</p>{{/if}}
          </div>
          <KeyValue class='facts' @items={{this.facts}} @layout='stacked' />
        </header>
        {{#if @model.questions.length}}
          <ol class='questions'>
            {{#each @fields.questions as |Question index|}}
              <li class='q'>
                <span class='q-n'>{{inc index}}</span>
                <div class='q-body'><Question /></div>
              </li>
            {{/each}}
          </ol>
        {{else}}
          <EmptyState
            @size='s'
            @title='No questions yet'
            @message='Add questions in edit mode; each one carries its own points.'
          />
        {{/if}}
      </article>
      <style scoped>
        .quiz {
          max-width: 52rem;
          margin: 0 auto;
          container-type: inline-size;
          padding: var(--boxel-sp-xl) var(--boxel-sp-lg);
          display: grid;
          gap: var(--boxel-sp-lg);
          color: var(--foreground);
          background: var(--background);
        }
        .hero {
          display: flex;
          justify-content: space-between;
          gap: var(--boxel-sp);
          align-items: flex-start;
          flex-wrap: wrap;
        }
        .eyebrow {
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
        .instr {
          margin: var(--boxel-sp-xs) 0 0;
          color: var(--muted-foreground);
        }
        .facts {
          padding: var(--boxel-sp-sm) var(--boxel-sp);
          border-radius: var(--radius);
          background: var(--card);
          border: 1px solid var(--border);
        }
        .questions {
          list-style: none;
          margin: 0;
          padding: 0;
          display: grid;
          gap: var(--boxel-sp-sm);
        }
        .q {
          display: grid;
          grid-template-columns: auto minmax(0, 1fr);
          gap: var(--boxel-sp-sm);
          padding: var(--boxel-sp);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          background: var(--card);
        }
        .q-n {
          width: 1.75rem;
          height: 1.75rem;
          display: grid;
          place-items: center;
          border-radius: 50%;
          background: color-mix(in oklab, var(--primary) 14%, var(--card));
          font-weight: 700;
          font-size: var(--boxel-font-size-sm);
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='row'>
        <span class='title'>{{@model.cardTitle}}</span>
        <span class='meta'>{{@model.questionCount}}
          q · pass
          {{if @model.passMarkPct @model.passMarkPct 0}}%</span>
        <span class='pts'>{{@model.totalPoints}} pts</span>
      </div>
      <style scoped>
        .row {
          display: grid;
          grid-template-columns: minmax(0, 1fr) auto 5rem;
          gap: var(--boxel-sp-xs);
          align-items: center;
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .title {
          font-weight: 600;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .meta {
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
          white-space: nowrap;
        }
        .pts {
          text-align: end;
          font-variant-numeric: tabular-nums;
          font-weight: 600;
        }
        @container (width < 20rem) {
          .row {
            grid-template-columns: minmax(0, 1fr) auto;
          }
          .meta {
            display: none;
          }
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='atom'>? {{@model.cardTitle}}</span>
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
      { id: 'rules', label: 'Rules' },
      { id: 'instructions', label: 'Instructions' },
      { id: 'questions', label: 'Questions' },
    ];
    <template>
      <SectionedEdit
        @sections={{this.sections}}
        @ariaLabel='Quiz sections'
        as |e|
      >
        <e.Section @id='identity' @title='Identity' @cols={{1}}>
          <FieldContainer @label='Title' @vertical={{true}}><@fields.title
            /></FieldContainer>
        </e.Section>
        <e.Section @id='rules' @title='Rules' @cols={{2}}>
          <FieldContainer
            @label='Pass mark %'
            @vertical={{true}}
          ><@fields.passMarkPct /></FieldContainer>
          <FieldContainer
            @label='Attempts allowed (0 = unlimited)'
            @vertical={{true}}
          ><@fields.attemptsAllowed /></FieldContainer>
          <FieldContainer
            @label='Time limit'
            @vertical={{true}}
          ><@fields.timeLimit /></FieldContainer>
          <FieldContainer
            @label='Shuffle questions'
            @vertical={{true}}
          ><@fields.shuffleQuestions /></FieldContainer>
        </e.Section>
        <e.Section @id='instructions' @title='Instructions' @cols={{1}}>
          <FieldContainer
            @label='Shown before the first question'
            @vertical={{true}}
          ><@fields.instructions /></FieldContainer>
        </e.Section>
        <e.Section
          @id='questions'
          @title='Questions'
          @hint='mark at least one option correct per question'
          @cols={{1}}
        >
          <FieldContainer
            @label='Questions'
            @vertical={{true}}
          ><@fields.questions /></FieldContainer>
        </e.Section>
      </SectionedEdit>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <FittedCard @titleTag='h3'>
        <:eyebrow>Quiz ·
          {{@model.questionCount}}
          questions</:eyebrow>
        <:title>{{@model.cardTitle}}</:title>
        <:subtitle>{{@model.instructions}}</:subtitle>
        <:footer>Pass
          {{if @model.passMarkPct @model.passMarkPct 0}}% ·
          {{attemptsLabel @model.attemptsAllowed}}
          attempts{{#if @model.timeLimit.value}}
            ·
            {{concatDuration @model.timeLimit}}{{/if}}</:footer>
      </FittedCard>
    </template>
  };
}

export function quizTotalPoints(q: Partial<Quiz> | null | undefined): number {
  return (q?.questions ?? []).reduce(
    (sum: number, x: any) => sum + pointsOf(x),
    0,
  );
}

export function attemptsLabel(n?: number | null): string {
  return n && n > 0 ? String(n) : 'Unlimited';
}

function concatDuration(d?: Partial<DurationField> | null): string {
  if (!d?.value) return '';
  return (d as any).label || `${d.value} ${d.unit ?? 'minutes'}`;
}

function inc(i: number) {
  return i + 1;
}

export default Quiz;
