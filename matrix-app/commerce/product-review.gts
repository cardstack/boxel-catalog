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
    <template>
      <div class='fitted'>
        <div class='fmt badge'>
          <StarIcon class='doc-icon' />
          <span class='figure'>{{if @model.rating @model.rating '—'}}/5</span>
        </div>
        <div class='fmt strip'>
          <StarIcon class='doc-icon' />
          <span class='figure'>{{if @model.rating @model.rating '—'}}/5</span>
          {{#if @model.body}}
            <span class='meta'>{{@model.body}}</span>
          {{/if}}
        </div>
      </div>
      <style scoped>
        .fitted {
          width: 100%;
          height: 100%;
          color: var(--foreground);
        }
        .fmt {
          display: none;
          width: 100%;
          height: 100%;
          box-sizing: border-box;
          overflow: hidden;
          align-items: center;
          gap: var(--boxel-sp-xs);
        }
        .doc-icon {
          width: 18px;
          height: 18px;
          color: var(--warning-ink);
          flex-shrink: 0;
        }
        .figure {
          font-weight: 700;
          font-size: var(--boxel-font-size-sm);
          white-space: nowrap;
        }
        .meta {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        @container fitted-card (max-width: 150px) and (max-height: 169px) {
          .badge {
            display: flex;
            flex-direction: column;
            justify-content: center;
            padding: var(--boxel-sp-xs);
            text-align: center;
          }
        }
        @container fitted-card (min-width: 151px) {
          .strip {
            display: flex;
            padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          }
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
      <style scoped>
        .review-page {
          max-width: 32rem;
          margin: 0 auto;
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
