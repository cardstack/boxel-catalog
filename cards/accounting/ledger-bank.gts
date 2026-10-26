// The bank feed: lines that come in from a bank statement and wait to be matched to the books, added
// to them, or excluded; the receipt of each import; and the rules that suggest how a line is
// categorized. A bank line posts nothing itself. Adding one posts a journal entry in the same batch
// that marks the line added, so the feed and the books can't disagree.
import {
  CardDef,
  FieldDef,
  Component,
  field,
  contains,
  containsMany,
  linksToMany,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import BooleanField from '@cardstack/base/boolean';
import LandmarkIcon from '@cardstack/boxel-icons/landmark';
import {
  operation,
  bxl,
  type OperationDeclaration,
} from '@cardstack/base/operations';
import {
  Sheet,
  Part,
  Facts,
  Strip,
  Fit,
  money,
  day,
  type Fact,
} from './record-kit';
import { IsoDateField } from './ledger-dates';
import { BankLineStatusField } from './ledger-status';

const STATUS_LABEL: Record<string, string> = {
  'for-review': 'For review',
  matched: 'Matched',
  added: 'Added',
  excluded: 'Excluded',
};
export const bankLineState = (status: string | undefined) =>
  STATUS_LABEL[status ?? 'for-review'] ?? 'For review';
const isIn = (amount: number | undefined) => (amount ?? 0) > 0;
const isOff = (active: boolean | undefined) => active === false;
const count = (n: number | undefined) => String(n ?? 0);

/** One line of a bank or card statement. Money in is positive, money out negative. */
export class BankTransaction extends CardDef {
  static displayName = 'Bank transaction';
  static icon = LandmarkIcon;
  @field account = contains(StringField); // the bank or card account in the chart
  @field externalId = contains(StringField); // the bank's own ID for the line
  @field date = contains(IsoDateField);
  @field description = contains(StringField);
  @field amountMinor = contains(NumberField);
  @field reference = contains(StringField); // a check number or the bank's reference
  @field payee = contains(StringField);
  @field importNo = contains(StringField); // the import it came in with
  @field status = contains(BankLineStatusField);
  @field category = contains(StringField); // the account it was added to
  @field matchedKey = contains(StringField); // the journal posting it was matched to or added as
  @field excludedReason = contains(StringField);
  @field reviewedBy = contains(StringField);
  @field importKey = contains(StringField, {
    computeVia: function (this: BankTransaction) {
      return `${this.account ?? ''}|${this.externalId ?? ''}`;
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: BankTransaction) {
      return this.description || this.payee || this.externalId || 'Bank line';
    },
  });

  /** Mark the line added, naming the journal posting the same batch posts for it. */
  @operation static add = {
    base: 'transform',
    params: { key: StringField, category: StringField },
    transformations: bxl`
      assert(if .status == null then true else .status == "for-review" end; "Only a line waiting for review can be added.");
      assert(params("key") != null; "Name the journal posting this line was added as.");
      assert(params("category") != null; "Say which account the line goes to.");
      assert(params("category") != .account; "A bank line can't be added to its own bank account.");
      .status = "added";
      .matchedKey = params("key");
      .category = params("category");
      .reviewedBy = actor();
    `,
  } satisfies OperationDeclaration;
  /** Mark the line matched to a posting already in the books. */
  @operation static match = {
    base: 'transform',
    params: { key: StringField },
    transformations: bxl`
      assert(if .status == null then true else .status == "for-review" end; "Only a line waiting for review can be matched.");
      assert(params("key") != null; "Name the journal posting this line matches.");
      .status = "matched";
      .matchedKey = params("key");
      .reviewedBy = actor();
    `,
  } satisfies OperationDeclaration;
  /** Put a matched or added line back for review: the desk sends it when the posting it names is reversed. */
  @operation static unmatch = {
    base: 'transform',
    transformations: bxl`
      assert([.status == "matched", .status == "added"] | any; "Only a matched or added line can go back for review.");
      .status = "for-review";
      .matchedKey = null;
      .category = null;
      .reviewedBy = null;
    `,
  } satisfies OperationDeclaration;
  /** Leave the line out of the books, saying why. */
  @operation static exclude = {
    base: 'transform',
    params: { reason: StringField },
    transformations: bxl`
      assert(if .status == null then true else .status == "for-review" end; "Only a line waiting for review can be excluded.");
      .status = "excluded";
      .excludedReason = params("reason");
      .reviewedBy = actor();
    `,
  } satisfies OperationDeclaration;
  /** Put an excluded line back up for review. */
  @operation static restore = {
    base: 'transform',
    transformations: bxl`
      assert(.status == "excluded"; "Only an excluded line can be put back for review.");
      .status = "for-review";
      .excludedReason = null;
      .reviewedBy = null;
    `,
  } satisfies OperationDeclaration;

  /** Refuse the batch it's in. An import sends it to lines already in the feed with a bank ID the file
   *  brings again, so two imports of one file can't both land. */
  @operation static refuseReimport = {
    base: 'transform',
    transformations: bxl`
      assert(false; "A line with this bank ID is already in the feed for this account. Nothing was imported; read the file again.");
    `,
  } satisfies OperationDeclaration;

  /** What the line says and what became of it; the desk's drawer reads this too. */
  facts(): Fact[] {
    return [
      { key: 'Account', value: this.account ?? '', mono: true },
      { key: 'Date', value: day(this.date) },
      { key: 'Description', value: this.description ?? '' },
      ...(this.payee ? [{ key: 'Payee', value: this.payee }] : []),
      ...(this.reference
        ? [{ key: 'Reference', value: this.reference, mono: true }]
        : []),
      { key: 'Bank ID', value: this.externalId ?? '', mono: true },
      { key: 'Import', value: this.importNo ?? '', mono: true },
      ...(this.category
        ? [{ key: 'Added to', value: this.category, mono: true }]
        : []),
      ...(this.matchedKey
        ? [{ key: 'Journal posting', value: this.matchedKey, mono: true }]
        : []),
      ...(this.excludedReason
        ? [{ key: 'Excluded because', value: this.excludedReason }]
        : []),
      ...(this.reviewedBy
        ? [{ key: 'Reviewed by', value: this.reviewedBy }]
        : []),
    ];
  }

  static isolated = class extends Component<typeof BankTransaction> {
    get facts(): Fact[] {
      return this.args.model.facts?.() ?? [];
    }
    get state() {
      return bankLineState(this.args.model.status);
    }
    <template>
      <Sheet
        @eyebrow='Bank transaction'
        @title={{@model.cardTitle}}
        @figureMinor={{@model.amountMinor}}
        @figureLabel={{if (isIn @model.amountMinor) 'Money in' 'Money out'}}
        @status={{this.state}}
      ><Part @title='From the bank'><Facts
            @items={{this.facts}}
          /></Part></Sheet>
    </template>
  };
  static embedded = class extends Component<typeof BankTransaction> {
    get meta() {
      let m = this.args.model;
      return `${day(m.date)} · ${bankLineState(m.status)}`;
    }
    <template>
      <Strip
        @eyebrow='Bank transaction'
        @title={{@model.cardTitle}}
        @figure={{money @model.amountMinor}}
        @meta={{this.meta}}
      />
    </template>
  };
  static fitted = class extends Component<typeof BankTransaction> {
    <template>
      <Fit
        @eyebrow='Bank line'
        @title={{@model.cardTitle}}
        @figure={{money @model.amountMinor}}
        @meta={{@model.account}}
      />
    </template>
  };
}

/** A row of a statement file that wasn't imported, and why. */
export class ImportRejection extends FieldDef {
  static displayName = 'Rejected row';
  @field row = contains(NumberField);
  @field reason = contains(StringField);
}

/** The receipt of one statement import: what came in, what was already there, and what was refused. */
export class BankStatementImport extends CardDef {
  static displayName = 'Statement import';
  static icon = LandmarkIcon;
  @field importNo = contains(StringField);
  @field account = contains(StringField);
  @field fileName = contains(StringField);
  @field format = contains(StringField); // csv or ofx
  @field contentHash = contains(StringField); // SHA-256 of the file
  @field importedOn = contains(IsoDateField);
  @field firstDate = contains(IsoDateField);
  @field lastDate = contains(IsoDateField);
  @field acceptedCount = contains(NumberField);
  @field skippedCount = contains(NumberField); // already imported, unchanged
  @field rejected = containsMany(ImportRejection);
  @field importedBy = contains(StringField);
  @field lines = linksToMany(() => BankTransaction, {
    query: {
      filter: { eq: { importNo: '$this.importNo' } },
      page: { size: 500 },
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: BankStatementImport) {
      return `Import ${this.importNo ?? ''} · ${this.account ?? ''}`;
    },
  });

  static isolated = class extends Component<typeof BankStatementImport> {
    get facts(): Fact[] {
      let m = this.args.model;
      return [
        { key: 'Account', value: m.account ?? '', mono: true },
        { key: 'File', value: m.fileName ?? '' },
        { key: 'Format', value: (m.format ?? '').toUpperCase() },
        { key: 'Imported', value: day(m.importedOn) },
        { key: 'Imported by', value: m.importedBy ?? '' },
        {
          key: 'Covers',
          value: m.firstDate ? `${day(m.firstDate)} – ${day(m.lastDate)}` : '',
        },
        { key: 'New lines', value: String(m.acceptedCount ?? 0), strong: true },
        { key: 'Already imported', value: String(m.skippedCount ?? 0) },
        { key: 'Refused', value: String((m.rejected ?? []).length) },
        {
          key: 'File hash',
          value: (m.contentHash ?? '').slice(0, 16),
          mono: true,
        },
      ];
    }
    get refusals(): Fact[] {
      return (this.args.model.rejected ?? [])
        .filter(Boolean)
        .map((r) => ({ key: `Row ${r!.row}`, value: r!.reason ?? '' }));
    }
    <template>
      <Sheet
        @eyebrow='Statement import'
        @title={{@model.cardTitle}}
        @figure={{count @model.acceptedCount}}
        @figureLabel='New lines'
      ><Part @title='The file'><Facts @items={{this.facts}} /></Part>
        {{#if this.refusals.length}}<Part @title='Rows refused'><Facts
              @items={{this.refusals}}
            /></Part>{{/if}}
        <Part @title='Lines'><div class='lines'>{{#each
              @fields.lines
              as |Line|
            }}<Line @format='embedded' />{{/each}}</div></Part></Sheet>
      <style scoped>
        .lines {
          display: grid;
          gap: var(--boxel-sp-xs);
        }
      </style>
    </template>
  };
  static embedded = class extends Component<typeof BankStatementImport> {
    <template>
      <Strip
        @eyebrow='Statement import'
        @title={{@model.cardTitle}}
        @figure={{count @model.acceptedCount}}
        @meta={{@model.fileName}}
      />
    </template>
  };
  static fitted = class extends Component<typeof BankStatementImport> {
    <template>
      <Fit
        @eyebrow='Import'
        @title={{@model.importNo}}
        @figure={{count @model.acceptedCount}}
        @meta={{@model.account}}
      />
    </template>
  };
}

/** Suggests how bank lines are categorized. A rule never posts: the line still needs a person to add it. */
export class BankRule extends CardDef {
  static displayName = 'Bank rule';
  static icon = LandmarkIcon;
  @field name = contains(StringField);
  @field account = contains(StringField); // the bank or card account it watches; empty for any
  @field descriptionContains = contains(StringField);
  @field direction = contains(StringField); // in, out, or empty for either
  @field minMinor = contains(NumberField);
  @field maxMinor = contains(NumberField);
  @field category = contains(StringField); // the account it suggests
  @field payee = contains(StringField);
  @field cls = contains(StringField);
  @field priority = contains(NumberField); // lower runs first
  @field active = contains(BooleanField);
  @field cardTitle = contains(StringField, {
    computeVia: function (this: BankRule) {
      return this.name || 'Bank rule';
    },
  });

  static isolated = class extends Component<typeof BankRule> {
    get when(): Fact[] {
      let m = this.args.model;
      return [
        { key: 'Account', value: m.account || 'Any bank or card account' },
        {
          key: 'Direction',
          value:
            m.direction === 'in'
              ? 'Money in'
              : m.direction === 'out'
                ? 'Money out'
                : 'Either',
        },
        ...(m.descriptionContains
          ? [{ key: 'Description contains', value: m.descriptionContains }]
          : []),
        ...(m.minMinor != null
          ? [{ key: 'At least', value: money(m.minMinor) }]
          : []),
        ...(m.maxMinor != null
          ? [{ key: 'At most', value: money(m.maxMinor) }]
          : []),
        { key: 'Priority', value: String(m.priority ?? 0) },
        { key: 'Active', value: m.active === false ? 'No' : 'Yes' },
      ];
    }
    get then(): Fact[] {
      let m = this.args.model;
      return [
        { key: 'Account', value: m.category ?? '', mono: true, strong: true },
        ...(m.payee ? [{ key: 'Payee', value: m.payee }] : []),
        ...(m.cls ? [{ key: 'Class', value: m.cls }] : []),
      ];
    }
    <template>
      <Sheet
        @eyebrow='Bank rule'
        @title={{@model.cardTitle}}
        @status={{if (isOff @model.active) 'Inactive' 'Active'}}
        @note='A rule suggests; adding a line to the books is still a person’s decision.'
      ><Part @title='When a line'><Facts @items={{this.when}} /></Part><Part
          @title='Suggest'
        ><Facts @items={{this.then}} /></Part></Sheet>
    </template>
  };
  static embedded = class extends Component<typeof BankRule> {
    <template>
      <Strip
        @eyebrow='Bank rule'
        @title={{@model.cardTitle}}
        @figure={{@model.category}}
        @meta={{@model.descriptionContains}}
      />
    </template>
  };
  static fitted = class extends Component<typeof BankRule> {
    <template>
      <Fit
        @eyebrow='Rule'
        @title={{@model.cardTitle}}
        @meta={{@model.category}}
      />
    </template>
  };
}
