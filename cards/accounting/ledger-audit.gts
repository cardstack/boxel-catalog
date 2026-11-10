// The audit log: who did what to the books, and when, read from what the books already record. Every
// journal posting carries who posted it and when; documents carry who entered and posted them; voids,
// closes, reconciliations and the year's sign-off carry who did them. Nothing is written to keep it.
import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { identifyCard } from '@cardstack/runtime-common';
import type { CardContext } from '@cardstack/base/card-api';
import { Input } from '@cardstack/pretui/components/input';
import { Field } from '@cardstack/pretui/components/field';
import { Callout } from '@cardstack/pretui/components/callout';
import { Skeleton } from '@cardstack/pretui/components/skeleton';
import { DataTable } from '@cardstack/pretui/components/data-table';
import { money } from './record-kit';
import { JournalMonth, KIND_LABEL, seqText } from './ledger-journal';
import { LedgerDocument } from './ledger-document';
import { Bill } from './ledger-cards';
import { BillPayment } from './ledger-payments';
import { OpeningBalances } from './ledger-opening';
import { MonthClose, BankReconciliation } from './ledger-close';
import { YearClose } from './ledger-year';
import { instancesOf, loadingOf, isCapped } from './ledger-report-custom';
import { toHome } from './ledger-document';

export type AuditKind =
  | 'posted'
  | 'reversal'
  | 'void'
  | 'entered'
  | 'closed'
  | 'sealed'
  | 'reconciled'
  | 'signed-off';
export const AUDIT_KINDS: { value: AuditKind; label: string }[] = [
  { value: 'posted', label: 'Posted' },
  { value: 'reversal', label: 'Reversal' },
  { value: 'void', label: 'Void' },
  { value: 'entered', label: 'Entered' },
  { value: 'closed', label: 'Month closed' },
  { value: 'sealed', label: 'Month sealed' },
  { value: 'reconciled', label: 'Reconciled' },
  { value: 'signed-off', label: 'Year signed off' },
];
const KIND_NAME = new Map(AUDIT_KINDS.map((k) => [k.value, k.label]));

export interface AuditEvent {
  at: string; // when it was recorded, where the books stamp it: yyyy-mm-dd hh:mm:ss
  date: string; // the books' date it concerns
  who: string;
  kind: AuditKind;
  doc: string;
  amountMinor?: number;
  detail: string;
}
/** What the log reads. Each list holds the cards as the desk loads them. */
export interface AuditSources {
  journal?: any[];
  documents?: any[];
  closes?: any[];
  reconciliations?: any[];
  years?: any[];
}

const monthEnd = (ym: string) => {
  let [y, m] = (ym ?? '').split('-').map(Number);
  return y && m ? new Date(Date.UTC(y, m, 0)).toISOString().slice(0, 10) : '';
};
const debits = (lines: any[] | undefined) =>
  (lines ?? []).reduce((n, l) => n + (l?.debitMinor ?? 0), 0);

/** Every recorded action in the books, newest first. */
export function auditEvents(src: AuditSources): AuditEvent[] {
  let out: AuditEvent[] = [];
  for (let m of (src.journal ?? []).filter(Boolean)) {
    let posts = (m.postings ?? []).filter(Boolean);
    for (let p of posts) {
      let kind: AuditKind =
        p.kind === 'reversal'
          ? 'reversal'
          : p.kind === 'void'
            ? 'void'
            : 'posted';
      let reviewed = [
        p.preparer ? `prepared by ${p.preparer}` : '',
        p.reviewer ? `reviewed by ${p.reviewer}` : '',
      ]
        .filter(Boolean)
        .join(', ');
      out.push({
        at: p.postedAt ?? '',
        date: p.date ?? '',
        who: p.postedBy ?? '',
        kind,
        doc: p.source || seqText(m.month, p.seq),
        amountMinor: debits(p.lines),
        detail: [
          kind === 'reversal'
            ? `Reverses ${seqText(m.month, p.reverses)}`
            : (KIND_LABEL[p.kind] ?? p.kind),
          `journal ${seqText(m.month, p.seq)}`,
          reviewed,
        ]
          .filter(Boolean)
          .join(' · '),
      });
    }
    if (m.closedBy)
      out.push({
        at: '',
        date: m.lastDay || monthEnd(m.month),
        who: m.closedBy,
        kind: 'closed',
        doc: `Journal ${m.month}`,
        detail: 'Journal month closed: nothing more posts to it',
      });
    if (m.sealedBy)
      out.push({
        at: '',
        date: m.lastDay || monthEnd(m.month),
        who: m.sealedBy,
        kind: 'sealed',
        doc: `Journal ${m.month}`,
        detail: `Sealed with ${m.sealCount ?? 0} postings`,
      });
  }
  // A void the journal records is logged from the journal, with its time.
  let journalVoids = new Set(
    (src.journal ?? [])
      .filter(Boolean)
      .flatMap((m) => (m.postings ?? []).filter(Boolean))
      .filter((p) => p.kind === 'void')
      .map((p) => p.source),
  );
  for (let d of (src.documents ?? []).filter(Boolean)) {
    let doc = d.docNo ?? d.billNo ?? d.paymentNo ?? '';
    let label = (d.constructor as { displayName?: string })?.displayName ?? '';
    let amountMinor =
      d.totalMinor == null ? undefined : toHome(d.totalMinor, d.rateMicros);
    if (d.enteredBy)
      out.push({
        at: '',
        date: d.date ?? '',
        who: d.enteredBy,
        kind: 'entered',
        doc,
        amountMinor,
        detail: `${label} entered as a draft`,
      });
    // A journaled document's posting is in the journal, with its time.
    if (d.postedBy && d.status === 'posted')
      out.push({
        at: '',
        date: d.date ?? '',
        who: d.postedBy,
        kind: 'posted',
        doc,
        amountMinor,
        detail: `${label} posted`,
      });
    if (d.voidDate && d.voidedBy && !journalVoids.has(doc))
      out.push({
        at: '',
        date: d.voidDate,
        who: d.voidedBy,
        kind: 'void',
        doc,
        amountMinor,
        detail: [`${label} voided`, d.voidReason].filter(Boolean).join(' · '),
      });
  }
  for (let c of (src.closes ?? []).filter(Boolean))
    if (c.closedBy)
      out.push({
        at: '',
        date: monthEnd(c.month),
        who: c.closedBy,
        kind: 'closed',
        doc: `Month close ${c.month}`,
        amountMinor: c.debitMinor ?? undefined,
        detail: 'Month closed with its totals stored',
      });
  for (let r of (src.reconciliations ?? []).filter(Boolean))
    if (r.reconciledBy)
      out.push({
        at: '',
        date: r.statementDate ?? '',
        who: r.reconciledBy,
        kind: 'reconciled',
        doc: `Reconciliation ${r.account ?? ''} ${r.statementDate ?? ''}`.trim(),
        amountMinor: r.endingBalanceMinor ?? undefined,
        detail: 'Reconciliation finished against the statement',
      });
  for (let y of (src.years ?? []).filter(Boolean))
    if (y.signedOffBy)
      out.push({
        at: '',
        date: monthEnd(y.toMonth),
        who: y.signedOffBy,
        kind: 'signed-off',
        doc: `Year ${y.year ?? ''}`.trim(),
        detail: 'Year-end close signed off',
      });
  // Newest first: by when it was recorded where the books stamp a time, else by its date.
  let key = (e: AuditEvent) => e.at || e.date;
  return out.sort(
    (a, b) => key(b).localeCompare(key(a)) || a.doc.localeCompare(b.doc),
  );
}

/** The events a user, a kind and a period keep. */
export function filterAudit(
  events: AuditEvent[],
  f: { who?: string; kind?: string; from?: string; to?: string },
) {
  return events.filter((e) => {
    let day = (e.at || e.date).slice(0, 10);
    return (
      (!f.who || e.who === f.who) &&
      (!f.kind || e.kind === f.kind) &&
      (!f.from || day >= f.from) &&
      (!f.to || day <= f.to)
    );
  });
}

/** The kinds the books record no time for, which the log places by their date. */
export const UNTIMED =
  "entered and posted documents (by the document's date), voids of documents posted as cards (by the void date), month closes and seals (by the month's last day), reconciliations (by the statement date) and year-end sign-offs (by the year's last day)";

/** What the books don't record, so the log can't show it. */
export const NOT_RECORDED = [
  'An edit to a draft before it posts: a draft keeps who entered it, not each change.',
  'A card deleted: nothing of it stays in the books.',
  'A reconciliation reopened: reopening clears who finished it.',
  "A settings change: the books' settings keep no history of who changed them.",
  'The time a document was entered, or posted as a card: only who. Postings in the journal carry their time.',
];

type Row = AuditEvent & { key: string; amount: string; kindLabel: string };

interface AuditSignature {
  Args: { context?: CardContext; realms: string[] };
}
export class AuditLog extends GlimmerComponent<AuditSignature> {
  @tracked from = '';
  @tracked to = '';
  // Each source within the period when one is set, newest first, so a full page drops the oldest.
  query = (type: unknown, size: number, field?: 'date' | 'month') => {
    let ref = identifyCard(type as never),
      from = field === 'month' ? this.from.slice(0, 7) : this.from,
      to = field === 'month' ? this.to.slice(0, 7) : this.to,
      range = {
        ...(from ? { gte: from } : {}),
        ...(to ? { lte: to } : {}),
      };
    return {
      filter: {
        every: [
          { type: ref },
          ...(field && (from || to)
            ? [{ on: ref, range: { [field]: range } }]
            : []),
        ],
      },
      ...(field ? { sort: [{ by: field, on: ref, direction: 'desc' }] } : {}),
      page: { size },
    } as never;
  };
  load = (type: unknown, size: number, field?: 'date' | 'month') =>
    this.args.context?.getCards(
      this,
      () => this.query(type, size, field),
      () => this.args.realms,
      { isLive: true },
    );
  journalData = this.load(JournalMonth, 240, 'month');
  docData = this.load(LedgerDocument, 1000, 'date');
  billData = this.load(Bill, 1000, 'date');
  billPaymentData = this.load(BillPayment, 1000, 'date');
  openingData = this.load(OpeningBalances, 10);
  closeData = this.load(MonthClose, 240, 'month');
  recData = this.load(BankReconciliation, 500);
  yearData = this.load(YearClose, 50);
  get sources(): [unknown, number, string][] {
    return [
      [this.journalData, 240, 'journal months'],
      [this.docData, 1000, 'documents'],
      [this.billData, 1000, 'bills'],
      [this.billPaymentData, 1000, 'bill payments'],
      [this.openingData, 10, 'opening balances'],
      [this.closeData, 240, 'month closes'],
      [this.recData, 500, 'reconciliations'],
      [this.yearData, 50, 'year-end closes'],
    ];
  }
  get loading() {
    return this.sources.some(([r]) => loadingOf(r));
  }
  get capNote() {
    let full = this.sources.filter(([r, size]) => isCapped(r, size));
    return full.length
      ? `The log read only the newest ${full.map(([, size, noun]) => `${size} ${noun}`).join(' and ')}, so older events are missing. Set a From and To date to read a shorter period.`
      : '';
  }
  untimed = UNTIMED;
  get events(): AuditEvent[] {
    return auditEvents({
      journal: instancesOf(this.journalData),
      documents: [
        ...instancesOf(this.docData),
        ...instancesOf(this.billData),
        ...instancesOf(this.billPaymentData),
        ...instancesOf(this.openingData),
      ],
      closes: instancesOf(this.closeData),
      reconciliations: instancesOf(this.recData),
      years: instancesOf(this.yearData),
    });
  }
  get rows(): Row[] {
    return filterAudit(this.events, { from: this.from, to: this.to }).map(
      (e, i) => ({
        ...e,
        key: `${i}-${e.kind}-${e.doc}`,
        amount: e.amountMinor === undefined ? '' : money(e.amountMinor),
        kindLabel: KIND_NAME.get(e.kind) ?? e.kind,
      }),
    );
  }
  get columns() {
    let who = [...new Set(this.events.map((e) => e.who))].sort();
    return [
      { key: 'at', label: 'When recorded', mono: true, width: '11rem' },
      { key: 'date', label: 'Date', mono: true, width: '7.5rem' },
      {
        key: 'who',
        label: 'Who',
        mono: true,
        filter: {
          kind: 'options' as const,
          options: who.map((w) => ({ value: w, label: w })),
          match: (r: Row, v: unknown) =>
            Array.isArray(v)
              ? !v.length || v.includes(r.who)
              : !v || r.who === v,
        },
      },
      {
        key: 'kindLabel',
        label: 'What',
        filter: {
          kind: 'options' as const,
          options: AUDIT_KINDS.map((k) => ({ value: k.label, label: k.label })),
        },
      },
      { key: 'doc', label: 'Document', mono: true },
      { key: 'amount', label: 'Amount', mono: true, align: 'end' as const },
      { key: 'detail', label: 'Detail' },
    ];
  }
  rowKey = (r: Row) => r.key;
  rowLabel = (r: Row) => `${r.kindLabel} ${r.doc}`;
  notRecorded = NOT_RECORDED;
  setFrom = (v: string) => (this.from = v);
  setTo = (v: string) => (this.to = v);
  <template>
    <section class='audit' data-audit-log>
      <div class='period'>
        <Field @label='From'>
          <:default as |id|><Input
              @controlId={{id}}
              @type='date'
              @value={{this.from}}
              @onInput={{this.setFrom}}
            /></:default>
        </Field>
        <Field @label='To'>
          <:default as |id|><Input
              @controlId={{id}}
              @type='date'
              @value={{this.to}}
              @onInput={{this.setTo}}
            /></:default>
        </Field>
      </div>
      {{#if this.loading}}
        <Skeleton @height='8rem' />
      {{else}}
        <DataTable
          @columns={{this.columns}}
          @rows={{this.rows}}
          @key={{this.rowKey}}
          @rowLabel={{this.rowLabel}}
          @label='Audit log'
          @itemNoun='events'
          @size='s'
          @pageSize={{100}}
          @sortable={{false}}
          @emptyTitle='Nothing recorded in this period'
          @emptyMessage='Postings, voids, closes and sign-offs in the period list here, newest first.'
        />
      {{/if}}
      {{#if this.capNote}}<Callout
          @tone='warning'
          @title='Incomplete'
          data-report-capped
        >{{this.capNote}}</Callout>{{/if}}
      <Callout @tone='info' @title='When each kind was recorded'>
        Postings, reversals and voids in the journal carry the time they were
        posted, and the log orders and filters them by it. These carry no
        recorded time, so they're placed by their date instead:
        {{this.untimed}}.
      </Callout>
      <Callout @tone='info' @title='Not in the log'>
        <ul class='not-recorded'>
          {{#each this.notRecorded as |n|}}<li>{{n}}</li>{{/each}}
        </ul>
      </Callout>
    </section>
    <style scoped>
      .audit {
        display: grid;
        gap: var(--boxel-sp-sm);
        min-width: 0;
      }
      .period {
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp-sm);
      }
      .not-recorded {
        margin: 0;
        padding-left: var(--boxel-sp-lg);
        display: grid;
        gap: var(--boxel-sp-5xs);
      }
    </style>
  </template>
}
