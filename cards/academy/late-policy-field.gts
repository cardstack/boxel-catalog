import { Component, FieldDef, contains, field } from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import PercentageField from '@cardstack/base/percentage';
import ClockAlertIcon from '@cardstack/boxel-icons/clock-alert';

/**
 * How a course treats work handed in after the due moment.
 *
 * A policy is arithmetic the course owner decides once and every assignment
 * inherits: a per-day deduction, the most that deduction may ever reach, a
 * grace window in which nothing is deducted, and the day after which the drop
 * box closes for good. All four are stored on the Course; the penalty itself
 * is never stored — `latePenalty()` recomputes it from the submission moment
 * so a correction to the policy re-prices every late submission at once.
 */
export class LatePolicyField extends FieldDef {
  static displayName = 'Late Policy';
  static icon = ClockAlertIcon;

  @field penaltyPctPerDay = contains(PercentageField, {
    description: 'Deducted from the total for each full or partial day late.',
  });
  @field capPct = contains(PercentageField, {
    description: 'The deduction never exceeds this share of the total.',
  });
  @field graceHours = contains(NumberField, {
    description: 'Hours after the due moment in which nothing is deducted.',
  });
  @field hardCloseDays = contains(NumberField, {
    description: 'Days after due when the drop box closes; 0 = never closes.',
  });

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <span class='late-policy'>{{describeLatePolicy @model}}</span>
      <style scoped>
        .late-policy {
          font-size: var(--boxel-font-size-sm);
          color: var(--foreground, var(--boxel-dark));
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='late-policy-atom'>{{shortLatePolicy @model}}</span>
      <style scoped>
        .late-policy-atom {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
          white-space: nowrap;
        }
      </style>
    </template>
  };
}

export const DEFAULT_LATE_POLICY = {
  penaltyPctPerDay: 10,
  capPct: 50,
  graceHours: 0,
  hardCloseDays: 7,
};

export interface LatePenalty {
  /** Whole days late, rounded up; 0 when on time or inside grace. */
  daysLate: number;
  /** Percentage points to deduct from the total, already capped. */
  penaltyPct: number;
  /** True when the submission moment is past the hard close. */
  closed: boolean;
}

/**
 * The one place late arithmetic happens. Pure: no clocks, no models —
 * the caller passes the moments so a command and a template agree.
 */
export function latePenalty(
  policy: Partial<LatePolicyField> | null | undefined,
  dueAt: Date | string | null | undefined,
  submittedAt: Date | string | null | undefined,
): LatePenalty {
  let p = { ...DEFAULT_LATE_POLICY, ...(compact(policy) as any) };
  if (!dueAt || !submittedAt) {
    return { daysLate: 0, penaltyPct: 0, closed: false };
  }
  let due = new Date(dueAt).getTime();
  let sub = new Date(submittedAt).getTime();
  let lateMs = sub - due - (p.graceHours ?? 0) * 3600_000;
  if (lateMs <= 0) {
    return { daysLate: 0, penaltyPct: 0, closed: false };
  }
  let daysLate = Math.ceil(lateMs / 86_400_000);
  let penaltyPct = Math.min(
    p.capPct ?? 100,
    daysLate * (p.penaltyPctPerDay ?? 0),
  );
  let closed =
    (p.hardCloseDays ?? 0) > 0 && sub > due + p.hardCloseDays * 86_400_000;
  return { daysLate, penaltyPct, closed };
}

export function hardCloseAt(
  policy: Partial<LatePolicyField> | null | undefined,
  dueAt: Date | string | null | undefined,
): Date | undefined {
  if (!dueAt) return undefined;
  let days = policy?.hardCloseDays ?? DEFAULT_LATE_POLICY.hardCloseDays;
  if (!days || days <= 0) return undefined;
  return new Date(new Date(dueAt).getTime() + days * 86_400_000);
}

function compact(obj: any) {
  if (!obj) return {};
  let out: Record<string, unknown> = {};
  for (let k of Object.keys(DEFAULT_LATE_POLICY)) {
    if (obj[k] != null) out[k] = obj[k];
  }
  return out;
}

export function describeLatePolicy(
  policy: Partial<LatePolicyField> | null | undefined,
): string {
  let p = { ...DEFAULT_LATE_POLICY, ...(compact(policy) as any) };
  let parts = [`−${p.penaltyPctPerDay}% per day`, `capped at ${p.capPct}%`];
  if (p.graceHours) parts.push(`${p.graceHours}h grace`);
  parts.push(
    p.hardCloseDays ? `closes ${p.hardCloseDays}d after due` : 'never closes',
  );
  return parts.join(' · ');
}

export function shortLatePolicy(
  policy: Partial<LatePolicyField> | null | undefined,
): string {
  let p = { ...DEFAULT_LATE_POLICY, ...(compact(policy) as any) };
  return `−${p.penaltyPctPerDay}%/day · cap ${p.capPct}%`;
}

export default LatePolicyField;
