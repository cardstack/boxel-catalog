// Sales, card-native: invoices, sales receipts, customer payments, deposits and payouts, credit
// memos and write-offs. Each is a LedgerDocument entered as a draft and posted by an operation the
// realm runs; whatever a post changes on another card (an invoice's paid amount, a receipt marked
// deposited) is sent in the same batch, so it all lands together or not at all.
//
// Cost of goods sold is not posted here yet: a sale draws on roasted lots, and roasts are not cards
// yet. Each sale line keeps its product and quantity for when they are.
import {
  FieldDef,
  field,
  contains,
  containsMany,
  linksTo,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import BooleanField from '@cardstack/base/boolean';
import BookIcon from '@cardstack/boxel-icons/book-open';
import {
  operation,
  params,
  actor,
  instance,
  bxl,
  type OperationDeclaration,
} from '@cardstack/base/operations';
import { Account } from '@cardstack/catalog/cards/crm/account';
import { LedgerDocument, type PostingInput } from './ledger-document';
import { money, day, type Fact } from './record-kit';
import { IsoDateField } from './ledger-dates';

const AR = '1100',
  TAX = '2200';
const sum = (xs: (number | undefined)[]) =>
  xs.reduce<number>((n, x) => n + (x ?? 0), 0);

export class SaleLine extends FieldDef {
  static displayName = 'Sale line';
  @field sku = contains(StringField); // a product, or empty for a service or opening line
  @field description = contains(StringField);
  @field qty = contains(NumberField); // thousandths of a unit
  @field priceMinor = contains(NumberField); // cents per unit
  @field amountMinor = contains(NumberField); // cents; for a product line, price × qty / 1000, rounded
  @field account = contains(StringField); // the income (or deferred revenue) account it credits
  @field cls = contains(StringField);
  @field loc = contains(StringField);
}

export class InvoiceApplication extends FieldDef {
  static displayName = 'Invoice paid';
  @field invoiceNo = contains(StringField);
  @field amountMinor = contains(NumberField);
}

export class DepositItem extends FieldDef {
  static displayName = 'Deposited item';
  @field docNo = contains(StringField); // the payment or sales receipt deposited
  @field amountMinor = contains(NumberField);
}

/** A sale's own lines: a credit per line, sales tax, and the debit for what the customer owes or paid. */
function saleLines(
  d: {
    lines?: SaleLine[];
    taxMinor?: number;
    agencyId?: string;
    docNo?: string;
    customerId?: string;
  },
  debitAccount: string,
): PostingInput[] {
  let lines = (d.lines ?? []).filter(Boolean);
  let out: PostingInput[] = lines
    .filter((l) => (l.amountMinor ?? 0) > 0)
    .map((l) => ({
      account: l.account,
      debitMinor: 0,
      creditMinor: l.amountMinor,
      cls: l.cls,
      loc: l.loc,
    }));
  if ((d.taxMinor ?? 0) > 0)
    out.push({
      account: TAX,
      debitMinor: 0,
      creditMinor: d.taxMinor,
      party: d.agencyId,
    });
  out.push({
    account: debitAccount,
    debitMinor: sum(lines.map((l) => l.amountMinor)) + (d.taxMinor ?? 0),
    creditMinor: 0,
    party: d.customerId,
    doc: d.docNo,
  });
  return out;
}

// ── credit memos and write-offs: reducing what a customer owes ──────────────
export class CreditMemo extends LedgerDocument {
  static displayName = 'Credit memo';
  static icon = BookIcon;
  @field invoiceNo = contains(StringField);
  @field customerId = contains(StringField);
  @field customer = linksTo(() => Customer);
  @field amountMinor = contains(NumberField);
  @field account = contains(StringField); // the income account it reverses
  @field cls = contains(StringField);

  postings() {
    return [
      {
        account: this.account ?? '',
        debitMinor: this.amountMinor ?? 0,
        creditMinor: 0,
        cls: this.cls,
      },
      {
        account: AR,
        debitMinor: 0,
        creditMinor: this.amountMinor ?? 0,
        party: this.customerId,
        doc: this.invoiceNo,
      },
    ];
  }
  title() {
    return `Credit memo ${this.docNo ?? ''}`;
  }
  party() {
    return this.customerId ?? '';
  }
  facts(): Fact[] {
    return [
      { key: 'Memo no.', value: this.docNo ?? '', mono: true },
      { key: 'Against invoice', value: this.invoiceNo ?? '' },
      { key: 'Customer', value: this.customerId ?? '' },
      { key: 'Date', value: day(this.date) },
      { key: 'Posted by', value: this.postedBy ?? '' },
    ];
  }

  @operation static post = {
    base: 'transform',
    transformations: bxl`
      assert(if .status == null then true else .status == "draft" end; "Only a draft credit memo can be posted. This one is already posted.");
      assert(.amountMinor > 0; "A credit must be positive.");
      assert([.amountMinor | floor] == [.amountMinor]; "Amounts are in whole cents.");
      assert(.account != null; "Say which income account the credit reverses.");
      assert(.date > realmConfig("closedThrough"); "That date is on or before the closing date, so the credit can't post.");
      .status = "posted";
      .postedBy = actor();
    `,
  } satisfies OperationDeclaration;
}

export class WriteOff extends LedgerDocument {
  static displayName = 'Write-off';
  static icon = BookIcon;
  @field invoiceNo = contains(StringField);
  @field customerId = contains(StringField);
  @field customer = linksTo(() => Customer);
  @field amountMinor = contains(NumberField);
  @field account = contains(StringField); // bad debt expense
  @field reason = contains(StringField);

  postings() {
    return [
      {
        account: this.account ?? '',
        debitMinor: this.amountMinor ?? 0,
        creditMinor: 0,
        party: this.customerId,
      },
      {
        account: AR,
        debitMinor: 0,
        creditMinor: this.amountMinor ?? 0,
        party: this.customerId,
        doc: this.invoiceNo,
      },
    ];
  }
  title() {
    return `Write-off of ${this.invoiceNo ?? ''}`;
  }
  party() {
    return this.customerId ?? '';
  }
  facts(): Fact[] {
    return [
      { key: 'Invoice', value: this.invoiceNo ?? '', mono: true },
      { key: 'Customer', value: this.customerId ?? '' },
      { key: 'Date', value: day(this.date) },
      { key: 'Reason', value: this.reason ?? '' },
      { key: 'Approved and posted by', value: this.postedBy ?? '' },
    ];
  }

  @operation static post = {
    base: 'transform',
    transformations: bxl`
      assert(if .status == null then true else .status == "draft" end; "Only a draft write-off can be posted. This one is already posted.");
      assert(.amountMinor > 0; "A write-off must be positive.");
      assert(.reason != null; "Say why the invoice is being written off.");
      assert(.account != null; "Say which expense account takes the write-off.");
      assert(.date > realmConfig("closedThrough"); "That date is on or before the closing date, so the write-off can't post.");
      .status = "posted";
      .postedBy = actor();
    `,
  } satisfies OperationDeclaration;
}

// ── invoices ─────────────────────────────────────────────────────────────────
export class Invoice extends LedgerDocument {
  static displayName = 'Invoice';
  static icon = BookIcon;
  static prefersWideFormat = false;
  @field customerId = contains(StringField);
  @field customer = linksTo(() => Customer);
  @field due = contains(IsoDateField);
  @field kind = contains(StringField); // 'sale', or 'opening' for one open at conversion
  @field lines = containsMany(SaleLine);
  @field agencyId = contains(StringField);
  @field taxRatePpm = contains(NumberField);
  @field taxMinor = contains(NumberField);
  @field paidMinor = contains(NumberField); // written only by applyPayment
  @field creditedMinor = contains(NumberField); // written only by applyCredit
  @field writtenOffMinor = contains(NumberField); // written only by applyWriteOff
  // A void never deletes: the invoice keeps its posting in its own month, and the void posts the
  // mirror entry into the journal month of the void date, in the same batch as `void`.
  @field voidDate = contains(IsoDateField); // written only by void
  @field voidedBy = contains(StringField);
  @field voidReason = contains(StringField);
  @field openMinor = contains(NumberField, {
    computeVia: function (this: Invoice) {
      return this.voidDate
        ? 0
        : (this.totalMinor ?? 0) -
            (this.paidMinor ?? 0) -
            (this.creditedMinor ?? 0) -
            (this.writtenOffMinor ?? 0);
    },
  });

  // An opening invoice's receivable was posted by the opening balances; the card tracks what's still owed.
  postings() {
    return this.kind === 'opening' ? [] : saleLines(this, AR);
  }
  total() {
    return (
      sum((this.lines ?? []).map((l) => l?.amountMinor)) + (this.taxMinor ?? 0)
    );
  }
  title() {
    return `Invoice ${this.docNo ?? ''}${this.customerId ? ' · ' + this.customerId : ''}`;
  }
  party() {
    return this.customerId ?? '';
  }
  state() {
    if (this.status !== 'posted') return 'Draft';
    if (this.voidDate) return 'Void';
    if ((this.writtenOffMinor ?? 0) > 0 && (this.openMinor ?? 0) <= 0)
      return 'Written off';
    return (this.openMinor ?? 0) <= 0
      ? 'Paid'
      : (this.paidMinor ?? 0) + (this.creditedMinor ?? 0) > 0
        ? 'Partial'
        : 'Open';
  }
  facts(): Fact[] {
    return [
      { key: 'Invoice no.', value: this.docNo ?? '', mono: true },
      { key: 'Customer', value: this.customerId ?? '' },
      { key: 'Date', value: day(this.date) },
      { key: 'Due', value: day(this.due) },
      ...(this.kind === 'opening'
        ? [
            {
              key: 'Opening',
              value: 'Owed at conversion; posted in the opening balances',
            },
          ]
        : []),
      { key: 'Paid', value: money(this.paidMinor) },
      ...((this.creditedMinor ?? 0)
        ? [{ key: 'Credited', value: money(this.creditedMinor) }]
        : []),
      ...((this.writtenOffMinor ?? 0)
        ? [{ key: 'Written off', value: money(this.writtenOffMinor) }]
        : []),
      { key: 'Open', value: money(this.openMinor), strong: true },
      { key: 'Posted by', value: this.postedBy ?? '' },
      ...(this.voidDate
        ? [
            {
              key: 'Voided',
              value: `${day(this.voidDate)} by ${this.voidedBy ?? ''}${this.voidReason ? ' · ' + this.voidReason : ''}`,
            },
          ]
        : []),
    ];
  }

  @operation static post = {
    base: 'transform',
    transformations: bxl`
      assert(if .status == null then true else .status == "draft" end; "Only a draft invoice can be posted. This one is already posted.");
      assert((.lines | length) > 0; "An invoice needs at least one line.");
      assert(([.lines[].amountMinor | type] | unique) == ["number"]; "Every line needs an amount.");
      assert([.lines[].amountMinor] | all(. > 0); "Every line needs a positive amount.");
      assert([.lines[].amountMinor | floor] == [.lines[].amountMinor]; "Amounts are in whole cents.");
      assert([.lines[] | select(.sku != null) | .priceMinor * .qty / 1000 | round] == [.lines[] | select(.sku != null) | .amountMinor]; "A product line's amount must be its price times its quantity.");
      assert([.lines[].account != null] | all; "Every line needs an income account.");
      assert([[.lines[].amountMinor * .taxRatePpm] | add / 1000000 | round] == [.taxMinor]; "The sales tax must be the tax rate times the amount.");
      assert(.date > realmConfig("closedThrough"); "That date is on or before the closing date, so the invoice can't post.");
      .status = "posted";
      .postedBy = actor();
    `,
  } satisfies OperationDeclaration;
  /** Record a customer payment against this invoice. Sent in the same batch as the payment's post. */
  @operation static applyPayment = {
    base: 'transform',
    params: {
      amountMinor: NumberField,
      paymentNo: StringField,
      customerId: StringField,
    },
    transformations: bxl`
      assert(.status == "posted"; "Only a posted invoice can be paid.");
      assert(.voidDate == null; "This invoice is void, so it can't be paid.");
      assert(params("customerId") == .customerId; "A payment pays only its own customer's invoices. This invoice belongs to someone else.");
      assert(params("amountMinor") > 0; "A payment amount must be positive.");
      assert([.lines[].amountMinor, .taxMinor] + [0 - .paidMinor - .creditedMinor - .writtenOffMinor - params("amountMinor")] | add | . >= 0; "That pays more than the invoice has open.");
      .paidMinor |= . + params("amountMinor");
    `,
  } satisfies OperationDeclaration;
  /** Record a credit memo against this invoice. Sent in the same batch as the memo's post. */
  @operation static applyCredit = {
    base: 'transform',
    params: {
      amountMinor: NumberField,
      docNo: StringField,
      customerId: StringField,
    },
    transformations: bxl`
      assert(.status == "posted"; "Only a posted invoice can be credited.");
      assert(.voidDate == null; "This invoice is void, so it can't be credited.");
      assert(params("customerId") == .customerId; "A credit applies only to its own customer's invoices. This invoice belongs to someone else.");
      assert(params("amountMinor") > 0; "A credit must be positive.");
      assert([.lines[].amountMinor, .taxMinor] + [0 - .paidMinor - .creditedMinor - .writtenOffMinor - params("amountMinor")] | add | . >= 0; "That credits more than the invoice has open.");
      .creditedMinor |= . + params("amountMinor");
    `,
  } satisfies OperationDeclaration;
  /** Write off what's left. The amount must be exactly what's open. Sent with the write-off's post. */
  @operation static applyWriteOff = {
    base: 'transform',
    params: {
      amountMinor: NumberField,
      docNo: StringField,
      customerId: StringField,
    },
    transformations: bxl`
      assert(.status == "posted"; "Only a posted invoice can be written off.");
      assert(.voidDate == null; "This invoice is void, so there's nothing to write off.");
      assert(params("customerId") == .customerId; "A write-off applies only to its own customer's invoices. This invoice belongs to someone else.");
      assert([.lines[].amountMinor, .taxMinor] + [0 - .paidMinor - .creditedMinor - .writtenOffMinor - params("amountMinor")] | add | . == 0; "A write-off must be exactly what the invoice has open.");
      .writtenOffMinor |= . + params("amountMinor");
    `,
  } satisfies OperationDeclaration;
  /** Take back a payment, when the payment's posting is reversed. Sent in the same batch as the reversal. */
  @operation static unapplyPayment = {
    base: 'transform',
    params: {
      amountMinor: NumberField,
      paymentNo: StringField,
      customerId: StringField,
    },
    transformations: bxl`
      assert(params("customerId") == .customerId; "That payment wasn't this customer's.");
      assert(params("amountMinor") > 0; "The amount taken back must be positive.");
      assert([.paidMinor - params("amountMinor")] | all(. >= 0); "That takes back more than was paid on this invoice.");
      .paidMinor |= . - params("amountMinor");
    `,
  } satisfies OperationDeclaration;
  /** Take back a credit memo, when its posting is reversed. */
  @operation static unapplyCredit = {
    base: 'transform',
    params: {
      amountMinor: NumberField,
      docNo: StringField,
      customerId: StringField,
    },
    transformations: bxl`
      assert(params("customerId") == .customerId; "That credit wasn't this customer's.");
      assert(params("amountMinor") > 0; "The amount taken back must be positive.");
      assert([.creditedMinor - params("amountMinor")] | all(. >= 0); "That takes back more than was credited on this invoice.");
      .creditedMinor |= . - params("amountMinor");
    `,
  } satisfies OperationDeclaration;
  /** Take back a write-off, when its posting is reversed. */
  @operation static unapplyWriteOff = {
    base: 'transform',
    params: {
      amountMinor: NumberField,
      docNo: StringField,
      customerId: StringField,
    },
    transformations: bxl`
      assert(params("customerId") == .customerId; "That write-off wasn't this customer's.");
      assert(params("amountMinor") > 0; "The amount taken back must be positive.");
      assert([.writtenOffMinor - params("amountMinor")] | all(. >= 0); "That takes back more than was written off on this invoice.");
      .writtenOffMinor |= . - params("amountMinor");
    `,
  } satisfies OperationDeclaration;
  /**
   * Void the invoice. Nothing is deleted: the invoice keeps its posting, and the same batch posts the
   * mirror entry into the journal month of the void date. Refused while anything is applied to it
   * (reverse those first), for an invoice owed at conversion (write it off instead), and on or
   * before the closing date.
   */
  @operation static void = {
    base: 'transform',
    params: { date: StringField, reason: StringField },
    transformations: bxl`
      assert(.status == "posted"; "Only a posted invoice can be voided. Delete a draft instead.");
      assert(.voidDate == null; "This invoice is already void.");
      assert(.kind != "opening"; "This invoice was owed at conversion and posted in the opening balances. Write it off instead.");
      assert([.paidMinor + 0, .creditedMinor + 0, .writtenOffMinor + 0] | all(. == 0); "Payments, credits or write-offs are applied to this invoice. Reverse them first, then void it.");
      assert(params("date") >= .date; "A void can't be dated before the invoice.");
      assert(params("date") > realmConfig("closedThrough"); "That date is on or before the closing date. Void it in an open month.");
      assert(params("reason") != null; "Say why the invoice is void.");
      assert(params("reason") != ""; "Say why the invoice is void.");
      .voidDate = params("date");
      .voidReason = params("reason");
      .voidedBy = actor();
    `,
  } satisfies OperationDeclaration;
  /** Draft a credit memo against this invoice; CreditMemo.post checks it. */
  @operation static enterCredit = {
    base: 'create',
    of: CreditMemo,
    params: {
      docNo: StringField,
      date: StringField,
      amountMinor: NumberField,
      account: StringField,
      cls: StringField,
      memo: StringField,
    },
    fill: {
      docNo: params('docNo'),
      date: params('date'),
      amountMinor: params('amountMinor'),
      account: params('account'),
      cls: params('cls'),
      memo: params('memo'),
      invoiceNo: instance('docNo'),
      customerId: instance('customerId'),
      status: 'draft',
      enteredBy: actor(),
    },
  } satisfies OperationDeclaration;
  /** Draft a write-off of this invoice; WriteOff.post checks it. */
  @operation static enterWriteOff = {
    base: 'create',
    of: WriteOff,
    params: {
      docNo: StringField,
      date: StringField,
      amountMinor: NumberField,
      account: StringField,
      reason: StringField,
    },
    fill: {
      docNo: params('docNo'),
      date: params('date'),
      amountMinor: params('amountMinor'),
      account: params('account'),
      reason: params('reason'),
      memo: params('reason'),
      invoiceNo: instance('docNo'),
      customerId: instance('customerId'),
      status: 'draft',
      enteredBy: actor(),
    },
  } satisfies OperationDeclaration;
}

// ── sales receipts: paid at the time of sale ────────────────────────────────
export class SalesReceipt extends LedgerDocument {
  static displayName = 'Sales receipt';
  static icon = BookIcon;
  @field customerId = contains(StringField);
  @field customer = linksTo(() => Customer);
  @field lines = containsMany(SaleLine);
  @field agencyId = contains(StringField);
  @field taxRatePpm = contains(NumberField);
  @field taxMinor = contains(NumberField);
  @field depositTo = contains(StringField); // the clearing account the money waits in (1010)
  @field depositNo = contains(StringField); // written only by markDeposited

  postings() {
    return saleLines(this, this.depositTo ?? '');
  }
  total() {
    return (
      sum((this.lines ?? []).map((l) => l?.amountMinor)) + (this.taxMinor ?? 0)
    );
  }
  title() {
    return `Sales receipt ${this.docNo ?? ''}`;
  }
  party() {
    return this.customerId ?? '';
  }
  state() {
    return this.status !== 'posted'
      ? 'Draft'
      : this.depositNo
        ? 'Deposited'
        : 'Undeposited';
  }
  facts(): Fact[] {
    let l = (this.lines ?? []).filter(Boolean)[0];
    return [
      { key: 'Receipt no.', value: this.docNo ?? '', mono: true },
      { key: 'Customer', value: this.customerId ?? '' },
      { key: 'Date', value: day(this.date) },
      ...(l?.sku
        ? [{ key: 'Product', value: `${l.sku} × ${(l.qty ?? 0) / 1000}` }]
        : []),
      ...((this.taxMinor ?? 0)
        ? [
            {
              key: 'Sales tax',
              value: `${money(this.taxMinor)} (${(this.taxRatePpm ?? 0) / 10000}% · ${this.agencyId ?? ''})`,
            },
          ]
        : []),
      { key: 'Deposited in', value: this.depositNo ?? 'Not yet' },
      { key: 'Posted by', value: this.postedBy ?? '' },
    ];
  }

  @operation static post = {
    base: 'transform',
    transformations: bxl`
      assert(if .status == null then true else .status == "draft" end; "Only a draft sales receipt can be posted. This one is already posted.");
      assert((.lines | length) > 0; "A sales receipt needs at least one line.");
      assert(([.lines[].amountMinor | type] | unique) == ["number"]; "Every line needs an amount.");
      assert([.lines[].amountMinor] | all(. > 0); "Every line needs a positive amount.");
      assert([.lines[].amountMinor | floor] == [.lines[].amountMinor]; "Amounts are in whole cents.");
      assert([.lines[] | select(.sku != null) | .priceMinor * .qty / 1000 | round] == [.lines[] | select(.sku != null) | .amountMinor]; "A product line's amount must be its price times its quantity.");
      assert([.lines[].account != null] | all; "Every line needs an income account.");
      assert([[.lines[].amountMinor * .taxRatePpm] | add / 1000000 | round] == [.taxMinor]; "The sales tax must be the tax rate times the amount.");
      assert(.depositTo != null; "Say which account the money is held in until it's deposited.");
      assert(.date > realmConfig("closedThrough"); "That date is on or before the closing date, so the receipt can't post.");
      .status = "posted";
      .postedBy = actor();
    `,
  } satisfies OperationDeclaration;
  /** Mark this receipt deposited. The deposit must carry exactly its total, and only once. */
  @operation static markDeposited = {
    base: 'transform',
    params: { depositNo: StringField, amountMinor: NumberField },
    transformations: bxl`
      assert(.status == "posted"; "Only a posted sales receipt can be deposited.");
      assert(.depositNo == null; "This sales receipt is already deposited.");
      assert([.lines[].amountMinor, .taxMinor] + [0 - params("amountMinor")] | add | . == 0; "A deposit must carry the receipt's full amount.");
      .depositNo = params("depositNo");
    `,
  } satisfies OperationDeclaration;
}

// ── customer payments: money received against invoices ──────────────────────
export class CustomerPayment extends LedgerDocument {
  static displayName = 'Customer payment';
  static icon = BookIcon;
  @field customerId = contains(StringField);
  @field customer = linksTo(() => Customer);
  @field depositTo = contains(StringField);
  @field applications = containsMany(InvoiceApplication);
  @field depositNo = contains(StringField); // written only by markDeposited

  postings() {
    let apps = (this.applications ?? []).filter(
      (a) => a && (a.amountMinor ?? 0) > 0,
    );
    return [
      ...apps.map((a) => ({
        account: AR,
        debitMinor: 0,
        creditMinor: a.amountMinor,
        party: this.customerId,
        doc: a.invoiceNo,
      })),
      {
        account: this.depositTo ?? '',
        debitMinor: sum(apps.map((a) => a.amountMinor)),
        creditMinor: 0,
        party: this.customerId,
        doc: this.docNo,
      },
    ];
  }
  title() {
    return `Payment ${this.docNo ?? ''}${this.customerId ? ' · ' + this.customerId : ''}`;
  }
  party() {
    return this.customerId ?? '';
  }
  state() {
    return this.status !== 'posted'
      ? 'Draft'
      : this.depositNo
        ? 'Deposited'
        : 'Undeposited';
  }
  facts(): Fact[] {
    return [
      { key: 'Payment no.', value: this.docNo ?? '', mono: true },
      { key: 'Customer', value: this.customerId ?? '' },
      { key: 'Received', value: day(this.date) },
      ...(this.applications ?? [])
        .filter(Boolean)
        .map((a) => ({ key: a.invoiceNo ?? '', value: money(a.amountMinor) })),
      { key: 'Deposited in', value: this.depositNo ?? 'Not yet' },
      { key: 'Posted by', value: this.postedBy ?? '' },
    ];
  }

  @operation static post = {
    base: 'transform',
    transformations: bxl`
      assert(if .status == null then true else .status == "draft" end; "Only a draft payment can be posted. This one is already posted.");
      assert((.applications | length) > 0; "A payment has to pay at least one invoice.");
      assert(([.applications[].amountMinor | type] | unique) == ["number"]; "Every invoice paid needs an amount.");
      assert([.applications[].amountMinor] | all(. > 0); "Every amount paid must be positive.");
      assert([.applications[].amountMinor | floor] == [.applications[].amountMinor]; "Amounts are in whole cents.");
      assert(.depositTo != null; "Say which account the money is held in until it's deposited.");
      assert(.date > realmConfig("closedThrough"); "That date is on or before the closing date, so the payment can't post.");
      .status = "posted";
      .postedBy = actor();
    `,
  } satisfies OperationDeclaration;
  @operation static markDeposited = {
    base: 'transform',
    params: { depositNo: StringField, amountMinor: NumberField },
    transformations: bxl`
      assert(.status == "posted"; "Only a posted payment can be deposited.");
      assert(.depositNo == null; "This payment is already deposited.");
      assert([.applications[].amountMinor] + [0 - params("amountMinor")] | add | . == 0; "A deposit must carry the payment's full amount.");
      .depositNo = params("depositNo");
    `,
  } satisfies OperationDeclaration;
}

// ── deposits and processor payouts: money moving from clearing to the bank ──
export class Deposit extends LedgerDocument {
  static displayName = 'Deposit';
  static icon = BookIcon;
  @field bank = contains(StringField); // the bank account it lands in
  @field clearingAccount = contains(StringField); // where the items waited (1010)
  @field processor = contains(StringField); // Square, Shopify Payments, … or empty for a bank deposit
  @field items = containsMany(DepositItem);
  @field feeMinor = contains(NumberField); // what a processor kept
  @field feeAccount = contains(StringField);
  @field cls = contains(StringField);
  @field loc = contains(StringField);
  @field grossMinor = contains(NumberField, {
    computeVia: function (this: Deposit) {
      return sum((this.items ?? []).map((i) => i?.amountMinor));
    },
  });

  postings() {
    let gross = this.grossMinor ?? 0,
      fee = this.feeMinor ?? 0;
    return [
      {
        account: this.bank ?? '',
        debitMinor: gross - fee,
        creditMinor: 0,
        doc: this.docNo,
      },
      ...(fee > 0
        ? [
            {
              account: this.feeAccount ?? '',
              debitMinor: fee,
              creditMinor: 0,
              cls: this.cls,
              loc: this.loc,
            },
          ]
        : []),
      {
        account: this.clearingAccount ?? '',
        debitMinor: 0,
        creditMinor: gross,
        doc: this.docNo,
      },
    ];
  }
  title() {
    return this.processor
      ? `${this.processor} payout ${this.docNo ?? ''}`
      : `Deposit ${this.docNo ?? ''}`;
  }
  party() {
    return this.processor ?? this.bank ?? '';
  }
  facts(): Fact[] {
    return [
      {
        key: this.processor ? 'Payout no.' : 'Deposit no.',
        value: this.docNo ?? '',
        mono: true,
      },
      { key: 'Date', value: day(this.date) },
      { key: 'Into', value: this.bank ?? '' },
      ...(this.items ?? [])
        .filter(Boolean)
        .map((i) => ({ key: i.docNo ?? '', value: money(i.amountMinor) })),
      ...((this.feeMinor ?? 0)
        ? [
            { key: 'Processor fee', value: money(this.feeMinor) },
            {
              key: 'Net to bank',
              value: money((this.grossMinor ?? 0) - (this.feeMinor ?? 0)),
              strong: true,
            },
          ]
        : []),
      { key: 'Posted by', value: this.postedBy ?? '' },
    ];
  }

  /** Post a deposit. Sent in one batch with markDeposited on each item, so nothing is deposited twice. */
  @operation static post = {
    base: 'transform',
    transformations: bxl`
      assert(if .status == null then true else .status == "draft" end; "Only a draft deposit can be posted. This one is already posted.");
      assert((.items | length) > 0; "A deposit needs at least one payment or receipt.");
      assert(([.items[].amountMinor | type] | unique) == ["number"]; "Every item needs an amount.");
      assert([.items[].amountMinor] | all(. > 0); "Every item needs a positive amount.");
      assert([.items[].amountMinor, .feeMinor | floor] == [.items[].amountMinor, .feeMinor]; "Amounts are in whole cents.");
      assert(.feeMinor >= 0; "A fee can't be negative.");
      assert([.items[].amountMinor] + [0 - .feeMinor] | add | . > 0; "The fee can't be more than the deposit.");
      assert(.bank != null; "Say which bank account it lands in.");
      assert(.date > realmConfig("closedThrough"); "That date is on or before the closing date, so the deposit can't post.");
      .status = "posted";
      .postedBy = actor();
    `,
  } satisfies OperationDeclaration;
}

// ── customers: where sales are entered from ─────────────────────────────────
// The matrix customer (CRM Account), plus the key the ledger knows it by and
// the sales-tax and channel facts invoicing needs.
export class Customer extends Account {
  static displayName = 'Customer';
  @field customerId = contains(StringField);
  @field channel = contains(StringField); // wholesale, retail, dtc
  @field taxable = contains(BooleanField);
  @field shipState = contains(StringField);

  /** Draft an invoice to this customer; Invoice.post checks it. */
  @operation static enterInvoice = {
    base: 'create',
    of: Invoice,
    params: {
      docNo: StringField,
      date: StringField,
      due: StringField,
      kind: StringField,
      memo: StringField,
      lines: SaleLine,
      agencyId: StringField,
      taxRatePpm: NumberField,
      taxMinor: NumberField,
    },
    fill: {
      docNo: params('docNo'),
      date: params('date'),
      due: params('due'),
      kind: params('kind'),
      memo: params('memo'),
      lines: params('lines'),
      agencyId: params('agencyId'),
      taxRatePpm: params('taxRatePpm'),
      taxMinor: params('taxMinor'),
      customerId: instance('customerId'),
      status: 'draft',
      enteredBy: actor(),
      paidMinor: 0,
      creditedMinor: 0,
      writtenOffMinor: 0,
    },
  } satisfies OperationDeclaration;
  /** Draft a sales receipt (paid at the time of sale); SalesReceipt.post checks it. */
  @operation static enterSalesReceipt = {
    base: 'create',
    of: SalesReceipt,
    params: {
      docNo: StringField,
      date: StringField,
      memo: StringField,
      lines: SaleLine,
      agencyId: StringField,
      taxRatePpm: NumberField,
      taxMinor: NumberField,
      depositTo: StringField,
    },
    fill: {
      docNo: params('docNo'),
      date: params('date'),
      memo: params('memo'),
      lines: params('lines'),
      agencyId: params('agencyId'),
      taxRatePpm: params('taxRatePpm'),
      taxMinor: params('taxMinor'),
      depositTo: params('depositTo'),
      customerId: instance('customerId'),
      status: 'draft',
      enteredBy: actor(),
    },
  } satisfies OperationDeclaration;
  /** Draft a payment received from this customer; CustomerPayment.post checks it. */
  @operation static receivePayment = {
    base: 'create',
    of: CustomerPayment,
    params: {
      docNo: StringField,
      date: StringField,
      memo: StringField,
      depositTo: StringField,
      applications: InvoiceApplication,
    },
    fill: {
      docNo: params('docNo'),
      date: params('date'),
      memo: params('memo'),
      depositTo: params('depositTo'),
      applications: params('applications'),
      customerId: instance('customerId'),
      status: 'draft',
      enteredBy: actor(),
    },
  } satisfies OperationDeclaration;
}
