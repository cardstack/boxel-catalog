// Customizing a report beyond its settings: which columns show, filters by account, class, location,
// customer, vendor or project, grouping with subtotals, and sort. The lines come from the same
// postings reader every statement uses (ledger-report-settings), so a custom report ties to them.
// Any report on the desk saves as a SavedReport and exports to CSV exactly as its table shows.
import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { modifier } from 'ember-modifier';
import { identifyCard } from '@cardstack/runtime-common';
import { getFields } from '@cardstack/base/card-api';
import type { CardContext, CardDef } from '@cardstack/base/card-api';
import { operations } from '@cardstack/base/operations';
import { Button } from '@cardstack/pretui/components/button';
import { Select } from '@cardstack/pretui/components/select';
import { MultiSelect } from '@cardstack/pretui/components/multi-select';
import { Dialog } from '@cardstack/pretui/components/dialog';
import { Input } from '@cardstack/pretui/components/input';
import { Field } from '@cardstack/pretui/components/field';
import { Chip } from '@cardstack/pretui/components/chip';
import { Callout } from '@cardstack/pretui/components/callout';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { Skeleton } from '@cardstack/pretui/components/skeleton';
import {
  StatementTable,
  type StatementColumn as Col,
  type StatementRow as Line,
} from './components/statement-table';
import {
  accrualEntries,
  cashEntries,
  ReportView,
  type ReportEntry,
} from './ledger-report-settings';
import { CUSTOMER_KINDS, VENDOR_KINDS } from './ledger-report-library';
import { AllCards } from './all-cards';
import { JournalMonth, KIND_LABEL } from './ledger-journal';
import { LedgerAccount, Bill } from './ledger-cards';
import { Invoice } from './ledger-sales';
import { OpeningBalances } from './ledger-opening';
import {
  DIMENSIONS,
  NO_CUSTOMIZATION,
  customizationOf,
  type Customization,
  type SavedLike,
  type SavedSettings,
} from './ledger-saved-report';

// ── the lines ───────────────────────────────────────────────────────────────
/** One posting line as a custom report reads it. Amounts are cents: net is debits less credits. */
export interface DetailLine {
  date: string;
  kind: string;
  doc: string;
  entry: string;
  party: string;
  customer: string;
  vendor: string;
  account: string;
  accountName: string;
  section: string;
  cls: string;
  loc: string;
  project: string;
  net: number;
}

export const DETAIL_COLUMNS: Col[] = [
  { key: 'date', label: 'Date', width: '7rem' },
  { key: 'kind', label: 'Type', priority: 'secondary' },
  { key: 'doc', label: 'No.', kind: 'code' },
  { key: 'party', label: 'Name' },
  { key: 'account', label: 'Account', kind: 'code' },
  { key: 'accountName', label: 'Account name', priority: 'secondary' },
  { key: 'cls', label: 'Class', priority: 'secondary' },
  { key: 'loc', label: 'Location', priority: 'secondary' },
  { key: 'project', label: 'Project', priority: 'secondary' },
  { key: 'debit', label: 'Debit', kind: 'amount' },
  { key: 'credit', label: 'Credit', kind: 'amount' },
  { key: 'amount', label: 'Amount', kind: 'amount' },
];
const COLUMN_BY_KEY = new Map(DETAIL_COLUMNS.map((c) => [c.key, c]));
const AMOUNT_KEYS = new Set(['debit', 'credit', 'amount']);

export interface AccountName {
  name: string;
  section: string;
}

/** The posting lines, each with its account's name and the customer or vendor it belongs to. */
export function detailLines(
  entries: ReportEntry[],
  accounts: Map<string, AccountName>,
): DetailLine[] {
  return entries.map((e) => ({
    date: e.date,
    kind: KIND_LABEL[e.kind] ?? e.kind,
    doc: e.doc,
    entry: e.entry,
    party: e.party,
    customer: CUSTOMER_KINDS.has(e.kind) ? e.party : '',
    vendor: VENDOR_KINDS.has(e.kind) ? e.party : '',
    account: e.account,
    accountName: accounts.get(e.account)?.name ?? '',
    section: accounts.get(e.account)?.section ?? '',
    cls: e.cls,
    loc: e.loc,
    project: e.project,
    net: e.net,
  }));
}

/** A line's value in a dimension. */
export const dimensionOf = (l: DetailLine, dimension: string): string =>
  dimension === 'account'
    ? l.account
    : String((l as unknown as Record<string, unknown>)[dimension] ?? '');

/** The values a dimension takes across some lines, for a filter's choices. */
export function dimensionValues(lines: DetailLine[], dimension: string) {
  return [...new Set(lines.map((l) => dimensionOf(l, dimension)))]
    .filter(Boolean)
    .sort();
}

const cellsOf = (l: DetailLine): Record<string, unknown> => ({
  date: l.date,
  kind: l.kind,
  doc: l.doc,
  party: l.party,
  account: l.account,
  accountName: l.accountName,
  cls: l.cls,
  loc: l.loc,
  project: l.project,
  debit: l.net > 0 ? l.net : undefined,
  credit: l.net < 0 ? -l.net : undefined,
  amount: l.net,
});

export interface CustomTable {
  cols: Col[];
  rows: Line[];
  count: number;
  totals: { debit: number; credit: number; amount: number };
  // Each group's totals, by its key, when the report is grouped.
  groups: Map<string, { debit: number; credit: number; amount: number }>;
}

const sums = (lines: DetailLine[]) => ({
  debit: lines.reduce((n, l) => n + (l.net > 0 ? l.net : 0), 0),
  credit: lines.reduce((n, l) => n + (l.net < 0 ? -l.net : 0), 0),
  amount: lines.reduce((n, l) => n + l.net, 0),
});

/**
 * The report table for some lines within a period: the columns chosen, the lines the filters keep,
 * sorted, and grouped with a subtotal after each group and a total at the end.
 */
export function customTable(
  all: DetailLine[],
  custom: Customization,
  opts: { from?: string; to?: string; columns?: string[] } = {},
): CustomTable {
  let keys = custom.columns.length
    ? custom.columns
    : (opts.columns ?? DETAIL_COLUMNS.map((c) => c.key));
  let cols = keys.map((k) => COLUMN_BY_KEY.get(k)).filter(Boolean) as Col[];
  let from = opts.from ?? '',
    to = opts.to ?? '';
  let lines = all.filter((l) => {
    let m = l.date.slice(0, 7);
    if (from && m < from) return false;
    if (to && m > to) return false;
    return custom.filters.every((f) => dimensionOf(l, f.dimension) === f.value);
  });
  let dir = custom.sortDir === 'desc' ? -1 : 1;
  let byKey = (k: string) => (a: DetailLine, b: DetailLine) => {
    let x = cellsOf(a)[k],
      y = cellsOf(b)[k];
    if (typeof x === 'number' || typeof y === 'number')
      return ((Number(x) || 0) - (Number(y) || 0)) * dir;
    return String(x ?? '').localeCompare(String(y ?? '')) * dir;
  };
  let natural = (a: DetailLine, b: DetailLine) =>
    (a.date.localeCompare(b.date) || a.doc.localeCompare(b.doc)) * dir;
  let order = custom.sortBy
    ? (a: DetailLine, b: DetailLine) =>
        byKey(custom.sortBy)(a, b) || natural(a, b)
    : natural;
  lines = [...lines].sort(order);
  let first = cols[0]?.key ?? '';
  // A subtotal's or total's label goes in the first column that holds text.
  let textKey = cols.find((c) => !AMOUNT_KEYS.has(c.key))?.key;
  let labelCell = (text: string) => (textKey ? { [textKey]: text } : {});
  let amountCells = (s: { debit: number; credit: number; amount: number }) =>
    Object.fromEntries(
      cols
        .filter((c) => AMOUNT_KEYS.has(c.key))
        .map((c) => [c.key, s[c.key as 'debit' | 'credit' | 'amount']]),
    );
  let lineRow = (l: DetailLine, i: number, depth: number): Line => ({
    key: `l-${i}`,
    depth,
    cells: cellsOf(l),
    data: { reportLine: true },
  });
  let rows: Line[] = [],
    groups = new Map<
      string,
      { debit: number; credit: number; amount: number }
    >();
  if (custom.groupBy) {
    let by = new Map<string, DetailLine[]>();
    for (let l of lines) {
      let k = dimensionOf(l, custom.groupBy),
        group = by.get(k);
      if (group) group.push(l);
      else by.set(k, [l]);
    }
    let label = (k: string) => {
      if (!k) return '(none)';
      if (custom.groupBy === 'entry') {
        let doc = by.get(k)![0].doc;
        return doc && doc !== k ? `${doc} · ${k}` : k;
      }
      if (custom.groupBy !== 'account') return k;
      let name = lines.find((l) => l.account === k)?.accountName;
      return name ? `${k} ${name}` : k;
    };
    let n = 0;
    // A journal reads entry by entry in date order; any other grouping in key order.
    let keys =
      custom.groupBy === 'entry'
        ? [...by.keys()].sort(
            (a, b) =>
              by.get(a)![0].date.localeCompare(by.get(b)![0].date) ||
              a.localeCompare(b),
          )
        : [...by.keys()].sort();
    for (let k of keys) {
      let group = by.get(k)!,
        s = sums(group);
      groups.set(k, s);
      rows.push({
        key: `h-${k}`,
        role: 'heading',
        cells: { [first]: label(k) },
      });
      for (let l of group) rows.push(lineRow(l, n++, 1));
      rows.push({
        key: `s-${k}`,
        role: 'subtotal',
        cells: { ...labelCell(`Total for ${label(k)}`), ...amountCells(s) },
        data: { reportSubtotal: k || '(none)' },
      });
    }
  } else lines.forEach((l, i) => rows.push(lineRow(l, i, 0)));
  let totals = sums(lines);
  rows.push({
    key: 'total',
    role: 'total',
    cells: { ...labelCell('Total'), ...amountCells(totals) },
    data: { reportTotal: true },
  });
  return { cols, rows, count: lines.length, totals, groups };
}

// ── CSV ─────────────────────────────────────────────────────────────────────
/** Comma-separated values, quoted where a value needs it, one line per row. */
export function csvText(rows: string[][]): string {
  let quote = (v: string) =>
    /[",\r\n]/.test(v) ? `"${v.replace(/"/g, '""')}"` : v;
  return rows.map((r) => r.map(quote).join(',')).join('\r\n') + '\r\n';
}
// A spreadsheet runs a cell that starts with one of these as a formula. Amounts aren't touched.
const FORMULA_START = /^[=+\-@\t\r]/;
/** Text a spreadsheet opens as text, not as a formula. */
export const formulaSafe = (text: string) =>
  FORMULA_START.test(text) ? `'${text}` : text;
/** A table's cells as it shows them: each header and row, a heading's title in its first column. */
export function tableCells(table: HTMLTableElement): string[][] {
  let out: string[][] = [];
  for (let tr of Array.from(table.rows)) {
    let row: string[] = [];
    for (let cell of Array.from(tr.cells)) {
      let copy = cell.cloneNode(true) as HTMLElement;
      // The spoken form of a negative amount sits beside the one shown.
      copy.querySelectorAll('[data-statement-sr]').forEach((n) => n.remove());
      let text = (copy.textContent ?? '').replace(/\s+/g, ' ').trim();
      row.push(cell.dataset.numeric ? text : formulaSafe(text));
      for (let i = 1; i < cell.colSpan; i++) row.push('');
    }
    out.push(row);
  }
  return out;
}
/** Every table inside an element, as CSV, one after another with a blank line between. */
export function elementCsv(el: Element): string {
  return Array.from(el.querySelectorAll('table'))
    .map((t) => csvText(tableCells(t as HTMLTableElement)))
    .join('\r\n');
}
export function downloadCsv(filename: string, text: string) {
  let url = URL.createObjectURL(new Blob([text], { type: 'text/csv' }));
  let a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}
export const csvName = (label: string) =>
  `${
    label
      .replace(/[^\w-]+/g, '-')
      .replace(/^-|-$/g, '')
      .toLowerCase() || 'report'
  }.csv`;

// ── saving ──────────────────────────────────────────────────────────────────
export interface SaveRequest {
  name: string;
  kind: string;
  kindLabel: string;
  settings: SavedSettings;
  custom: Customization;
  visibility: 'shared' | 'private';
}
/** The parameters `Ledger.saveReport` takes. */
export const saveParams = (r: SaveRequest) => ({
  name: r.name,
  kind: r.kind,
  kindLabel: r.kindLabel,
  ...r.settings,
  columnKeys: r.custom.columns.join(','),
  filters: r.custom.filters.map((f) => ({
    dimension: f.dimension,
    value: f.value,
  })),
  groupBy: r.custom.groupBy,
  sortBy: r.custom.sortBy,
  sortDir: r.custom.sortDir,
  visibility: r.visibility,
});

// The fields a desk statement is set up by. A computed one (an aging report's month) is left out.
const STATEMENT_FIELDS = [
  'fromMonth',
  'toMonth',
  'asOf',
  'asOfMonth',
  'throughMonth',
  'year',
  'account',
];
// getFields leaves computed fields out unless asked for them.
const settable = (card: any, k: string) =>
  !!card && k in getFields(card.constructor as typeof CardDef);

/** The settings a desk statement card carries, read so a save can store them. */
export function settingsOfCard(card: any): SavedSettings {
  let v = card?.view,
    own = Object.fromEntries(
      STATEMENT_FIELDS.filter((k) => settable(card, k)).map((k) => [
        k,
        card[k] ?? null,
      ]),
    );
  return {
    fromMonth: card?.fromMonth ?? '',
    toMonth: card?.toMonth ?? '',
    asOfMonth: card?.asOfMonth ?? card?.throughMonth ?? '',
    basis: v?.basis ?? '',
    columns: v?.columns ?? '',
    compare: v?.compare ?? '',
    account: card?.account ?? '',
    statement: JSON.stringify(own),
  };
}
/**
 * A new, unsaved statement of the same kind as a desk statement card, set up as a saved report
 * stored it. The shared card is left as it is.
 */
export function statementCopy(card: any, s: SavedSettings) {
  let data: Record<string, unknown> = {};
  for (let k of STATEMENT_FIELDS) if (settable(card, k)) data[k] = card[k];
  // A save from before statements stored their own fields carries only the common ones.
  let saved: Record<string, unknown> = {
    ...(s.fromMonth ? { fromMonth: s.fromMonth } : {}),
    ...(s.toMonth ? { toMonth: s.toMonth } : {}),
    ...(s.asOfMonth
      ? { asOfMonth: s.asOfMonth, throughMonth: s.asOfMonth }
      : {}),
    ...(s.account ? { account: s.account } : {}),
  };
  try {
    if (s.statement) saved = JSON.parse(s.statement);
  } catch {
    // an unreadable statement keeps the common fields
  }
  for (let [k, v] of Object.entries(saved))
    if (STATEMENT_FIELDS.includes(k) && settable(card, k)) data[k] = v;
  // Its view as saved, the defaults included, so a later change to the shared card doesn't leak in.
  if ('view' in card)
    data.view = new ReportView({
      basis: s.basis || 'accrual',
      columns: s.columns || 'total',
      compare: s.compare || 'none',
    });
  return new (card.constructor as new (d: Record<string, unknown>) => CardDef)(
    data,
  );
}

const VISIBILITY = [
  { value: 'shared', label: "Shared with the books' users" },
  { value: 'private', label: 'Not listed for others' },
];
const errorText = (e: any) => e?.detail ?? e?.message ?? String(e);
/** A failure's next step first, then what the realm said. */
export const failureText = (e: any) =>
  `Check your connection and try again. If it keeps failing, ask an Admin about your role. (${errorText(e)})`;
// Puts focus on an element once it renders, for a view the reader just opened.
export const focusOnInsert = modifier((el: HTMLElement) => {
  el.focus();
});

interface SaveSignature {
  Args: {
    context?: CardContext;
    ledger?: CardDef;
    kind: string;
    kindLabel: string;
    settings: () => SavedSettings;
    custom?: Customization;
    onSaved?: (name: string) => void;
  };
}
/** "Save as" for a report: a name and who may see it, saved through the ledger so the realm stamps the saver. */
export class SaveReportAs extends GlimmerComponent<SaveSignature> {
  @tracked open = false;
  @tracked name = '';
  @tracked visibility: 'shared' | 'private' = 'shared';
  @tracked busy = false;
  @tracked error = '';
  @tracked nameError = '';
  // The realm's answer for this viewer; only a refusal hides the control.
  get refused() {
    let l = this.args.ledger;
    return !!l && this.args.context?.canInvoke?.('saveReport', l) === false;
  }
  show = () => {
    this.name = `${this.args.kindLabel}`;
    this.error = '';
    this.nameError = '';
    this.open = true;
  };
  close = () => (this.open = false);
  setName = (v: string) => {
    this.name = v;
    if (v.trim()) this.nameError = '';
  };
  setVisibility = (v: string) =>
    (this.visibility = v === 'private' ? 'private' : 'shared');
  save = async () => {
    let ledger = this.args.ledger;
    this.nameError = this.name.trim() ? '' : 'Enter a name';
    if (this.nameError) return;
    if (!ledger) {
      this.error =
        "These books have no ledger card to save the report through. Ask an Admin to link the desk's ledger.";
      return;
    }
    this.busy = true;
    this.error = '';
    try {
      await (operations(ledger) as any).saveReport(
        saveParams({
          name: this.name.trim(),
          kind: this.args.kind,
          kindLabel: this.args.kindLabel,
          settings: this.args.settings(),
          custom: this.args.custom ?? NO_CUSTOMIZATION,
          visibility: this.visibility,
        }),
      );
      this.open = false;
      this.args.onSaved?.(this.name.trim());
    } catch (e) {
      this.error = failureText(e);
    } finally {
      this.busy = false;
    }
  };
  <template>
    {{#if this.refused}}
      <span class='muted' data-save-refused>Your role can't save reports.</span>
    {{else}}
      <Button
        @tone='neutral'
        @appearance='outlined'
        @size='s'
        {{on 'click' this.show}}
      >Save as…</Button>
    {{/if}}
    <Dialog @open={{this.open}} @onClose={{this.close}} @size='s'>
      <:title>Save report</:title>
      <:default>
        <div class='save-form'>
          <Field @label='Name' @error={{this.nameError}}>
            <:default as |id|><Input
                @controlId={{id}}
                @value={{this.name}}
                @invalid={{if this.nameError true false}}
                @onInput={{this.setName}}
              /></:default>
          </Field>
          <Field
            @label='Listed for'
            @hint='Not listed for others leaves it out of their lists; anyone who can read the books can still open it.'
          >
            <:default as |id hint|><Select
                @controlId={{id}}
                @options={{VISIBILITY}}
                @value={{this.visibility}}
                @onValueChange={{this.setVisibility}}
                aria-describedby={{hint}}
              /></:default>
          </Field>
          {{#if this.error}}<Callout
              @tone='danger'
              @title="It wasn't saved"
            >{{this.error}}</Callout>{{/if}}
        </div>
      </:default>
      <:footer>
        <Button @appearance='plain' {{on 'click' this.close}}>Cancel</Button>
        <Button
          @tone='primary'
          @appearance='accent'
          @busy={{this.busy}}
          {{on 'click' this.save}}
        >Save</Button>
      </:footer>
    </Dialog>
    <style scoped>
      .save-form {
        display: grid;
        gap: var(--boxel-sp-sm);
      }
      .muted {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
    </style>
  </template>
}

// Marks the element a report's actions export from: the nearest report body around it.
export const reportBody = modifier(
  (el: HTMLElement, [setter]: [(el: HTMLElement | undefined) => void]) => {
    setter(el.closest('[data-report-body]') as HTMLElement | undefined);
    return () => setter(undefined);
  },
);

interface ActionsSignature {
  Args: {
    context?: CardContext;
    ledger?: CardDef;
    kind: string;
    kindLabel: string;
    card?: unknown; // the statement card whose settings a save stores
  };
}
/** Save as and Export CSV above a desk statement: the CSV is the tables in the report as shown. */
export class ReportActions extends GlimmerComponent<ActionsSignature> {
  @tracked saved = '';
  @tracked hasRows = false;
  body: HTMLElement | undefined;
  observer: MutationObserver | undefined;
  // Export waits for the statement's table: the body is watched until it holds rows.
  setBody = (el: HTMLElement | undefined) => {
    this.observer?.disconnect();
    this.body = el;
    let check = () => (this.hasRows = !!el?.querySelector('table tbody tr'));
    if (el) {
      this.observer = new MutationObserver(check);
      this.observer.observe(el, { childList: true, subtree: true });
      check();
    }
  };
  willDestroy() {
    super.willDestroy();
    this.observer?.disconnect();
  }
  settings = () => settingsOfCard(this.args.card);
  exportCsv = () => {
    if (this.body)
      downloadCsv(csvName(this.args.kindLabel), elementCsv(this.body));
  };
  onSaved = (name: string) => (this.saved = name);
  <template>
    <div class='report-actions' data-report-actions {{reportBody this.setBody}}>
      <span class='muted' role='status'>{{#if this.saved}}Saved as “{{this.saved}}”
          in My reports.{{/if}}</span>
      <SaveReportAs
        @context={{@context}}
        @ledger={{@ledger}}
        @kind={{@kind}}
        @kindLabel={{@kindLabel}}
        @settings={{this.settings}}
        @onSaved={{this.onSaved}}
      />
      {{#if this.hasRows}}<Button
          @tone='neutral'
          @appearance='outlined'
          @size='s'
          {{on 'click' this.exportCsv}}
        >Export CSV</Button>{{/if}}
    </div>
    <style scoped>
      .report-actions {
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp-xs);
        justify-content: flex-end;
        align-items: center;
        margin-bottom: var(--boxel-sp-sm);
      }
      .muted {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
    </style>
  </template>
}

// ── the custom report on the desk ───────────────────────────────────────────
export const instancesOf = (r: unknown): any[] =>
  (((r as any)?.instances ?? []) as any[]).filter(Boolean);
export const loadingOf = (r: unknown) => (r as any)?.isLoading !== false;
const MONTH = /^\d{4}-(0[1-9]|1[0-2])$/;
/** Whether a value is a whole month, yyyy-mm. */
export const isMonth = (ym: string | undefined) => MONTH.test(ym ?? '');
const monthEnd = (ym: string) => {
  let [y, m] = ym.split('-').map(Number);
  return new Date(Date.UTC(y, m, 0)).toISOString().slice(0, 10);
};
export const thisMonth = () => new Date().toISOString().slice(0, 7);
const GROUPS = [
  { value: '', label: 'No grouping' },
  ...DIMENSIONS,
  { value: 'party', label: 'Name' },
  { value: 'entry', label: 'Entry' },
];
const SORT_DIRS = [
  { value: 'asc', label: 'Ascending' },
  { value: 'desc', label: 'Descending' },
];
const BASES = [
  { value: 'accrual', label: 'Accrual' },
  { value: 'cash', label: 'Cash' },
];

/** A report preset: the report a library entry opens, as a customization of the posting lines. */
export interface DetailPreset {
  kind: string;
  label: string;
  note: string;
  columns: string[];
  groupBy?: string;
  sections?: string[]; // only accounts in these chart sections
  accounts?: string[]; // only these accounts
  through?: boolean; // a balance: every line up to the period's end, not just those in it
}
export const PRESETS: Record<string, DetailPreset> = {
  custom: {
    kind: 'custom',
    label: 'Custom report',
    note: 'Every posting line in the period. Choose its columns, filter it, group it with subtotals and sort it.',
    columns: [
      'date',
      'kind',
      'doc',
      'party',
      'account',
      'cls',
      'debit',
      'credit',
    ],
  },
  'transaction-detail': {
    kind: 'transaction-detail',
    label: 'Transaction detail by account',
    note: 'Every posting line in the period, account by account, with a subtotal for each.',
    columns: [
      'date',
      'kind',
      'doc',
      'party',
      'cls',
      'debit',
      'credit',
      'amount',
    ],
    groupBy: 'account',
  },
  journal: {
    kind: 'journal',
    label: 'Journal',
    note: 'Every entry in the period in date order, each with its lines.',
    columns: [
      'date',
      'kind',
      'party',
      'account',
      'accountName',
      'debit',
      'credit',
    ],
    groupBy: 'entry',
  },
  'pnl-detail': {
    kind: 'pnl-detail',
    label: 'Profit and loss detail',
    note: 'The postings behind the profit and loss: income, cost of goods and expense lines by account.',
    columns: ['date', 'kind', 'doc', 'party', 'cls', 'amount'],
    groupBy: 'account',
    sections: ['income', 'cogs', 'expense'],
  },
  'bs-detail': {
    kind: 'bs-detail',
    label: 'Balance sheet detail',
    note: 'The postings behind the balance sheet: asset, liability and equity lines by account, up to the period end.',
    columns: ['date', 'kind', 'doc', 'party', 'amount'],
    groupBy: 'account',
    sections: ['asset', 'liability', 'equity'],
    through: true,
  },
  'customer-balance-detail': {
    kind: 'customer-balance-detail',
    label: 'Customer balance detail',
    note: 'What each customer owes: every posting to receivables (1100) up to the period end, by customer.',
    columns: ['date', 'kind', 'doc', 'amount'],
    groupBy: 'party',
    accounts: ['1100'],
    through: true,
  },
  'vendor-balance-detail': {
    kind: 'vendor-balance-detail',
    label: 'Vendor balance detail',
    note: 'What is owed to each vendor: every posting to payables (2000) up to the period end, by vendor. A credit is owed.',
    columns: ['date', 'kind', 'doc', 'amount'],
    groupBy: 'party',
    accounts: ['2000'],
    through: true,
  },
};

/** The lines a preset reads: its chart sections or accounts. */
export const presetLines = (lines: DetailLine[], p: DetailPreset) =>
  lines.filter(
    (l) =>
      (!p.sections || p.sections.includes(l.section)) &&
      (!p.accounts || p.accounts.includes(l.account)),
  );
/** A preset's report over a period: a balance reads every line up to the period's end. */
export const presetTable = (
  lines: DetailLine[],
  p: DetailPreset,
  custom: Customization,
  from: string,
  to: string,
) =>
  customTable(presetLines(lines, p), custom, {
    from: p.through ? '' : from,
    to,
    columns: p.columns,
  });
/** A preset's own customization, as the report first opens. */
export const presetCustomization = (p: DetailPreset): Customization => ({
  ...NO_CUSTOMIZATION,
  columns: [...p.columns],
  groupBy: p.groupBy ?? '',
});

interface RunnerSignature {
  Args: {
    context?: CardContext;
    realms: string[];
    refRealms?: string[];
    ledger?: CardDef;
    kind?: string | null;
    saved?: SavedLike; // opens with its settings and customization
  };
}
export class CustomReportRunner extends GlimmerComponent<RunnerSignature> {
  get preset(): DetailPreset {
    return PRESETS[this.args.kind ?? ''] ?? PRESETS.custom;
  }
  @tracked fromMonth =
    this.args.saved?.fromMonth || `${thisMonth().slice(0, 4)}-01`;
  @tracked toMonth = this.args.saved?.toMonth || thisMonth();
  @tracked basis = this.args.saved?.basis === 'cash' ? 'cash' : 'accrual';
  @tracked custom: Customization = this.args.saved
    ? customizationOf(this.args.saved)
    : {
        ...NO_CUSTOMIZATION,
        columns: [...this.preset.columns],
        groupBy: this.preset.groupBy ?? '',
      };
  @tracked filterDimension = 'account';
  @tracked filterValue = '';
  @tracked savedName = '';

  get readFrom() {
    return this.basis === 'cash' || this.preset.through
      ? '0000-01'
      : this.fromMonth;
  }
  // A balance reads every line up to its To month, so it has no From.
  get periodError() {
    if (this.preset.through)
      return isMonth(this.toMonth) ? '' : 'Enter the month to report through.';
    if (!isMonth(this.fromMonth) || !isMonth(this.toMonth))
      return 'Enter a From and a To month.';
    if (this.fromMonth > this.toMonth)
      return 'The From month must come before the To month.';
    return '';
  }
  journalData = new AllCards(
    this.args.context,
    this,
    () =>
      (this.periodError
        ? undefined
        : {
            filter: {
              every: [
                { type: identifyCard(JournalMonth) },
                {
                  on: identifyCard(JournalMonth),
                  range: { month: { gte: this.readFrom, lte: this.toMonth } },
                },
              ],
            },
          }) as never,
    () => this.args.realms,
    { isLive: true },
  );
  docQuery = (type: typeof CardDef) => () =>
    (this.periodError
      ? undefined
      : {
          filter: {
            every: [
              { type: identifyCard(type) },
              { on: identifyCard(type), eq: { status: 'posted' } },
              {
                on: identifyCard(type),
                range: {
                  date: {
                    gte: `${this.readFrom}-01`,
                    lte: monthEnd(this.toMonth),
                  },
                },
              },
            ],
          },
          sort: [{ by: 'date', on: identifyCard(type), direction: 'desc' }],
        }) as never;
  invoiceData = new AllCards(
    this.args.context,
    this,
    this.docQuery(Invoice),
    () => this.args.realms,
    { isLive: true },
  );
  billData = new AllCards(
    this.args.context,
    this,
    this.docQuery(Bill),
    () => this.args.realms,
    { isLive: true },
  );
  openingData = this.args.context?.getCards(
    this,
    () =>
      ({
        filter: {
          every: [
            { type: identifyCard(OpeningBalances) },
            { on: identifyCard(OpeningBalances), eq: { status: 'posted' } },
          ],
        },
        page: { size: 10 },
      }) as never,
    () => this.args.realms,
    { isLive: true },
  );
  accountData = new AllCards(
    this.args.context,
    this,
    () => ({ filter: { type: identifyCard(LedgerAccount) } }) as never,
    () => this.args.refRealms ?? this.args.realms,
    { isLive: true },
  );
  // A source that couldn't be read whole would leave postings out, so the report shows no totals.
  get capNote() {
    if (this.periodError || this.loading) return '';
    let failed = (
      [
        [this.journalData, 'journal months'],
        [this.invoiceData, 'invoices'],
        [this.billData, 'bills'],
        [this.accountData, 'accounts'],
      ] as [AllCards, string][]
    ).filter(([r]) => !r.isComplete);
    let opening = (this.openingData as any)?.errors?.length
      ? ['opening balances']
      : [];
    let nouns = [...failed.map(([, noun]) => noun), ...opening];
    return nouns.length
      ? `This report couldn't read all of its ${nouns.join(', ')}, so it shows no lines or totals. ${failed.some(([r]) => r.tooMany) ? 'Narrow the period.' : 'Reload to try again.'}`
      : '';
  }
  get loading() {
    return (
      !this.periodError &&
      [
        this.journalData,
        this.invoiceData,
        this.billData,
        this.openingData,
        this.accountData,
      ].some(loadingOf)
    );
  }
  get canExport() {
    return (
      !this.loading &&
      !this.periodError &&
      !this.capNote &&
      this.table.count > 0
    );
  }
  get accounts() {
    return new Map(
      instancesOf(this.accountData).map((a) => [
        a.code ?? '',
        { name: a.name ?? '', section: a.section ?? '' },
      ]),
    );
  }
  get lines(): DetailLine[] {
    let src = {
      journal: instancesOf(this.journalData),
      invoices: instancesOf(this.invoiceData),
      bills: instancesOf(this.billData),
      openings: instancesOf(this.openingData),
    };
    let entries =
      this.basis === 'cash' ? cashEntries(src) : accrualEntries(src);
    return presetLines(detailLines(entries, this.accounts), this.preset);
  }
  get table() {
    if (this.periodError) return customTable([], this.custom, {});
    return presetTable(
      this.lines,
      this.preset,
      this.custom,
      this.fromMonth,
      this.toMonth,
    );
  }
  get columnOptions() {
    return DETAIL_COLUMNS.map((c) => ({ value: c.key, label: c.label }));
  }
  get sortOptions() {
    return [
      { value: '', label: 'Date' },
      ...DETAIL_COLUMNS.filter((c) => c.key !== 'date').map((c) => ({
        value: c.key,
        label: c.label,
      })),
    ];
  }
  dimensionOptions = DIMENSIONS.map((d) => ({
    value: d.value,
    label: d.label,
  }));
  groupOptions = GROUPS.map((d) => ({ value: d.value, label: d.label }));
  sortDirs = SORT_DIRS;
  bases = BASES;
  get valueOptions() {
    return dimensionValues(this.lines, this.filterDimension).map((v) => ({
      value: v,
      label:
        this.filterDimension === 'account'
          ? `${v} ${this.accounts.get(v)?.name ?? ''}`.trim()
          : v,
    }));
  }
  change = (patch: Partial<Customization>) =>
    (this.custom = { ...this.custom, ...patch });
  setColumns = (columns: string[]) => this.change({ columns });
  setGroup = (groupBy: string) => this.change({ groupBy });
  setSort = (sortBy: string) => this.change({ sortBy });
  setSortDir = (d: string) =>
    this.change({ sortDir: d === 'desc' ? 'desc' : 'asc' });
  setFrom = (v: string) => (this.fromMonth = v);
  setTo = (v: string) => (this.toMonth = v);
  setBasis = (v: string) => (this.basis = v === 'cash' ? 'cash' : 'accrual');
  setFilterDimension = (v: string) => {
    this.filterDimension = v;
    this.filterValue = '';
  };
  setFilterValue = (v: string) => {
    this.filterValue = v;
    this.filterError = '';
  };
  @tracked filterError = '';
  addFilter = () => {
    this.filterError = this.filterValue ? '' : 'Choose a value to filter by';
    if (this.filterError) return;
    this.change({
      filters: [
        ...this.custom.filters.filter(
          (f) => f.dimension !== this.filterDimension,
        ),
        { dimension: this.filterDimension, value: this.filterValue },
      ],
    });
    this.filterValue = '';
  };
  removeFilter = (dimension: string) =>
    this.change({
      filters: this.custom.filters.filter((f) => f.dimension !== dimension),
    });
  filterLabel = (f: { dimension: string; value: string }) =>
    `${DIMENSIONS.find((d) => d.value === f.dimension)?.label ?? f.dimension}: ${f.value}`;
  settings = (): SavedSettings => ({
    fromMonth: this.fromMonth,
    toMonth: this.toMonth,
    asOfMonth: '',
    basis: this.basis,
    columns: '',
    compare: '',
    account: '',
    statement: '',
  });
  onSaved = (name: string) => (this.savedName = name);
  body: HTMLElement | undefined;
  setBody = (el: HTMLElement | undefined) => (this.body = el);
  exportCsv = () => {
    if (this.body) downloadCsv(csvName(this.title), elementCsv(this.body));
  };
  get title() {
    return this.args.saved?.name || this.preset.label;
  }
  <template>
    <section
      class='runner'
      data-report-body
      data-custom-report
      aria-busy={{if this.loading 'true'}}
    >
      <header class='runner-head'>
        <div>
          {{#if @saved}}<h2
              tabindex='-1'
              {{focusOnInsert}}
            >{{this.title}}</h2>{{/if}}
          <p class='muted'>{{this.preset.note}}</p>
        </div>
        <div class='runner-actions' {{reportBody this.setBody}}>
          <span class='muted' role='status'>{{#if this.loading}}Loading report…{{else if
              this.savedName
            }}Saved as “{{this.savedName}}” in My reports.{{/if}}</span>
          <SaveReportAs
            @context={{@context}}
            @ledger={{@ledger}}
            @kind={{this.preset.kind}}
            @kindLabel={{this.preset.label}}
            @settings={{this.settings}}
            @custom={{this.custom}}
            @onSaved={{this.onSaved}}
          />
          {{#if this.canExport}}<Button
              @tone='neutral'
              @appearance='outlined'
              @size='s'
              {{on 'click' this.exportCsv}}
            >Export CSV</Button>{{/if}}
        </div>
      </header>
      <div class='controls'>
        {{#unless this.preset.through}}
          <Field @label='From'>
            <:default as |id|><Input
                @controlId={{id}}
                @type='month'
                @value={{this.fromMonth}}
                @onInput={{this.setFrom}}
              /></:default>
          </Field>
        {{/unless}}
        <Field
          @label={{if this.preset.through 'Through' 'To'}}
          @error={{this.periodError}}
        >
          <:default as |id|><Input
              @controlId={{id}}
              @type='month'
              @value={{this.toMonth}}
              @onInput={{this.setTo}}
            /></:default>
        </Field>
        <Field @label='Basis'>
          <:default as |id|><Select
              @controlId={{id}}
              @options={{this.bases}}
              @value={{this.basis}}
              @onValueChange={{this.setBasis}}
            /></:default>
        </Field>
        <Field @label='Group and subtotal by'>
          <:default as |id|><Select
              @controlId={{id}}
              @options={{this.groupOptions}}
              @value={{this.custom.groupBy}}
              @onValueChange={{this.setGroup}}
            /></:default>
        </Field>
        <Field @label='Sort by'>
          <:default as |id|><Select
              @controlId={{id}}
              @options={{this.sortOptions}}
              @value={{this.custom.sortBy}}
              @onValueChange={{this.setSort}}
            /></:default>
        </Field>
        <Field @label='Order'>
          <:default as |id|><Select
              @controlId={{id}}
              @options={{this.sortDirs}}
              @value={{this.custom.sortDir}}
              @onValueChange={{this.setSortDir}}
            /></:default>
        </Field>
      </div>
      <div class='controls'>
        <div class='wide'>
          <MultiSelect
            @label='Columns'
            @placeholder='Columns'
            @options={{this.columnOptions}}
            @value={{this.custom.columns}}
            @onValueChange={{this.setColumns}}
          />
        </div>
        <Field @label='Filter by'>
          <:default as |id|><Select
              @controlId={{id}}
              @options={{this.dimensionOptions}}
              @value={{this.filterDimension}}
              @onValueChange={{this.setFilterDimension}}
            /></:default>
        </Field>
        <Field @label='Is' @error={{this.filterError}}>
          <:default as |id|><Select
              @controlId={{id}}
              @options={{this.valueOptions}}
              @value={{this.filterValue}}
              @placeholder='Choose…'
              @onValueChange={{this.setFilterValue}}
            /></:default>
        </Field>
        <Button
          @tone='neutral'
          @appearance='outlined'
          {{on 'click' this.addFilter}}
        >Add filter</Button>
      </div>
      {{#if this.custom.filters.length}}
        <div class='filters'>
          {{#each this.custom.filters as |f|}}
            <span class='filter'><Chip @label={{this.filterLabel f}} /><Button
                @appearance='plain'
                @size='xs'
                aria-label='Remove the filter {{this.filterLabel f}}'
                {{on 'click' (fn this.removeFilter f.dimension)}}
              >Remove</Button></span>
          {{/each}}
        </div>
      {{/if}}
      {{#if this.capNote}}<Callout
          @tone='danger'
          @title='Incomplete'
          data-report-capped
        >{{this.capNote}}</Callout>{{/if}}
      {{#if this.periodError}}
        <EmptyState @size='s' @title='Set the period' />
      {{else if this.loading}}
        <div class='skeletons'><Skeleton @height='2rem' /><Skeleton
            @height='2rem'
          /><Skeleton @height='2rem' /></div>
      {{else if this.capNote}}{{else if this.table.count}}
        <StatementTable
          @label={{this.title}}
          @columns={{this.table.cols}}
          @rows={{this.table.rows}}
          @density='compact'
        />
      {{else}}
        <EmptyState
          @size='s'
          @title='No postings match'
          @message='Nothing posted in this period passes the filters. Widen the period or remove a filter.'
        />
      {{/if}}
    </section>
    <style scoped>
      .runner {
        display: grid;
        gap: var(--boxel-sp-sm);
        min-width: 0;
      }
      .runner-head {
        display: flex;
        flex-wrap: wrap;
        justify-content: space-between;
        gap: var(--boxel-sp-sm);
      }
      .runner-actions {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: var(--boxel-sp-xs);
      }
      .controls {
        display: flex;
        flex-wrap: wrap;
        align-items: end;
        gap: var(--boxel-sp-sm);
      }
      .controls > * {
        min-width: 9rem;
      }
      .wide {
        flex: 1 1 18rem;
      }
      .filters {
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp-xs);
      }
      .filter {
        display: inline-flex;
        align-items: center;
        gap: var(--boxel-sp-5xs);
      }
      .skeletons {
        display: grid;
        gap: var(--boxel-sp-xs);
      }
      .muted {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
    </style>
  </template>
}
