import {
  CardDef,
  Component,
  field,
  contains,
  containsMany,
  StringField,
} from '@cardstack/base/card-api';
import FileInvoiceIcon from '@cardstack/boxel-icons/file-invoice';

import { LineItem } from '../line-item';
import InvoiceEditor from '../components/invoice-editor';

// Usage page for the Invoice Editor block: a draft invoice's line items,
// edited in place. Every change goes back through `@onChange` to the
// card's own `lineItems`, the way a consumer wires it.
export class InvoiceEditorExample extends CardDef {
  static displayName = 'Invoice Editor Example';
  static icon = FileInvoiceIcon;

  @field lineItems = containsMany(LineItem);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: InvoiceEditorExample) {
      return 'Invoice Editor — a draft before it is sent';
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    setLineItems = (items: LineItem[]) => {
      this.args.model.lineItems = items;
    };

    <template>
      <div class='demo'>
        <InvoiceEditor
          @lineItems={{@model.lineItems}}
          @onChange={{this.setLineItems}}
        />
      </div>
      <style scoped>
        .demo {
          padding: var(--boxel-sp-lg);
          max-width: 48rem;
        }
      </style>
    </template>
  };
}
