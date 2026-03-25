import { CardDef, field, contains, containsMany } from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import DateField from 'https://cardstack.com/base/date';
import TextAreaField from 'https://cardstack.com/base/text-area';
import { Component } from 'https://cardstack.com/base/card-api';

export class Invitation extends CardDef {
  static displayName = "Invitation";

  @field eventName = contains(StringField);
  @field eventDate = contains(DateField);
  @field location = contains(StringField);
  @field hostName = contains(StringField);
  @field guestName = contains(StringField);
  @field message = contains(TextAreaField);
  @field rsvpDeadline = contains(DateField);

  static isolated = class Isolated extends Component<typeof this> {
    <template>
      <div class="invitation">
        <h2>{{@model.eventName}}</h2>
        <p><strong>Host:</strong> {{@model.hostName}}</p>
        <p><strong>Guest:</strong> {{@model.guestName}}</p>
        <p><strong>Date:</strong> {{@model.eventDate}}</p>
        <p><strong>Location:</strong> {{@model.location}}</p>
        <p><strong>Message:</strong> {{@model.message}}</p>
        <p><strong>RSVP By:</strong> {{@model.rsvpDeadline}}</p>
      </div>
    </template>
  };
}