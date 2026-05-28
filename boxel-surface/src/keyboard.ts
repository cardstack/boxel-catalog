const textInputTypes = new Set([
  '',
  'date',
  'datetime-local',
  'email',
  'month',
  'number',
  'password',
  'search',
  'tel',
  'text',
  'time',
  'url',
  'week',
]);

const keyboardOwnerSelector = [
  '[data-surface-keyboard-owner]',
  '[data-surface-key-scope]',
].join(', ');

const nativeInteractiveSelector = [
  'input',
  'textarea',
  'select',
  'button',
  'a[href]',
  '[contenteditable]:not([contenteditable=false])',
  '[role="button"]',
  '[role="checkbox"]',
  '[role="link"]',
  '[role="listbox"]',
  '[role="menu"]',
  '[role="menuitem"]',
  '[role="menuitemcheckbox"]',
  '[role="menuitemradio"]',
  '[role="option"]',
  '[role="radio"]',
  '[role="slider"]',
  '[role="switch"]',
  '[role="textbox"]',
].join(', ');

const focusRetainingSelectionTargetSelector = [
  '[data-bx-lift]',
  '[data-surface-key-scope]',
  '[data-surface-preserve-focus]',
  'select',
  'textarea',
  '[contenteditable]:not([contenteditable=false])',
  '[role="listbox"]',
  '[role="menu"]',
  '[role="menuitem"]',
  '[role="menuitemcheckbox"]',
  '[role="menuitemradio"]',
  '[role="option"]',
  '[role="textbox"]',
].join(', ');

const pointerOwnedControlSelector = [
  '[data-surface-atom-editor]',
  '[data-surface-keyboard-owner]',
  '[data-surface-key-scope]',
  '[data-surface-preserve-focus]',
  'input',
  'textarea',
  'select',
  '[contenteditable]:not([contenteditable=false])',
  '[role="listbox"]',
  '[role="menu"]',
  '[role="menuitem"]',
  '[role="menuitemcheckbox"]',
  '[role="menuitemradio"]',
  '[role="option"]',
  '[role="slider"]',
  '[role="textbox"]',
].join(', ');

const activationKeys = new Set(['Enter', ' ']);
const inputOwnedRoles = new Set([
  'listbox',
  'menu',
  'menuitem',
  'menuitemcheckbox',
  'menuitemradio',
  'option',
  'slider',
  'textbox',
]);

export function isSurfaceTextEntryTarget(
  target: EventTarget | Element | null | undefined,
): boolean {
  const element = target instanceof Element ? target : null;
  const control = element?.closest<HTMLElement>(
    'input, textarea, [contenteditable]:not([contenteditable=false]), [role="textbox"]',
  );
  if (!control) return false;
  if (control instanceof HTMLTextAreaElement) return true;
  if (control instanceof HTMLInputElement) {
    return textInputTypes.has(control.type.toLowerCase());
  }
  return true;
}

export function surfaceTargetOwnsKeyboardEvent(event: KeyboardEvent): boolean {
  return surfaceElementOwnsKeyboardEvent(
    event.target instanceof Element ? event.target : null,
    event.key,
  );
}

export function surfaceTargetOwnsPointerEvent(
  target: EventTarget | Element | null | undefined,
): boolean {
  const element = target instanceof Element ? target : null;
  return Boolean(element?.closest(pointerOwnedControlSelector));
}

export function surfaceElementOwnsKeyboardEvent(
  target: Element | null | undefined,
  key: string,
): boolean {
  if (!target) return false;
  if (target.closest(keyboardOwnerSelector)) return true;

  const control = target.closest<HTMLElement>(nativeInteractiveSelector);
  if (!control) return false;

  if (isSurfaceTextEntryTarget(control)) return true;

  if (control instanceof HTMLSelectElement) return true;
  if (control instanceof HTMLInputElement) {
    const type = control.type.toLowerCase();
    if (type === 'range') return true;
    if (type === 'checkbox' || type === 'radio') return activationKeys.has(key);
    return false;
  }

  const role = control.getAttribute('role');
  if (role && inputOwnedRoles.has(role)) return true;

  if (
    control instanceof HTMLButtonElement ||
    control instanceof HTMLAnchorElement ||
    role === 'button' ||
    role === 'checkbox' ||
    role === 'radio' ||
    role === 'switch'
  ) {
    return activationKeys.has(key);
  }

  return false;
}

export function surfaceTargetRetainsBrowserFocusAfterSelection(
  target: EventTarget | Element | null | undefined,
): boolean {
  const element = target instanceof Element ? target : null;
  if (!element) return false;

  if (surfaceTargetOwnsPointerEvent(element)) return true;

  if (element.closest(focusRetainingSelectionTargetSelector)) return true;

  const input = element.closest<HTMLInputElement>('input');
  return input ? isSurfaceTextEntryTarget(input) : false;
}
