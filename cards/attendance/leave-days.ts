// Leave days and balances, computed live from the leave requests a person can
// read. A balance is allowed minus approved days, never stored.

export interface LeaveLike {
  userId?: string | null;
  ptoType?: string | null;
  startDate?: Date | string | null;
  endDate?: Date | string | null;
  state?: string | null;
}

export interface AllowancesLike {
  vacation?: number | null;
  sick?: number | null;
  personal?: number | null;
}

export interface LeaveBalance {
  type: string;
  label: string;
  allowed: number;
  used: number;
  remaining: number;
}

// Sick and personal days are declared: approved when filed, no approver.
export const DECLARED_TYPES = ['sick', 'personal'];

export const LEAVE_TYPES = [
  { value: 'vacation', label: 'Vacation' },
  { value: 'sick', label: 'Sick' },
  { value: 'personal', label: 'Personal' },
  { value: 'parental', label: 'Parental' },
  { value: 'unpaid', label: 'Unpaid' },
];

export const BALANCE_TYPES = ['vacation', 'sick', 'personal'];

export const LEAVE_STATE_LABEL: Record<string, string> = {
  pending: 'Pending',
  approved: 'Approved',
  declined: 'Declined',
};

// A date field arrives as a Date at local midnight or as "2026-11-23".
export function dayKeyOf(value: Date | string | null | undefined): string {
  if (!value) {
    return '';
  }
  if (typeof value === 'string') {
    return /^\d{4}-\d{2}-\d{2}/.test(value) ? value.slice(0, 10) : '';
  }
  if (Number.isNaN(value.getTime())) {
    return '';
  }
  let m = String(value.getMonth() + 1).padStart(2, '0');
  let d = String(value.getDate()).padStart(2, '0');
  return `${value.getFullYear()}-${m}-${d}`;
}

function dayNumber(key: string): number {
  let [y, m, d] = key.split('-').map(Number);
  return Date.UTC(y, m - 1, d) / 86400000;
}

// Inclusive calendar days; 0 when a date is missing or the range is inverted.
export function leaveDays(leave: LeaveLike): number {
  let start = dayKeyOf(leave.startDate);
  let end = dayKeyOf(leave.endDate);
  if (!start || !end) {
    return 0;
  }
  return Math.max(0, dayNumber(end) - dayNumber(start) + 1);
}

export function coversDay(leave: LeaveLike, day: string): boolean {
  let start = dayKeyOf(leave.startDate);
  let end = dayKeyOf(leave.endDate);
  return Boolean(start && end && start <= day && day <= end);
}

// Leave counts toward a year by the day it starts. A year with no bounds
// counts everything.
export function leaveBalances(
  allowances: AllowancesLike | null | undefined,
  leave: LeaveLike[],
  yearStart?: Date | string | null,
  yearEnd?: Date | string | null,
): LeaveBalance[] {
  let from = dayKeyOf(yearStart);
  let to = dayKeyOf(yearEnd);
  return BALANCE_TYPES.map((type) => {
    let used = leave
      .filter((l) => {
        let start = dayKeyOf(l.startDate);
        return (
          l.ptoType === type &&
          l.state === 'approved' &&
          (!from || start >= from) &&
          (!to || start <= to)
        );
      })
      .reduce((sum, l) => sum + leaveDays(l), 0);
    let allowed =
      (allowances?.[type as keyof AllowancesLike] as number | undefined) ?? 0;
    return {
      type,
      label: LEAVE_TYPES.find((t) => t.value === type)?.label ?? type,
      allowed,
      used,
      remaining: allowed - used,
    };
  });
}
