// VENDORED — types match `@cardstack/boxel-ui/icons/types.ts`. The
// `Icon` interface is the structural contract every icon component
// must satisfy. Icons in this directory are vendored from boxel-ui
// so `@cardstack/surfaces` builds without the linked boxel-ui
// addon (Vercel, GitHub Actions, fresh npm install).

import type { TemplateOnlyComponent } from '@ember/component/template-only';
import type { ComponentLike } from '@glint/template';

export interface Signature {
  Element: SVGSVGElement;
}

export type Icon = ComponentLike<Signature>;
export type IconComponent = TemplateOnlyComponent<Signature>;
