import { htmlSafe } from '@ember/template';
import { modifier } from 'ember-modifier';

// The Pret UI settings the Property Listing blocks share, kept in one module
// so the listing page, the publish panel and the photo viewer render their
// messages and controls the same way.

// Pret UI `Alert` paints its tone from the fill tokens, whose text mixes fall
// under 4.5:1 on some grounds, and its info tone reads a token boxel's theme
// does not declare. Alert writes its hue as an inline style, so the override
// is inline too: the hue is the tone's `--*-ink` token, the tint is 10%, and
// the glyph disc's mark is the card colour. The body text is the ink as well,
// except for info: `--info-ink` is 4.79:1 on the dark card before any tint,
// so an info body reads `--foreground`.
function alertStyle(ink: string, body = ink) {
  return htmlSafe(
    `--pretui-alert-hue: var(${ink}); --pretui-chip-mix: 10%; --pretui-on-neutral: var(--card); color: var(${body})`,
  );
}

export const ALERT_STYLE = {
  danger: alertStyle('--destructive-ink'),
  success: alertStyle('--success-ink'),
  info: alertStyle('--info-ink', '--foreground'),
  attention: alertStyle('--attention-ink'),
};

/**
 * Pret UI's ghost `Button` / `IconButton` on the photo viewer's black scrim.
 * The neutral tone writes its ink tokens on the button element itself, so an
 * ancestor cannot retint it; this inline style sets white ink, a white hover
 * veil and a white focus ring, which read in both schemes because the scrim
 * never follows the theme.
 */
export const SCRIM_BUTTON_STYLE = htmlSafe(
  '--pretui-btn-ink: white; --pretui-btn-ink-quiet: white; --hover: color-mix(in oklch, white 14%, transparent); --ring: white',
);

/**
 * The slideshow Pause/Resume button: the scrim button knobs plus its ring.
 * The ring is inline because Pret UI's ghost Button rules out-rank a scoped
 * `box-shadow` on the same element.
 */
export const PAUSE_BUTTON_STYLE = htmlSafe(
  `${SCRIM_BUTTON_STYLE}; box-shadow: 0 0 0 1px color-mix(in oklch, white 40%, transparent)`,
);

/**
 * Points the form control a Pret UI component renders inside this element at
 * the elements that describe it (`ids` is a space-separated id list), for the
 * components (`Checkbox`) whose `...attributes` land on the wrapping label
 * rather than the control.
 */
export const describeControl = modifier(
  (element: HTMLElement, [ids]: [string | undefined]) => {
    let control = element.querySelector('input');
    if (ids) {
      control?.setAttribute('aria-describedby', ids);
    } else {
      control?.removeAttribute('aria-describedby');
    }
  },
);
