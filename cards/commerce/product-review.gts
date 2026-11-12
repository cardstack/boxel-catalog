import {
  CardDef,
  Component,
  contains,
  field,
  linksTo,
  StringField,
  NumberField,
} from '@cardstack/base/card-api';
import StarIcon from '@cardstack/boxel-icons/star';
import { Plan } from './plan';
import { Service } from './service';
import { IsoFrame } from '../shared/compact-sheet';
import { RichFittedCard, Detail, Metric } from '../shared/rich-fitted-card';

// Product Review — customer feedback on a Plan or Service, not on a
// specific purchase. Deliberately NOT rendered inside RevenueOs (an internal
// sales-ops console, not a public review surface) — instead self-hosted by
// consuming `plan.gts`/`service.gts`'s own isolated views, which is a real
// consumer without forcing the wrong UI into the wrong app.

export class ProductReview extends CardDef {
  static displayName = 'Product Review';
  static icon = StarIcon;

  @field rating = contains(NumberField);
  @field body = contains(StringField);
  @field plan = linksTo(Plan);
  @field service = linksTo(Service);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: ProductReview) {
      let subject = this.plan?.cardTitle ?? this.service?.cardTitle;
      return subject
        ? `Review of ${subject}`
        : `Untitled ${this.constructor.displayName}`;
    },
  });

  static atom = class Atom extends Component<typeof ProductReview> {
    <template>
      <span class='review-atom'>
        <StarIcon class='ra-icon' />
        <span class='ra-rating'>{{if @model.rating @model.rating '—'}}/5</span>
      </span>
      <style scoped>
        .review-atom {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-2xs);
          font-size: var(--boxel-font-size-xs);
          font-weight: 600;
          color: var(--foreground);
        }
        .ra-icon {
          width: 14px;
          height: 14px;
          color: var(--warning-ink);
          flex-shrink: 0;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof ProductReview> {
    get stars() {
      let rating = this.args.model?.rating ?? 0;
      return [1, 2, 3, 4, 5].map((n) => ({ on: n <= rating }));
    }
    get ratingLabel() {
      return `Rated ${this.args.model?.rating ?? 0} out of 5`;
    }
    <template>
      <div class='review-row'>
        <div class='stars'>
          <span class='boxel-sr-only'>{{this.ratingLabel}}</span>
          {{#each this.stars as |star|}}
            <StarIcon
              class='star {{if star.on "star-on"}}'
              aria-hidden='true'
            />
          {{/each}}
        </div>
        {{#if @model.body}}
          <p class='body'>{{@model.body}}</p>
        {{/if}}
      </div>
      <style scoped>
        .review-row {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-2xs);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          font-size: var(--boxel-font-size-sm);
        }
        .stars {
          display: flex;
          gap: var(--boxel-sp-6xs);
        }
        .star {
          width: 14px;
          height: 14px;
          color: var(--border);
        }
        .star-on {
          color: var(--warning-ink);
          fill: currentColor;
        }
        .body {
          color: var(--foreground);
          line-height: 1.5;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof ProductReview> {
    get score() {
      let r = this.args.model?.rating;
      return `${r ? r : '—'}/5`;
    }
    <template>
      <RichFittedCard>
        <:avatar><StarIcon class='mark' aria-hidden='true' /></:avatar>
        <:title>{{@model.cardTitle}}</:title>
        <:subtitle>Rated {{this.score}}</:subtitle>
        <:fact>{{@model.body}}</:fact>
        <:metric><Metric @value={{this.score}} @label='Rating' /></:metric>
        <:details>
          {{#if @model.plan}}<Detail @label='Plan'><@fields.plan
                @format='atom'
                @displayContainer={{false}}
              /></Detail>{{/if}}
          {{#if @model.service}}<Detail @label='Service'><@fields.service
                @format='atom'
                @displayContainer={{false}}
              /></Detail>{{/if}}
        </:details>
      </RichFittedCard>
      <style scoped>
        .mark {
          inline-size: var(--pretui-avatar-size);
          block-size: var(--pretui-avatar-size);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static isolated = class Isolated extends Component<typeof ProductReview> {
    get stars() {
      let rating = this.args.model?.rating ?? 0;
      return [1, 2, 3, 4, 5].map((n) => ({ on: n <= rating }));
    }
    get ratingLabel() {
      return `Rated ${this.args.model?.rating ?? 0} out of 5`;
    }
    <template>
      <IsoFrame>
        <article class='review-page'>
          <div class='stars-lg'>
            <span class='boxel-sr-only'>{{this.ratingLabel}}</span>
            {{#each this.stars as |star|}}
              <StarIcon
                class='star {{if star.on "star-on"}}'
                aria-hidden='true'
              />
            {{/each}}
          </div>
          {{#if @model.body}}
            <p class='body'>{{@model.body}}</p>
          {{/if}}
        </article>
      </IsoFrame>
      <style scoped>
        .review-page {
          background: var(--card);
          color: var(--card-foreground);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          max-width: 32rem;
          margin: 0 auto;
          inline-size: 100%;
          padding: var(--boxel-sp-xl) var(--boxel-sp-lg);
        }
        .stars-lg {
          display: flex;
          gap: var(--boxel-sp-4xs);
          margin-bottom: var(--boxel-sp);
        }
        .star {
          width: 22px;
          height: 22px;
          color: var(--border);
        }
        .star-on {
          color: var(--warning-ink);
          fill: currentColor;
        }
        .body {
          font-size: var(--boxel-font-size);
          line-height: 1.6;
        }
      </style>
    </template>
  };
}
