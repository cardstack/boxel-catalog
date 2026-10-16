// The account register (general ledger detail): every posted line on one account over a run of
// months, with a running balance that starts from the closed months before it. The lines come from
// the journal's month cards and from the documents that stay cards (bills, invoices, the opening
// balances), each a query on the indexed `ledgerLines.account`.
import {
  CardDef,
  FieldDef,
  Component,
  field,
  contains,
  containsMany,
  linksToMany,
} from '@cardstack/base/card-api';
import type { QueryWithInterpolations } from '@cardstack/runtime-common';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import BookIcon from '@cardstack/boxel-icons/book-open';
import { Bill, LedgerAccount } from './ledger-cards';
import { OpeningBalances } from './ledger-opening';
import { Invoice } from './ledger-sales';
import { JournalMonth, KIND_LABEL, seqText } from './ledger-journal';
import { MonthClose, netOf } from './ledger-close';
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

const monthEnd = (ym: string) => {
  let [y, m] = ym.split('-').map(Number);
  return new Date(Date.UTC(y, m, 0)).toISOString().slice(0, 10);
};
const on: QueryWithInterpolations = {
  filter: {
    every: [
      { eq: { status: 'posted' } },
      { eq: { 'ledgerLines.account': '$this.account' } },
      { range: { date: { gte: '$this.fromDate', lte: '$this.toDate' } } },
    ],
  },
  page: { size: 1000 },
};
const KINDS = ['bills', 'openings', 'invoices'] as const;
type Doc = {
  date?: string;
  memo?: string;
  cardTitle?: string;
  billNo?: string;
  docNo?: string;
  paymentNo?: string;
  ledgerLines?: (
    | {
        account?: string;
        debitMinor?: number;
        creditMinor?: number;
        party?: string;
        doc?: string;
      }
    | undefined
  )[];
};

export class RegisterLine extends FieldDef {
  @field date = contains(StringField);
  @field docNo = contains(StringField);
  @field title = contains(StringField);
  @field party = contains(StringField);
  @field debitMinor = contains(NumberField);
  @field creditMinor = contains(NumberField);
  @field balanceMinor = contains(NumberField); // running, debits less credits
}

export class AccountRegister extends CardDef {
  static displayName = 'Account register';
  static icon = BookIcon;
  static prefersWideFormat = true;
  @field account = contains(StringField);
  @field fromMonth = contains(StringField);
  @field toMonth = contains(StringField);
  @field fromDate = contains(StringField, {
    computeVia: function (this: AccountRegister) {
      return this.fromMonth ? `${this.fromMonth}-01` : '';
    },
  });
  @field toDate = contains(StringField, {
    computeVia: function (this: AccountRegister) {
      return this.toMonth ? monthEnd(this.toMonth) : '';
    },
  });
  @field accountCard = linksToMany(() => LedgerAccount, {
    query: { filter: { eq: { code: '$this.account' } }, page: { size: 1 } },
  });
  @field before = linksToMany(() => MonthClose, {
    query: {
      filter: { range: { month: { lt: '$this.fromMonth' } } },
      page: { size: 240 },
    },
  });
  @field bills = linksToMany(() => Bill, { query: on });
  @field openings = linksToMany(() => OpeningBalances, { query: on });
  @field invoices = linksToMany(() => Invoice, { query: on });
  @field journal = linksToMany(() => JournalMonth, {
    query: {
      filter: {
        every: [
          { eq: { 'ledgerLines.account': '$this.account' } },
          {
            range: { month: { gte: '$this.fromMonth', lte: '$this.toMonth' } },
          },
        ],
      },
      page: { size: 240 },
    },
  });
  @field openingBalanceMinor = contains(NumberField, {
    computeVia: function (this: AccountRegister) {
      return netOf(this.before).get(this.account ?? '') ?? 0;
    },
  });
  @field lines = containsMany(RegisterLine, {
    computeVia: function (this: AccountRegister) {
      let raw: {
        date: string;
        docNo: string;
        title: string;
        party: string;
        dr: number;
        cr: number;
      }[] = [];
      for (let kind of KINDS)
        for (let d of ((this[kind] ?? []) as (Doc | undefined)[]).filter(
          Boolean,
        ) as Doc[]) {
          for (let l of d.ledgerLines ?? [])
            if (l?.account === this.account)
              raw.push({
                date: d.date ?? '',
                docNo: d.docNo ?? d.billNo ?? d.paymentNo ?? '',
                title: d.cardTitle ?? '',
                party: l.party ?? '',
                dr: l.debitMinor ?? 0,
                cr: l.creditMinor ?? 0,
              });
        }
      for (let m of (this.journal ?? []).filter(Boolean))
        for (let p of (m!.postings ?? []).filter(Boolean)) {
          if (
            (p!.date ?? '') < (this.fromDate ?? '') ||
            (p!.date ?? '') > (this.toDate ?? '')
          )
            continue;
          for (let l of (p!.lines ?? []).filter(Boolean))
            if (l!.account === this.account)
              raw.push({
                date: p!.date ?? '',
                docNo: p!.source || seqText(m!.month, p!.seq),
                title: `${KIND_LABEL[p!.kind ?? ''] ?? p!.kind} · ${seqText(m!.month, p!.seq)}`,
                party: l!.party ?? p!.party ?? '',
                dr: l!.debitMinor ?? 0,
                cr: l!.creditMinor ?? 0,
              });
        }
      raw.sort(
        (a, b) =>
          a.date.localeCompare(b.date) || a.docNo.localeCompare(b.docNo),
      );
      let bal = this.openingBalanceMinor ?? 0;
      return raw.map((r) => {
        bal += r.dr - r.cr;
        return new RegisterLine({
          date: r.date,
          docNo: r.docNo,
          title: r.title,
          party: r.party,
          debitMinor: r.dr,
          creditMinor: r.cr,
          balanceMinor: bal,
        });
      });
    },
  });
  @field debitMinor = contains(NumberField, {
    computeVia: function (this: AccountRegister) {
      return (this.lines ?? []).reduce((n, l) => n + (l?.debitMinor ?? 0), 0);
    },
  });
  @field creditMinor = contains(NumberField, {
    computeVia: function (this: AccountRegister) {
      return (this.lines ?? []).reduce((n, l) => n + (l?.creditMinor ?? 0), 0);
    },
  });
  @field closingBalanceMinor = contains(NumberField, {
    computeVia: function (this: AccountRegister) {
      return (
        (this.openingBalanceMinor ?? 0) +
        (this.debitMinor ?? 0) -
        (this.creditMinor ?? 0)
      );
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: AccountRegister) {
      let name = (this.accountCard ?? []).filter(Boolean)[0]?.name;
      return `${this.account ?? ''}${name ? ' · ' + name : ''} · ${this.fromMonth ?? ''}${this.toMonth && this.toMonth !== this.fromMonth ? ' to ' + this.toMonth : ''}`;
    },
  });

  static isolated = class extends Component<typeof AccountRegister> {
    get facts(): Fact[] {
      let m = this.args.model;
      return [
        { key: 'Balance at the start', value: money(m.openingBalanceMinor) },
        { key: 'Debits', value: money(m.debitMinor) },
        { key: 'Credits', value: money(m.creditMinor) },
        {
          key: 'Balance at the end',
          value: money(m.closingBalanceMinor),
          strong: true,
        },
        { key: 'Lines', value: String((m.lines ?? []).length) },
      ];
    }
    cols: Col[] = [
      { key: 'date', label: 'Date', width: '7.5rem' },
      { key: 'doc', label: 'Document', kind: 'code' },
      { key: 'title', label: 'Entry', priority: 'secondary' },
      { key: 'party', label: 'Party', priority: 'secondary' },
      { key: 'dr', label: 'Debit', kind: 'amount' },
      { key: 'cr', label: 'Credit', kind: 'amount' },
      { key: 'bal', label: 'Balance', kind: 'amount' },
    ];
    get rows(): Line[] {
      let m = this.args.model;
      return [
        {
          key: 'open',
          role: 'subtotal' as const,
          cells: {
            date: '',
            doc: '',
            title: 'Balance at the start',
            party: '',
            bal: m.openingBalanceMinor ?? 0,
          },
        },
        ...(m.lines ?? []).filter(Boolean).map((l, i) => ({
          key: `${i}`,
          cells: {
            date: day(l!.date),
            doc: l!.docNo,
            title: l!.title,
            party: l!.party,
            dr: l!.debitMinor,
            cr: l!.creditMinor,
            bal: l!.balanceMinor,
          },
        })),
        {
          key: 'close',
          role: 'total' as const,
          cells: {
            date: '',
            doc: '',
            title: 'Balance at the end',
            party: '',
            dr: m.debitMinor,
            cr: m.creditMinor,
            bal: m.closingBalanceMinor,
          },
        },
      ];
    }
    <template>
      <Sheet
        @eyebrow='Account register'
        @title={{@model.cardTitle}}
        @figureMinor={{@model.closingBalanceMinor}}
        @figureLabel='Ending balance (debits less credits)'
        @note='Every posted line on this account, oldest first. The starting balance comes from the closed months before the period.'
      >
        <Part @title='Period'><div
            data-row
            data-key='summary'
            data-dr={{@model.debitMinor}}
            data-cr={{@model.creditMinor}}
            data-total={{@model.closingBalanceMinor}}
          ><Facts @items={{this.facts}} /></div></Part>
        <Part @title='Lines'><StatementTable
            @label='Lines on this account'
            @columns={{this.cols}}
            @rows={{this.rows}}
            @zero='show'
          /></Part>
      </Sheet>
    </template>
  };
  static embedded = class extends Component<typeof AccountRegister> {
    <template>
      <Strip
        @eyebrow='Account register'
        @title={{@model.cardTitle}}
        @figure={{money @model.closingBalanceMinor}}
        @meta='Ending balance'
      />
    </template>
  };
  static fitted = class extends Component<typeof AccountRegister> {
    <template>
      <Fit
        @eyebrow='Register'
        @title={{@model.account}}
        @figure={{money @model.closingBalanceMinor}}
        @meta={{@model.toMonth}}
      />
    </template>
  };
}
