import { modifier } from 'ember-modifier';

export interface InlineEditOptions {
  enabled?: boolean;
  activation?: 'always' | 'change-inline';
  value?: string;
  label?: string;
  multiline?: boolean;
  onInput?: (value: string, event: InputEvent) => void;
}

const CommitInlineEditEvent = 'boxel-surface:inline-edit-commit';
const InlineEditTextDisplayAttribute = 'data-surface-inline-text-display';

export function commitInlineEdits(root: ParentNode = document): void {
  for (const element of root.querySelectorAll<HTMLElement>(
    '[data-surface-inline-edit="true"]',
  )) {
    element.dispatchEvent(new Event(CommitInlineEditEvent));
  }
}

function restoreAttribute(
  element: HTMLElement,
  name: string,
  value: string | null,
): void {
  if (value === null) {
    element.removeAttribute(name);
  } else {
    element.setAttribute(name, value);
  }
}

function surfaceModeForElement(element: HTMLElement): string {
  return (
    element
      .closest<HTMLElement>('[data-surface-mode]')
      ?.getAttribute('data-surface-mode') ?? 'inspect'
  );
}

function changeRouteForElement(element: HTMLElement): string {
  return (
    element
      .closest<HTMLElement>('[data-surface-change-route]')
      ?.getAttribute('data-surface-change-route') ?? 'auto'
  );
}

function shouldActivateInlineEdit(
  element: HTMLElement,
  opts: InlineEditOptions,
): boolean {
  if (!opts.enabled) return false;
  if (opts.activation !== 'change-inline') return true;
  return (
    surfaceModeForElement(element) === 'change' &&
    changeRouteForElement(element) !== 'lifted'
  );
}

const surfaceInlineEdit = modifier<{
  Element: HTMLElement;
  Args: { Named: InlineEditOptions };
}>((element, _, opts = {}) => {
  const syncTextDisplay = (): void => {
    if (
      element.getAttribute(InlineEditTextDisplayAttribute) === 'true' &&
      opts.value !== undefined &&
      document.activeElement !== element &&
      element.textContent !== opts.value
    ) {
      element.textContent = opts.value;
    }
  };

  if (!opts.enabled) {
    syncTextDisplay();

    if (element.getAttribute('data-surface-inline-edit') === 'true') {
      element.removeAttribute('contenteditable');
      element.removeAttribute('role');
      element.removeAttribute('aria-label');
      element.removeAttribute('aria-multiline');
      element.removeAttribute('spellcheck');
      element.removeAttribute('data-surface-inline-edit');
      element.removeAttribute('data-surface-inline-multiline');
      element.removeAttribute('data-surface-inline-dirty');
    }
    return;
  }

  const priorContentEditable = element.getAttribute('contenteditable');
  const priorRole = element.getAttribute('role');
  const priorAriaLabel = element.getAttribute('aria-label');
  const priorAriaMultiline = element.getAttribute('aria-multiline');
  const priorSpellcheck = element.getAttribute('spellcheck');
  const priorInlineEdit = element.getAttribute('data-surface-inline-edit');
  const priorInlineMultiline = element.getAttribute(
    'data-surface-inline-multiline',
  );
  const previousInlineEdit = priorInlineEdit === 'true';
  let isActive = false;

  const activate = (): void => {
    if (isActive) return;
    element.setAttribute('contenteditable', 'plaintext-only');
    element.setAttribute('role', 'textbox');
    element.setAttribute('spellcheck', 'false');
    element.setAttribute('data-surface-inline-edit', 'true');
    element.setAttribute(InlineEditTextDisplayAttribute, 'true');

    if (opts.label) {
      element.setAttribute('aria-label', opts.label);
    }

    if (opts.multiline) {
      element.setAttribute('aria-multiline', 'true');
      element.setAttribute('data-surface-inline-multiline', 'true');
    } else {
      element.removeAttribute('aria-multiline');
      element.removeAttribute('data-surface-inline-multiline');
    }
    isActive = true;
  };

  const deactivate = (): void => {
    if (
      !isActive &&
      element.getAttribute('data-surface-inline-edit') !== 'true'
    ) {
      syncTextDisplay();
      return;
    }
    restoreAttribute(
      element,
      'contenteditable',
      previousInlineEdit ? null : priorContentEditable,
    );
    restoreAttribute(element, 'role', previousInlineEdit ? null : priorRole);
    restoreAttribute(
      element,
      'aria-label',
      previousInlineEdit ? null : priorAriaLabel,
    );
    restoreAttribute(
      element,
      'aria-multiline',
      previousInlineEdit ? null : priorAriaMultiline,
    );
    restoreAttribute(
      element,
      'spellcheck',
      previousInlineEdit ? null : priorSpellcheck,
    );
    restoreAttribute(
      element,
      'data-surface-inline-edit',
      previousInlineEdit ? null : priorInlineEdit,
    );
    restoreAttribute(
      element,
      'data-surface-inline-multiline',
      previousInlineEdit ? null : priorInlineMultiline,
    );
    element.removeAttribute('data-surface-inline-dirty');
    isActive = false;
    syncTextDisplay();
  };

  let lastCommittedValue = opts.value;

  const commit = (event: Event): void => {
    const value = element.textContent ?? '';
    const isDirty =
      element.getAttribute('data-surface-inline-dirty') === 'true';
    if (value === lastCommittedValue) {
      element.removeAttribute('data-surface-inline-dirty');
      return;
    }
    if (!isDirty) {
      return;
    }

    lastCommittedValue = value;
    element.removeAttribute('data-surface-inline-dirty');
    opts.onInput?.(value, event as InputEvent);
  };

  const onInput = (event: Event): void => {
    const value = element.textContent ?? '';
    lastCommittedValue = value;
    element.setAttribute('data-surface-inline-dirty', 'true');
    opts.onInput?.(value, event as InputEvent);
  };

  const onKeydown = (event: KeyboardEvent): void => {
    if (!opts.multiline && event.key === 'Enter') {
      event.preventDefault();
      commit(event);
      element.blur();
    }
  };

  const onCommitRequest = (event: Event): void => {
    commit(event);
    element.blur();
  };

  const sync = (): void => {
    if (shouldActivateInlineEdit(element, opts)) {
      activate();
    } else {
      deactivate();
    }
  };

  element.addEventListener('input', onInput);
  element.addEventListener('blur', commit);
  element.addEventListener('keydown', onKeydown);
  element.addEventListener(CommitInlineEditEvent, onCommitRequest);
  sync();

  const modeRoot = element.closest<HTMLElement>('[data-surface-mode]');
  const routeRoot = element.closest<HTMLElement>('[data-surface-change-route]');
  const observer = new MutationObserver(sync);
  if (modeRoot && routeRoot === modeRoot) {
    observer.observe(modeRoot, {
      attributes: true,
      attributeFilter: ['data-surface-mode', 'data-surface-change-route'],
    });
  } else {
    if (modeRoot) {
      observer.observe(modeRoot, {
        attributes: true,
        attributeFilter: ['data-surface-mode'],
      });
    }
    if (routeRoot) {
      observer.observe(routeRoot, {
        attributes: true,
        attributeFilter: ['data-surface-change-route'],
      });
    }
  }

  return (): void => {
    observer.disconnect();
    element.removeEventListener('input', onInput);
    element.removeEventListener('blur', commit);
    element.removeEventListener('keydown', onKeydown);
    element.removeEventListener(CommitInlineEditEvent, onCommitRequest);
    deactivate();
  };
});

export default surfaceInlineEdit;
