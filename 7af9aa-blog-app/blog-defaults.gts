import { htmlSafe } from '@ember/template';
import { modifier } from 'ember-modifier';

// Single source for the blog's design tokens (was copy-pasted into
// blog-app / blog-post / author). Two deliberate properties:
//
// 1. Colours are NOT declared here: blog templates read the theme contract
//    (--background, --foreground, --primary, …) directly, with no fallback
//    and no --blog-color-* adapter layer (pret-ui-theming rules 2 and 6).
//    Only typography, spacing and shadow knobs live in this block.
// 2. The selector is `.blog-scope` (every blog card root carries the class),
//    NOT `:root` — the injected stylesheet no longer restyles the host
//    document. Only the Google-Fonts @import is inherently global.
export const DEFAULT_BLOG_THEME_CSS = `@import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap');
.blog-scope {
  --blog-font-family: var(--font-sans);
  --blog-font-headline: 800 4rem/1.05 var(--blog-font-family);
  --blog-font-display-l: 800 2.6rem/1.05 var(--blog-font-family);
  --blog-font-display-m: 800 2rem/1.1 var(--blog-font-family);
  --blog-font-name: 800 1.5rem/1.15 var(--blog-font-family);
  --blog-font-h2: 800 1.75rem/1.2 var(--blog-font-family);
  --blog-font-h3: 700 1.2rem/1.3 var(--blog-font-family);
  --blog-font-subtitle: 400 1.25rem/1.45 var(--blog-font-family);
  --blog-font-pullquote: 600 1.5rem/1.35 var(--blog-font-family);
  --blog-font-body: 400 1.0625rem/1.7 var(--blog-font-family);
  --blog-font-body-sm: 400 0.95rem/1.6 var(--blog-font-family);
  --blog-font-meta: 600 0.7rem/1 var(--blog-font-family);
  --blog-font-eyebrow: 700 0.7rem/1 var(--blog-font-family);
  --blog-tracking-meta: 0.05em;
  --blog-tracking-eyebrow: 0.18em;
  --blog-tracking-tight: -0.02em;
  --blog-tracking-tighter: -0.01em;
  --blog-reading-max: 42.5rem;
  --blog-subtitle-max: 45rem;
  --blog-headline-max: 53.75rem;
  --blog-canvas-max: 68.75rem;
  --blog-radius-md: 0.75rem;
  --blog-radius-pill: 62.4375rem;
  --blog-shadow-card: 0 1px 0.1875rem color-mix(in oklch, var(--foreground) 6%, transparent);
  --blog-shadow-card-hover: 0 0.375rem 1.125rem color-mix(in oklch, var(--foreground) 10%, transparent);
  --blog-shadow-portrait: 0 0.25rem 0.875rem color-mix(in oklch, var(--foreground) 8%, transparent);
}`;

// Defaults live in a low-priority cascade layer so a theme's own un-layered
// cssVariables (emitted after) always win; a themeless card just gets the
// layered defaults.
export function buildBlogThemeCss(theme: any): string {
  const fallback = `@layer blog-defaults { ${DEFAULT_BLOG_THEME_CSS} }`;
  if (!theme || !theme.cssVariables) return fallback;
  const imports = (theme.cssImports ?? [])
    .filter(Boolean)
    .map((u: string) => `@import url('${u}');`)
    .join('\n');
  return `${fallback}\n${imports}\n${theme.cssVariables}`;
}

export function themeStyleFor(component: any) {
  return htmlSafe(buildBlogThemeCss(component?.args?.model?.cardInfo?.theme));
}

export const onClickOutside = modifier(
  (element: HTMLElement, [callback]: [() => void]) => {
    const handler = (event: MouseEvent) => {
      if (!element.contains(event.target as Node)) {
        callback();
      }
    };
    // defer registration so the click that opened the element doesn't
    // immediately close it
    const timer = setTimeout(() => {
      document.addEventListener('mousedown', handler);
    }, 0);
    return () => {
      clearTimeout(timer);
      document.removeEventListener('mousedown', handler);
    };
  },
);

export const formatDatetime = (
  datetime: Date,
  opts: Intl.DateTimeFormatOptions,
) => new Intl.DateTimeFormat('en-US', opts).format(datetime);

export function toISOString(datetime: Date): string {
  return datetime.toISOString();
}
