// Payroll filings as generated forms: each one's figures from the standing payroll postings in its
// period (and, for W-2s, the paychecks of the standing runs). Nothing here is e-filed.
import { PAYROLL_LIABILITIES } from './payroll-calc';

/** A payroll posting as the forms read it: its date, wage items, and facts by name. */
export interface PayrollPost {
  date: string;
  kind?: string;
  items: { amountMinor?: number | null }[];
  num: (key: string) => number;
  fact: (key: string) => string;
  lines?: {
    account?: string;
    debitMinor?: number;
    creditMinor?: number;
    party?: string;
  }[];
}
export interface FormLine {
  key: string;
  label: string;
  amountMinor: number;
  employeeId?: string | null;
}
export interface FormFigures {
  lines: FormLine[];
  dueMinor: number;
}
export interface W2Paycheck {
  employeeId?: string;
  name?: string;
  grossMinor?: number;
  fitWagesMinor?: number;
  fitMinor?: number;
  ssWagesMinor?: number;
  ssMinor?: number;
  medicareWagesMinor?: number;
  medicareMinor?: number;
  addlMedicareMinor?: number;
  stateWagesMinor?: number;
  stateMinor?: number;
  deductions?: ({ kind?: string; amountMinor?: number } | undefined)[];
}

export const FORMS: Record<string, string> = {
  'irs-941': '941',
  'irs-940': '940',
  'ny-dtf': 'NYS-45',
  'ny-dbl-pfl': 'DBL/PFL',
  ssa: 'W-2/W-3',
};
export const PAYROLL_TAX_KIND = 'payroll tax';

const inPeriod = (date: string, start: string, end: string) =>
  date >= start && date <= end;
const sum = <T>(xs: T[], f: (x: T) => number) =>
  xs.reduce((n, x) => n + (f(x) || 0), 0);
const gross = (p: PayrollPost) => sum(p.items, (i) => i.amountMinor ?? 0);
// A run worked out in the books carries each tax; one synced from a provider only its totals.
const fromBooks = (p: PayrollPost) => !!p.fact('headcount');
/** A provider's runs can't be split by tax, so a form lists them apart, for filing from its report. */
function syncedLines(posts: PayrollPost[]): FormLine[] {
  let synced = posts.filter((p) => !fromBooks(p));
  return synced.length
    ? [
        {
          key: 'synced-wages',
          label: `Not split: gross wages of ${synced.length} provider-synced run${synced.length === 1 ? '' : 's'}; file them from the provider's report`,
          amountMinor: sum(synced, gross),
        },
        {
          key: 'synced-withheld',
          label: 'Not split: what those runs withheld, every tax together',
          amountMinor: sum(synced, (p) => p.num('withholdingMinor')),
        },
        {
          key: 'synced-employer',
          label: 'Not split: those runs’ employer taxes, every tax together',
          amountMinor: sum(synced, (p) => p.num('employerTaxMinor')),
        },
      ]
    : [];
}

/** Form 941 figures for a quarter's payroll postings. */
export function form941(all: PayrollPost[]): FormFigures {
  let posts = all.filter(fromBooks);
  let n = (k: string) => sum(posts, (p) => p.num(k));
  let fit = n('fitMinor'),
    ss = n('ssTaxMinor'),
    med = n('medicareTaxMinor'),
    addl = n('addlMedicareMinor');
  return {
    lines: [
      {
        key: '1',
        label: 'Employees paid',
        amountMinor: Math.max(0, ...posts.map((p) => p.num('headcount'))),
      },
      {
        key: '2',
        label: 'Wages, tips and compensation (W-2 box 1)',
        amountMinor: n('fitWagesMinor'),
      },
      { key: '3', label: 'Federal income tax withheld', amountMinor: fit },
      {
        key: '5a',
        label: 'Taxable Social Security wages',
        amountMinor: n('ssWagesMinor'),
      },
      {
        key: '5a-tax',
        label: 'Social Security tax (employee and employer)',
        amountMinor: ss,
      },
      {
        key: '5c',
        label: 'Taxable Medicare wages',
        amountMinor: n('medicareWagesMinor'),
      },
      {
        key: '5c-tax',
        label: 'Medicare tax (employee and employer)',
        amountMinor: med - addl,
      },
      {
        key: '5d',
        label: 'Wages subject to additional Medicare withholding',
        amountMinor: n('addlMedicareWagesMinor'),
      },
      { key: '5d-tax', label: 'Additional Medicare tax', amountMinor: addl },
      {
        key: '12',
        label: 'Total taxes after adjustments',
        amountMinor: fit + ss + med,
      },
      ...syncedLines(all),
    ],
    dueMinor: fit + ss + med,
  };
}

/** New York's quarterly withholding and wage report (NYS-45). */
export function nys45(all: PayrollPost[]): FormFigures {
  let posts = all.filter(fromBooks);
  let wh = sum(posts, (p) => p.num('stateTaxMinor')),
    ui = sum(posts, (p) => p.num('sutaMinor'));
  return {
    lines: [
      {
        key: 'gross',
        label: 'Total remuneration paid',
        amountMinor: sum(posts, gross),
      },
      {
        key: 'ui-wages',
        label: 'Unemployment insurance wages',
        amountMinor: sum(posts, (p) => p.num('sutaWagesMinor')),
      },
      {
        key: 'ui',
        label: 'Unemployment insurance contributions',
        amountMinor: ui,
      },
      {
        key: 'wh',
        label: 'New York State income tax withheld',
        amountMinor: wh,
      },
      { key: 'due', label: 'Total due', amountMinor: wh + ui },
      ...syncedLines(all),
    ],
    dueMinor: wh + ui,
  };
}

/** Form 940, the year's federal unemployment tax. */
export function form940(all: PayrollPost[]): FormFigures {
  let posts = all.filter(fromBooks);
  let futa = sum(posts, (p) => p.num('futaMinor'));
  let paid = sum(posts, gross),
    exempt = sum(posts, (p) => p.num('section125Minor')),
    taxable = sum(posts, (p) => p.num('futaWagesMinor'));
  let over = paid - exempt - taxable;
  return {
    lines: [
      { key: '3', label: 'Total payments to employees', amountMinor: paid },
      {
        key: '4',
        label: 'Payments exempt from FUTA (section 125 benefits)',
        amountMinor: exempt,
      },
      {
        key: '5',
        label: 'Payments over $7,000 to each employee',
        amountMinor: over,
      },
      {
        key: '6',
        label: 'Subtotal (line 4 plus line 5)',
        amountMinor: exempt + over,
      },
      { key: '7', label: 'Taxable FUTA wages', amountMinor: taxable },
      { key: '8', label: 'FUTA tax before adjustments', amountMinor: futa },
      {
        key: '12',
        label: 'Total FUTA tax after adjustments',
        amountMinor: futa,
      },
      ...syncedLines(all),
    ],
    dueMinor: futa,
  };
}

/** The disability and paid family leave withheld for the carrier. */
export function dblPfl(all: PayrollPost[]): FormFigures {
  let due = sum(all.filter(fromBooks), (p) => p.num('sdiPflMinor'));
  return {
    lines: [
      {
        key: 'due',
        label: 'Disability and paid family leave withheld',
        amountMinor: due,
      },
      ...syncedLines(all),
    ],
    dueMinor: due,
  };
}

/** A W-2 per employee from the year's paychecks, and the W-3 that totals them. */
export function w2s(checks: W2Paycheck[]): FormFigures {
  let by = new Map<string, W2Paycheck[]>();
  for (let p of checks)
    by.set(p.employeeId ?? '', [...(by.get(p.employeeId ?? '') ?? []), p]);
  let boxes: [string, string, (p: W2Paycheck) => number][] = [
    ['1', 'Wages, tips, other compensation', (p) => p.fitWagesMinor ?? 0],
    ['2', 'Federal income tax withheld', (p) => p.fitMinor ?? 0],
    ['3', 'Social Security wages', (p) => p.ssWagesMinor ?? 0],
    ['4', 'Social Security tax withheld', (p) => p.ssMinor ?? 0],
    ['5', 'Medicare wages and tips', (p) => p.medicareWagesMinor ?? 0],
    [
      '6',
      'Medicare tax withheld',
      (p) => (p.medicareMinor ?? 0) + (p.addlMedicareMinor ?? 0),
    ],
    [
      '12D',
      '401(k) elective deferrals',
      (p) =>
        sum(
          (p.deductions ?? []).filter((d) => d?.kind === 'retirement'),
          (d) => d!.amountMinor ?? 0,
        ),
    ],
    ['16', 'State wages (NY)', (p) => p.stateWagesMinor ?? 0],
    ['17', 'State income tax (NY)', (p) => p.stateMinor ?? 0],
  ];
  let lines: FormLine[] = [];
  for (let [id, mine] of [...by].sort(([a], [b]) => a.localeCompare(b)))
    for (let [box, label, f] of boxes)
      lines.push({
        key: `W-2 ${id} ${box}`,
        label: `${mine[0].name || id} · box ${box} ${label}`,
        amountMinor: sum(mine, f),
        employeeId: id,
      });
  for (let [box, label, f] of boxes)
    lines.push({
      key: `W-3 ${box}`,
      label: `W-3 · box ${box} ${label}`,
      amountMinor: sum(checks, f),
    });
  return { lines, dueMinor: 0 };
}

/** A filing's figures from its period's postings and paychecks. */
export function formFigures(
  agencyId: string,
  posts: PayrollPost[],
  checks: W2Paycheck[],
  start: string,
  end: string,
): FormFigures {
  let mine = posts.filter((p) => inPeriod(p.date, start, end));
  switch (agencyId) {
    case 'irs-941':
      return form941(mine);
    case 'irs-940':
      return form940(mine);
    case 'ny-dtf':
      return nys45(mine);
    case 'ny-dbl-pfl':
      return dblPfl(mine);
    case 'ssa':
      return w2s(checks);
    default:
      return { lines: [], dueMinor: 0 };
  }
}

/** What each agency is owed from the runs' facts, less what's been paid it. */
export function agencyOwed(posts: PayrollPost[]): Map<string, number> {
  let L = PAYROLL_LIABILITIES;
  let owed = new Map<string, number>([
    [L.federal.agencyId, 0],
    [L.futa.agencyId, 0],
    [L.state.agencyId, 0],
    [L.dblPfl.agencyId, 0],
  ]);
  let add = (id: string, n: number) => owed.set(id, (owed.get(id) ?? 0) + n);
  for (let p of posts) {
    if (p.kind === 'payroll' && p.fact('headcount')) {
      add(
        L.federal.agencyId,
        p.num('fitMinor') + p.num('ssTaxMinor') + p.num('medicareTaxMinor'),
      );
      add(L.futa.agencyId, p.num('futaMinor'));
      add(L.state.agencyId, p.num('stateTaxMinor') + p.num('sutaMinor'));
      add(L.dblPfl.agencyId, p.num('sdiPflMinor'));
    }
    if (
      p.kind === 'bank-payment' &&
      p.fact('kind') === PAYROLL_TAX_KIND &&
      owed.has(p.fact('payee'))
    )
      add(p.fact('payee'), -p.num('amountMinor'));
  }
  return owed;
}

/** The credit balance each agency's liability account holds in the journal. */
export function liabilityBalance(posts: PayrollPost[]): Map<string, number> {
  let byAccount = new Map<string, string>(
    Object.values(PAYROLL_LIABILITIES).map((l) => [l.account, l.agencyId]),
  );
  let out = new Map<string, number>(
    Object.values(PAYROLL_LIABILITIES).map((l) => [l.agencyId, 0]),
  );
  for (let p of posts)
    for (let l of p.lines ?? []) {
      let id = byAccount.get(l.account ?? '');
      if (id)
        out.set(
          id,
          (out.get(id) ?? 0) + (l.creditMinor ?? 0) - (l.debitMinor ?? 0),
        );
    }
  return out;
}
