import { concat } from '@ember/helper';
/*
  Risk: Player definition
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
} from 'https://cardstack.com/base/card-api'; // ¹
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';
import ColorField from 'https://cardstack.com/base/color';
import UserIcon from '@cardstack/boxel-icons/user'; // ²

export class Player extends CardDef {
  // ³
  static displayName = 'Player';
  static icon = UserIcon;

  @field name = contains(StringField); // ⁴
  @field color = contains(ColorField); // ⁵ hex color
  @field reserves = contains(NumberField); // ⁶ unplaced armies
  @field eliminated = contains(StringField); // ⁷ status text/fallback

  // Title derived from name
  @field cardTitle = contains(StringField, {
    computeVia: function (this: Player) {
      return this.name ?? 'Player';
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='player' style={{concat '--accent: ' @model.color}}>
        <div class='header'>
          <div class='swatch'></div>
          <h4 class='name'>{{if @model.name @model.name 'Player'}}</h4>
        </div>
        <div class='meta'>
          <span>Reserves: {{if @model.reserves @model.reserves 0}}</span>
          {{#if @model.eliminated}}
            <span class='eliminated'>{{@model.eliminated}}</span>
          {{/if}}
        </div>
      </div>
      <style scoped>
        .player {
          --accent: #64748b;
          font-size: 0.8125rem;
        }
        .header {
          display: flex;
          align-items: center;
          gap: 0.5rem;
        }
        .swatch {
          width: 10px;
          height: 10px;
          border-radius: 999px;
          background: var(--accent);
        }
        .name {
          font-weight: 600;
        }
        .meta {
          margin-top: 0.25rem;
          font-size: 0.75rem;
          display: flex;
          gap: 0.5rem;
        }
        .eliminated {
          color: #b91c1c;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <div class='fitted-container' style={{concat '--accent: ' @model.color}}>
        <div class='badge-format'>
          <div class='row'>
            <div class='swatch'></div>
            <div class='primary-text'>{{if
                @model.name
                @model.name
                'Player'
              }}</div>
          </div>
          <div class='tertiary-text'>Reserves:
            {{if @model.reserves @model.reserves 0}}</div>
        </div>
      </div>
      <style scoped>
        .fitted-container {
          width: 100%;
          height: 100%;
          container-type: size;
          --accent: #64748b;
        }
        .badge-format {
          display: none;
          padding: clamp(0.1875rem, 2%, 0.5rem);
        }
        .row {
          display: flex;
          align-items: center;
          gap: 0.375rem;
        }
        .swatch {
          width: 10px;
          height: 10px;
          border-radius: 999px;
          background: var(--accent);
        }
        @container (max-width: 399px) {
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
          opacity: 0.85;
        }
      </style>
    </template>
  };

  // Additional formats or components
}
