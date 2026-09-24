import { FieldDef, Component, field, contains } from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import BooleanField from '@cardstack/base/boolean';
import ColorField from '@cardstack/base/color';
import enumField from '@cardstack/base/enum';
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
          gap: 0.75rem;
          padding: 0.625rem 0.75rem;
          border: 1px solid var(--border);
          border-radius: 0.6875rem;
        }
        .fx-thumb {
          width: 2.5rem;
          height: 2.5rem;
          flex: none;
        }
        .fx-body {
          display: flex;
          flex-direction: column;
          gap: 0.1875rem;
          min-width: 0;
        }
        .fx-label {
          font-size: 0.875rem;
        }
        .fx-kind {
          font: 0.6875rem var(--font-sans);
          color: var(--muted-foreground);
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
          gap: 0.25rem 0.625rem;
          padding: 0.625rem 0.75rem;
          box-sizing: border-box;
          overflow: hidden;
          align-content: center;
          grid-template-columns: auto minmax(0, 1fr);
          grid-template-areas: 'thumb head' 'thumb meta';
        }
        .r-thumb {
          grid-area: thumb;
          width: 2.75rem;
          height: 2.75rem;
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
          font-size: 0.875rem;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .kind {
          font: 0.6875rem var(--font-sans);
          color: var(--muted-foreground);
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
          gap: 0.875rem;
          padding: 1.75rem;
          box-sizing: border-box;
        }
        .fx-iso-art {
          width: 10rem;
          height: 10rem;
        }
        h1 {
          margin: 0;
          font-family: var(--font-serif);
          font-size: 1.625rem;
        }
        .fx-iso-kind {
          margin: 0;
          font: 0.625rem var(--font-sans);
          letter-spacing: 0.2em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };
}
