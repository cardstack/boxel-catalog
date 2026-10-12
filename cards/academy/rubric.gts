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
import { FieldContainer } from '@cardstack/boxel-ui/components';

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
          <div class='total'>
            <span class='total-n'>{{@model.totalPoints}}</span>
            <span class='total-l'>points</span>
          </div>
        </header>
        <section class='grid'>
          {{#each @fields.criteria as |Criterion|}}
            <div class='crit-card'><Criterion /></div>
          {{else}}
            <p class='empty'>No criteria yet. A rubric with no rows cannot grade
              anything — add the first criterion in edit.</p>
          {{/each}}
        </section>
      </article>
      <style scoped>
        .rubric {
          max-width: 60rem;
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
          align-items: flex-start;
          gap: var(--boxel-sp);
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
        .purpose {
          margin: var(--boxel-sp-xs) 0 0;
          color: var(--muted-foreground, var(--boxel-450));
        }
        .total {
          flex: none;
          display: grid;
          justify-items: center;
          padding: var(--boxel-sp-sm) var(--boxel-sp);
          border-radius: var(--radius, var(--boxel-border-radius));
          background: color-mix(
            in oklab,
            var(--primary, var(--boxel-highlight)) 14%,
            var(--card, var(--boxel-light))
          );
        }
        .total-n {
          font-size: var(--boxel-font-size-xl);
          font-weight: 700;
          font-variant-numeric: tabular-nums;
          line-height: 1;
        }
        .total-l {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
        }
        .grid {
          display: grid;
          gap: var(--boxel-sp-sm);
        }
        .crit-card {
          padding: var(--boxel-sp);
          border: 1px solid var(--border, var(--boxel-200));
          border-radius: var(--radius, var(--boxel-border-radius));
          background: var(--card, var(--boxel-light));
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
        <span class='title'>{{@model.cardTitle}}</span>
        <span class='meta'>{{@model.criterionCount}} criteria</span>
        <span class='pts'>{{@model.totalPoints}} pts</span>
      </div>
      <style scoped>
        .row {
          display: grid;
          grid-template-columns: 1fr auto 5rem;
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
          color: var(--muted-foreground, var(--boxel-450));
        }
        .pts {
          text-align: end;
          font-variant-numeric: tabular-nums;
          font-weight: 600;
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
      <article class='fit'>
        <div class='fit-top'>
          <span class='badge'>{{@model.totalPoints}}</span>
          <div class='fit-head'>
            <h3 class='fit-name'>{{@model.cardTitle}}</h3>
            <span class='fit-eb'>{{@model.criterionCount}} criteria</span>
          </div>
        </div>
        <ul class='fit-list'>
          {{#each @model.criteria as |c|}}
            <li><span>{{c.name}}</span><span
                class='n'
              >{{c.maxPoints}}</span></li>
          {{/each}}
        </ul>
      </article>
      <style scoped>
        .fit {
          height: 100%;
          padding: var(--boxel-sp-xs);
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-xs);
          overflow: hidden;
        }
        .fit-top {
          display: flex;
          gap: var(--boxel-sp-xs);
          align-items: flex-start;
          min-width: 0;
        }
        .badge {
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
          font-weight: 700;
          font-variant-numeric: tabular-nums;
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
        .fit-list {
          display: none;
          list-style: none;
          margin: 0;
          padding: 0;
          font-size: var(--boxel-font-size-xs);
        }
        .fit-list li {
          display: flex;
          justify-content: space-between;
          gap: var(--boxel-sp-xs);
          padding: 2px 0;
          border-top: 1px solid var(--border, var(--boxel-200));
        }
        .n {
          font-variant-numeric: tabular-nums;
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
          .fit-list {
            display: block;
            overflow: hidden;
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

export default Rubric;
