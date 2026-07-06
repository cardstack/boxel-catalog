// FIXTURE — minimal linked def for the bare-linksTo seed in event.gts.
import {
  CardDef,
  field,
  contains,
  Component,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';

export class Venue extends CardDef {
  static displayName = 'Venue';
  @field name = contains(StringField);

  static isolated = class extends Component<typeof Venue> {
    <template>
      <h1>{{@model.name}}</h1>
    </template>
  };
  static embedded = class extends Component<typeof Venue> {
    <template>
      <span>{{@model.name}}</span>
    </template>
  };
  static fitted = class extends Component<typeof Venue> {
    <template>
      <div class='v'>{{@model.name}}</div>
      <style scoped>
        @container card (height <= 80px) {
          .v {
            font-size: 11px;
          }
        }
      </style>
    </template>
  };
}
