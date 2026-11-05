// The closure gate, in one place: the field computes it to report a gap, the
// close command refuses on it. Two implementations is how a card comes to
// claim it is validly closed while the command that closed it disagreed.
//
// Pure, and the resolution vocabulary is injected rather than imported — a
// util that reached into a card module would drag the card API into every
// consumer of this file, which is the inversion the vocabulary
// modules exist to avoid.

export interface ClosureContext {
  code?: string | null;
  /** A corrective action is linked. */
  hasCorrectiveAction?: boolean;
  /** That corrective action is in its terminal state. */
  correctiveActionDone?: boolean;
  /** The decision on the risk acceptance, when one was sought. */
  acceptanceDecision?: string | null;
  /** Who closed it. A closure with no name is not a record. */
  closedById?: string | null;
}

/**
 * What still stands between this finding and an honest closure, or null when
 * nothing does.
 *
 * Two codes carry an obligation of their own: `remediated` claims something
 * was fixed, so the corrective action has to be done rather than merely
 * linked; `risk-accepted` claims somebody chose to live with it, so there has
 * to be an approval saying so. Every other code is a statement about the
 * finding itself and needs nothing further.
 */
export function closureGap(
  ctx: ClosureContext,
  knownCodes?: readonly string[],
): string | null {
  let code = (ctx.code ?? '').trim();
  if (!code) {
    return 'A resolution code is required — "closed" alone does not say whether anything was fixed.';
  }
  if (knownCodes && !knownCodes.includes(code)) {
    return `"${code}" is not a resolution code. Use one of: ${knownCodes.join(', ')}.`;
  }
  if (!(ctx.closedById ?? '').trim()) {
    return 'Record who closed it — an unattributed closure is not a record.';
  }
  if (code === 'remediated') {
    if (!ctx.hasCorrectiveAction) {
      return 'Remediated needs the corrective action it was fixed by.';
    }
    if (!ctx.correctiveActionDone) {
      return 'The corrective action is not done yet, so nothing has been remediated.';
    }
  }
  if (code === 'risk-accepted') {
    let decision = (ctx.acceptanceDecision ?? '').trim();
    if (!decision || decision === 'pending') {
      return 'Risk accepted needs an approval on record. Route it for a decision first.';
    }
    if (decision !== 'approved') {
      return `The risk acceptance was ${decision}, so the finding cannot close as accepted.`;
    }
  }
  return null;
}
