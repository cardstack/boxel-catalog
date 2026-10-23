// Reconciling an account against a bank statement: the book balance on the statement date, what the
// reconciliation lists to tick, and the key a bank line posts under. Plain functions over the journal
// months, month closes and reconciliations the desk already holds.

export interface LineLike {
  account?: string | null;
  debitMinor?: number | null;
  creditMinor?: number | null;
}
export interface PostingLike {
  key?: string | null;
  date?: string | null;
  lines?: (LineLike | null | undefined)[] | null;
}
export interface JournalMonthLike {
  month?: string | null;
  postings?: (PostingLike | null | undefined)[] | null;
}
export interface CloseLike {
  month?: string | null;
  status?: string | null;
  totals?: (LineLike | null | undefined)[] | null;
}
export interface ReconciliationLike {
  id?: string;
  account?: string | null;
  statementDate?: string | null;
  side?: string | null;
  status?: string | null;
  outstanding?:
    | (
        | { ref?: string | null; amountMinor?: number | null }
        | null
        | undefined
      )[]
    | null;
  cleared?: ({ key?: string | null } | null | undefined)[] | null;
}

const present = <T>(xs: (T | null | undefined)[] | null | undefined): T[] =>
  (xs ?? []).filter((x): x is T => x != null);
const netOn = (lines: LineLike[], account: string) =>
  lines
    .filter((l) => l.account === account)
    .reduce((n, l) => n + (l.debitMinor ?? 0) - (l.creditMinor ?? 0), 0);

/** The last day of a `yyyy-mm` month, as `yyyy-mm-dd`. */
export function monthEndOf(ym: string): string {
  return ym
    ? new Date(Date.UTC(+ym.slice(0, 4), +ym.slice(5, 7), 0))
        .toISOString()
        .slice(0, 10)
    : '';
}

/** The book balance of an account on a day, month by month up to the day's month: a closed month counts
 *  its stored totals, which hold everything posted in it; any other month, and a closed month the day
 *  ends before its last day, counts the journal's postings up to the day. Flipped for the credit side. */
export function bookAt(
  account: string,
  date: string,
  side: string | null | undefined,
  closes: CloseLike[],
  journalMonths: JournalMonthLike[],
): number {
  let month = date.slice(0, 7),
    closed = new Map(
      closes
        .filter((c) => c.status === 'closed')
        .map((c) => [String(c.month ?? ''), c]),
    );
  let months = [
    ...new Set([
      ...closed.keys(),
      ...journalMonths.map((m) => String(m.month ?? '')),
    ]),
  ]
    .filter((m) => m && m <= month)
    .sort();
  let n = 0;
  for (let m of months) {
    let c = closed.get(m);
    if (c && (m < month || date === monthEndOf(m))) {
      n += netOn(present(c.totals), account);
      continue;
    }
    let jm = journalMonths.find((j) => j.month === m);
    for (let p of present(jm?.postings))
      if (String(p.date ?? '') <= date) n += netOn(present(p.lines), account);
  }
  return side === 'credit' ? -n : n;
}

/** The last day of the latest closed month before `month`: where a first reconciliation's list starts. */
export function closedBefore(month: string, closes: CloseLike[]): string {
  let latest = closes
    .filter((c) => c.status === 'closed' && String(c.month ?? '') < month)
    .map((c) => String(c.month))
    .sort()
    .at(-1);
  return monthEndOf(latest ?? '');
}

/** The account's finished reconciliation with the latest statement date before `before`, if any. */
export function lastRecOf<R extends ReconciliationLike>(
  recs: R[],
  account: string,
  before: string,
  except?: string,
): R | undefined {
  return recs
    .filter(
      (x) =>
        x.account === account &&
        x.id !== except &&
        x.status === 'reconciled' &&
        String(x.statementDate ?? '') < before,
    )
    .sort((a, b) =>
      String(a.statementDate ?? '').localeCompare(
        String(b.statementDate ?? ''),
      ),
    )
    .at(-1);
}

export interface RecItem<P> {
  key: string;
  date: string;
  amountMinor: number; // as the books carry it for the reconciled account
  posting?: P; // absent for an item carried in as outstanding
}

/** The day after which a reconciliation lists postings: the previous reconciliation's statement date,
 *  or for a first one the end of the closed run before the statement month. */
export function recFrom(
  rec: ReconciliationLike,
  recs: ReconciliationLike[],
  closes: CloseLike[],
): string {
  let date = rec.statementDate ?? '';
  return (
    lastRecOf(recs, rec.account ?? '', date, rec.id)?.statementDate ??
    closedBefore(date.slice(0, 7), closes)
  );
}

/** What a reconciliation ticks: what was outstanding before, then every posting on the account dated
 *  after `recFrom` up to the statement date that no other reconciliation of the account cleared. */
export function recItems<P extends PostingLike>(
  rec: ReconciliationLike,
  recs: ReconciliationLike[],
  closes: CloseLike[],
  journalMonths: (JournalMonthLike & {
    postings?: (P | null | undefined)[] | null;
  })[],
): RecItem<P>[] {
  let account = rec.account ?? '',
    date = rec.statementDate ?? '',
    sign = rec.side === 'credit' ? -1 : 1,
    from = recFrom(rec, recs, closes);
  let clearedBefore = new Set(
    recs
      .filter((x) => x.account === account && x.id !== rec.id)
      .flatMap((x) => present(x.cleared).map((i) => i.key)),
  );
  let carried: RecItem<P>[] = present(rec.outstanding).map((o) => ({
    key: String(o.ref ?? ''),
    date: '',
    amountMinor: o.amountMinor ?? 0,
  }));
  let posted = journalMonths
    .flatMap((m) => present(m.postings))
    .filter(
      (p) =>
        String(p.date ?? '') > from &&
        String(p.date ?? '') <= date &&
        p.key &&
        !clearedBefore.has(p.key) &&
        !carried.some((c) => c.key === p.key),
    )
    .map((p) => ({
      key: p.key as string,
      date: String(p.date ?? ''),
      amountMinor: netOn(present(p.lines), account) * sign,
      posting: p,
    }))
    .filter((i) => i.amountMinor !== 0);
  return [...carried, ...posted];
}

/** The key a bank line posts under. A posting reversed by mistake keeps its key in the month, so a later
 *  attempt takes the next number. */
export function bankKey(
  importKey: string | null | undefined,
  date: string | null | undefined,
  journalMonths: JournalMonthLike[],
): string {
  let base = `bank:${importKey}`,
    month = String(date ?? '').slice(0, 7),
    used = present(
      journalMonths.find((m) => m.month === month)?.postings,
    ).filter(
      (p) => p.key === base || String(p.key).startsWith(`${base}#`),
    ).length;
  return used ? `${base}#${used + 1}` : base;
}
