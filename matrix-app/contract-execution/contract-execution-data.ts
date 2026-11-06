import type { Tone } from '../shared/compact-format';

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

/**
 * The index of the step a contract's chain is waiting on, or -1 when none is
 * open. It reads the steps' decisions, like the chain's computed
 * `currentStepIndex`, because a live-query row does not always carry computed
 * fields. A step with no decision yet counts as pending.
 */
export function openStepIndex(c: any): number {
  let steps = (c?.approvalChain?.steps ?? []).filter(Boolean);
  return steps.findIndex(
    (st: any) => (st?.decision ?? 'pending') === 'pending',
  );
}

/** The step a contract is currently sitting on, or undefined if none is open. */
export function openStep(c: any): any {
  let idx = openStepIndex(c);
  return idx < 0
    ? undefined
    : (c?.approvalChain?.steps ?? []).filter(Boolean)[idx];
}

/** Days left on a notice: red inside a month, amber inside the window. */
export function noticeTone(days?: number | null): Tone {
  if (typeof days !== 'number') return 'neutral';
  return days <= 30
    ? 'danger'
    : days <= NOTICE_WINDOW_DAYS
      ? 'warning'
      : 'neutral';
}

/** Initials for an avatar mark. */
export function initials(name?: string | null): string {
  return (name ?? '')
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((w) => w[0]!.toUpperCase())
    .join('');
}
