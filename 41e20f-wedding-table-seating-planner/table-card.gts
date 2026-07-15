import {
  CardDef,
  Component,
  field,
  contains,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';

// A printable wedding table card / sign: a large table name or number with the
// event title, styled to match the planner's burgundy/gold theme.
export class TableCard extends CardDef {
  static displayName = 'Table Card';

  @field tableName = contains(StringField);
  @field eventTitle = contains(StringField);
  @field accent = contains(StringField);

  @field title = contains(StringField, {
    computeVia: function (this: TableCard) {
      return this.tableName?.trim() || 'Table Card';
    },
  });

  static isolated = class Isolated extends Component<typeof TableCard> {
    <template>
      <section class='tc-stage'>
        <article class='table-card'>
          {{#if @model.eventTitle}}
            <span class='tc-event'>{{@model.eventTitle}}</span>
          {{/if}}
          <span class='tc-name'>{{if
              @model.tableName
              @model.tableName
              'Table'
            }}</span>
          {{#if @model.accent}}
            <span class='tc-accent'>{{@model.accent}}</span>
          {{/if}}
        </article>
      </section>
      <style scoped>
        .tc-stage {
          --tc-paper: #fbf6ec;
          --tc-ink: #5a1a1a;
          --tc-gold: #a5854a;
          --tc-serif: 'Cormorant Garamond', Georgia, serif;
          --tc-sans: 'Jost', system-ui, sans-serif;
          display: grid;
          place-items: center;
          min-height: 100%;
          padding: 24px;
          background: #efe6d4;
        }
        .table-card {
          display: flex;
          flex-direction: column;
          align-items: center;
          gap: 12px;
          width: min(520px, 100%);
          padding: 44px 40px;
          background: var(--tc-paper);
          color: var(--tc-ink);
          border: 2px solid var(--tc-gold);
          border-radius: 8px;
          box-shadow: 0 10px 34px rgba(90, 26, 26, 0.16);
          text-align: center;
        }
        .tc-event {
          font-family: var(--tc-sans);
          font-size: 12px;
          letter-spacing: 0.26em;
          text-transform: uppercase;
          color: var(--tc-gold);
        }
        .tc-name {
          font-family: var(--tc-serif);
          font-size: 72px;
          font-weight: 700;
          line-height: 1;
        }
        .tc-accent {
          font-family: var(--tc-serif);
          font-size: 20px;
          font-style: italic;
          opacity: 0.8;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof TableCard> {
    <template>
      <article class='table-card'>
        {{#if @model.eventTitle}}
          <span class='tc-event'>{{@model.eventTitle}}</span>
        {{/if}}
        <span class='tc-name'>{{if
            @model.tableName
            @model.tableName
            'Table'
          }}</span>
        {{#if @model.accent}}
          <span class='tc-accent'>{{@model.accent}}</span>
        {{/if}}
      </article>
      <style scoped>
        .table-card {
          --tc-paper: #fbf6ec;
          --tc-ink: #5a1a1a;
          --tc-gold: #a5854a;
          --tc-serif: 'Cormorant Garamond', Georgia, serif;
          --tc-sans: 'Jost', system-ui, sans-serif;
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          gap: 6px;
          width: 100%;
          height: 100%;
          padding: 12px;
          background: var(--tc-paper);
          color: var(--tc-ink);
          border: 2px solid var(--tc-gold);
          text-align: center;
          overflow: hidden;
        }
        .tc-event {
          font-family: var(--tc-sans);
          font-size: 8px;
          letter-spacing: 0.2em;
          text-transform: uppercase;
          color: var(--tc-gold);
        }
        .tc-name {
          font-family: var(--tc-serif);
          font-size: clamp(28px, 22cqw, 60px);
          font-weight: 700;
          line-height: 1;
        }
        .tc-accent {
          font-family: var(--tc-serif);
          font-size: clamp(11px, 6cqw, 18px);
          font-style: italic;
          opacity: 0.8;
        }
      </style>
    </template>
  };
}
