// Bill payments, card-native. A payment is entered as a draft and posted by an operation the realm
// runs; posting is sent in one batch with Bill.applyPayment on each bill it pays, so the payment and
// the bills' paid amounts land together or not at all.
//
// (A module of its own: the realm's render pool keeps the first copy of a module it loads, so new
// card types go in new modules and existing types only gain operations.)
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
  bxl,
  type OperationDeclaration,
} from '@cardstack/base/operations';
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
import { PostingLine } from './ledger-document';
import { DocumentStatusField } from './ledger-status';

const isPosted = (s: string | undefined) => s === 'posted';

/** A line a payment posts (the same shape as a bill's ledger lines). */

export class PaymentApplication extends FieldDef {
  static displayName = 'Payment application';
  @field billNo = contains(StringField);
  @field amountMinor = contains(NumberField);
}

export class BillPayment extends CardDef {
  static displayName = 'Bill payment';
  static icon = BookIcon;
  @field paymentNo = contains(StringField);
  @field vendorId = contains(StringField);
  @field date = contains(StringField); // YYYY-MM-DD
  @field fromAccount = contains(StringField); // the bank or card account it's paid from
  @field method = contains(StringField);
  @field memo = contains(StringField);
  @field applications = containsMany(PaymentApplication);
  @field status = contains(DocumentStatusField);
  @field enteredBy = contains(StringField);
  @field postedBy = contains(StringField);
  @field totalMinor = contains(NumberField, {
    computeVia: function (this: BillPayment) {
      return (this.applications ?? []).reduce(
        (n, a) => n + (a?.amountMinor ?? 0),
        0,
      );
    },
  });
  // Debit Accounts Payable for each bill paid; credit the account it was paid from.
  @field ledgerLines = containsMany(PostingLine, {
    computeVia: function (this: BillPayment) {
      let date = this.date ?? '',
        party = this.vendorId ?? '';
      let debits = (this.applications ?? [])
        .filter((a) => a && (a.amountMinor ?? 0) > 0)
        .map(
          (a) =>
            new PostingLine({
              account: '2000',
              debitMinor: a.amountMinor,
              creditMinor: 0,
              date,
              party,
              doc: a.billNo,
            }),
        );
      return [
        ...debits,
        new PostingLine({
          account: this.fromAccount ?? '',
          debitMinor: 0,
          creditMinor: this.totalMinor ?? 0,
          date,
          doc: this.paymentNo,
        }),
      ];
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: BillPayment) {
      return `Payment ${this.paymentNo ?? ''}${this.vendorId ? ' · ' + this.vendorId : ''}`;
    },
  });

  /** Post a draft payment: the realm checks it against itself and stamps who posted it. */
  @operation static post = {
    base: 'transform',
    transformations: bxl`
      assert(.status == "draft"; "Only a draft payment can be posted. This one is already posted.");
      assert((.applications | length) > 0; "A payment has to pay at least one bill.");
      assert(([.applications[].amountMinor | type] | unique) == ["number"]; "Every bill paid needs an amount.");
      assert([.applications[].amountMinor] | all(. > 0); "Every amount paid must be positive.");
      assert([.applications[].amountMinor | floor] == [.applications[].amountMinor]; "Amounts are in whole cents.");
      assert(.fromAccount != null; "Say which account the payment comes from.");
      assert(.date > realmConfig("closedThrough"); "That date is on or before the closing date, so the payment can't post.");
      .status = "posted";
      .postedBy = actor();
    `,
  } satisfies OperationDeclaration;

  static isolated = class extends Component<typeof BillPayment> {
    get facts(): Fact[] {
      let m = this.args.model;
      return [
        { key: 'Payment no.', value: m.paymentNo ?? '', mono: true },
        { key: 'Vendor', value: m.vendorId ?? '' },
        { key: 'Date', value: day(m.date) },
        { key: 'From', value: m.fromAccount ?? '' },
        { key: 'Method', value: m.method ?? '' },
        { key: 'Posted by', value: m.postedBy ?? '' },
      ];
    }
    get applied(): Fact[] {
      return (this.args.model.applications ?? [])
        .filter(Boolean)
        .map((a) => ({ key: a!.billNo ?? '', value: money(a!.amountMinor) }));
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
        @eyebrow='Bill payment'
        @title={{@model.cardTitle}}
        @meta={{@model.memo}}
        @figure={{money @model.totalMinor}}
        @figureLabel='Paid'
        @status={{if (isPosted @model.status) 'Posted' 'Draft'}}
      >
        <Part @title='Payment'><Facts @items={{this.facts}} /></Part>
        <Part @title='Bills paid'><Facts @items={{this.applied}} /></Part>
        <Part @title='Posts to the ledger'><Lines
            @lines={{this.postLines}}
            @owner={{@model}}
            @context={{@context}}
            @viewCard={{@viewCard}}
          /></Part>
      </Sheet>
    </template>
  };
  static embedded = class extends Component<typeof BillPayment> {
    <template>
      <Strip
        @eyebrow='Bill payment'
        @title={{@model.cardTitle}}
        @meta={{@model.date}}
        @figure={{money @model.totalMinor}}
      />
    </template>
  };
  static fitted = class extends Component<typeof BillPayment> {
    <template>
      <Fit
        @eyebrow='Payment'
        @title={{@model.paymentNo}}
        @figure={{money @model.totalMinor}}
        @meta={{@model.vendorId}}
      />
    </template>
  };
}

export { PostingLine as PaymentLedgerLine };
