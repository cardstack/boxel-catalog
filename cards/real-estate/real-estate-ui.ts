import { htmlSafe } from '@ember/template';
import { modifier } from 'ember-modifier';

// The Pret UI settings the Property Listing blocks share, kept in one module
// so the listing page, the publish panel and the photo viewer render their
// controls the same way. The settings every cluster shares live in
// `components/pretui-helpers`.

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
