import { Component, field, contains } from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import enumField from '@cardstack/base/enum';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { BoxelInput, Button } from '@cardstack/boxel-ui/components';
import { eq } from '@cardstack/boxel-ui/helpers';
import CrownIcon from '@cardstack/boxel-icons/crown';
import ImageSourceField from '@cardstack/catalog/fields/image-source/image-source';

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

  // The edit form renders subclass fields before inherited ones, so
  // fullName/photo are re-declared here to hoist identity to the top; role is
  // the only host-specific input; computed title stays last.

  @field fullName = contains(StringField);

  @field photo = contains(ImageSourceField);

  @field role = contains(RoleField);

  @field title = contains(StringField, {
    computeVia: function (this: Host) {
      return this.fullName?.trim() || 'Unnamed Host';
    },
  });

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
          gap: 0.75rem;
          padding: 0.5625rem 0.75rem;
          border: 1px solid var(--border);
          border-radius: 0.6875rem;
          background-color: var(--card);
          font-family: var(--font-sans);
          color: var(--card-foreground);
        }
        .h-avatar {
          width: 2.375rem;
          height: 2.375rem;
          border-radius: 50%;
          flex: none;
          object-fit: cover;
        }
        .h-initials {
          display: flex;
          align-items: center;
          justify-content: center;
          font: 600 0.8125rem var(--font-serif);
          color: var(--accent-foreground);
          background: linear-gradient(
            135deg,
            color-mix(in oklch, var(--accent) 45%, var(--card)),
            var(--accent)
          );
        }
        .h-main {
          flex: 1;
          min-width: 0;
          display: flex;
          flex-direction: column;
          gap: 0.1875rem;
        }
        .h-name {
          font-size: 0.875rem;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .h-role {
          font: 0.625rem var(--font-sans);
          letter-spacing: 0.08em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .h-badge {
          flex: none;
          font: 600 0.5312rem var(--font-sans);
          letter-spacing: 0.12em;
          text-transform: uppercase;
          color: var(--accent-foreground);
          background-color: var(--accent);
          border-radius: 0.25rem;
          padding: 0.1875rem 0.4375rem;
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
            background-color: var(--primary);
            color: var(--primary-foreground);
          }
        }
        .b-mark {
          flex: none;
          font-size: 0.8125rem;
          color: var(--accent-ink);
        }
        .b-info {
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
        .b-role {
          font-size: 0.5rem;
          letter-spacing: 0.16em;
          text-transform: uppercase;
          color: var(--accent-ink);
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }

        /* ── STRIP ── */
        @container fitted-card (min-width: 151px) and (max-height: 169px) {
          .strip {
            display: flex;
            align-items: center;
            gap: 0.625rem;
            padding: 0.5rem 0.75rem;
            background: linear-gradient(
              120deg,
              var(--card) 55%,
              var(--muted) 140%
            );
            color: var(--card-foreground);
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
        .s-role {
          font-size: 0.55rem;
          letter-spacing: 0.18em;
          text-transform: uppercase;
          color: var(--accent-ink);
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
        @container fitted-card (max-height: 64px) {
          .s-tag {
            display: none;
          }
        }

        /* ── TILE — navy invitation ── */
        @container fitted-card (max-width: 399px) and (min-height: 170px) {
          .tile {
            display: block;
            padding: clamp(0.375rem, 4cqmin, 0.75rem);
            background:
              radial-gradient(
                120% 80% at 50% -10%,
                color-mix(in oklch, var(--card) 22%, transparent),
                transparent 55%
              ),
              var(--card);
            color: var(--card-foreground);
          }
        }
        .t-frame {
          width: 100%;
          height: 100%;
          box-sizing: border-box;
          border: 1px solid color-mix(in oklch, var(--accent) 45%, transparent);
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
          font-family: var(--font-serif);
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
            in oklch,
            var(--primary-foreground) 78%,
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

        /* ── CARD — split invitation ── */
        @container fitted-card (min-width: 400px) and (min-height: 170px) {
          .cardf {
            display: flex;
            background-color: var(--card);
            color: var(--card-foreground);
            border: 1px solid var(--border);
            border-radius: var(--radius);
          }
        }
        .c-spine {
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
              120% 80% at 50% -10%,
              color-mix(in oklch, var(--accent) 24%, transparent),
              transparent 55%
            ),
            var(--primary);
          color: var(--primary-foreground);
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
        .c-spine-rule {
          width: 40%;
          height: 1px;
          background: linear-gradient(
            90deg,
            transparent,
            var(--accent),
            transparent
          );
        }
        .c-spine-tag {
          font-size: 0.5rem;
          letter-spacing: 0.3em;
          text-transform: uppercase;
          color: var(--accent-ink);
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
          font-family: var(--font-serif);
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
          color: var(--muted-foreground);
        }
        .c-foot {
          display: flex;
          align-items: center;
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
            <BoxelInput
              class='iso-name-input'
              @value={{@model.fullName}}
              placeholder='Unnamed Host'
              aria-label='Host name'
              {{on 'input' this.setName}}
            />
            <div class='iso-roles' aria-label='Role'>
              {{#each this.roleOptions as |role|}}
                <Button
                  @size='auto'
                  @kind='text-only'
                  aria-pressed={{if (eq @model.role role) 'true' 'false'}}
                  class='iso-catchip {{if (eq @model.role role) "is-on"}}'
                  {{on 'click' (fn this.setRole role)}}
                >
                  {{role}}
                </Button>
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
            var(--border),
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
        .iso-crown {
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
          flex: 1;
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
          color: var(--foreground);
          font-family: var(--font-serif);
          font-size: clamp(1.625rem, 5.5cqw, 2.375rem);
          font-weight: 500;
          line-height: 1.12;
        }
        .iso-name-input::placeholder {
          color: var(--muted-foreground);
        }
        .iso-name-input:hover {
          border-bottom-color: var(--border);
        }
        .iso-name-input:focus {
          outline: none;
          border-bottom-color: var(--ring);
        }
        .iso-roles {
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
          border: 1px solid var(--border);
          border-radius: 62.4375rem;
          background-color: var(--card);
          cursor: pointer;
          font-family: var(--font-sans);
          font-size: 0.6875rem;
          color: var(--card-foreground);
        }
        .iso-catchip.is-on {
          border-color: transparent;
          background-color: var(--accent);
          color: var(--accent-foreground);
        }
        .iso-tags {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          gap: 0.5rem;
          margin-top: 2px;
        }
        .iso-pill.is-host {
          display: inline-flex;
          align-items: center;
          gap: 0.4375rem;
          padding: 0.3125rem 0.8125rem;
          border: 1px solid var(--accent);
          border-radius: 62.4375rem;
          font-family: var(--font-sans);
          font-size: 0.5938rem;
          letter-spacing: 0.14em;
          text-transform: uppercase;
          color: var(--accent-foreground);
          background-color: var(--accent);
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
