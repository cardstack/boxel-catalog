// Inventory, card-native: stock lots, roasting, landed cost, fulfillment (cost of goods sold) and
// count adjustments.
//
// A StockLot is one FIFO cost layer: what's left of it and what that's left of costs, split between
// green coffee and roasting (5000) and packaging (5100). Only its operations change it: `draw` takes
// stock out at the lot's own rate (remaining cost × quantity ÷ remaining quantity, all of it on the
// last draw) and refuses to overdraw. (The rounding check is cross-multiplied: BXL mis-evaluates
// parenthesized arithmetic.) `addCost` adds landed cost. Every document that moves stock is
// posted in one batch with the draws it makes, so the document and the lots land together or not at
// all. Which lots to draw (oldest first) is chosen by whoever enters the document; the realm checks
// each draw against the lot.
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
import BookIcon from '@cardstack/boxel-icons/book-open';
import {
  operation,
  instance,
  bxl,
  type OperationDeclaration,
} from '@cardstack/base/operations';
import {
  LedgerDocument,
  type PostingInput,
  journalOperation,
} from './ledger-document';
import {
  Sheet,
  Part,
  Facts,
  Strip,
  Fit,
  money,
  day,
  percent,
  partialNote,
  type Fact,
} from './record-kit';
import {
  StatementTable,
  type StatementColumn as Col,
  type StatementRow as Line,
} from './components/statement-table';

const sum = (xs: (number | undefined)[]) =>
  xs.reduce<number>((n, x) => n + (x ?? 0), 0);
const qtyText = (milli: number | undefined) =>
  ((milli ?? 0) / 1000).toLocaleString('en-US', { maximumFractionDigits: 3 });

// ── stock lots ───────────────────────────────────────────────────────────────
export class StockLot extends CardDef {
  static displayName = 'Stock lot';
  static icon = BookIcon;
  @field sku = contains(StringField);
  @field lot = contains(StringField);
  @field received = contains(StringField); // YYYY-MM-DD; FIFO order
  @field asset = contains(StringField); // the inventory account the lot sits in
  @field source = contains(StringField); // the bill, roast batch or opening balances it came from
  @field qty = contains(NumberField); // thousandths of a unit, as received
  @field costMinor = contains(NumberField); // as received, before landed cost
  @field consumedQty = contains(NumberField); // written only by draw
  @field landedMinor = contains(NumberField); // written only by addCost
  @field part5000Minor = contains(NumberField); // remaining cost on green coffee and roasting
  @field part5100Minor = contains(NumberField); // remaining cost on packaging
  @field retiredBy = contains(StringField); // the reversal that undid the roast that made this lot
  @field remainingQty = contains(NumberField, {
    computeVia: function (this: StockLot) {
      return (this.qty ?? 0) - (this.consumedQty ?? 0);
    },
  });
  @field remainingCostMinor = contains(NumberField, {
    computeVia: function (this: StockLot) {
      return (this.part5000Minor ?? 0) + (this.part5100Minor ?? 0);
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: StockLot) {
      return `${this.sku ?? ''} · ${this.lot ?? ''}`;
    },
  });

  /** Take stock out of this lot. Sent in the same batch as the document that uses it. */
  @operation static draw = {
    base: 'transform',
    params: {
      qty: NumberField,
      costMinor: NumberField,
      part5000Minor: NumberField,
      part5100Minor: NumberField,
      docNo: StringField,
    },
    transformations: bxl`
      assert(params("qty") > 0; "A draw takes a positive quantity.");
      assert([.qty] + [0 - .consumedQty - params("qty")] | add | . >= 0; "Not enough left in this lot.");
      assert([.part5000Minor * params("qty") * 2, .part5100Minor * params("qty") * 2, 0 - params("costMinor") * .qty * 2, params("costMinor") * .consumedQty * 2, 0 - .qty, .consumedQty] | add | . <= 0; "A draw costs its share of what's left: remaining cost × quantity ÷ remaining quantity, rounded.");
      assert([params("costMinor") * .qty * 2, 0 - params("costMinor") * .consumedQty * 2, 0 - .part5000Minor * params("qty") * 2, 0 - .part5100Minor * params("qty") * 2, 0 - .qty, .consumedQty] | add | . <= 0; "A draw costs its share of what's left: remaining cost × quantity ÷ remaining quantity, rounded.");
      assert([params("part5000Minor"), params("part5100Minor")] | all(. >= 0); "A cost split can't be negative.");
      assert([params("part5000Minor") + params("part5100Minor")] == [params("costMinor")]; "The cost split must add up to the cost.");
      assert([.part5000Minor - params("part5000Minor"), .part5100Minor - params("part5100Minor")] | all(. >= 0); "That takes more of a cost account than the lot has left.");
      .consumedQty |= . + params("qty");
      .part5000Minor |= . - params("part5000Minor");
      .part5100Minor |= . - params("part5100Minor");
    `,
  } satisfies OperationDeclaration;
  /** Put back what a draw took, when the posting that drew it is reversed: the same quantity at the
   *  same cost. Sent in the same batch as the reversal. */
  @operation static restore = {
    base: 'transform',
    params: {
      qty: NumberField,
      costMinor: NumberField,
      part5000Minor: NumberField,
      part5100Minor: NumberField,
      docNo: StringField,
    },
    transformations: bxl`
      assert(params("qty") > 0; "A restore puts back a positive quantity.");
      assert([.consumedQty - params("qty")] | all(. >= 0); "That puts back more than was ever drawn from this lot.");
      assert([params("part5000Minor"), params("part5100Minor")] | all(. >= 0); "A cost split can't be negative.");
      assert([params("part5000Minor") + params("part5100Minor")] == [params("costMinor")]; "The cost split must add up to the cost.");
      assert(.retiredBy == null; "This lot was retired when its roast was reversed.");
      .consumedQty |= . - params("qty");
      .part5000Minor |= . + params("part5000Minor");
      .part5100Minor |= . + params("part5100Minor");
    `,
  } satisfies OperationDeclaration;
  /** Take landed cost back off this lot, when the landed-cost posting is reversed. */
  @operation static removeCost = {
    base: 'transform',
    params: { amountMinor: NumberField, docNo: StringField },
    transformations: bxl`
      assert(params("amountMinor") > 0; "The amount taken off must be positive.");
      assert([.landedMinor - params("amountMinor"), .part5000Minor - params("amountMinor")] | all(. >= 0); "That takes off more landed cost than this lot carries.");
      .part5000Minor |= . - params("amountMinor");
      .landedMinor |= . - params("amountMinor");
    `,
  } satisfies OperationDeclaration;
  /** Retire a lot a roast made, when the roast is reversed: only while none of it has been used. */
  @operation static retire = {
    base: 'transform',
    params: { docNo: StringField },
    transformations: bxl`
      assert([.consumedQty + 0] | all(. == 0); "Some of this lot has been used. Reverse what used it first.");
      assert(.retiredBy == null; "This lot is already retired.");
      .consumedQty = .qty;
      .part5000Minor = 0;
      .part5100Minor = 0;
      .retiredBy = params("docNo");
    `,
  } satisfies OperationDeclaration;
  /** Add landed cost (freight, duty) to this lot. Sent in the same batch as the LandedCost post. */
  @operation static addCost = {
    base: 'transform',
    params: { amountMinor: NumberField, docNo: StringField },
    transformations: bxl`
      assert(params("amountMinor") > 0; "Landed cost must be positive.");
      assert([.qty] + [0 - .consumedQty] | add | . > 0; "Landed cost goes on a lot that still has stock.");
      .part5000Minor |= . + params("amountMinor");
      .landedMinor |= . + params("amountMinor");
    `,
  } satisfies OperationDeclaration;

  static isolated = class extends Component<typeof StockLot> {
    get facts(): Fact[] {
      let m = this.args.model;
      return [
        { key: 'Product', value: m.sku ?? '', mono: true },
        { key: 'Received', value: day(m.received) },
        { key: 'From', value: m.source ?? '' },
        { key: 'Quantity received', value: qtyText(m.qty) },
        { key: 'Remaining', value: qtyText(m.remainingQty), strong: true },
        { key: 'Cost received', value: money(m.costMinor) },
        ...((m.landedMinor ?? 0)
          ? [{ key: 'Landed cost added', value: money(m.landedMinor) }]
          : []),
        {
          key: 'Remaining cost',
          value: money(m.remainingCostMinor),
          strong: true,
        },
        {
          key: 'of which green and roasting (5000)',
          value: money(m.part5000Minor),
        },
        { key: 'of which packaging (5100)', value: money(m.part5100Minor) },
      ];
    }
    <template>
      <Sheet
        @eyebrow='Stock lot'
        @title={{@model.cardTitle}}
        @figureMinor={{@model.remainingCostMinor}}
        @figureLabel='Remaining cost'
        @status={{if @model.remainingQty 'On hand' 'Used up'}}
      ><Part @title='Lot'><Facts @items={{this.facts}} /></Part></Sheet>
    </template>
  };
  static embedded = class extends Component<typeof StockLot> {
    <template>
      <Strip
        @eyebrow='Stock lot'
        @title={{@model.cardTitle}}
        @meta={{@model.received}}
        @figure={{money @model.remainingCostMinor}}
      />
    </template>
  };
  static fitted = class extends Component<typeof StockLot> {
    <template>
      <Fit
        @eyebrow='Lot'
        @title={{@model.lot}}
        @figure={{money @model.remainingCostMinor}}
        @meta={{@model.sku}}
      />
    </template>
  };
}

/** One draw on one lot: what a roast, a sale or a count takes, at the lot's cost. */
export class Draw extends FieldDef {
  static displayName = 'Draw';
  @field sku = contains(StringField);
  @field lot = contains(StringField);
  @field asset = contains(StringField);
  @field qty = contains(NumberField);
  @field costMinor = contains(NumberField);
  @field part5000Minor = contains(NumberField);
  @field part5100Minor = contains(NumberField);
}
export class LandedAllocation extends FieldDef {
  static displayName = 'Landed cost allocation';
  @field sku = contains(StringField);
  @field lot = contains(StringField);
  @field asset = contains(StringField);
  @field amountMinor = contains(NumberField);
}
const drawFacts = (draws: (Draw | undefined)[] | undefined): Fact[] =>
  (draws ?? []).filter(Boolean).map((d) => ({
    key: `${d!.lot ?? ''}`,
    value: `${qtyText(d!.qty)} · ${money(d!.costMinor)}`,
  }));

// ── roast batches ────────────────────────────────────────────────────────────
export class RoastBatch extends LedgerDocument {
  static displayName = 'Roast batch';
  static icon = BookIcon;
  @field loc = contains(StringField);
  @field inputs = containsMany(Draw); // green coffee and packaging drawn
  @field outputSku = contains(StringField);
  @field outputLot = contains(StringField);
  @field outputAsset = contains(StringField);
  @field outputQty = contains(NumberField);
  @field outputPart5000Minor = contains(NumberField); // must equal the inputs' green cost
  @field outputPart5100Minor = contains(NumberField); // must equal the inputs' packaging cost
  @field chargedWeight = contains(NumberField);
  @field finishedWeight = contains(NumberField);
  @field roastLog = contains(StringField);

  postings(): PostingInput[] {
    let inputs = (this.inputs ?? []).filter(Boolean);
    return [
      ...inputs.map((d) => ({
        account: d.asset,
        debitMinor: 0,
        creditMinor: d.costMinor,
        loc: this.loc,
        doc: d.lot,
      })),
      {
        account: this.outputAsset ?? '',
        debitMinor: sum(inputs.map((d) => d.costMinor)),
        creditMinor: 0,
        loc: this.loc,
        doc: this.outputLot,
      },
    ];
  }
  title() {
    return `Roast batch ${this.docNo ?? ''}`;
  }
  party() {
    return this.outputSku ?? '';
  }
  facts(): Fact[] {
    let yieldPct =
      this.chargedWeight && this.finishedWeight
        ? percent(this.finishedWeight / this.chargedWeight)
        : '';
    return [
      { key: 'Batch', value: this.docNo ?? '', mono: true },
      { key: 'Roasted', value: day(this.date) },
      {
        key: 'Makes',
        value: `${this.outputSku ?? ''} × ${qtyText(this.outputQty)}`,
      },
      ...(yieldPct
        ? [
            {
              key: 'Charged → finished',
              value: `${qtyText(this.chargedWeight)} lb → ${qtyText(this.finishedWeight)} lb (${yieldPct})`,
            },
          ]
        : []),
      ...drawFacts(this.inputs),
      { key: 'Posted by', value: this.postedBy ?? '' },
    ];
  }

  @operation static post = {
    base: 'transform',
    transformations: bxl`
      assert(if .status == null then true else .status == "draft" end; "Only a draft roast batch can be posted. This one is already posted.");
      assert((.inputs | length) > 0; "A roast needs at least one input.");
      assert(([.inputs[].qty, .inputs[].costMinor | type] | unique) == ["number"]; "Every input needs a quantity and a cost.");
      assert([.inputs[].qty] | all(. > 0); "Every input takes a positive quantity.");
      assert([.inputs[] | .part5000Minor + .part5100Minor] == [.inputs[].costMinor]; "Each input's cost split must add up to its cost.");
      assert([.inputs[].part5000Minor] + [0 - .outputPart5000Minor] | add | . == 0; "The roasted lot must carry exactly the green cost drawn.");
      assert([.inputs[].part5100Minor] + [0 - .outputPart5100Minor] | add | . == 0; "The roasted lot must carry exactly the packaging cost drawn.");
      assert(.outputQty > 0; "A roast makes a positive quantity.");
      assert(.date > realmConfig().closedThrough; "That date is on or before the closing date, so the roast can't post.");
      assert(if realmConfig().chart == null then true else (([.inputs[].asset, .outputAsset] - [null, ""]) - realmConfig().chart | length == 0) end; "An account on this roast isn't in the chart of accounts. Add it to the chart, then post.");
      .status = "posted";
      .postedBy = actor();
    `,
  } satisfies OperationDeclaration;
  /** Post it into a journal month: every check `post` makes, recorded as journaled. The desk sends
   *  the lot operations it implies in the same batch. */
  @operation static journal = journalOperation(this.post);
  /** The roasted lot this batch makes, carrying exactly the cost the post checked. Sent with post. */
  @operation static produceLot = {
    base: 'create',
    of: StockLot,
    fill: {
      sku: instance('outputSku'),
      lot: instance('outputLot'),
      asset: instance('outputAsset'),
      received: instance('date'),
      source: instance('docNo'),
      qty: instance('outputQty'),
      consumedQty: 0,
      landedMinor: 0,
      costMinor: 0,
      part5000Minor: instance('outputPart5000Minor'),
      part5100Minor: instance('outputPart5100Minor'),
    },
  } satisfies OperationDeclaration;
}

// ── fulfillment: the stock a sale ships, and its cost of goods sold ─────────
export class Fulfillment extends LedgerDocument {
  static displayName = 'Fulfillment';
  static icon = BookIcon;
  @field saleNo = contains(StringField); // the invoice or sales receipt
  @field customerId = contains(StringField);
  @field cls = contains(StringField);
  @field loc = contains(StringField);
  @field draws = containsMany(Draw);

  postings(): PostingInput[] {
    let draws = (this.draws ?? []).filter(Boolean),
      g = sum(draws.map((d) => d.part5000Minor)),
      p = sum(draws.map((d) => d.part5100Minor));
    return [
      ...(g
        ? [
            {
              account: '5000',
              debitMinor: g,
              creditMinor: 0,
              cls: this.cls,
              loc: this.loc,
            },
          ]
        : []),
      ...(p
        ? [
            {
              account: '5100',
              debitMinor: p,
              creditMinor: 0,
              cls: this.cls,
              loc: this.loc,
            },
          ]
        : []),
      ...draws.map((d) => ({
        account: d.asset,
        debitMinor: 0,
        creditMinor: d.costMinor,
        cls: this.cls,
        loc: this.loc,
        doc: d.lot,
      })),
    ];
  }
  title() {
    return `Fulfillment of ${this.saleNo ?? ''}`;
  }
  party() {
    return this.customerId ?? '';
  }
  facts(): Fact[] {
    return [
      { key: 'Sale', value: this.saleNo ?? '', mono: true },
      { key: 'Customer', value: this.customerId ?? '' },
      { key: 'Shipped', value: day(this.date) },
      ...drawFacts(this.draws),
      { key: 'Posted by', value: this.postedBy ?? '' },
    ];
  }

  @operation static post = {
    base: 'transform',
    transformations: bxl`
      assert(if .status == null then true else .status == "draft" end; "Only a draft fulfillment can be posted. This one is already posted.");
      assert((.draws | length) > 0; "A fulfillment draws at least one lot.");
      assert([.draws[].qty] | all(. > 0); "Every draw takes a positive quantity.");
      assert([.draws[] | .part5000Minor + .part5100Minor] == [.draws[].costMinor]; "Each draw's cost split must add up to its cost.");
      assert(.saleNo != null; "Say which sale this ships.");
      assert(.date > realmConfig().closedThrough; "That date is on or before the closing date, so the fulfillment can't post.");
      assert(if realmConfig().chart == null then true else (([.draws[].asset] - [null, ""]) - realmConfig().chart | length == 0) end; "An account on this fulfillment isn't in the chart of accounts. Add it to the chart, then post.");
      .status = "posted";
      .postedBy = actor();
    `,
  } satisfies OperationDeclaration;
  /** Post it into a journal month: every check `post` makes, recorded as journaled. The desk sends
   *  the lot operations it implies in the same batch. */
  @operation static journal = journalOperation(this.post);
  /** Replace a draft's draws, when the lots changed after it was drafted. The desk prices them again
   *  from the lots; the lots' own draws check each cost when it posts. */
  @operation static useDraws = {
    base: 'transform',
    params: { draws: Draw },
    transformations: bxl`
      assert(if .status == null then true else .status == "draft" end; "Only a draft's draws can change.");
      assert((params("draws") | length) > 0; "A draft needs at least one draw.");
      .draws = params("draws");
    `,
  } satisfies OperationDeclaration;
}

// ── count adjustments: what a physical count found missing ──────────────────
export class CountAdjustment extends LedgerDocument {
  static displayName = 'Count adjustment';
  static icon = BookIcon;
  @field reason = contains(StringField);
  @field account = contains(StringField); // shrink (5200)
  @field draws = containsMany(Draw);

  postings(): PostingInput[] {
    let draws = (this.draws ?? []).filter(Boolean);
    return [
      {
        account: this.account ?? '',
        debitMinor: sum(draws.map((d) => d.costMinor)),
        creditMinor: 0,
      },
      ...draws.map((d) => ({
        account: d.asset,
        debitMinor: 0,
        creditMinor: d.costMinor,
        doc: d.lot,
      })),
    ];
  }
  title() {
    return `Count ${this.docNo ?? ''}`;
  }
  facts(): Fact[] {
    return [
      { key: 'Count', value: this.docNo ?? '', mono: true },
      { key: 'Date', value: day(this.date) },
      { key: 'Reason', value: this.reason ?? '' },
      ...drawFacts(this.draws),
      { key: 'Posted by', value: this.postedBy ?? '' },
    ];
  }

  @operation static post = {
    base: 'transform',
    transformations: bxl`
      assert(if .status == null then true else .status == "draft" end; "Only a draft count adjustment can be posted. This one is already posted.");
      assert((.draws | length) > 0; "A count adjustment draws at least one lot.");
      assert([.draws[].qty] | all(. > 0); "Every draw takes a positive quantity.");
      assert([.draws[] | .part5000Minor + .part5100Minor] == [.draws[].costMinor]; "Each draw's cost split must add up to its cost.");
      assert(.reason != null; "Every count adjustment needs a reason.");
      assert(.account != null; "Say which account takes the shrink.");
      assert(.date > realmConfig().closedThrough; "That date is on or before the closing date, so the adjustment can't post.");
      assert(if realmConfig().chart == null then true else (([.account, .draws[].asset] - [null, ""]) - realmConfig().chart | length == 0) end; "An account on this adjustment isn't in the chart of accounts. Add it to the chart, then post.");
      .status = "posted";
      .postedBy = actor();
    `,
  } satisfies OperationDeclaration;
  /** Post it into a journal month: every check `post` makes, recorded as journaled. The desk sends
   *  the lot operations it implies in the same batch. */
  @operation static journal = journalOperation(this.post);
  /** Replace a draft's draws, when the lots changed after it was drafted. The desk prices them again
   *  from the lots; the lots' own draws check each cost when it posts. */
  @operation static useDraws = {
    base: 'transform',
    params: { draws: Draw },
    transformations: bxl`
      assert(if .status == null then true else .status == "draft" end; "Only a draft's draws can change.");
      assert((params("draws") | length) > 0; "A draft needs at least one draw.");
      .draws = params("draws");
    `,
  } satisfies OperationDeclaration;
}

// ── landed cost: freight and duty moved from clearing into the lots ─────────
export class LandedCost extends LedgerDocument {
  static displayName = 'Landed cost';
  static icon = BookIcon;
  @field driver = contains(StringField); // weight or value
  @field clearingAccount = contains(StringField); // 1230
  @field amountMinor = contains(NumberField);
  @field allocations = containsMany(LandedAllocation);

  postings(): PostingInput[] {
    let a = (this.allocations ?? []).filter(Boolean);
    return [
      ...a.map((x) => ({
        account: x.asset,
        debitMinor: x.amountMinor,
        creditMinor: 0,
        doc: x.lot,
      })),
      {
        account: this.clearingAccount ?? '',
        debitMinor: 0,
        creditMinor: this.amountMinor ?? 0,
        doc: this.docNo,
      },
    ];
  }
  title() {
    return `Landed cost ${this.docNo ?? ''}`;
  }
  facts(): Fact[] {
    return [
      { key: 'Allocated', value: day(this.date), strong: true },
      { key: 'By', value: this.driver ?? '' },
      ...(this.allocations ?? [])
        .filter(Boolean)
        .map((x) => ({ key: x!.lot ?? '', value: money(x!.amountMinor) })),
      { key: 'Posted by', value: this.postedBy ?? '' },
    ];
  }

  /** Post a landed-cost allocation. Sent in one batch with StockLot.addCost on each lot. */
  @operation static post = {
    base: 'transform',
    transformations: bxl`
      assert(if .status == null then true else .status == "draft" end; "Only a draft landed cost can be posted. This one is already posted.");
      assert((.allocations | length) > 0; "Landed cost goes to at least one lot.");
      assert([.allocations[].amountMinor] | all(. > 0); "Every allocation must be positive.");
      assert([.allocations[].amountMinor] + [0 - .amountMinor] | add | . == 0; "The allocations must add up to the amount.");
      assert(.clearingAccount != null; "Say which clearing account the cost comes out of.");
      assert(.date > realmConfig().closedThrough; "That date is on or before the closing date, so the landed cost can't post.");
      assert(if realmConfig().chart == null then true else (([.clearingAccount, .allocations[].asset] - [null, ""]) - realmConfig().chart | length == 0) end; "An account on this landed cost isn't in the chart of accounts. Add it to the chart, then post.");
      .status = "posted";
      .postedBy = actor();
    `,
  } satisfies OperationDeclaration;
  /** Post it into a journal month: every check `post` makes, recorded as journaled. The desk sends
   *  the lot operations it implies in the same batch. */
  @operation static journal = journalOperation(this.post);
}

// ── inventory on hand, from the lots ────────────────────────────────────────
export class StockRow extends FieldDef {
  @field sku = contains(StringField);
  @field lots = contains(NumberField);
  @field qtyMilli = contains(NumberField);
  @field costMinor = contains(NumberField);
}

export class StockOnHandReport extends CardDef {
  static displayName = 'Inventory on hand';
  static icon = BookIcon;
  static prefersWideFormat = true;
  @field lots = linksToMany(() => StockLot, {
    query: { page: { size: 1000 } },
  });
  @field rows = containsMany(StockRow, {
    computeVia: function (this: StockOnHandReport) {
      let by = new Map<
        string,
        { sku: string; lots: number; qtyMilli: number; costMinor: number }
      >();
      for (let l of (this.lots ?? []).filter(Boolean)) {
        if ((l.remainingQty ?? 0) <= 0) continue;
        let r = by.get(l.sku ?? '') ?? {
          sku: l.sku ?? '',
          lots: 0,
          qtyMilli: 0,
          costMinor: 0,
        };
        r.lots++;
        r.qtyMilli += l.remainingQty ?? 0;
        r.costMinor += l.remainingCostMinor ?? 0;
        by.set(r.sku, r);
      }
      return [...by.values()]
        .sort((a, b) => a.sku.localeCompare(b.sku))
        .map((r) => new StockRow(r));
    },
  });
  @field totalCostMinor = contains(NumberField, {
    computeVia: function (this: StockOnHandReport) {
      return (this.rows ?? []).reduce((n, r) => n + (r?.costMinor ?? 0), 0);
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function () {
      return 'Inventory on hand';
    },
  });

  static isolated = class extends Component<typeof StockOnHandReport> {
    get note() {
      return (
        partialNote(this.args.model, 'lots', 'lots') ||
        'What is left of each lot at its own remaining cost (FIFO), after roasting, sales and counts.'
      );
    }
    cols: Col[] = [
      { key: 'sku', label: 'Product', kind: 'code' },
      { key: 'lots', label: 'Lots', kind: 'number', priority: 'secondary' },
      { key: 'qty', label: 'On hand', kind: 'quantity', scale: 3 },
      {
        key: 'unit',
        label: 'Average cost',
        kind: 'amount',
        priority: 'secondary',
      },
      { key: 'value', label: 'Value', kind: 'amount' },
    ];
    get rows(): Line[] {
      let m = this.args.model;
      return [
        ...(m.rows ?? []).filter(Boolean).map((r) => ({
          key: r!.sku ?? '',
          cells: {
            sku: r!.sku,
            lots: r!.lots,
            qty: r!.qtyMilli,
            unit: r!.qtyMilli
              ? Math.round(((r!.costMinor ?? 0) * 1000) / r!.qtyMilli)
              : undefined,
            value: r!.costMinor,
          },
          data: {
            row: true,
            key: r!.sku,
            total: r!.costMinor ?? 0,
            qty: r!.qtyMilli ?? 0,
          },
        })),
        {
          key: 'total',
          role: 'total' as const,
          cells: { sku: 'Total', value: m.totalCostMinor },
        },
      ];
    }
    <template>
      <Sheet
        @eyebrow='Inventory valuation'
        @title='Inventory on hand'
        @figureMinor={{@model.totalCostMinor}}
        @figureLabel='At cost'
        @note={{this.note}}
      >
        <Part @title='By product'><StatementTable
            @label='Inventory by product'
            @columns={{this.cols}}
            @rows={{this.rows}}
          /></Part>
      </Sheet>
    </template>
  };
  static embedded = class extends Component<typeof StockOnHandReport> {
    <template>
      <Strip
        @eyebrow='Inventory'
        @title='Inventory on hand'
        @figure={{money @model.totalCostMinor}}
        @meta='At cost, by lot'
      />
    </template>
  };
  static fitted = class extends Component<typeof StockOnHandReport> {
    <template>
      <Fit
        @eyebrow='Inventory'
        @title='On hand'
        @figure={{money @model.totalCostMinor}}
        @meta='At cost'
      />
    </template>
  };
}
