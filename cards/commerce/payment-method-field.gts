import StringField from '@cardstack/base/string';
import enumField from '@cardstack/base/enum';

// Extracted from payment.gts 2026-09-08 to break a definition cycle, not for
// tidiness. `payment` and `invoice` import each other, so a module that
// reached PaymentMethodField through `payment` evaluated it mid-cycle and read
// `undefined` — which left PaymentTermsField's own `method` field classless,
// and an unresolvable field definition makes the definition lookup fail for
// every type whose links reach a searchable `linksTo(CardDef)`. `payment.gts`
// re-exports this name, so importing it from either module works.
//
// Payment and Invoice still import each other.
export const PaymentMethodField = enumField(StringField, {
  options: ['card', 'bank transfer', 'cash', 'other'],
  displayName: 'Payment Method',
});

export default PaymentMethodField;
