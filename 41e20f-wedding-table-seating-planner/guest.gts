import {
  Component,
  field,
  contains,
  linksTo,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import BooleanField from 'https://cardstack.com/base/boolean';
import enumField from 'https://cardstack.com/base/enum';
import { htmlSafe } from '@ember/template';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import UserIcon from '@cardstack/boxel-icons/user';

import { Person } from './person';
import {
  initialsOf,
  GUEST_CATEGORIES,
  categoryLabel,
  categoryColor,
} from './utils/index';

export const CategoryField = enumField(StringField, {
  options: GUEST_CATEGORIES.map(({ value, label }) => ({ value, label })),
});

function swatch(color: string | null | undefined) {
  return htmlSafe(`background:${color || '#c5a35c'}`);
}

export class Guest extends Person {
  static displayName = 'Guest';
  static icon = UserIcon;

  @field category = contains(CategoryField);

  @field parentGuest = linksTo(() => Guest); // set on a +1 → the inviting guest

  @field vip = contains(BooleanField);

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
        </span>
        {{#if @model.parentGuest}}
          <span class='g-party'>+1 of {{@model.parentGuest.fullName}}</span>
        {{/if}}
      </div>
      <style scoped>
        .g-row {
          display: flex;
          align-items: center;
          gap: 12px;
          padding: 9px 12px;
          border: 1px solid
            var(--tsp-border, var(--border, rgba(220, 193, 136, 0.3)));
          border-radius: 11px;
          background: var(--tsp-background, var(--background, #ffffff));
          font-family: var(
            --tsp-font-sans,
            var(--font-sans, 'Jost', system-ui, sans-serif)
          );
          color: var(--tsp-foreground, var(--foreground, #22283f));
        }
        .g-avatar {
          width: 38px;
          height: 38px;
          border-radius: 50%;
          flex: none;
          object-fit: cover;
        }
        .g-initials {
          display: flex;
          align-items: center;
          justify-content: center;
          font: 600 13px
            var(
              --tsp-font-serif,
              var(--font-serif, 'Cormorant Garamond', serif)
            );
          color: var(--tsp-foreground, var(--foreground, #22283f));
          background: linear-gradient(
            135deg,
            #dcc188,
            var(--tsp-accent, var(--accent, #c5a35c))
          );
        }
        .g-main {
          flex: 1;
          min-width: 0;
          display: flex;
          flex-direction: column;
          gap: 3px;
        }
        .g-name-line {
          display: flex;
          align-items: center;
          gap: 7px;
        }
        .g-name {
          font-size: 14px;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .g-vip {
          flex: none;
          font: 600 8px
            var(--tsp-font-sans, var(--font-sans, 'Jost', monospace));
          letter-spacing: 0.12em;
          color: var(--tsp-foreground, var(--foreground, #22283f));
          background: var(--tsp-accent, var(--accent, #c5a35c));
          border-radius: 4px;
          padding: 2px 5px;
        }
        .g-cat {
          display: flex;
          align-items: center;
          gap: 6px;
          font-size: 11px;
          color: var(--tsp-muted-foreground, var(--muted-foreground, #a5919c));
        }
        .g-dot {
          width: 10px;
          height: 10px;
          border-radius: 50%;
          flex: none;
        }
        .g-party {
          flex: none;
          font: 11px var(--tsp-font-sans, var(--font-sans, 'Jost', monospace));
          color: var(--tsp-accent-deep, #dcc188);
          border: 1px solid rgba(220, 193, 136, 0.35);
          border-radius: 999px;
          padding: 2px 8px;
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
          --background: #faf6ec;
          --foreground: #22283f;
          --card: #fffdf8;
          --card-foreground: #22283f;
          --popover: #fffdf8;
          --popover-foreground: #22283f;
          --primary: #141b33;
          --primary-foreground: #f3ead6;
          --secondary: #c5a35c;
          --secondary-foreground: #22283f;
          --muted: #f4eddb;
          --muted-foreground: #7d7460;
          --accent: #c5a35c;
          --accent-foreground: #22283f;
          --border: rgba(197, 163, 92, 0.35);
          --input: #fffdf8;
          --ring: #c5a35c;
          --radius: 0.75rem;
          --font-sans: 'Jost', system-ui, sans-serif;
          --font-serif: 'Cormorant Garamond', Georgia, serif;
        }
        .fitted {
          width: 100%;
          height: 100%;
          font-family: var(
            --tsp-font-sans,
            var(--font-sans, 'Jost', system-ui, sans-serif)
          );
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
            gap: 8px;
            padding: 6px 10px;
            background: var(--tsp-card, var(--card, #fffdf8));
            color: var(--tsp-card-foreground, var(--card-foreground, #22283f));
            border-left: 3px solid var(--tsp-accent, var(--accent, #c5a35c));
          }
        }
        .b-dot {
          flex: none;
          width: 8px;
          height: 8px;
          border-radius: 50%;
        }
        .b-info {
          flex: 1;
          min-width: 0;
        }
        .b-name {
          font-family: var(
            --tsp-font-serif,
            var(--font-serif, 'Cormorant Garamond', Georgia, serif)
          );
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
          color: var(--tsp-muted-foreground, var(--muted-foreground, #7d7460));
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .b-star {
          flex: none;
          font-size: 11px;
          color: var(--tsp-accent-deep, #a5854a);
        }

        /* ── STRIP ── */
        @container fitted-card (min-width: 151px) and (max-height: 169px) {
          .strip {
            display: flex;
            align-items: center;
            gap: 12px;
            padding: 8px 14px 8px 12px;
            background: linear-gradient(
              120deg,
              var(--tsp-card, var(--card, #fffdf8)) 55%,
              var(--tsp-muted, var(--muted, #f4eddb)) 140%
            );
            color: var(--tsp-card-foreground, var(--card-foreground, #22283f));
            border-left: 3px solid var(--tsp-accent, var(--accent, #c5a35c));
            box-shadow: inset 0 0 0 1px
              var(--tsp-border, var(--border, rgba(197, 163, 92, 0.35)));
          }
        }
        .s-ring {
          flex: none;
          display: block;
          width: clamp(28px, 70cqmin, 44px);
          height: clamp(28px, 70cqmin, 44px);
          border-radius: 50%;
          padding: 2px;
          background: conic-gradient(
            from 140deg,
            color-mix(
              in srgb,
              var(--tsp-accent, var(--accent, #c5a35c)) 60%,
              #ffffff
            ),
            var(--tsp-accent, var(--accent, #c5a35c)),
            color-mix(
              in srgb,
              var(--tsp-accent, var(--accent, #c5a35c)) 60%,
              #ffffff
            )
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
          font: 600 0.8em
            var(
              --tsp-font-serif,
              var(--font-serif, 'Cormorant Garamond', Georgia, serif)
            );
          color: var(
            --tsp-accent-foreground,
            var(--accent-foreground, #22283f)
          );
          background: var(--tsp-accent, var(--accent, #c5a35c));
        }
        .s-info {
          flex: 1;
          min-width: 0;
        }
        .s-name {
          font-family: var(
            --tsp-font-serif,
            var(--font-serif, 'Cormorant Garamond', Georgia, serif)
          );
          font-size: clamp(0.85rem, 26cqmin, 1.1rem);
          line-height: 1.15;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .s-meta {
          display: flex;
          align-items: center;
          gap: 5px;
          min-width: 0;
        }
        .s-dot {
          flex: none;
          width: 7px;
          height: 7px;
          border-radius: 50%;
        }
        .s-cat {
          font-size: 0.55rem;
          letter-spacing: 0.18em;
          text-transform: uppercase;
          color: var(--tsp-muted-foreground, var(--muted-foreground, #7d7460));
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
          color: var(
            --tsp-accent-foreground,
            var(--accent-foreground, #22283f)
          );
          background: var(--tsp-accent, var(--accent, #c5a35c));
          border-radius: 999px;
          padding: 3px 8px;
          white-space: nowrap;
        }
        .s-orn {
          flex: none;
          font-family: var(
            --tsp-font-serif,
            var(--font-serif, 'Cormorant Garamond', Georgia, serif)
          );
          font-size: clamp(14px, 34cqmin, 22px);
          line-height: 1;
          color: color-mix(
            in srgb,
            var(--tsp-accent, var(--accent, #c5a35c)) 45%,
            transparent
          );
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
            padding: clamp(6px, 4cqmin, 12px);
            background: radial-gradient(
              130% 90% at 50% -12%,
              var(--tsp-card, var(--card, #fffdf8)),
              var(--tsp-muted, var(--muted, #f4eddb)) 78%
            );
            color: var(--tsp-card-foreground, var(--card-foreground, #22283f));
          }
        }
        .t-frame {
          width: 100%;
          height: 100%;
          box-sizing: border-box;
          border: 1px solid
            var(--tsp-border, var(--border, rgba(197, 163, 92, 0.45)));
          border-radius: calc(var(--tsp-radius, var(--radius, 0.75rem)) / 1.5);
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          gap: clamp(3px, 2.4cqmin, 8px);
          padding: clamp(6px, 5cqmin, 16px);
          text-align: center;
          overflow: hidden;
        }
        .t-orn {
          flex: none;
          font-size: clamp(9px, 6cqmin, 13px);
          color: var(--tsp-accent-deep, #a5854a);
        }
        .t-ring {
          position: relative;
          flex: none;
          display: block;
          width: clamp(40px, 34cqmin, 84px);
          height: clamp(40px, 34cqmin, 84px);
          border-radius: 50%;
          padding: 2px;
          background: conic-gradient(
            from 140deg,
            color-mix(
              in srgb,
              var(--tsp-accent, var(--accent, #c5a35c)) 60%,
              #ffffff
            ),
            var(--tsp-accent, var(--accent, #c5a35c)),
            color-mix(
              in srgb,
              var(--tsp-accent, var(--accent, #c5a35c)) 60%,
              #ffffff
            )
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
          font: 600 clamp(14px, 13cqmin, 30px)
            var(
              --tsp-font-serif,
              var(--font-serif, 'Cormorant Garamond', Georgia, serif)
            );
          color: var(
            --tsp-accent-foreground,
            var(--accent-foreground, #22283f)
          );
          background: var(--tsp-accent, var(--accent, #c5a35c));
        }
        .t-star {
          position: absolute;
          right: -2px;
          bottom: -2px;
          width: clamp(14px, 10cqmin, 20px);
          height: clamp(14px, 10cqmin, 20px);
          border-radius: 50%;
          background: var(--tsp-accent, var(--accent, #c5a35c));
          color: var(
            --tsp-accent-foreground,
            var(--accent-foreground, #22283f)
          );
          font-size: clamp(8px, 6cqmin, 11px);
          display: flex;
          align-items: center;
          justify-content: center;
          border: 2px solid var(--tsp-card, var(--card, #fffdf8));
        }
        .t-kicker {
          font-size: clamp(0.42rem, 4cqmin, 0.55rem);
          letter-spacing: 0.26em;
          text-transform: uppercase;
          color: var(--tsp-accent-deep, #a5854a);
          white-space: nowrap;
          overflow: hidden;
          max-width: 100%;
          text-overflow: ellipsis;
        }
        .t-name {
          color: var(--tsp-primary, var(--primary, #141b33));
          font-family: var(
            --tsp-font-serif,
            var(--font-serif, 'Cormorant Garamond', Georgia, serif)
          );
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
          gap: 5px;
          max-width: 100%;
          font-size: clamp(0.5rem, 4.5cqmin, 0.62rem);
          letter-spacing: 0.2em;
          text-transform: uppercase;
          color: var(--tsp-muted-foreground, var(--muted-foreground, #7d7460));
          white-space: nowrap;
          overflow: hidden;
        }
        .t-dot {
          flex: none;
          width: 7px;
          height: 7px;
          border-radius: 50%;
        }
        .t-rule {
          flex: none;
          width: 34%;
          height: 1px;
          background: linear-gradient(
            90deg,
            transparent,
            var(--tsp-accent, var(--accent, #c5a35c)),
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
            background: var(--tsp-card, var(--card, #fffdf8));
            border: 1px solid
              var(--tsp-border, var(--border, rgba(197, 163, 92, 0.35)));
            border-radius: var(--tsp-radius, var(--radius, 0.75rem));
          }
        }
        .c-body {
          flex: 1;
          min-width: 0;
          display: flex;
          flex-direction: column;
          justify-content: center;
          gap: clamp(3px, 2.4cqmin, 8px);
          padding: clamp(10px, 6cqmin, 22px);
          color: var(--tsp-card-foreground, var(--card-foreground, #22283f));
        }
        .c-kicker {
          font-size: clamp(0.45rem, 4cqmin, 0.58rem);
          letter-spacing: 0.28em;
          text-transform: uppercase;
          color: var(--tsp-accent-deep, #a5854a);
        }
        .c-name {
          color: var(--tsp-primary, var(--primary, #141b33));
          font-family: var(
            --tsp-font-serif,
            var(--font-serif, 'Cormorant Garamond', Georgia, serif)
          );
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
          gap: 6px;
          font-size: clamp(0.55rem, 4.5cqmin, 0.7rem);
          letter-spacing: 0.2em;
          text-transform: uppercase;
          color: var(--tsp-muted-foreground, var(--muted-foreground, #7d7460));
        }
        .c-dot {
          flex: none;
          width: 8px;
          height: 8px;
          border-radius: 50%;
        }
        .c-foot {
          display: flex;
          align-items: center;
          flex-wrap: wrap;
          gap: 6px;
          margin-top: clamp(2px, 2cqmin, 8px);
        }
        .c-pill {
          font-size: 0.52rem;
          font-weight: 600;
          letter-spacing: 0.14em;
          text-transform: uppercase;
          color: var(
            --tsp-accent-foreground,
            var(--accent-foreground, #22283f)
          );
          background: var(--tsp-accent, var(--accent, #c5a35c));
          border: 1px solid var(--tsp-accent, var(--accent, #c5a35c));
          border-radius: 999px;
          padding: 3px 10px;
          white-space: nowrap;
        }
        .c-pill-ghost {
          color: var(--tsp-accent-deep, #a5854a);
          background: transparent;
          border-color: var(
            --tsp-border,
            var(--border, rgba(197, 163, 92, 0.45))
          );
          overflow: hidden;
          text-overflow: ellipsis;
          max-width: 100%;
        }
        .c-panel {
          flex: none;
          width: 34%;
          max-width: 176px;
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          gap: clamp(4px, 3cqmin, 10px);
          padding: clamp(8px, 5cqmin, 18px);
          background:
            radial-gradient(
              130% 90% at 50% -12%,
              color-mix(
                in srgb,
                var(--tsp-accent, var(--accent, #c5a35c)) 18%,
                transparent
              ),
              transparent 60%
            ),
            var(--tsp-muted, var(--muted, #f4eddb));
          border-left: 1px solid
            var(--tsp-border, var(--border, rgba(197, 163, 92, 0.35)));
        }
        .c-orn {
          font-size: clamp(10px, 6cqmin, 14px);
          color: var(--tsp-accent-deep, #a5854a);
        }
        .c-ring {
          display: block;
          width: clamp(48px, 38cqmin, 96px);
          height: clamp(48px, 38cqmin, 96px);
          border-radius: 50%;
          padding: 2.5px;
          background: conic-gradient(
            from 140deg,
            color-mix(
              in srgb,
              var(--tsp-accent, var(--accent, #c5a35c)) 60%,
              #ffffff
            ),
            var(--tsp-accent, var(--accent, #c5a35c)),
            color-mix(
              in srgb,
              var(--tsp-accent, var(--accent, #c5a35c)) 60%,
              #ffffff
            )
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
          font: 600 clamp(16px, 14cqmin, 34px)
            var(
              --tsp-font-serif,
              var(--font-serif, 'Cormorant Garamond', Georgia, serif)
            );
          color: var(
            --tsp-accent-foreground,
            var(--accent-foreground, #22283f)
          );
          background: var(--tsp-accent, var(--accent, #c5a35c));
        }
        .c-panel-rule {
          width: 40%;
          height: 1px;
          background: linear-gradient(
            90deg,
            transparent,
            var(--tsp-accent, var(--accent, #c5a35c)),
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
            <input
              class='iso-name-input'
              value={{@model.fullName}}
              placeholder='Unnamed Guest'
              aria-label='Guest name'
              {{on 'input' this.setName}}
            />
            <div class='iso-cats' aria-label='Category'>
              {{#each this.categoryOptions as |cat|}}
                <button
                  type='button'
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
                </button>
              {{/each}}
            </div>
            <div class='iso-tags'>
              <button
                type='button'
                aria-pressed={{if @model.vip 'true' 'false'}}
                class='iso-vip-toggle {{if @model.vip "is-on"}}'
                title='Mark as a VIP guest'
                {{on 'click' this.toggleVip}}
              >&#10022; VIP</button>
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
          --background: #faf6ec;
          --foreground: #22283f;
          --card: #fffdf8;
          --card-foreground: #22283f;
          --popover: #fffdf8;
          --popover-foreground: #22283f;
          --primary: #141b33;
          --primary-foreground: #f3ead6;
          --secondary: #c5a35c;
          --secondary-foreground: #22283f;
          --muted: #f4eddb;
          --muted-foreground: #7d7460;
          --accent: #c5a35c;
          --accent-foreground: #22283f;
          --border: rgba(197, 163, 92, 0.35);
          --input: #fffdf8;
          --ring: #c5a35c;
          --radius: 0.75rem;
          --font-sans: 'Jost', system-ui, sans-serif;
          --font-serif: 'Cormorant Garamond', Georgia, serif;
        }

        .iso {
          container-type: inline-size;
          container-name: iso;
          height: 100%;
          overflow-y: auto;
          box-sizing: border-box;
          padding: 26px 30px 34px;
          background:
            radial-gradient(
              120% 60% at 50% -8%,
              rgba(197, 163, 92, 0.16),
              transparent 60%
            ),
            var(--tsp-background, var(--background, #f7f1e4));
          color: var(--tsp-foreground, var(--foreground, #22283f));
          font-family: var(
            --tsp-font-sans,
            var(--font-sans, 'Jost', system-ui, sans-serif)
          );
        }
        .iso-mast,
        .iso-colophon {
          display: flex;
          align-items: center;
          gap: 14px;
        }
        .iso-rule {
          flex: 1;
          height: 1px;
          background: linear-gradient(
            90deg,
            transparent,
            rgba(41, 26, 35, 0.35),
            transparent
          );
        }
        .iso-mast-title {
          flex: none;
          font-family: var(
            --tsp-font-sans,
            var(--font-sans, 'Jost', sans-serif)
          );
          font-size: 10px;
          letter-spacing: 0.34em;
          text-transform: uppercase;
          color: var(--tsp-accent, var(--accent, #a5854a));
        }
        .iso-colophon {
          margin-top: 34px;
        }
        .iso-colophon-mark {
          flex: none;
          font-size: 12px;
          color: var(--tsp-accent, var(--accent, #a5854a));
        }
        .iso-hero {
          display: flex;
          align-items: center;
          gap: 24px;
          margin: 28px 0 10px;
        }
        .iso-portrait {
          position: relative;
          flex: none;
        }
        .iso-ring {
          display: block;
          width: 96px;
          height: 96px;
          border-radius: 50%;
          padding: 3px;
          background: conic-gradient(
            from 140deg,
            color-mix(
              in srgb,
              var(--tsp-accent, var(--accent, #c5a35c)) 60%,
              #ffffff
            ),
            color-mix(
              in srgb,
              var(--tsp-accent, var(--accent, #c5a35c)) 70%,
              #000000
            ),
            color-mix(
              in srgb,
              var(--tsp-accent, var(--accent, #c5a35c)) 60%,
              #ffffff
            )
          );
        }
        .iso-photo {
          width: 100%;
          height: 100%;
          border-radius: 50%;
          object-fit: cover;
          display: block;
          background: var(--tsp-background, var(--background, #f7f1e4));
        }
        .iso-initials {
          display: flex;
          align-items: center;
          justify-content: center;
          font: 600 30px
            var(
              --tsp-font-serif,
              var(--font-serif, 'Cormorant Garamond', Georgia, serif)
            );
          color: var(
            --tsp-accent-foreground,
            var(--accent-foreground, #22283f)
          );
          background: linear-gradient(
            135deg,
            color-mix(
              in srgb,
              var(--tsp-accent, var(--accent, #c5a35c)) 45%,
              #ffffff
            ),
            var(--tsp-accent, var(--accent, #c5a35c))
          );
        }
        .iso-star {
          position: absolute;
          right: 0;
          bottom: 2px;
          width: 26px;
          height: 26px;
          border-radius: 50%;
          background: var(--tsp-accent, var(--accent, #a5854a));
          color: var(--tsp-card, var(--card, #fffdf8));
          font-size: 13px;
          display: flex;
          align-items: center;
          justify-content: center;
          border: 2px solid var(--tsp-background, var(--background, #f7f1e4));
        }
        .iso-ident {
          min-width: 0;
          display: flex;
          flex-direction: column;
          gap: 8px;
        }
        .iso-kicker {
          font-family: var(
            --tsp-font-sans,
            var(--font-sans, 'Jost', sans-serif)
          );
          font-size: 9.5px;
          letter-spacing: 0.3em;
          text-transform: uppercase;
          color: var(--tsp-accent, var(--accent, #a5854a));
        }
        .iso-name-input {
          width: 100%;
          margin: 0;
          padding: 0 0 2px;
          border: none;
          border-bottom: 1px solid transparent;
          background: transparent;
          font-family: var(
            --tsp-font-serif,
            var(--font-serif, 'Cormorant Garamond', Georgia, serif)
          );
          font-size: clamp(26px, 5.5cqw, 38px);
          font-weight: 500;
          line-height: 1.12;
          color: var(--tsp-foreground, var(--foreground, #22283f));
        }
        .iso-name-input:hover {
          border-bottom-color: rgba(41, 26, 35, 0.2);
        }
        .iso-name-input:focus {
          outline: none;
          border-bottom-color: var(--tsp-accent, var(--accent, #a5854a));
        }
        .iso-cats {
          display: flex;
          flex-wrap: wrap;
          gap: 6px;
          margin-top: 8px;
        }
        .iso-catchip {
          display: inline-flex;
          align-items: center;
          gap: 6px;
          padding: 5px 11px;
          border: 1px solid rgba(41, 26, 35, 0.2);
          border-radius: 999px;
          background: var(--tsp-card, var(--card, #fffdf8));
          cursor: pointer;
          font-family: var(
            --tsp-font-sans,
            var(--font-sans, 'Jost', sans-serif)
          );
          font-size: 11px;
          color: var(--tsp-foreground, var(--foreground, #22283f));
        }
        .iso-catchip.is-on {
          border-color: transparent;
          background: var(--tsp-accent, var(--accent, #a5854a));
          color: var(--tsp-card, var(--card, #fffdf8));
        }
        .iso-vip-toggle {
          display: inline-flex;
          align-items: center;
          gap: 6px;
          padding: 5px 13px;
          border: 1px solid rgba(41, 26, 35, 0.28);
          border-radius: 999px;
          background: var(--tsp-card, var(--card, #fffdf8));
          cursor: pointer;
          font-family: var(
            --tsp-font-sans,
            var(--font-sans, 'Jost', sans-serif)
          );
          font-size: 9.5px;
          letter-spacing: 0.14em;
          text-transform: uppercase;
          color: var(--tsp-foreground, var(--foreground, #22283f));
        }
        .iso-vip-toggle.is-on {
          background: var(--tsp-accent, var(--accent, #a5854a));
          border-color: var(--tsp-accent, var(--accent, #a5854a));
          color: var(--tsp-card, var(--card, #fffdf8));
        }
        .iso-tags {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          gap: 8px;
          margin-top: 2px;
        }
        .iso-pill {
          display: inline-flex;
          align-items: center;
          gap: 7px;
          padding: 5px 13px;
          border: 1px solid rgba(41, 26, 35, 0.28);
          border-radius: 999px;
          font-family: var(
            --tsp-font-sans,
            var(--font-sans, 'Jost', sans-serif)
          );
          font-size: 9.5px;
          letter-spacing: 0.14em;
          text-transform: uppercase;
          color: var(--tsp-foreground, var(--foreground, #22283f));
          background: var(--tsp-card, var(--card, #fffdf8));
        }
        .iso-pill.is-vip {
          background: var(--tsp-accent, var(--accent, #a5854a));
          border-color: var(--tsp-accent, var(--accent, #a5854a));
          color: var(--tsp-card, var(--card, #fffdf8));
        }
        .iso-dot {
          width: 9px;
          height: 9px;
          border-radius: 50%;
          flex: none;
        }
        .iso-sect {
          display: flex;
          align-items: baseline;
          gap: 12px;
          margin: 32px 0 14px;
        }
        .iso-sect-no {
          flex: none;
          font-family: var(
            --tsp-font-serif,
            var(--font-serif, 'Cormorant Garamond', Georgia, serif)
          );
          font-style: italic;
          font-size: 15px;
          color: var(--tsp-accent, var(--accent, #a5854a));
        }
        .iso-sect-title {
          flex: none;
          font-family: var(
            --tsp-font-sans,
            var(--font-sans, 'Jost', sans-serif)
          );
          font-size: 10px;
          letter-spacing: 0.3em;
          text-transform: uppercase;
          color: var(--tsp-foreground, var(--foreground, #22283f));
        }
        .iso-sect .iso-rule {
          align-self: center;
        }
        .iso-party {
          display: flex;
          flex-direction: column;
          gap: 8px;
        }
        .iso-lbl {
          font-family: var(
            --tsp-font-sans,
            var(--font-sans, 'Jost', sans-serif)
          );
          font-size: 9px;
          letter-spacing: 0.24em;
          text-transform: uppercase;
          color: var(--tsp-muted-foreground, var(--muted-foreground, #8a7f6c));
        }
        .iso-party-card {
          max-width: 460px;
        }
        .iso-empty-line {
          margin: 0;
          font-family: var(
            --tsp-font-serif,
            var(--font-serif, 'Cormorant Garamond', Georgia, serif)
          );
          font-style: italic;
          font-size: 13.5px;
          color: var(--tsp-muted-foreground, var(--muted-foreground, #8a7f6c));
        }
        @container iso (max-width: 480px) {
          .iso-hero {
            flex-direction: column;
            align-items: flex-start;
            gap: 16px;
          }
        }
      </style>
    </template>
  };
}
