import { gt } from '@cardstack/boxel-ui/helpers';
/* 
  Risk: Continent definition
  - CardDef because continents are referenced by territories and game state.
*/
// ═══ [EDIT TRACKING: ON] Mark all changes with ⁿ ═══
import {
  CardDef,
  FieldDef,
  Component,
  field,
  contains,
  containsMany,
  linksToMany,
} from 'https://cardstack.com/base/card-api'; // ¹ Core
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';
import MapPinIcon from '@cardstack/boxel-icons/map-pin'; // ² icon
import { Territory } from './territory'; // ³ bring symbol into scope for thunk

export class Continent extends CardDef {
  // ³ Card definition
  static displayName = 'Continent';
  static icon = MapPinIcon;

  @field name = contains(StringField); // ⁴ Name
  @field bonusArmies = contains(NumberField); // ⁵ Bonus per Risk rules
  @field territories = linksToMany(() => Territory); // ⁶ Territories in this continent (set by game/map)

  // ⁷ Compute inherited title
  @field cardTitle = contains(StringField, {
    computeVia: function (this: Continent) {
      try {
        const n = this.name ?? 'Unnamed Continent';
        const b = this.bonusArmies != null ? ` (+${this.bonusArmies})` : '';
        return `${n}${b}`;
      } catch {
        return 'Continent';
      }
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='continent'>
        <h4 class='name'>{{if @model.name @model.name 'Unnamed Continent'}}</h4>
        <div class='bonus'>Bonus:
          {{if @model.bonusArmies @model.bonusArmies 0}}</div>
        {{#if (gt @model.territories.length 0)}}
          <div class='territories'>
            <@fields.territories @format='atom' />
          </div>
        {{/if}}
      </div>
      <style scoped>
        .continent {
          font-size: 0.8125rem;
        }
        .name {
          font-weight: 600;
          margin-bottom: 0.25rem;
        }
        .bonus {
          color: rgba(0, 0, 0, 0.7);
          font-size: 0.75rem;
        }
        .territories > .containsMany-field {
          display: flex;
          flex-wrap: wrap;
          gap: 0.25rem;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <div class='fitted-container'>
        <div class='badge-format'>
          <div class='primary-text'>{{if
              @model.name
              @model.name
              'Continent'
            }}</div>
          <div class='tertiary-text'>+{{if
              @model.bonusArmies
              @model.bonusArmies
              0
            }}
            armies</div>
        </div>
      </div>
      <style scoped>
        .fitted-container {
          width: 100%;
          height: 100%;
          container-type: size;
        }
        .badge-format {
          display: none;
          padding: clamp(0.1875rem, 2%, 0.5rem);
        }
        @container (max-width: 399px) and (max-height: 169px) {
          .badge-format {
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
          font-weight: 400;
          opacity: 0.8;
        }
      </style>
    </template>
  };

  // Additional formats or components
}
