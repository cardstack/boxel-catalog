export interface StableSizeGateOptions {
  jitterPx?: number;
  thrashLimit?: number;
  thrashWindowMs?: number;
  cooldownMs?: number;
  now?: () => number;
}

export type StableSizeDecisionReason =
  | 'initial'
  | 'changed'
  | 'jitter'
  | 'cooldown';

export interface StableSizeDecision {
  apply: boolean;
  width: number;
  height: number;
  reason: StableSizeDecisionReason;
}

/**
 * Guards expensive renderer resizes from feedback loops caused by transient
 * overlays, scrollbars, transformed anchors, or ResizeObserver jitter.
 */
export class StableSizeGate {
  private jitterPx: number;
  private thrashLimit: number;
  private thrashWindowMs: number;
  private cooldownMs: number;
  private now: () => number;
  private width = 0;
  private height = 0;
  private hasAcceptedSize = false;
  private resizeTimes: number[] = [];
  private cooldownUntil = 0;
  private pending: { width: number; height: number } | null = null;

  constructor(options: StableSizeGateOptions = {}) {
    this.jitterPx = options.jitterPx ?? 2;
    this.thrashLimit = options.thrashLimit ?? 6;
    this.thrashWindowMs = options.thrashWindowMs ?? 300;
    this.cooldownMs = options.cooldownMs ?? 450;
    this.now = options.now ?? (() => performance.now());
  }

  consider(width: number, height: number): StableSizeDecision {
    const next = this.normalize(width, height);
    if (!this.hasAcceptedSize) {
      return this.accept(next.width, next.height, 'initial');
    }

    if (this.isJitter(next.width, next.height)) {
      return this.decision(false, next.width, next.height, 'jitter');
    }

    const now = this.now();
    if (now < this.cooldownUntil) {
      this.pending = next;
      return this.decision(false, next.width, next.height, 'cooldown');
    }

    this.recordResize(now);
    if (this.resizeTimes.length >= this.thrashLimit) {
      this.cooldownUntil = now + this.cooldownMs;
      this.resizeTimes = [];
      this.pending = next;
      return this.decision(false, next.width, next.height, 'cooldown');
    }

    return this.accept(next.width, next.height, 'changed');
  }

  flush(): StableSizeDecision | null {
    const pending = this.pending;
    if (!pending) return null;
    if (this.now() < this.cooldownUntil) {
      return this.decision(false, pending.width, pending.height, 'cooldown');
    }
    this.pending = null;
    if (this.isJitter(pending.width, pending.height)) {
      return this.decision(false, pending.width, pending.height, 'jitter');
    }
    return this.accept(pending.width, pending.height, 'changed');
  }

  get hasPending(): boolean {
    return this.pending !== null;
  }

  private normalize(
    width: number,
    height: number,
  ): { width: number; height: number } {
    return {
      width: Math.max(1, Math.round(width)),
      height: Math.max(1, Math.round(height)),
    };
  }

  private isJitter(width: number, height: number): boolean {
    return (
      Math.abs(width - this.width) <= this.jitterPx &&
      Math.abs(height - this.height) <= this.jitterPx
    );
  }

  private recordResize(now: number): void {
    const cutoff = now - this.thrashWindowMs;
    this.resizeTimes = this.resizeTimes.filter((time) => time >= cutoff);
    this.resizeTimes.push(now);
  }

  private accept(
    width: number,
    height: number,
    reason: StableSizeDecisionReason,
  ): StableSizeDecision {
    this.width = width;
    this.height = height;
    this.hasAcceptedSize = true;
    return this.decision(true, width, height, reason);
  }

  private decision(
    apply: boolean,
    width: number,
    height: number,
    reason: StableSizeDecisionReason,
  ): StableSizeDecision {
    return { apply, width, height, reason };
  }
}
