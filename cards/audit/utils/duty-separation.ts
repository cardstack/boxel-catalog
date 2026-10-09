// Segregation of duties, as a pure function over ids.
//
// The actor is an ARGUMENT here, never read from the session, and that is the
// design rather than a limitation. A compliance check has to reproduce months
// later from the record alone, so it tests the actor WRITTEN ON THE RECORD —
// `raisedBy`, `evaluatedBy`, an approver on the sign-off chain — not whoever
// happens to have the app open. An ambient current-user would make the same
// finding answer differently depending on who opened it.
//
// What this is not: access control. Realm write permission is the security
// boundary; these are domain rules layered on top, enforced at the commands
// that write, and the actor they judge is asserted by the caller.

export const DUTY_ACTIONS = [
  'close-finding',
  'accept-risk',
  'sign-off',
] as const;
export type DutyAction = (typeof DUTY_ACTIONS)[number];

export const DUTY_ACTION_LABELS: Record<string, string> = {
  'close-finding': 'Close a finding',
  'accept-risk': 'Accept the risk on a finding',
  'sign-off': 'Sign off a report',
};

export const DUTY_RULES: Record<string, string> = {
  'SOD-00': 'A duty check needs a named actor.',
  'SOD-01':
    'The auditor who raised a finding cannot close it or accept its risk.',
  'SOD-02': 'Whoever ran an audit cannot be its sole sign-off.',
};

export interface DutyContext {
  actorId?: string | null;
  /** Who raised the finding being closed or accepted. */
  raisedById?: string | null;
  /** Who ran the audit that produced the record. */
  ranById?: string | null;
  /** Approvers named on the sign-off chain, in order. */
  approverIds?: (string | null | undefined)[];
}

export interface DutyVerdict {
  allowed: boolean;
  /** The rule that decided it; null when nothing barred the act. */
  ruleId: string | null;
  reason: string;
}

function sameId(a?: string | null, b?: string | null): boolean {
  return Boolean(a && b && a === b);
}

function allowed(reason: string): DutyVerdict {
  return { allowed: true, ruleId: null, reason };
}

function denied(ruleId: string, reason: string): DutyVerdict {
  return { allowed: false, ruleId, reason };
}

export function isDutyAction(value?: string | null): value is DutyAction {
  return (DUTY_ACTIONS as readonly string[]).includes(value ?? '');
}

/**
 * May this actor perform this act on this record?
 *
 * An unnamed actor is refused: a duty cannot be separated from an anonymous
 * one, and a compliance app that let unattributed closures through would be
 * defeating its own purpose.
 *
 * A record with no raiser recorded is ALLOWED, with the reason saying so. No
 * conflict can be established from an absent fact, and refusing every such
 * closure would punish the user for a gap in older data rather than surface
 * it.
 */
export function checkDuty(action: DutyAction, ctx: DutyContext): DutyVerdict {
  if (!(ctx.actorId ?? '').trim()) {
    return denied(
      'SOD-00',
      'No actor was named, so no duty can be separated. Record who is acting.',
    );
  }

  if (action === 'close-finding' || action === 'accept-risk') {
    if (!(ctx.raisedById ?? '').trim()) {
      return allowed(
        'No raiser is recorded on the finding, so no conflict can be established.',
      );
    }
    if (sameId(ctx.actorId, ctx.raisedById)) {
      return denied(
        'SOD-01',
        action === 'close-finding'
          ? 'The auditor who raised this finding cannot close it. Someone else must.'
          : 'The auditor who raised this finding cannot accept its risk. Someone else must.',
      );
    }
    return allowed('The actor did not raise this finding.');
  }

  // sign-off
  let approvers = (ctx.approverIds ?? [])
    .map((id) => (id ?? '').trim())
    .filter(Boolean);
  let unique = [...new Set(approvers)];
  if (sameId(ctx.actorId, ctx.ranById) && unique.length <= 1) {
    return denied(
      'SOD-02',
      unique.length === 0
        ? 'Whoever ran the audit cannot sign it off alone — the chain names no second approver.'
        : 'Whoever ran the audit cannot be its only approver. Add a second approver to the chain.',
    );
  }
  return sameId(ctx.actorId, ctx.ranById)
    ? allowed(
        `The actor ran the audit but is one of ${unique.length} approvers, not the only one.`,
      )
    : allowed('The actor did not run this audit.');
}
