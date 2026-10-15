// Reporting dimensions, purchasing and people as cards: classes and locations, a profit and loss by
// class computed from the posted documents' lines, purchase orders with what's been received against
// them computed from the bills they link, and the books' users and roles.
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
import BookIcon from '@cardstack/boxel-icons/book-open';
import { Bill, LedgerAccount, Vendor } from './ledger-cards';
import { OpeningBalances } from './ledger-opening';
import { Invoice } from './ledger-sales';
import { JournalMonth } from './ledger-journal';
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

const monthEnd = (ym: string) => {
  let [y, m] = ym.split('-').map(Number);
  return new Date(Date.UTC(y, m, 0)).toISOString().slice(0, 10);
};
const SECTION: Record<string, string> = {
  income: 'income',
  cogs: 'cogs',
  expense: 'expense',
  other: 'expense',
};
const qtyText = (milli: number | undefined) =>
  ((milli ?? 0) / 1000).toLocaleString('en-US', { maximumFractionDigits: 3 });

// ── classes and locations ───────────────────────────────────────────────────
export class BooksClass extends CardDef {
  static displayName = 'Class';
  static icon = BookIcon;
  @field name = contains(StringField);
  @field parent = contains(StringField);
  @field cardTitle = contains(StringField, {
    computeVia: function (this: BooksClass) {
      return this.name ?? 'Class';
    },
  });
  static isolated = class extends Component<typeof BooksClass> {
    <template>
      <Sheet @eyebrow='Class' @title={{@model.name}} @meta={{@model.parent}} />
    </template>
  };
  static embedded = class extends Component<typeof BooksClass> {
    <template><Strip @eyebrow='Class' @title={{@model.name}} /></template>
  };
  static fitted = class extends Component<typeof BooksClass> {
    <template><Fit @eyebrow='Class' @title={{@model.name}} /></template>
  };
}
export class BooksLocation extends CardDef {
  static displayName = 'Location';
  static icon = BookIcon;
  @field name = contains(StringField);
  @field cardTitle = contains(StringField, {
    computeVia: function (this: BooksLocation) {
      return this.name ?? 'Location';
    },
  });
  static isolated = class extends Component<typeof BooksLocation> {
    <template><Sheet @eyebrow='Location' @title={{@model.name}} /></template>
  };
  static embedded = class extends Component<typeof BooksLocation> {
    <template><Strip @eyebrow='Location' @title={{@model.name}} /></template>
  };
  static fitted = class extends Component<typeof BooksLocation> {
    <template><Fit @eyebrow='Location' @title={{@model.name}} /></template>
  };
}

// ── profit and loss by class ────────────────────────────────────────────────
export class ClassRow extends FieldDef {
  @field cls = contains(StringField);
  @field incomeMinor = contains(NumberField);
  @field cogsMinor = contains(NumberField);
  @field expenseMinor = contains(NumberField);
  @field netMinor = contains(NumberField);
}
const inPeriod = {
  filter: {
    every: [
      { eq: { status: 'posted' } },
      { range: { date: { gte: '$this.fromDate', lte: '$this.toDate' } } },
    ],
  },
  page: { size: 1000 },
};
// Since the books moved to the append-log journal, invoices, bills and the opening balances are the only
// documents still posted as cards; every other kind is a row on a JournalMonth (its old card is marked
// "journaled", so a status-posted query no longer finds it).
const KINDS = ['bills', 'openings', 'invoices'] as const;
type Lined = {
  ledgerLines?: (
    | {
        account?: string;
        debitMinor?: number;
        creditMinor?: number;
        cls?: string;
      }
    | undefined
  )[];
};

export class ProfitByClass extends CardDef {
  static displayName = 'Profit and loss by class';
  static icon = BookIcon;
  static prefersWideFormat = true;
  @field fromMonth = contains(StringField);
  @field toMonth = contains(StringField);
  @field fromDate = contains(StringField, {
    computeVia: function (this: ProfitByClass) {
      return this.fromMonth ? `${this.fromMonth}-01` : '';
    },
  });
  @field toDate = contains(StringField, {
    computeVia: function (this: ProfitByClass) {
      return this.toMonth ? monthEnd(this.toMonth) : '';
    },
  });
  @field accounts = linksToMany(() => LedgerAccount, {
    query: { page: { size: 500 } },
  });
  @field bills = linksToMany(() => Bill, { query: inPeriod });
  @field openings = linksToMany(() => OpeningBalances, { query: inPeriod });
  @field invoices = linksToMany(() => Invoice, { query: inPeriod });
  @field journal = linksToMany(() => JournalMonth, {
    query: {
      filter: {
        range: { month: { gte: '$this.fromMonth', lte: '$this.toMonth' } },
      },
      page: { size: 60 },
    },
  });
  @field rows = containsMany(ClassRow, {
    computeVia: function (this: ProfitByClass) {
      let types = new Map(
        (this.accounts ?? [])
          .filter(Boolean)
          .map((a) => [a!.code ?? '', SECTION[a!.type ?? ''] ?? '']),
      );
      let by = new Map<
        string,
        {
          cls: string;
          incomeMinor: number;
          cogsMinor: number;
          expenseMinor: number;
        }
      >();
      let from = this.fromDate ?? '',
        to = this.toDate ?? '9999-12-31';
      let journalLines = (this.journal ?? [])
        .filter(Boolean)
        .flatMap((m) =>
          (m!.ledgerLines ?? []).filter(
            (l) => !!l && (l.date ?? '') >= from && (l.date ?? '') <= to,
          ),
        );
      let docLines = KINDS.flatMap((kind) =>
        ((this[kind] ?? []) as (Lined | undefined)[])
          .filter(Boolean)
          .flatMap((d) => d!.ledgerLines ?? []),
      );
      for (let l of [...docLines, ...journalLines]) {
        let section = types.get(l?.account ?? '');
        if (!section) continue;
        let k = l!.cls || '(none)',
          r = by.get(k) ?? {
            cls: k,
            incomeMinor: 0,
            cogsMinor: 0,
            expenseMinor: 0,
          };
        let v = (l!.debitMinor ?? 0) - (l!.creditMinor ?? 0);
        if (section === 'income') r.incomeMinor -= v;
        else if (section === 'cogs') r.cogsMinor += v;
        else r.expenseMinor += v;
        by.set(k, r);
      }
      return [...by.values()]
        .sort((a, b) => a.cls.localeCompare(b.cls))
        .map(
          (r) =>
            new ClassRow({
              ...r,
              netMinor: r.incomeMinor - r.cogsMinor - r.expenseMinor,
            }),
        );
    },
  });
  @field netIncomeMinor = contains(NumberField, {
    computeVia: function (this: ProfitByClass) {
      return (this.rows ?? []).reduce((n, r) => n + (r?.netMinor ?? 0), 0);
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: ProfitByClass) {
      return `Profit and loss by class · ${this.fromMonth ?? ''} to ${this.toMonth ?? ''}`;
    },
  });
  static isolated = class extends Component<typeof ProfitByClass> {
    get rows() {
      return (this.args.model.rows ?? []).filter(Boolean).map((r) => ({
        k: r!.cls,
        i: money(r!.incomeMinor),
        c: money(r!.cogsMinor),
        e: money(r!.expenseMinor),
        n: money(r!.netMinor),
        m: r!.netMinor ?? 0,
        im: r!.incomeMinor ?? 0,
        cm: r!.cogsMinor ?? 0,
        em: r!.expenseMinor ?? 0,
      }));
    }
    <template>
      <Sheet
        @eyebrow='Profit and loss by class'
        @title={{@model.cardTitle}}
        @figure={{money @model.netIncomeMinor}}
        @figureLabel='Net income'
        @note='Every posted line on an income, cost or expense account in the period, grouped by its class. Lines with no class show as (none).'
      >
        <Part @title='By class'><div class='scroll'><table class='rpt'><thead
              ><tr><th>Class</th><th class='n'>Income</th><th class='n'>Cost of
                    goods</th><th class='n'>Expenses</th><th
                    class='n'
                  >Net</th></tr></thead>
              <tbody>{{#each this.rows as |r|}}<tr
                    data-row
                    data-key={{r.k}}
                    data-total={{r.m}}
                    data-dr={{r.im}}
                    data-cr={{r.em}}
                    data-qty={{r.cm}}
                  ><td>{{r.k}}</td><td class='n'>{{r.i}}</td><td
                      class='n'
                    >{{r.c}}</td><td class='n'>{{r.e}}</td><td class='n'><b
                      >{{r.n}}</b></td></tr>{{/each}}</tbody></table></div></Part>
      </Sheet>
      <style scoped>
        .scroll {
          overflow-x: auto;
        }
        .rpt {
          width: 100%;
          border-collapse: collapse;
          font-size: 0.8125rem;
        }
        th {
          text-align: left;
          font-weight: 500;
          color: var(--muted-foreground);
          padding: 0.35rem 0.5rem;
          border-bottom: 1px solid var(--border);
        }
        td {
          padding: 0.35rem 0.5rem;
          border-bottom: 1px solid var(--border);
        }
        .n {
          text-align: right;
          font-family: var(--font-mono);
          white-space: nowrap;
        }
      </style>
    </template>
  };
  static embedded = class extends Component<typeof ProfitByClass> {
    <template>
      <Strip
        @eyebrow='P&L by class'
        @title={{@model.cardTitle}}
        @figure={{money @model.netIncomeMinor}}
        @meta='Net income'
      />
    </template>
  };
  static fitted = class extends Component<typeof ProfitByClass> {
    <template>
      <Fit
        @eyebrow='P&L by class'
        @title={{@model.toMonth}}
        @figure={{money @model.netIncomeMinor}}
        @meta='Net income'
      />
    </template>
  };
}

// ── purchase orders ─────────────────────────────────────────────────────────
export class PoLine extends FieldDef {
  static displayName = 'PO line';
  @field sku = contains(StringField);
  @field qty = contains(NumberField); // thousandths of a unit
  @field rateMinor = contains(NumberField); // cents per unit
}
export class PoLineStatus extends FieldDef {
  @field sku = contains(StringField);
  @field orderedQty = contains(NumberField);
  @field receivedQty = contains(NumberField);
}
export class PurchaseOrder extends CardDef {
  static displayName = 'Purchase order';
  static icon = BookIcon;
  @field poNo = contains(StringField);
  @field vendorId = contains(StringField);
  @field vendor = linksTo(() => Vendor);
  @field date = contains(StringField);
  @field cls = contains(StringField);
  @field loc = contains(StringField);
  @field lines = containsMany(PoLine);
  @field bills = linksToMany(() => Bill); // the bills received against this order
  @field lineStatus = containsMany(PoLineStatus, {
    computeVia: function (this: PurchaseOrder) {
      let got = new Map<string, number>();
      for (let b of (this.bills ?? []).filter(Boolean))
        for (let l of b!.lines ?? [])
          if (l?.sku) got.set(l.sku, (got.get(l.sku) ?? 0) + (l.qty ?? 0));
      return (this.lines ?? []).filter(Boolean).map(
        (l) =>
          new PoLineStatus({
            sku: l!.sku,
            orderedQty: l!.qty ?? 0,
            receivedQty: Math.min(l!.qty ?? 0, got.get(l!.sku ?? '') ?? 0),
          }),
      );
    },
  });
  @field orderedMinor = contains(NumberField, {
    computeVia: function (this: PurchaseOrder) {
      return (this.lines ?? []).reduce(
        (n, l) => n + Math.round(((l?.rateMinor ?? 0) * (l?.qty ?? 0)) / 1000),
        0,
      );
    },
  });
  @field status = contains(StringField, {
    computeVia: function (this: PurchaseOrder) {
      let s = this.lineStatus ?? [];
      return s.every((l) => (l?.receivedQty ?? 0) >= (l?.orderedQty ?? 0))
        ? 'Closed'
        : s.some((l) => (l?.receivedQty ?? 0) > 0)
          ? 'Partially received'
          : 'Open';
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: PurchaseOrder) {
      return `PO ${this.poNo ?? ''}${this.vendorId ? ' · ' + this.vendorId : ''}`;
    },
  });
  static isolated = class extends Component<typeof PurchaseOrder> {
    get facts(): Fact[] {
      let m = this.args.model;
      return [
        { key: 'PO', value: m.poNo ?? '', mono: true },
        { key: 'Vendor', value: m.vendorId ?? '' },
        { key: 'Ordered', value: day(m.date) },
        ...(m.lineStatus ?? []).filter(Boolean).map((l) => ({
          key: l!.sku ?? '',
          value: `${qtyText(l!.receivedQty)} of ${qtyText(l!.orderedQty)} received`,
        })),
        { key: 'Bills', value: String((m.bills ?? []).filter(Boolean).length) },
      ];
    }
    <template>
      <Sheet
        @eyebrow='Purchase order'
        @title={{@model.cardTitle}}
        @figure={{money @model.orderedMinor}}
        @figureLabel='Ordered'
        @status={{@model.status}}
      ><Part @title='Order'><div
            data-row
            data-key={{@model.poNo}}
            data-total={{@model.orderedMinor}}
          ><Facts @items={{this.facts}} /></div></Part></Sheet>
    </template>
  };
  static embedded = class extends Component<typeof PurchaseOrder> {
    <template>
      <Strip
        @eyebrow='Purchase order'
        @title={{@model.cardTitle}}
        @figure={{money @model.orderedMinor}}
        @meta={{@model.status}}
      />
    </template>
  };
  static fitted = class extends Component<typeof PurchaseOrder> {
    <template>
      <Fit
        @eyebrow='PO'
        @title={{@model.poNo}}
        @figure={{money @model.orderedMinor}}
        @meta={{@model.status}}
      />
    </template>
  };
}
