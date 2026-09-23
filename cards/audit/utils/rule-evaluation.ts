// The evaluation engine, kept apart from every card that uses it so the rule
// field, both commands and the future Audit command share ONE definition of
// what "pass" means. A second implementation is how a report and a badge end
// up disagreeing about the same control.
//
// Nothing here names a domain concept. A rule points at a field by path and
// says how to test it; that is the whole contract, and it is what lets the
// same engine judge a vendor, a contract, a site or a Spec card.

export const RULE_KINDS = [
  'presence',
  'threshold',
  'expiry',
  'predicate',
] as const;
export type RuleKind = (typeof RULE_KINDS)[number];

export const RULE_KIND_LABELS: Record<string, string> = {
  presence: 'Presence',
  threshold: 'Threshold',
  expiry: 'Expiry',
  predicate: 'Predicate',
};

export const RULE_KIND_HINTS: Record<string, string> = {
  presence: 'The field must hold a value.',
  threshold: 'A number must sit within min/max.',
  expiry: 'A date must be recent enough, or not yet past.',
  predicate: 'A value must equal one of the allowed values.',
};

export type RuleStatus =
  | 'pass'
  | 'fail'
  | 'partial'
  | 'not-applicable'
  | 'unproven'
  | 'pending';

export interface RuleLike {
  ruleId?: string | null;
  statement?: string | null;
  kind?: string | null;
  fieldPath?: string | null;
  parameters?: string | null;
  evidenceRequired?: boolean | null;
}

export interface RuleOutcome {
  status: RuleStatus;
  /** What the engine actually saw, rendered for a human. */
  observed: string;
  /** Why the verdict is what it is, in one sentence. */
  reason: string;
}

export function parseParameters(raw?: string | null): Record<string, any> {
  let text = (raw ?? '').trim();
  if (!text) {
    return {};
  }
  try {
    let parsed = JSON.parse(text);
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed)
      ? parsed
      : {};
  } catch {
    return {};
  }
}

export function parametersAreValid(raw?: string | null): boolean {
  let text = (raw ?? '').trim();
  if (!text) {
    return true;
  }
  try {
    let parsed = JSON.parse(text);
    return Boolean(parsed) && typeof parsed === 'object' && !Array.isArray(parsed);
  } catch {
    return false;
  }
}

/**
 * Read a dotted path off any card, defensively.
 *
 * A linked slot reads `undefined` while it loads and forever if it is broken,
 * so a missing value is never treated as a failure here — the caller maps it
 * to `not-applicable`. Guessing "absent means non-compliant" would fail every
 * subject whose links had not finished loading.
 */
export function readPath(subject: unknown, path?: string | null): unknown {
  let parts = (path ?? '')
    .split('.')
    .map((p) => p.trim())
    .filter(Boolean);
  if (!parts.length) {
    return undefined;
  }
  let current: any = subject;
  for (let part of parts) {
    if (current == null) {
      return undefined;
    }
    current = current[part];
  }
  return current;
}

function isEmpty(value: unknown): boolean {
  if (value == null) {
    return true;
  }
  if (typeof value === 'string') {
    return value.trim() === '';
  }
  if (Array.isArray(value)) {
    return value.filter((v) => v != null).length === 0;
  }
  return false;
}

export function describeValue(value: unknown): string {
  if (value == null) {
    return '—';
  }
  if (value instanceof Date) {
    return value.toISOString().slice(0, 10);
  }
  if (Array.isArray(value)) {
    return `${value.filter((v) => v != null).length} item(s)`;
  }
  if (typeof value === 'object') {
    let title = (value as any).cardTitle ?? (value as any).title;
    return typeof title === 'string' && title ? title : 'present';
  }
  return String(value);
}

function toDate(value: unknown): Date | undefined {
  if (value instanceof Date) {
    return isNaN(value.getTime()) ? undefined : value;
  }
  if (typeof value === 'string' && value.trim()) {
    let d = new Date(value);
    return isNaN(d.getTime()) ? undefined : d;
  }
  return undefined;
}

function daysBetween(a: Date, b: Date): number {
  return Math.floor((a.getTime() - b.getTime()) / 86400000);
}

/**
 * Evaluate one rule against one subject.
 *
 * `hasEvidence` is the caller's business: this engine cannot see whether a
 * proof was attached, and a rule marked `evidenceRequired` that would
 * otherwise pass returns `unproven` instead. That distinction is the whole
 * reason the status vocabulary has six values and not two.
 */
export function evaluateRule(
  rule: RuleLike,
  subject: unknown,
  opts?: { hasEvidence?: boolean; now?: Date },
): RuleOutcome {
  let now = opts?.now ?? new Date();
  let kind = (rule.kind ?? '') as RuleKind;
  let params = parseParameters(rule.parameters);
  let raw = readPath(subject, rule.fieldPath);
  let observed = describeValue(raw);

  if (!rule.fieldPath) {
    return {
      status: 'pending',
      observed: '—',
      reason: 'The rule names no field to test.',
    };
  }
  if (!parametersAreValid(rule.parameters)) {
    return {
      status: 'pending',
      observed,
      reason: 'The rule’s parameters are not a JSON object.',
    };
  }

  let verdict = ((): RuleOutcome => {
    switch (kind) {
      case 'presence': {
        return isEmpty(raw)
          ? { status: 'fail', observed, reason: `${rule.fieldPath} is empty.` }
          : {
              status: 'pass',
              observed,
              reason: `${rule.fieldPath} holds a value.`,
            };
      }
      case 'threshold': {
        let n = typeof raw === 'number' ? raw : Number(raw);
        if (raw == null || Number.isNaN(n)) {
          return {
            status: 'not-applicable',
            observed,
            reason: `${rule.fieldPath} holds no number to compare.`,
          };
        }
        let { min, max } = params as { min?: number; max?: number };
        let tooLow = typeof min === 'number' && n < min;
        let tooHigh = typeof max === 'number' && n > max;
        if (tooLow || tooHigh) {
          let bound = tooLow ? `below ${min}` : `above ${max}`;
          return { status: 'fail', observed, reason: `${n} is ${bound}.` };
        }
        return { status: 'pass', observed, reason: `${n} is within bounds.` };
      }
      case 'expiry': {
        let d = toDate(raw);
        if (!d) {
          return {
            status: 'not-applicable',
            observed,
            reason: `${rule.fieldPath} holds no date.`,
          };
        }
        let { maxAgeDays, mustBeFuture } = params as {
          maxAgeDays?: number;
          mustBeFuture?: boolean;
        };
        if (mustBeFuture) {
          return d.getTime() >= now.getTime()
            ? { status: 'pass', observed, reason: 'Not yet expired.' }
            : {
                status: 'fail',
                observed,
                reason: `Expired ${daysBetween(now, d)} day(s) ago.`,
              };
        }
        if (typeof maxAgeDays === 'number') {
          let age = daysBetween(now, d);
          return age <= maxAgeDays
            ? {
                status: 'pass',
                observed,
                reason: `${age} day(s) old, within ${maxAgeDays}.`,
              }
            : {
                status: 'fail',
                observed,
                reason: `${age} day(s) old, over ${maxAgeDays}.`,
              };
        }
        return {
          status: 'pending',
          observed,
          reason: 'An expiry rule needs maxAgeDays or mustBeFuture.',
        };
      }
      case 'predicate': {
        if (isEmpty(raw)) {
          return {
            status: 'not-applicable',
            observed,
            reason: `${rule.fieldPath} is empty.`,
          };
        }
        let { equals, oneOf } = params as { equals?: unknown; oneOf?: unknown[] };
        let value = typeof raw === 'object' ? describeValue(raw) : raw;
        if (Array.isArray(oneOf)) {
          return oneOf.some((o) => String(o) === String(value))
            ? { status: 'pass', observed, reason: `${observed} is allowed.` }
            : {
                status: 'fail',
                observed,
                reason: `${observed} is not one of ${oneOf.join(', ')}.`,
              };
        }
        if (equals !== undefined) {
          return String(equals) === String(value)
            ? { status: 'pass', observed, reason: `${observed} matches.` }
            : {
                status: 'fail',
                observed,
                reason: `${observed} is not ${String(equals)}.`,
              };
        }
        return {
          status: 'pending',
          observed,
          reason: 'A predicate rule needs equals or oneOf.',
        };
      }
      default:
        return {
          status: 'pending',
          observed,
          reason: `Unknown rule kind “${rule.kind ?? ''}”.`,
        };
    }
  })();

  // A pass on paper with nothing to show for it is not a pass.
  if (verdict.status === 'pass' && rule.evidenceRequired && !opts?.hasEvidence) {
    return {
      status: 'unproven',
      observed: verdict.observed,
      reason: `${verdict.reason} No evidence attached.`,
    };
  }
  return verdict;
}

export interface RollupCounts {
  pass: number;
  fail: number;
  partial: number;
  notApplicable: number;
  unproven: number;
  pending: number;
}

export function emptyCounts(): RollupCounts {
  return {
    pass: 0,
    fail: 0,
    partial: 0,
    notApplicable: 0,
    unproven: 0,
    pending: 0,
  };
}

export function tally(outcomes: RuleOutcome[]): RollupCounts {
  let c = emptyCounts();
  for (let o of outcomes) {
    if (o.status === 'not-applicable') {
      c.notApplicable += 1;
    } else {
      (c as any)[o.status] += 1;
    }
  }
  return c;
}

/**
 * One verdict for a whole subject. Any failure makes it non-compliant; a
 * clean run with something unproven or pending is `partial`, never `pass` —
 * the roll-up must never be more confident than its parts.
 */
export function rollup(counts: RollupCounts): RuleStatus {
  if (counts.fail > 0) {
    return 'fail';
  }
  if (counts.partial > 0 || counts.unproven > 0 || counts.pending > 0) {
    return 'partial';
  }
  if (counts.pass > 0) {
    return 'pass';
  }
  return 'not-applicable';
}

/** Rules that reached a conclusive verdict, over rules that applied. */
export function coverage(counts: RollupCounts): number {
  let applicable =
    counts.pass + counts.fail + counts.partial + counts.unproven + counts.pending;
  if (!applicable) {
    return 0;
  }
  return Math.round(((counts.pass + counts.fail + counts.partial) / applicable) * 100);
}
