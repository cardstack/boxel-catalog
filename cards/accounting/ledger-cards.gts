// The system of record, card-native (proof of concept, starting with bills).
// In the demo, a run's books are a fold over posted events held as JSON. Here the record is card
// data: a posted bill is a Bill card whose lines, ledger lines and totals are fields the index can
// see, written by operations the realm runs for every caller. Posting operations are declared below
// each type (see `enter` on Bill); the realm, not the browser, decides whether a post is valid.
import {
  CardDef,
  FieldDef,
  Component,
  field,
  contains,
  containsMany,
  linksTo,
  linksToMany,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import BooleanField from '@cardstack/base/boolean';
import enumField from '@cardstack/base/enum';
import BookIcon from '@cardstack/boxel-icons/book-open';
import {
  operation,
  params,
  actor,
  instance,
  bxl,
  type OperationDeclaration,
} from '@cardstack/base/operations';
import { Vendor as ProcurementVendor } from '@cardstack/catalog/cards/procurement/vendor';
import { Product } from '../commerce/product';
import { BillPayment, PaymentApplication } from './ledger-payments';
import { Deposit, DepositItem } from './ledger-sales';
import {
  StockLot,
  Draw,
  LandedAllocation,
  RoastBatch,
  Fulfillment,
  CountAdjustment,
  LandedCost,
} from './ledger-stock';
import {
  EntryLine,
  AmountLine,
  PayrollRun,
  BankPayment,
  Transfer,
  CardCharge,
  LoanPayment,
  AssetDisposal,
  VendorCredit,
  JournalEntry,
  ScheduledEntry,
  DepreciationRun,
} from './ledger-cash';
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
import { IsoDateField, monthLabel } from './ledger-dates';
import { settingsLink, settingsOf } from './ledger-settings';

// ── reference cards: the chart, vendors, products ───────────────────────────
// Each account type: its label, the statement section it rolls up to, and its cash flow activity.
export const ACCOUNT_TYPES: Record<
  string,
  { label: string; section: string; cashFlow: string }
> = {
  bank: { label: 'Bank', section: 'asset', cashFlow: 'cash' },
  ar: { label: 'Accounts receivable', section: 'asset', cashFlow: 'operating' },
  inventory: { label: 'Inventory', section: 'asset', cashFlow: 'operating' },
  clearing: { label: 'Clearing', section: 'asset', cashFlow: 'operating' },
  asset: {
    label: 'Other current asset',
    section: 'asset',
    cashFlow: 'operating',
  },
  fixed: { label: 'Fixed asset', section: 'asset', cashFlow: 'investing' },
  contra: { label: 'Contra asset', section: 'asset', cashFlow: 'operating' },
  ap: {
    label: 'Accounts payable',
    section: 'liability',
    cashFlow: 'operating',
  },
  cc: { label: 'Credit card', section: 'liability', cashFlow: 'operating' },
  liability: {
    label: 'Other current liability',
    section: 'liability',
    cashFlow: 'operating',
  },
  longterm: {
    label: 'Long-term liability',
    section: 'liability',
    cashFlow: 'financing',
  },
  equity: { label: 'Equity', section: 'equity', cashFlow: 'financing' },
  income: { label: 'Income', section: 'income', cashFlow: 'income' },
  cogs: { label: 'Cost of goods sold', section: 'cogs', cashFlow: 'income' },
  expense: { label: 'Expense', section: 'expense', cashFlow: 'income' },
  other: { label: 'Other expense', section: 'expense', cashFlow: 'income' },
};
const AccountTypeField = enumField(StringField, {
  options: Object.entries(ACCOUNT_TYPES).map(([value, t]) => ({
    value,
    label: t.label,
  })),
  displayName: 'Account type',
});

export class LedgerAccount extends CardDef {
  static displayName = 'Account';
  static icon = BookIcon;
  @field code = contains(StringField);
  @field name = contains(StringField);
  @field type = contains(AccountTypeField);
  @field section = contains(StringField, {
    computeVia: function (this: LedgerAccount) {
      return ACCOUNT_TYPES[this.type ?? '']?.section ?? '';
    },
  });
  @field active = contains(BooleanField);
  @field cardTitle = contains(StringField, {
    computeVia: function (this: LedgerAccount) {
      return `${this.code ?? ''} ${this.name ?? ''}`.trim() || 'Account';
    },
  });
  static embedded = class extends Component<typeof LedgerAccount> {
    <template>
      <Strip
        @eyebrow='Account'
        @title={{@model.cardTitle}}
        @meta={{@model.type}}
      />
    </template>
  };
  static fitted = class extends Component<typeof LedgerAccount> {
    <template>
      <Fit
        @eyebrow='Account'
        @title={{@model.cardTitle}}
        @meta={{@model.type}}
      />
    </template>
  };
  static isolated = class extends Component<typeof LedgerAccount> {
    get facts(): Fact[] {
      let m = this.args.model;
      return [
        { key: 'Number', value: m.code ?? '', mono: true },
        { key: 'Type', value: m.type ?? '' },
        { key: 'Active', value: m.active === false ? 'No' : 'Yes' },
      ];
    }
    <template>
      <Sheet
        @eyebrow='Chart of accounts'
        @title={{@model.name}}
        @meta={{@model.code}}
      ><Part @title='Account'><Facts @items={{this.facts}} /></Part></Sheet>
    </template>
  };
}

// The matrix Vendor, plus the key the ledger knows it by and its 1099 flag.
export class Vendor extends ProcurementVendor {
  static displayName = 'Vendor';
  @field vendorId = contains(StringField);
  @field track1099 = contains(BooleanField);
}

// The matrix Product, plus the ledger accounts an inventory item posts to.
export class Item extends Product {
  static displayName = 'Product';
  @field assetAccount = contains(StringField);
  @field cogsAccount = contains(StringField);
  static isolated = class extends Component<typeof Item> {
    get facts(): Fact[] {
      let m = this.args.model;
      return [
        { key: 'SKU', value: m.sku ?? '', mono: true },
        { key: 'Type', value: m.productType ?? '' },
        { key: 'Asset account', value: m.assetAccount ?? '' },
        { key: 'Cost account', value: m.cogsAccount ?? '' },
      ];
    }
    <template>
      <Sheet
        @eyebrow='Product'
        @title={{@model.cardTitle}}
        @meta={{@model.sku}}
      ><Part @title='Product'><Facts @items={{this.facts}} /></Part></Sheet>
    </template>
  };
}

// ── a bill ───────────────────────────────────────────────────────────────────
export class BillLine extends FieldDef {
  static displayName = 'Bill line';
  @field account = contains(StringField); // an expense or clearing account, or empty for a product line
  @field sku = contains(StringField); // a product, or empty for an account line
  @field qty = contains(NumberField); // thousandths of a unit (pounds, bags)
  @field unitCostMinor = contains(NumberField); // cents per unit
  @field amountMinor = contains(NumberField); // cents; for a product line, unitCost × qty / 1000, rounded
  @field lot = contains(StringField);
  @field debitAccount = contains(StringField); // the account the line debits: the item's asset account for inventory
  @field description = contains(StringField);
  @field cls = contains(StringField);
  @field loc = contains(StringField);
}

export class Bill extends CardDef {
  static displayName = 'Bill';
  static icon = BookIcon;
  @field billNo = contains(StringField);
  @field vendorId = contains(StringField);
  @field vendor = linksTo(Vendor);
  @field date = contains(IsoDateField); // YYYY-MM-DD
  @field due = contains(IsoDateField);
  @field memo = contains(StringField);
  @field lines = containsMany(BillLine);
  @field status = contains(DocumentStatusField); // only the post operation moves it
  @field enteredBy = contains(StringField); // stamped by the realm when the draft is created
  @field postedBy = contains(StringField); // stamped by the realm when the bill is posted
  @field paidMinor = contains(NumberField);
  // A void keeps the bill and its posting; the mirror entry posts into the void date's journal month.
  @field voidDate = contains(IsoDateField); // written only by void
  @field voidedBy = contains(StringField);
  @field voidReason = contains(StringField);
  @field totalMinor = contains(NumberField, {
    computeVia: function (this: Bill) {
      return (this.lines ?? []).reduce((n, l) => n + (l?.amountMinor ?? 0), 0);
    },
  });
  @field openMinor = contains(NumberField, {
    computeVia: function (this: Bill) {
      return this.voidDate ? 0 : (this.totalMinor ?? 0) - (this.paidMinor ?? 0);
    },
  });
  // What the bill posts: a debit per line, and one credit to Accounts Payable for the total. Indexed,
  // so "every line on 6800 in March" is a query, not a replay.
  @field ledgerLines = containsMany(PostingLine, {
    computeVia: function (this: Bill) {
      let doc = this.billNo ?? '',
        date = this.date ?? '',
        party = this.vendorId ?? '';
      let debits = (this.lines ?? [])
        .filter((l) => l && (l.amountMinor ?? 0) > 0)
        .map(
          (l) =>
            new PostingLine({
              account: l.debitAccount || l.account,
              debitMinor: l.amountMinor,
              creditMinor: 0,
              date,
              cls: l.cls,
              loc: l.loc,
              party: '',
              doc,
            }),
        );
      return [
        ...debits,
        new PostingLine({
          account: '2000',
          debitMinor: 0,
          creditMinor: this.totalMinor ?? 0,
          date,
          party,
          doc,
        }),
      ];
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: Bill) {
      return `Bill ${this.billNo ?? ''}${this.vendorId ? ' · ' + this.vendorId : ''}`;
    },
  });
  /**
   * Post a draft bill. A create can't check anything (its program never runs), but a transform can:
   * the realm runs these asserts against the bill as stored, for every caller, and refuses with the
   * message. Posting is one-way: nothing grants a raw edit, so a posted bill stays as posted.
   */
  @operation static post = {
    base: 'transform',
    transformations: bxl`
      assert(.status == "draft"; "Only a draft bill can be posted. This one is already posted.");
      assert((.lines | length) > 0; "A bill needs at least one line.");
      assert(([.lines[].amountMinor | type] | unique) == ["number"]; "Every line needs an amount.");
      assert([.lines[].amountMinor] | all(. > 0); "Every line needs a positive amount.");
      assert([.lines[].amountMinor | floor] == [.lines[].amountMinor]; "Amounts are in whole cents.");
      assert([.lines[] | select(.sku != null) | .unitCostMinor * .qty / 1000 | round] == [.lines[] | select(.sku != null) | .amountMinor]; "A product line's amount must be its unit cost times its quantity.");
      assert([.lines[] | select(.sku == null) | .account != null] | all; "Every line needs an account or a product.");
      assert(.date > (realmConfig().closedThrough // ""); "That date is on or before the closing date, so the bill can't post.");
      assert(([.lines[].account, .lines[].debitAccount] - [null, ""]) - (realmConfig().chart // [.lines[].account, .lines[].debitAccount]) | length == 0; "An account on this bill isn't in the chart of accounts. Add it to the chart, then post.");
      .status = "posted";
      .postedBy = actor();
    `,
  } satisfies OperationDeclaration;
  /**
   * Record part or all of a payment against this bill. Sent in the same batch as the payment's post,
   * so the payment and the bills it pays land together. Refuses paying a draft or paying more than
   * the bill has open.
   */
  @operation static applyPayment = {
    base: 'transform',
    params: {
      amountMinor: NumberField,
      paymentNo: StringField,
      vendorId: StringField,
    },
    transformations: bxl`
      assert(.status == "posted"; "Only a posted bill can be paid.");
      assert(.voidDate == null; "This bill is void, so it can't be paid.");
      assert(params("vendorId") == .vendorId; "A payment pays only its own vendor's bills. This bill is from someone else.");
      assert(params("amountMinor") > 0; "A payment amount must be positive.");
      assert([.lines[].amountMinor] + [0 - .paidMinor - params("amountMinor")] | add | . >= 0; "That pays more than the bill has open.");
      .paidMinor |= . + params("amountMinor");
    `,
  } satisfies OperationDeclaration;
  /** Take back a payment or vendor credit, when its posting is reversed. Sent in the same batch as the reversal. */
  @operation static unapplyPayment = {
    base: 'transform',
    params: {
      amountMinor: NumberField,
      paymentNo: StringField,
      vendorId: StringField,
    },
    transformations: bxl`
      assert(params("vendorId") == .vendorId; "That payment wasn't to this vendor.");
      assert(params("amountMinor") > 0; "The amount taken back must be positive.");
      assert([.paidMinor - params("amountMinor")] | all(. >= 0); "That takes back more than was paid on this bill.");
      .paidMinor |= . - params("amountMinor");
    `,
  } satisfies OperationDeclaration;
  /**
   * Void the bill. Nothing is deleted: the bill keeps its posting, and the same batch posts the mirror
   * entry into the journal month of the void date. Refused while anything is paid on it.
   */
  @operation static void = {
    base: 'transform',
    params: { date: StringField, reason: StringField },
    transformations: bxl`
      assert(.status == "posted"; "Only a posted bill can be voided. Delete a draft instead.");
      assert(.voidDate == null; "This bill is already void.");
      assert([.paidMinor + 0] | all(. == 0); "Payments or credits are applied to this bill. Reverse them first, then void it.");
      assert(params("date") >= .date; "A void can't be dated before the bill.");
      assert(params("date") > (realmConfig().closedThrough // ""); "That date is on or before the closing date. Void it in an open month.");
      assert(params("reason") != null; "Say why the bill is void.");
      assert(params("reason") != ""; "Say why the bill is void.");
      .voidDate = params("date");
      .voidReason = params("reason");
      .voidedBy = actor();
    `,
  } satisfies OperationDeclaration;
  /**
   * Receive one stock lot from this bill. Sent in the same batch as post, so the bill and its lots
   * land together or not at all.
   */
  @operation static receiveLot = {
    base: 'create',
    of: StockLot,
    params: {
      sku: StringField,
      lot: StringField,
      qty: NumberField,
      costMinor: NumberField,
      received: StringField,
      asset: StringField,
      part5000Minor: NumberField,
      part5100Minor: NumberField,
    },
    fill: {
      sku: params('sku'),
      lot: params('lot'),
      qty: params('qty'),
      costMinor: params('costMinor'),
      received: params('received'),
      asset: params('asset'),
      part5000Minor: params('part5000Minor'),
      part5100Minor: params('part5100Minor'),
      consumedQty: 0,
      landedMinor: 0,
      source: instance('billNo'),
    },
  } satisfies OperationDeclaration;

  static isolated = class extends Component<typeof Bill> {
    get facts(): Fact[] {
      let m = this.args.model;
      return [
        { key: 'Bill no.', value: m.billNo ?? '', mono: true },
        { key: 'Vendor', value: m.vendorId ?? '' },
        { key: 'Bill date', value: day(m.date) },
        { key: 'Due', value: day(m.due) },
        { key: 'Posted by', value: m.postedBy ?? '' },
        ...(m.voidDate
          ? [
              {
                key: 'Voided',
                value: `${day(m.voidDate)} by ${m.voidedBy ?? ''}${m.voidReason ? ' · ' + m.voidReason : ''}`,
              },
            ]
          : []),
      ];
    }
    get postLines() {
      return (this.args.model.ledgerLines ?? []).map((l) => ({
        accountCode: l?.account,
        accountName: [l?.cls, l?.loc, l?.party].filter(Boolean).join(' · '),
        debitMinor: l?.debitMinor ?? 0,
        creditMinor: l?.creditMinor ?? 0,
      }));
    }
    get status() {
      let m = this.args.model;
      return m.voidDate
        ? 'Void'
        : (m.openMinor ?? 0) <= 0
          ? 'Paid'
          : (m.paidMinor ?? 0) > 0
            ? 'Partial'
            : 'Open';
    }
    <template>
      <Sheet
        @eyebrow='Bill'
        @title={{@model.cardTitle}}
        @meta={{@model.memo}}
        @figure={{money @model.totalMinor}}
        @figureLabel='Total'
        @status={{this.status}}
      >
        <Part @title='Bill'><Facts @items={{this.facts}} /></Part>
        <Part @title='Posts to the ledger'><Lines
            @lines={{this.postLines}}
            @owner={{@model}}
            @context={{@context}}
            @viewCard={{@viewCard}}
          /></Part>
      </Sheet>
    </template>
  };
  static embedded = class extends Component<typeof Bill> {
    <template>
      <Strip
        @eyebrow='Bill'
        @title={{@model.cardTitle}}
        @meta={{@model.date}}
        @figure={{money @model.totalMinor}}
      />
    </template>
  };
  static fitted = class extends Component<typeof Bill> {
    <template>
      <Fit
        @eyebrow='Bill'
        @title={{@model.billNo}}
        @figure={{money @model.totalMinor}}
        @meta={{@model.vendorId}}
      />
    </template>
  };
}

// ── the company: settings the posting rules read ────────────────────────────
export class Ledger extends CardDef {
  static displayName = 'Ledger';
  static icon = BookIcon;
  static prefersWideFormat = true;
  @field company = contains(StringField);
  // The books' settings, from the realm's configuration (see ledger-settings).
  @field settings = settingsLink();
  @field accounts = linksToMany(() => LedgerAccount, {
    query: { page: { size: 500 } },
  });
  @field closedThrough = contains(IsoDateField, {
    computeVia: function (this: Ledger) {
      return settingsOf(this).closedThrough;
    },
  });
  @field currency = contains(StringField, {
    computeVia: function (this: Ledger) {
      return settingsOf(this).currency;
    },
  });
  @field fiscalYearStart = contains(NumberField, {
    computeVia: function (this: Ledger) {
      return settingsOf(this).fiscalYearStart;
    },
  });
  @field billCount = contains(NumberField);
  @field cardTitle = contains(StringField, {
    computeVia: function (this: Ledger) {
      return this.company || 'Ledger';
    },
  });
  /**
   * Enter a draft bill: the realm stamps who entered it and creates the Bill card as a draft. It
   * checks nothing (a create can't assert); Bill.post does the checking.
   */
  @operation static enterBill = {
    base: 'create',
    of: Bill,
    params: {
      billNo: StringField,
      vendorId: StringField,
      date: StringField,
      due: StringField,
      memo: StringField,
      lines: BillLine,
    },
    fill: {
      billNo: params('billNo'),
      vendorId: params('vendorId'),
      date: params('date'),
      due: params('due'),
      memo: params('memo'),
      lines: params('lines'),
      status: 'draft',
      enteredBy: actor(),
      paidMinor: 0,
    },
  } satisfies OperationDeclaration;
  /** Enter a draft bill payment: stamped with who entered it; BillPayment.post checks it. */
  @operation static enterPayment = {
    base: 'create',
    of: BillPayment,
    params: {
      paymentNo: StringField,
      vendorId: StringField,
      date: StringField,
      fromAccount: StringField,
      method: StringField,
      memo: StringField,
      applications: PaymentApplication,
    },
    fill: {
      paymentNo: params('paymentNo'),
      vendorId: params('vendorId'),
      date: params('date'),
      fromAccount: params('fromAccount'),
      method: params('method'),
      memo: params('memo'),
      applications: params('applications'),
      status: 'draft',
      enteredBy: actor(),
    },
  } satisfies OperationDeclaration;
  /** Draft a bank deposit or processor payout; Deposit.post checks it, and is sent with markDeposited on each item. */
  @operation static enterDeposit = {
    base: 'create',
    of: Deposit,
    params: {
      docNo: StringField,
      date: StringField,
      memo: StringField,
      bank: StringField,
      clearingAccount: StringField,
      processor: StringField,
      items: DepositItem,
      feeMinor: NumberField,
      feeAccount: StringField,
      cls: StringField,
      loc: StringField,
    },
    fill: {
      docNo: params('docNo'),
      date: params('date'),
      memo: params('memo'),
      bank: params('bank'),
      clearingAccount: params('clearingAccount'),
      processor: params('processor'),
      items: params('items'),
      feeMinor: params('feeMinor'),
      feeAccount: params('feeAccount'),
      cls: params('cls'),
      loc: params('loc'),
      status: 'draft',
      enteredBy: actor(),
    },
  } satisfies OperationDeclaration;
  /** Draft a roast batch; RoastBatch.post checks it, sent with StockLot.draw per input and produceLot. */
  @operation static enterRoast = {
    base: 'create',
    of: RoastBatch,
    params: {
      docNo: StringField,
      date: StringField,
      memo: StringField,
      loc: StringField,
      inputs: Draw,
      outputSku: StringField,
      outputLot: StringField,
      outputAsset: StringField,
      outputQty: NumberField,
      outputPart5000Minor: NumberField,
      outputPart5100Minor: NumberField,
      chargedWeight: NumberField,
      finishedWeight: NumberField,
      roastLog: StringField,
    },
    fill: {
      docNo: params('docNo'),
      date: params('date'),
      memo: params('memo'),
      loc: params('loc'),
      inputs: params('inputs'),
      outputSku: params('outputSku'),
      outputLot: params('outputLot'),
      outputAsset: params('outputAsset'),
      outputQty: params('outputQty'),
      outputPart5000Minor: params('outputPart5000Minor'),
      outputPart5100Minor: params('outputPart5100Minor'),
      chargedWeight: params('chargedWeight'),
      finishedWeight: params('finishedWeight'),
      roastLog: params('roastLog'),
      status: 'draft',
      enteredBy: actor(),
    },
  } satisfies OperationDeclaration;
  /** Draft the fulfillment of a sale (its cost of goods sold); posted with StockLot.draw per lot. */
  @operation static enterFulfillment = {
    base: 'create',
    of: Fulfillment,
    params: {
      docNo: StringField,
      date: StringField,
      memo: StringField,
      saleNo: StringField,
      customerId: StringField,
      cls: StringField,
      loc: StringField,
      draws: Draw,
    },
    fill: {
      docNo: params('docNo'),
      date: params('date'),
      memo: params('memo'),
      saleNo: params('saleNo'),
      customerId: params('customerId'),
      cls: params('cls'),
      loc: params('loc'),
      draws: params('draws'),
      status: 'draft',
      enteredBy: actor(),
    },
  } satisfies OperationDeclaration;
  /** Draft a count adjustment; posted with StockLot.draw per lot. */
  @operation static enterCount = {
    base: 'create',
    of: CountAdjustment,
    params: {
      docNo: StringField,
      date: StringField,
      memo: StringField,
      reason: StringField,
      account: StringField,
      draws: Draw,
    },
    fill: {
      docNo: params('docNo'),
      date: params('date'),
      memo: params('memo'),
      reason: params('reason'),
      account: params('account'),
      draws: params('draws'),
      status: 'draft',
      enteredBy: actor(),
    },
  } satisfies OperationDeclaration;
  /** Draft a landed-cost allocation; posted with StockLot.addCost per lot. */
  @operation static enterLanded = {
    base: 'create',
    of: LandedCost,
    params: {
      docNo: StringField,
      date: StringField,
      memo: StringField,
      driver: StringField,
      clearingAccount: StringField,
      amountMinor: NumberField,
      allocations: LandedAllocation,
    },
    fill: {
      docNo: params('docNo'),
      date: params('date'),
      memo: params('memo'),
      driver: params('driver'),
      clearingAccount: params('clearingAccount'),
      amountMinor: params('amountMinor'),
      allocations: params('allocations'),
      status: 'draft',
      enteredBy: actor(),
    },
  } satisfies OperationDeclaration;
  /** Draft a payroll run from the payroll provider; PayrollRun.post checks it. */
  @operation static enterPayroll = {
    base: 'create',
    of: PayrollRun,
    params: {
      docNo: StringField,
      date: StringField,
      memo: StringField,
      provider: StringField,
      bank: StringField,
      employerTaxAccount: StringField,
      liabilityAccount: StringField,
      employerTaxMinor: NumberField,
      withholdingMinor: NumberField,
      deductionsMinor: NumberField,
      netMinor: NumberField,
      wages: AmountLine,
    },
    fill: {
      docNo: params('docNo'),
      date: params('date'),
      memo: params('memo'),
      provider: params('provider'),
      bank: params('bank'),
      employerTaxAccount: params('employerTaxAccount'),
      liabilityAccount: params('liabilityAccount'),
      employerTaxMinor: params('employerTaxMinor'),
      withholdingMinor: params('withholdingMinor'),
      deductionsMinor: params('deductionsMinor'),
      netMinor: params('netMinor'),
      wages: params('wages'),
      status: 'draft',
      enteredBy: actor(),
    },
  } satisfies OperationDeclaration;
  /** Draft a payroll remittance, sales tax payment or owner draw; BankPayment.post checks it. */
  @operation static enterBankPayment = {
    base: 'create',
    of: BankPayment,
    params: {
      docNo: StringField,
      date: StringField,
      memo: StringField,
      kind: StringField,
      bank: StringField,
      account: StringField,
      payee: StringField,
      period: StringField,
      amountMinor: NumberField,
    },
    fill: {
      docNo: params('docNo'),
      date: params('date'),
      memo: params('memo'),
      kind: params('kind'),
      bank: params('bank'),
      account: params('account'),
      payee: params('payee'),
      period: params('period'),
      amountMinor: params('amountMinor'),
      status: 'draft',
      enteredBy: actor(),
    },
  } satisfies OperationDeclaration;
  /** Draft a transfer between accounts; Transfer.post checks it. */
  @operation static enterTransfer = {
    base: 'create',
    of: Transfer,
    params: {
      docNo: StringField,
      date: StringField,
      memo: StringField,
      fromAccount: StringField,
      toAccount: StringField,
      amountMinor: NumberField,
    },
    fill: {
      docNo: params('docNo'),
      date: params('date'),
      memo: params('memo'),
      fromAccount: params('fromAccount'),
      toAccount: params('toAccount'),
      amountMinor: params('amountMinor'),
      status: 'draft',
      enteredBy: actor(),
    },
  } satisfies OperationDeclaration;
  /** Draft a credit card charge; CardCharge.post checks it. */
  @operation static enterCardCharge = {
    base: 'create',
    of: CardCharge,
    params: {
      docNo: StringField,
      date: StringField,
      memo: StringField,
      card: StringField,
      account: StringField,
      vendor: StringField,
      cls: StringField,
      support: StringField,
      amountMinor: NumberField,
    },
    fill: {
      docNo: params('docNo'),
      date: params('date'),
      memo: params('memo'),
      card: params('card'),
      account: params('account'),
      vendor: params('vendor'),
      cls: params('cls'),
      support: params('support'),
      amountMinor: params('amountMinor'),
      status: 'draft',
      enteredBy: actor(),
    },
  } satisfies OperationDeclaration;
  /** Draft a loan payment; LoanPayment.post checks it. */
  @operation static enterLoanPayment = {
    base: 'create',
    of: LoanPayment,
    params: {
      docNo: StringField,
      date: StringField,
      memo: StringField,
      loan: StringField,
      bank: StringField,
      loanAccount: StringField,
      interestAccount: StringField,
      amountMinor: NumberField,
      principalMinor: NumberField,
      interestMinor: NumberField,
    },
    fill: {
      docNo: params('docNo'),
      date: params('date'),
      memo: params('memo'),
      loan: params('loan'),
      bank: params('bank'),
      loanAccount: params('loanAccount'),
      interestAccount: params('interestAccount'),
      amountMinor: params('amountMinor'),
      principalMinor: params('principalMinor'),
      interestMinor: params('interestMinor'),
      status: 'draft',
      enteredBy: actor(),
    },
  } satisfies OperationDeclaration;
  /** Draft the disposal of a fixed asset; AssetDisposal.post checks it. */
  @operation static enterDisposal = {
    base: 'create',
    of: AssetDisposal,
    params: {
      docNo: StringField,
      date: StringField,
      memo: StringField,
      asset: StringField,
      bank: StringField,
      assetAccount: StringField,
      accumulatedAccount: StringField,
      gainLossAccount: StringField,
      proceedsMinor: NumberField,
      costMinor: NumberField,
      accumulatedMinor: NumberField,
    },
    fill: {
      docNo: params('docNo'),
      date: params('date'),
      memo: params('memo'),
      asset: params('asset'),
      bank: params('bank'),
      assetAccount: params('assetAccount'),
      accumulatedAccount: params('accumulatedAccount'),
      gainLossAccount: params('gainLossAccount'),
      proceedsMinor: params('proceedsMinor'),
      costMinor: params('costMinor'),
      accumulatedMinor: params('accumulatedMinor'),
      status: 'draft',
      enteredBy: actor(),
    },
  } satisfies OperationDeclaration;
  /** Draft a vendor credit; posted with Bill.applyPayment on the bill it is applied to; VendorCredit.post checks it. */
  @operation static enterVendorCredit = {
    base: 'create',
    of: VendorCredit,
    params: {
      docNo: StringField,
      date: StringField,
      memo: StringField,
      vendorId: StringField,
      billNo: StringField,
      account: StringField,
      amountMinor: NumberField,
    },
    fill: {
      docNo: params('docNo'),
      date: params('date'),
      memo: params('memo'),
      vendorId: params('vendorId'),
      billNo: params('billNo'),
      account: params('account'),
      amountMinor: params('amountMinor'),
      status: 'draft',
      enteredBy: actor(),
    },
  } satisfies OperationDeclaration;
  /** Draft a journal entry; JournalEntry.post checks it. */
  @operation static enterJournal = {
    base: 'create',
    of: JournalEntry,
    params: {
      docNo: StringField,
      date: StringField,
      memo: StringField,
      preparer: StringField,
      reviewer: StringField,
      support: StringField,
      lines: EntryLine,
    },
    fill: {
      docNo: params('docNo'),
      date: params('date'),
      memo: params('memo'),
      preparer: params('preparer'),
      reviewer: params('reviewer'),
      support: params('support'),
      lines: params('lines'),
      status: 'draft',
      enteredBy: actor(),
    },
  } satisfies OperationDeclaration;
  /** Draft one period of a schedule; ScheduledEntry.post checks it. */
  @operation static enterScheduled = {
    base: 'create',
    of: ScheduledEntry,
    params: {
      docNo: StringField,
      date: StringField,
      memo: StringField,
      schedule: StringField,
      kind: StringField,
      period: NumberField,
      lines: EntryLine,
    },
    fill: {
      docNo: params('docNo'),
      date: params('date'),
      memo: params('memo'),
      schedule: params('schedule'),
      kind: params('kind'),
      period: params('period'),
      lines: params('lines'),
      status: 'draft',
      enteredBy: actor(),
    },
  } satisfies OperationDeclaration;
  /** Draft a month of depreciation; DepreciationRun.post checks it. */
  @operation static enterDepreciation = {
    base: 'create',
    of: DepreciationRun,
    params: {
      docNo: StringField,
      date: StringField,
      memo: StringField,
      month: StringField,
      assets: AmountLine,
      lines: EntryLine,
    },
    fill: {
      docNo: params('docNo'),
      date: params('date'),
      memo: params('memo'),
      month: params('month'),
      assets: params('assets'),
      lines: params('lines'),
      status: 'draft',
      enteredBy: actor(),
    },
  } satisfies OperationDeclaration;
  static embedded = class extends Component<typeof Ledger> {
    <template>
      <Strip
        @eyebrow='Ledger'
        @title={{@model.company}}
        @meta={{@model.closedThrough}}
      />
    </template>
  };
  static fitted = class extends Component<typeof Ledger> {
    <template>
      <Fit
        @eyebrow='Ledger'
        @title={{@model.company}}
        @meta={{@model.closedThrough}}
      />
    </template>
  };
  static isolated = class extends Component<typeof Ledger> {
    get facts(): Fact[] {
      let m = this.args.model,
        s = settingsOf(m);
      let codes = new Set(
          (m.accounts ?? []).map((a) => a?.code).filter(Boolean) as string[],
        ),
        noCard = (s.chart ?? []).filter((c) => !codes.has(c)),
        notInChart = s.chart
          ? [...codes].filter((c) => !s.chart!.includes(c))
          : [];
      return [
        { key: 'Home currency', value: s.currency },
        {
          key: 'Fiscal year starts',
          value: monthLabel(
            `2000-${String(s.fiscalYearStart).padStart(2, '0')}`,
          ).replace(' 2000', ''),
        },
        {
          key: 'Closing date',
          value: s.closedThrough
            ? day(s.closedThrough)
            : 'None: any date posts',
        },
        {
          key: 'Materiality',
          value:
            s.materialityMinor === undefined
              ? 'None: no entry needs a reviewer'
              : money(s.materialityMinor),
        },
        {
          key: 'Chart',
          value: !s.chart
            ? 'Not set: a journal line may use any code'
            : noCard.length || notInChart.length
              ? [
                  noCard.length
                    ? `No account card for ${noCard.join(', ')}`
                    : '',
                  notInChart.length
                    ? `Not in the chart: ${notInChart.join(', ')}`
                    : '',
                ]
                  .filter(Boolean)
                  .join('. ')
              : `${s.chart.length} codes, each with an account card`,
        },
      ];
    }
    <template>
      <Sheet
        @eyebrow='System of record'
        @title={{@model.company}}
        @note='These settings live in the realm configuration: the config object in its realm.json.'
      ><Part @title='Settings'><Facts @items={{this.facts}} /></Part></Sheet>
    </template>
  };
}

export { PostingLine as LedgerLine };
