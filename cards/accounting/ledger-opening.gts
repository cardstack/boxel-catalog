// Opening balances, card-native: converting from QuickBooks at a year-end.
// The open vendor bills become ordinary Bill cards (entered and posted like any bill, debiting
// Opening Balance Equity); everything else in the prior balance sheet is one OpeningBalances card:
// account balances, open customer invoices (AR, until invoices are cards), inventory at cost, and the
// Opening Balance Equity line that makes it balance. Its inventory lots are StockLot cards,
// received in the same batch as its post.
import {
  CardDef,
  FieldDef,
  Component,
  field,
  contains,
  containsMany,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import BookIcon from '@cardstack/boxel-icons/book-open';
import {
  operation,
  params,
  actor,
  instance,
  bxl,
  type OperationDeclaration,
} from '@cardstack/base/operations';
import { StockLot } from './ledger-stock';
import {
  Sheet,
  Part,
  Facts,
  Lines,
  Strip,
  Fit,
  money,
  day,
  type Fact,
} from './record-kit';
import { PostingLine, AccountTotal } from './ledger-document';
import { DocumentStatusField } from './ledger-status';
import { IsoDateField } from './ledger-dates';

const isPosted = (s: string | undefined) => s === 'posted';

export class OpeningInvoice extends FieldDef {
  static displayName = 'Open invoice';
  @field invoiceNo = contains(StringField);
  @field customerId = contains(StringField);
  @field date = contains(IsoDateField);
  @field due = contains(IsoDateField);
  @field amountMinor = contains(NumberField);
}
export class OpeningStock extends FieldDef {
  static displayName = 'Opening inventory';
  @field sku = contains(StringField);
  @field lot = contains(StringField);
  @field qty = contains(NumberField); // thousandths of a unit
  @field costMinor = contains(NumberField);
  @field debitAccount = contains(StringField); // the item's inventory asset account
}

export class OpeningBalances extends CardDef {
  static displayName = 'Opening balances';
  static icon = BookIcon;
  static prefersWideFormat = true;
  @field date = contains(IsoDateField); // the first day of the new books
  @field memo = contains(StringField);
  @field accounts = containsMany(AccountTotal);
  @field openInvoices = containsMany(OpeningInvoice);
  @field inventory = containsMany(OpeningStock);
  @field status = contains(DocumentStatusField);
  @field enteredBy = contains(StringField);
  @field postedBy = contains(StringField);
  // Every line the opening posts, and the Opening Balance Equity (3900) line that balances them. The
  // open vendor bills post themselves (each a Bill debiting 3900), so they are not repeated here.
  @field ledgerLines = containsMany(PostingLine, {
    computeVia: function (this: OpeningBalances) {
      let date = this.date ?? '',
        out: PostingLine[] = [];
      for (let a of (this.accounts ?? []).filter(Boolean))
        out.push(
          new PostingLine({
            account: a.account,
            debitMinor: a.debitMinor ?? 0,
            creditMinor: a.creditMinor ?? 0,
            date,
          }),
        );
      for (let i of (this.openInvoices ?? []).filter(Boolean))
        out.push(
          new PostingLine({
            account: '1100',
            debitMinor: i.amountMinor ?? 0,
            creditMinor: 0,
            date,
            party: i.customerId,
            doc: i.invoiceNo,
          }),
        );
      for (let s of (this.inventory ?? []).filter(Boolean))
        out.push(
          new PostingLine({
            account: s.debitAccount,
            debitMinor: s.costMinor ?? 0,
            creditMinor: 0,
            date,
            doc: s.lot,
          }),
        );
      let dr = out.reduce((n, l) => n + (l.debitMinor ?? 0), 0),
        cr = out.reduce((n, l) => n + (l.creditMinor ?? 0), 0);
      if (dr !== cr)
        out.push(
          new PostingLine({
            account: '3900',
            debitMinor: Math.max(0, cr - dr),
            creditMinor: Math.max(0, dr - cr),
            date,
            doc: 'Opening balance equity',
          }),
        );
      return out;
    },
  });
  @field equityMinor = contains(NumberField, {
    computeVia: function (this: OpeningBalances) {
      let l = (this.ledgerLines ?? []).find((x) => x?.account === '3900');
      return (l?.creditMinor ?? 0) - (l?.debitMinor ?? 0);
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: OpeningBalances) {
      return `Opening balances · ${this.date ?? ''}`;
    },
  });

  /** Post the draft: the realm checks every line against the opening itself and stamps who posted it. */
  @operation static post = {
    base: 'transform',
    transformations: bxl`
      assert(.status == "draft"; "Only draft opening balances can be posted. These are already posted.");
      assert([.accounts[].debitMinor, .accounts[].creditMinor] | all(. >= 0); "Opening balances can't be negative.");
      assert([.accounts[] | .debitMinor + .creditMinor] | all(. > 0); "Each opening balance needs a debit or a credit.");
      assert([.accounts[] | .debitMinor * .creditMinor] | all(. == 0); "An opening balance is a debit or a credit, not both.");
      assert([.accounts[].debitMinor, .accounts[].creditMinor, .openInvoices[].amountMinor, .inventory[].costMinor | floor] == [.accounts[].debitMinor, .accounts[].creditMinor, .openInvoices[].amountMinor, .inventory[].costMinor]; "Amounts are in whole cents.");
      assert([.openInvoices[].amountMinor, .inventory[].costMinor, .inventory[].qty] | all(. > 0); "Open invoices and inventory need positive amounts.");
      assert(.date > (realmConfig().closedThrough // ""); "The opening date is on or before the closing date.");
      .status = "posted";
      .postedBy = actor();
    `,
  } satisfies OperationDeclaration;
  /** Receive one opening inventory lot. Sent in the same batch as post. */
  @operation static receiveLot = {
    base: 'create',
    of: StockLot,
    params: {
      sku: StringField,
      lot: StringField,
      qty: NumberField,
      costMinor: NumberField,
      asset: StringField,
      part5000Minor: NumberField,
      part5100Minor: NumberField,
    },
    fill: {
      sku: params('sku'),
      lot: params('lot'),
      qty: params('qty'),
      costMinor: params('costMinor'),
      asset: params('asset'),
      part5000Minor: params('part5000Minor'),
      part5100Minor: params('part5100Minor'),
      received: instance('date'),
      consumedQty: 0,
      landedMinor: 0,
      source: 'Opening balances',
    },
  } satisfies OperationDeclaration;

  static isolated = class extends Component<typeof OpeningBalances> {
    get facts(): Fact[] {
      let m = this.args.model;
      return [
        { key: 'Books open on', value: day(m.date), strong: true },
        { key: 'Open invoices', value: String((m.openInvoices ?? []).length) },
        { key: 'Inventory lots', value: String((m.inventory ?? []).length) },
        { key: 'Opening balance equity', value: money(m.equityMinor) },
        { key: 'Posted by', value: m.postedBy ?? '' },
      ];
    }
    get postLines() {
      return (this.args.model.ledgerLines ?? []).map((l) => ({
        accountCode: l?.account,
        accountName: [l?.party, l?.doc].filter(Boolean).join(' · '),
        debitMinor: l?.debitMinor ?? 0,
        creditMinor: l?.creditMinor ?? 0,
      }));
    }
    <template>
      <Sheet
        @eyebrow='Conversion'
        @title={{@model.cardTitle}}
        @meta={{@model.memo}}
        @figure={{money @model.equityMinor}}
        @figureLabel='Opening equity'
        @status={{if (isPosted @model.status) 'Posted' 'Draft'}}
        @note='The open vendor bills are their own Bill cards, each posting against Opening Balance Equity.'
      >
        <Part @title='Opening'><Facts @items={{this.facts}} /></Part>
        <Part @title='Posts to the ledger'><Lines
            @lines={{this.postLines}}
            @owner={{@model}}
            @context={{@context}}
            @viewCard={{@viewCard}}
          /></Part>
      </Sheet>
    </template>
  };
  static embedded = class extends Component<typeof OpeningBalances> {
    <template>
      <Strip
        @eyebrow='Opening balances'
        @title={{@model.cardTitle}}
        @meta={{@model.memo}}
        @figure={{money @model.equityMinor}}
      />
    </template>
  };
  static fitted = class extends Component<typeof OpeningBalances> {
    <template>
      <Fit
        @eyebrow='Opening'
        @title={{@model.date}}
        @figure={{money @model.equityMinor}}
        @meta='Opening equity'
      />
    </template>
  };
}

/** The conversion into these books: where the opening balances came from, and the operation that enters them. */
export class Conversion extends CardDef {
  static displayName = 'Conversion';
  static icon = BookIcon;
  @field source = contains(StringField); // e.g. QuickBooks Online
  @field asOf = contains(StringField); // the prior year-end the balances are taken from
  @field cardTitle = contains(StringField, {
    computeVia: function (this: Conversion) {
      return `Conversion from ${this.source ?? ''} · ${this.asOf ?? ''}`;
    },
  });
  @operation static enterOpening = {
    base: 'create',
    of: OpeningBalances,
    params: {
      date: StringField,
      memo: StringField,
      accounts: AccountTotal,
      openInvoices: OpeningInvoice,
      inventory: OpeningStock,
    },
    fill: {
      date: params('date'),
      memo: params('memo'),
      accounts: params('accounts'),
      openInvoices: params('openInvoices'),
      inventory: params('inventory'),
      status: 'draft',
      enteredBy: actor(),
    },
  } satisfies OperationDeclaration;
  static isolated = class extends Component<typeof Conversion> {
    get facts(): Fact[] {
      let m = this.args.model;
      return [
        { key: 'From', value: m.source ?? '' },
        { key: 'Balances as of', value: day(m.asOf) },
      ];
    }
    <template>
      <Sheet @eyebrow='Conversion' @title={{@model.cardTitle}}><Part
          @title='Source'
        ><Facts @items={{this.facts}} /></Part></Sheet>
    </template>
  };
  static embedded = class extends Component<typeof Conversion> {
    <template>
      <Strip @eyebrow='Conversion' @title={{@model.cardTitle}} />
    </template>
  };
  static fitted = class extends Component<typeof Conversion> {
    <template>
      <Fit
        @eyebrow='Conversion'
        @title={{@model.source}}
        @meta={{@model.asOf}}
      />
    </template>
  };
}

export { PostingLine as OpeningLedgerLine, AccountTotal as OpeningAccountLine };
