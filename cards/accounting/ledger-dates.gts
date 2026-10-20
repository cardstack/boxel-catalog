import { Component } from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import { DatePicker } from '@cardstack/pretui/components/date-picker';
import { Input } from '@cardstack/pretui/components/input';
import { Button } from '@cardstack/pretui/components/button';
import { on } from '@ember/modifier';
import { tracked } from '@glimmer/tracking';
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
    clear = () => this.args.set(null);
    <template>
      <div class='iso-date'>
        <DatePicker
          @value={{this.value}}
          @onValueChange={{@set}}
          aria-label='Date, yyyy-mm-dd'
        />
        {{#if @model}}<Button
            @tone='neutral'
            @appearance='plain'
            @size='s'
            {{on 'click' this.clear}}
          >Clear</Button>{{/if}}
      </div>
      <style scoped>
        .iso-date {
          display: flex;
          gap: var(--boxel-sp-xs);
          align-items: center;
          min-width: 0;
        }
      </style>
    </template>
  };
  static atom = class Atom extends Component<typeof this> {
    <template>{{day @model}}</template>
  };
  static embedded = class Embedded extends Component<typeof this> {
    <template>{{day @model}}</template>
  };
}

// What was typed, kept until it is a whole month: where the browser has no month picker the input is
// plain text, and only yyyy-mm (or nothing) is stored.
class MonthEdit extends Component<typeof IsoMonthField> {
  @tracked typed: string | undefined;
  get value() {
    return this.typed ?? this.args.model ?? undefined;
  }
  get invalid() {
    return !!this.typed && !ISO_MONTH.test(this.typed);
  }
  update = (value: string) => {
    this.typed = value;
    if (!value) this.args.set(null);
    else if (ISO_MONTH.test(value)) this.args.set(value);
  };
  <template>
    <Input
      @type='month'
      @value={{this.value}}
      @onInput={{this.update}}
      @invalid={{this.invalid}}
      placeholder='yyyy-mm'
      aria-label='Month, yyyy-mm'
    />
  </template>
}

export class IsoMonthField extends StringField {
  static displayName = 'Month';
  static edit = MonthEdit;
  static atom = class Atom extends Component<typeof this> {
    <template>{{monthLabel @model}}</template>
  };
  static embedded = class Embedded extends Component<typeof this> {
    <template>{{monthLabel @model}}</template>
  };
}
