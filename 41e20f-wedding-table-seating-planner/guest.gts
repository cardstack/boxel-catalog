import {
  Component,
  field,
  contains,
  containsMany,
  linksTo,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import BooleanField from '@cardstack/base/boolean';
import enumField from '@cardstack/base/enum';
import { htmlSafe } from '@ember/template';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { BoxelInput, Button } from '@cardstack/boxel-ui/components';
import { eq } from '@cardstack/boxel-ui/helpers';
import UserIcon from '@cardstack/boxel-icons/user';
import ImageSourceField from '@cardstack/catalog/fields/image-source/image-source';

import { Person } from './person';
import {
  initialsOf,
  GUEST_CATEGORIES,
  categoryLabel,
  categoryColor,
  DIETARY_OPTIONS,
  dietaryLabel,
} from './utils/index';

export const CategoryField = enumField(StringField, {
  options: GUEST_CATEGORIES.map(({ value, label }) => ({ value, label })),
});

export const DietaryField = enumField(StringField, {
  options: DIETARY_OPTIONS.map(({ value, label }) => ({ value, label })),
});

function swatch(color: string | null | undefined) {
  return htmlSafe(`background-color:${color || 'var(--accent)'}`);
}

export class Guest extends Person {
  static displayName = 'Guest';
  static icon = UserIcon;

  // Fields follow the order a planner fills them in. The edit form renders
  // subclass fields before inherited ones, so fullName/photo are re-declared
  // here to hoist identity to the top; computed title stays last.

  @field fullName = contains(StringField);

  @field photo = contains(ImageSourceField);

  @field category = contains(CategoryField);

  @field vip = contains(BooleanField);

  // dietary restrictions / meal needs the caterer must know about;
  // containsMany because one guest can carry several (e.g. vegan + nut allergy)
  @field dietary = containsMany(DietaryField);

  @field parentGuest = linksTo(() => Guest); // set on a +1 → the inviting guest

  @field title = contains(StringField, {
    computeVia: function (this: Guest) {
      return this.fullName?.trim() || 'Unnamed Guest';
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    get initials() {
      return initialsOf(this.args.model?.fullName);
    }

    <template>
      <div class='g-row'>
        {{#if @model.photoURL}}
          <img class='g-avatar' src={{@model.photoURL}} alt='' />
        {{else}}
          <span class='g-avatar g-initials'>{{this.initials}}</span>
        {{/if}}
        <span class='g-main'>
          <span class='g-name-line'>
            <span class='g-name'>{{if
                @model.fullName
                @model.fullName
                'Unnamed Guest'
              }}</span>
            {{#if @model.vip}}<span class='g-vip'>VIP</span>{{/if}}
          </span>
          {{#if @model.category}}
            <span class='g-cat'>
              <span
                class='g-dot'
                style={{swatch (categoryColor @model.category)}}
              ></span>
              {{categoryLabel @model.category}}
            </span>
          {{/if}}
          {{#if @model.dietary.length}}
            <span class='g-diet'>
              {{#each @model.dietary as |d index|}}{{if
                  index
                  ' · '
                }}{{dietaryLabel d}}{{/each}}
            </span>
          {{/if}}
        </span>
        {{#if @model.parentGuest}}
          <span class='g-party'>+1 of {{@model.parentGuest.fullName}}</span>
        {{/if}}
      </div>
      <style scoped>
        .g-row {
          display: flex;
          align-items: center;
          gap: 0.75rem;
          padding: 0.5625rem 0.75rem;
          border: 1px solid var(--border);
          border-radius: 0.6875rem;
        }
        .g-avatar {
          width: 2.375rem;
          height: 2.375rem;
          border-radius: 50%;
          flex: none;
          object-fit: cover;
        }
        .g-initials {
          display: flex;
          align-items: center;
          justify-content: center;
          font: 600 0.8125rem var(--font-serif);
          color: var(--accent-foreground);
          background: linear-gradient(135deg, var(--accent), var(--accent));
        }
        .g-main {
          flex: 1;
          min-width: 0;
          display: flex;
          flex-direction: column;
          gap: 0.1875rem;
        }
        .g-name-line {
          display: flex;
          align-items: center;
          gap: 0.4375rem;
        }
        .g-name {
          font-size: 0.875rem;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .g-vip {
          flex: none;
          font: 600 0.6875rem var(--font-sans);
          letter-spacing: 0.12em;
          color: var(--accent-foreground);
          background-color: var(--accent);
          border-radius: 0.25rem;
          padding: 2px 0.3125rem;
        }
        .g-cat {
          display: flex;
          align-items: center;
          gap: 0.375rem;
          font-size: 0.6875rem;
          color: var(--muted-foreground);
        }
        .g-dot {
          width: 0.625rem;
          height: 0.625rem;
          border-radius: 50%;
          flex: none;
        }
        .g-diet {
          font-size: 0.6875rem;
          color: var(--accent-ink);
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .g-party {
          flex: none;
          font: 0.6875rem var(--font-sans);
          color: var(--accent-ink);
          border: 1px solid color-mix(in oklch, var(--accent) 35%, transparent);
          border-radius: 62.4375rem;
          padding: 2px 0.5rem;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof Guest> {
    get hasLinkedTheme(): boolean {
      return Boolean((this.args.model as any)?.cardInfo?.theme);
    }

    get initials() {
      return initialsOf(this.args.model?.fullName);
    }

    get name() {
      return this.args.model?.fullName || 'Unnamed Guest';
    }

    <template>
      <div class='fitted {{unless this.hasLinkedTheme "tsp-default-theme"}}'>

        {{! BADGE (≤150w × ≤169h) — category dot + name + VIP }}
        <div class='fmt badge'>
          <span
            class='b-dot'
            style={{swatch (categoryColor @model.category)}}
          ></span>
          <div class='b-info'>
            <div class='b-name'>{{this.name}}</div>
            {{#if @model.category}}
              <div class='b-cat'>{{categoryLabel @model.category}}</div>
            {{/if}}
          </div>
          {{#if @model.vip}}<span class='b-star' title='VIP'>★</span>{{/if}}
        </div>

        {{! STRIP (≥151w × ≤169h) — avatar · name · category · VIP }}
        <div class='fmt strip'>
          <span class='s-ring'>
            {{#if @model.photoURL}}
              <img class='s-av' src={{@model.photoURL}} alt='' />
            {{else}}
              <span class='s-av s-initials'>{{this.initials}}</span>
            {{/if}}
          </span>
          <div class='s-info'>
            <div class='s-name'>{{this.name}}</div>
            <div class='s-meta'>
              {{#if @model.category}}
                <span
                  class='s-dot'
                  style={{swatch (categoryColor @model.category)}}
                ></span>
                <span class='s-cat'>{{categoryLabel @model.category}}</span>
              {{/if}}
            </div>
          </div>
          {{#if @model.vip}}
            <span class='s-tag'>★ VIP</span>
          {{else}}
            <span class='s-orn' aria-hidden='true'>&#10087;</span>
          {{/if}}
        </div>

        {{! TILE (≤399w × ≥170h) — cream invitation frame }}
        <div class='fmt tile'>
          <div class='t-frame'>
            <span class='t-orn t-orn-top'>❧</span>
            <span class='t-ring'>
              {{#if @model.photoURL}}
                <img class='t-av' src={{@model.photoURL}} alt='' />
              {{else}}
                <span class='t-av t-initials'>{{this.initials}}</span>
              {{/if}}
              {{#if @model.vip}}<span class='t-star' title='VIP'>★</span>{{/if}}
            </span>
            <div class='t-kicker'>Invited guest</div>
            <div class='t-name'>{{this.name}}</div>
            {{#if @model.category}}
              <div class='t-cat'>
                <span
                  class='t-dot'
                  style={{swatch (categoryColor @model.category)}}
                ></span>
                {{categoryLabel @model.category}}
              </div>
            {{/if}}
            <span class='t-rule'></span>
            <span class='t-orn t-orn-bottom'>✦</span>
          </div>
        </div>

        {{! CARD (≥400w × ≥170h) — cream invitation with portrait panel }}
        <div class='fmt cardf'>
          <div class='c-body'>
            <div class='c-kicker'>Invited guest</div>
            <div class='c-name'>{{this.name}}</div>
            {{#if @model.category}}
              <div class='c-cat'>
                <span
                  class='c-dot'
                  style={{swatch (categoryColor @model.category)}}
                ></span>
                {{categoryLabel @model.category}}
              </div>
            {{/if}}
            <div class='c-foot'>
              {{#if @model.vip}}<span class='c-pill'>★ VIP</span>{{/if}}
              {{#if @model.parentGuest}}
                <span class='c-pill c-pill-ghost'>+1 of
                  {{@model.parentGuest.fullName}}</span>
              {{/if}}
            </div>
          </div>
          <div class='c-panel'>
            <span class='c-orn'>❧</span>
            <span class='c-ring'>
              {{#if @model.photoURL}}
                <img class='c-av' src={{@model.photoURL}} alt='' />
              {{else}}
                <span class='c-av c-initials'>{{this.initials}}</span>
              {{/if}}
            </span>
            <span class='c-panel-rule'></span>
          </div>
        </div>

      </div>
      <style scoped>
        /* Default palette when NO theme is linked — pins the semantic
           tokens to the Parisian look so app-level defaults can't restyle
           the card arbitrarily. A linked theme omits this class. */
        .tsp-default-theme {
          color: var(--card-foreground);
        }
        .fitted {
          width: 100%;
          height: 100%;
          font-family: var(--font-sans);
        }
        .fmt {
          display: none;
          width: 100%;
          height: 100%;
          box-sizing: border-box;
          overflow: hidden;
        }

        /* ── BADGE ── */
        @container fitted-card (max-width: 150px) and (max-height: 169px) {
          .badge {
            display: flex;
            align-items: center;
            gap: 0.5rem;
            padding: 0.375rem 0.625rem;
            background-color: var(--card);
            color: var(--card-foreground);
            border-left: 3px solid var(--accent);
          }
        }
        .b-dot {
          flex: none;
          width: 0.5rem;
          height: 0.5rem;
          border-radius: 50%;
        }
        .b-info {
          flex: 1;
          min-width: 0;
        }
        .b-name {
          font-family: var(--font-serif);
          font-size: clamp(0.7rem, 22cqmin, 0.95rem);
          line-height: 1.15;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .b-cat {
          font-size: 0.5rem;
          letter-spacing: 0.16em;
          text-transform: uppercase;
          color: var(--muted-foreground);
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .b-star {
          flex: none;
          font-size: 0.6875rem;
          color: var(--accent-ink);
        }

        /* ── STRIP ── */
        @container fitted-card (min-width: 151px) and (max-height: 169px) {
          .strip {
            display: flex;
            align-items: center;
            gap: 0.75rem;
            padding: 0.5rem 0.875rem 0.5rem 0.75rem;
            background: linear-gradient(
              120deg,
              var(--card) 55%,
              var(--muted) 140%
            );
            color: var(--card-foreground);
            border-left: 3px solid var(--accent);
            box-shadow: inset 0 0 0 1px var(--border);
          }
        }
        .s-ring {
          flex: none;
          display: block;
          width: clamp(1.75rem, 70cqmin, 2.75rem);
          height: clamp(1.75rem, 70cqmin, 2.75rem);
          border-radius: 50%;
          padding: 2px;
          background: conic-gradient(
            from 140deg,
            color-mix(in oklch, var(--accent) 60%, var(--card)),
            var(--accent),
            color-mix(in oklch, var(--accent) 60%, var(--card))
          );
        }
        .s-av {
          width: 100%;
          height: 100%;
          border-radius: 50%;
          object-fit: cover;
          display: block;
        }
        .s-initials {
          display: flex;
          align-items: center;
          justify-content: center;
          font: 600 0.8em var(--font-serif);
          color: var(--accent-foreground);
          background-color: var(--accent);
        }
        .s-info {
          flex: 1;
          min-width: 0;
        }
        .s-name {
          font-family: var(--font-serif);
          font-size: clamp(0.85rem, 26cqmin, 1.1rem);
          line-height: 1.15;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .s-meta {
          display: flex;
          align-items: center;
          gap: 0.3125rem;
          min-width: 0;
        }
        .s-dot {
          flex: none;
          width: 0.4375rem;
          height: 0.4375rem;
          border-radius: 50%;
        }
        .s-cat {
          font-size: 0.55rem;
          letter-spacing: 0.18em;
          text-transform: uppercase;
          color: var(--muted-foreground);
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .s-tag {
          flex: none;
          font-size: 0.5rem;
          font-weight: 600;
          letter-spacing: 0.14em;
          text-transform: uppercase;
          color: var(--accent-foreground);
          background-color: var(--accent);
          border-radius: 62.4375rem;
          padding: 0.1875rem 0.5rem;
          white-space: nowrap;
        }
        .s-orn {
          flex: none;
          font-family: var(--font-serif);
          font-size: clamp(0.875rem, 34cqmin, 1.375rem);
          line-height: 1;
          color: color-mix(in oklch, var(--accent-ink) 45%, transparent);
        }
        @container fitted-card (max-height: 64px) {
          .s-tag,
          .s-orn {
            display: none;
          }
        }

        /* ── TILE — cream invitation ── */
        @container fitted-card (max-width: 399px) and (min-height: 170px) {
          .tile {
            display: block;
            padding: clamp(0.375rem, 4cqmin, 0.75rem);
            background: radial-gradient(
              130% 90% at 50% -12%,
              var(--card),
              var(--muted) 78%
            );
            color: var(--card-foreground);
          }
        }
        .t-frame {
          width: 100%;
          height: 100%;
          box-sizing: border-box;
          border: 1px solid var(--border);
          border-radius: calc(var(--radius) / 1.5);
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          gap: clamp(0.1875rem, 2.4cqmin, 0.5rem);
          padding: clamp(0.375rem, 5cqmin, 1rem);
          text-align: center;
          overflow: hidden;
        }
        .t-orn {
          flex: none;
          font-size: clamp(0.5625rem, 6cqmin, 0.8125rem);
          color: var(--accent-ink);
        }
        .t-ring {
          position: relative;
          flex: none;
          display: block;
          width: clamp(2.5rem, 34cqmin, 5.25rem);
          height: clamp(2.5rem, 34cqmin, 5.25rem);
          border-radius: 50%;
          padding: 2px;
          background: conic-gradient(
            from 140deg,
            color-mix(in oklch, var(--accent) 60%, var(--card)),
            var(--accent),
            color-mix(in oklch, var(--accent) 60%, var(--card))
          );
        }
        .t-av {
          width: 100%;
          height: 100%;
          border-radius: 50%;
          object-fit: cover;
          display: block;
        }
        .t-initials {
          display: flex;
          align-items: center;
          justify-content: center;
          font: 600 clamp(0.875rem, 13cqmin, 1.875rem) var(--font-serif);
          color: var(--accent-foreground);
          background-color: var(--accent);
        }
        .t-star {
          position: absolute;
          right: -2px;
          bottom: -2px;
          width: clamp(0.875rem, 10cqmin, 1.25rem);
          height: clamp(0.875rem, 10cqmin, 1.25rem);
          border-radius: 50%;
          background-color: var(--accent);
          color: var(--accent-foreground);
          font-size: clamp(0.5rem, 6cqmin, 0.6875rem);
          display: flex;
          align-items: center;
          justify-content: center;
          border: 2px solid var(--card);
        }
        .t-kicker {
          font-size: clamp(0.42rem, 4cqmin, 0.55rem);
          letter-spacing: 0.26em;
          text-transform: uppercase;
          color: var(--accent-ink);
          white-space: nowrap;
          overflow: hidden;
          max-width: 100%;
          text-overflow: ellipsis;
        }
        .t-name {
          color: var(--primary-ink);
          font-family: var(--font-serif);
          font-size: clamp(0.95rem, 11cqmin, 1.7rem);
          line-height: 1.12;
          max-width: 100%;
          overflow: hidden;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
        }
        .t-cat {
          display: inline-flex;
          align-items: center;
          gap: 0.3125rem;
          max-width: 100%;
          font-size: clamp(0.5rem, 4.5cqmin, 0.62rem);
          letter-spacing: 0.2em;
          text-transform: uppercase;
          color: var(--muted-foreground);
          white-space: nowrap;
          overflow: hidden;
        }
        .t-dot {
          flex: none;
          width: 0.4375rem;
          height: 0.4375rem;
          border-radius: 50%;
        }
        .t-rule {
          flex: none;
          width: 34%;
          height: 1px;
          background: linear-gradient(
            90deg,
            transparent,
            var(--accent),
            transparent
          );
        }
        @container fitted-card (max-height: 220px) {
          .t-orn-top,
          .t-rule {
            display: none;
          }
        }

        /* ── CARD — invitation with portrait panel ── */
        @container fitted-card (min-width: 400px) and (min-height: 170px) {
          .cardf {
            display: flex;
            background-color: var(--card);
            color: var(--card-foreground);
            border: 1px solid var(--border);
            border-radius: var(--radius);
          }
        }
        .c-body {
          flex: 1;
          min-width: 0;
          display: flex;
          flex-direction: column;
          justify-content: center;
          gap: clamp(0.1875rem, 2.4cqmin, 0.5rem);
          padding: clamp(0.625rem, 6cqmin, 1.375rem);
          color: var(--card-foreground);
        }
        .c-kicker {
          font-size: clamp(0.45rem, 4cqmin, 0.58rem);
          letter-spacing: 0.28em;
          text-transform: uppercase;
          color: var(--accent-ink);
        }
        .c-name {
          color: var(--primary-ink);
          font-family: var(--font-serif);
          font-size: clamp(1.2rem, 13cqmin, 2.2rem);
          line-height: 1.1;
          overflow: hidden;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
        }
        .c-cat {
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
          font-size: clamp(0.55rem, 4.5cqmin, 0.7rem);
          letter-spacing: 0.2em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .c-dot {
          flex: none;
          width: 0.5rem;
          height: 0.5rem;
          border-radius: 50%;
        }
        .c-foot {
          display: flex;
          align-items: center;
          flex-wrap: wrap;
          gap: 0.375rem;
          margin-top: clamp(2px, 2cqmin, 0.5rem);
        }
        .c-pill {
          font-size: 0.52rem;
          font-weight: 600;
          letter-spacing: 0.14em;
          text-transform: uppercase;
          color: var(--accent-foreground);
          background-color: var(--accent);
          border: 1px solid var(--accent);
          border-radius: 62.4375rem;
          padding: 0.1875rem 0.625rem;
          white-space: nowrap;
        }
        .c-pill-ghost {
          color: var(--accent-ink);
          background-color: transparent;
          border-color: var(--border);
          overflow: hidden;
          text-overflow: ellipsis;
          max-width: 100%;
        }
        .c-panel {
          flex: none;
          width: 34%;
          max-width: 11rem;
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          gap: clamp(0.25rem, 3cqmin, 0.625rem);
          padding: clamp(0.5rem, 5cqmin, 1.125rem);
          background:
            radial-gradient(
              130% 90% at 50% -12%,
              color-mix(in oklch, var(--inset) 18%, transparent),
              transparent 60%
            ),
            var(--muted);
          border-left: 1px solid var(--border);
        }
        .c-orn {
          font-size: clamp(0.625rem, 6cqmin, 0.875rem);
          color: var(--accent-ink);
        }
        .c-ring {
          display: block;
          width: clamp(3rem, 38cqmin, 6rem);
          height: clamp(3rem, 38cqmin, 6rem);
          border-radius: 50%;
          padding: 0.1562rem;
          background: conic-gradient(
            from 140deg,
            color-mix(in oklch, var(--accent) 60%, var(--card)),
            var(--accent),
            color-mix(in oklch, var(--accent) 60%, var(--card))
          );
        }
        .c-av {
          width: 100%;
          height: 100%;
          border-radius: 50%;
          object-fit: cover;
          display: block;
        }
        .c-initials {
          display: flex;
          align-items: center;
          justify-content: center;
          font: 600 clamp(1rem, 14cqmin, 2.125rem) var(--font-serif);
          color: var(--accent-foreground);
          background-color: var(--accent);
        }
        .c-panel-rule {
          width: 40%;
          height: 1px;
          background: linear-gradient(
            90deg,
            transparent,
            var(--accent),
            transparent
          );
        }
      </style>
    </template>
  };

  static isolated = class Isolated extends Component<typeof Guest> {
    get hasLinkedTheme(): boolean {
      return Boolean((this.args.model as any)?.cardInfo?.theme);
    }

    categoryOptions = GUEST_CATEGORIES;

    get initials() {
      return initialsOf(this.args.model?.fullName);
    }

    setName = (e: Event) => {
      this.args.model.fullName = (e.target as HTMLInputElement).value;
    };

    setCategory = (value: string) => {
      this.args.model.category =
        this.args.model.category === value ? undefined : value;
    };

    toggleVip = () => {
      this.args.model.vip = !this.args.model.vip;
    };

    dietaryOptions = DIETARY_OPTIONS;

    isDietary = (value: string) =>
      (this.args.model.dietary ?? []).includes(value);

    toggleDietary = (value: string) => {
      let current = this.args.model.dietary ?? [];
      this.args.model.dietary = current.includes(value)
        ? current.filter((v: string) => v !== value)
        : [...current, value];
    };

    <template>
      <article class='iso {{unless this.hasLinkedTheme "tsp-default-theme"}}'>

        <header class='iso-mast' aria-label='Masthead'>
          <span class='iso-rule'></span>
          <span class='iso-mast-title'>The Guest List</span>
          <span class='iso-rule'></span>
        </header>

        <div class='iso-hero'>
          <div class='iso-portrait'>
            <span class='iso-ring'>
              {{#if @model.photoURL}}
                <img class='iso-photo' src={{@model.photoURL}} alt='' />
              {{else}}
                <span class='iso-photo iso-initials'>{{this.initials}}</span>
              {{/if}}
            </span>
            {{#if @model.vip}}
              <span class='iso-star' title='VIP'>&#9733;</span>
            {{/if}}
          </div>
          <div class='iso-ident'>
            <span class='iso-kicker'>Guest Profile</span>
            <BoxelInput
              class='iso-name-input'
              @value={{@model.fullName}}
              placeholder='Unnamed Guest'
              aria-label='Guest name'
              {{on 'input' this.setName}}
            />
            <div class='iso-cats' aria-label='Category'>
              {{#each this.categoryOptions as |cat|}}
                <Button
                  @size='auto'
                  @kind='text-only'
                  aria-pressed={{if
                    (eq @model.category cat.value)
                    'true'
                    'false'
                  }}
                  class='iso-catchip
                    {{if (eq @model.category cat.value) "is-on"}}'
                  {{on 'click' (fn this.setCategory cat.value)}}
                >
                  <span class='iso-dot' style={{swatch cat.color}}></span>
                  {{cat.label}}
                </Button>
              {{/each}}
            </div>
            <div class='iso-tags'>
              <Button
                @size='auto'
                @kind='text-only'
                aria-pressed={{if @model.vip 'true' 'false'}}
                class='iso-vip-toggle {{if @model.vip "is-on"}}'
                title='Mark as a VIP guest'
                {{on 'click' this.toggleVip}}
              >&#10022; VIP</Button>
              {{#if @model.parentGuest}}
                <span class='iso-pill'>+1 of
                  {{@model.parentGuest.fullName}}</span>
              {{/if}}
            </div>
          </div>
        </div>

        <header class='iso-sect' aria-label='Party'>
          <span class='iso-sect-no'>01</span>
          <span class='iso-sect-title'>Party</span>
          <span class='iso-rule'></span>
        </header>
        {{#if @model.parentGuest}}
          <section class='iso-party'>
            <span class='iso-lbl'>Guest of</span>
            <div class='iso-party-card'>
              <@fields.parentGuest @format='embedded' />
            </div>
          </section>
        {{else}}
          <p class='iso-empty-line'>Attending on their own invitation.</p>
        {{/if}}

        <header class='iso-sect' aria-label='Dietary'>
          <span class='iso-sect-no'>02</span>
          <span class='iso-sect-title'>Dietary Needs</span>
          <span class='iso-rule'></span>
        </header>
        <div class='iso-cats' aria-label='Dietary restrictions'>
          {{#each this.dietaryOptions as |opt|}}
            <Button
              @size='auto'
              @kind='text-only'
              aria-pressed={{if (this.isDietary opt.value) 'true' 'false'}}
              class='iso-catchip {{if (this.isDietary opt.value) "is-on"}}'
              {{on 'click' (fn this.toggleDietary opt.value)}}
            >
              {{opt.label}}
            </Button>
          {{/each}}
        </div>

        <footer class='iso-colophon'>
          <span class='iso-rule'></span>
          <span class='iso-colophon-mark'>&#10022;</span>
          <span class='iso-rule'></span>
        </footer>
      </article>
      <style scoped>
        /* Default palette when NO theme is linked — pins the semantic
           tokens to the Parisian look so app-level defaults can't restyle
           the card arbitrarily. A linked theme omits this class. */
        .tsp-default-theme {
          color: var(--card-foreground);
        }

        .iso {
          container-type: inline-size;
          container-name: iso;
          height: 100%;
          overflow-y: auto;
          box-sizing: border-box;
          padding: 1.625rem 1.875rem 2.125rem;
          background:
            radial-gradient(
              120% 60% at 50% -8%,
              color-mix(in oklch, var(--card) 16%, transparent),
              transparent 60%
            ),
            var(--background);
          color: var(--foreground);
          font-family: var(--font-sans);
        }
        .iso-mast,
        .iso-colophon {
          display: flex;
          align-items: center;
          gap: 0.875rem;
        }
        .iso-rule {
          flex: 1;
          height: 1px;
          background: linear-gradient(
            90deg,
            transparent,
            color-mix(in oklch, var(--card) 35%, transparent),
            transparent
          );
        }
        .iso-mast-title {
          flex: none;
          font-family: var(--font-sans);
          font-size: 0.625rem;
          letter-spacing: 0.34em;
          text-transform: uppercase;
          color: var(--accent-ink);
        }
        .iso-colophon {
          margin-top: 2.125rem;
        }
        .iso-colophon-mark {
          flex: none;
          font-size: 0.75rem;
          color: var(--accent-ink);
        }
        .iso-hero {
          display: flex;
          align-items: center;
          gap: 1.5rem;
          margin: 1.75rem 0 0.625rem;
        }
        .iso-portrait {
          position: relative;
          flex: none;
        }
        .iso-ring {
          display: block;
          width: 6rem;
          height: 6rem;
          border-radius: 50%;
          padding: 0.1875rem;
          background: conic-gradient(
            from 140deg,
            color-mix(in oklch, var(--accent) 60%, var(--card)),
            color-mix(in oklch, var(--accent) 70%, var(--card)),
            color-mix(in oklch, var(--accent) 60%, var(--card))
          );
        }
        .iso-photo {
          width: 100%;
          height: 100%;
          border-radius: 50%;
          object-fit: cover;
          display: block;
          background-color: var(--background);
        }
        .iso-initials {
          display: flex;
          align-items: center;
          justify-content: center;
          font: 600 1.875rem var(--font-serif);
          color: var(--accent-foreground);
          background: linear-gradient(
            135deg,
            color-mix(in oklch, var(--accent) 45%, var(--card)),
            var(--accent)
          );
        }
        .iso-star {
          position: absolute;
          right: 0;
          bottom: 2px;
          width: 1.625rem;
          height: 1.625rem;
          border-radius: 50%;
          background-color: var(--accent);
          color: var(--accent-foreground);
          font-size: 0.8125rem;
          display: flex;
          align-items: center;
          justify-content: center;
          border: 2px solid var(--background);
        }
        .iso-ident {
          min-width: 0;
          display: flex;
          flex-direction: column;
          gap: 0.5rem;
        }
        .iso-kicker {
          font-family: var(--font-sans);
          font-size: 0.5938rem;
          letter-spacing: 0.3em;
          text-transform: uppercase;
          color: var(--accent-ink);
        }
        .iso-name-input {
          width: 100%;
          margin: 0;
          padding: 0 0 2px;
          border: none;
          border-bottom: 1px solid transparent;
          background-color: transparent;
          font-family: var(--font-serif);
          font-size: clamp(1.625rem, 5.5cqw, 2.375rem);
          font-weight: 500;
          line-height: 1.12;
          color: var(--foreground);
        }
        .iso-name-input:hover {
          border-bottom-color: color-mix(
            in oklch,
            var(--border-strong) 20%,
            transparent
          );
        }
        .iso-name-input:focus {
          outline: none;
          border-bottom-color: var(--accent);
        }
        .iso-cats {
          display: flex;
          flex-wrap: wrap;
          gap: 0.375rem;
          margin-top: 0.5rem;
        }
        .iso-catchip {
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
          padding: 0.3125rem 0.6875rem;
          border: 1px solid
            color-mix(in oklch, var(--border-strong) 20%, transparent);
          border-radius: 62.4375rem;
          background-color: var(--card);
          cursor: pointer;
          font-family: var(--font-sans);
          font-size: 0.6875rem;
          color: var(--foreground);
        }
        .iso-catchip.is-on {
          border-color: transparent;
          background-color: var(--accent);
          color: var(--accent-foreground);
        }
        .iso-vip-toggle {
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
          padding: 0.3125rem 0.8125rem;
          border: 1px solid
            color-mix(in oklch, var(--border-strong) 28%, transparent);
          border-radius: 62.4375rem;
          background-color: var(--card);
          cursor: pointer;
          font-family: var(--font-sans);
          font-size: 0.5938rem;
          letter-spacing: 0.14em;
          text-transform: uppercase;
          color: var(--foreground);
        }
        .iso-vip-toggle.is-on {
          background-color: var(--accent);
          border-color: var(--accent);
          color: var(--accent-foreground);
        }
        .iso-tags {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          gap: 0.5rem;
          margin-top: 2px;
        }
        .iso-pill {
          display: inline-flex;
          align-items: center;
          gap: 0.4375rem;
          padding: 0.3125rem 0.8125rem;
          border: 1px solid
            color-mix(in oklch, var(--border-strong) 28%, transparent);
          border-radius: 62.4375rem;
          font-family: var(--font-sans);
          font-size: 0.5938rem;
          letter-spacing: 0.14em;
          text-transform: uppercase;
          color: var(--foreground);
          background-color: var(--card);
        }
        .iso-pill.is-vip {
          background-color: var(--accent);
          border-color: var(--accent);
          color: var(--accent-foreground);
        }
        .iso-dot {
          width: 0.5625rem;
          height: 0.5625rem;
          border-radius: 50%;
          flex: none;
        }
        .iso-sect {
          display: flex;
          align-items: baseline;
          gap: 0.75rem;
          margin: 2rem 0 0.875rem;
        }
        .iso-sect-no {
          flex: none;
          font-family: var(--font-serif);
          font-style: italic;
          font-size: 0.9375rem;
          color: var(--accent-ink);
        }
        .iso-sect-title {
          flex: none;
          font-family: var(--font-sans);
          font-size: 0.625rem;
          letter-spacing: 0.3em;
          text-transform: uppercase;
          color: var(--foreground);
        }
        .iso-sect .iso-rule {
          align-self: center;
        }
        .iso-party {
          display: flex;
          flex-direction: column;
          gap: 0.5rem;
        }
        .iso-lbl {
          font-family: var(--font-sans);
          font-size: 0.5625rem;
          letter-spacing: 0.24em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .iso-party-card {
          max-width: 28.75rem;
        }
        .iso-empty-line {
          margin: 0;
          font-family: var(--font-serif);
          font-style: italic;
          font-size: 0.8438rem;
          color: var(--muted-foreground);
        }
        @container iso (max-width: 480px) {
          .iso-hero {
            flex-direction: column;
            align-items: flex-start;
            gap: 1rem;
          }
        }
      </style>
    </template>
  };
}
