import {
  FieldDef,
  Component,
  field,
  contains,
  containsMany,
  linksToMany,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import TextAreaField from '@cardstack/base/text-area';
import NumberField from '@cardstack/base/number';
import BooleanField from '@cardstack/base/boolean';
import ColorField from '@cardstack/base/color';
import enumField from '@cardstack/base/enum';
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
          gap: 0.75rem;
          padding: 0.625rem 0.75rem;
          border: 1px solid var(--border);
          border-radius: 0.6875rem;
        }
        .t-glyph {
          width: 2.5rem;
          height: 2.5rem;
          flex: none;
          display: flex;
          align-items: center;
          justify-content: center;
          font: 600 0.875rem var(--font-serif);
          color: var(--accent-foreground);
          background: linear-gradient(135deg, var(--accent), var(--accent));
          border-radius: 50%;
        }
        .t-rect,
        .t-square {
          border-radius: 0.5rem;
        }
        .t-oval {
          border-radius: 50% / 40%;
        }
        .t-body {
          flex: 1;
          min-width: 0;
          display: flex;
          flex-direction: column;
          gap: 0.1875rem;
        }
        .t-name {
          font-size: 0.875rem;
          display: flex;
          align-items: center;
          gap: 0.4375rem;
        }
        .t-vip {
          font: 600 0.5rem var(--font-sans);
          letter-spacing: 0.12em;
          color: var(--accent-foreground);
          background-color: var(--accent);
          border-radius: 0.25rem;
          padding: 2px 0.3125rem;
        }
        .t-meta {
          font: 0.6875rem var(--font-sans);
          color: var(--muted-foreground);
        }
        .t-cap {
          flex: none;
          font: 0.75rem var(--font-sans);
          color: var(--muted-foreground);
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
          gap: 0.25rem 0.625rem;
          padding: 0.625rem 0.75rem;
          box-sizing: border-box;
          overflow: hidden;
          align-content: center;
          grid-template-columns: auto minmax(0, 1fr);
          grid-template-areas: 'glyph head' 'glyph meta';
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
          gap: 0.4375rem;
        }
        .glyph {
          width: 2.625rem;
          height: 2.625rem;
          display: flex;
          align-items: center;
          justify-content: center;
          font: 600 0.9375rem var(--font-serif);
          color: var(--accent-foreground);
          background: linear-gradient(135deg, var(--accent), var(--accent));
          border-radius: 50%;
        }
        .t-rect,
        .t-square {
          border-radius: 0.5625rem;
        }
        .t-oval {
          border-radius: 50% / 40%;
        }
        .name {
          font-weight: 600;
          font-size: 0.875rem;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .cap {
          font: 0.75rem var(--font-sans);
          color: var(--muted-foreground);
        }
        .vip {
          font: 600 0.5rem var(--font-sans);
          letter-spacing: 0.12em;
          color: var(--accent-foreground);
          background-color: var(--accent);
          border-radius: 0.25rem;
          padding: 2px 0.3125rem;
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
          padding: 1.75rem;
          box-sizing: border-box;
        }
        h1 {
          margin: 0;
          font-family: var(--font-serif);
          font-size: 1.75rem;
          display: flex;
          align-items: center;
          gap: 0.625rem;
        }
        .pill {
          font: 600 0.5625rem var(--font-sans);
          letter-spacing: 0.14em;
          color: var(--accent-foreground);
          background-color: var(--accent);
          border-radius: 0.3125rem;
          padding: 0.1875rem 0.4375rem;
        }
        .facts {
          margin: 1.375rem 0 0;
          display: grid;
          grid-template-columns: repeat(3, 1fr);
          gap: 0.875rem;
        }
        dt {
          font: 0.625rem var(--font-sans);
          letter-spacing: 0.2em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        dd {
          margin: 0.25rem 0 0;
          font-size: 1rem;
        }
        section {
          margin-top: 1.5rem;
        }
        h2 {
          font: 0.625rem var(--font-sans);
          letter-spacing: 0.2em;
          text-transform: uppercase;
          color: var(--muted-foreground);
          margin: 0 0 0.625rem;
        }
        .note {
          margin: 0;
          font-size: 0.875rem;
          line-height: 1.6;
        }
        .res-cats {
          display: flex;
          flex-wrap: wrap;
          gap: 0.5rem;
        }
        .res-cat {
          display: inline-flex;
          align-items: center;
          gap: 0.4375rem;
          padding: 0.25rem 0.6875rem 0.25rem 0.5rem;
          border-radius: 62.4375rem;
          border: 1px solid color-mix(in oklch, var(--accent) 35%, transparent);
          font-size: 0.7812rem;
        }
        .res-dot {
          width: 0.625rem;
          height: 0.625rem;
          border-radius: 0.1875rem;
          flex: none;
        }
      </style>
    </template>
  };
}
