import type { TableColumn } from '../../components/table';

export const TABS = [
  // The desk: notice deadlines, awaiting signature, open deviations (Legal
  // Home block). First because it is the screen the contracts manager opens
  // in the morning.
  { key: 'home', label: 'Home' },
  { key: 'repository', label: 'Repository' },
  // One contract, clause by clause, with its ceremony — Contract Workspace +
  // Signature Block View blocks over whichever contract was picked.
  { key: 'workspace', label: 'Workspace' },
  { key: 'approvals', label: 'Approvals' },
  { key: 'obligations', label: 'Obligations' },
  { key: 'compliance', label: 'Compliance' },
  { key: 'clauses', label: 'Clauses' },
  { key: 'signatories', label: 'Signatories' },
  { key: 'renewals', label: 'Renewals' },
  { key: 'templates', label: 'Templates' },
  { key: 'requests', label: 'Requests' },
  { key: 'audit', label: 'Audit' },
];

/** Renewal urgency band, in days to the notice deadline. */
export const NOTICE_WINDOW_DAYS = 90;

/** A person's display name: stored `name` first, computed `cardTitle` second. */
export function personLabelOrUndefined(e: any): string | undefined {
  if (!e) return undefined;
  let n = typeof e.name === 'string' ? e.name.trim() : '';
  if (n) return n;
  let t = typeof e.cardTitle === 'string' ? e.cardTitle.trim() : '';
  return t || undefined;
}
export function personLabel(e: any): string {
  return personLabelOrUndefined(e) ?? 'Unnamed';
}

/**
 * Who reviews a contract that matches no rule.
 *
 * A named constant rather than an inline string so the fallback is visible in
 * one place and can become a policy card later without hunting for it.
 */
export const DEFAULT_REVIEWER = 'Legal';

/**
 * Bars are scaled against the LARGEST band, not against the total.
 *
 * Scaling to the total is the obvious choice and it is wrong here: with three
 * statuses holding one contract each, every bar would render at 33% and the
 * chart would say nothing that the three identical numbers beside it did not.
 * Scaling to the max makes the biggest band a full bar and every other band a
 * readable fraction of it, which is the comparison the reader actually wants.
 */
export function scaleBands<T extends { count: number }>(
  rows: T[],
): (T & { pct: number })[] {
  let max = Math.max(0, ...rows.map((r) => r.count));
  return rows.map((r) => ({
    ...r,
    pct: max ? Math.round((r.count / max) * 100) : 0,
  }));
}

/** `2027-07-14`, not `Wed Jul 14 2027 00:00:00 GMT+0800`. */
export function formatDay(v: unknown): string {
  if (!v) return '—';
  let d = new Date(v as any);
  if (Number.isNaN(d.getTime())) return String(v);
  // NOT toISOString(): it converts to UTC first, which renders a local date a
  // day early or late depending on the offset — the Acme term end showed
  // 2027-07-13 for a contract ending 2027-07-14. On a notice deadline that is
  // a missed obligation, not a formatting nit.
  let m = `${d.getMonth() + 1}`.padStart(2, '0');
  let day = `${d.getDate()}`.padStart(2, '0');
  return `${d.getFullYear()}-${m}-${day}`;
}

/** `out for signature` -> `Out for signature`. */
export function humanise(v: unknown): string {
  if (v === null || v === undefined || v === '') return '—';
  let t = String(v).replace(/[_-]+/g, ' ').trim();
  return t.charAt(0).toUpperCase() + t.slice(1);
}

/** A timestamp's local calendar day, or '' when there is none. */
export function formatStamp(v: unknown): string {
  return v ? formatDay(v).replace('—', '') : '';
}

export const CONTRACT_COLUMNS: TableColumn[] = [
  {
    key: 'contractNumber',
    label: 'Number',
    width: '9rem',
    value: (c: any) => c?.contractNumber,
  },
  { key: 'cardTitle', label: 'Contract', value: (c: any) => c?.cardTitle },
  {
    key: 'contractType',
    label: 'Type',
    showAbove: 720,
    value: (c: any) => humanise(c?.contractType),
  },
  { key: 'status', label: 'Status', custom: true, width: '10rem' },
  { key: 'riskGrade', label: 'Risk', custom: true, width: '8rem' },
  {
    key: 'endDate',
    label: 'Expires',
    align: 'end',
    showAbove: 640,
    value: (c: any) => formatDay(c?.endDate),
  },
  /**
   * The entry point into the workflow.
   *
   * A contract with no approval chain is not "approved" — it has never been
   * asked about. Without this the only way into the queue was to hand-edit the
   * card's JSON, which is why the Approvals tab only ever showed the one
   * contract that had a chain written into it by hand.
   */
  { key: 'submit', label: '', custom: true, width: '11rem', align: 'end' },
];

/**
 * Clause columns follow the artifact: usage and deviation counts sit ON the
 * library row, so a reviewer can scan a whole library without opening
 * anything. Agiloft's deviation-markup-as-a-column is the nearest prior art;
 * no researched product shows the usage count at all.
 */
export const CLAUSE_COLUMNS: TableColumn[] = [
  { key: 'cardTitle', label: 'Clause', value: (c: any) => c?.cardTitle },
  {
    key: 'clauseType',
    label: 'Category',
    showAbove: 640,
    value: (c: any) => humanise(c?.clauseType),
  },
  { key: 'riskLevel', label: 'Risk', custom: true, width: '7rem' },
  {
    key: 'usedIn',
    label: 'Used in',
    custom: true,
    align: 'end',
    width: '7rem',
  },
  {
    key: 'deviations',
    label: 'Deviations',
    custom: true,
    align: 'end',
    width: '7rem',
    showAbove: 640,
  },
  {
    key: 'ownerRole',
    label: 'Owned by',
    showAbove: 900,
    value: (c: any) => c?.ownerRole,
  },
];

/** The signing-authority matrix: ceiling, scope, and whether it is usable. */
export const SIGNATORY_COLUMNS: TableColumn[] = [
  { key: 'cardTitle', label: 'Signatory', value: (sg: any) => sg?.cardTitle },
  {
    key: 'signatureAuthority',
    label: 'Authority ceiling',
    custom: true,
    align: 'end',
    width: '11rem',
  },
  { key: 'mySign', label: 'May sign', custom: true, showAbove: 640 },
  {
    key: 'routed',
    label: 'Routed here',
    custom: true,
    align: 'end',
    width: '8rem',
    showAbove: 720,
  },
  { key: 'isActive', label: 'Status', custom: true, width: '8rem' },
];

export const NOTICE_COLUMNS: TableColumn[] = [
  { key: 'cardTitle', label: 'Contract', value: (c: any) => c?.cardTitle },
  {
    key: 'account',
    label: 'Counterparty',
    showAbove: 640,
    value: (c: any) => c?.account?.cardTitle,
  },
  {
    key: 'noticeBy',
    label: 'Notice by',
    align: 'end',
    width: '9rem',
    value: (c: any) => formatDay(c?.noticeBy),
  },
  {
    key: 'daysToNotice',
    label: 'Days left',
    custom: true,
    align: 'end',
    width: '8rem',
  },
  {
    key: 'endDate',
    label: 'Auto-renews',
    align: 'end',
    showAbove: 720,
    value: (c: any) => formatDay(c?.endDate),
  },
];

/**
 * Obligation columns follow the artifact.
 *
 * `contract`, `recurrence` and evidence are the three that make this a tracker
 * rather than a to-do list: which agreement it came from, whether it comes back,
 * and whether anyone can prove it was done. Only Icertis and Agiloft handle
 * recurrence and evidence at all among the six researched products.
 */
export const TEMPLATE_COLUMNS: TableColumn[] = [
  { key: 'cardTitle', label: 'Template', value: (t: any) => t?.cardTitle },
  {
    key: 'contractType',
    label: 'Type',
    showAbove: 640,
    value: (t: any) => humanise(t?.contractType),
  },
  {
    key: 'useCase',
    label: 'Use case',
    showAbove: 900,
    value: (t: any) => t?.useCase,
  },
  {
    key: 'clauses',
    label: 'Clauses',
    align: 'end',
    width: '7rem',
    value: (t: any) => (t?.standardClauses ?? []).filter(Boolean).length,
  },
  { key: 'isPublished', label: 'Status', custom: true, width: '8rem' },
];

export const REQUEST_COLUMNS: TableColumn[] = [
  { key: 'cardTitle', label: 'Request', value: (r: any) => r?.cardTitle },
  {
    key: 'contractType',
    label: 'Type',
    showAbove: 640,
    value: (r: any) => humanise(r?.contractType),
  },
  {
    key: 'requestedBy',
    label: 'Requested by',
    showAbove: 720,
    value: (r: any) => r?.requestedBy?.cardTitle,
  },
  {
    key: 'neededBy',
    label: 'Needed by',
    align: 'end',
    width: '9rem',
    value: (r: any) => formatDay(r?.neededBy),
  },
  { key: 'status', label: 'Status', custom: true, width: '9rem' },
];

export const AUDIT_COLUMNS: TableColumn[] = [
  {
    key: 'occurredAt',
    label: 'When',
    width: '11rem',
    value: (a: any) => formatDay(a?.occurredAt),
  },
  {
    key: 'doneBy',
    label: 'Who',
    showAbove: 640,
    value: (a: any) => a?.doneBy?.cardTitle,
  },
  { key: 'action', label: 'Action', custom: true, width: '13rem' },
  {
    key: 'subjectTitle',
    label: 'Subject',
    value: (a: any) => a?.subjectTitle,
  },
  {
    key: 'conditions',
    label: 'Conditions',
    showAbove: 900,
    value: (a: any) => a?.conditions,
  },
];

export const OBLIGATION_COLUMNS: TableColumn[] = [
  { key: 'cardTitle', label: 'Obligation', value: (o: any) => o?.cardTitle },
  {
    key: 'contract',
    label: 'Contract',
    showAbove: 900,
    value: (o: any) => o?.contract?.contractNumber ?? o?.contract?.cardTitle,
  },
  {
    key: 'obligationType',
    label: 'Type',
    showAbove: 720,
    value: (o: any) => humanise(o?.obligationType),
  },
  {
    key: 'recurrence',
    label: 'Recurrence',
    showAbove: 900,
    custom: true,
    width: '8rem',
  },
  { key: 'status', label: 'State', width: '9rem', custom: true },
  {
    key: 'nextDueDate',
    label: 'Due',
    align: 'end',
    width: '7rem',
    value: (o: any) => formatDay(o?.nextDueDate),
  },
  {
    key: 'owner',
    label: 'Owner',
    showAbove: 640,
    value: (o: any) => o?.owner?.name,
  },
  {
    key: 'evidence',
    label: 'Evidence',
    custom: true,
    align: 'end',
    width: '8rem',
    showAbove: 720,
  },
];

/** The step a contract is currently sitting on, or undefined if none is open. */
export function openStep(c: any): any {
  let steps = (c?.approvalChain?.steps ?? []).filter(Boolean);
  let idx = c?.approvalChain?.currentStepIndex ?? steps.length;
  return steps[idx];
}

export const APPROVAL_COLUMNS: TableColumn[] = [
  { key: 'cardTitle', label: 'Contract', value: (c: any) => c?.cardTitle },
  { key: 'step', label: 'Step', width: '9rem', custom: true },
  {
    key: 'approver',
    label: 'With',
    showAbove: 640,
    value: (c: any) => {
      let s = openStep(c);
      return s?.delegatedTo?.name ?? s?.approver?.name ?? '—';
    },
  },
  {
    key: 'waiting',
    label: 'Waiting',
    align: 'end',
    width: '6rem',
    value: (c: any) => {
      let d = openStep(c)?.waitingDays;
      return typeof d === 'number' ? `${d}d` : '—';
    },
    sortValue: (c: any) => openStep(c)?.waitingDays ?? -1,
  },
  { key: 'riskGrade', label: 'Risk', width: '8rem', custom: true },
];
