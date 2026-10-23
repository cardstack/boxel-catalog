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
  linksTo,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import BookIcon from '@cardstack/boxel-icons/book-open';
import {
  operation,
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
import {
  PostingLine,
  journalOperation,
  FX_CHECKS,
  RATE_SCALE,
} from './ledger-document';
import { REALIZED_FX } from './ledger-settings';
import { DocumentStatusField } from './ledger-status';
import { IsoDateField } from './ledger-dates';
import { PaymentMethod } from './ledger-terms';
import { Vendor } from './ledger-vendor';
import { Payment as CommercePayment } from '@cardstack/catalog/cards/commerce/payment';

const isPosted = (s: string | undefined) => s === 'posted';

/** A line a payment posts (the same shape as a bill's ledger lines). */

export class PaymentApplication extends FieldDef {
  static displayName = 'Payment application';
  @field billNo = contains(StringField);
  @field amountMinor = contains(NumberField); // in the bill's currency
  @field rateMicros = contains(NumberField); // the bill's rate, for one in another currency
}

export class BillPayment extends CardDef {
  static displayName = 'Bill payment';
  static icon = BookIcon;
  @field paymentNo = contains(StringField);
  @field vendorId = contains(StringField);
  @field vendor = linksTo(() => Vendor);
  @field date = contains(IsoDateField); // YYYY-MM-DD
  @field fromAccount = contains(StringField); // the bank or card account it's paid from
  @field method = contains(StringField);
  @field paymentMethod = linksTo(() => PaymentMethod);
  @field sourcePayment = linksTo(() => CommercePayment); // the commerce payment it was posted from
  @field memo = contains(StringField);
  @field applications = containsMany(PaymentApplication);
  @field currency = contains(StringField); // empty: the home currency
  @field rateMicros = contains(NumberField); // the rate the money went out at
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
  // Debit Accounts Payable for each bill paid; credit the account it was paid from. In another
  // currency, each bill's payable clears at the rate it was booked at and the money goes out at this
  // payment's; the difference is realized exchange gain or loss.
  @field ledgerLines = containsMany(PostingLine, {
    computeVia: function (this: BillPayment) {
      let date = this.date ?? '',
        party = this.vendorId ?? '',
        foreign = !!this.currency;
      let at = (minor: number | undefined, rate: number | undefined) =>
        foreign
          ? Math.round(((minor ?? 0) * (rate ?? RATE_SCALE)) / RATE_SCALE)
          : (minor ?? 0);
      let debits = (this.applications ?? [])
        .filter((a) => a && (a.amountMinor ?? 0) > 0)
        .map(
          (a) =>
            new PostingLine({
              account: '2000',
              debitMinor: at(a.amountMinor, a.rateMicros),
              creditMinor: 0,
              date,
              party,
              doc: a.billNo,
            }),
        );
      let paid = at(this.totalMinor, this.rateMicros),
        loss = paid - debits.reduce((n, l) => n + (l.debitMinor ?? 0), 0);
      return [
        ...debits,
        new PostingLine({
          account: this.fromAccount ?? '',
          debitMinor: 0,
          creditMinor: paid,
          date,
          doc: this.paymentNo,
        }),
        ...(loss
          ? [
              new PostingLine({
                account: REALIZED_FX,
                debitMinor: Math.max(0, loss),
                creditMinor: Math.max(0, -loss),
                date,
                party,
                doc: this.paymentNo,
              }),
            ]
          : []),
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
    transformations: {
      $bxl: `
      assert(if .status == null then true else .status == "draft" end; "Only a draft payment can be posted. This one is already posted.");
      assert((.applications | length) > 0; "A payment has to pay at least one bill.");
      assert(([.applications[].amountMinor | type] | unique) == ["number"]; "Every bill paid needs an amount.");
      assert([.applications[].amountMinor] | all(. > 0); "Every amount paid must be positive.");
      assert([.applications[].amountMinor | floor] == [.applications[].amountMinor]; "Amounts are in whole cents.");
      assert(.fromAccount != null; "Say which account the payment comes from.");
      assert(.date > realmConfig().closedThrough; "That date is on or before the closing date, so the payment can't post.");
      assert(if realmConfig().chart == null then true else (([.fromAccount] - [null, ""]) - realmConfig().chart | length == 0) end; "An account on this payment isn't in the chart of accounts. Add it to the chart, then post.");${FX_CHECKS}
      assert(if .currency == null then true else ([.applications[].rateMicros] | all(. > 0)) end; "Each bill paid in another currency needs the rate it was booked at.");
      assert(if .currency == null then true else (if realmConfig().chart == null then true else (["${REALIZED_FX}"] - realmConfig().chart | length == 0) end) end; "Add ${REALIZED_FX}, realized exchange gain or loss, to the chart to post a payment in another currency.");
      .status = "posted";
      .postedBy = actor();
    `,
    },
  } satisfies OperationDeclaration;
  /** Post it into a journal month: every check `post` makes, recorded as journaled. */
  @operation static journal = journalOperation(this.post);

  static isolated = class extends Component<typeof BillPayment> {
    get facts(): Fact[] {
      let m = this.args.model;
      return [
        { key: 'Payment no.', value: m.paymentNo ?? '', mono: true },
        { key: 'Vendor', value: m.vendorId ?? '' },
        { key: 'Date', value: day(m.date) },
        { key: 'From', value: m.fromAccount ?? '' },
        { key: 'Method', value: m.paymentMethod?.name ?? m.method ?? '' },
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
