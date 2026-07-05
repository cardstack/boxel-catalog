// FIXTURE — intentionally violates conformance gates for selftest.mjs.
// Seeded bugs: bare kit-internal linksTo (S09), slop gradient (S14),
// no @container in fitted (S08 warn).
import {
  CardDef,
  field,
  contains,
  linksTo,
  Component,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import DateField from 'https://cardstack.com/base/date';
import { Venue } from './venue';

export class Event extends CardDef {
  static displayName = 'Event';
  @field title = contains(StringField);
  @field startDate = contains(DateField);
  @field venue = linksTo(Venue);

  static isolated = class extends Component<typeof Event> {
    <template>
      <div class='hero'><h1>{{@model.title}}</h1></div>
      <style scoped>
        .hero {
          background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        }
      </style>
    </template>
  };

  static embedded = class extends Component<typeof Event> {
    <template>
      <span>{{@model.title}}</span>
    </template>
  };

  static fitted = class extends Component<typeof Event> {
    <template>
      <div class='tile'>{{@model.title}}</div>
      <style scoped>
        .tile {
          padding: 4px;
        }
      </style>
    </template>
  };
}
