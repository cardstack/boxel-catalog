import {
  FieldDef,
  Component,
  field,
  contains,
  containsMany,
  StringField,
} from 'https://cardstack.com/base/card-api';
import NumberField from 'https://cardstack.com/base/number';
import TextAreaField from 'https://cardstack.com/base/text-area';
import enumField from 'https://cardstack.com/base/enum';

import { EmptyState } from '@cardstack/pretui/components/empty-state';

import ScoreField from '@cardstack/catalog/fields/rating/rating';
import {
  StatePill,
  stateColor,
  type Hue,
  type StateColor,
} from '@cardstack/catalog/components/state-pill';
import { hueOf } from './hr-ui';

export const RECOMMENDATIONS = [
  'strong-hire',
  'hire',
  'no-hire',
  'strong-no-hire',
];

export const RECOMMENDATION_LABELS: Record<string, string> = {
  'strong-hire': 'Strong hire',
  hire: 'Hire',
  'no-hire': 'No hire',
  'strong-no-hire': 'Strong no hire',
};

// Colocated with ScorecardField — the same map colors the recommendation pill
// wherever a scorecard renders (Meeting's isolated view, this field's own
// embedded format). A recommendation is a verdict, so it reads the status
// hues: green for both votes to hire, amber and red against, mirroring the
// CANDIDATE_STAGE_HUES convention of hired=green/rejected=red. The label
// tells the two forward votes apart.
export const RECOMMENDATION_HUES: Record<string, Hue> = {
  'strong-hire': 'green',
  hire: 'green',
  'no-hire': 'amber',
  'strong-no-hire': 'red',
};

export const RECOMMENDATION_COLORS: Record<string, StateColor> =
  Object.fromEntries(
    Object.entries(RECOMMENDATION_HUES).map(([k, hue]) => [k, stateColor(hue)]),
  );

export const RECOMMENDATION_OPTIONS = RECOMMENDATIONS.map((value) => ({
  value,
  label: RECOMMENDATION_LABELS[value],
}));

export const RecommendationField = enumField(StringField, {
  options: RECOMMENDATION_OPTIONS,
  displayName: 'Recommendation',
});

export class ScorecardCriterionField extends FieldDef {
  static displayName = 'Scorecard Criterion';

  @field name = contains(StringField);
  @field score = contains(ScoreField);
  @field notes = contains(TextAreaField);

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <li class='criterion-row'>
        <div class='criterion-head'>
          <span class='criterion-name'>{{if
              @model.name
              @model.name
              'Untitled criterion'
            }}</span>
          <@fields.score @format='atom' @displayContainer={{false}} />
        </div>
        {{#if @model.notes}}
          <p class='criterion-notes'>{{@model.notes}}</p>
        {{/if}}
      </li>
      <style scoped>
        .criterion-row {
          padding: var(--boxel-sp-xs) 0;
          border-bottom: 1px solid var(--border);
        }
        .criterion-row:last-child {
          border-bottom: 0;
        }
        .criterion-head {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: var(--boxel-sp-xs);
        }
        .criterion-name {
          font-size: var(--boxel-font-size-sm);
          font-weight: 600;
        }
        .criterion-notes {
          margin: var(--boxel-sp-4xs) 0 0;
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
          line-height: 1.5;
          overflow: hidden;
          text-overflow: ellipsis;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
        }
      </style>
    </template>
  };
}

function averageOf(criteria: ScorecardCriterionField[] | undefined) {
  let scores = (criteria ?? [])
    .map((c) => c?.score)
    .filter((v): v is number => typeof v === 'number' && Number.isFinite(v));
  if (!scores.length) {
    return undefined;
  }
  let avg = scores.reduce((a, b) => a + b, 0) / scores.length;
  return Math.round(avg * 10) / 10;
}

// Reusable interview-scorecard block: a set of scored criteria plus a
// recommendation, embedded on a Meeting to structure interview feedback
// beyond a single 1-5 number. See the catalog Rating field for the star widget this
// composes rather than duplicates.
export class ScorecardField extends FieldDef {
  static displayName = 'Scorecard';

  @field criteria = containsMany(ScorecardCriterionField);
  @field recommendation = contains(RecommendationField);
  @field overallNotes = contains(TextAreaField);

  @field averageScore = contains(NumberField, {
    computeVia: function (this: ScorecardField) {
      return averageOf(this.criteria);
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    get recommendationHue() {
      return hueOf(RECOMMENDATION_HUES, this.args.model?.recommendation);
    }

    get recommendationLabel() {
      let value = this.args.model?.recommendation;
      return value ? (RECOMMENDATION_LABELS[value] ?? value) : undefined;
    }

    get averageLabel(): string {
      let v = this.args.model?.averageScore;
      return typeof v === 'number' ? `${v} / 5 avg` : 'Not yet scored';
    }

    <template>
      <div class='scorecard'>
        <div class='scorecard-head'>
          <span class='scorecard-avg'>{{this.averageLabel}}</span>
          <StatePill
            @label={{this.recommendationLabel}}
            @hue={{this.recommendationHue}}
            @dot={{true}}
          />
        </div>

        {{#if @model.criteria.length}}
          <h4 class='sr-only-heading'>Criteria</h4>
          <ul class='criteria-list'>
            <@fields.criteria />
          </ul>
        {{else}}
          <EmptyState
            class='empty'
            @texture={{false}}
            @title='No criteria scored yet'
          />
        {{/if}}

        {{#if @model.overallNotes}}
          <p class='overall-notes'>{{@model.overallNotes}}</p>
        {{/if}}
      </div>
      <style scoped>
        .scorecard {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-xs);
        }
        .scorecard-head {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: var(--boxel-sp-xs);
        }
        .scorecard-avg {
          font-size: var(--boxel-font-size-sm);
          font-weight: 700;
        }
        .sr-only-heading {
          margin: 0;
          position: absolute;
          width: 1px;
          height: 1px;
          overflow: hidden;
          clip: rect(0 0 0 0);
        }
        .criteria-list {
          list-style: none;
          margin: 0;
          padding: 0;
        }
        .empty {
          --space-9: var(--boxel-sp);
          --space-6: var(--boxel-sp);
          --text-heading: var(--boxel-font-size);
        }
        .overall-notes {
          margin: 0;
          font-size: var(--boxel-font-size-sm);
          line-height: 1.6;
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };
}
