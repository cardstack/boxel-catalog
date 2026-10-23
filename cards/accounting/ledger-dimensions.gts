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
import { Bill, LedgerAccount, Vendor, plSection } from './ledger-cards';
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
import {
  StatementTable,
  type StatementColumn as Col,
  type StatementRow as Line,
} from './components/statement-table';
import { IsoDateField, IsoMonthField } from './ledger-dates';
import { Warehouse } from '@cardstack/catalog/cards/fulfilment/warehouse';
import { Project } from '@cardstack/catalog/cards/projects/project';
import { TimeActivity } from './ledger-time';

const monthEnd = (ym: string) => {
  let [y, m] = ym.split('-').map(Number);
  return new Date(Date.UTC(y, m, 0)).toISOString().slice(0, 10);
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
/** A job the books track income and costs by, for one customer. Beside its class, a line can name it. */
export class BooksProject extends CardDef {
  static displayName = 'Project';
  static icon = BookIcon;
  @field projectId = contains(StringField);
  @field name = contains(StringField);
  @field customerId = contains(StringField);
  @field status = contains(StringField); // active, completed or canceled
  @field project = linksTo(() => Project); // the projects cluster's card for the work itself, if any
  @field cardTitle = contains(StringField, {
    computeVia: function (this: BooksProject) {
      return this.name ?? this.projectId ?? 'Project';
    },
  });
  static isolated = class extends Component<typeof BooksProject> {
    get meta() {
      let m = this.args.model;
      return [m.customerId, m.status].filter(Boolean).join(' · ');
    }
    <template>
      <Sheet
        @eyebrow='Project'
        @title={{@model.cardTitle}}
        @meta={{this.meta}}
      />
    </template>
  };
  static embedded = class extends Component<typeof BooksProject> {
    <template>
      <Strip
        @eyebrow='Project'
        @title={{@model.cardTitle}}
        @meta={{@model.customerId}}
      />
    </template>
  };
  static fitted = class extends Component<typeof BooksProject> {
    <template>
      <Fit
        @eyebrow='Project'
        @title={{@model.cardTitle}}
        @meta={{@model.status}}
      />
    </template>
  };
}
export class BooksLocation extends CardDef {
  static displayName = 'Location';
  static icon = BookIcon;
  @field name = contains(StringField);
  @field warehouse = linksTo(() => Warehouse); // the fulfilment cluster's warehouse at this location
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

interface ProfitSource {
  fromDate?: string;
  toDate?: string;
  accounts?: (LedgerAccount | undefined)[];
  journal?: (JournalMonth | undefined)[];
  bills?: unknown[];
  openings?: unknown[];
  invoices?: unknown[];
}
/**
 * Income, cost of goods and expenses in a period, grouped by a line tag (`cls` or `project`): every
 * posted line on an income, cost or expense account, from the documents still posted as cards and the
 * journal months' lines in the period. A line without the tag groups as "(none)".
 */
function profitBy(source: ProfitSource, key: 'cls' | 'project') {
  let types = new Map(
    (source.accounts ?? [])
      .filter(Boolean)
      .map((a) => [a!.code ?? '', plSection(a!.type)]),
  );
  let by = new Map<
    string,
    {
      key: string;
      incomeMinor: number;
      cogsMinor: number;
      expenseMinor: number;
    }
  >();
  let from = source.fromDate ?? '',
    to = source.toDate ?? '9999-12-31';
  let journalLines = (source.journal ?? [])
    .filter(Boolean)
    .flatMap((m) =>
      (m!.ledgerLines ?? []).filter(
        (l) => !!l && (l.date ?? '') >= from && (l.date ?? '') <= to,
      ),
    );
  let docLines = KINDS.flatMap((kind) =>
    ((source[kind] ?? []) as (Lined | undefined)[])
      .filter(Boolean)
      .flatMap((d) => d!.ledgerLines ?? []),
  );
  for (let l of [...docLines, ...journalLines]) {
    let section = types.get(l?.account ?? '');
    if (!section) continue;
    let k = (l as any)?.[key] || '(none)',
      r = by.get(k) ?? {
        key: k,
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
  return [...by.values()].sort((a, b) => a.key.localeCompare(b.key));
}

export class ProfitByClass extends CardDef {
  static displayName = 'Profit and loss by class';
  static icon = BookIcon;
  static prefersWideFormat = true;
  @field fromMonth = contains(IsoMonthField);
  @field toMonth = contains(IsoMonthField);
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
      return profitBy(this, 'cls').map(
        (r) =>
          new ClassRow({
            cls: r.key,
            incomeMinor: r.incomeMinor,
            cogsMinor: r.cogsMinor,
            expenseMinor: r.expenseMinor,
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
    cols: Col[] = [
      { key: 'cls', label: 'Class' },
      { key: 'income', label: 'Income', kind: 'amount' },
      { key: 'cogs', label: 'Cost of goods', kind: 'amount' },
      { key: 'expense', label: 'Expenses', kind: 'amount' },
      { key: 'net', label: 'Net', kind: 'amount' },
    ];
    get rows(): Line[] {
      let m = this.args.model;
      let lines: Line[] = (m.rows ?? []).filter(Boolean).map((r) => ({
        key: r!.cls ?? '',
        cells: {
          cls: r!.cls,
          income: r!.incomeMinor ?? 0,
          cogs: r!.cogsMinor ?? 0,
          expense: r!.expenseMinor ?? 0,
          net: r!.netMinor ?? 0,
        },
        data: {
          row: true,
          key: r!.cls,
          total: r!.netMinor ?? 0,
          dr: r!.incomeMinor ?? 0,
          cr: r!.expenseMinor ?? 0,
          qty: r!.cogsMinor ?? 0,
        },
      }));
      return lines.length
        ? [
            ...lines,
            {
              key: 'total',
              role: 'total',
              cells: { cls: 'Net income', net: m.netIncomeMinor ?? 0 },
            },
          ]
        : lines;
    }
    <template>
      <Sheet
        @eyebrow='Profit and loss by class'
        @title={{@model.cardTitle}}
        @figure={{money @model.netIncomeMinor}}
        @figureLabel='Net income'
        @note='Every posted line on an income, cost or expense account in the period, grouped by its class. Lines with no class show as (none).'
      >
        <Part @title='By class'><StatementTable
            @label='Profit and loss by class'
            @columns={{this.cols}}
            @rows={{this.rows}}
            @zero='show'
          /></Part>
      </Sheet>
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
export class ProjectRow extends FieldDef {
  @field project = contains(StringField);
  @field incomeMinor = contains(NumberField);
  @field costMinor = contains(NumberField); // cost of goods and expenses
  @field laborMinor = contains(NumberField); // time worked at its cost rate; posts nothing
  @field profitMinor = contains(NumberField);
}

export class ProfitByProject extends CardDef {
  static displayName = 'Profit by project';
  static icon = BookIcon;
  static prefersWideFormat = true;
  @field fromMonth = contains(IsoMonthField);
  @field toMonth = contains(IsoMonthField);
  @field fromDate = contains(StringField, {
    computeVia: function (this: ProfitByProject) {
      return this.fromMonth ? `${this.fromMonth}-01` : '';
    },
  });
  @field toDate = contains(StringField, {
    computeVia: function (this: ProfitByProject) {
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
  @field time = linksToMany(() => TimeActivity, {
    query: {
      filter: {
        range: { date: { gte: '$this.fromDate', lte: '$this.toDate' } },
      },
      page: { size: 2000 },
    },
  });
  @field rows = containsMany(ProjectRow, {
    computeVia: function (this: ProfitByProject) {
      let labor = new Map<string, number>();
      for (let t of (this.time ?? []).filter(Boolean))
        if (t!.projectId)
          labor.set(
            t!.projectId,
            (labor.get(t!.projectId) ?? 0) +
              Math.round(((t!.costRateMinor ?? 0) * (t!.hours ?? 0)) / 1000),
          );
      let rows = new Map(
        profitBy(this, 'project')
          .filter((r) => r.key !== '(none)')
          .map((r) => [r.key, r]),
      );
      for (let p of labor.keys())
        if (!rows.has(p))
          rows.set(p, {
            key: p,
            incomeMinor: 0,
            cogsMinor: 0,
            expenseMinor: 0,
          });
      return [...rows.values()]
        .sort((a, b) => a.key.localeCompare(b.key))
        .map((r) => {
          let cost = r.cogsMinor + r.expenseMinor,
            laborMinor = labor.get(r.key) ?? 0;
          return new ProjectRow({
            project: r.key,
            incomeMinor: r.incomeMinor,
            costMinor: cost,
            laborMinor,
            profitMinor: r.incomeMinor - cost - laborMinor,
          });
        });
    },
  });
  @field profitMinor = contains(NumberField, {
    computeVia: function (this: ProfitByProject) {
      return (this.rows ?? []).reduce((n, r) => n + (r?.profitMinor ?? 0), 0);
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: ProfitByProject) {
      return `Profit by project · ${this.fromMonth ?? ''} to ${this.toMonth ?? ''}`;
    },
  });
  static isolated = class extends Component<typeof ProfitByProject> {
    cols: Col[] = [
      { key: 'project', label: 'Project' },
      { key: 'income', label: 'Income', kind: 'amount' },
      { key: 'cost', label: 'Costs', kind: 'amount' },
      { key: 'labor', label: 'Labor (time)', kind: 'amount' },
      { key: 'profit', label: 'Profit', kind: 'amount' },
    ];
    get rows(): Line[] {
      let m = this.args.model;
      let lines: Line[] = (m.rows ?? []).filter(Boolean).map((r) => ({
        key: r!.project ?? '',
        cells: {
          project: r!.project,
          income: r!.incomeMinor ?? 0,
          cost: r!.costMinor ?? 0,
          labor: r!.laborMinor ?? 0,
          profit: r!.profitMinor ?? 0,
        },
      }));
      return lines.length
        ? [
            ...lines,
            {
              key: 'total',
              role: 'total',
              cells: { project: 'All projects', profit: m.profitMinor ?? 0 },
            },
          ]
        : lines;
    }
    <template>
      <Sheet
        @eyebrow='Profit by project'
        @title={{@model.cardTitle}}
        @figure={{money @model.profitMinor}}
        @figureLabel='Profit'
        @note='Every posted line on an income, cost or expense account in the period that names a project, and the time worked on each project at its cost rate. Labor from time posts nothing; it counts here only.'
      >
        <Part @title='By project'><StatementTable
            @label='Profit by project'
            @columns={{this.cols}}
            @rows={{this.rows}}
            @zero='show'
          /></Part>
      </Sheet>
    </template>
  };
  static embedded = class extends Component<typeof ProfitByProject> {
    <template>
      <Strip
        @eyebrow='Profit by project'
        @title={{@model.cardTitle}}
        @figure={{money @model.profitMinor}}
      />
    </template>
  };
  static fitted = class extends Component<typeof ProfitByProject> {
    <template>
      <Fit
        @eyebrow='Profit by project'
        @title={{@model.toMonth}}
        @figure={{money @model.profitMinor}}
      />
    </template>
  };
}

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
  @field date = contains(IsoDateField);
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
