import { modifier } from 'ember-modifier';

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
