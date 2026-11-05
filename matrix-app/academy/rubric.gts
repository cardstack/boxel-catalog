import {
  CardDef,
  Component,
  StringField,
  contains,
  containsMany,
  field,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import ListCheckIcon from '@cardstack/boxel-icons/list-check';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import { Avatar } from '../../ui-component/components/avatar';
import { FitTile } from '../../ui-component/components/fit-tile';
import {
  KeyValue,
  type KeyValueItem,
} from '../../ui-component/components/key-value';
import { FittedExtras } from '../procurement/vendor';
import {
  AcademyAtom,
  AcademyEmbedded,
  AcademyIsolated,
  AcademyPanel,
  type FormatFact,
} from './components/card-formats';
import { EmptyState } from '../../ui-component/components/empty-state';
import { Stat } from '../../ui-component/components/stat';
import {
  RubricCriterionField,
  criterionMaxPoints,
  round1,
} from './rubric-criterion-field';

/**
 * A reusable grading grid: named criteria, each with a ladder of levels. A
 * Rubric is its own card so one rubric grades many assignments across many
 * cohorts, and a change to a descriptor reaches every grader at once.
 * `totalPoints` is computed from the criteria — never typed in.
 */
export class Rubric extends CardDef {
  static displayName = 'Rubric';
  static icon = ListCheckIcon;

  @field title = contains(StringField);
  @field purpose = contains(StringField, {
    description: 'What kind of work this rubric judges.',
  });
  @field criteria = containsMany(RubricCriterionField);

  @field totalPoints = contains(NumberField, {
    computeVia: function (this: Rubric): number {
      return rubricTotalPoints(this);
    },
  });
  @field criterionCount = contains(NumberField, {
    computeVia: function (this: Rubric) {
      return (this.criteria ?? []).length;
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: Rubric) {
      return this.title?.trim() || 'Untitled rubric';
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    get details(): KeyValueItem[] {
      let m = this.args.model;
      return [
        { key: 'Criteria', value: String(m?.criterionCount ?? 0) },
        { key: 'Total points', value: String(m?.totalPoints ?? 0) },
        { key: 'Purpose', value: m?.purpose || '—' },
      ];
    }
    <template>
      <AcademyIsolated
        @mark='Ru'
        @title={{@model.cardTitle}}
        @subtitle={{@model.purpose}}
      >
        <:chips>
          <StatePill
            @label='{{@model.criterionCount}} {{if
              (eq1 @model.criterionCount)
              "criterion"
              "criteria"
            }}'
            @hue='blue'
          />
        </:chips>
        <:stats>
          <Stat
            @label='Points'
            @value={{orZero @model.totalPoints}}
            @hint='sum of the criteria'
            @roll={{false}}
          />
          <Stat
            @label='Criteria'
            @value={{if @model.criterionCount @model.criterionCount 0}}
            @hint='rows in the grid'
            @roll={{false}}
          />
        </:stats>
        <:main>
          <AcademyPanel @title='Criteria'>
            {{#if @model.criteria.length}}
              <div class='grid'>
                {{#each @fields.criteria as |Criterion|}}
                  <div class='crit'><Criterion /></div>
                {{/each}}
              </div>
            {{else}}
              <EmptyState
                @size='s'
                @title='No criteria yet'
                @message='A rubric with no rows cannot grade anything. Add the first criterion in edit mode.'
              />
            {{/if}}
          </AcademyPanel>
        </:main>
        <:side>
          <AcademyPanel @title='Details'>
            <KeyValue @items={{this.details}} @rows='ruled' />
          </AcademyPanel>
        </:side>
      </AcademyIsolated>
      <style scoped>
        @layer PretComponent {
          .grid {
            display: grid;
          }
          .crit {
            padding: var(--boxel-sp-sm) 0;
          }
          .crit + .crit {
            border-top: 1px solid var(--border);
          }
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    get facts(): FormatFact[] {
      let m = this.args.model;
      return [
        { key: 'Total', value: `${m?.totalPoints ?? 0} pts` },
        ...(m?.criteria ?? []).slice(0, 5).map((c: any) => ({
          key: c?.name || 'Criterion',
          value: `${c?.maxPoints ?? 0} pts`,
        })),
      ];
    }
    <template>
      <AcademyEmbedded
        @mark='Ru'
        @title={{@model.cardTitle}}
        @subtitle={{@model.purpose}}
        @facts={{this.facts}}
      >
        <:chips><StatePill
            @label='{{@model.criterionCount}} criteria'
            @hue='blue'
          /></:chips>
        <:relations></:relations>
      </AcademyEmbedded>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <AcademyAtom @mark='Ru' @name={{@model.cardTitle}}>
        <StatePill @label='{{@model.totalPoints}} pts' @hue='blue' />
      </AcademyAtom>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get fact() {
      let m = this.args.model;
      return `${m?.criterionCount ?? 0} criteria · ${m?.totalPoints ?? 0} pts`;
    }
    get facts(): KeyValueItem[] {
      return (this.args.model?.criteria ?? []).slice(0, 5).map((c: any) => ({
        key: c?.name || 'Criterion',
        value: `${c?.maxPoints ?? 0} pts`,
      }));
    }
    <template>
      <FittedExtras @facts={{this.facts}}>
        <:default>
          <FitTile>
            <:avatar>
              <Avatar
                @name='Ru'
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
            <:subtitle>{{@model.purpose}}</:subtitle>
            <:status><StatePill
                @label='{{@model.totalPoints}} pts'
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

export function rubricTotalPoints(
  r: Partial<Rubric> | null | undefined,
): number {
  return round1(
    (r?.criteria ?? []).reduce(
      (sum: number, c: any) => sum + criterionMaxPoints(c),
      0,
    ),
  );
}

function eq1(n?: number | null) {
  return n === 1;
}

function orZero(n?: number | null): number {
  return n ?? 0;
}

export default Rubric;
