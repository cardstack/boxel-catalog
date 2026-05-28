// Small template-callable helpers used by the Form surface components
// (`form.gts`, `form-tab.gts`, `form-step.gts`, `form-tabs.gts`,
// `form-wizard.gts`, `form-field.gts`, `form-alert.gts`).
//
// Locally vendored from `@cardstack/boxel-ui/helpers/{truth-helpers,
// math-helpers, element}` so that `@cardstack/surfaces` does not
// depend on `boxel-ui` being installed. `boxel-ui` is a workspace-link
// package in development and is not published to npm, so Vercel and
// CI builds cannot resolve it from the registry. Vendoring eliminates
// the cross-repo coupling for the engine; consumers can still install
// `boxel-ui` for the broader Boxel design system, but they are not
// required to.
//
// Keep signatures aligned with the boxel-ui originals at
// `boxel/packages/boxel-ui/addon/src/helpers/{truth-helpers,math-helpers,element}.ts`.

import EmberComponent from '@ember/component';
import type { ComponentLike } from '@glint/template';

export function eq<T>(a: T, b: T): boolean {
  return a === b;
}

export function lt<T>(a: T, b: T): boolean {
  return a < b;
}

export function add(a: number, b: number): number {
  return a + b;
}

interface ElementSignature<T extends keyof HTMLElementTagNameMap> {
  Blocks: { default: [] };
  Element: HTMLElementTagNameMap[T];
}

export function element<T extends keyof HTMLElementTagNameMap>(
  tagName: T | undefined,
): ComponentLike<ElementSignature<T>> {
  return class DynamicElement extends EmberComponent<ElementSignature<T>> {
    tagName = (tagName ?? ('div' as T)) as string;
  };
}
