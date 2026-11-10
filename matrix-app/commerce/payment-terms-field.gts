import {
  FieldDef,
  Component,
  field,
  contains,
  StringField,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';

// Imported from its own module, never through `payment` — that path runs
// through the payment↔invoice cycle and yields undefined.
import { PaymentMethodField } from './payment-method-field';

// Negotiated payment terms as one value — "2/10 net 30" as data, not a
// string someone parses later. The computed `shorthand` renders the
// industry notation everywhere terms appear; the discount window math
// (deadline, cash value) belongs to whoever holds the invoice date, so
// this field carries the parts and never a date.
export function termsShorthand(
  netDays?: number | null,
  discountPct?: number | null,
  discountDays?: number | null,
): string {
  if (netDays == null) {
    return '';
  }
  if (discountPct && discountDays) {
    return `${discountPct}/${discountDays} net ${netDays}`;
  }
  return `net ${netDays}`;
}

export class PaymentTermsField extends FieldDef {
  static displayName = 'Payment Terms';

  @field netDays = contains(NumberField);
  @field discountPct = contains(NumberField);
  @field discountDays = contains(NumberField);
  @field method = contains(PaymentMethodField);
  @field notes = contains(StringField);

  @field shorthand = contains(StringField, {
    computeVia: function (this: PaymentTermsField) {
      return termsShorthand(this.netDays, this.discountPct, this.discountDays);
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='terms'>
        <span class='shorthand'>{{@model.shorthand}}</span>
        {{#if @model.method}}<span class='method'>·
            {{@model.method}}</span>{{/if}}
        {{#if @model.notes}}<span class='notes'>{{@model.notes}}</span>{{/if}}
      </div>
      <style scoped>
        .terms {
          display: flex;
          align-items: baseline;
          gap: var(--boxel-sp-xs);
          flex-wrap: wrap;
          font-size: var(--boxel-font-size-sm);
        }
        .shorthand {
          font-weight: 700;
          font-variant-numeric: tabular-nums;
        }
        .method {
          color: var(--muted-foreground);
        }
        .notes {
          flex-basis: 100%;
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='terms-atom'>{{@model.shorthand}}</span>
      <style scoped>
        .terms-atom {
          font-weight: 600;
          font-variant-numeric: tabular-nums;
          font-size: var(--boxel-font-size-sm);
        }
      </style>
    </template>
  };
}

export default PaymentTermsField;
