import { htmlSafe } from '@ember/template';
import { modifier } from 'ember-modifier';

// The Pret UI settings the Service Desk blocks share, kept in one module so
// the workspace, the link picker and the record views that show a problem, a
// result or an avatar all render them the same way.

// Pret UI `Alert` paints its tone from the fill tokens, whose text mixes fall
// under 4.5:1 on some grounds. Alert writes its hue as an inline style, so the
// override is inline too: the hue is the tone's `--*-ink` token, the tint is
// 10%, the glyph disc's mark is the card colour, and the body text is the ink.
function alertStyle(ink: string) {
  return htmlSafe(
    `--pretui-alert-hue: var(${ink}); --pretui-chip-mix: 10%; --pretui-on-neutral: var(--card); color: var(${ink})`,
  );
}

export const ALERT_STYLE = {
  danger: alertStyle('--destructive-ink'),
  success: alertStyle('--success-ink'),
};

/**
 * The hue for Pret UI `Avatar`. Avatar tints its disc 16% of the hue and sets
 * its initials at 80% of it, so a fill token as the hue leaves pale initials
 * on a pale disc. `--primary-ink` keeps the primary identity the initials had
 * and clears 4.5:1 in both schemes.
 */
export const AVATAR_HUE = 'var(--primary-ink)';

/**
 * Pret UI's `ProgressBar` renders its `role='progressbar'` element with no
 * accessible name and no minimum, so this names it and states the 0 floor.
 */
export const nameProgress = modifier(
  (element: HTMLElement, [label]: [string]) => {
    let bar = element.querySelector('[role="progressbar"]');
    bar?.setAttribute('aria-label', label);
    bar?.setAttribute('aria-valuemin', '0');
  },
);
