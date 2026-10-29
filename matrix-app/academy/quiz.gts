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
import { StatePill } from '@cardstack/catalog/components/state-pill';
import { Avatar } from '../../ui-component/components/avatar';
import { FitTile } from '../../ui-component/components/fit-tile';
import type { KeyValueItem } from '../../ui-component/components/key-value';
import { FittedExtras } from '../procurement/vendor';
import {
  AcademyAtom,
  AcademyEmbedded,
  AcademyIsolated,
  AcademyPanel,
  type FormatFact,
} from './components/card-formats';
import { EmptyState } from '../../ui-component/components/empty-state';
import { KeyValue } from '../../ui-component/components/key-value';
import { Stat } from '../../ui-component/components/stat';
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
    get facts(): KeyValueItem[] {
      let m = this.args.model;
      return [
        { key: 'Pass mark', value: `${m?.passMarkPct ?? 0}%` },
        { key: 'Attempts', value: attemptsLabel(m?.attemptsAllowed) },
        {
          key: 'Time limit',
          value: m?.timeLimit?.value ? concatDuration(m.timeLimit) : 'None',
        },
        { key: 'Shuffle', value: m?.shuffleQuestions ? 'Yes' : 'No' },
      ];
    }
    <template>
      <AcademyIsolated
        @mark='Qz'
        @title={{@model.cardTitle}}
        @subtitle={{@model.instructions}}
      >
        <:chips>
          <StatePill @label='{{@model.questionCount}} questions' @hue='blue' />
        </:chips>
        <:stats>
          <Stat
            @label='Questions'
            @value={{if @model.questionCount @model.questionCount 0}}
            @hint='{{@model.totalPoints}} points in total'
            @roll={{false}}
          />
          <Stat
            @label='Pass mark'
            @value='{{@model.passMarkPct}}%'
            @hint='attempts: {{attemptsLabel @model.attemptsAllowed}}'
            @roll={{false}}
          />
          <Stat
            @label='Time limit'
            @value={{if
              @model.timeLimit.value
              (concatDuration @model.timeLimit)
              'None'
            }}
            @hint={{if @model.shuffleQuestions 'shuffled' 'fixed order'}}
            @roll={{false}}
          />
        </:stats>
        <:main>
          <AcademyPanel @title='Questions'>
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
          </AcademyPanel>
        </:main>
        <:side>
          <AcademyPanel @title='Details'>
            <KeyValue @items={{this.facts}} @rows='ruled' />
          </AcademyPanel>
        </:side>
      </AcademyIsolated>
      <style scoped>
        @layer PretComponent {
          .questions {
            list-style: none;
            margin: 0;
            padding: 0;
          }
          .q {
            display: grid;
            grid-template-columns: auto minmax(0, 1fr);
            gap: var(--boxel-sp-sm);
            padding: var(--boxel-sp-sm) 0;
          }
          .q + .q {
            border-top: 1px solid var(--border);
          }
          .q-n {
            width: 1.75rem;
            height: 1.75rem;
            display: grid;
            place-items: center;
            border-radius: 50%;
            background: color-mix(in oklab, var(--primary) 14%, var(--card));
            font-weight: 600;
            font-size: var(--boxel-font-size-sm);
          }
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    get facts(): FormatFact[] {
      let m = this.args.model;
      return [
        { key: 'Questions', value: String(m?.questionCount ?? 0) },
        { key: 'Points', value: String(m?.totalPoints ?? 0) },
        { key: 'Pass mark', value: `${m?.passMarkPct ?? 0}%` },
        { key: 'Attempts', value: attemptsLabel(m?.attemptsAllowed) },
        { key: 'Time limit', value: concatDuration(m?.timeLimit) || '—' },
      ];
    }
    <template>
      <AcademyEmbedded
        @mark='Qz'
        @title={{@model.cardTitle}}
        @subtitle={{@model.instructions}}
        @facts={{this.facts}}
      >
        <:chips><StatePill
            @label='{{@model.questionCount}} questions'
            @hue='blue'
          /></:chips>
        <:relations></:relations>
      </AcademyEmbedded>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <AcademyAtom @mark='Qz' @name={{@model.cardTitle}}>
        <StatePill @label='{{@model.questionCount}} q' @hue='blue' />
      </AcademyAtom>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get fact() {
      let m = this.args.model;
      return `Pass ${m?.passMarkPct ?? 0}% · ${attemptsLabel(m?.attemptsAllowed)} attempts`;
    }
    get facts(): KeyValueItem[] {
      let m = this.args.model;
      return [
        { key: 'Points', value: String(m?.totalPoints ?? 0) },
        { key: 'Time limit', value: concatDuration(m?.timeLimit) || '—' },
        { key: 'Shuffle', value: m?.shuffleQuestions ? 'Yes' : 'No' },
      ];
    }
    <template>
      <FittedExtras @facts={{this.facts}}>
        <:default>
          <FitTile>
            <:avatar>
              <Avatar
                @name='Qz'
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
            <:subtitle>{{@model.instructions}}</:subtitle>
            <:status><StatePill
                @label='{{@model.questionCount}} questions'
                @hue='blue'
              /></:status>
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
