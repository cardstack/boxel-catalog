import { modifier } from 'ember-modifier';
import { statusHue } from '@cardstack/pretui/internal/ink';

/** "$12,000.00" from an amount and an ISO 4217 code; a bare number when the code is missing or unknown. */
export function formatMoney(amount: number | undefined, code?: string): string {
  if (amount === undefined || !Number.isFinite(amount)) return '';
  if (code) {
    try {
      return new Intl.NumberFormat('en-US', {
        style: 'currency',
        currency: code,
      }).format(amount);
    } catch {
      /* unknown code: fall through to the plain number */
    }
  }
  return new Intl.NumberFormat('en-US', {
    maximumFractionDigits: 2,
  }).format(amount);
}

/**
 * Whether a number is present and finite, so a template can guard a money line
 * or a score. 0 counts: only an unset value hides.
 */
export function hasNumber(value: number | null | undefined): value is number {
  return typeof value === 'number' && Number.isFinite(value);
}

/**
 * The hue for Pret UI's `Avatar`: the chart hue Avatar would hash from the
 * name, pulled 55% toward the foreground. Avatar's own ink is 80% hue, which
 * leaves the paler chart hues below 4.5:1 (2.18 light, 2.63 dark); pulled
 * toward the foreground the initials clear 4.5:1 for every chart hue in both
 * schemes, and the hue still reads.
 */
export function avatarHue(name: string | null | undefined): string {
  return `color-mix(in oklch, ${statusHue(name ?? '')} 45%, var(--foreground))`;
}

/**
 * Pret UI's `ProgressBar` renders its `role='progressbar'` element with no
 * accessible name, so this names it after an element on the page instead.
 */
export const labelProgress = modifier(
  (element: HTMLElement, [id]: [string | undefined]) => {
    let bar = element.querySelector('[role="progressbar"]');
    if (!bar) {
      return;
    }
    if (id) {
      bar.setAttribute('aria-labelledby', id);
    } else {
      bar.removeAttribute('aria-labelledby');
    }
  },
);
