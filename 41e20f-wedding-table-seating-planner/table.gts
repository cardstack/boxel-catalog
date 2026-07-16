import {
  FieldDef,
  Component,
  field,
  contains,
  containsMany,
  linksToMany,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import TextAreaField from 'https://cardstack.com/base/text-area';
import NumberField from 'https://cardstack.com/base/number';
import BooleanField from 'https://cardstack.com/base/boolean';
import ColorField from 'https://cardstack.com/base/color';
import enumField from 'https://cardstack.com/base/enum';
import { get } from '@ember/helper';
import CircleIcon from '@cardstack/boxel-icons/circle-dashed';

import { Guest, CategoryField } from './guest';
import { htmlSafe } from '@ember/template';
import {
  TABLE_SHAPES,
  SEATING_STYLES,
  SEAT_ORDERS,
  TABLE_SHAPE_LABELS,
  SEATING_STYLE_LABELS,
  shortTableLabel,
  categoryLabel,
  categoryColor,
} from './utils/index';

function catSwatch(value: string | null | undefined) {
  return htmlSafe(`background:${categoryColor(value)}`);
}

const ShapeField = enumField(StringField, { options: TABLE_SHAPES });
const SeatingStyleField = enumField(StringField, { options: SEATING_STYLES });
const SeatOrderField = enumField(StringField, { options: SEAT_ORDERS });

export class Table extends FieldDef {
  static displayName = 'Table';
  static icon = CircleIcon;

  @field name = contains(StringField);
  @field shape = contains(ShapeField);
  @field seatCount = contains(NumberField);
  @field seatingStyle = contains(SeatingStyleField);
  @field rows = contains(NumberField);
  @field cols = contains(NumberField);
  @field seatOrder = contains(SeatOrderField);

  @field x = contains(NumberField);
  @field y = contains(NumberField);
  @field width = contains(NumberField);
  @field height = contains(NumberField);
  @field rotation = contains(NumberField);
  @field z = contains(NumberField); // canvas stacking order

  @field themeColor = contains(ColorField);
  @field reservedCategories = containsMany(CategoryField);
  @field seatedGuests = linksToMany(() => Guest); // packed list of seated guests
  @field seatSlots = containsMany(NumberField);
  @field vip = contains(BooleanField);
  @field rank = contains(NumberField);
  @field locked = contains(BooleanField);
  @field note = contains(TextAreaField);

  @field seatedCount = contains(NumberField, {
    computeVia: function (this: Table) {
      return this.seatedGuests?.length ?? 0;
    },
  });

  @field title = contains(StringField, {
    computeVia: function (this: Table) {
      return this.name?.trim() || 'Untitled Table';
    },
  });

  static embedded = class Embedded extends Component<typeof Table> {
    get short() {
      return shortTableLabel(this.args.model?.name);
    }
    <template>
      <div class='t-row'>
        <span class='t-glyph t-{{if @model.shape @model.shape "round"}}'>
          {{this.short}}
        </span>
        <span class='t-body'>
          <span class='t-name'>{{if @model.name @model.name 'Untitled Table'}}
            {{#if @model.vip}}<span class='t-vip'>VIP</span>{{/if}}</span>
          <span class='t-meta'>
            {{if @model.seatCount @model.seatCount 0}}
            seats ·
            {{get
              SEATING_STYLE_LABELS
              (if @model.seatingStyle @model.seatingStyle '')
            }}
          </span>
        </span>
        <span class='t-cap'>{{if @model.seatedCount @model.seatedCount 0}}/{{if
            @model.seatCount
            @model.seatCount
            0
          }}</span>
      </div>
      <style scoped>
        .t-row {
          display: flex;
          align-items: center;
          gap: 12px;
          padding: 10px 12px;
          border: 1px solid var(--border, rgba(0, 0, 0, 0.1));
          border-radius: 11px;
          background: var(--background, #fff);
          color: var(--foreground, #22283f);
          font-family: var(--font-sans, 'Jost', system-ui, sans-serif);
        }
        .t-glyph {
          width: 40px;
          height: 40px;
          flex: none;
          display: flex;
          align-items: center;
          justify-content: center;
          font:
            600 14px 'Cormorant Garamond',
            serif;
          color: var(--ink, #22283f);
          background: linear-gradient(135deg, #dcc188, var(--gold, #c5a35c));
          border-radius: 50%;
        }
        .t-rect,
        .t-square {
          border-radius: 8px;
        }
        .t-oval {
          border-radius: 50% / 40%;
        }
        .t-body {
          flex: 1;
          min-width: 0;
          display: flex;
          flex-direction: column;
          gap: 3px;
        }
        .t-name {
          font-size: 14px;
          display: flex;
          align-items: center;
          gap: 7px;
        }
        .t-vip {
          font:
            600 8px 'Jost',
            monospace;
          letter-spacing: 0.12em;
          color: var(--ink, #22283f);
          background: var(--gold, #c5a35c);
          border-radius: 4px;
          padding: 2px 5px;
        }
        .t-meta {
          font:
            11px 'Jost',
            monospace;
          color: var(--muted-foreground, #a5919c);
        }
        .t-cap {
          flex: none;
          font:
            12px 'Jost',
            monospace;
          color: var(--muted-foreground, #a5919c);
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof Table> {
    get short() {
      return shortTableLabel(this.args.model?.name);
    }
    <template>
      <div class='cq'>
        <div class='fit'>
          <div class='r-glyph'>
            <span
              class='glyph t-{{if @model.shape @model.shape "round"}}'
            >{{this.short}}</span>
          </div>
          <div class='r-head'>
            <span class='name'>{{if
                @model.name
                @model.name
                'Untitled Table'
              }}</span>
          </div>
          <div class='r-meta'>
            <span class='cap'>{{if
                @model.seatedCount
                @model.seatedCount
                0
              }}/{{if @model.seatCount @model.seatCount 0}}</span>
            {{#if @model.vip}}<span class='vip'>VIP</span>{{/if}}
          </div>
        </div>
      </div>
      <style scoped>
        .cq {
          container-type: size;
          container-name: tbl;
          width: 100%;
          height: 100%;
          overflow: hidden;
        }
        .fit {
          width: 100%;
          height: 100%;
          display: grid;
          gap: 4px 10px;
          padding: 10px 12px;
          box-sizing: border-box;
          overflow: hidden;
          align-content: center;
          grid-template-columns: auto minmax(0, 1fr);
          grid-template-areas: 'glyph head' 'glyph meta';
          background: var(--background, #fff);
          color: var(--foreground, #22283f);
          font-family: var(--font-sans, 'Jost', system-ui, sans-serif);
        }
        .r-glyph {
          grid-area: glyph;
          overflow: hidden;
          min-height: 0;
          align-self: center;
        }
        .r-head {
          grid-area: head;
          overflow: hidden;
          min-height: 0;
        }
        .r-meta {
          grid-area: meta;
          overflow: hidden;
          min-height: 0;
          display: flex;
          align-items: center;
          gap: 7px;
        }
        .glyph {
          width: 42px;
          height: 42px;
          display: flex;
          align-items: center;
          justify-content: center;
          font:
            600 15px 'Cormorant Garamond',
            serif;
          color: var(--ink, #22283f);
          background: linear-gradient(135deg, #dcc188, var(--gold, #c5a35c));
          border-radius: 50%;
        }
        .t-rect,
        .t-square {
          border-radius: 9px;
        }
        .t-oval {
          border-radius: 50% / 40%;
        }
        .name {
          font-weight: 600;
          font-size: 14px;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .cap {
          font:
            12px 'Jost',
            monospace;
          color: var(--muted-foreground, #a5919c);
        }
        .vip {
          font:
            600 8px 'Jost',
            monospace;
          letter-spacing: 0.12em;
          color: var(--ink, #22283f);
          background: var(--gold, #c5a35c);
          border-radius: 4px;
          padding: 2px 5px;
        }
        @container tbl (width <= 90px) {
          .fit {
            grid-template-columns: 1fr;
            grid-template-areas: 'glyph';
            justify-items: center;
          }
          .r-head,
          .r-meta {
            display: none;
          }
        }
      </style>
    </template>
  };

  static isolated = class Isolated extends Component<typeof Table> {
    <template>
      <article class='t-iso'>
        <h1>{{if @model.name @model.name 'Untitled Table'}}
          {{#if @model.vip}}<span class='pill'>VIP</span>{{/if}}</h1>
        <dl class='facts'>
          <div><dt>Shape</dt><dd>{{get
                TABLE_SHAPE_LABELS
                (if @model.shape @model.shape '')
              }}</dd></div>
          <div><dt>Seating</dt><dd>{{get
                SEATING_STYLE_LABELS
                (if @model.seatingStyle @model.seatingStyle '')
              }}</dd></div>
          <div><dt>Capacity</dt><dd>{{if
                @model.seatedCount
                @model.seatedCount
                0
              }}
              of
              {{if @model.seatCount @model.seatCount 0}}</dd></div>
        </dl>
        {{#if @model.reservedCategories.length}}
          <section>
            <h2>Reserved for</h2>
            <div class='res-cats'>
              {{#each @model.reservedCategories as |c|}}
                <span class='res-cat'>
                  <span class='res-dot' style={{catSwatch c}}></span>
                  {{categoryLabel c}}
                </span>
              {{/each}}
            </div>
          </section>
        {{/if}}
        {{#if @model.seatedGuests.length}}
          <section>
            <h2>Assigned</h2>
            <@fields.seatedGuests @format='embedded' />
          </section>
        {{/if}}
        {{#if @model.note}}
          <section><h2>Notes</h2><p class='note'>{{@model.note}}</p></section>
        {{/if}}
      </article>
      <style scoped>
        .t-iso {
          height: 100%;
          overflow-y: auto;
          padding: 28px;
          box-sizing: border-box;
          background: var(--background, #faf5ec);
          color: var(--foreground, #22283f);
          font-family: var(--font-sans, 'Jost', system-ui, sans-serif);
        }
        h1 {
          margin: 0;
          font-family: var(--font-serif, 'Cormorant Garamond', Georgia, serif);
          font-size: 28px;
          display: flex;
          align-items: center;
          gap: 10px;
        }
        .pill {
          font:
            600 9px 'Jost',
            monospace;
          letter-spacing: 0.14em;
          color: var(--ink, #22283f);
          background: var(--gold, #c5a35c);
          border-radius: 5px;
          padding: 3px 7px;
        }
        .facts {
          margin: 22px 0 0;
          display: grid;
          grid-template-columns: repeat(3, 1fr);
          gap: 14px;
        }
        dt {
          font:
            10px 'Jost',
            monospace;
          letter-spacing: 0.2em;
          text-transform: uppercase;
          color: var(--muted-foreground, #a5919c);
        }
        dd {
          margin: 4px 0 0;
          font-size: 16px;
        }
        section {
          margin-top: 24px;
        }
        h2 {
          font:
            10px 'Jost',
            monospace;
          letter-spacing: 0.2em;
          text-transform: uppercase;
          color: var(--muted-foreground, #a5919c);
          margin: 0 0 10px;
        }
        .note {
          margin: 0;
          font-size: 14px;
          line-height: 1.6;
        }
        .res-cats {
          display: flex;
          flex-wrap: wrap;
          gap: 8px;
        }
        .res-cat {
          display: inline-flex;
          align-items: center;
          gap: 7px;
          padding: 4px 11px 4px 8px;
          border-radius: 999px;
          border: 1px solid rgba(220, 193, 136, 0.35);
          font-size: 12.5px;
        }
        .res-dot {
          width: 10px;
          height: 10px;
          border-radius: 3px;
          flex: none;
        }
      </style>
    </template>
  };
}
