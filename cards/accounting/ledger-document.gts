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
import { DocumentStatusField } from './ledger-status';

export class PostingLine extends FieldDef {
  static displayName = 'Ledger line';
  @field account = contains(StringField);
  @field debitMinor = contains(NumberField);
  @field creditMinor = contains(NumberField);
  @field date = contains(StringField);
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

export class LedgerDocument extends CardDef {
  static displayName = 'Ledger document';
  static icon = BookIcon;
  @field docNo = contains(StringField);
  @field date = contains(StringField); // YYYY-MM-DD; the month it posts in
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
