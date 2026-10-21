// The append-log journal: one card per month whose postings are an append-only list. Only the card's
// own operations write it. `post` checks the entry (balanced, in this open month, after the closing
// date, a reviewer at or above materiality, no key posted twice) and appends it with the realm's own
// stamp of who posted it and when; `reverse` appends the negating entry; `close` and `seal` end the
// month, `seal` recording the hash of the month's .jsonl export. Nothing edits a posting in place.
//
// Write-once events (payments, receipts, deposits, payroll, bank and card activity, transfers,
// journal and scheduled entries, roasts, fulfillments, adjustments) become rows here instead of a
// card each. Things with a balance or a lifecycle (invoices, bills, lots, customers) stay cards and
// change in the same atomic batch as the posting. See design/append-log-journal-architecture.md.
import {
  CardDef,
  FieldDef,
  Component,
  field,
  contains,
  containsMany,
  linksToMany,
  getFields,
} from '@cardstack/base/card-api';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { Button } from '@cardstack/pretui/components/button';
import { Callout } from '@cardstack/pretui/components/callout';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import BookIcon from '@cardstack/boxel-icons/book-open';
import {
  operation,
  operations,
  bxl,
  type OperationDeclaration,
} from '@cardstack/base/operations';
import { PostingLine, AccountTotal } from './ledger-document';
import { LedgerAccount } from './ledger-cards';
import { LineGrid, type LineGridColumn } from './components/line-grid';
import {
  Sheet,
  Part,
  Facts,
  Strip,
  Fit,
  money,
  day,
  toneFor,
  type Fact,
} from './record-kit';
import { StatusChip } from '@cardstack/pretui/components/status-chip';
import {
  StatementTable,
  type StatementColumn as Col,
  type StatementRow as Line,
} from './components/statement-table';
import { JournalMonthStatusField } from './ledger-status';
import { IsoDateField, IsoMonthField } from './ledger-dates';

export const SEGMENT_CAP = 300;
/** Kinds whose posting changed other cards. Reversing one must undo those changes in the same batch. */
export const UNWINDS_ITEMS = [
  'customer-payment',
  'bill-payment',
  'fulfillment',
  'count',
  'roast',
  'landed-cost',
];
export const UNWINDS_FACT = ['credit-memo', 'write-off', 'vendor-credit'];

// ── posting a draft document into its journal month ─────────────────────────
// The journal kind each document type posts as, for the types a desk can post straight into a month.
// Stock movements (roasts, fulfillments, counts, landed costs) also draw from or restore lots, so
// they aren't here.
export const JOURNAL_KIND: Record<string, string> = {
  SalesReceipt: 'sales-receipt',
  RefundReceipt: 'refund-receipt',
  CustomerPayment: 'customer-payment',
  Deposit: 'deposit',
  CreditMemo: 'credit-memo',
  WriteOff: 'write-off',
  BillPayment: 'bill-payment',
  VendorCredit: 'vendor-credit',
  Transfer: 'transfer',
  CardCharge: 'card-charge',
  BankPayment: 'bank-payment',
  LoanPayment: 'loan-payment',
  PayrollRun: 'payroll',
  JournalEntry: 'journal',
  ScheduledEntry: 'scheduled',
  DepreciationRun: 'depreciation',
  AssetDisposal: 'disposal',
};
const NOT_FACTS = new Set([
  'id',
  'totalMinor', // added below, from the lines
  'docNo',
  'paymentNo',
  'date',
  'memo',
  'status',
  'enteredBy',
  'postedBy',
  'preparer',
  'reviewer',
  'cardTitle',
  'cardDescription',
  'cardThumbnailURL',
]);
const item = (o: Record<string, unknown>) => ({
  sku: null,
  lot: null,
  label: null,
  account: null,
  ref: null,
  qty: null,
  amountMinor: null,
  ...o,
});

/**
 * The JournalMonth.post payload for a draft document, in the shape converted documents have in the
 * journal: its lines, its own scalar fields as facts (what a reversal reads to unwind it), and what
 * it applies to or is made of as items. `type` is the document's class name.
 */
export function journalPostingFor(card: any, type: string, cardId: string) {
  let kind = JOURNAL_KIND[type];
  if (kind === 'deposit' && card.processor) kind = 'payout';
  let docNo = card.docNo ?? card.paymentNo ?? '';
  let lines = ((card.ledgerLines ?? []) as any[])
    .filter((l) => l && ((l.debitMinor ?? 0) > 0 || (l.creditMinor ?? 0) > 0))
    .map((l) => ({
      account: l.account ?? null,
      debitMinor: l.debitMinor ?? 0,
      creditMinor: l.creditMinor ?? 0,
      date: card.date ?? null,
      cls: l.cls ?? null,
      loc: l.loc ?? null,
      party: l.party ?? null,
      doc: l.doc ?? null,
    }));
  let facts = Object.keys(getFields(card))
    .filter((k) => !NOT_FACTS.has(k))
    .map((k) => [k, card[k]] as const)
    .filter(
      ([, v]) =>
        typeof v === 'string' ||
        typeof v === 'number' ||
        typeof v === 'boolean',
    )
    .map(([key, value]) => ({ key, value: String(value) }));
  let total = lines.reduce((n, l) => n + l.debitMinor, 0);
  facts.push(
    { key: 'totalMinor', value: String(total) },
    { key: 'originalCard', value: cardId },
  );
  // A sale's tax by code and rate, so the agency registers can read what each agency is owed.
  let taxLines = ((card.taxLines ?? []) as any[]).filter(Boolean);
  if (taxLines.length)
    facts.push({
      key: 'taxLines',
      value: JSON.stringify(
        taxLines.map((t) => ({
          code: t.code ?? null,
          agencyId: t.agencyId ?? null,
          ratePpm: t.ratePpm ?? null,
          taxableMinor: t.taxableMinor ?? null,
          taxMinor: t.taxMinor ?? null,
        })),
      ),
    });
  let items =
    type === 'CustomerPayment'
      ? ((card.applications ?? []) as any[]).map((a) =>
          item({ ref: a?.invoiceNo, amountMinor: a?.amountMinor }),
        )
      : type === 'BillPayment'
        ? ((card.applications ?? []) as any[]).map((a) =>
            item({ ref: a?.billNo, amountMinor: a?.amountMinor }),
          )
        : type === 'Deposit'
          ? ((card.items ?? []) as any[]).map((i) =>
              item({ ref: i?.docNo, amountMinor: i?.amountMinor }),
            )
          : type === 'SalesReceipt' || type === 'RefundReceipt'
            ? ((card.lines ?? []) as any[]).map((l) =>
                item({
                  sku: l?.sku ?? null,
                  qty: l?.qty ?? null,
                  label: l?.description ?? null,
                  account: l?.account ?? null,
                  amountMinor: l?.amountMinor,
                }),
              )
            : type === 'PayrollRun' || type === 'DepreciationRun'
              ? ((card.wages ?? card.assets ?? []) as any[]).map((a) =>
                  item({
                    label: a?.label ?? null,
                    account: a?.account ?? null,
                    amountMinor: a?.amountMinor,
                  }),
                )
              : [];
  return {
    key: `${type}:${docNo}`,
    kind,
    date: card.date ?? null,
    memo: card.memo ?? null,
    party: card.party?.() ?? card.vendorId ?? card.customerId ?? null,
    source: docNo,
    lines,
    facts,
    items,
    preparer: card.preparer ?? null,
    reviewer: card.reviewer ?? null,
  };
}
const sum = (xs: (number | undefined)[]) =>
  xs.reduce<number>((n, x) => n + (x ?? 0), 0);
export const seqText = (month: string | undefined, seq: number | undefined) =>
  seq ? `J-${month ?? ''}-${String(seq).padStart(4, '0')}` : '';
export const KIND_LABEL: Record<string, string> = {
  'bill-payment': 'Bill payment',
  'customer-payment': 'Customer payment',
  'sales-receipt': 'Sales receipt',
  'refund-receipt': 'Refund receipt',
  deposit: 'Deposit',
  payout: 'Processor payout',
  payroll: 'Payroll run',
  'bank-payment': 'Bank payment',
  transfer: 'Transfer',
  'card-charge': 'Card charge',
  'loan-payment': 'Loan payment',
  journal: 'Journal entry',
  scheduled: 'Scheduled entry',
  depreciation: 'Depreciation',
  disposal: 'Asset disposal',
  'vendor-credit': 'Vendor credit',
  'credit-memo': 'Credit memo',
  'write-off': 'Write-off',
  roast: 'Roast batch',
  fulfillment: 'Fulfillment',
  'landed-cost': 'Landed cost',
  count: 'Count adjustment',
  reversal: 'Reversal',
  void: 'Void',
};

/** A detail a kind of posting carries: the card used, the provider, the invoice paid, the lot drawn. */
export class PostingFact extends FieldDef {
  static displayName = 'Posting detail';
  @field key = contains(StringField);
  @field value = contains(StringField);
}

/** A line of business detail a posting carries beside its ledger lines: a product sold, a lot drawn,
 *  a wage line, an invoice or bill a payment applies to, an asset depreciated. Registers read these. */
export class PostingItem extends FieldDef {
  static displayName = 'Posting item';
  @field sku = contains(StringField);
  @field lot = contains(StringField);
  @field label = contains(StringField);
  @field account = contains(StringField);
  @field ref = contains(StringField); // the invoice, bill or document it applies to
  @field qty = contains(NumberField); // thousandths of a unit
  @field amountMinor = contains(NumberField);
}

/** One posted entry: the envelope a file segment line will carry once postings move to files. */
export class Posting extends FieldDef {
  static displayName = 'Posting';
  @field seq = contains(NumberField); // set by the realm: 1, 2, 3… within the month
  @field key = contains(StringField); // idempotency key: the source document, or a client id
  @field kind = contains(StringField);
  @field date = contains(IsoDateField);
  @field memo = contains(StringField);
  @field party = contains(StringField);
  @field source = contains(StringField); // the document number it came from
  @field lines = containsMany(PostingLine);
  @field facts = containsMany(PostingFact);
  @field items = containsMany(PostingItem);
  @field preparer = contains(StringField);
  @field reviewer = contains(StringField);
  @field reverses = contains(NumberField); // the seq this posting reverses
  @field postedBy = contains(StringField); // stamped by the realm: actor()
  @field postedAt = contains(StringField); // stamped by the realm: NOW()
}

/** A posting as the registers read it: reversed pairs left out, facts by name. */
export interface JournalPost {
  month: string;
  seq: number;
  kind: string;
  date: string;
  party: string;
  source: string;
  memo: string;
  lines: any[];
  items: any[];
  fact: (key: string) => string;
  num: (key: string) => number;
}
/** The postings in these month cards that still stand: a reversed posting and its reversal cancel out. */
export function journalPostings(
  months: unknown[] | undefined,
  kinds?: string[],
): JournalPost[] {
  let out: JournalPost[] = [];
  for (let m of (months ?? []).filter(Boolean) as {
    month?: string;
    postings?: any[];
  }[]) {
    let posts = (m.postings ?? []).filter(Boolean),
      reversed = new Set(posts.map((p) => p.reverses).filter(Boolean));
    for (let p of posts) {
      if (
        p.kind === 'reversal' ||
        reversed.has(p.seq) ||
        (kinds && !kinds.includes(p.kind))
      )
        continue;
      let facts = new Map(
        ((p.facts ?? []) as any[])
          .filter(Boolean)
          .map((f) => [f.key, f.value ?? '']),
      );
      out.push({
        month: m.month ?? '',
        seq: p.seq,
        kind: p.kind,
        date: p.date ?? '',
        party: p.party ?? '',
        source: p.source ?? '',
        memo: p.memo ?? '',
        lines: (p.lines ?? []).filter(Boolean),
        items: (p.items ?? []).filter(Boolean),
        fact: (k) => String(facts.get(k) ?? ''),
        num: (k) => Number(facts.get(k)) || 0,
      });
    }
  }
  return out;
}

export class KindTotal extends FieldDef {
  @field kind = contains(StringField);
  @field count = contains(NumberField);
  @field amountMinor = contains(NumberField); // debits
}

export class JournalMonth extends CardDef {
  static displayName = 'Journal month';
  static icon = BookIcon;
  static prefersWideFormat = true;
  @field month = contains(IsoMonthField); // YYYY-MM
  @field firstDay = contains(IsoDateField); // YYYY-MM-DD: postings date on or after
  @field lastDay = contains(IsoDateField); // …and on or before
  @field status = contains(JournalMonthStatusField); // only the operations move it
  @field nextSeq = contains(NumberField); // only post and reverse move it
  @field postings = containsMany(Posting); // append-only
  @field closedBy = contains(StringField);
  @field sealHash = contains(StringField); // sha256 of the month's .jsonl export
  @field sealCount = contains(NumberField);
  @field sealedBy = contains(StringField);

  @field count = contains(NumberField, {
    computeVia: function (this: JournalMonth) {
      return (this.postings ?? []).filter(Boolean).length;
    },
  });
  @field debitMinor = contains(NumberField, {
    computeVia: function (this: JournalMonth) {
      return sum(
        (this.postings ?? []).flatMap((p) =>
          (p?.lines ?? []).map((l) => l?.debitMinor),
        ),
      );
    },
  });
  @field creditMinor = contains(NumberField, {
    computeVia: function (this: JournalMonth) {
      return sum(
        (this.postings ?? []).flatMap((p) =>
          (p?.lines ?? []).map((l) => l?.creditMinor),
        ),
      );
    },
  });
  /** Every posted line, stamped with its posting's date and number, so `ledgerLines.account` queries find the month. */
  @field ledgerLines = containsMany(PostingLine, {
    computeVia: function (this: JournalMonth) {
      return (this.postings ?? []).filter(Boolean).flatMap((p) =>
        (p!.lines ?? []).filter(Boolean).map(
          (l) =>
            new PostingLine({
              account: l!.account,
              debitMinor: l!.debitMinor ?? 0,
              creditMinor: l!.creditMinor ?? 0,
              date: p!.date,
              cls: l!.cls,
              loc: l!.loc,
              party: l!.party ?? p!.party,
              doc: l!.doc ?? seqText(this.month, p!.seq),
            }),
        ),
      );
    },
  });
  /** The month's totals per account: the same shape a MonthClose stores. */
  @field totals = containsMany(AccountTotal, {
    computeVia: function (this: JournalMonth) {
      let t = new Map<string, [number, number]>();
      for (let p of (this.postings ?? []).filter(Boolean))
        for (let l of (p!.lines ?? []).filter(Boolean)) {
          let a = t.get(l!.account ?? '') ?? [0, 0];
          a[0] += l!.debitMinor ?? 0;
          a[1] += l!.creditMinor ?? 0;
          t.set(l!.account ?? '', a);
        }
      return [...t]
        .sort(([a], [b]) => a.localeCompare(b))
        .map(
          ([account, [d, c]]) =>
            new AccountTotal({ account, debitMinor: d, creditMinor: c }),
        );
    },
  });
  @field kinds = containsMany(KindTotal, {
    computeVia: function (this: JournalMonth) {
      let t = new Map<string, [number, number]>();
      for (let p of (this.postings ?? []).filter(Boolean)) {
        let a = t.get(p!.kind ?? '') ?? [0, 0];
        a[0] += 1;
        a[1] += sum((p!.lines ?? []).map((l) => l?.debitMinor));
        t.set(p!.kind ?? '', a);
      }
      return [...t]
        .sort(([, a], [, b]) => b[0] - a[0])
        .map(
          ([kind, [count, amountMinor]]) =>
            new KindTotal({ kind, count, amountMinor }),
        );
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: JournalMonth) {
      return `Journal · ${this.month ?? ''}`;
    },
  });

  /** Append one balanced entry. The realm stamps its number, who posted it and when. */
  @operation static post = {
    base: 'transform',
    params: {
      key: StringField,
      kind: StringField,
      date: StringField,
      memo: StringField,
      party: StringField,
      source: StringField,
      lines: PostingLine,
      facts: PostingFact,
      items: PostingItem,
      preparer: StringField,
      reviewer: StringField,
      postedAt: StringField,
    },
    // The time is stamped here, before the program runs: a program must be repeatable, so NOW() is
    // refused inside it, and a value merged on the right of the payload can't be supplied by the caller.
    input: bxl`. + { postedAt: TEXT(NOW(); "yyyy-mm-dd hh:mm:ss") }`,
    transformations: bxl`
      assert(.status == "open"; "This month is closed, so nothing more can post to it.");
      assert([params("date") >= .firstDay, params("date") <= .lastDay] | all; "That date isn't in this month. Post it to the month it belongs to.");
      assert(params("date") > realmConfig().closedThrough; "That date is on or before the closing date, so it can't post.");
      assert([.postings[].key] | all(. != params("key")); "An entry with this key has already posted. Nothing was posted twice.");
      assert([.postings | length] | all(. < 300); "This month's journal is full. Post to its next segment.");
      assert([params("lines") | length] | all(. > 1); "An entry needs at least two lines.");
      assert([params("lines")[].account != null] | all; "Every line needs an account.");
      assert([params("lines")[].account] | all(. != ""); "Every line needs an account.");
      assert(if realmConfig().chart == null then true else ([params("lines")[].account] - realmConfig().chart | length == 0) end; "A line's account isn't in the chart of accounts. Add the account to the chart, then post.");
      assert([params("lines")[] | .debitMinor * .creditMinor] | all(. == 0); "A line is a debit or a credit, not both.");
      assert([params("lines")[] | .debitMinor + .creditMinor] | all(. > 0); "Every line needs an amount.");
      assert([params("lines")[].debitMinor, params("lines")[].creditMinor] | all(. >= 0); "Amounts can't be negative.");
      assert([params("lines")[].debitMinor, params("lines")[].creditMinor | floor] == [params("lines")[].debitMinor, params("lines")[].creditMinor]; "Amounts are in whole cents.");
      assert([params("lines")[].debitMinor] + [params("lines")[].creditMinor | 0 - .] | add | . == 0; "Debits must equal credits.");
      assert(if params("kind") != "journal" then true else (if params("reviewer") != null then true else (if realmConfig().materiality == null then true else (([params("lines")[].debitMinor] | add) < realmConfig().materiality) end) end) end; "A journal entry at or above the materiality threshold needs a reviewer.");
      assert([params("reviewer") == null] + [params("reviewer") != params("preparer")] | any; "The reviewer must be someone other than the preparer.");
      .postings = .postings + [{ seq: .nextSeq, key: params("key"), kind: params("kind"), date: params("date"), memo: params("memo"), party: params("party"), source: params("source"), lines: params("lines"), facts: params("facts"), items: params("items"), preparer: params("preparer"), reviewer: params("reviewer"), reverses: null, postedBy: actor(), postedAt: params("postedAt") }];
      .nextSeq |= . + 1;
    `,
  } satisfies OperationDeclaration;

  /** Bring in an entry that already posted somewhere else: a document card from before the books moved
   *  to the journal. The same checks as `post` on the entry itself (balanced, in this month, not twice),
   *  but no closing-date or reviewer check: those held when it first posted. Owner only: no policy can
   *  grant it. Its facts say where it came from and who first posted it. */
  @operation static importPosting = {
    base: 'transform',
    nonGrantable: true,
    params: {
      key: StringField,
      kind: StringField,
      date: StringField,
      memo: StringField,
      party: StringField,
      source: StringField,
      lines: PostingLine,
      facts: PostingFact,
      items: PostingItem,
      preparer: StringField,
      reviewer: StringField,
      postedAt: StringField,
    },
    input: bxl`. + { postedAt: TEXT(NOW(); "yyyy-mm-dd hh:mm:ss") }`,
    transformations: bxl`
      assert(.status == "open"; "This month is closed, so nothing more can come into it.");
      assert([params("date") >= .firstDay, params("date") <= .lastDay] | all; "That date isn't in this month.");
      assert([.postings[].key] | all(. != params("key")); "An entry with this key is already in the journal. Nothing was imported twice.");
      assert([.postings | length] | all(. < 300); "This month's journal is full.");
      assert([params("lines") | length] | all(. > 1); "An entry needs at least two lines.");
      assert([params("lines")[].account != null] | all; "Every line needs an account.");
      assert([params("lines")[].account] | all(. != ""); "Every line needs an account.");
      assert([params("lines")[] | .debitMinor * .creditMinor] | all(. == 0); "A line is a debit or a credit, not both.");
      assert([params("lines")[] | .debitMinor + .creditMinor] | all(. > 0); "Every line needs an amount.");
      assert([params("lines")[].debitMinor, params("lines")[].creditMinor] | all(. >= 0); "Amounts can't be negative.");
      assert([params("lines")[].debitMinor] + [params("lines")[].creditMinor | 0 - .] | add | . == 0; "Debits must equal credits.");
      .postings = .postings + [{ seq: .nextSeq, key: params("key"), kind: params("kind"), date: params("date"), memo: params("memo"), party: params("party"), source: params("source"), lines: params("lines"), facts: params("facts"), items: params("items"), preparer: params("preparer"), reviewer: params("reviewer"), reverses: null, postedBy: actor(), postedAt: params("postedAt") }];
      .nextSeq |= . + 1;
    `,
  } satisfies OperationDeclaration;

  /** Append the entry that undoes posting `seq` of this month. The caller sends the reversing lines;
   *  the realm checks they are exactly the original's with debits and credits swapped. The original is
   *  never edited. A posting that changed other cards (a payment, a credit, a stock draw) can only be
   *  reversed with those changes undone in the same batch: the caller lists them in `unwound` and the
   *  realm checks the list is exactly what the posting applied. A void is never reversed. */
  @operation static reverse = {
    base: 'transform',
    params: {
      seq: NumberField,
      key: StringField,
      date: StringField,
      memo: StringField,
      party: StringField,
      source: StringField,
      lines: PostingLine,
      unwound: PostingItem,
      postedAt: StringField,
    },
    input: bxl`. + { postedAt: TEXT(NOW(); "yyyy-mm-dd hh:mm:ss") }`,
    transformations: bxl`
      assert(.status == "open"; "This month is closed, so nothing more can post to it.");
      assert([params("date") >= .firstDay, params("date") <= .lastDay] | all; "That date isn't in this month.");
      assert(params("date") > realmConfig().closedThrough; "That date is on or before the closing date, so it can't post.");
      assert([.postings[].seq] | any(. == params("seq")); "There's no posting with that number in this month.");
      assert([.postings[].reverses] | all(. != params("seq")); "That posting has already been reversed.");
      assert([.postings[] | select(.seq == params("seq")) | .kind] | all(. != "reversal"); "A reversal can't itself be reversed. Post a new entry instead.");
      assert([.postings[] | select(.seq == params("seq")) | .kind] | all(. != "void"); "A void can't be reversed. Enter the document again instead.");
      assert([.postings[] | select(.seq == params("seq")) | select(.kind == "customer-payment" or .kind == "bill-payment" or .kind == "fulfillment" or .kind == "count" or .kind == "roast" or .kind == "landed-cost") | [.items[] | [.ref, .lot, .amountMinor]]] | all(. == [params("unwound")[] | [.ref, .lot, .amountMinor]]); "Reversing this undoes what it changed on its invoices, bills or stock lots. Send those changes with the reversal, one for each line it applied.");
      assert([.postings[] | select(.seq == params("seq")) | select(.kind == "credit-memo" or .kind == "write-off" or .kind == "vendor-credit") | [.facts[] | select(.key == "invoiceNo" or .key == "billNo") | .value]] | all(. == [params("unwound")[].ref]); "Reversing this takes its credit back off the invoice or bill it was applied to. Send that change with the reversal.");
      assert([.postings[].key] | all(. != params("key")); "An entry with this key has already posted.");
      assert([.postings[] | select(.seq == params("seq")) | .lines[] | [.account, .creditMinor, .debitMinor]] == [params("lines")[] | [.account, .debitMinor, .creditMinor]]; "A reversal posts exactly the original's lines with debits and credits swapped.");
      .postings = .postings + [{ seq: .nextSeq, key: params("key"), kind: "reversal", date: params("date"), memo: params("memo"), party: params("party"), source: params("source"), lines: params("lines"), facts: [], items: [], preparer: null, reviewer: null, reverses: params("seq"), postedBy: actor(), postedAt: params("postedAt") }];
      .nextSeq |= . + 1;
    `,
  } satisfies OperationDeclaration;

  /** Close the month: nothing more posts to it. Sent in the same batch as the month's close. */
  @operation static close = {
    base: 'transform',
    transformations: bxl`
      assert(.status == "open"; "This month is already closed.");
      .status = "closed";
      .closedBy = actor();
    `,
  } satisfies OperationDeclaration;

  /** Seal a closed month with the hash of its .jsonl export: one canonical line per posting, in order. */
  @operation static seal = {
    base: 'transform',
    params: { sealHash: StringField, sealCount: NumberField },
    transformations: bxl`
      assert(.status == "closed"; "Only a closed month can be sealed.");
      assert([.postings | length] == [params("sealCount")]; "The export must hold every posting of the month.");
      .status = "sealed";
      .sealHash = params("sealHash");
      .sealCount = params("sealCount");
      .sealedBy = actor();
    `,
  } satisfies OperationDeclaration;

  // History is only appended: no grant can rewrite or remove the month.
  @operation static update = {
    base: 'update',
    nonGrantable: true,
  } satisfies OperationDeclaration;
  @operation static delete = {
    base: 'delete',
    nonGrantable: true,
  } satisfies OperationDeclaration;

  static isolated = class extends Component<typeof JournalMonth> {
    get facts(): Fact[] {
      let m = this.args.model;
      return [
        {
          key: 'Status',
          value:
            m.status === 'sealed'
              ? 'Sealed'
              : m.status === 'closed'
                ? 'Closed'
                : 'Open',
        },
        { key: 'Postings', value: `${m.count ?? 0} of ${SEGMENT_CAP}` },
        { key: 'Debits', value: money(m.debitMinor) },
        { key: 'Credits', value: money(m.creditMinor) },
        {
          key: 'Balanced',
          value: (m.debitMinor ?? 0) === (m.creditMinor ?? 0) ? 'Yes' : 'No',
        },
        ...(m.sealHash
          ? [
              {
                key: 'Sealed',
                value: `${m.sealCount} lines · sha256 ${m.sealHash.slice(0, 16)}…`,
              },
            ]
          : []),
      ];
    }
    kindCols: Col[] = [
      { key: 'kind', label: 'Kind' },
      { key: 'n', label: 'Postings', kind: 'number' },
      { key: 'amount', label: 'Debits', kind: 'amount' },
    ];
    get kinds(): Line[] {
      let m = this.args.model;
      return [
        ...(m.kinds ?? []).filter(Boolean).map((k) => ({
          key: k!.kind ?? '',
          cells: {
            kind: KIND_LABEL[k!.kind ?? ''] ?? k!.kind,
            n: k!.count,
            amount: k!.amountMinor,
          },
        })),
        {
          key: 'total',
          role: 'total' as const,
          cells: { kind: 'All postings', n: m.count, amount: m.debitMinor },
        },
      ];
    }
    postingCols: Col[] = [
      { key: 'seq', label: 'No.', kind: 'code' },
      { key: 'date', label: 'Date', width: '7.5rem' },
      { key: 'kind', label: 'Kind', priority: 'secondary' },
      { key: 'memo', label: 'Memo' },
      {
        key: 'accounts',
        label: 'Accounts',
        kind: 'code',
        priority: 'secondary',
      },
      { key: 'state', label: 'State', kind: 'custom' },
      { key: 'amount', label: 'Amount', kind: 'amount' },
      { key: 'by', label: 'Posted', priority: 'secondary' },
    ];
    get rows(): Line[] {
      let m = this.args.model,
        reversed = new Set(
          (m.postings ?? []).map((p) => p?.reverses).filter(Boolean),
        );
      return (m.postings ?? []).filter(Boolean).map((p) => ({
        key: String(p!.seq),
        cells: {
          seq: seqText(m.month, p!.seq),
          date: day(p!.date),
          kind: KIND_LABEL[p!.kind ?? ''] ?? p!.kind,
          memo: [p!.memo || p!.source, p!.party].filter(Boolean).join(' · '),
          accounts: [
            ...new Set((p!.lines ?? []).map((l) => l?.account).filter(Boolean)),
          ].join(' '),
          state: p!.reverses
            ? `Reverses ${seqText(m.month, p!.reverses)}`
            : reversed.has(p!.seq)
              ? 'Reversed'
              : '',
          amount: sum((p!.lines ?? []).map((l) => l?.debitMinor)),
          by: `${p!.postedBy ?? ''} · ${p!.postedAt ?? ''}`,
        },
        data: { seq: seqText(m.month, p!.seq) },
      }));
    }
    state = (v: unknown) => String(v ?? '');
    stateTone = (v: unknown) =>
      String(v ?? '').startsWith('Reverses')
        ? 'attention'
        : toneFor(String(v ?? ''));
    <template>
      <Sheet
        @eyebrow='Journal'
        @title={{@model.cardTitle}}
        @figureMinor={{@model.debitMinor}}
        @figureLabel='Posted this month (debits)'
        @status={{@model.status}}
        @note='An append-only journal. Each posting was checked and stamped by the realm when it posted; corrections are new reversing entries, never edits.'
      >
        <Part @title='Month'><Facts @items={{this.facts}} /></Part>
        <Part @title='By kind'><StatementTable
            @label='Postings by kind'
            @columns={{this.kindCols}}
            @rows={{this.kinds}}
            @density='compact'
          /></Part>
        <Part @title='Postings'>
          <StatementTable
            @label='Postings in this month'
            @columns={{this.postingCols}}
            @rows={{this.rows}}
            @density='compact'
          >
            <:cell as |value|>{{#if value}}<StatusChip
                  @value={{this.state value}}
                  @tone={{this.stateTone value}}
                />{{/if}}</:cell>
          </StatementTable>
        </Part>
      </Sheet>
    </template>
  };
  // The month is written only through its operations, so its editor shows the same read-only view
  // (the default editor would render every posting as an inline form).
  static edit = JournalMonth.isolated;
  static embedded = class extends Component<typeof JournalMonth> {
    <template>
      <Strip
        @eyebrow='Journal'
        @title={{@model.cardTitle}}
        @meta={{@model.status}}
        @figure={{money @model.debitMinor}}
      />
    </template>
  };
  static fitted = class extends Component<typeof JournalMonth> {
    <template>
      <Fit
        @eyebrow='Journal'
        @title={{@model.month}}
        @figure={{money @model.debitMinor}}
        @meta={{@model.status}}
      />
    </template>
  };
}

/** The pad's page: the entry as written so far, and Post, which sends it to its month's journal and
 *  clears the pad in one batch. The month's own checks decide; a refusal shows its reason here. */
class EntryPadView extends Component<typeof EntryPad> {
  @tracked message = '';
  @tracked error = '';
  @tracked busy = false;
  // The grid edits the pad's own lines in place, so every cell autosaves; nothing is held in a draft.
  get columns(): LineGridColumn[] {
    let options = (
      (this.args.model.accounts ?? []).filter(Boolean) as LedgerAccount[]
    )
      .sort((a, b) => (a.code ?? '').localeCompare(b.code ?? ''))
      .map((a) => ({
        value: a.code ?? '',
        label: `${a.code} · ${a.name}`,
        meta: a.type,
      }));
    return [
      {
        key: 'account',
        label: 'Account',
        kind: 'choice',
        options,
        required: true,
        placeholder: 'Account',
      },
      {
        key: 'debitMinor',
        label: 'Debit',
        kind: 'amount',
        pairsWith: 'creditMinor',
        total: true,
        width: '9.5rem',
      },
      {
        key: 'creditMinor',
        label: 'Credit',
        kind: 'amount',
        pairsWith: 'debitMinor',
        total: true,
        width: '9.5rem',
      },
      { key: 'party', label: 'Party', placeholder: 'Optional', width: '10rem' },
    ];
  }
  get rows() {
    return (this.args.model.lines ?? []).filter(Boolean) as unknown as Record<
      string,
      unknown
    >[];
  }
  balance: [string, string] = ['debitMinor', 'creditMinor'];
  change = (index: number, key: string, value: unknown) => {
    let line = (this.args.model.lines ?? [])[index] as any;
    if (!line) return;
    line[key] =
      value ?? (key === 'debitMinor' || key === 'creditMinor' ? 0 : null);
  };
  addLine = () => {
    this.args.model.lines = [
      ...(this.args.model.lines ?? []),
      new PostingLine({ debitMinor: 0, creditMinor: 0 }),
    ];
  };
  removeLine = (index: number) => {
    this.args.model.lines = (this.args.model.lines ?? []).filter(
      (_, i) => i !== index,
    );
  };
  get canPost() {
    return (
      (this.args.model.lines ?? []).length > 1 &&
      !!this.args.model.date &&
      !this.busy
    );
  }
  post = async () => {
    let pad = this.args.model as EntryPad,
      month = (pad.journal ?? []).filter(Boolean)[0];
    this.busy = true;
    this.message = '';
    this.error = '';
    try {
      if (!month)
        throw new Error(
          `There's no journal month for ${pad.monthKey}. Open the month before posting to it.`,
        );
      let key = `pad:${pad.kind}:${Date.now().toString(36)}`;
      let lines = (pad.lines ?? []).filter(Boolean).map((l) => ({
        account: l!.account ?? null,
        debitMinor: l!.debitMinor ?? 0,
        creditMinor: l!.creditMinor ?? 0,
        date: null,
        cls: l!.cls ?? null,
        loc: l!.loc ?? null,
        party: l!.party ?? null,
        doc: l!.doc ?? null,
      }));
      await (operations(month) as any).atomic((b: any) => {
        b.post({
          key,
          kind: pad.kind ?? 'journal',
          date: pad.date,
          memo: pad.memo ?? null,
          party: pad.party ?? null,
          source: null,
          lines,
          facts: [],
          items: [],
          preparer: pad.preparer ?? null,
          reviewer: pad.reviewer ?? null,
        });
        b.on(pad).clear({ posted: key });
      });
      this.message = `Posted to ${month.cardTitle}. The realm checked it, numbered it and stamped who posted it; the pad is clear for the next one.`;
    } catch (e: any) {
      this.error = e?.detail ?? e?.message ?? String(e);
    } finally {
      this.busy = false;
    }
  };
  <template>
    <Sheet
      @eyebrow='Entry pad'
      @title={{@model.cardTitle}}
      @note='Write the entry in the editor (it saves as you type), then post it. Posting goes through the month’s own checks; nothing here can change the journal any other way.'
    >
      <Part @title='Entry'>
        <div class='head'>
          <label><span>Date</span><@fields.date @format='edit' /></label>
          <label class='wide'><span>Memo</span><@fields.memo
              @format='edit'
            /></label>
          <label><span>Party</span><@fields.party @format='edit' /></label>
          <label><span>Prepared by</span><@fields.preparer
              @format='edit'
            /></label>
          <label><span>Reviewed by</span><@fields.reviewer
              @format='edit'
            /></label>
        </div>
      </Part>
      <Part @title='Lines'>
        <LineGrid
          @label='Lines on this pad'
          @columns={{this.columns}}
          @rows={{this.rows}}
          @balance={{this.balance}}
          @minRows={{2}}
          @onChange={{this.change}}
          @onAdd={{this.addLine}}
          @onRemove={{this.removeLine}}
        />
      </Part>
      {{#if @model.lastPosted}}<p class='last'>Last posted:
          {{@model.lastPosted}}</p>{{/if}}
      <div class='act'><Button
          @tone='primary'
          @appearance='accent'
          @busy={{this.busy}}
          @disabled={{if this.canPost false true}}
          {{on 'click' this.post}}
        >Post to the journal</Button></div>
      {{#if this.error}}<Callout
          @tone='danger'
          @title='The month refused this entry'
        >{{this.error}}</Callout>{{/if}}
      {{#if this.message}}<Callout
          @tone='success'
          role='status'
        >{{this.message}}</Callout>{{/if}}
    </Sheet>
    <style scoped>
      .act {
        margin-block: 1rem 0.75rem;
      }
      .head {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(11rem, 1fr));
        gap: 0.75rem 1rem;
      }
      .head label {
        display: grid;
        gap: 0.3rem;
        min-width: 0;
      }
      .head label span {
        font-size: var(--boxel-ui-label-font-size);
        font-weight: var(--boxel-ui-label-font-weight);
        letter-spacing: var(--boxel-ui-label-letter-spacing);
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .head .wide {
        grid-column: span 2;
      }
      .last {
        margin: 0;
        font-size: 0.75rem;
        color: var(--muted-foreground);
      }
    </style>
  </template>
}

/** An entry being written. Its fields are what the form binds to (Boxel saves as you type); posting
 *  sends them to the month's `post` and clears the pad in the same batch. One pad per person per kind. */
export class EntryPad extends CardDef {
  static displayName = 'Entry pad';
  static icon = BookIcon;
  @field owner = contains(StringField);
  @field kind = contains(StringField);
  @field date = contains(IsoDateField);
  @field memo = contains(StringField);
  @field party = contains(StringField);
  @field lines = containsMany(PostingLine);
  @field preparer = contains(StringField);
  @field reviewer = contains(StringField);
  @field lastPosted = contains(StringField); // the key of what it last posted
  @field monthKey = contains(StringField, {
    computeVia: function (this: EntryPad) {
      return (this.date ?? '').slice(0, 7);
    },
  });
  @field accounts = linksToMany(() => LedgerAccount, {
    query: { page: { size: 200 } },
  });
  @field journal = linksToMany(() => JournalMonth, {
    query: { filter: { eq: { month: '$this.monthKey' } }, page: { size: 1 } },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: EntryPad) {
      return `${KIND_LABEL[this.kind ?? ''] ?? 'Entry'} pad${this.owner ? ' · ' + this.owner : ''}`;
    },
  });

  /** Empty the pad after its entry posts. */
  @operation static clear = {
    base: 'transform',
    params: { posted: StringField },
    transformations: bxl`
      .lastPosted = params("posted");
      .memo = null;
      .party = null;
      .reviewer = null;
      .lines = [];
    `,
  } satisfies OperationDeclaration;

  static isolated = EntryPadView;
  // The pad's page is already where it is written, so its editor is the same page.
  static edit = EntryPadView;
  static embedded = class extends Component<typeof EntryPad> {
    <template>
      <Strip
        @eyebrow='Entry pad'
        @title={{@model.cardTitle}}
        @meta={{@model.lastPosted}}
      />
    </template>
  };
  static fitted = class extends Component<typeof EntryPad> {
    <template>
      <Fit @eyebrow='Pad' @title={{@model.kind}} @meta={{@model.lastPosted}} />
    </template>
  };
}
