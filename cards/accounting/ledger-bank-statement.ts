// Reading a bank statement file into bank lines, deciding which lines are new, and the rule that
// suggests how a line is categorized. Plain functions: the desk runs them in the browser before it
// sends the import as one batch.
import { parseCsvRecords } from '@cardstack/catalog/utils/csv';

/** One line as the bank reported it. Amounts are signed: money in is positive. */
export interface StatementLine {
  row: number;
  externalId: string;
  date: string; // yyyy-mm-dd
  description: string;
  amountMinor: number;
  reference: string;
  payee: string;
}
export interface RejectedRow {
  row: number;
  reason: string;
}

/** Which column holds each part of a line. Debit and credit stand in for a single signed amount. */
export interface ColumnMap {
  date?: number;
  description?: number;
  amount?: number;
  debit?: number;
  credit?: number;
  id?: number;
  reference?: number;
  payee?: number;
}
export const COLUMN_FIELDS: { key: keyof ColumnMap; label: string }[] = [
  { key: 'date', label: 'Date' },
  { key: 'description', label: 'Description' },
  { key: 'amount', label: 'Amount' },
  { key: 'debit', label: 'Money out' },
  { key: 'credit', label: 'Money in' },
  { key: 'id', label: 'Bank ID' },
  { key: 'reference', label: 'Reference' },
  { key: 'payee', label: 'Payee' },
];
const HEADER_NAMES: Record<keyof ColumnMap, string[]> = {
  date: ['date', 'posted date', 'transaction date', 'posting date'],
  description: ['description', 'memo', 'details', 'narrative'],
  amount: ['amount', 'amount (usd)', 'transaction amount'],
  debit: ['debit', 'withdrawal', 'withdrawals', 'money out', 'paid out'],
  credit: ['credit', 'deposit', 'deposits', 'money in', 'paid in'],
  id: ['transaction id', 'id', 'fitid', 'bank id', 'reference number'],
  reference: ['reference', 'check number', 'check no', 'ref', 'cheque number'],
  payee: ['payee', 'name', 'merchant', 'counterparty'],
};

/** The column map a header row suggests, matched by the usual names banks export: each part takes
 *  the column its likeliest name labels, and no column serves two parts. */
export function guessColumns(header: string[]): ColumnMap {
  let names = header.map((h) => h.trim().toLowerCase());
  let map: ColumnMap = {},
    used = new Set<number>();
  for (let [key, aliases] of Object.entries(HEADER_NAMES) as [
    keyof ColumnMap,
    string[],
  ][]) {
    for (let alias of aliases) {
      let i = names.findIndex((n, j) => n === alias && !used.has(j));
      if (i >= 0) {
        map[key] = i;
        used.add(i);
        break;
      }
    }
  }
  return map;
}

/** Whole cents from a bank's amount text: "1,234.50", "-12.00", "12.00-", "(12.00)", "$5", and a
 *  decimal comma ("86,42") where the comma is the last separator and one or two digits follow it. */
export function toMinor(text: string): number {
  let s = text.trim().replace(/[$\s]/g, '');
  let negative = /^\(.*\)$/.test(s) || s.startsWith('-') || s.endsWith('-');
  s = s.replace(/[()+-]/g, '');
  s = /^[\d.]*,\d{1,2}$/.test(s)
    ? s.replace(/\./g, '').replace(',', '.')
    : s.replace(/,/g, '');
  if (!/^\d+(\.\d{1,2})?$/.test(s))
    throw new Error(`"${text.trim()}" isn't an amount`);
  let [whole, frac = ''] = s.split('.');
  let minor = Number(whole) * 100 + Number(frac.padEnd(2, '0'));
  return negative ? -minor : minor;
}

/** A calendar day from yyyy-mm-dd, OFX's yyyymmdd[hhmmss…], or m/d/yyyy (d/m/yyyy when `dayFirst`). */
export function toDay(text: string, dayFirst = false): string {
  let s = text.trim();
  let m =
    /^(\d{4})-(\d{2})-(\d{2})$/.exec(s) ?? /^(\d{4})(\d{2})(\d{2})/.exec(s);
  let y: number, mo: number, d: number;
  if (m) [y, mo, d] = [Number(m[1]), Number(m[2]), Number(m[3])];
  else {
    let us = /^(\d{1,2})\/(\d{1,2})\/(\d{4})$/.exec(s);
    if (!us) throw new Error(`"${s}" isn't a date`);
    [y, mo, d] = dayFirst
      ? [Number(us[3]), Number(us[2]), Number(us[1])]
      : [Number(us[3]), Number(us[1]), Number(us[2])];
  }
  let date = new Date(Date.UTC(y, mo - 1, d));
  if (date.getUTCMonth() !== mo - 1 || date.getUTCDate() !== d)
    throw new Error(`"${s}" isn't a date`);
  return date.toISOString().slice(0, 10);
}

// A line with no bank ID gets one from what it says, numbered when the same date, amount and
// description repeat, so importing the same file again produces the same IDs.
function withIds(lines: Omit<StatementLine, 'externalId'>[], ids: string[]) {
  let seen = new Map<string, number>();
  return lines.map((l, i) => {
    if (ids[i]) return { ...l, externalId: ids[i] };
    let base = `${l.date}:${l.amountMinor}:${l.description.toLowerCase()}`;
    let n = (seen.get(base) ?? 0) + 1;
    seen.set(base, n);
    return {
      ...l,
      externalId: `${l.date}:${l.amountMinor}:${n}:${hash(base)}`,
    };
  });
}
function hash(text: string) {
  let h = 0;
  for (let i = 0; i < text.length; i++) h = (h * 31 + text.charCodeAt(i)) | 0;
  return (h >>> 0).toString(36);
}

export interface ParsedStatement {
  header: string[];
  lines: StatementLine[];
  rejected: RejectedRow[];
  card?: boolean; // an OFX credit card statement
}

/** How a file writes what a parser can't tell from the file itself. */
export interface ReadOptions {
  columns?: ColumnMap;
  dayFirst?: boolean; // dates are d/m/yyyy
  flipSigns?: boolean; // money out is positive, as some card issuers export it
}
const signed = (minor: number, o: ReadOptions) =>
  o.flipSigns ? -minor : minor;

// A first row with a date in it is a transaction, not a header.
function hasHeader(cells: string[]) {
  return !cells.some((c) => {
    try {
      toDay(c);
      return true;
    } catch {
      return false;
    }
  });
}

/** A CSV file's column names (numbered when it has no header row) and the column map they suggest. */
export function readCsvHeader(text: string): {
  header: string[];
  columns: ColumnMap;
} {
  let first = parseCsvRecords(text)[0]?.cells ?? [];
  return hasHeader(first)
    ? { header: first, columns: guessColumns(first) }
    : { header: first.map((_, i) => `Column ${i + 1}`), columns: {} };
}

/** The lines of a CSV statement under a column map. A row that can't be read is rejected, not guessed.
 *  A file whose first row is already a transaction has no header; its columns are named by number. */
export function parseCsvStatement(
  text: string,
  options: ReadOptions = {},
): ParsedStatement {
  let all = parseCsvRecords(text);
  let headed = !!all[0] && hasHeader(all[0].cells);
  let records = headed ? all.slice(1) : all;
  let header = headed
    ? all[0].cells
    : (all[0]?.cells ?? []).map((_, i) => `Column ${i + 1}`);
  let map = options.columns ?? (headed ? guessColumns(header) : {});
  let rejected: RejectedRow[] = [];
  let good: Omit<StatementLine, 'externalId'>[] = [],
    ids: string[] = [];
  let cell = (cells: string[], i: number | undefined) =>
    i == null ? '' : (cells[i] ?? '').trim();
  if (map.date == null)
    return {
      header,
      lines: [],
      rejected: [{ row: 1, reason: 'No date column' }],
    };
  if (map.amount == null && map.debit == null && map.credit == null)
    return {
      header,
      lines: [],
      rejected: [{ row: 1, reason: 'No amount column' }],
    };
  for (let r of records) {
    try {
      let c = r.cells;
      let amountMinor =
        map.amount != null
          ? signed(toMinor(cell(c, map.amount)), options)
          : (cell(c, map.credit) ? Math.abs(toMinor(cell(c, map.credit))) : 0) -
            (cell(c, map.debit) ? Math.abs(toMinor(cell(c, map.debit))) : 0);
      if (!amountMinor) throw new Error('The amount is zero');
      good.push({
        row: r.row,
        date: toDay(cell(c, map.date), options.dayFirst),
        description: cell(c, map.description) || cell(c, map.payee),
        amountMinor,
        reference: cell(c, map.reference),
        payee: cell(c, map.payee),
      });
      ids.push(cell(c, map.id));
    } catch (e: any) {
      rejected.push({ row: r.row, reason: e?.message ?? String(e) });
    }
  }
  return { header, lines: withIds(good, ids), rejected };
}

/** The transactions of an OFX or QFX statement: each <STMTTRN> block, SGML or XML. A file holding
 *  more than one account's statement is refused, since its lines would land in one account. */
export function parseOfxStatement(
  text: string,
  options: ReadOptions = {},
): ParsedStatement {
  let statements = (text.match(/<(CC)?STMTRS>/gi) ?? []).length;
  let card = /<CCSTMTRS>/i.test(text);
  if (statements > 1)
    return {
      header: [],
      lines: [],
      rejected: [
        {
          row: 1,
          reason: `This file holds ${statements} accounts' statements. Export one account at a time.`,
        },
      ],
      card,
    };
  let rejected: RejectedRow[] = [];
  let good: Omit<StatementLine, 'externalId'>[] = [],
    ids: string[] = [];
  let blocks = text.split(/<STMTTRN>/i).slice(1);
  let tag = (block: string, name: string) =>
    (new RegExp(`<${name}>([^<\\r\\n]*)`, 'i').exec(block)?.[1] ?? '').trim();
  blocks.forEach((raw, i) => {
    let block = raw.split(/<\/STMTTRN>/i)[0];
    try {
      let name = tag(block, 'NAME'),
        memo = tag(block, 'MEMO');
      good.push({
        row: i + 1,
        date: toDay(tag(block, 'DTPOSTED')),
        description: [name, memo].filter(Boolean).join(' · '),
        amountMinor: signed(toMinor(tag(block, 'TRNAMT')), options),
        reference: tag(block, 'CHECKNUM') || tag(block, 'REFNUM'),
        payee: name,
      });
      ids.push(tag(block, 'FITID'));
    } catch (e: any) {
      rejected.push({ row: i + 1, reason: e?.message ?? String(e) });
    }
  });
  if (!blocks.length)
    rejected.push({ row: 1, reason: 'No transactions found' });
  return { header: [], lines: withIds(good, ids), rejected, card };
}

/** What the bank already has on file for an account, by bank ID. */
export interface KnownLine {
  externalId: string;
  date: string;
  amountMinor: number;
  description: string;
}
export interface ImportPlan {
  accepted: StatementLine[];
  skipped: StatementLine[]; // already imported, unchanged
  rejected: RejectedRow[];
}

/**
 * Which lines are new. A bank ID already imported for the account is skipped when it says the same
 * thing, and refused when it says something different: the bank changed a line, or two files
 * disagree, and either way a person should look.
 */
export function planImport(
  parsed: ParsedStatement,
  known: KnownLine[],
): ImportPlan {
  let byId = new Map(known.map((k) => [k.externalId, k]));
  let plan: ImportPlan = {
    accepted: [],
    skipped: [],
    rejected: [...parsed.rejected],
  };
  let inFile = new Set<string>();
  for (let l of parsed.lines) {
    if (inFile.has(l.externalId)) {
      plan.rejected.push({
        row: l.row,
        reason: `Bank ID ${l.externalId} appears twice in this file`,
      });
      continue;
    }
    inFile.add(l.externalId);
    let k = byId.get(l.externalId);
    if (!k) plan.accepted.push(l);
    else if (k.date === l.date && k.amountMinor === l.amountMinor)
      plan.skipped.push(l);
    else
      plan.rejected.push({
        row: l.row,
        reason: `Bank ID ${l.externalId} was imported before with a different date or amount`,
      });
  }
  return plan;
}

/** What a rule needs to decide whether it applies, and what it suggests. */
export interface RuleLike {
  name?: string;
  account?: string;
  descriptionContains?: string;
  direction?: string; // 'in', 'out' or empty for either
  minMinor?: number | null;
  maxMinor?: number | null;
  category?: string;
  payee?: string;
  cls?: string;
  priority?: number | null;
  active?: boolean | null;
}
export interface LineLike {
  account?: string;
  description?: string;
  payee?: string;
  amountMinor?: number;
}

export function ruleApplies(rule: RuleLike, line: LineLike): boolean {
  if (rule.active === false || !rule.category) return false;
  if (rule.account && rule.account !== line.account) return false;
  let amount = line.amountMinor ?? 0;
  if (rule.direction === 'in' && amount <= 0) return false;
  if (rule.direction === 'out' && amount >= 0) return false;
  let size = Math.abs(amount);
  if (rule.minMinor != null && size < rule.minMinor) return false;
  if (rule.maxMinor != null && size > rule.maxMinor) return false;
  let text = rule.descriptionContains?.trim().toLowerCase();
  if (
    text &&
    !`${line.description ?? ''} ${line.payee ?? ''}`
      .toLowerCase()
      .includes(text)
  )
    return false;
  return true;
}

/** The first rule that applies, lowest priority number first. */
export function ruleFor<R extends RuleLike>(
  rules: R[],
  line: LineLike,
): R | undefined {
  return [...rules]
    .sort((a, b) => (a.priority ?? 0) - (b.priority ?? 0))
    .find((r) => ruleApplies(r, line));
}

/** A journal posting as matching reads it. */
export interface PostingLike {
  key?: string;
  date?: string;
  kind?: string;
  memo?: string;
  party?: string;
  reverses?: number | null;
  lines?: { account?: string; debitMinor?: number; creditMinor?: number }[];
}
export interface MatchCandidate<P extends PostingLike> {
  posting: P;
  days: number;
}

/**
 * The postings already in the books a bank line could be: ones that move the line's account by
 * exactly its amount, within `withinDays` of its date, nearest first. A line's amount is the debit it
 * makes to its account (money in debits a bank and pays down a card), so the rule holds for both.
 */
export function matchCandidates<P extends PostingLike>(
  line: { account?: string; date?: string; amountMinor?: number },
  postings: P[],
  taken: Set<string> = new Set(),
  withinDays = 7,
): MatchCandidate<P>[] {
  let day = (d: string) => Date.parse(`${d}T00:00:00Z`) / 86400000;
  let at = day(line.date ?? '');
  return postings
    .filter((p) => p.key && !taken.has(p.key) && p.kind !== 'reversal')
    .map((p) => {
      let net = (p.lines ?? [])
        .filter((l) => l.account === line.account)
        .reduce((n, l) => n + (l.debitMinor ?? 0) - (l.creditMinor ?? 0), 0);
      return { posting: p, net, days: Math.abs(day(p.date ?? '') - at) };
    })
    .filter((c) => c.net === line.amountMinor && c.days <= withinDays)
    .sort((a, b) => a.days - b.days)
    .map(({ posting, days }) => ({ posting, days }));
}

/**
 * The key of the posting a bank line is added as, given its month's postings. A posting reversed by
 * mistake keeps its key in the month, so a later attempt takes the next number: `#2`, `#3`.
 */
export function bankPostingKey(
  importKey: string,
  monthPostings: { key?: string | null }[],
): string {
  let base = `bank:${importKey}`,
    used = monthPostings.filter(
      (p) => p?.key === base || String(p?.key).startsWith(`${base}#`),
    ).length;
  return used ? `${base}#${used + 1}` : base;
}
