// Payroll, bank and card activity, and the remaining entries, card-native: payroll runs, liability
// and tax payments, transfers, card charges, loan payments, asset disposals, vendor credits, journal
// entries, scheduled entries (prepaids, deferred revenue, accruals) and depreciation runs.
// Each is a LedgerDocument entered as a draft and posted by an operation the realm runs, which
// checks that it balances and adds up before stamping who posted it.
import {
  FieldDef,
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
import { LedgerDocument, type PostingInput } from './ledger-document';
import { money, day, type Fact } from './record-kit';
import { IsoMonthField } from './ledger-dates';

const posted = (d: { postedBy?: string }): Fact => ({
  key: 'Posted by',
  value: d.postedBy ?? '',
});

/** A journal line: a debit or a credit on one account. */
export class EntryLine extends FieldDef {
  static displayName = 'Entry line';
  @field account = contains(StringField);
  @field debitMinor = contains(NumberField);
  @field creditMinor = contains(NumberField);
  @field cls = contains(StringField);
  @field loc = contains(StringField);
  @field party = contains(StringField);
  @field doc = contains(StringField);
}
/** An amount on one account (a wage line, an asset's depreciation). */
export class AmountLine extends FieldDef {
  static displayName = 'Amount';
  @field account = contains(StringField);
  @field label = contains(StringField);
  @field amountMinor = contains(NumberField);
  @field cls = contains(StringField);
  @field loc = contains(StringField);
}
const asPostings = (
  lines: (EntryLine | undefined)[] | undefined,
): PostingInput[] =>
  (lines ?? []).filter(Boolean).map((l) => ({
    account: l!.account,
    debitMinor: l!.debitMinor ?? 0,
    creditMinor: l!.creditMinor ?? 0,
    cls: l!.cls,
    loc: l!.loc,
    party: l!.party,
    doc: l!.doc,
  }));

// ── payroll ──────────────────────────────────────────────────────────────────
export class PayrollRun extends LedgerDocument {
  static displayName = 'Payroll run';
  static icon = BookIcon;
  @field provider = contains(StringField); // Gusto
  @field bank = contains(StringField); // where net pay comes from
  @field wages = containsMany(AmountLine); // gross wages by expense account
  @field employerTaxMinor = contains(NumberField);
  @field employerTaxAccount = contains(StringField);
  @field withholdingMinor = contains(NumberField); // held back from wages, owed to agencies
  @field deductionsMinor = contains(NumberField); // benefits and other deductions, owed onward
  @field netMinor = contains(NumberField); // paid to employees
  @field liabilityAccount = contains(StringField); // payroll liabilities (2300)

  postings(): PostingInput[] {
    return [
      ...(this.wages ?? []).filter(Boolean).map((w) => ({
        account: w.account,
        debitMinor: w.amountMinor ?? 0,
        creditMinor: 0,
        cls: w.cls,
        loc: w.loc,
      })),
      {
        account: this.employerTaxAccount ?? '',
        debitMinor: this.employerTaxMinor ?? 0,
        creditMinor: 0,
      },
      {
        account: this.liabilityAccount ?? '',
        debitMinor: 0,
        creditMinor:
          (this.withholdingMinor ?? 0) +
          (this.deductionsMinor ?? 0) +
          (this.employerTaxMinor ?? 0),
      },
      {
        account: this.bank ?? '',
        debitMinor: 0,
        creditMinor: this.netMinor ?? 0,
      },
    ];
  }
  title() {
    return `Payroll ${this.docNo ?? ''}`;
  }
  party() {
    return this.provider ?? '';
  }
  facts(): Fact[] {
    return [
      { key: 'Sync', value: this.docNo ?? '', mono: true },
      { key: 'From', value: this.provider ?? '' },
      { key: 'Pay date', value: day(this.date) },
      ...(this.wages ?? []).filter(Boolean).map((w) => ({
        key: `Wages · ${w!.label ?? w!.account}`,
        value: money(w!.amountMinor),
      })),
      { key: 'Withheld', value: money(this.withholdingMinor) },
      { key: 'Deductions', value: money(this.deductionsMinor) },
      { key: 'Net pay', value: money(this.netMinor), strong: true },
      { key: 'Employer taxes', value: money(this.employerTaxMinor) },
      posted(this),
    ];
  }
  @operation static post = {
    base: 'transform',
    transformations: bxl`
      assert(if .status == null then true else .status == "draft" end; "Only a draft payroll run can be posted. This one is already posted.");
      assert((.wages | length) > 0; "A payroll run needs wages.");
      assert([.wages[].amountMinor, .employerTaxMinor, .withholdingMinor, .deductionsMinor, .netMinor] | all(. >= 0); "Payroll amounts can't be negative.");
      assert([.wages[].amountMinor] + [0 - .netMinor - .withholdingMinor - .deductionsMinor] | add | . == 0; "Gross wages must equal net pay plus what was withheld and deducted.");
      assert([.bank, .liabilityAccount, .employerTaxAccount] | all(. != null); "Say which bank pays and which accounts take the taxes.");
      assert(.date > realmConfig("closedThrough"); "That date is on or before the closing date, so it can't post.");
      .status = "posted";
      .postedBy = actor();
    `,
  } satisfies OperationDeclaration;
}

// ── money out of the bank to settle something ───────────────────────────────
/** A payroll tax remittance, a sales tax payment or an owner's estimated-tax draw. */
export class BankPayment extends LedgerDocument {
  static displayName = 'Bank payment';
  static icon = BookIcon;
  @field kind = contains(StringField); // payroll remittance, sales tax, owner draw
  @field bank = contains(StringField);
  @field account = contains(StringField); // the liability or equity account it settles
  @field payee = contains(StringField);
  @field period = contains(StringField); // the quarter or period it covers
  @field amountMinor = contains(NumberField);

  postings(): PostingInput[] {
    return [
      {
        account: this.account ?? '',
        debitMinor: this.amountMinor ?? 0,
        creditMinor: 0,
        party: this.payee,
      },
      {
        account: this.bank ?? '',
        debitMinor: 0,
        creditMinor: this.amountMinor ?? 0,
      },
    ];
  }
  title() {
    return `${this.kind ? this.kind[0].toUpperCase() + this.kind.slice(1) : 'Payment'} ${this.docNo ?? ''}`;
  }
  party() {
    return this.payee ?? this.kind ?? '';
  }
  facts(): Fact[] {
    return [
      { key: 'Payment', value: this.docNo ?? '', mono: true },
      { key: 'Kind', value: this.kind ?? '' },
      { key: 'Date', value: day(this.date) },
      ...(this.payee ? [{ key: 'Paid to', value: this.payee }] : []),
      ...(this.period ? [{ key: 'Covers', value: this.period }] : []),
      { key: 'From', value: this.bank ?? '' },
      posted(this),
    ];
  }
  @operation static post = {
    base: 'transform',
    transformations: bxl`
      assert(if .status == null then true else .status == "draft" end; "Only a draft payment can be posted. This one is already posted.");
      assert(.amountMinor > 0; "A payment must be positive.");
      assert([.amountMinor | floor] == [.amountMinor]; "Amounts are in whole cents.");
      assert([.bank, .account] | all(. != null); "Say which bank pays and which account it settles.");
      assert(.date > realmConfig("closedThrough"); "That date is on or before the closing date, so it can't post.");
      .status = "posted";
      .postedBy = actor();
    `,
  } satisfies OperationDeclaration;
}

export class Transfer extends LedgerDocument {
  static displayName = 'Transfer';
  static icon = BookIcon;
  @field fromAccount = contains(StringField);
  @field toAccount = contains(StringField);
  @field amountMinor = contains(NumberField);

  postings(): PostingInput[] {
    return [
      {
        account: this.toAccount ?? '',
        debitMinor: this.amountMinor ?? 0,
        creditMinor: 0,
      },
      {
        account: this.fromAccount ?? '',
        debitMinor: 0,
        creditMinor: this.amountMinor ?? 0,
      },
    ];
  }
  title() {
    return `Transfer ${this.docNo ?? ''}`;
  }
  facts(): Fact[] {
    return [
      { key: 'Transfer', value: this.docNo ?? '', mono: true },
      { key: 'Date', value: day(this.date) },
      { key: 'From', value: this.fromAccount ?? '' },
      { key: 'To', value: this.toAccount ?? '' },
      posted(this),
    ];
  }
  @operation static post = {
    base: 'transform',
    transformations: bxl`
      assert(if .status == null then true else .status == "draft" end; "Only a draft transfer can be posted. This one is already posted.");
      assert(.amountMinor > 0; "A transfer must be positive.");
      assert(.fromAccount != .toAccount; "A transfer moves money between two different accounts.");
      assert(.date > realmConfig("closedThrough"); "That date is on or before the closing date, so it can't post.");
      .status = "posted";
      .postedBy = actor();
    `,
  } satisfies OperationDeclaration;
}

export class CardCharge extends LedgerDocument {
  static displayName = 'Card charge';
  static icon = BookIcon;
  @field card = contains(StringField); // the credit card account (2100)
  @field account = contains(StringField); // the expense
  @field vendor = contains(StringField);
  @field amountMinor = contains(NumberField);
  @field cls = contains(StringField);
  @field support = contains(StringField); // the receipt on file

  postings(): PostingInput[] {
    return [
      {
        account: this.account ?? '',
        debitMinor: this.amountMinor ?? 0,
        creditMinor: 0,
        cls: this.cls,
        party: this.vendor,
      },
      {
        account: this.card ?? '',
        debitMinor: 0,
        creditMinor: this.amountMinor ?? 0,
      },
    ];
  }
  title() {
    return `Card charge ${this.docNo ?? ''}`;
  }
  party() {
    return this.vendor ?? '';
  }
  facts(): Fact[] {
    return [
      { key: 'Charge', value: this.docNo ?? '', mono: true },
      { key: 'Vendor', value: this.vendor ?? '' },
      { key: 'Date', value: day(this.date) },
      { key: 'Expense', value: this.account ?? '' },
      { key: 'Receipt', value: this.support ?? 'None on file' },
      posted(this),
    ];
  }
  @operation static post = {
    base: 'transform',
    transformations: bxl`
      assert(if .status == null then true else .status == "draft" end; "Only a draft card charge can be posted. This one is already posted.");
      assert(.amountMinor > 0; "A charge must be positive.");
      assert(.support != null; "Every card charge needs its receipt.");
      assert([.card, .account] | all(. != null); "Say which card and which expense account.");
      assert(.date > realmConfig("closedThrough"); "That date is on or before the closing date, so it can't post.");
      .status = "posted";
      .postedBy = actor();
    `,
  } satisfies OperationDeclaration;
}

export class LoanPayment extends LedgerDocument {
  static displayName = 'Loan payment';
  static icon = BookIcon;
  @field loan = contains(StringField);
  @field bank = contains(StringField);
  @field amountMinor = contains(NumberField);
  @field principalMinor = contains(NumberField);
  @field interestMinor = contains(NumberField);
  @field loanAccount = contains(StringField); // 2500
  @field interestAccount = contains(StringField); // 6600

  postings(): PostingInput[] {
    return [
      {
        account: this.loanAccount ?? '',
        debitMinor: this.principalMinor ?? 0,
        creditMinor: 0,
      },
      {
        account: this.interestAccount ?? '',
        debitMinor: this.interestMinor ?? 0,
        creditMinor: 0,
      },
      {
        account: this.bank ?? '',
        debitMinor: 0,
        creditMinor: this.amountMinor ?? 0,
      },
    ];
  }
  title() {
    return `Loan payment ${this.docNo ?? ''}`;
  }
  party() {
    return this.loan ?? '';
  }
  facts(): Fact[] {
    return [
      { key: 'Payment', value: this.docNo ?? '', mono: true },
      { key: 'Loan', value: this.loan ?? '', mono: true },
      { key: 'Date', value: day(this.date) },
      { key: 'Principal', value: money(this.principalMinor) },
      { key: 'Interest', value: money(this.interestMinor) },
      posted(this),
    ];
  }
  @operation static post = {
    base: 'transform',
    transformations: bxl`
      assert(if .status == null then true else .status == "draft" end; "Only a draft loan payment can be posted. This one is already posted.");
      assert([.principalMinor, .interestMinor] | all(. >= 0); "Principal and interest can't be negative.");
      assert([.principalMinor + .interestMinor] == [.amountMinor]; "Principal and interest must add up to the payment.");
      assert(.date > realmConfig("closedThrough"); "That date is on or before the closing date, so it can't post.");
      .status = "posted";
      .postedBy = actor();
    `,
  } satisfies OperationDeclaration;
}

export class AssetDisposal extends LedgerDocument {
  static displayName = 'Asset disposal';
  static icon = BookIcon;
  @field asset = contains(StringField);
  @field bank = contains(StringField);
  @field proceedsMinor = contains(NumberField);
  @field costMinor = contains(NumberField);
  @field accumulatedMinor = contains(NumberField); // depreciation taken to date
  @field assetAccount = contains(StringField); // 1500
  @field accumulatedAccount = contains(StringField); // 1510
  @field gainLossAccount = contains(StringField); // 7900

  postings(): PostingInput[] {
    let loss =
      (this.costMinor ?? 0) -
      (this.accumulatedMinor ?? 0) -
      (this.proceedsMinor ?? 0);
    return [
      ...((this.proceedsMinor ?? 0)
        ? [
            {
              account: this.bank ?? '',
              debitMinor: this.proceedsMinor ?? 0,
              creditMinor: 0,
            },
          ]
        : []),
      {
        account: this.accumulatedAccount ?? '',
        debitMinor: this.accumulatedMinor ?? 0,
        creditMinor: 0,
      },
      {
        account: this.assetAccount ?? '',
        debitMinor: 0,
        creditMinor: this.costMinor ?? 0,
      },
      ...(loss
        ? [
            {
              account: this.gainLossAccount ?? '',
              debitMinor: Math.max(0, loss),
              creditMinor: Math.max(0, -loss),
            },
          ]
        : []),
    ];
  }
  title() {
    return `Disposal of ${this.asset ?? ''}`;
  }
  party() {
    return this.asset ?? '';
  }
  facts(): Fact[] {
    let loss =
      (this.costMinor ?? 0) -
      (this.accumulatedMinor ?? 0) -
      (this.proceedsMinor ?? 0);
    return [
      { key: 'Asset', value: this.asset ?? '', strong: true, mono: true },
      { key: 'Date', value: day(this.date) },
      { key: 'Cost', value: money(this.costMinor) },
      { key: 'Depreciation to date', value: money(this.accumulatedMinor) },
      { key: 'Proceeds', value: money(this.proceedsMinor) },
      {
        key: loss >= 0 ? 'Loss' : 'Gain',
        value: money(Math.abs(loss)),
        strong: true,
      },
      posted(this),
    ];
  }
  @operation static post = {
    base: 'transform',
    transformations: bxl`
      assert(if .status == null then true else .status == "draft" end; "Only a draft disposal can be posted. This one is already posted.");
      assert([.costMinor, .accumulatedMinor, .proceedsMinor] | all(. >= 0); "Amounts can't be negative.");
      assert([.costMinor] + [0 - .accumulatedMinor] | add | . >= 0; "Depreciation can't exceed the asset's cost.");
      assert(.date > realmConfig("closedThrough"); "That date is on or before the closing date, so it can't post.");
      .status = "posted";
      .postedBy = actor();
    `,
  } satisfies OperationDeclaration;
}

/** A vendor's credit, applied to one of their bills. Posted with Bill.applyPayment on that bill. */
export class VendorCredit extends LedgerDocument {
  static displayName = 'Vendor credit';
  static icon = BookIcon;
  @field vendorId = contains(StringField);
  @field billNo = contains(StringField); // the bill it's applied to
  @field account = contains(StringField); // what it reduces
  @field amountMinor = contains(NumberField);

  postings(): PostingInput[] {
    return [
      {
        account: '2000',
        debitMinor: this.amountMinor ?? 0,
        creditMinor: 0,
        party: this.vendorId,
        doc: this.docNo,
      },
      {
        account: this.account ?? '',
        debitMinor: 0,
        creditMinor: this.amountMinor ?? 0,
      },
    ];
  }
  title() {
    return `Vendor credit ${this.docNo ?? ''}`;
  }
  party() {
    return this.vendorId ?? '';
  }
  facts(): Fact[] {
    return [
      { key: 'Credit', value: this.docNo ?? '', mono: true },
      { key: 'Vendor', value: this.vendorId ?? '' },
      { key: 'Date', value: day(this.date) },
      { key: 'Applied to', value: this.billNo ?? '' },
      posted(this),
    ];
  }
  @operation static post = {
    base: 'transform',
    transformations: bxl`
      assert(if .status == null then true else .status == "draft" end; "Only a draft vendor credit can be posted. This one is already posted.");
      assert(.amountMinor > 0; "A credit must be positive.");
      assert([.billNo, .vendorId] | all(. != null); "Say which vendor and which bill the credit applies to.");
      assert(.date > realmConfig("closedThrough"); "That date is on or before the closing date, so it can't post.");
      .status = "posted";
      .postedBy = actor();
    `,
  } satisfies OperationDeclaration;
}

// ── entries made of journal lines ───────────────────────────────────────────
export class JournalEntry extends LedgerDocument {
  static displayName = 'Journal entry';
  static icon = BookIcon;
  @field lines = containsMany(EntryLine);
  @field preparer = contains(StringField);
  @field reviewer = contains(StringField);
  @field support = contains(StringField);

  postings() {
    return asPostings(this.lines);
  }
  title() {
    return `Journal entry ${this.docNo ?? ''}`;
  }
  facts(): Fact[] {
    return [
      { key: 'Entry', value: this.docNo ?? '', mono: true },
      { key: 'Date', value: day(this.date) },
      { key: 'Prepared by', value: this.preparer ?? '' },
      { key: 'Reviewed by', value: this.reviewer ?? '' },
      ...(this.support ? [{ key: 'Support', value: this.support }] : []),
      posted(this),
    ];
  }
  @operation static post = {
    base: 'transform',
    transformations: bxl`
      assert(if .status == null then true else .status == "draft" end; "Only a draft journal entry can be posted. This one is already posted.");
      assert((.lines | length) > 1; "An entry needs at least two lines.");
      assert(([.lines[].debitMinor, .lines[].creditMinor | type] | unique) == ["number"]; "Every line needs a debit and a credit amount (one of them zero).");
      assert([.lines[] | .debitMinor * .creditMinor] | all(. == 0); "A line is a debit or a credit, not both.");
      assert([.lines[] | .debitMinor + .creditMinor] | all(. > 0); "Every line needs an amount.");
      assert([.lines[].debitMinor, .lines[].creditMinor] | all(. >= 0); "Amounts can't be negative.");
      assert([.lines[].debitMinor, .lines[].creditMinor | floor] == [.lines[].debitMinor, .lines[].creditMinor]; "Amounts are in whole cents.");
      assert([.lines[].debitMinor] + [.lines[].creditMinor | 0 - .] | add | . == 0; "Debits must equal credits.");
      assert([.lines[].account != null] | all; "Every line needs an account.");
      assert(.memo != null; "Every journal entry needs a memo saying why.");
      assert(.preparer != null; "A journal entry names its preparer.");
      assert([.reviewer != null] + [[.lines[].debitMinor] | add | . < realmConfig("materiality")] | any; "An entry at or above the materiality threshold needs a reviewer.");
      assert(.reviewer != .preparer; "The reviewer must be someone other than the preparer.");
      assert(.date > realmConfig("closedThrough"); "That date is on or before the closing date, so it can't post.");
      .status = "posted";
      .postedBy = actor();
    `,
  } satisfies OperationDeclaration;
}

/** One period of a schedule: a prepaid expensed, deferred revenue earned, an accrual. */
export class ScheduledEntry extends LedgerDocument {
  static displayName = 'Scheduled entry';
  static icon = BookIcon;
  @field schedule = contains(StringField);
  @field kind = contains(StringField); // prepaid, deferred, accrual
  @field period = contains(NumberField); // which period of the schedule (0-based)
  @field lines = containsMany(EntryLine);

  postings() {
    return asPostings(this.lines);
  }
  title() {
    return `${this.schedule ?? ''} · period ${(this.period ?? 0) + 1}`;
  }
  party() {
    return this.kind ?? '';
  }
  facts(): Fact[] {
    return [
      { key: 'Schedule', value: this.schedule ?? '', mono: true },
      { key: 'Kind', value: this.kind ?? '' },
      { key: 'Period', value: String((this.period ?? 0) + 1) },
      { key: 'Date', value: day(this.date) },
      posted(this),
    ];
  }
  @operation static post = {
    base: 'transform',
    transformations: bxl`
      assert(if .status == null then true else .status == "draft" end; "Only a draft scheduled entry can be posted. This one is already posted.");
      assert((.lines | length) > 1; "An entry needs at least two lines.");
      assert(([.lines[].debitMinor, .lines[].creditMinor | type] | unique) == ["number"]; "Every line needs a debit and a credit amount (one of them zero).");
      assert([.lines[] | .debitMinor * .creditMinor] | all(. == 0); "A line is a debit or a credit, not both.");
      assert([.lines[] | .debitMinor + .creditMinor] | all(. > 0); "Every line needs an amount.");
      assert([.lines[].debitMinor, .lines[].creditMinor] | all(. >= 0); "Amounts can't be negative.");
      assert([.lines[].debitMinor, .lines[].creditMinor | floor] == [.lines[].debitMinor, .lines[].creditMinor]; "Amounts are in whole cents.");
      assert([.lines[].debitMinor] + [.lines[].creditMinor | 0 - .] | add | . == 0; "Debits must equal credits.");
      assert([.lines[].account != null] | all; "Every line needs an account.");
      assert(.schedule != null; "Say which schedule this period belongs to.");
      assert(.date > realmConfig("closedThrough"); "That date is on or before the closing date, so it can't post.");
      .status = "posted";
      .postedBy = actor();
    `,
  } satisfies OperationDeclaration;
}

export class DepreciationRun extends LedgerDocument {
  static displayName = 'Depreciation run';
  static icon = BookIcon;
  @field month = contains(IsoMonthField);
  @field assets = containsMany(AmountLine); // each asset's depreciation this month
  @field lines = containsMany(EntryLine);

  postings() {
    return asPostings(this.lines);
  }
  title() {
    return `Depreciation · ${this.month ?? ''}`;
  }
  facts(): Fact[] {
    return [
      { key: 'Month', value: this.month ?? '', strong: true },
      ...(this.assets ?? [])
        .filter(Boolean)
        .map((a) => ({ key: a!.label ?? '', value: money(a!.amountMinor) })),
      posted(this),
    ];
  }
  @operation static post = {
    base: 'transform',
    transformations: bxl`
      assert(if .status == null then true else .status == "draft" end; "Only a draft depreciation run can be posted. This one is already posted.");
      assert((.lines | length) > 1; "An entry needs at least two lines.");
      assert(([.lines[].debitMinor, .lines[].creditMinor | type] | unique) == ["number"]; "Every line needs a debit and a credit amount (one of them zero).");
      assert([.lines[] | .debitMinor * .creditMinor] | all(. == 0); "A line is a debit or a credit, not both.");
      assert([.lines[] | .debitMinor + .creditMinor] | all(. > 0); "Every line needs an amount.");
      assert([.lines[].debitMinor, .lines[].creditMinor] | all(. >= 0); "Amounts can't be negative.");
      assert([.lines[].debitMinor, .lines[].creditMinor | floor] == [.lines[].debitMinor, .lines[].creditMinor]; "Amounts are in whole cents.");
      assert([.lines[].debitMinor] + [.lines[].creditMinor | 0 - .] | add | . == 0; "Debits must equal credits.");
      assert([.lines[].account != null] | all; "Every line needs an account.");
      assert([.assets[].amountMinor] + [.lines[].debitMinor | 0 - .] | add | . == 0; "The assets' depreciation must add up to what the run posts.");
      assert(.date > realmConfig("closedThrough"); "That date is on or before the closing date, so it can't post.");
      .status = "posted";
      .postedBy = actor();
    `,
  } satisfies OperationDeclaration;
}
