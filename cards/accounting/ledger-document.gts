// The common shape of every posted document in the card-native ledger.
// A LedgerDocument has a date, a status that only its post operation moves, who entered and posted
// it, and the ledger lines it contributes. Each kind of document says what it posts by overriding
// postings(), and the base type's formats render it from those methods, so a new kind of document
// (a roast, a vendor credit) needs no templates of its own. (Reports list each kind as its own
// query: a query on this base type resolved only some of its matches in the host.)
//
// (Bills, bill payments and the opening balances came first and are their own types; the month
// report reads them alongside this one.)
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
  Sheet,
  Part,
  Facts,
  Lines,
  Strip,
  Fit,
  money,
  type Fact,
} from './record-kit';
import { type OperationDeclaration } from '@cardstack/base/operations';
import { DocumentStatusField } from './ledger-status';
import { IsoDateField } from './ledger-dates';

export class PostingLine extends FieldDef {
  static displayName = 'Ledger line';
  @field account = contains(StringField);
  @field debitMinor = contains(NumberField);
  @field creditMinor = contains(NumberField);
  @field date = contains(IsoDateField);
  @field cls = contains(StringField);
  @field loc = contains(StringField);
  @field party = contains(StringField);
  @field doc = contains(StringField);
}

/** Debits and credits on one account: a month's totals, a close snapshot, an opening balance. */
export class AccountTotal extends FieldDef {
  static displayName = 'Account total';
  @field account = contains(StringField);
  @field debitMinor = contains(NumberField);
  @field creditMinor = contains(NumberField);
}

// The plain shape a document's posting rules return; ledgerLines turns each into a PostingLine.
export type PostingInput = {
  account?: string;
  debitMinor?: number;
  creditMinor?: number;
  date?: string;
  cls?: string;
  loc?: string;
  party?: string;
  doc?: string;
};

/** An exchange rate as documents store it: home-currency units per foreign unit, times a million. */
export const RATE_SCALE = 1_000_000;

/** An amount in a document's currency, in the home currency at its rate; unchanged without one. */
export const toHome = (
  minor: number | null | undefined,
  rateMicros: number | null | undefined,
) =>
  rateMicros && rateMicros !== RATE_SCALE
    ? Math.round(((minor ?? 0) * rateMicros) / RATE_SCALE)
    : (minor ?? 0);

/**
 * A foreign-currency document's lines in the home currency, at its rate. The line for `balance`
 * (receivables or payables) is the document's total at the rate, rounded once, so a payment of the
 * whole amount at the same rate clears it exactly; each other line rounds on its own, and whatever
 * that leaves over goes on the largest of them, so the entry still balances. Lines of a
 * home-currency document (no rate) come back unchanged.
 */
export function inHome<
  T extends { account?: string; debitMinor?: number; creditMinor?: number },
>(lines: T[], rateMicros: number | null | undefined, balance: string): T[] {
  if (!rateMicros || rateMicros === RATE_SCALE) return lines;
  let out = lines.map((l) => ({
    ...l,
    debitMinor: toHome(l.debitMinor, rateMicros),
    creditMinor: toHome(l.creditMinor, rateMicros),
  }));
  let off =
    out.reduce((n, l) => n + l.debitMinor, 0) -
    out.reduce((n, l) => n + l.creditMinor, 0);
  let fix = out
    .filter((l) => l.account !== balance)
    .sort(
      (a, b) => b.debitMinor + b.creditMinor - (a.debitMinor + a.creditMinor),
    )[0];
  if (off && fix) {
    if (fix.creditMinor) fix.creditMinor += off;
    else fix.debitMinor -= off;
  }
  return out;
}

/**
 * The checks a document in another currency adds to its post. Its currency is empty in the home
 * currency; otherwise the books must allow multicurrency and that currency, and the document must
 * carry its rate.
 */
export const FX_CHECKS = `
      assert(if .currency == null then true else realmConfig().multicurrency == true end; "This document is in another currency. Turn on multicurrency in the books' settings to post it.");
      assert(if .currency == null then true else .currency != realmConfig().currency end; "A document in the home currency leaves its currency empty.");
      assert(if .currency == null then true else (if realmConfig().currencies == null then false else ([.currency] - realmConfig().currencies | length == 0) end) end; "The books' settings don't list this document's currency.");
      assert(if .currency == null then true else .rateMicros > 0 end; "A document in another currency needs its exchange rate.");
      assert(if .rateMicros == null then true else ([.rateMicros | floor] == [.rateMicros]) end; "An exchange rate is stored in millionths, as a whole number.");`;

/** Set a draft's currency and rate; empty for the home currency. */
export const useCurrencyOperation = {
  base: 'transform',
  params: { currency: StringField, rateMicros: NumberField },
  transformations: {
    $bxl: `
      assert(if .status == null then true else .status == "draft" end; "Only a draft's currency can change.");
      assert(if params("currency") == null then params("rateMicros") == null else params("rateMicros") > 0 end; "A currency other than the home currency needs its exchange rate.");
      .currency = params("currency");
      .rateMicros = params("rateMicros");
    `,
  },
} as OperationDeclaration;

/**
 * A document's `journal` operation, made from its own `post`: every check its post makes, then the
 * document is recorded as journaled (its lines live in a journal month) rather than posted. The desk
 * sends it in one batch with JournalMonth.post, which appends those lines. Only the kinds a journal
 * records declare it.
 */
export const journalOperation = (post: { transformations?: unknown }) =>
  ({
    base: 'transform',
    transformations: {
      $bxl: (post.transformations as { $bxl: string }).$bxl.replace(
        '.status = "posted";',
        '.status = "journaled";',
      ),
    },
  }) as OperationDeclaration;

export class LedgerDocument extends CardDef {
  static displayName = 'Ledger document';
  static icon = BookIcon;
  @field docNo = contains(StringField);
  @field date = contains(IsoDateField); // YYYY-MM-DD; the month it posts in
  @field memo = contains(StringField);
  @field status = contains(DocumentStatusField); // only the post operation moves it
  @field enteredBy = contains(StringField); // stamped by the realm when the draft is created
  @field postedBy = contains(StringField); // stamped by the realm when it posts
  @field ledgerLines = containsMany(PostingLine, {
    computeVia: function (this: LedgerDocument) {
      return this.postings().map(
        (l) => new PostingLine({ date: this.date ?? '', ...l }),
      );
    },
  });
  @field totalMinor = contains(NumberField, {
    computeVia: function (this: LedgerDocument) {
      return this.total();
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: LedgerDocument) {
      return this.title();
    },
  });

  /** What the document posts. Debits and credits must balance. */
  postings(): PostingInput[] {
    return [];
  }
  total(): number {
    return (this.ledgerLines ?? []).reduce(
      (n, l) => n + (l?.debitMinor ?? 0),
      0,
    );
  }
  title(): string {
    return `${(this.constructor as typeof CardDef).displayName} ${this.docNo ?? ''}`;
  }
  facts(): Fact[] {
    return [];
  }
  /** Draft, Posted, or a document's own state (Paid, Deposited, …). */
  state(): string {
    return this.status === 'posted' ? 'Posted' : 'Draft';
  }
  party(): string {
    return '';
  }

  static isolated = class extends Component<typeof LedgerDocument> {
    get kind() {
      return (this.args.model.constructor as typeof CardDef).displayName;
    }
    get facts() {
      return this.args.model.facts?.() ?? [];
    }
    get state() {
      return this.args.model.state?.() ?? '';
    }
    get postLines() {
      return (this.args.model.ledgerLines ?? []).map((l) => ({
        accountCode: l?.account,
        accountName: [l?.cls, l?.loc, l?.party, l?.doc]
          .filter(Boolean)
          .join(' · '),
        debitMinor: l?.debitMinor ?? 0,
        creditMinor: l?.creditMinor ?? 0,
      }));
    }
    <template>
      <Sheet
        @eyebrow={{this.kind}}
        @title={{@model.cardTitle}}
        @meta={{@model.memo}}
        @figure={{money @model.totalMinor}}
        @figureLabel='Total'
        @status={{this.state}}
      >
        <Part @title={{this.kind}}><Facts @items={{this.facts}} /></Part>
        <Part @title='Posts to the ledger'><Lines
            @lines={{this.postLines}}
            @owner={{@model}}
            @context={{@context}}
            @viewCard={{@viewCard}}
          /></Part>
      </Sheet>
    </template>
  };
  static embedded = class extends Component<typeof LedgerDocument> {
    get kind() {
      return (this.args.model.constructor as typeof CardDef).displayName;
    }
    <template>
      <Strip
        @eyebrow={{this.kind}}
        @title={{@model.cardTitle}}
        @meta={{@model.date}}
        @figure={{money @model.totalMinor}}
      />
    </template>
  };
  static fitted = class extends Component<typeof LedgerDocument> {
    get kind() {
      return (this.args.model.constructor as typeof CardDef).displayName;
    }
    get party() {
      return this.args.model.party?.() ?? '';
    }
    <template>
      <Fit
        @eyebrow={{this.kind}}
        @title={{@model.docNo}}
        @figure={{money @model.totalMinor}}
        @meta={{this.party}}
      />
    </template>
  };
}
