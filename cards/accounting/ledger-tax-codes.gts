// Sales tax the way QuickBooks keeps it: an agency collects at one or more rates, a tax code groups
// the rates a sale is taxed at (a state rate plus a city rate, or a federal and a provincial one),
// and each line of a sale carries a code. A document's tax lines, one per code and rate, are what
// it owes each agency. The codes the operations check against live in the books' settings
// (`taxCodes`), since that is what an operation can read; the TaxCode and TaxRate cards are the
// record people keep, and the Ledger flags any code the two disagree on.
import {
  CardDef,
  FieldDef,
  Component,
  field,
  contains,
  linksToMany,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import BookIcon from '@cardstack/boxel-icons/book-open';
import { Sheet, Part, Facts, Strip, Fit, money, type Fact } from './record-kit';
import { IsoDateField } from './ledger-dates';

const percent = (ppm: number | null | undefined) =>
  `${Number(((ppm ?? 0) / 10000).toFixed(4))}%`;

export class TaxRate extends CardDef {
  static displayName = 'Tax rate';
  static icon = BookIcon;
  @field name = contains(StringField);
  @field agencyId = contains(StringField); // the agency it's owed to
  @field ratePpm = contains(NumberField); // parts per million: 65000 is 6.5%
  @field startDate = contains(IsoDateField);
  @field endDate = contains(IsoDateField);
  @field cardTitle = contains(StringField, {
    computeVia: function (this: TaxRate) {
      return this.name ?? 'Tax rate';
    },
  });
  static isolated = class extends Component<typeof TaxRate> {
    get facts(): Fact[] {
      let m = this.args.model;
      return [
        { key: 'Rate', value: percent(m.ratePpm), strong: true },
        { key: 'Agency', value: m.agencyId ?? '', mono: true },
        { key: 'From', value: m.startDate ?? 'Always' },
        { key: 'Until', value: m.endDate ?? 'Still in effect' },
      ];
    }
    <template>
      <Sheet @eyebrow='Tax rate' @title={{@model.name}}><Part
          @title='Rate'
        ><Facts @items={{this.facts}} /></Part></Sheet>
    </template>
  };
  static embedded = class extends Component<typeof TaxRate> {
    get rate() {
      return percent(this.args.model.ratePpm);
    }
    <template>
      <Strip
        @eyebrow='Tax rate'
        @title={{@model.name}}
        @figure={{this.rate}}
        @meta={{@model.agencyId}}
      />
    </template>
  };
  static fitted = class extends Component<typeof TaxRate> {
    get rate() {
      return percent(this.args.model.ratePpm);
    }
    <template>
      <Fit
        @eyebrow='Tax rate'
        @title={{@model.name}}
        @figure={{this.rate}}
        @meta={{@model.agencyId}}
      />
    </template>
  };
}

export class TaxCode extends CardDef {
  static displayName = 'Tax code';
  static icon = BookIcon;
  @field code = contains(StringField); // the key lines and the books' settings use
  @field name = contains(StringField);
  @field rates = linksToMany(() => TaxRate); // none: the code is exempt
  @field exemptReason = contains(StringField); // for an exempt code, why
  @field combinedPpm = contains(NumberField, {
    computeVia: function (this: TaxCode) {
      return (this.rates ?? [])
        .filter(Boolean)
        .reduce((n, r) => n + (r!.ratePpm ?? 0), 0);
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: TaxCode) {
      return this.name ?? this.code ?? 'Tax code';
    },
  });
  /** The code as the books' settings hold it: one entry per rate. */
  components() {
    return (this.rates ?? [])
      .filter(Boolean)
      .map((r) => ({ agency: r!.agencyId ?? '', ratePpm: r!.ratePpm ?? 0 }));
  }
  static isolated = class extends Component<typeof TaxCode> {
    get facts(): Fact[] {
      let m = this.args.model;
      return [
        { key: 'Code', value: m.code ?? '', mono: true, strong: true },
        {
          key: 'Rate',
          value: (m.rates ?? []).filter(Boolean).length
            ? percent(m.combinedPpm)
            : `Exempt${m.exemptReason ? ` · ${m.exemptReason}` : ''}`,
        },
      ];
    }
    <template>
      <Sheet @eyebrow='Tax code' @title={{@model.cardTitle}}>
        <Part @title='Code'><Facts @items={{this.facts}} /></Part>
        <Part @title='Rates'><@fields.rates @format='embedded' /></Part>
      </Sheet>
    </template>
  };
  static embedded = class extends Component<typeof TaxCode> {
    get rate() {
      return percent(this.args.model.combinedPpm);
    }
    <template>
      <Strip
        @eyebrow='Tax code'
        @title={{@model.cardTitle}}
        @figure={{this.rate}}
        @meta={{@model.code}}
      />
    </template>
  };
  static fitted = class extends Component<typeof TaxCode> {
    get rate() {
      return percent(this.args.model.combinedPpm);
    }
    <template>
      <Fit
        @eyebrow='Tax code'
        @title={{@model.cardTitle}}
        @figure={{this.rate}}
        @meta={{@model.code}}
      />
    </template>
  };
}

/** What a sale owes one agency at one rate of one code. */
export class TaxLine extends FieldDef {
  static displayName = 'Tax line';
  @field code = contains(StringField);
  @field agencyId = contains(StringField);
  @field ratePpm = contains(NumberField);
  @field taxableMinor = contains(NumberField); // the lines taxed under the code
  @field taxMinor = contains(NumberField); // taxable × rate, rounded to the cent
}

// A sale's tax lines from its lines and the books' tax codes, in BXL. A line without a code takes the
// document's; lines are grouped by code, and each group owes every rate of its code. Written without
// `$variables` or a parenthesized merge, which the server's readable syntax doesn't keep.
const TAX_LINES = `[{doc: .taxCode} + .lines[] | {code: (if .taxCode == null then .doc else .taxCode end), amountMinor: .amountMinor}] | map(select(.code != null)) | map(select(.code != "")) | group_by(.code) | map({code: .[0].code, taxableMinor: (map(.amountMinor) | add), comp: realmConfig().taxCodes[.[0].code][]}) | map({code: .code, agencyId: .comp.agency, ratePpm: .comp.ratePpm, taxableMinor: .taxableMinor, taxMinor: [.taxableMinor * .comp.ratePpm / 1000000 | round][0]})`;
const CODES = `[{doc: .taxCode} + .lines[] | if .taxCode == null then .doc else .taxCode end] | map(select(. != null)) | map(select(. != ""))`;

/**
 * The tax checks a sale's `post` makes. A sale with tax codes must carry the tax lines the books'
 * codes give for its lines, so its tax is what the settings say; one without codes keeps its single
 * document rate.
 */
export const TAX_CHECKS = `
      assert(if ${CODES} | length == 0 then true else realmConfig().taxCodes != null end; "The books have no tax codes. Add them to the settings, then post.");
      assert(if ${CODES} | length == 0 then true else ${CODES} | unique | map(select(realmConfig().taxCodes[.] == null)) | length == 0 end; "A tax code on this sale isn't in the books' tax codes.");
      assert(if ${CODES} | length == 0 then true else [.taxLines + []] == [${TAX_LINES}] end; "The tax isn't calculated for these lines. Calculate the tax, then post.");
      assert(if [.taxLines + []] == [[]] then [[.lines[].amountMinor * .taxRatePpm] | add / 1000000 | round] == [.taxMinor] else [.taxMinor] == [[.taxLines[].taxMinor] | add] end; "The sales tax must be the tax rate times the amount.");`;

/** Sets a sale's tax lines and tax from its codes; the draft then shows, and posts, that tax. */
export const CALCULATE_TAX = `
      assert(${CODES} | length > 0; "Give the sale or its lines a tax code first.");
      assert(realmConfig().taxCodes != null; "The books have no tax codes. Add them to the settings first.");
      assert(${CODES} | unique | map(select(realmConfig().taxCodes[.] == null)) | length == 0; "A tax code on this sale isn't in the books' tax codes.");
      .taxLines = [${TAX_LINES}][0];
      .taxMinor = ([.taxLines[].taxMinor] + [0] | add);
      .taxRatePpm = null;
      .agencyId = null;`;

interface TaxedLike {
  agencyId?: string | null;
  taxMinor?: number | null;
  taxLines?:
    | (
        | {
            code?: string;
            agencyId?: string;
            taxableMinor?: number;
            taxMinor?: number;
          }
        | undefined
      )[]
    | null;
  lines?: ({ amountMinor?: number | null } | undefined)[] | null;
}

/**
 * What a sale owes one agency: its taxable amount and tax. A sale with tax lines owes what they
 * name, counting a code's taxable amount once however many of its rates the agency collects; one
 * without owes its single rate to its own agency.
 */
export function agencyTaxOf(d: TaxedLike, agencyId: string) {
  let taxLines = (d.taxLines ?? []).filter(Boolean);
  if (taxLines.length) {
    let mine = taxLines.filter((t) => t!.agencyId === agencyId);
    let taxable = new Map(mine.map((t) => [t!.code, t!.taxableMinor ?? 0]));
    return {
      taxableMinor: [...taxable.values()].reduce((n, x) => n + x, 0),
      taxMinor: mine.reduce((n, t) => n + (t!.taxMinor ?? 0), 0),
    };
  }
  return d.agencyId === agencyId
    ? {
        taxableMinor: (d.lines ?? []).reduce(
          (n, l) => n + (l?.amountMinor ?? 0),
          0,
        ),
        taxMinor: d.taxMinor ?? 0,
      }
    : { taxableMinor: 0, taxMinor: 0 };
}

/** A sale's tax by agency, for its 2200 credits: tax lines summed per agency, or its single rate. */
export function taxByAgency(
  d: TaxedLike,
): { agencyId: string; taxMinor: number }[] {
  let taxLines = (d.taxLines ?? []).filter(Boolean);
  if (!taxLines.length)
    return (d.taxMinor ?? 0) > 0
      ? [{ agencyId: d.agencyId ?? '', taxMinor: d.taxMinor ?? 0 }]
      : [];
  let by = new Map<string, number>();
  for (let t of taxLines)
    by.set(
      t!.agencyId ?? '',
      (by.get(t!.agencyId ?? '') ?? 0) + (t!.taxMinor ?? 0),
    );
  return [...by]
    .filter(([, taxMinor]) => taxMinor > 0)
    .map(([agencyId, taxMinor]) => ({ agencyId, taxMinor }));
}

/** A sale's tax, as the facts its document shows: by code and rate, or its single rate. */
export function taxFacts(
  d: TaxedLike & { taxRatePpm?: number | null },
): Fact[] {
  let taxLines = (d.taxLines ?? []).filter(Boolean);
  if (taxLines.length)
    return taxLines.map((t) => ({
      key: `Tax · ${t!.code ?? ''}`,
      value: `${money(t!.taxMinor)} (${percent((t as { ratePpm?: number }).ratePpm)} of ${money(t!.taxableMinor)} · ${t!.agencyId ?? ''})`,
    }));
  return (d.taxMinor ?? 0)
    ? [
        {
          key: 'Sales tax',
          value: `${money(d.taxMinor)} (${percent(d.taxRatePpm)} · ${d.agencyId ?? ''})`,
        },
      ]
    : [];
}
