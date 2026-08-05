import { htmlSafe } from '@ember/template';
import { modifier } from 'ember-modifier';

// Single source for the blog's design tokens (was copy-pasted into
// blog-app / blog-post / author). Two deliberate properties:
//
// 1. Color tokens CHAIN to the semantic theme vocabulary (--background,
//    --foreground, --primary, …) with the blog's own literals as fallback,
//    so a linked Theme card that supplies only semantic tokens re-skins the
//    whole blog — direct --blog-* overrides from a theme's cssVariables
//    still win outright.
// 2. The selector is `.blog-scope` (every blog card root carries the class),
//    NOT `:root` — the injected stylesheet no longer restyles the host
//    document. Only the Google-Fonts @import is inherently global.
export const DEFAULT_BLOG_THEME_CSS = `@import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap');
.blog-scope {
  --blog-color-bg: var(--background, #ffffff);
  --blog-color-text: var(--foreground, #121212);
  --blog-color-body: var(--foreground, #1a1a1a);
  --blog-color-muted: var(--muted-foreground, #555);
  --blog-color-subtle: var(--muted-foreground, #6b6b6b);
  --blog-color-faint: var(--muted-foreground, #999);
  --blog-color-placeholder: #b5b5b5;
  --blog-color-thumb-bg: var(--muted, #e5e7eb);
  --blog-color-divider: var(--border, #d1d5db);
  --blog-color-border: var(--border, #e5e7eb);
  --blog-color-accent: var(--primary, #7b61ff);
  --blog-color-on-accent: var(--primary-foreground, #ffffff);
  --blog-color-card-bg: var(--card, #ffffff);
  --blog-color-text-muted: var(--muted-foreground, #6b7280);
  --blog-font-family: var(--font-sans, 'Inter', system-ui, -apple-system, sans-serif);
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
  --blog-reading-max: 680px;
  --blog-subtitle-max: 720px;
  --blog-headline-max: 860px;
  --blog-canvas-max: 1100px;
  --blog-radius-md: 12px;
  --blog-radius-pill: 999px;
  --blog-shadow-card: 0 1px 3px rgba(0, 0, 0, 0.06);
  --blog-shadow-card-hover: 0 6px 18px rgba(0, 0, 0, 0.1);
  --blog-shadow-portrait: 0 4px 14px rgba(0, 0, 0, 0.08);
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
