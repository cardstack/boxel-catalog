import { or } from '@cardstack/boxel-ui/helpers';
import { concat } from '@ember/helper';
/*
  Risk: Territory definition
*/
// ═══ [EDIT TRACKING: ON] Mark all changes with ⁿ ═══
import {
  CardDef,
  FieldDef,
  Component,
  field,
  contains,
  containsMany,
  linksTo,
  linksToMany,
} from 'https://cardstack.com/base/card-api'; // ¹
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';
import MapIcon from '@cardstack/boxel-icons/map'; // ²
import { Player } from './player';
import { Continent } from './continent';

export class Territory extends CardDef {
  // ³
  static displayName = 'Territory';
  static icon = MapIcon;

  @field name = contains(StringField); // ⁴
  @field shortId = contains(StringField); // ⁵ e.g., "NA-1"
  @field armies = contains(NumberField); // ⁶ stationed armies
  @field owner = linksTo(Player); // ⁷ owner
  @field continent = linksTo(() => Continent); // ⁸ belonging continent (thunk to avoid cycle)
  @field neighbors = linksToMany(() => Territory); // ⁹ adjacency

  // Title
  @field cardTitle = contains(StringField, {
    computeVia: function (this: Territory) {
      try {
        const n = this.name ?? 'Territory';
        const a = this.armies != null ? ` (${this.armies})` : '';
        return `${n}${a}`;
      } catch {
        return 'Territory';
      }
    },
  });

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='atom'>{{if
          @model.shortId
          @model.shortId
          (if @model.name @model.name 'Territory')
        }}</span>
      <style scoped>
        .atom {
          font-size: 0.75rem;
          opacity: 0.9;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='territory'>
        <div class='header'>
          <h4 class='name'>{{if @model.name @model.name 'Territory'}}</h4>
          <span class='armies'>⛬ {{if @model.armies @model.armies 0}}</span>
        </div>
        <div class='meta'>
          <div>Continent:
            {{if @fields.continent @model.continent.name '—'}}</div>
          <div>Owner: {{if @fields.owner @model.owner.name 'Unclaimed'}}</div>
        </div>
      </div>
      <style scoped>
        .territory {
          font-size: 0.8125rem;
        }
        .header {
          display: flex;
          justify-content: space-between;
          align-items: center;
        }
        .name {
          font-weight: 600;
        }
        .armies {
          font-size: 0.75rem;
          opacity: 0.85;
        }
        .meta {
          margin-top: 0.25rem;
          display: flex;
          gap: 0.5rem;
          font-size: 0.75rem;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <div
        class='fitted'
        style={{concat '--owner: ' (or @model.owner.color '#64748b')}}
      >
        <div class='badge'>
          <div class='primary-text'>{{if
              @model.shortId
              @model.shortId
              (if @model.name @model.name 'Territory')
            }}</div>
          <div class='tertiary-text'>⛬
            {{if @model.armies @model.armies 0}}</div>
        </div>
      </div>
      <style scoped>
        .fitted {
          width: 100%;
          height: 100%;
          container-type: size;
        }
        .badge {
          display: none;
          padding: clamp(0.1875rem, 2%, 0.5rem);
          border-left: 3px solid var(--owner, #64748b);
        }
        @container (max-width: 399px) and (max-height: 169px) {
          .badge {
            display: flex;
            flex-direction: column;
            justify-content: space-between;
          }
        }
        .primary-text {
          font-size: 1em;
          font-weight: 600;
        }
        .tertiary-text {
          font-size: 0.75em;
        }
      </style>
    </template>
  };

  // Additional formats or components
}
