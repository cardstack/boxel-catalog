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

// Sets ARIA attributes on the element a Pret UI component renders inside the
// one this modifier sits on, for the components that expose no argument for
// them.
function setAriaOn(
  element: HTMLElement,
  selector: string,
  attrs: Record<string, string>,
) {
  let target = element.querySelector(selector);
  for (let [name, value] of Object.entries(attrs)) {
    target?.setAttribute(name, value);
  }
}

/**
 * Pret UI's `ProgressBar` renders its `role='progressbar'` element with no
 * accessible name and no minimum, so this names it and states the 0 floor.
 */
export const nameProgress = modifier(
  (element: HTMLElement, [label]: [string]) => {
    setAriaOn(element, '[role="progressbar"]', {
      'aria-label': label,
      'aria-valuemin': '0',
    });
  },
);

/**
 * Pret UI's `Table` has no caption slot, so a table is named by the heading
 * above it: this points the rendered `<table>` at that heading's id.
 */
export const labelledBy = modifier((element: HTMLElement, [id]: [string]) => {
  setAriaOn(element, 'table', { 'aria-labelledby': id });
});

// Pret UI `Token` sets its text at `--text-body` minus this offset, so a
// Token that should read at a given size takes that size plus the offset.
const TOKEN_TEXT_OFFSET = '3.5px';

/**
 * Inline style for a Pret UI `Token` drawn in `hue` with its text at `size`
 * (a font-size custom property such as `--boxel-font-size-xs`). Token writes
 * `@hue` as its own inline style, which a caller's `style` would replace, so
 * the hue travels in this style instead of through `@hue`.
 */
export function tokenStyle(size: string, hue: string) {
  return htmlSafe(
    `--pretui-token-hue: ${hue}; --text-body: calc(var(${size}) + ${TOKEN_TEXT_OFFSET})`,
  );
}
