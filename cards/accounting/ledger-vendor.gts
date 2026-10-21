// The books' vendor: a procurement Vendor with the keys and defaults the accounting documents use. In
// its own module so the documents that link a vendor (bill payments, vendor credits) can import it
// without importing ledger-cards, which imports them.
import { field, contains, linksTo } from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import BooleanField from '@cardstack/base/boolean';
import { Vendor as ProcurementVendor } from '@cardstack/catalog/cards/procurement/vendor';
import { PaymentTerm } from './ledger-terms';

// The matrix Vendor, plus the key the ledger knows it by and its 1099 flag.
export class Vendor extends ProcurementVendor {
  static displayName = 'Vendor';
  @field vendorId = contains(StringField);
  @field track1099 = contains(BooleanField);
  @field defaultTerms = linksTo(() => PaymentTerm);
}
