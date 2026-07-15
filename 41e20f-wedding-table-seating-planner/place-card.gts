import {
  CardDef,
  Component,
  field,
  contains,
  linksTo,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';

import { Guest } from './guest';

// A printable wedding place card: the guest's name, their table, and the
// event title, styled to match the planner's burgundy/gold theme. The fitted
// format is sized for print (standard tented place-card proportions).
export class PlaceCard extends CardDef {
  static displayName = 'Place Card';

  @field guest = linksTo(() => Guest);
  @field tableName = contains(StringField);
  @field eventTitle = contains(StringField);
  @field message = contains(StringField);

  @field guestName = contains(StringField, {
    computeVia: function (this: PlaceCard) {
      return this.guest?.fullName?.trim() || 'Guest Name';
    },
  });

  @field title = contains(StringField, {
    computeVia: function (this: PlaceCard) {
      return this.guest?.fullName?.trim() || 'Place Card';
    },
  });

  static isolated = class Isolated extends Component<typeof PlaceCard> {
    <template>
      <section class='pc-stage'>
        <article class='place-card'>
          {{#if @model.eventTitle}}
            <span class='pc-event'>{{@model.eventTitle}}</span>
          {{/if}}
          <span class='pc-name'>{{@model.guestName}}</span>
          <span class='pc-rule'></span>
          {{#if @model.tableName}}
            <span class='pc-table'>{{@model.tableName}}</span>
          {{/if}}
          {{#if @model.message}}
            <span class='pc-msg'>{{@model.message}}</span>
          {{/if}}
        </article>
      </section>
      <style scoped>
        .pc-stage {
          --pc-paper: #fbf6ec;
          --pc-ink: #5a1a1a;
          --pc-gold: #a5854a;
          --pc-serif: 'Cormorant Garamond', Georgia, serif;
          --pc-sans: 'Jost', system-ui, sans-serif;
          display: grid;
          place-items: center;
          min-height: 100%;
          padding: 24px;
          background: #efe6d4;
        }
        .place-card {
          display: flex;
          flex-direction: column;
          align-items: center;
          gap: 8px;
          width: min(420px, 100%);
          padding: 36px 32px;
          background: var(--pc-paper);
          color: var(--pc-ink);
          border: 1px solid var(--pc-gold);
          border-radius: 6px;
          box-shadow: 0 8px 30px rgba(90, 26, 26, 0.14);
          text-align: center;
        }
        .pc-event {
          font-family: var(--pc-sans);
          font-size: 11px;
          letter-spacing: 0.24em;
          text-transform: uppercase;
          color: var(--pc-gold);
        }
        .pc-name {
          font-family: var(--pc-serif);
          font-size: 44px;
          font-weight: 600;
          line-height: 1.05;
        }
        .pc-rule {
          width: 40px;
          height: 1px;
          margin: 4px 0;
          background: var(--pc-gold);
        }
        .pc-table {
          font-family: var(--pc-sans);
          font-size: 13px;
          letter-spacing: 0.14em;
          text-transform: uppercase;
          color: var(--pc-gold);
        }
        .pc-msg {
          font-family: var(--pc-serif);
          font-size: 16px;
          font-style: italic;
          opacity: 0.8;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof PlaceCard> {
    <template>
      <article class='place-card'>
        {{#if @model.eventTitle}}
          <span class='pc-event'>{{@model.eventTitle}}</span>
        {{/if}}
        <span class='pc-name'>{{@model.guestName}}</span>
        <span class='pc-rule'></span>
        {{#if @model.tableName}}
          <span class='pc-table'>{{@model.tableName}}</span>
        {{/if}}
      </article>
      <style scoped>
        .place-card {
          --pc-paper: #fbf6ec;
          --pc-ink: #5a1a1a;
          --pc-gold: #a5854a;
          --pc-serif: 'Cormorant Garamond', Georgia, serif;
          --pc-sans: 'Jost', system-ui, sans-serif;
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          gap: 4px;
          width: 100%;
          height: 100%;
          padding: 12px;
          background: var(--pc-paper);
          color: var(--pc-ink);
          border: 1px solid var(--pc-gold);
          text-align: center;
          overflow: hidden;
        }
        .pc-event {
          font-family: var(--pc-sans);
          font-size: 8px;
          letter-spacing: 0.2em;
          text-transform: uppercase;
          color: var(--pc-gold);
        }
        .pc-name {
          font-family: var(--pc-serif);
          font-size: clamp(18px, 9cqw, 34px);
          font-weight: 600;
          line-height: 1.05;
        }
        .pc-rule {
          width: 28px;
          height: 1px;
          background: var(--pc-gold);
        }
        .pc-table {
          font-family: var(--pc-sans);
          font-size: 10px;
          letter-spacing: 0.12em;
          text-transform: uppercase;
          color: var(--pc-gold);
        }
      </style>
    </template>
  };
}
