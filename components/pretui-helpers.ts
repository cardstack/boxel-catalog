import { htmlSafe } from '@ember/template';
import { modifier } from 'ember-modifier';

// The Pret UI settings the catalog's cards and fields share, kept in one
// module so every alert, avatar, id token, compact empty state, progress bar
// and table renders the same way in every cluster. Settings that belong to
// one cluster stay in that cluster's own module.

// Pret UI `Alert` paints its tone from the fill tokens, whose text mixes fall
// under 4.5:1 on some grounds, and its info tone reads a token boxel's theme
// does not declare. Alert writes its hue as an inline style, so the override
// is inline too: the hue is the tone's `--*-ink` token, the tint is 10%, and
// the glyph disc's mark is the card colour. The body text is the ink as well,
// except for info: `--info-ink` is 4.79:1 on the dark card before any tint,
// so an info body reads `--foreground`.
// Pret UI gap, tracked in CS-13378.
function alertStyle(ink: string, body = ink) {
  return htmlSafe(
    `--pretui-alert-hue: var(${ink}); --pretui-chip-mix: 10%; --pretui-on-neutral: var(--card); color: var(${body})`,
  );
}

/** Inline style for a Pret UI `Alert`, per tone. */
export const ALERT_STYLE = {
  danger: alertStyle('--destructive-ink'),
  success: alertStyle('--success-ink'),
  info: alertStyle('--info-ink', '--foreground'),
  attention: alertStyle('--attention-ink'),
};

/**
 * The hue for Pret UI `Avatar`. Avatar tints its disc 16% of the hue and sets
 * its initials at 80% of it, so a fill token as the hue leaves pale initials
 * on a pale disc. `--primary-ink` keeps the primary identity and clears 4.5:1
 * in both schemes.
 * A catalog design choice rather than a Pret UI gap: it stays when Pret UI
 * changes.
 */
export const AVATAR_HUE = 'var(--primary-ink)';

/**
 * Pret UI `EmptyState` tuned through its spacing and title knobs to a compact
 * well, for an empty list inside a section rather than a whole page.
 * Pret UI gap, tracked in CS-13420.
 */
export const COMPACT_EMPTY_STYLE = htmlSafe(
  '--space-9: 1rem; --space-6: 1rem; --text-heading: var(--boxel-font-size)',
);

// Pret UI `Token` sets its text at `--text-body` minus this offset, so a
// Token that should read at a given size takes that size plus the offset.
// Pret UI gap, tracked in CS-13267.
const TOKEN_TEXT_OFFSET = '3.5px';

/**
 * Inline style for a Pret UI `Token` drawn in `hue` with its text at `size`
 * (a font-size custom property such as `--boxel-font-size-xs`). Token writes
 * `@hue` as its own inline style, which a caller's `style` would replace, so
 * the hue travels in this style instead of through `@hue`.
 * Pret UI gap, tracked in CS-13267.
 */
export function tokenStyle(size: string, hue: string) {
  return htmlSafe(
    `--pretui-token-hue: ${hue}; --text-body: calc(var(${size}) + ${TOKEN_TEXT_OFFSET})`,
  );
}

/**
 * Pret UI `Token` for a machine value (an id, a reference, a field path, a
 * hash) in the muted hue, at the small or extra-small size.
 * Pret UI gap, tracked in CS-13267.
 */
export const ID_TOKEN_STYLE = {
  sm: tokenStyle('--boxel-font-size-sm', 'var(--muted-foreground)'),
  xs: tokenStyle('--boxel-font-size-xs', 'var(--muted-foreground)'),
};

/**
 * Names a Pret UI `ProgressBar`: gives its `role='progressbar'` element a
 * fixed `aria-label` and states the 0 floor with `aria-valuemin`. The optional
 * value text becomes `aria-valuetext`, for a bar whose count alone would
 * mislead (a run that ended early fills every segment); without it the
 * modifier leaves `aria-valuetext` as the component set it.
 * It names the element it is applied to when that element carries the role,
 * and otherwise its first descendant that does, so it covers both ProgressBar
 * layouts: the role on the component root, and the role on an inner track.
 * Pret UI gap, tracked in CS-13265.
 */
export const nameProgress = modifier(
  (element: HTMLElement, [label, valueText]: [string, string?]) => {
    let bar = progressbarOf(element);
    bar?.setAttribute('aria-label', label);
    bar?.setAttribute('aria-valuemin', '0');
    if (valueText) {
      bar?.setAttribute('aria-valuetext', valueText);
    }
  },
);

/**
 * The `role='progressbar'` element of a Pret UI `ProgressBar` a modifier is
 * applied to: the element itself when it carries the role, otherwise its
 * first descendant that does.
 */
export function progressbarOf(element: Element): Element | null {
  return element.matches('[role="progressbar"]')
    ? element
    : element.querySelector('[role="progressbar"]');
}

/**
 * Pret UI's `Table` has no caption slot, so a table is named by the text
 * above it: this points the rendered `<table>` at that text's id, and
 * drops the attribute when there is no id to point at.
 * Pret UI gap, tracked in CS-13266.
 */
export const labelledBy = modifier(
  (element: HTMLElement, [id]: [string | undefined]) => {
    let table = element.querySelector('table');
    if (id) {
      table?.setAttribute('aria-labelledby', id);
    } else {
      table?.removeAttribute('aria-labelledby');
    }
  },
);
