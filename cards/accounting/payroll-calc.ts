// Paycheck arithmetic, in integer cents. Each tax rounds per paycheck; a run's totals are the sum of
// its paychecks. The tax figures come from hand-entered tables (see PayrollTaxTable), looked up by
// the newest table effective on or before the pay date.

export type FilingStatus = 'single' | 'married' | 'head';
export type PaySchedule = 'weekly' | 'biweekly' | 'semimonthly' | 'monthly';
export type DeductionKind = 'retirement' | 'section125' | 'posttax';

export const PERIODS: Record<PaySchedule, number> = {
  weekly: 52,
  biweekly: 26,
  semimonthly: 24,
  monthly: 12,
};

export const TAX_KEYS = [
  'federal-income',
  'social-security',
  'medicare',
  'futa',
  'ny-income',
  'ny-suta',
  'ny-sdi',
  'ny-pfl',
] as const;
export type TaxKey = (typeof TAX_KEYS)[number];

export interface Bracket {
  filingStatus?: string;
  overMinor?: number; // annual taxable wages the rate starts above
  ratePpm?: number;
}
export interface StatusAmount {
  filingStatus?: string;
  amountMinor?: number;
}
/** The shape of a PayrollTaxTable card the calculation reads. */
export interface TaxTableData {
  tax?: string;
  year?: number;
  effectiveFrom?: string;
  ratePpm?: number; // the employee's rate
  employerRatePpm?: number;
  wageBaseMinor?: number; // annual wages the tax stops at
  thresholdMinor?: number; // annual wages an extra rate starts above
  extraRatePpm?: number;
  weeklyCapMinor?: number;
  annualCapMinor?: number; // most the tax can be in a year
  allowanceMinor?: number; // what each withholding allowance takes off annual wages
  brackets?: (Bracket | undefined)[];
  statusAmounts?: (StatusAmount | undefined)[]; // a deduction from annual wages by filing status
}

/** The newest table for a tax effective on or before the pay date. */
export function tableFor(
  tables: (TaxTableData | undefined)[],
  tax: TaxKey,
  payDate: string,
): TaxTableData | undefined {
  return tables
    .filter(
      (t): t is TaxTableData =>
        !!t && t.tax === tax && !!t.effectiveFrom && t.effectiveFrom <= payDate,
    )
    .sort((a, b) => String(b.effectiveFrom).localeCompare(a.effectiveFrom!))[0];
}

const ppm = (minor: number, rate: number | undefined) =>
  Math.round((minor * (rate ?? 0)) / 1_000_000);

/** Tax on annual taxable wages through progressive brackets for a filing status. */
export function bracketTax(
  annualMinor: number,
  brackets: (Bracket | undefined)[] | undefined,
  status: string,
): number {
  let rows = (brackets ?? [])
    .filter((b): b is Bracket => !!b && b.filingStatus === status)
    .sort((a, b) => (a.overMinor ?? 0) - (b.overMinor ?? 0));
  let tax = 0;
  for (let i = 0; i < rows.length; i++) {
    let from = rows[i].overMinor ?? 0,
      to = rows[i + 1]?.overMinor ?? Infinity;
    if (annualMinor <= from) break;
    tax += ((Math.min(annualMinor, to) - from) * (rows[i].ratePpm ?? 0)) / 1e6;
  }
  return tax;
}

const statusAmount = (t: TaxTableData | undefined, status: string) =>
  (t?.statusAmounts ?? []).find((s) => s?.filingStatus === status)
    ?.amountMinor ?? 0;

export interface PayDeductionData {
  label?: string;
  kind?: string;
  amountMinor?: number; // a fixed amount each paycheck
  ratePpm?: number; // or a share of gross
  account?: string; // the liability it's owed onward on
}
export interface PaySetupData {
  employeeId?: string;
  name?: string;
  payType?: string; // salary or hourly
  annualSalaryMinor?: number;
  hourlyRateMinor?: number;
  schedule?: string;
  expenseAccount?: string;
  cls?: string;
  filingStatus?: string;
  allowances?: number; // state withholding allowances
  federalCreditsMinor?: number; // annual credits for dependents (W-4 step 3)
  extraWithholdingMinor?: number; // added to federal withholding each paycheck
  deductions?: (PayDeductionData | undefined)[];
}
/** Year-to-date wages and taxes before this paycheck, so wage-base limits stop at their cap. */
export interface Ytd {
  grossMinor: number;
  ssWagesMinor: number;
  medicareWagesMinor: number;
  futaWagesMinor: number;
  sutaWagesMinor: number;
  pflMinor: number;
  netMinor: number;
}
export const NO_YTD: Ytd = {
  grossMinor: 0,
  ssWagesMinor: 0,
  medicareWagesMinor: 0,
  futaWagesMinor: 0,
  sutaWagesMinor: 0,
  pflMinor: 0,
  netMinor: 0,
};

export interface DeductionLine {
  label: string;
  kind: DeductionKind;
  account: string;
  amountMinor: number;
}
export interface PaycheckData {
  employeeId: string;
  name: string;
  expenseAccount: string;
  cls: string | null;
  hoursMilli: number | null;
  grossMinor: number;
  deductions: DeductionLine[];
  fitWagesMinor: number;
  fitMinor: number;
  ssWagesMinor: number;
  ssMinor: number;
  medicareWagesMinor: number;
  medicareMinor: number;
  addlMedicareMinor: number;
  stateWagesMinor: number;
  stateMinor: number;
  sdiMinor: number;
  pflMinor: number;
  netMinor: number;
  erSsMinor: number;
  erMedicareMinor: number;
  futaWagesMinor: number;
  futaMinor: number;
  sutaWagesMinor: number;
  sutaMinor: number;
  ytdGrossMinor: number;
  ytdNetMinor: number;
}

const KINDS: DeductionKind[] = ['retirement', 'section125', 'posttax'];
const kindOf = (k: string | undefined): DeductionKind =>
  KINDS.includes(k as DeductionKind) ? (k as DeductionKind) : 'posttax';
const capLeft = (base: number | undefined, used: number) =>
  base ? Math.max(0, base - used) : Infinity;

export interface PaycheckInput {
  setup: PaySetupData;
  payDate: string;
  hoursMilli?: number; // hourly pay: hours worked this period, in thousandths
  ytd?: Ytd;
  tables: (TaxTableData | undefined)[];
}

/** One paycheck: gross, deductions, each tax, and net. Refuses what it can't work out. */
export function calcPaycheck({
  setup,
  payDate,
  hoursMilli,
  ytd = NO_YTD,
  tables,
}: PaycheckInput): PaycheckData {
  let who = setup.name || setup.employeeId || 'this employee';
  let periods = PERIODS[setup.schedule as PaySchedule];
  if (!periods) throw new Error(`Give ${who} a pay schedule.`);
  let need = (tax: TaxKey) => {
    let t = tableFor(tables, tax, payDate);
    if (!t) throw new Error(`There is no ${tax} tax table for ${payDate}.`);
    return t;
  };
  let hourly = setup.payType === 'hourly';
  let gross = hourly
    ? Math.round(((setup.hourlyRateMinor ?? 0) * (hoursMilli ?? 0)) / 1000)
    : Math.round((setup.annualSalaryMinor ?? 0) / periods);
  if (gross < 0) throw new Error(`${who}'s pay can't be negative.`);

  let deductions: DeductionLine[] = (setup.deductions ?? [])
    .filter((d): d is PayDeductionData => !!d)
    .map((d) => ({
      label: d.label ?? '',
      kind: kindOf(d.kind),
      account: d.account ?? '',
      amountMinor: d.ratePpm ? ppm(gross, d.ratePpm) : (d.amountMinor ?? 0),
    }));
  let byKind = (k: DeductionKind) =>
    deductions
      .filter((d) => d.kind === k)
      .reduce((n, d) => n + d.amountMinor, 0);
  let retirement = byKind('retirement'),
    s125 = byKind('section125');
  let status = (setup.filingStatus as FilingStatus) || 'single';

  // Federal income tax: the annual percentage method.
  let fitWages = Math.max(0, gross - retirement - s125);
  let fed = need('federal-income');
  let annualFit =
    bracketTax(fitWages * periods, fed.brackets, status) -
    (setup.federalCreditsMinor ?? 0);
  let fit =
    Math.max(0, Math.round(annualFit / periods)) +
    (setup.extraWithholdingMinor ?? 0);

  // Social Security and Medicare: section 125 comes off, retirement doesn't.
  let ficaWages = Math.max(0, gross - s125);
  let ss = need('social-security');
  let ssWages = Math.min(
    ficaWages,
    capLeft(ss.wageBaseMinor, ytd.ssWagesMinor),
  );
  let med = need('medicare');
  let over = med.thresholdMinor ?? Infinity;
  let addlWages = Math.max(
    0,
    ytd.medicareWagesMinor + ficaWages - Math.max(over, ytd.medicareWagesMinor),
  );

  // Employer unemployment taxes, each to its wage base.
  let futa = need('futa');
  let futaWages = Math.min(
    ficaWages,
    capLeft(futa.wageBaseMinor, ytd.futaWagesMinor),
  );
  let suta = need('ny-suta');
  let sutaWages = Math.min(
    ficaWages,
    capLeft(suta.wageBaseMinor, ytd.sutaWagesMinor),
  );

  // New York withholding: annualize, less the deduction and allowances, through the brackets.
  let ny = need('ny-income');
  let nyStatus = status === 'married' ? 'married' : 'single';
  let nyAnnual = Math.max(
    0,
    fitWages * periods -
      statusAmount(ny, nyStatus) -
      (setup.allowances ?? 0) * (ny.allowanceMinor ?? 0),
  );
  let state = Math.max(
    0,
    Math.round(bracketTax(nyAnnual, ny.brackets, nyStatus) / periods),
  );

  // New York disability and paid family leave, each to its cap.
  let sdiT = need('ny-sdi');
  let sdi = Math.min(
    ppm(gross, sdiT.ratePpm),
    sdiT.weeklyCapMinor
      ? Math.round((sdiT.weeklyCapMinor * 52) / periods)
      : Infinity,
  );
  let pflT = need('ny-pfl');
  let pfl = Math.min(
    ppm(gross, pflT.ratePpm),
    capLeft(pflT.annualCapMinor, ytd.pflMinor),
  );

  let p = {
    fitMinor: fit,
    ssMinor: ppm(ssWages, ss.ratePpm),
    medicareMinor: ppm(ficaWages, med.ratePpm),
    addlMedicareMinor: ppm(addlWages, med.extraRatePpm),
    stateMinor: state,
    sdiMinor: sdi,
    pflMinor: pfl,
  };
  let taxes = Object.values(p).reduce((n, x) => n + x, 0);
  let net = gross - deductions.reduce((n, d) => n + d.amountMinor, 0) - taxes;
  if (net < 0)
    throw new Error(
      `${who}'s deductions and taxes come to more than their pay this period.`,
    );
  return {
    employeeId: setup.employeeId ?? '',
    name: setup.name ?? '',
    expenseAccount: setup.expenseAccount ?? '',
    cls: setup.cls || null,
    hoursMilli: hourly ? (hoursMilli ?? 0) : null,
    grossMinor: gross,
    deductions,
    fitWagesMinor: fitWages,
    ...p,
    ssWagesMinor: ssWages,
    medicareWagesMinor: ficaWages,
    stateWagesMinor: fitWages,
    netMinor: net,
    erSsMinor: ppm(ssWages, ss.employerRatePpm),
    erMedicareMinor: ppm(ficaWages, med.employerRatePpm),
    futaWagesMinor: futaWages,
    futaMinor: ppm(futaWages, futa.employerRatePpm),
    sutaWagesMinor: sutaWages,
    sutaMinor: ppm(sutaWages, suta.employerRatePpm),
    ytdGrossMinor: ytd.grossMinor + gross,
    ytdNetMinor: ytd.netMinor + net,
  };
}

/** What a paycheck withholds from the employee: every employee tax. */
export const withheldOf = (p: Partial<PaycheckData>) =>
  (p.fitMinor ?? 0) +
  (p.ssMinor ?? 0) +
  (p.medicareMinor ?? 0) +
  (p.addlMedicareMinor ?? 0) +
  (p.stateMinor ?? 0) +
  (p.sdiMinor ?? 0) +
  (p.pflMinor ?? 0);
/** What a paycheck costs the employer on top of gross. */
export const employerTaxOf = (p: Partial<PaycheckData>) =>
  (p.erSsMinor ?? 0) +
  (p.erMedicareMinor ?? 0) +
  (p.futaMinor ?? 0) +
  (p.sutaMinor ?? 0);

/** An employee's year to date from the paychecks of standing runs in the pay date's year, before it. */
export function ytdOf(
  employeeId: string,
  payDate: string,
  runs: {
    date?: string;
    paychecks?: (Partial<PaycheckData> | undefined)[];
  }[],
): Ytd {
  let year = payDate.slice(0, 4),
    out = { ...NO_YTD };
  for (let r of runs) {
    let d = r.date ?? '';
    if (d.slice(0, 4) !== year || d >= payDate) continue;
    for (let p of r.paychecks ?? []) {
      if (!p || p.employeeId !== employeeId) continue;
      out.grossMinor += p.grossMinor ?? 0;
      out.ssWagesMinor += p.ssWagesMinor ?? 0;
      out.medicareWagesMinor += p.medicareWagesMinor ?? 0;
      out.futaWagesMinor += p.futaWagesMinor ?? 0;
      out.sutaWagesMinor += p.sutaWagesMinor ?? 0;
      out.pflMinor += p.pflMinor ?? 0;
      out.netMinor += p.netMinor ?? 0;
    }
  }
  return out;
}

// ── runs ─────────────────────────────────────────────────────────────────────
/** The liability accounts payroll taxes wait in, and the agency each is owed to. */
export const PAYROLL_LIABILITIES = {
  federal: { account: '2310', agencyId: 'irs-941' },
  futa: { account: '2315', agencyId: 'irs-940' },
  state: { account: '2320', agencyId: 'ny-dtf' },
  dblPfl: { account: '2330', agencyId: 'ny-dbl-pfl' },
} as const;
export const EMPLOYER_TAX_ACCOUNT = '6120';

const isoDay = (t: number) => new Date(t).toISOString().slice(0, 10);
const dayMs = 864e5;

/** The days a paycheck on this date pays for: the period ends on the pay date. */
export function periodFor(
  schedule: string,
  payDate: string,
): { start: string; end: string } {
  let t = Date.parse(`${payDate}T00:00:00Z`);
  if (isNaN(t)) return { start: '', end: '' };
  let [y, m, d] = payDate.split('-').map(Number);
  let monthEnd = isoDay(Date.UTC(y, m, 0));
  let first = `${payDate.slice(0, 7)}-01`;
  switch (schedule) {
    case 'weekly':
      return { start: isoDay(t - 6 * dayMs), end: payDate };
    case 'biweekly':
      return { start: isoDay(t - 13 * dayMs), end: payDate };
    case 'semimonthly':
      return d <= 15
        ? { start: first, end: `${payDate.slice(0, 7)}-15` }
        : { start: `${payDate.slice(0, 7)}-16`, end: monthEnd };
    default:
      return { start: first, end: monthEnd };
  }
}

const total = (
  checks: Partial<PaycheckData>[],
  f: (p: Partial<PaycheckData>) => number,
) => checks.reduce((n, p) => n + f(p), 0);
const deducted = (p: Partial<PaycheckData>) =>
  (p.deductions ?? []).reduce((n, d) => n + (d?.amountMinor ?? 0), 0);

/** A run's stored totals, each the sum of its paychecks. */
export function runTotals(checks: Partial<PaycheckData>[]) {
  let wages = new Map<
    string,
    { account: string; cls: string | null; amountMinor: number }
  >();
  for (let p of checks) {
    let k = `${p.expenseAccount}|${p.cls ?? ''}`;
    let w = wages.get(k) ?? {
      account: p.expenseAccount ?? '',
      cls: p.cls ?? null,
      amountMinor: 0,
    };
    w.amountMinor += p.grossMinor ?? 0;
    wages.set(k, w);
  }
  let n = (f: (p: Partial<PaycheckData>) => number) => total(checks, f);
  return {
    wages: [...wages.values()].map((w) => ({
      account: w.account,
      label: w.cls ? `Wages · ${w.cls}` : 'Wages',
      amountMinor: w.amountMinor,
      cls: w.cls,
      loc: null,
    })),
    withholdingMinor: n(withheldOf),
    deductionsMinor: n(deducted),
    employerTaxMinor: n(employerTaxOf),
    netMinor: n((p) => p.netMinor ?? 0),
    fitMinor: n((p) => p.fitMinor ?? 0),
    ssWagesMinor: n((p) => p.ssWagesMinor ?? 0),
    ssTaxMinor: n((p) => (p.ssMinor ?? 0) + (p.erSsMinor ?? 0)),
    medicareWagesMinor: n((p) => p.medicareWagesMinor ?? 0),
    medicareTaxMinor: n(
      (p) =>
        (p.medicareMinor ?? 0) +
        (p.erMedicareMinor ?? 0) +
        (p.addlMedicareMinor ?? 0),
    ),
    stateWagesMinor: n((p) => p.stateWagesMinor ?? 0),
    stateTaxMinor: n((p) => p.stateMinor ?? 0),
    sdiPflMinor: n((p) => (p.sdiMinor ?? 0) + (p.pflMinor ?? 0)),
    futaWagesMinor: n((p) => p.futaWagesMinor ?? 0),
    futaMinor: n((p) => p.futaMinor ?? 0),
    sutaWagesMinor: n((p) => p.sutaWagesMinor ?? 0),
    sutaMinor: n((p) => p.sutaMinor ?? 0),
    headcount: checks.length,
  };
}
export type RunTotals = ReturnType<typeof runTotals>;

interface Line {
  account: string;
  debitMinor: number;
  creditMinor: number;
  cls?: string;
  party?: string;
}
/**
 * What a run with paychecks posts: wages by expense account and class, employer taxes, each tax to
 * the liability of the agency it's owed to, each deduction to its own liability, and net from the
 * bank.
 */
export function paycheckPostings(run: {
  bank?: string;
  employerTaxAccount?: string;
  wages?: (
    | { account?: string; amountMinor?: number; cls?: string }
    | undefined
  )[];
  employerTaxMinor?: number;
  fitMinor?: number;
  ssTaxMinor?: number;
  medicareTaxMinor?: number;
  futaMinor?: number;
  stateTaxMinor?: number;
  sutaMinor?: number;
  sdiPflMinor?: number;
  netMinor?: number;
  paychecks?: (Partial<PaycheckData> | undefined)[];
}): Line[] {
  let L = PAYROLL_LIABILITIES;
  let cr = (
    { account, agencyId }: { account: string; agencyId: string },
    minor: number,
  ): Line => ({
    account,
    debitMinor: 0,
    creditMinor: minor,
    party: agencyId,
  });
  let byAccount = new Map<string, number>();
  for (let p of run.paychecks ?? [])
    for (let d of p?.deductions ?? [])
      if (d)
        byAccount.set(
          d.account ?? '',
          (byAccount.get(d.account ?? '') ?? 0) + (d.amountMinor ?? 0),
        );
  return [
    ...(run.wages ?? [])
      .filter((w) => !!w)
      .map((w) => ({
        account: w!.account ?? '',
        debitMinor: w!.amountMinor ?? 0,
        creditMinor: 0,
        cls: w!.cls ?? undefined,
      })),
    {
      account: run.employerTaxAccount ?? EMPLOYER_TAX_ACCOUNT,
      debitMinor: run.employerTaxMinor ?? 0,
      creditMinor: 0,
    },
    cr(
      L.federal,
      (run.fitMinor ?? 0) + (run.ssTaxMinor ?? 0) + (run.medicareTaxMinor ?? 0),
    ),
    cr(L.futa, run.futaMinor ?? 0),
    cr(L.state, (run.stateTaxMinor ?? 0) + (run.sutaMinor ?? 0)),
    cr(L.dblPfl, run.sdiPflMinor ?? 0),
    ...[...byAccount].map(([account, minor]) => ({
      account,
      debitMinor: 0,
      creditMinor: minor,
    })),
    { account: run.bank ?? '', debitMinor: 0, creditMinor: run.netMinor ?? 0 },
  ];
}

/** The runs that stand: posted, or journaled and not reversed in the journal. */
export function standingRuns<T extends { status?: string; docNo?: string }>(
  runs: (T | undefined)[],
  journaledSources: Set<string>,
): T[] {
  return runs.filter(
    (r): r is T =>
      !!r &&
      (r.status === 'posted' ||
        (r.status === 'journaled' && journaledSources.has(r.docNo ?? ''))),
  );
}

/** Hours an employee worked in a period, from their time activities, in thousandths. */
export function hoursIn(
  acts: (
    | {
        workerKind?: string;
        worker?: string;
        date?: string;
        hours?: number;
      }
    | undefined
  )[],
  employeeId: string,
  period: { start: string; end: string },
): number | undefined {
  let mine = acts.filter(
    (t) =>
      !!t &&
      t.workerKind === 'employee' &&
      t.worker === employeeId &&
      (t.date ?? '') >= period.start &&
      (t.date ?? '') <= period.end,
  );
  return mine.length
    ? mine.reduce((n, t) => n + (t!.hours ?? 0), 0)
    : undefined;
}
