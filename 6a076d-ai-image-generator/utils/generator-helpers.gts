// 1-based version label for a history entry, used as a template helper.
export function versionLabel(index: number): number {
  return index + 1;
}

// Rewrite raw command/API failures into copy that owns the failure and gives
// the person one clear next step.
export function friendlyError(raw: string | null | undefined): string {
  let msg = raw ?? '';
  if (/credit|payment|402/i.test(msg)) {
    return "You're out of AI credits — top up to keep creating.";
  }
  if (
    /\b404\b|no endpoints|not a valid model|no allowed providers/i.test(msg)
  ) {
    return "That model isn't available right now — switch to Nano Banana and try again.";
  }
  if (/forbidden|permission|403/i.test(msg)) {
    return "You don't have permission to save images here — open this generator in a workspace you can write to.";
  }
  if (/network|fetch|timeout/i.test(msg)) {
    return "We couldn't reach the image service. Check your connection and try again.";
  }
  return msg || "That one didn't come through — try generating again.";
}
