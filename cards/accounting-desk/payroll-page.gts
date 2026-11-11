// The desk's Payroll page: who is paid and how, running payroll for a pay date (draft the run,
// review each paycheck, post it), and past runs with their stubs.
import Component from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { fn } from '@ember/helper';
import { on } from '@ember/modifier';
import {
  getRelationshipMembershipState,
  type CardContext,
  type CardDef,
  type ViewCardFn,
} from '@cardstack/base/card-api';
import { operations } from '@cardstack/base/operations';
import { codeRef } from '@cardstack/runtime-common';
import { Button } from '@cardstack/pretui/components/button';
import { Callout } from '@cardstack/pretui/components/callout';
import {
  DataTable,
  type DataColumn,
} from '@cardstack/pretui/components/data-table';
import { Descriptions } from '@cardstack/pretui/components/descriptions';
import { Drawer } from '@cardstack/pretui/components/drawer';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { Field } from '@cardstack/pretui/components/field';
import { Select } from '@cardstack/pretui/components/select';
import { Input } from '@cardstack/pretui/components/input';
import { AlertDialog } from '@cardstack/pretui/components/alert-dialog';
import { StatusChip } from '@cardstack/pretui/components/status-chip';
import { money, toneFor, type Fact } from '../accounting/record-kit';
import { AllCards } from '../accounting/all-cards';
import { escapeGuard } from './escape-guard';
import {
  stubFacts,
  labelOf,
  FILING_STATUSES,
  PAY_SCHEDULES,
  PayrollAgency,
} from '../accounting/ledger-payroll';
import {
  PayrollFiling,
  filingStatusLabel,
} from '../accounting/ledger-payroll-filings';
import { PayrollRun, BankPayment } from '../accounting/ledger-cash';
import {
  agencyOwed,
  liabilityBalance,
  PAYROLL_TAX_KIND,
} from '../accounting/payroll-forms';
import {
  journalPostings,
  journalPostingFor,
} from '../accounting/ledger-journal';
import {
  calcPaycheck,
  hoursIn,
  periodFor,
  runTotals,
  standingRuns,
  ytdOf,
  runBlocker,
  staleEmployees,
  EMPLOYER_TAX_ACCOUNT,
  PAYROLL_LIABILITIES,
  type PaycheckData,
} from '../accounting/payroll-calc';

// @ts-expect-error TS1470 -- import.meta is valid in realm-served modules; only the CommonJS type-check rejects it
const here: string = import.meta.url;

export interface PayrollPageSignature {
  Args: {
    ledger: CardDef | undefined;
    context: CardContext | undefined;
    realms: string[];
    viewCard?: ViewCardFn;
    notify: (title: string, message?: string) => void;
  };
}

const isName = (col: unknown) => (col as { key?: string })?.key === 'name';
const isNumber = (col: unknown) => (col as { key?: string })?.key === 'number';
const isAgency = (col: unknown) => (col as { key?: string })?.key === 'agency';
const isAction = (col: unknown) => (col as { key?: string })?.key === 'action';
const isStatus = (col: unknown) => (col as { key?: string })?.key === 'status';
const plural = (n: number, one: string, many = `${one}s`) =>
  `${n} ${n === 1 ? one : many}`;
const instancesOf = (r: unknown): any[] =>
  (((r as any)?.instances ?? []) as any[]).filter(Boolean);
const PAYCHECK_KEYS = [
  'employeeId',
  'name',
  'expenseAccount',
  'cls',
  'hoursMilli',
  'grossMinor',
  'deductionsMinor',
  'fitWagesMinor',
  'fitMinor',
  'ssWagesMinor',
  'ssMinor',
  'medicareWagesMinor',
  'medicareMinor',
  'addlMedicareMinor',
  'stateWagesMinor',
  'stateMinor',
  'sdiMinor',
  'pflMinor',
  'netMinor',
  'erSsMinor',
  'erMedicareMinor',
  'futaWagesMinor',
  'futaMinor',
  'sutaWagesMinor',
  'sutaMinor',
  'ytdGrossMinor',
  'ytdNetMinor',
];
/** A stored paycheck as plain values: what an operation takes and the calculation reads. */
const plainPaycheck = (p: any): PaycheckData =>
  ({
    ...Object.fromEntries(PAYCHECK_KEYS.map((k) => [k, p?.[k] ?? null])),
    deductions: ((p?.deductions ?? []) as any[]).filter(Boolean).map((d) => ({
      label: d.label ?? null,
      kind: d.kind ?? null,
      account: d.account ?? null,
      amountMinor: d.amountMinor ?? 0,
    })),
  }) as PaycheckData;

interface SetupRow {
  key: string;
  card: any;
  name: string;
  pay: string;
  schedule: string;
  posts: string;
  filing: string;
  period: string;
}
interface CheckRow {
  key: string;
  name: string;
  hours: string;
  gross: string;
  deductions: string;
  taxes: string;
  net: string;
  employer: string;
}
interface RunRow {
  key: string;
  card: any;
  number: string;
  date: string;
  schedule: string;
  people: number;
  gross: string;
  net: string;
  status: string;
}

const doc = (Def: unknown, eq: Record<string, string>) => ({
  every: [{ type: Def }, { on: Def, eq }],
});
const periodEndOf = (period: string | undefined) =>
  String(period ?? '')
    .split(' to ')
    .at(-1) ?? '';
/** Every payroll agency refuses a run dated in a period filed with it. */
export const payrollLock =
  (date: string) =>
  (b: any): unknown =>
    b
      .on(b.find({ type: PayrollAgency }, { expect: 'many' }))
      .checkOpen({ date });
/** What posting a document changes on the payroll side, in the same batch: the period locks for a
 *  run, and the filing a payroll tax payment pays. */
export function payrollPostSteps(c: unknown): ((b: any) => unknown)[] {
  if (c instanceof PayrollRun) return [payrollLock(c.date ?? '')];
  if (c instanceof BankPayment && c.kind === PAYROLL_TAX_KIND)
    return [
      (b) =>
        b
          .on(
            b.find(
              doc(PayrollFiling, {
                agencyId: c.payee ?? '',
                periodEnd: periodEndOf(c.period),
              }),
              { expect: 'one' },
            ),
          )
          .markPaid({ paymentNo: c.docNo, amountMinor: c.amountMinor }),
    ];
  return [];
}
/** What reversing a payroll posting puts back: a run in a filed period can't be reversed, and a
 *  payment comes back off its filing. */
export function payrollUnwindSteps(p: any): ((b: any) => unknown)[] {
  let fact = (k: string) =>
    String(((p?.facts ?? []) as any[]).find((f) => f?.key === k)?.value ?? '');
  if (p?.kind === 'payroll') return [payrollLock(String(p.date ?? ''))];
  if (p?.kind === 'bank-payment' && fact('kind') === PAYROLL_TAX_KIND)
    return [
      (b) =>
        b
          .on(
            b.find(
              doc(PayrollFiling, {
                agencyId: fact('payee'),
                periodEnd: periodEndOf(fact('period')),
              }),
              { expect: 'one' },
            ),
          )
          .unmarkPaid({
            paymentNo: p.source ?? '',
            amountMinor: Number(fact('amountMinor')) || 0,
          }),
    ];
  return [];
}
/** The books health check: what the agencies are owed, from the runs and payments, against the
 *  payroll tax liability accounts in the journal. */
export function payrollTie(months: unknown[]): {
  ok: boolean;
  caption: string;
} {
  // Only payroll runs and payroll tax payments: an opening balance or a journal entry on these
  // accounts isn't payroll the agencies are owed.
  let posts = journalPostings(months).filter(
    (p) =>
      p.kind === 'payroll' ||
      (p.kind === 'bank-payment' && p.fact('kind') === PAYROLL_TAX_KIND),
  );
  let owed = agencyOwed(posts),
    held = liabilityBalance(posts);
  let off = [...owed].filter(([id, n]) => n !== (held.get(id) ?? 0));
  let total = [...owed.values()].reduce((n, x) => n + x, 0);
  return {
    ok: off.length === 0,
    caption: off.length
      ? off
          .map(
            ([id, n]) =>
              `${id} is owed ${money(n)}; its account holds ${money(held.get(id))}`,
          )
          .join(', ')
      : `Each agency's account holds what it's owed, ${money(total)} in all`,
  };
}

interface FilingRow {
  key: string;
  card: any;
  agency: string;
  form: string;
  period: string;
  status: string;
  due: string;
  paid: string;
  open: string;
  action: string;
}

/** The desk's own post refuses a run with paychecks: the Payroll page posts it, after checking its year to date. */
export function payrollPostGuard(c: unknown) {
  if (c instanceof PayrollRun && (c.paychecks ?? []).some(Boolean))
    throw new Error(
      'Post this run from Run payroll, which checks each paycheck against the runs before it first.',
    );
}

export class PayrollPage extends Component<PayrollPageSignature> {
  @tracked schedule = 'biweekly';
  @tracked chosenDate = '';
  @tracked error = '';
  @tracked busy = false;
  @tracked busyKey = ''; // the run or row an action is working on
  @tracked stubRun: any;
  isBusy = (key: string | undefined) => !!key && this.busyKey === key;

  query = (module: string, name: string) => () =>
    ({ filter: { type: codeRef(here, module, name) } }) as never;
  all = (getQuery: () => unknown) =>
    new AllCards(this.args.context, this, getQuery, () => this.args.realms, {
      isLive: true,
    });
  setupData = this.all(this.query('../accounting/ledger-payroll', 'PaySetup'));
  tableData = this.all(this.query('../accounting/ledger-payroll', 'PayrollTaxTable'));
  runData = this.all(this.query('../accounting/ledger-cash', 'PayrollRun'));
  monthData = this.all(this.query('../accounting/ledger-journal', 'JournalMonth'));
  timeData = this.all(() => {
      let type = codeRef(here, '../accounting/ledger-time', 'TimeActivity');
      return {
        filter: {
          every: [
            { type },
            { on: type, eq: { workerKind: 'employee' } },
            {
              on: type,
              range: {
                date: { gte: this.period.start, lte: this.period.end },
              },
            },
          ],
        },
      } as never;
  });

  filingData = this.all(
    this.query('../accounting/ledger-payroll-filings', 'PayrollFiling'),
  );
  agencyData = this.all(this.query('../accounting/ledger-payroll', 'PayrollAgency'));
  paymentData = this.all(() => {
      let type = codeRef(here, '../accounting/ledger-cash', 'BankPayment');
      return {
        filter: {
          every: [{ type }, { on: type, eq: { kind: PAYROLL_TAX_KIND } }],
        },
      } as never;
  });
  get setups() {
    return instancesOf(this.setupData).sort((a, b) =>
      String(a.name ?? '').localeCompare(String(b.name ?? '')),
    );
  }
  get months() {
    return instancesOf(this.monthData);
  }
  get runs() {
    return instancesOf(this.runData);
  }
  get loading() {
    return [
      this.setupData,
      this.tableData,
      this.runData,
      this.monthData,
      this.timeData,
    ].some((r) => (r as any)?.isLoading !== false);
  }
  // A read that comes back full may have left records out, so the page says so.
  // A read that failed, or came back full and may have left records out, would draft or post a run
  // from incomplete history, so both wait until every read is whole.
  get capNotes() {
    let reads: [AllCards, string][] = [
      [this.setupData, 'pay setups'],
      [this.tableData, 'tax tables'],
      [this.runData, 'payroll runs'],
      [this.monthData, 'journal months'],
      [this.timeData, 'time activities in this period'],
    ];
    if (this.loading) return '';
    return reads
      .filter(([r]) => !r.isComplete)
      .map(([r, noun]) =>
        r.tooMany
          ? `There are too many ${noun} to read.`
          : `The ${noun} couldn't be read.`,
      )
      .join(' ');
  }
  // The runs that stand: a reversed run's paychecks no longer count toward anyone's year.
  get standing() {
    let sources = new Set(
      journalPostings(this.months, ['payroll']).map((p) => p.source),
    );
    return standingRuns(this.runs, sources);
  }
  get drafts() {
    return this.runs.filter(
      (r) => (r.status ?? 'draft') === 'draft' && (r.paychecks ?? []).length,
    );
  }

  // ── employees ──
  setupCols: DataColumn<SetupRow>[] = [
    { key: 'name', label: 'Employee' },
    { key: 'pay', label: 'Pay', align: 'end' },
    { key: 'schedule', label: 'Schedule' },
    { key: 'period', label: 'Gross a period', align: 'end' },
    { key: 'posts', label: 'Wages post to', mono: true },
    { key: 'filing', label: 'Filing status' },
  ];
  get setupRows(): SetupRow[] {
    return this.setups.map((s) => ({
      key: s.id ?? s.employeeId,
      card: s,
      name: `${s.name ?? s.employeeId}${s.active === false ? ' (inactive)' : ''}`,
      pay:
        s.payType === 'hourly'
          ? `${money(s.hourlyRateMinor)}/h`
          : `${money(s.salaryMinor)}/yr`,
      schedule: labelOf(PAY_SCHEDULES, s.schedule),
      period: money(s.periodGrossMinor?.() ?? 0),
      posts: `${s.expenseAccount ?? ''}${s.cls ? ' · ' + s.cls : ''}`,
      filing: `${labelOf(FILING_STATUSES, s.filingStatus)} · ${plural(s.allowances ?? 0, 'allowance')}`,
    }));
  }
  openSetup = (row: SetupRow) => this.args.viewCard?.(row.card, 'isolated');

  // ── running payroll ──
  setSchedule = (v: string) => (this.schedule = v || 'biweekly');
  setPayDate = (iso: string) => (this.chosenDate = iso);
  get today() {
    return new Date().toISOString().slice(0, 10);
  }
  // The first day a new entry can post: today, or the start of the first open month after it.
  get postable() {
    let open = this.months
      .filter((m) => m.status === 'open')
      .map((m) => ({
        first: String(m.firstDay ?? ''),
        last: String(m.lastDay ?? ''),
      }))
      .sort((a, b) => a.first.localeCompare(b.first));
    let t = this.today;
    if (open.some((m) => t >= m.first && t <= m.last)) return t;
    return open.find((m) => m.first > t)?.first ?? open.at(-1)?.first ?? t;
  }
  get payDate() {
    return this.chosenDate || this.postable;
  }
  get period() {
    return periodFor(this.schedule, this.payDate);
  }
  get payees() {
    return this.setups.filter(
      (s) => s.active !== false && s.schedule === this.schedule,
    );
  }
  // Each paycheck as it would be drafted now; a setup that can't be worked out says why.
  get preview(): { checks: PaycheckData[]; error: string } {
    let tables = instancesOf(this.tableData),
      acts = instancesOf(this.timeData),
      runs = this.standing;
    let checks: PaycheckData[] = [];
    try {
      for (let s of this.payees) {
        let hours =
          s.payType === 'hourly'
            ? (hoursIn(acts, s.employeeId, this.period) ??
              s.defaultHoursMilli ??
              0)
            : undefined;
        checks.push(
          calcPaycheck({
            setup: s.calcInput(),
            payDate: this.payDate,
            hoursMilli: hours,
            ytd: ytdOf(s.employeeId, this.payDate, runs),
            tables,
          }),
        );
      }
    } catch (e: any) {
      return { checks: [], error: e?.message ?? String(e) };
    }
    return { checks, error: '' };
  }
  checkCols: DataColumn<CheckRow>[] = [
    { key: 'name', label: 'Employee' },
    { key: 'hours', label: 'Hours', align: 'end' },
    { key: 'gross', label: 'Gross', align: 'end' },
    { key: 'deductions', label: 'Deductions', align: 'end' },
    { key: 'taxes', label: 'Taxes withheld', align: 'end' },
    { key: 'net', label: 'Net pay', align: 'end' },
    { key: 'employer', label: 'Employer taxes', align: 'end' },
  ];
  checkRows = (checks: any[]): CheckRow[] =>
    checks.filter(Boolean).map((p) => {
      let t = runTotals([p]);
      return {
        key: p.employeeId,
        name: p.name || p.employeeId,
        hours: p.hoursMilli ? String(p.hoursMilli / 1000) : '',
        gross: money(p.grossMinor),
        deductions: money(t.deductionsMinor),
        taxes: money(t.withholdingMinor),
        net: money(p.netMinor),
        employer: money(t.employerTaxMinor),
      };
    });
  get previewRows() {
    return this.checkRows(this.preview.checks);
  }
  get previewTotal() {
    let t = runTotals(this.preview.checks);
    return `${plural(this.preview.checks.length, 'paycheck')} · gross ${money(
      t.wages.reduce((n, w) => n + w.amountMinor, 0),
    )} · net ${money(t.netMinor)} · employer taxes ${money(t.employerTaxMinor)}`;
  }
  // Why this run can't be drafted now: a draft still waiting, or a period already paid.
  get blocker() {
    return runBlocker(
      {
        schedule: this.schedule,
        payDate: this.payDate,
        start: this.period.start,
        end: this.period.end,
        employeeIds: this.payees.map((s) => s.employeeId),
      },
      [...this.standing, ...this.drafts],
    );
  }
  get canDraft() {
    return (
      !this.busy &&
      !this.loading &&
      !this.capNotes &&
      !this.blocker &&
      !this.preview.error &&
      this.preview.checks.length > 0
    );
  }
  draftRun = async () => {
    let ledger = this.args.ledger;
    if (!ledger || !this.canDraft) return;
    this.busy = true;
    this.busyKey = 'draft';
    this.error = '';
    try {
      let checks = this.preview.checks,
        t = runTotals(checks);
      await (operations(ledger) as any).enterPayrollRun({
        docNo: `PR-${this.payDate}-${Date.now().toString(36).toUpperCase()}`,
        date: this.payDate,
        memo: `Payroll ${this.period.start} to ${this.period.end} (${this.schedule})`,
        bank: '1000',
        employerTaxAccount: EMPLOYER_TAX_ACCOUNT,
        liabilityAccount: PAYROLL_LIABILITIES.federal.account,
        schedule: this.schedule,
        periodStart: this.period.start,
        periodEnd: this.period.end,
        ...t,
        paychecks: checks,
      });
      this.args.notify(
        'Run drafted',
        'Review each paycheck, then post the run.',
      );
    } catch (e: any) {
      this.error = e?.detail ?? e?.message ?? String(e);
    } finally {
      this.busy = false;
      this.busyKey = '';
    }
  };
  // The stale check reads the pay setups and tables, so posting waits until they are in.
  get draftHint() {
    return this.loading
      ? 'Waiting for the pay setups, tax tables, time and runs to load.'
      : '';
  }
  get postHint() {
    return this.canPost || this.busy
      ? ''
      : this.capNotes
        ? 'Posting waits until every read is whole.'
        : 'Waiting for the pay setups, tax tables, time and runs to load.';
  }
  deleteTitle = (run: any) => `Delete draft run ${run.docNo}?`;
  deleteLabel = (run: any) => `delete:${run.docNo}`;
  get readsWhole() {
    return !this.loading && !this.capNotes;
  }
  get canPost() {
    return !this.busy && this.readsWhole;
  }
  deleteRun = async (run: any) => {
    this.busy = true;
    this.busyKey = `delete:${run.docNo}`;
    this.error = '';
    try {
      await (operations(run) as any).atomic((b: any) => [
        b.checkDraft(),
        b.delete(),
      ]);
      if (this.stubRun === run) this.stubRun = undefined;
      this.args.notify('Draft deleted', `${run.docNo} is gone.`);
    } catch (e: any) {
      this.error = e?.detail ?? e?.message ?? String(e);
    } finally {
      this.busy = false;
      this.busyKey = '';
    }
  };
  postRun = async (run: any) => {
    this.busy = true;
    this.busyKey = run.docNo;
    this.error = '';
    try {
      if ((run.paychecks ?? []).length && !this.readsWhole)
        throw new Error(
          this.capNotes ||
            'The pay setups, tax tables, time and runs are still loading. Try again in a moment.',
        );
      let month = String(run.date ?? '').slice(0, 7);
      if (!this.months.some((m) => m.month === month && m.status === 'open'))
        throw new Error(
          `There is no open journal month for ${month}, so the run can't post there.`,
        );
      if ((run.paychecks ?? []).length) {
        let stale = staleEmployees(
          run,
          this.setups.map((s) => s.calcInput()),
          instancesOf(this.tableData),
          this.standing.filter((r) => r !== run),
        );
        if (stale.length)
          throw new Error(
            `The paychecks for ${stale.join(', ')} no longer match their pay setup and the runs before this one. Delete this draft and run payroll again.`,
          );
      }
      let entry = journalPostingFor(
        run,
        run instanceof BankPayment ? 'BankPayment' : 'PayrollRun',
        run.id,
      );
      let steps = payrollPostSteps(run);
      let JournalMonth = codeRef(
        here,
        '../accounting/ledger-journal',
        'JournalMonth',
      );
      await (operations(run) as any).atomic((b: any) => [
        b.journal(),
        b
          .on(
            b.find(
              {
                every: [
                  { type: JournalMonth },
                  { on: JournalMonth, eq: { month, status: 'open' } },
                ],
              },
              { expect: 'one' },
            ),
          )
          .post(entry),
        ...steps.map((step) => step(b)),
      ]);
      this.args.notify(
        run instanceof BankPayment ? 'Payment posted' : 'Payroll posted',
        run instanceof BankPayment
          ? `It's in the ${month} journal and recorded on the filing it pays.`
          : `It's in the ${month} journal, with each tax owed to its agency.`,
      );
      if (this.stubRun === run) this.stubRun = undefined;
    } catch (e: any) {
      this.error = e?.detail ?? e?.message ?? String(e);
    } finally {
      this.busy = false;
      this.busyKey = '';
    }
  };

  // ── liabilities and filings ──
  filingCols: DataColumn<FilingRow>[] = [
    { key: 'agency', label: 'Agency', mono: true },
    { key: 'form', label: 'Form' },
    { key: 'period', label: 'Period', mono: true },
    { key: 'status', label: 'Status' },
    { key: 'due', label: 'Owed', align: 'end' },
    { key: 'paid', label: 'Paid', align: 'end' },
    { key: 'open', label: 'Open', align: 'end' },
    { key: 'action', label: 'Action' },
  ];
  get filings() {
    return instancesOf(this.filingData).sort(
      (a, b) =>
        String(b.periodEnd ?? '').localeCompare(a.periodEnd ?? '') ||
        String(a.agencyId ?? '').localeCompare(b.agencyId ?? ''),
    );
  }
  // An action on a filing waits until its filings, agencies and payments are all read, so a draft
  // payment that hasn't loaded can't re-offer Pay.
  get filingsRead() {
    return (
      this.filingData.isComplete &&
      this.agencyData.isComplete &&
      this.paymentData.isComplete
    );
  }
  get filingNote() {
    let reads = [this.filingData, this.agencyData, this.paymentData];
    return reads.some((r) => !r.isLoading && !r.isComplete)
      ? "The filings, agencies and tax payments couldn't all be read, so no filing action is offered. Reload to try again."
      : '';
  }
  get paymentDrafts() {
    return instancesOf(this.paymentData).filter(
      (p) => (p.status ?? 'draft') === 'draft',
    );
  }
  agencyOf = (id: string | undefined) =>
    instancesOf(this.agencyData).find((a) => a.agencyId === id);
  // Filing records the figures shown, so it waits until the period's months and runs are read.
  canFile = (f: any) =>
    f.status === 'open' &&
    String(f.periodEnd ?? '') < this.today &&
    !!getRelationshipMembershipState(f, 'journal').isLoaded &&
    !!getRelationshipMembershipState(f, 'runs').isLoaded;
  canPay = (f: any) =>
    f.status === 'filed' &&
    (f.openMinor ?? 0) > 0 &&
    !!this.agencyOf(f.agencyId)?.liabilityAccount &&
    !this.paymentDrafts.some(
      (d) => d.payee === f.agencyId && periodEndOf(d.period) === f.periodEnd,
    );
  nextPeriod = (f: any) => {
    let start = new Date(`${f.periodEnd}T00:00:00Z`);
    start.setUTCDate(start.getUTCDate() + 1);
    let months = this.agencyOf(f.agencyId)?.frequency === 'annual' ? 12 : 3;
    let end = new Date(
      Date.UTC(start.getUTCFullYear(), start.getUTCMonth() + months, 0),
    );
    return {
      start: start.toISOString().slice(0, 10),
      end: end.toISOString().slice(0, 10),
    };
  };
  canStartNext = (f: any) =>
    f.status !== 'open' &&
    !this.filings.some(
      (o) =>
        o.agencyId === f.agencyId && o.periodStart === this.nextPeriod(f).start,
    );
  get filingRows(): FilingRow[] {
    return this.filings.map((f) => ({
      key: f.id ?? `${f.agencyId}-${f.periodEnd}`,
      card: f,
      agency: f.agencyId ?? '',
      form: f.form ?? '',
      period: `${f.periodStart ?? ''} to ${f.periodEnd ?? ''}`,
      status: filingStatusLabel(f.status),
      due: money(f.dueMinor),
      paid: money(f.paidMinor),
      open: money(f.openMinor),
      action: !this.filingsRead
        ? ''
        : this.canFile(f)
        ? 'File'
        : this.canPay(f)
          ? 'Pay'
          : this.canStartNext(f)
            ? 'Start next'
            : '',
    }));
  }
  @tracked formFiling: any;
  showForm = (row: FilingRow) => (this.formFiling = row.card);
  closeForm = () => (this.formFiling = undefined);
  get formTitle() {
    return this.formFiling?.cardTitle ?? '';
  }
  get formItems() {
    return this.formFiling ? this.items(this.formFiling.facts?.() ?? []) : [];
  }
  actionLabel = (row: FilingRow) => `${row.action} ${row.form}, ${row.period}`;
  act = async (row: FilingRow) => {
    let f = row.card;
    this.busy = true;
    this.busyKey = row.key;
    this.error = '';
    try {
      if (row.action === 'File') await this.file(f);
      else if (row.action === 'Pay') await this.pay(f);
      else if (row.action === 'Start next') {
        let next = this.nextPeriod(f);
        await (operations(f) as any).openNext({
          periodStart: next.start,
          periodEnd: next.end,
        });
        this.args.notify('Period started', `${next.start} to ${next.end}.`);
      }
    } catch (e: any) {
      this.error = e?.detail ?? e?.message ?? String(e);
    } finally {
      this.busy = false;
      this.busyKey = '';
    }
  };
  file = async (f: any) => {
    let lines = ((f.lines ?? []) as any[]).filter(Boolean).map((l) => ({
      key: l.key ?? null,
      label: l.label ?? null,
      amountMinor: l.amountMinor ?? 0,
      employeeId: l.employeeId ?? null,
    }));
    await (operations(f) as any).atomic((b: any) => [
      b.file({ lines, dueMinor: f.dueMinor ?? 0, filedOn: this.today }),
      b
        .on(
          b.find(doc(PayrollAgency, { agencyId: f.agencyId }), {
            expect: 'one',
          }),
        )
        .markFiled({ periodStart: f.periodStart, periodEnd: f.periodEnd }),
    ]);
    this.args.notify(
      `${f.form} filed`,
      `Its figures are recorded, and runs dated through ${f.periodEnd} can no longer post.`,
    );
  };
  pay = async (f: any) => {
    let ledger = this.args.ledger;
    if (!ledger) throw new Error('This app is not linked to its ledger.');
    let agency = this.agencyOf(f.agencyId);
    await (operations(ledger) as any).enterBankPayment({
      docNo: `PTX-${f.agencyId}-${f.periodEnd}-${Date.now().toString(36).toUpperCase()}`,
      date: this.postable,
      memo: `${f.form} ${f.periodStart} to ${f.periodEnd}`,
      kind: PAYROLL_TAX_KIND,
      bank: '1000',
      account: agency.liabilityAccount,
      payee: f.agencyId,
      period: `${f.periodStart} to ${f.periodEnd}`,
      amountMinor: f.openMinor ?? 0,
    });
    this.args.notify(
      'Payment drafted',
      'Posting it pays the period and records the payment on it.',
    );
  };

  // ── runs and stubs ──
  runCols: DataColumn<RunRow>[] = [
    { key: 'number', label: 'Run', mono: true },
    { key: 'date', label: 'Pay date', mono: true },
    { key: 'schedule', label: 'Schedule' },
    { key: 'people', label: 'Paychecks', align: 'end' },
    { key: 'gross', label: 'Gross', align: 'end' },
    { key: 'net', label: 'Net', align: 'end' },
    { key: 'status', label: 'Status' },
  ];
  get runRows(): RunRow[] {
    let standing = new Set(this.standing);
    return this.runs
      .filter((r) => (r.paychecks ?? []).length)
      .sort((a, b) => String(b.date ?? '').localeCompare(a.date ?? ''))
      .map((r) => ({
        key: r.id ?? r.docNo,
        card: r,
        number: r.docNo ?? '',
        date: r.date ?? '',
        schedule: labelOf(PAY_SCHEDULES, r.schedule),
        people: (r.paychecks ?? []).length,
        gross: money(
          (r.wages ?? []).reduce(
            (n: number, w: any) => n + (w?.amountMinor ?? 0),
            0,
          ),
        ),
        net: money(r.netMinor),
        status:
          (r.status ?? 'draft') === 'draft'
            ? 'Draft'
            : standing.has(r)
              ? 'Posted'
              : 'Reversed',
      }));
  }
  showStubs = (row: RunRow | any) => (this.stubRun = row.card ?? row);
  closeStubs = () => (this.stubRun = undefined);
  get stubs(): { key: string; name: string; facts: Fact[] }[] {
    return ((this.stubRun?.paychecks ?? []) as any[])
      .filter(Boolean)
      .map((p) => ({
        key: p.employeeId,
        name: p.name || p.employeeId,
        facts: stubFacts(plainPaycheck(p)),
      }));
  }
  items = (facts: Fact[]) =>
    facts.map((f, i) => ({
      key: `${i}`,
      label: f.key,
      value: f.value,
      mono: f.mono,
    }));
  get stubTitle() {
    return this.stubRun ? `Paychecks · ${this.stubRun.docNo ?? ''}` : '';
  }
  paycheckCount = (run: any) =>
    plural((run.paychecks ?? []).length, 'paycheck');
  get stubIsDraft() {
    return (this.stubRun?.status ?? 'draft') === 'draft';
  }

  <template>
    <div class='payroll'>
      {{#if this.error}}<Callout
          @tone='danger'
          @title="That didn't go through"
        >{{this.error}}</Callout>{{/if}}
      {{#if this.capNotes}}<Callout
          @tone='warning'
          @title="Payroll can't be drafted or posted from this"
        >{{this.capNotes}}</Callout>{{/if}}

      <section class='block' aria-labelledby='payroll-run-h'>
        <h2 id='payroll-run-h'>Run payroll</h2>
        <div class='controls'>
          <Field class='control' @label='Pay schedule' as |controlId|><Select
              @controlId={{controlId}}
              @options={{PAY_SCHEDULES}}
              @value={{this.schedule}}
              @onChange={{this.setSchedule}}
            /></Field>
          <Field class='control' @label='Pay date' as |controlId|><Input
              @controlId={{controlId}}
              @type='date'
              @value={{this.payDate}}
              @onInput={{this.setPayDate}}
            /></Field>
          <p class='muted'>Pays for
            {{this.period.start}}
            to
            {{this.period.end}}.</p>
        </div>
        {{#if this.preview.error}}
          <Callout
            @tone='warning'
            @title="This run can't be worked out"
          >{{this.preview.error}}</Callout>
        {{else if this.previewRows.length}}
          <DataTable
            @columns={{this.checkCols}}
            @rows={{this.previewRows}}
            @label='Paychecks this run would pay'
            @itemNoun='paycheck'
            @size='s'
          />
          <div class='foot'>
            <span class='muted'>{{this.previewTotal}}</span>
            {{#if this.blocker}}<span
                class='muted'
              >{{this.blocker}}</span>{{/if}}
            {{#if this.draftHint}}<span
                class='muted'
              >{{this.draftHint}}</span>{{/if}}
            <Button
              @tone='primary'
              @appearance='accent'
              @size='s'
              @busy={{this.isBusy 'draft'}}
              @disabled={{if this.canDraft false true}}
              {{on 'click' this.draftRun}}
            >Draft run</Button>
          </div>
        {{else}}
          <EmptyState
            @size='s'
            @title='Nobody on this schedule'
            @message='Active pay setups on the chosen schedule get a paycheck in the run.'
          />
        {{/if}}
      </section>

      {{#if this.drafts.length}}
        <section class='block' aria-labelledby='payroll-drafts-h'>
          <h2 id='payroll-drafts-h'>Waiting to post</h2>
          <ul class='drafts'>
            {{#each this.drafts as |run|}}
              <li class='draft'>
                <span class='mono'>{{run.docNo}}</span>
                <span>{{run.date}}
                  ·
                  {{this.paycheckCount run}}
                  · net
                  {{money run.netMinor}}</span>
                <span class='actions'>
                  <Button
                    @tone='neutral'
                    @appearance='outlined'
                    @size='s'
                    {{on 'click' (fn this.showStubs run)}}
                  >Review paychecks</Button>
                  <AlertDialog
                    @title={{this.deleteTitle run}}
                    @description='Its paychecks are discarded. Run payroll again for the period to pay it.'
                    @confirmLabel='Delete draft'
                    @busy={{this.isBusy (this.deleteLabel run)}}
                    @onConfirm={{fn this.deleteRun run}}
                  >
                    <:trigger as |open toggle|><Button
                        @tone='danger'
                        @appearance='outlined'
                        @size='s'
                        @disabled={{this.busy}}
                        aria-expanded={{if open 'true' 'false'}}
                        {{on 'click' toggle}}
                      >Delete draft</Button></:trigger>
                  </AlertDialog>
                  <Button
                    @tone='primary'
                    @appearance='accent'
                    @size='s'
                    @busy={{this.isBusy run.docNo}}
                    @disabled={{if this.canPost false true}}
                    {{on 'click' (fn this.postRun run)}}
                  >Post run</Button>
                </span>
              </li>
            {{/each}}
          </ul>
        </section>
      {{/if}}

      <section class='block' aria-labelledby='payroll-filings-h'>
        <h2 id='payroll-filings-h'>Liabilities and filings</h2>
        {{#if this.paymentDrafts.length}}
          <ul class='drafts'>
            {{#each this.paymentDrafts as |pmt|}}
              <li class='draft'>
                <span class='mono'>{{pmt.docNo}}</span>
                <span>{{pmt.payee}}
                  ·
                  {{pmt.period}}
                  ·
                  {{money pmt.amountMinor}}</span>
                <span class='actions'><Button
                    @tone='primary'
                    @appearance='accent'
                    @size='s'
                    @busy={{this.isBusy pmt.docNo}}
                    @disabled={{this.busy}}
                    {{on 'click' (fn this.postRun pmt)}}
                  >Post payment</Button></span>
              </li>
            {{/each}}
          </ul>
        {{/if}}
        {{#if this.filingNote}}<Callout
            @tone='danger'
            @title="Couldn't read the filings"
          >{{this.filingNote}}</Callout>{{/if}}
        {{#if this.filingRows.length}}
          <DataTable
            @columns={{this.filingCols}}
            @rows={{this.filingRows}}
            @label='Payroll liabilities and filings by agency and period'
            @itemNoun='filing'
            @size='s'
          >
            <:cell as |text row col|>
              {{#if (isStatus col)}}<StatusChip
                  @value={{text}}
                  @tone={{toneFor text}}
                />{{else if (isAgency col)}}<Button
                  @tone='neutral'
                  @appearance='link'
                  @size='s'
                  {{on 'click' (fn this.showForm row)}}
                >{{text}}</Button>{{else if (isAction col)}}{{#if row.action}}<Button
                    @tone='neutral'
                    @appearance='outlined'
                    @size='s'
                    @busy={{this.isBusy row.key}}
                    @disabled={{this.busy}}
                    aria-label={{this.actionLabel row}}
                    {{on 'click' (fn this.act row)}}
                  >{{text}}</Button>{{/if}}{{else}}{{text}}{{/if}}
            </:cell>
          </DataTable>
        {{else}}
          <EmptyState
            @size='s'
            @title='No filings yet'
            @message='Each agency has a filing per period; its figures come from that period’s runs.'
          />
        {{/if}}
      </section>

      <section class='block' aria-labelledby='payroll-people-h'>
        <h2 id='payroll-people-h'>Employees</h2>
        {{#if this.setupRows.length}}
          <DataTable
            @columns={{this.setupCols}}
            @rows={{this.setupRows}}
            @label='Employees and their pay setup'
            @itemNoun='employee'
            @size='s'
          >
            <:cell as |text row col|>
              {{#if (isName col)}}<Button
                  @tone='neutral'
                  @appearance='link'
                  @size='s'
                  {{on 'click' (fn this.openSetup row)}}
                >{{text}}</Button>{{else}}{{text}}{{/if}}
            </:cell>
          </DataTable>
        {{else}}
          <EmptyState
            @size='s'
            @title='No pay setups yet'
            @message='A pay setup links an HR employee to how the books pay them.'
          />
        {{/if}}
      </section>

      <section class='block' aria-labelledby='payroll-runs-h'>
        <h2 id='payroll-runs-h'>Runs</h2>
        {{#if this.runRows.length}}
          <DataTable
            @columns={{this.runCols}}
            @rows={{this.runRows}}
            @label='Payroll runs'
            @itemNoun='run'
            @size='s'
          >
            <:cell as |text row col|>
              {{#if (isStatus col)}}<StatusChip
                  @value={{text}}
                  @tone={{toneFor text}}
                />{{else if (isNumber col)}}<Button
                  @tone='neutral'
                  @appearance='link'
                  @size='s'
                  {{on 'click' (fn this.showStubs row)}}
                >{{text}}</Button>{{else}}{{text}}{{/if}}
            </:cell>
          </DataTable>
        {{else}}
          <EmptyState
            @size='s'
            @title='No runs yet'
            @message='Runs drafted here list with their paychecks.'
          />
        {{/if}}
      </section>
    </div>

    <Drawer
      @open={{if this.formFiling true false}}
      @onClose={{this.closeForm}}
      @label={{this.formTitle}}
      @placement='end'
      {{escapeGuard (if this.formFiling true false) this.closeForm}}
    >
      <:title>{{this.formTitle}}</:title>
      <:default>
        <Descriptions
          @items={{this.formItems}}
          @columns={{1}}
          @size='s'
          @bordered={{true}}
        />
        <p class='muted'>Generated for someone to file; nothing is e-filed.</p>
      </:default>
      <:footer><Button
          @tone='neutral'
          @appearance='outlined'
          {{on 'click' this.closeForm}}
        >Close</Button></:footer>
    </Drawer>

    <Drawer
      @open={{if this.stubRun true false}}
      @onClose={{this.closeStubs}}
      @label={{this.stubTitle}}
      @placement='end'
      {{escapeGuard (if this.stubRun true false) this.closeStubs}}
    >
      <:title>{{this.stubTitle}}</:title>
      <:default>
        {{#if this.error}}<Callout
            @tone='danger'
            @title="That didn't go through"
          >{{this.error}}</Callout>{{/if}}
        {{#each this.stubs as |stub|}}
          <Descriptions
            class='stub'
            @title={{stub.name}}
            @items={{this.items stub.facts}}
            @columns={{1}}
            @size='s'
            @bordered={{true}}
          />
        {{/each}}
        {{#if this.stubIsDraft}}
          {{#if this.postHint}}<p class='muted'>{{this.postHint}}</p>{{/if}}
          <Button
            @tone='primary'
            @appearance='accent'
            @busy={{this.isBusy this.stubRun.docNo}}
            @disabled={{if this.canPost false true}}
            {{on 'click' (fn this.postRun this.stubRun)}}
          >Post run</Button>
        {{/if}}
      </:default>
      <:footer><Button
          @tone='neutral'
          @appearance='outlined'
          {{on 'click' this.closeStubs}}
        >Close</Button></:footer>
    </Drawer>

    <style scoped>
      .payroll {
        display: grid;
        gap: var(--boxel-sp-lg);
        min-width: 0;
      }
      .block {
        display: grid;
        gap: var(--boxel-sp-sm);
        min-width: 0;
      }
      h2 {
        font-size: var(--boxel-font-size-md);
        line-height: var(--boxel-line-height-md);
        font-weight: 600;
      }
      .controls {
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp);
        align-items: end;
      }
      .control {
        min-width: 12rem;
      }
      .foot {
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp-sm);
        align-items: center;
        justify-content: flex-end;
      }
      .muted {
        color: var(--muted-foreground);
      }
      .mono {
        font-family: var(--font-mono);
      }
      .drafts {
        list-style: none;
        margin: 0;
        padding: 0;
        display: grid;
        gap: var(--boxel-sp-xs);
      }
      .draft {
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp-sm);
        align-items: center;
        padding: var(--boxel-sp-xs) 0;
        border-bottom: 1px solid var(--border);
      }
      .actions {
        margin-inline-start: auto;
        display: flex;
        gap: var(--boxel-sp-xs);
      }
      .stub {
        margin-block-end: var(--boxel-sp);
      }
    </style>
  </template>
}
