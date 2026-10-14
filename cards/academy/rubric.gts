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
import { FieldContainer, FittedCard } from '@cardstack/boxel-ui/components';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { Stat } from '@cardstack/pretui/components/stat';

import { SectionedEdit } from '@cardstack/catalog/components/sectioned-edit';

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
    <template>
      <article class='rubric'>
        <header class='hero'>
          <div>
            <span class='eyebrow'>Rubric ·
              {{@model.criterionCount}}
              {{if (eq1 @model.criterionCount) 'criterion' 'criteria'}}</span>
            <h1>{{@model.cardTitle}}</h1>
            {{#if @model.purpose}}<p
                class='purpose'
              >{{@model.purpose}}</p>{{/if}}
          </div>
          <Stat @label='Points' @value={{orZero @model.totalPoints}} />
        </header>
        {{#if @model.criteria.length}}
          <section class='grid'>
            {{#each @fields.criteria as |Criterion|}}
              <div class='crit-card'><Criterion /></div>
            {{/each}}
          </section>
        {{else}}
          <EmptyState
            @size='s'
            @title='No criteria yet'
            @message='A rubric with no rows cannot grade anything. Add the first criterion in edit mode.'
          />
        {{/if}}
      </article>
      <style scoped>
        .rubric {
          max-width: 60rem;
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
          align-items: flex-start;
          gap: var(--boxel-sp);
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
        .purpose {
          margin: var(--boxel-sp-xs) 0 0;
          color: var(--muted-foreground);
        }
        .grid {
          display: grid;
          gap: var(--boxel-sp-sm);
        }
        .crit-card {
          padding: var(--boxel-sp);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          background: var(--card);
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='row'>
        <span class='title'>{{@model.cardTitle}}</span>
        <span class='meta'>{{@model.criterionCount}} criteria</span>
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
      <span class='atom'>{{@model.cardTitle}}
        ·
        {{@model.totalPoints}}
        pts</span>
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
      { id: 'criteria', label: 'Criteria' },
    ];
    <template>
      <SectionedEdit
        @sections={{this.sections}}
        @ariaLabel='Rubric sections'
        as |e|
      >
        <e.Section @id='identity' @title='Identity' @cols={{2}}>
          <FieldContainer @label='Title' @vertical={{true}}><@fields.title
            /></FieldContainer>
          <FieldContainer @label='Purpose' @vertical={{true}}><@fields.purpose
            /></FieldContainer>
        </e.Section>
        <e.Section
          @id='criteria'
          @title='Criteria'
          @hint='levels sort by points; weight multiplies them'
          @cols={{1}}
        >
          <FieldContainer @label='Criteria' @vertical={{true}}><@fields.criteria
            /></FieldContainer>
        </e.Section>
      </SectionedEdit>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <FittedCard @titleTag='h3'>
        <:eyebrow>Rubric · {{@model.totalPoints}} pts</:eyebrow>
        <:title>{{@model.cardTitle}}</:title>
        <:subtitle>{{@model.criterionCount}} criteria</:subtitle>
        <:meta>
          <ul class='crit'>
            {{#each @model.criteria as |c|}}
              <li><span class='name'>{{c.name}}</span><span
                  class='n'
                >{{c.maxPoints}}</span></li>
            {{/each}}
          </ul>
        </:meta>
      </FittedCard>
      <style scoped>
        .crit {
          list-style: none;
          margin: 0;
          padding: 0;
          display: grid;
          gap: var(--boxel-sp-5xs);
          font-size: var(--boxel-font-size-xs);
        }
        .crit li {
          display: flex;
          justify-content: space-between;
          gap: var(--boxel-sp-xs);
          min-width: 0;
        }
        .name {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .n {
          font-variant-numeric: tabular-nums;
          color: var(--muted-foreground);
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
