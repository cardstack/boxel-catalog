import { Component } from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import { DatePicker } from '@cardstack/pretui/components/date-picker';
import { Input } from '@cardstack/pretui/components/input';
import { day } from './record-kit';

// Dates and months the books store as ISO text (yyyy-mm-dd, yyyy-mm), so operations compare them as
// strings and code slices them. These keep that stored form and add a picker and a readable display.

const MONTH = new Intl.DateTimeFormat('en-US', {
  month: 'short',
  year: 'numeric',
  timeZone: 'UTC',
});
const ISO_MONTH = /^\d{4}-\d{2}$/;
export const monthLabel = (value: unknown) =>
  typeof value === 'string' && ISO_MONTH.test(value)
    ? MONTH.format(new Date(`${value}-01T00:00:00Z`))
    : String(value ?? '');

export class IsoDateField extends StringField {
  static displayName = 'Date';
  static edit = class Edit extends Component<typeof this> {
    get value() {
      return this.args.model ?? undefined;
    }
    <template>
      <DatePicker
        @value={{this.value}}
        @onValueChange={{@set}}
        aria-label='Date, yyyy-mm-dd'
      />
    </template>
  };
  static atom = class Atom extends Component<typeof this> {
    <template>{{day @model}}</template>
  };
  static embedded = class Embedded extends Component<typeof this> {
    <template>{{day @model}}</template>
  };
}

export class IsoMonthField extends StringField {
  static displayName = 'Month';
  static edit = class Edit extends Component<typeof this> {
    get value() {
      return this.args.model ?? undefined;
    }
    <template>
      <Input
        @type='month'
        @value={{this.value}}
        @onInput={{@set}}
        aria-label='Month, yyyy-mm'
      />
    </template>
  };
  static atom = class Atom extends Component<typeof this> {
    <template>{{monthLabel @model}}</template>
  };
  static embedded = class Embedded extends Component<typeof this> {
    <template>{{monthLabel @model}}</template>
  };
}
