import {
  Component,
  field,
  contains,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import enumField from 'https://cardstack.com/base/enum';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import CrownIcon from '@cardstack/boxel-icons/crown';

import { Person } from './person';
import { initialsOf } from './utils/index';

export const HOST_ROLES = [
  'Bride',
  'Groom',
  'Mother of the Bride',
  'Father of the Bride',
  'Mother of the Groom',
  'Father of the Groom',
] as const;

export const RoleField = enumField(StringField, {
  options: HOST_ROLES.map((r) => ({ value: r, label: r })),
});

export class Host extends Person {
  static displayName = 'Host';
  static icon = CrownIcon;

  @field role = contains(RoleField);

  static embedded = class Embedded extends Component<typeof this> {
    get initials() {
      return initialsOf(this.args.model?.fullName);
    }
    <template>
      <div class='h-row'>
        {{#if @model.photoURL}}
          <img class='h-avatar' src={{@model.photoURL}} alt='' />
        {{else}}
          <span class='h-avatar h-initials'>{{this.initials}}</span>
        {{/if}}
        <span class='h-main'>
          <span class='h-name'>{{if
              @model.fullName
              @model.fullName
              'Unnamed Host'
            }}</span>
          {{#if @model.role}}
            <span class='h-role'>{{@model.role}}</span>
          {{/if}}
        </span>
        <span class='h-badge'>✦ Host</span>
      </div>
      <style scoped>
        .h-row {
          display: flex;
          align-items: center;
          gap: 12px;
          padding: 9px 12px;
          border: 1px solid
            var(--tsp-border, var(--border, rgba(220, 193, 136, 0.55)));
          border-radius: 11px;
          background: var(--tsp-card, var(--card, #ffffff));
          font-family: var(
            --tsp-font-sans,
            var(--font-sans, 'Jost', system-ui, sans-serif)
          );
          color: var(--tsp-card-foreground, var(--card-foreground, #22283f));
        }
        .h-avatar {
          width: 38px;
          height: 38px;
          border-radius: 50%;
          flex: none;
          object-fit: cover;
        }
        .h-initials {
          display: flex;
          align-items: center;
          justify-content: center;
          font: 600 13px
            var(
              --tsp-font-serif,
              var(--font-serif, 'Cormorant Garamond', serif)
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
        .h-main {
          flex: 1;
          min-width: 0;
          display: flex;
          flex-direction: column;
          gap: 3px;
        }
        .h-name {
          font-size: 14px;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .h-role {
          font: 10px var(--tsp-font-sans, var(--font-sans, 'Jost', monospace));
          letter-spacing: 0.08em;
          text-transform: uppercase;
          color: var(--tsp-muted-foreground, var(--muted-foreground, #a5919c));
        }
        .h-badge {
          flex: none;
          font: 600 8.5px
            var(--tsp-font-sans, var(--font-sans, 'Jost', monospace));
          letter-spacing: 0.12em;
          text-transform: uppercase;
          color: var(
            --tsp-accent-foreground,
            var(--accent-foreground, #22283f)
          );
          background: var(--tsp-accent, var(--accent, #c5a35c));
          border-radius: 4px;
          padding: 3px 7px;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof Host> {
    get hasLinkedTheme(): boolean {
      return Boolean((this.args.model as any)?.cardInfo?.theme);
    }
    get initials() {
      return initialsOf(this.args.model?.fullName);
    }
    get name() {
      return this.args.model?.fullName || 'Unnamed Host';
    }
    <template>
      <div class='fitted {{unless this.hasLinkedTheme "tsp-default-theme"}}'>

        {{! BADGE (≤150w × ≤169h) — crown mark + name }}
        <div class='fmt badge'>
          <span class='b-mark'>✦</span>
          <div class='b-info'>
            <div class='b-name'>{{this.name}}</div>
            {{#if @model.role}}<div class='b-role'>{{@model.role}}</div>{{/if}}
          </div>
        </div>

        {{! STRIP (≥151w × ≤169h) — avatar · name · role · HOST tag }}
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
            {{#if @model.role}}<div class='s-role'>{{@model.role}}</div>{{/if}}
          </div>
          <span class='s-tag'>✦ Host</span>
        </div>

        {{! TILE (≤399w × ≥170h) — navy invitation spine, portrait, serif name }}
        <div class='fmt tile'>
          <div class='t-frame'>
            <span class='t-orn t-orn-top'>❧</span>
            <span class='t-ring'>
              {{#if @model.photoURL}}
                <img class='t-av' src={{@model.photoURL}} alt='' />
              {{else}}
                <span class='t-av t-initials'>{{this.initials}}</span>
              {{/if}}
            </span>
            <div class='t-kicker'>Hosting the celebration</div>
            <div class='t-name'>{{this.name}}</div>
            {{#if @model.role}}<div class='t-role'>{{@model.role}}</div>{{/if}}
            <span class='t-rule'></span>
            <span class='t-orn t-orn-bottom'>✦</span>
          </div>
        </div>

        {{! CARD (≥400w × ≥170h) — split invitation: navy spine + cream body }}
        <div class='fmt cardf'>
          <div class='c-spine'>
            <span class='c-orn'>❧</span>
            <span class='c-ring'>
              {{#if @model.photoURL}}
                <img class='c-av' src={{@model.photoURL}} alt='' />
              {{else}}
                <span class='c-av c-initials'>{{this.initials}}</span>
              {{/if}}
            </span>
            <span class='c-spine-rule'></span>
            <span class='c-spine-tag'>Host</span>
          </div>
          <div class='c-body'>
            <div class='c-kicker'>Hosting the celebration</div>
            <div class='c-name'>{{this.name}}</div>
            {{#if @model.role}}<div class='c-role'>{{@model.role}}</div>{{/if}}
            <div class='c-foot'>
              <span class='c-pill'>✦ Host</span>
              {{#if @model.role}}<span
                  class='c-pill c-pill-ghost'
                >{{@model.role}}</span>{{/if}}
            </div>
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
            background: var(--tsp-primary, var(--primary, #141b33));
            color: var(
              --tsp-primary-foreground,
              var(--primary-foreground, #f3ead6)
            );
          }
        }
        .b-mark {
          flex: none;
          font-size: 13px;
          color: var(--tsp-accent, var(--accent, #c5a35c));
        }
        .b-info {
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
        .b-role {
          font-size: 0.5rem;
          letter-spacing: 0.16em;
          text-transform: uppercase;
          color: var(--tsp-accent, var(--accent, #c5a35c));
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }

        /* ── STRIP ── */
        @container fitted-card (min-width: 151px) and (max-height: 169px) {
          .strip {
            display: flex;
            align-items: center;
            gap: 10px;
            padding: 8px 12px;
            background: linear-gradient(
              120deg,
              var(--tsp-primary, var(--primary, #141b33)) 0%,
              color-mix(
                  in srgb,
                  var(--tsp-primary, var(--primary, #141b33)) 88%,
                  #ffffff
                )
                100%
            );
            color: var(
              --tsp-primary-foreground,
              var(--primary-foreground, #f3ead6)
            );
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
        .s-role {
          font-size: 0.55rem;
          letter-spacing: 0.18em;
          text-transform: uppercase;
          color: var(--tsp-accent, var(--accent, #c5a35c));
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
        @container fitted-card (max-height: 64px) {
          .s-tag {
            display: none;
          }
        }

        /* ── TILE — navy invitation ── */
        @container fitted-card (max-width: 399px) and (min-height: 170px) {
          .tile {
            display: block;
            padding: clamp(6px, 4cqmin, 12px);
            background:
              radial-gradient(
                120% 80% at 50% -10%,
                color-mix(
                  in srgb,
                  var(--tsp-accent, var(--accent, #c5a35c)) 22%,
                  transparent
                ),
                transparent 55%
              ),
              var(--tsp-primary, var(--primary, #141b33));
            color: var(
              --tsp-primary-foreground,
              var(--primary-foreground, #f3ead6)
            );
          }
        }
        .t-frame {
          width: 100%;
          height: 100%;
          box-sizing: border-box;
          border: 1px solid
            color-mix(
              in srgb,
              var(--tsp-accent, var(--accent, #c5a35c)) 45%,
              transparent
            );
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
          color: var(--tsp-accent, var(--accent, #c5a35c));
        }
        .t-ring {
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
        .t-kicker {
          font-size: clamp(0.42rem, 4cqmin, 0.55rem);
          letter-spacing: 0.26em;
          text-transform: uppercase;
          color: var(--tsp-accent, var(--accent, #c5a35c));
          white-space: nowrap;
          overflow: hidden;
          max-width: 100%;
          text-overflow: ellipsis;
        }
        .t-name {
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
        .t-role {
          font-size: clamp(0.5rem, 4.5cqmin, 0.62rem);
          letter-spacing: 0.2em;
          text-transform: uppercase;
          color: color-mix(
            in srgb,
            var(--tsp-primary-foreground, var(--primary-foreground, #f3ead6))
              78%,
            transparent
          );
          white-space: nowrap;
          overflow: hidden;
          max-width: 100%;
          text-overflow: ellipsis;
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

        /* ── CARD — split invitation ── */
        @container fitted-card (min-width: 400px) and (min-height: 170px) {
          .cardf {
            display: flex;
            background: var(--tsp-card, var(--card, #fffdf8));
            border: 1px solid
              var(--tsp-border, var(--border, rgba(197, 163, 92, 0.35)));
            border-radius: var(--tsp-radius, var(--radius, 0.75rem));
          }
        }
        .c-spine {
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
              120% 80% at 50% -10%,
              color-mix(
                in srgb,
                var(--tsp-accent, var(--accent, #c5a35c)) 24%,
                transparent
              ),
              transparent 55%
            ),
            var(--tsp-primary, var(--primary, #141b33));
          color: var(
            --tsp-primary-foreground,
            var(--primary-foreground, #f3ead6)
          );
        }
        .c-orn {
          font-size: clamp(10px, 6cqmin, 14px);
          color: var(--tsp-accent, var(--accent, #c5a35c));
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
        .c-spine-rule {
          width: 40%;
          height: 1px;
          background: linear-gradient(
            90deg,
            transparent,
            var(--tsp-accent, var(--accent, #c5a35c)),
            transparent
          );
        }
        .c-spine-tag {
          font-size: 0.5rem;
          letter-spacing: 0.3em;
          text-transform: uppercase;
          color: var(--tsp-accent, var(--accent, #c5a35c));
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
        .c-role {
          font-size: clamp(0.55rem, 4.5cqmin, 0.7rem);
          letter-spacing: 0.2em;
          text-transform: uppercase;
          color: var(--tsp-muted-foreground, var(--muted-foreground, #7d7460));
        }
        .c-foot {
          display: flex;
          align-items: center;
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
        }
      </style>
    </template>
  };

  static isolated = class Isolated extends Component<typeof Host> {
    get hasLinkedTheme(): boolean {
      return Boolean((this.args.model as any)?.cardInfo?.theme);
    }
    get initials() {
      return initialsOf(this.args.model?.fullName);
    }
    setName = (e: Event) => {
      this.args.model.fullName = (e.target as HTMLInputElement).value;
    };
    roleOptions = HOST_ROLES;
    setRole = (value: string) => {
      this.args.model.role = this.args.model.role === value ? undefined : value;
    };
    <template>
      <article class='iso {{unless this.hasLinkedTheme "tsp-default-theme"}}'>
        <header class='iso-mast' aria-label='Masthead'>
          <span class='iso-rule'></span>
          <span class='iso-mast-title'>The Hosts</span>
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
            <span class='iso-crown' title='Host'>✦</span>
          </div>
          <div class='iso-ident'>
            <span class='iso-kicker'>Host Profile</span>
            <input
              class='iso-name-input'
              value={{@model.fullName}}
              placeholder='Unnamed Host'
              aria-label='Host name'
              {{on 'input' this.setName}}
            />
            <div class='iso-roles' aria-label='Role'>
              {{#each this.roleOptions as |role|}}
                <button
                  type='button'
                  aria-pressed={{if (eq @model.role role) 'true' 'false'}}
                  class='iso-catchip {{if (eq @model.role role) "is-on"}}'
                  {{on 'click' (fn this.setRole role)}}
                >
                  {{role}}
                </button>
              {{/each}}
            </div>
            <div class='iso-tags'>
              <span class='iso-pill is-host'>✦ Host</span>
            </div>
          </div>
        </div>

        <footer class='iso-colophon'>
          <span class='iso-rule'></span>
          <span class='iso-colophon-mark'>✦</span>
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
              color-mix(
                in srgb,
                var(--tsp-accent, var(--accent, #c5a35c)) 16%,
                transparent
              ),
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
            var(--tsp-border, var(--border, rgba(41, 26, 35, 0.35))),
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
          color: var(--tsp-accent-deep, #a5854a);
        }
        .iso-colophon {
          margin-top: 34px;
        }
        .iso-colophon-mark {
          flex: none;
          font-size: 12px;
          color: var(--tsp-accent-deep, #a5854a);
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
        .iso-crown {
          position: absolute;
          right: 0;
          bottom: 2px;
          width: 26px;
          height: 26px;
          border-radius: 50%;
          background: var(--tsp-accent, var(--accent, #a5854a));
          color: var(
            --tsp-accent-foreground,
            var(--accent-foreground, #22283f)
          );
          font-size: 13px;
          display: flex;
          align-items: center;
          justify-content: center;
          border: 2px solid var(--tsp-background, var(--background, #f7f1e4));
        }
        .iso-ident {
          min-width: 0;
          flex: 1;
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
          color: var(--tsp-accent-deep, #a5854a);
        }
        .iso-name-input {
          width: 100%;
          margin: 0;
          padding: 0 0 2px;
          border: none;
          border-bottom: 1px solid transparent;
          background: transparent;
          color: var(--tsp-foreground, var(--foreground, #22283f));
          font-family: var(
            --tsp-font-serif,
            var(--font-serif, 'Cormorant Garamond', Georgia, serif)
          );
          font-size: clamp(26px, 5.5cqw, 38px);
          font-weight: 500;
          line-height: 1.12;
        }
        .iso-name-input::placeholder {
          color: var(--tsp-muted-foreground, var(--muted-foreground, #8a7f6c));
        }
        .iso-name-input:hover {
          border-bottom-color: var(
            --tsp-border,
            var(--border, rgba(41, 26, 35, 0.2))
          );
        }
        .iso-name-input:focus {
          outline: none;
          border-bottom-color: var(--tsp-ring, var(--ring, #a5854a));
        }
        .iso-roles {
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
          border: 1px solid
            var(--tsp-border, var(--border, rgba(41, 26, 35, 0.2)));
          border-radius: 999px;
          background: var(--tsp-card, var(--card, #fffdf8));
          cursor: pointer;
          font-family: var(
            --tsp-font-sans,
            var(--font-sans, 'Jost', sans-serif)
          );
          font-size: 11px;
          color: var(--tsp-card-foreground, var(--card-foreground, #22283f));
        }
        .iso-catchip.is-on {
          border-color: transparent;
          background: var(--tsp-accent, var(--accent, #a5854a));
          color: var(
            --tsp-accent-foreground,
            var(--accent-foreground, #22283f)
          );
        }
        .iso-tags {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          gap: 8px;
          margin-top: 2px;
        }
        .iso-pill.is-host {
          display: inline-flex;
          align-items: center;
          gap: 7px;
          padding: 5px 13px;
          border: 1px solid var(--tsp-accent, var(--accent, #a5854a));
          border-radius: 999px;
          font-family: var(
            --tsp-font-sans,
            var(--font-sans, 'Jost', sans-serif)
          );
          font-size: 9.5px;
          letter-spacing: 0.14em;
          text-transform: uppercase;
          color: var(
            --tsp-accent-foreground,
            var(--accent-foreground, #22283f)
          );
          background: var(--tsp-accent, var(--accent, #a5854a));
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
