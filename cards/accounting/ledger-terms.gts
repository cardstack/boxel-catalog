// The lists documents pick from when money is owed or paid: payment terms (when it's due, and any
// discount for paying early) and payment methods (how it was paid).
import { markDefinition } from '@cardstack/base';
import { CardDef, Component, field, contains } from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import enumField from '@cardstack/base/enum';
import BookIcon from '@cardstack/boxel-icons/book-open';
import { Sheet, Part, Facts, Strip, Fit, day, type Fact } from './record-kit';

const addDays = (iso: string, n: number) => {
  let d = new Date(`${iso}T00:00:00Z`);
  if (Number.isNaN(d.getTime())) return '';
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
};

/** When a document is due under these terms, from its date (yyyy-mm-dd). */
export const dueDateFor = (date: string | undefined, term?: PaymentTerm) =>
  date && term ? addDays(date, term.dueDays ?? 0) : '';

/** The last day the early-payment discount applies, or '' when the terms have none. */
export const discountDateFor = (
  date: string | undefined,
  term?: PaymentTerm,
) =>
  date && term?.discountPercent && term.discountDays != null
    ? addDays(date, term.discountDays)
    : '';

/** The facts a document shows when its due date differs from its terms, and the discount deadline. */
export const termsFacts = (
  date: string | undefined,
  due: string | undefined,
  term: PaymentTerm | undefined,
) => {
  if (!term) return [];
  let byTerms = dueDateFor(date, term),
    discount = discountDateFor(date, term);
  return [
    { key: 'Terms', value: term.name ?? '' },
    ...(byTerms && byTerms !== due
      ? [{ key: 'Due by terms', value: day(byTerms) }]
      : []),
    ...(discount
      ? [
          {
            key: `${term.discountPercent}% off if paid by`,
            value: day(discount),
          },
        ]
      : []),
  ];
};

export class PaymentTerm extends CardDef {
  static displayName = 'Payment term';
  static icon = BookIcon;
  @field name = contains(StringField);
  @field dueDays = contains(NumberField); // days after the document date; 0 is due on receipt
  @field discountPercent = contains(NumberField); // for paying early, e.g. 2
  @field discountDays = contains(NumberField); // paid within this many days
  @field summary = contains(StringField, {
    computeVia: function (this: PaymentTerm) {
      let due = this.dueDays
          ? `Due ${this.dueDays} days after the date`
          : 'Due on receipt',
        discount =
          this.discountPercent && this.discountDays != null
            ? `, ${this.discountPercent}% off if paid within ${this.discountDays} days`
            : '';
      return due + discount;
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: PaymentTerm) {
      return this.name ?? 'Payment term';
    },
  });
  static isolated = class extends Component<typeof PaymentTerm> {
    get facts(): Fact[] {
      let m = this.args.model;
      return [
        {
          key: 'Due',
          value: m.dueDays ? `${m.dueDays} days after the date` : 'On receipt',
        },
        {
          key: 'Early payment',
          value:
            m.discountPercent && m.discountDays != null
              ? `${m.discountPercent}% off within ${m.discountDays} days`
              : 'No discount',
        },
      ];
    }
    <template>
      <Sheet
        @eyebrow='Payment term'
        @title={{@model.name}}
        @meta={{@model.summary}}
      ><Part @title='Terms'><Facts @items={{this.facts}} /></Part></Sheet>
    </template>
  };
  static embedded = class extends Component<typeof PaymentTerm> {
    <template>
      <Strip
        @eyebrow='Payment term'
        @title={{@model.name}}
        @meta={{@model.summary}}
      />
    </template>
  };
  static fitted = class extends Component<typeof PaymentTerm> {
    <template>
      <Fit
        @eyebrow='Payment term'
        @title={{@model.name}}
        @meta={{@model.summary}}
      />
    </template>
  };
}

export const PaymentMethodKindField = markDefinition(
  enumField(StringField, {
    displayName: 'Payment method kind',
    options: [
      { value: 'cash', label: 'Cash' },
      { value: 'check', label: 'Check' },
      { value: 'card', label: 'Card' },
      { value: 'ach', label: 'Bank transfer (ACH)' },
      { value: 'other', label: 'Other' },
    ],
  }),
);

export class PaymentMethod extends CardDef {
  static displayName = 'Payment method';
  static icon = BookIcon;
  @field name = contains(StringField);
  @field kind = contains(PaymentMethodKindField);
  @field holdAccount = contains(StringField); // the account money received this way normally waits in, e.g. 1010; a payment held elsewhere says so
  @field cardTitle = contains(StringField, {
    computeVia: function (this: PaymentMethod) {
      return this.name ?? 'Payment method';
    },
  });
  static isolated = class extends Component<typeof PaymentMethod> {
    get facts(): Fact[] {
      let m = this.args.model;
      return [
        { key: 'Kind', value: m.kind ?? '' },
        {
          key: 'Received into',
          value: m.holdAccount || 'The account the payment names',
          mono: !!m.holdAccount,
        },
      ];
    }
    <template>
      <Sheet @eyebrow='Payment method' @title={{@model.name}}><Part
          @title='Method'
        ><Facts @items={{this.facts}} /></Part></Sheet>
    </template>
  };
  static embedded = class extends Component<typeof PaymentMethod> {
    <template>
      <Strip
        @eyebrow='Payment method'
        @title={{@model.name}}
        @meta={{@model.kind}}
      />
    </template>
  };
  static fitted = class extends Component<typeof PaymentMethod> {
    <template>
      <Fit
        @eyebrow='Payment method'
        @title={{@model.name}}
        @meta={{@model.kind}}
      />
    </template>
  };
}
