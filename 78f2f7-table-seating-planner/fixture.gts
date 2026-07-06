import {
  FieldDef,
  Component,
  field,
  contains,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';
import BooleanField from 'https://cardstack.com/base/boolean';
import ColorField from 'https://cardstack.com/base/color';
import enumField from 'https://cardstack.com/base/enum';
import { get } from '@ember/helper';
import FlowerIcon from '@cardstack/boxel-icons/flower';

import FixtureGlyph from './components/fixture-glyph';
import {
  FIXTURE_KINDS,
  FIXTURE_PATTERNS,
  FIXTURE_KIND_LABELS,
} from './utils/index';

const KindField = enumField(StringField, { options: FIXTURE_KINDS });
const PatternField = enumField(StringField, { options: FIXTURE_PATTERNS });

export class Fixture extends FieldDef {
  static displayName = 'Fixture';
  static icon = FlowerIcon;

  @field label = contains(StringField);
  @field kind = contains(KindField);
  @field pattern = contains(PatternField);

  @field x = contains(NumberField);
  @field y = contains(NumberField);
  @field width = contains(NumberField);
  @field height = contains(NumberField);
  @field rotation = contains(NumberField);
  @field z = contains(NumberField); // canvas stacking order
  @field locked = contains(BooleanField); // locked fixtures can't be moved/resized on canvas

  @field color = contains(ColorField);

  @field title = contains(StringField, {
    computeVia: function (this: Fixture) {
      return (
        this.label?.trim() || FIXTURE_KIND_LABELS[this.kind ?? ''] || 'Fixture'
      );
    },
  });

  static embedded = class Embedded extends Component<typeof Fixture> {
    <template>
      <div class='fx-row'>
        <span class='fx-thumb'>
          <FixtureGlyph
            @kind={{@model.kind}}
            @color={{@model.color}}
            @pattern={{@model.pattern}}
          />
        </span>
        <span class='fx-body'>
          <span class='fx-label'>{{@model.title}}</span>
          <span class='fx-kind'>{{get
              FIXTURE_KIND_LABELS
              (if @model.kind @model.kind '')
            }}</span>
        </span>
      </div>
      <style scoped>
        .fx-row {
          display: flex;
          align-items: center;
          gap: 12px;
          padding: 10px 12px;
          border: 1px solid var(--border, rgba(0, 0, 0, 0.1));
          border-radius: 11px;
          background: var(--background, #fff);
          color: var(--foreground, #22283f);
          font-family: 'Jost', system-ui, sans-serif;
        }
        .fx-thumb {
          width: 40px;
          height: 40px;
          flex: none;
        }
        .fx-body {
          display: flex;
          flex-direction: column;
          gap: 3px;
          min-width: 0;
        }
        .fx-label {
          font-size: 14px;
        }
        .fx-kind {
          font:
            11px 'Jost',
            monospace;
          color: var(--muted-foreground, #a5919c);
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof Fixture> {
    <template>
      <div class='cq'>
        <div class='fit'>
          <div class='r-thumb'>
            <FixtureGlyph
              @kind={{@model.kind}}
              @color={{@model.color}}
              @pattern={{@model.pattern}}
            />
          </div>
          <div class='r-head'><span class='label'>{{@model.title}}</span></div>
          <div class='r-meta'><span class='kind'>{{get
                FIXTURE_KIND_LABELS
                (if @model.kind @model.kind '')
              }}</span></div>
        </div>
      </div>
      <style scoped>
        .cq {
          container-type: size;
          container-name: fx;
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
          grid-template-areas: 'thumb head' 'thumb meta';
          background: var(--background, #fff);
          color: var(--foreground, #22283f);
          font-family: 'Jost', system-ui, sans-serif;
        }
        .r-thumb {
          grid-area: thumb;
          width: 44px;
          height: 44px;
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
        }
        .label {
          font-weight: 600;
          font-size: 14px;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .kind {
          font:
            11px 'Jost',
            monospace;
          color: var(--muted-foreground, #a5919c);
        }
        @container fx (width <= 90px) {
          .fit {
            grid-template-columns: 1fr;
            grid-template-areas: 'thumb';
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

  static isolated = class Isolated extends Component<typeof Fixture> {
    <template>
      <article class='fx-iso'>
        <div class='fx-iso-art'>
          <FixtureGlyph
            @kind={{@model.kind}}
            @color={{@model.color}}
            @pattern={{@model.pattern}}
          />
        </div>
        <h1>{{@model.title}}</h1>
        <p class='fx-iso-kind'>{{get
            FIXTURE_KIND_LABELS
            (if @model.kind @model.kind '')
          }}</p>
      </article>
      <style scoped>
        .fx-iso {
          height: 100%;
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          gap: 14px;
          padding: 28px;
          box-sizing: border-box;
          background: var(--background, #faf5ec);
          color: var(--foreground, #22283f);
          font-family: 'Jost', system-ui, sans-serif;
        }
        .fx-iso-art {
          width: 160px;
          height: 160px;
        }
        h1 {
          margin: 0;
          font-family: 'Cormorant Garamond', Georgia, serif;
          font-size: 26px;
        }
        .fx-iso-kind {
          margin: 0;
          font:
            10px 'Jost',
            monospace;
          letter-spacing: 0.2em;
          text-transform: uppercase;
          color: var(--muted-foreground, #a5919c);
        }
      </style>
    </template>
  };
}
