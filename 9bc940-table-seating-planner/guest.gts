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

  static embedded = class Embedded extends Component<typeof Guest> {
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
          border: 1px solid var(--border, rgba(220, 193, 136, 0.3));
          border-radius: 11px;
          background: var(--background, #ffffff);
          font-family: 'Jost', system-ui, sans-serif;
          color: var(--foreground, #22283f);
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
          font:
            600 13px 'Cormorant Garamond',
            serif;
          color: #22283f;
          background: linear-gradient(135deg, #dcc188, #c5a35c);
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
          font:
            600 8px 'Jost',
            monospace;
          letter-spacing: 0.12em;
          color: #22283f;
          background: #c5a35c;
          border-radius: 4px;
          padding: 2px 5px;
        }
        .g-cat {
          display: flex;
          align-items: center;
          gap: 6px;
          font-size: 11px;
          color: var(--muted-foreground, #a5919c);
        }
        .g-dot {
          width: 10px;
          height: 10px;
          border-radius: 50%;
          flex: none;
        }
        .g-party {
          flex: none;
          font:
            11px 'Jost',
            monospace;
          color: var(--acc-deep, #dcc188);
          border: 1px solid rgba(220, 193, 136, 0.35);
          border-radius: 999px;
          padding: 2px 8px;
        }
      </style>
    </template>
  };

  static edit = class Edit extends Component<typeof Guest> {
    categoryOptions = GUEST_CATEGORIES;
    setCategory = (value: string) => {
      this.args.model.category =
        this.args.model.category === value ? undefined : value;
    };
    toggleVip = () => {
      this.args.model.vip = !this.args.model.vip;
    };
    <template>
      <article class='mag'>

        <header class='mag-mast' aria-label='Masthead'>
          <span class='mag-rule'></span>
          <span class='mag-mast-title'>The Guest List</span>
          <span class='mag-rule'></span>
        </header>

        <div class='mag-ident'>
          <div class='mag-ident-top'>
            <span class='mag-kicker'>Guest Profile</span>
            <button
              type='button'
              class='mag-vip {{if @model.vip "is-on"}}'
              title='Mark as a VIP guest'
              {{on 'click' this.toggleVip}}
            >
              <span class='mag-vip-star'>&#10022;</span>
              VIP
            </button>
          </div>
          <div class='mag-name'>
            <@fields.fullName />
          </div>

          <div class='mag-field'>
            <span class='mag-lbl'>Category</span>
            <div class='mag-cats'>
              {{#each this.categoryOptions as |cat|}}
                <button
                  type='button'
                  class='mag-cat {{if (eq @model.category cat.value) "is-on"}}'
                  {{on 'click' (fn this.setCategory cat.value)}}
                >
                  <span class='mag-cat-dot' style={{swatch cat.color}}></span>
                  {{cat.label}}
                </button>
              {{/each}}
            </div>
          </div>

          <div class='mag-field'>
            <span class='mag-lbl'>Photo
              <span class='mag-hint'>optional</span></span>
            <@fields.photo />
          </div>
        </div>

        <header class='mag-sect' aria-label='Party'>
          <span class='mag-sect-no'>01</span>
          <span class='mag-sect-title'>Party</span>
          <span class='mag-rule'></span>
        </header>
        <div class='mag-field'>
          <span class='mag-lbl'>Guest of
            <span class='mag-hint'>set on a +1 — links back to the guest who
              brings them</span></span>
          <@fields.parentGuest />
        </div>

        <footer class='mag-colophon'>
          <span class='mag-rule'></span>
          <span class='mag-colophon-mark'>&#10022;</span>
          <span class='mag-rule'></span>
        </footer>
      </article>
      <style scoped>
        .mag {
          --background: #fffdf8;
          --foreground: #22283f;
          --border: rgba(41, 26, 35, 0.18);
          --muted-foreground: #8a7f6c;
          --boxel-form-control-border-color: rgba(41, 26, 35, 0.22);
          --ink: #22283f;
          --gold: #a5854a;
          --paper: #f7f1e4;
          container-type: inline-size;
          container-name: mag;
          height: 100%;
          overflow-y: auto;
          box-sizing: border-box;
          padding: 26px 28px 34px;
          background:
            radial-gradient(
              120% 60% at 50% -8%,
              rgba(197, 163, 92, 0.16),
              transparent 60%
            ),
            var(--paper);
          color: var(--ink);
          font-family: 'Jost', system-ui, sans-serif;
        }
        .mag-mast,
        .mag-colophon {
          display: flex;
          align-items: center;
          gap: 14px;
        }
        .mag-rule {
          flex: 1;
          height: 1px;
          background: linear-gradient(
            90deg,
            transparent,
            rgba(41, 26, 35, 0.35),
            transparent
          );
        }
        .mag-mast-title {
          flex: none;
          font-family: 'Jost', sans-serif;
          font-size: 10px;
          letter-spacing: 0.34em;
          text-transform: uppercase;
          color: var(--gold);
        }
        .mag-colophon {
          margin-top: 30px;
        }
        .mag-colophon-mark {
          flex: none;
          font-size: 12px;
          color: var(--gold);
        }
        .mag-ident {
          min-width: 0;
          display: flex;
          flex-direction: column;
          gap: 16px;
          margin: 24px 0 8px;
        }
        .mag-ident-top {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: 12px;
        }
        .mag-kicker {
          font-family: 'Jost', sans-serif;
          font-size: 9.5px;
          letter-spacing: 0.3em;
          text-transform: uppercase;
          color: var(--gold);
        }
        .mag-vip {
          flex: none;
          display: inline-flex;
          align-items: center;
          gap: 6px;
          padding: 5px 12px;
          border: 1px solid rgba(41, 26, 35, 0.28);
          border-radius: 999px;
          background: transparent;
          font-family: 'Jost', sans-serif;
          font-size: 9.5px;
          letter-spacing: 0.2em;
          text-transform: uppercase;
          color: var(--muted-foreground);
          cursor: pointer;
          transition:
            background 0.15s,
            color 0.15s,
            border-color 0.15s;
        }
        .mag-vip:hover {
          border-color: var(--gold);
          color: var(--gold);
        }
        .mag-vip.is-on {
          background: var(--gold);
          border-color: var(--gold);
          color: #fffdf8;
        }
        .mag-vip-star {
          font-size: 11px;
        }
        .mag-name :deep(.boxel-input) {
          font-family: 'Cormorant Garamond', Georgia, serif;
          font-size: clamp(24px, 5cqw, 34px);
          font-weight: 500;
          line-height: 1.15;
          padding: 4px 2px 10px;
          background: transparent;
          border: none;
          border-radius: 0;
          border-bottom: 1px solid rgba(41, 26, 35, 0.3);
          color: var(--ink);
        }
        .mag-name :deep(.boxel-input:focus) {
          outline: none;
          border-bottom-color: var(--gold);
          box-shadow: none;
        }
        .mag-cats {
          display: flex;
          flex-wrap: wrap;
          gap: 8px;
        }
        .mag-cat {
          display: inline-flex;
          align-items: center;
          gap: 7px;
          padding: 6px 14px;
          border: 1px solid rgba(41, 26, 35, 0.28);
          border-radius: 999px;
          background: #fffdf8;
          font-family: 'Jost', sans-serif;
          font-size: 9.5px;
          letter-spacing: 0.14em;
          text-transform: uppercase;
          color: var(--muted-foreground);
          cursor: pointer;
          transition:
            background 0.15s,
            color 0.15s,
            border-color 0.15s;
        }
        .mag-cat:hover {
          border-color: var(--ink);
          color: var(--ink);
        }
        .mag-cat.is-on {
          background: var(--ink);
          border-color: var(--ink);
          color: #f7f1e4;
        }
        .mag-cat-dot {
          width: 9px;
          height: 9px;
          border-radius: 50%;
          flex: none;
        }
        .mag-sect {
          display: flex;
          align-items: baseline;
          gap: 12px;
          margin: 30px 0 14px;
        }
        .mag-sect-no {
          flex: none;
          font-family: 'Cormorant Garamond', Georgia, serif;
          font-style: italic;
          font-size: 15px;
          color: var(--gold);
        }
        .mag-sect-title {
          flex: none;
          font-family: 'Jost', sans-serif;
          font-size: 10px;
          letter-spacing: 0.3em;
          text-transform: uppercase;
          color: var(--ink);
        }
        .mag-sect .mag-rule {
          align-self: center;
        }
        .mag-field {
          min-width: 0;
          display: flex;
          flex-direction: column;
          gap: 6px;
        }
        .mag-lbl {
          font-family: 'Jost', sans-serif;
          font-size: 9px;
          letter-spacing: 0.24em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .mag-hint {
          letter-spacing: 0.05em;
          text-transform: none;
          color: rgba(138, 127, 108, 0.75);
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof Guest> {
    get initials() {
      return initialsOf(this.args.model?.fullName);
    }
    <template>
      <div class='cq'>
        <div class='fit'>
          <span class='gx' aria-hidden='true'>&#10022;</span>
          <div class='r-avatar'>
            <span class='ring'>
              {{#if @model.photoURL}}
                <img class='av' src={{@model.photoURL}} alt='' />
              {{else}}
                <span class='av initials'>{{this.initials}}</span>
              {{/if}}
            </span>
            {{#if @model.vip}}<span
                class='star'
                title='VIP'
              >&#9733;</span>{{/if}}
          </div>
          <div class='r-name'>{{if
              @model.fullName
              @model.fullName
              'Unnamed Guest'
            }}</div>
          <div class='r-meta'>
            {{#if @model.category}}
              <span
                class='dot'
                style={{swatch (categoryColor @model.category)}}
              ></span>
              <span class='cat'>{{categoryLabel @model.category}}</span>
            {{/if}}
          </div>
          <div class='r-foot'>
            {{#if @model.parentGuest}}
              <span class='pill'>+1 of {{@model.parentGuest.fullName}}</span>
            {{/if}}
            {{#if @model.vip}}<span class='pill is-vip'>VIP</span>{{/if}}
          </div>
        </div>
      </div>
      <style scoped>
        .cq {
          container-type: size;
          container-name: guest;
          width: 100%;
          height: 100%;
          overflow: hidden;
        }
        .fit {
          position: relative;
          width: 100%;
          height: 100%;
          box-sizing: border-box;
          overflow: hidden;
          display: grid;
          grid-template-columns: 1fr;
          grid-template-rows: auto auto auto 1fr;
          grid-template-areas: 'avatar' 'name' 'meta' 'foot';
          justify-items: center;
          align-content: center;
          text-align: center;
          gap: 7px;
          padding: 18px 14px;
          background: radial-gradient(
            130% 90% at 50% -12%,
            #ffffff,
            #f0eee7 72%
          );
          color: #22283f;
          border: 1px solid rgba(220, 193, 136, 0.3);
          border-radius: 14px;
          font-family: 'Jost', system-ui, sans-serif;
        }
        .gx {
          position: absolute;
          top: 9px;
          right: 12px;
          font-size: 11px;
          color: rgba(197, 163, 92, 0.55);
        }
        .r-avatar {
          grid-area: avatar;
          position: relative;
          min-height: 0;
        }
        .ring {
          display: block;
          width: 64px;
          height: 64px;
          border-radius: 50%;
          padding: 2px;
          background: conic-gradient(from 140deg, #dcc188, #8a6f3e, #dcc188);
        }
        .av {
          width: 100%;
          height: 100%;
          border-radius: 50%;
          object-fit: cover;
          display: block;
          background: #f0eee7;
        }
        .initials {
          display: flex;
          align-items: center;
          justify-content: center;
          font:
            600 22px 'Cormorant Garamond',
            Georgia,
            serif;
          color: #22283f;
          background: linear-gradient(135deg, #f0dca4, #c5a35c);
        }
        .star {
          position: absolute;
          right: -2px;
          bottom: -2px;
          width: 20px;
          height: 20px;
          border-radius: 50%;
          background: #c5a35c;
          color: #22283f;
          font-size: 11px;
          display: flex;
          align-items: center;
          justify-content: center;
          border: 2px solid #22283f;
        }
        .r-name {
          grid-area: name;
          min-height: 0;
          overflow: hidden;
          font-family: 'Cormorant Garamond', Georgia, serif;
          font-size: 17px;
          line-height: 1.16;
          color: #22283f;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
        }
        .r-meta {
          grid-area: meta;
          min-height: 0;
          overflow: hidden;
          display: flex;
          align-items: center;
          justify-content: center;
          gap: 7px;
        }
        .dot {
          width: 8px;
          height: 8px;
          border-radius: 2px;
          flex: none;
        }
        .cat {
          font-family: 'Jost', sans-serif;
          font-size: 9.5px;
          letter-spacing: 0.18em;
          text-transform: uppercase;
          color: #c2b1ba;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .r-foot {
          grid-area: foot;
          min-height: 0;
          overflow: hidden;
          align-self: start;
          display: flex;
          align-items: center;
          justify-content: center;
          gap: 6px;
        }
        .pill {
          font-family: 'Jost', sans-serif;
          font-size: 8.5px;
          letter-spacing: 0.12em;
          text-transform: uppercase;
          color: #dcc188;
          border: 1px solid rgba(220, 193, 136, 0.4);
          border-radius: 20px;
          padding: 3px 9px;
          white-space: nowrap;
        }
        .pill.is-vip {
          background: #c5a35c;
          color: #22283f;
          border-color: #c5a35c;
        }
        @container guest (max-height: 132px) and (min-width: 168px) {
          .fit {
            grid-template-columns: auto minmax(0, 1fr);
            grid-template-rows: auto auto;
            grid-template-areas: 'avatar name' 'avatar meta';
            justify-items: start;
            text-align: left;
            align-content: center;
            gap: 3px 13px;
            padding: 12px 15px;
            border-radius: 12px;
          }
          .gx,
          .r-foot {
            display: none;
          }
          .ring {
            width: 46px;
            height: 46px;
          }
          .initials {
            font-size: 16px;
          }
          .r-name {
            -webkit-line-clamp: 1;
            font-size: 15px;
          }
          .r-meta {
            justify-content: flex-start;
          }
        }
        @container guest (max-width: 122px) {
          .fit {
            grid-template-columns: 1fr;
            grid-template-rows: 1fr;
            grid-template-areas: 'avatar';
            padding: 8px;
            border-radius: 12px;
          }
          .gx,
          .r-name,
          .r-meta,
          .r-foot {
            display: none;
          }
          .ring {
            width: 44px;
            height: 44px;
          }
          .initials {
            font-size: 15px;
          }
        }
      </style>
    </template>
  };

  static isolated = class Isolated extends Component<typeof Guest> {
    get initials() {
      return initialsOf(this.args.model?.fullName);
    }
    <template>
      <article class='iso'>

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
            <h1 class='iso-name'>{{if
                @model.fullName
                @model.fullName
                'Unnamed Guest'
              }}</h1>
            <div class='iso-tags'>
              {{#if @model.category}}
                <span class='iso-pill'>
                  <span
                    class='iso-dot'
                    style={{swatch (categoryColor @model.category)}}
                  ></span>
                  {{categoryLabel @model.category}}
                </span>
              {{/if}}
              {{#if @model.vip}}
                <span class='iso-pill is-vip'>&#10022; VIP</span>
              {{/if}}
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
        .iso {
          --ink: #22283f;
          --gold: #a5854a;
          --paper: #f7f1e4;
          --muted: #8a7f6c;
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
            var(--paper);
          color: var(--ink);
          font-family: 'Jost', system-ui, sans-serif;
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
          font-family: 'Jost', sans-serif;
          font-size: 10px;
          letter-spacing: 0.34em;
          text-transform: uppercase;
          color: var(--gold);
        }
        .iso-colophon {
          margin-top: 34px;
        }
        .iso-colophon-mark {
          flex: none;
          font-size: 12px;
          color: var(--gold);
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
          background: conic-gradient(from 140deg, #dcc188, #8a6f3e, #dcc188);
        }
        .iso-photo {
          width: 100%;
          height: 100%;
          border-radius: 50%;
          object-fit: cover;
          display: block;
          background: var(--paper);
        }
        .iso-initials {
          display: flex;
          align-items: center;
          justify-content: center;
          font:
            600 30px 'Cormorant Garamond',
            Georgia,
            serif;
          color: #22283f;
          background: linear-gradient(135deg, #f0dca4, #c5a35c);
        }
        .iso-star {
          position: absolute;
          right: 0;
          bottom: 2px;
          width: 26px;
          height: 26px;
          border-radius: 50%;
          background: var(--gold);
          color: #fffdf8;
          font-size: 13px;
          display: flex;
          align-items: center;
          justify-content: center;
          border: 2px solid var(--paper);
        }
        .iso-ident {
          min-width: 0;
          display: flex;
          flex-direction: column;
          gap: 8px;
        }
        .iso-kicker {
          font-family: 'Jost', sans-serif;
          font-size: 9.5px;
          letter-spacing: 0.3em;
          text-transform: uppercase;
          color: var(--gold);
        }
        .iso-name {
          margin: 0;
          font-family: 'Cormorant Garamond', Georgia, serif;
          font-size: clamp(26px, 5.5cqw, 38px);
          font-weight: 500;
          line-height: 1.12;
          overflow-wrap: anywhere;
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
          font-family: 'Jost', sans-serif;
          font-size: 9.5px;
          letter-spacing: 0.14em;
          text-transform: uppercase;
          color: var(--ink);
          background: #fffdf8;
        }
        .iso-pill.is-vip {
          background: var(--gold);
          border-color: var(--gold);
          color: #fffdf8;
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
          font-family: 'Cormorant Garamond', Georgia, serif;
          font-style: italic;
          font-size: 15px;
          color: var(--gold);
        }
        .iso-sect-title {
          flex: none;
          font-family: 'Jost', sans-serif;
          font-size: 10px;
          letter-spacing: 0.3em;
          text-transform: uppercase;
          color: var(--ink);
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
          font-family: 'Jost', sans-serif;
          font-size: 9px;
          letter-spacing: 0.24em;
          text-transform: uppercase;
          color: var(--muted);
        }
        .iso-party-card {
          max-width: 460px;
        }
        .iso-empty-line {
          margin: 0;
          font-family: 'Cormorant Garamond', Georgia, serif;
          font-style: italic;
          font-size: 13.5px;
          color: var(--muted);
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
