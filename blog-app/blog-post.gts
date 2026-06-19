import DateTimeField from 'https://cardstack.com/base/datetime';
import StringField from 'https://cardstack.com/base/string';
import RichMarkdownField from 'https://cardstack.com/base/rich-markdown';
import BooleanField from 'https://cardstack.com/base/boolean';
import NumberField from 'https://cardstack.com/base/number';
import {
  CardDef,
  field,
  contains,
  Component,
  getCardMeta,
  linksToMany,
  realmURL,
} from 'https://cardstack.com/base/card-api';
import {
  codeRef,
  rri,
  type Query,
  searchEntryWireQueryFromQuery,
  type SearchEntryWireQuery,
} from '@cardstack/runtime-common';
import { tracked } from '@glimmer/tracking';
import { action } from '@ember/object';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { htmlSafe } from '@ember/template';
import { eq } from '@cardstack/boxel-ui/helpers';
import { modifier } from 'ember-modifier';

const DEFAULT_BLOG_THEME_CSS = `@import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap');
:root {
  --blog-color-bg: #ffffff;
  --blog-color-text: #121212;
  --blog-color-body: #1a1a1a;
  --blog-color-muted: #555;
  --blog-color-subtle: #6b6b6b;
  --blog-color-faint: #999;
  --blog-color-placeholder: #b5b5b5;
  --blog-color-thumb-bg: #e5e7eb;
  --blog-color-divider: #d1d5db;
  --blog-color-accent: #7b61ff;
  --blog-color-card-bg: #ffffff;
  --blog-font-family: 'Inter', system-ui, -apple-system, sans-serif;
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

function buildThemeCss(theme: any): string {
  // Defaults wrapped in a low-priority cascade layer so that any un-layered
  // :root vars an ancestor (e.g. BlogApp's Ramped theme) injects will win.
  const fallback = `@layer blog-defaults { ${DEFAULT_BLOG_THEME_CSS} }`;
  if (!theme || !theme.cssVariables) return fallback;
  const imports = (theme.cssImports ?? [])
    .filter(Boolean)
    .map((u: string) => `@import url('${u}');`)
    .join('\n');
  // The post's own theme is emitted un-layered — wins over both the layered
  // defaults and any parent's un-layered injection (later in DOM).
  return `${fallback}\n${imports}\n${theme.cssVariables}`;
}

// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
const here: string = import.meta.url;

const scrollProgress = modifier((element: HTMLElement) => {
  const findScroller = (): HTMLElement | Window => {
    let el: HTMLElement | null = element.parentElement;
    while (el) {
      const overflowY = getComputedStyle(el).overflowY;
      if (
        (overflowY === 'auto' || overflowY === 'scroll') &&
        el.scrollHeight > el.clientHeight
      ) {
        return el;
      }
      el = el.parentElement;
    }
    return window;
  };
  const scroller = findScroller();
  const update = () => {
    let pct = 0;
    if (scroller instanceof Window) {
      const max = document.documentElement.scrollHeight - window.innerHeight;
      pct = max > 0 ? Math.min(100, (window.scrollY / max) * 100) : 0;
    } else {
      const max = scroller.scrollHeight - scroller.clientHeight;
      pct = max > 0 ? Math.min(100, (scroller.scrollTop / max) * 100) : 0;
    }
    element.style.setProperty('width', `${pct}%`);
  };
  update();
  const opts: AddEventListenerOptions = { passive: true };
  (scroller as any).addEventListener('scroll', update, opts);
  return () => (scroller as any).removeEventListener('scroll', update);
});

// Fires `callback` on a mousedown that lands outside the modified element.
const onClickOutside = modifier(
  (element: HTMLElement, positional: unknown[]) => {
    const callback = positional[0] as () => void;
    const handler = (event: MouseEvent) => {
      if (!element.contains(event.target as Node)) {
        callback();
      }
    };
    const timer = setTimeout(() => {
      document.addEventListener('mousedown', handler);
    }, 50);
    return () => {
      clearTimeout(timer);
      document.removeEventListener('mousedown', handler);
    };
  },
);

const fadeInOnView = modifier((element: HTMLElement) => {
  if (typeof window === 'undefined' || !('IntersectionObserver' in window)) {
    element.classList.add('is-in-view');
    return () => {};
  }
  const reduceMotion = window.matchMedia(
    '(prefers-reduced-motion: reduce)',
  ).matches;
  if (reduceMotion) {
    element.classList.add('is-in-view');
    return () => {};
  }
  const obs = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (entry.isIntersecting) {
          (entry.target as HTMLElement).classList.add('is-in-view');
          obs.unobserve(entry.target);
        }
      }
    },
    { threshold: 0.08, rootMargin: '0px 0px -40px 0px' },
  );
  obs.observe(element);
  return () => obs.disconnect();
});

import CalendarCog from '@cardstack/boxel-icons/calendar-cog';
import BlogIcon from '@cardstack/boxel-icons/notebook';

import { setBackgroundImage } from '../components/layout';
import {
  LayoutCanvas,
  type Layout as BlogLayout,
} from './components/layout-canvas';
import { EditableField } from './components/editable-field';

import { Author } from './author';
import { BlogCategory, categoryStyle } from './blog-category';

// Local copy to avoid a circular import on `./blog-app`. Same signature.
const formatDatetime = (datetime: Date, opts: Intl.DateTimeFormatOptions) =>
  new Intl.DateTimeFormat('en-US', opts).format(datetime);
import { User } from './user';
import FeaturedImageField from '../fields/featured-image/featured-image';

class EmbeddedTemplate extends Component<typeof BlogPost> {
  <template>
    <article class='embedded-blog-post'>
      <div
        class='thumbnail'
        style={{setBackgroundImage @model.cardThumbnailURL}}
      />
      {{#if @model.categories.length}}
        <div class='categories'>
          {{#each @model.categories as |category|}}
            <div class='category' style={{categoryStyle category}}>
              {{category.shortName}}
            </div>
          {{/each}}
        </div>
      {{/if}}
      <h3 class='title'><@fields.cardTitle /></h3>
      <p class='description'>{{@model.cardDescription}}</p>
      <span class='byline'>
        {{@model.formattedAuthors}}
      </span>
      {{#if @model.datePublishedIsoTimestamp}}
        <time class='date' datetime={{@model.datePublishedIsoTimestamp}}>
          {{@model.formattedDatePublished}}
        </time>
      {{/if}}
    </article>
    <style scoped>
      .embedded-blog-post {
        width: 100%;
        height: 100%;
        display: grid;
        grid-template:
          'img categories categories' max-content
          'img title title' max-content
          'img desc desc' max-content
          'img byline date' 1fr / 40% 1fr max-content;
        gap: var(--boxel-sp-xs);
        padding-right: var(--boxel-sp-xl);
        overflow: hidden;
      }
      .thumbnail {
        grid-area: img;
        background-color: var(--boxel-200);
        background-position: center;
        background-size: cover;
        background-repeat: no-repeat;
        margin-right: var(--boxel-sp-lg);
      }
      .title {
        grid-area: title;
        margin: var(--boxel-sp-xxs) 0 0;
        font-size: var(--boxel-font-size-lg);
        line-height: calc(30 / 22);
        letter-spacing: var(--boxel-lsp-xs);
      }
      .description {
        grid-area: desc;
        margin: 0;
        font-size: var(--boxel-font-size);
        line-height: calc(22 / 16);
        letter-spacing: var(--boxel-lsp-xs);
      }
      .byline {
        grid-area: byline;
        align-self: end;
        width: auto;
        height: auto;
        text-wrap: nowrap;
        text-overflow: ellipsis;
        overflow: hidden;
      }
      .date {
        grid-area: date;
        align-self: end;
        justify-self: end;
      }
      .byline,
      .date {
        margin-bottom: var(--boxel-sp-xs);
        font: 500 var(--boxel-font-sm);
        letter-spacing: var(--boxel-lsp-xs);
        text-wrap: nowrap;
        text-overflow: ellipsis;
        overflow: hidden;
      }

      .categories {
        margin-top: var(--boxel-sp);
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp-xxxs);
      }

      .category {
        display: inline-block;
        padding: 3px var(--boxel-sp-xxxs);
        border-radius: var(--boxel-border-radius-sm);
        font: 500 var(--boxel-font-xs);
        letter-spacing: var(--boxel-lsp-sm);
      }
    </style>
  </template>
}

class FittedTemplate extends Component<typeof BlogPost> {
  <template>
    <article class='fitted-blog-post'>
      <div
        class='thumbnail'
        style={{setBackgroundImage @model.cardThumbnailURL}}
      />
      <div class='categories'>
        {{#each @model.categories as |category|}}
          <div class='category' style={{categoryStyle category}}>
            {{category.shortName}}
          </div>
        {{/each}}
      </div>
      <div class='content'>
        <h3 class='title'><@fields.cardTitle /></h3>
        <p class='description'>{{@model.cardDescription}}</p>
        {{#if @model.formattedAuthors}}
          <span class='byline'>{{@model.formattedAuthors}}</span>
        {{/if}}
        {{#if @model.datePublishedIsoTimestamp}}
          <time class='date' datetime={{@model.datePublishedIsoTimestamp}}>
            {{@model.formattedDatePublished}}
          </time>
        {{/if}}
      </div>
    </article>
    <style scoped>
      .fitted-blog-post {
        width: 100%;
        height: 100%;
        min-width: 100px;
        min-height: 29px;
        display: grid;
        overflow: hidden;
      }
      .thumbnail {
        grid-area: img;
        background-color: var(--boxel-200);
        background-position: center;
        background-size: cover;
        background-repeat: no-repeat;
      }
      .content {
        grid-area: content;
        gap: var(--boxel-sp-4xs);
        padding: var(--boxel-sp-xs);
        overflow: hidden;
      }
      .title {
        grid-area: title;
        display: -webkit-box;
        -webkit-box-orient: vertical;
        -webkit-line-clamp: 2;
        overflow: hidden;
        margin: 0;

        font: 600 var(--boxel-font-sm);
        letter-spacing: var(--boxel-lsp-sm);
        line-height: 1.3;
      }
      .description {
        grid-area: desc;
        display: -webkit-box;
        -webkit-box-orient: vertical;
        -webkit-line-clamp: 3;
        overflow: hidden;
        margin: 0;
        font: var(--boxel-font-xs);
        letter-spacing: var(--boxel-lsp-sm);
      }
      .byline {
        grid-area: byline;
        display: inline-block;
        text-wrap: nowrap;
        text-overflow: ellipsis;
        overflow: hidden;
      }
      .date {
        grid-area: date;
        text-wrap: nowrap;
        text-overflow: ellipsis;
        overflow: hidden;
      }
      .byline,
      .date {
        font:
          600 0.7rem/1 'Inter',
          system-ui,
          sans-serif;
        letter-spacing: 0.05em;
        text-transform: uppercase;
        color: #999;
      }

      .categories {
        margin-top: -27px;
        height: 20px;
        margin-left: 7px;
        display: none;
        overflow: hidden;
      }

      .category {
        height: 20px;
        padding: 3px 4px;
        border-radius: var(--boxel-border-radius-sm);
        display: inline-block;
        font: 500 var(--boxel-font-xs);
        letter-spacing: var(--boxel-lsp-sm);
        margin-right: var(--boxel-sp-xxxs);
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      @container fitted-card ((aspect-ratio <= 1.0) and (226px <= height)) {
        .fitted-blog-post {
          grid-template:
            'img' 42%
            'categories' max-content
            'content' 1fr / 1fr;
        }
        .categories {
          display: flex;
        }
        .content {
          display: grid;
          grid-template:
            'title title' max-content
            'desc desc' max-content
            'byline date' 1fr / 1fr max-content;
        }
        .byline,
        .date {
          align-self: end;
        }
        .date {
          justify-self: end;
        }
      }

      /* Aspect ratio < 1.0 (Vertical card) */
      @container fitted-card (aspect-ratio <= 1.0) and (224px <= height < 226px) {
        .fitted-blog-post {
          grid-template:
            'img' 92px
            'categories' max-content
            'content' 1fr / 1fr;
        }
        .categories {
          display: flex;
        }

        .content {
          display: grid;
          grid-template:
            'title' max-content
            'byline' max-content
            'date' 1fr / 1fr;
        }
        .description {
          display: none;
        }
        .date {
          align-self: end;
        }
      }

      @container fitted-card (aspect-ratio <= 1.0) and (180px <= height < 224px) {
        .fitted-blog-post {
          grid-template:
            'img' 92px
            'categories' max-content
            'content' 1fr / 1fr;
        }
        .categories {
          display: flex;
        }
        .content {
          display: grid;
          grid-template:
            'title' max-content
            'date' 1fr / 1fr;
        }
        .title {
          -webkit-line-clamp: 3;
        }
        .description,
        .byline {
          display: none;
        }
        .date {
          align-self: end;
        }
      }

      @container fitted-card ((aspect-ratio <= 1.0) and (height < 180px) ) {
        .title {
          font-size: var(--boxel-font-size-xs);
        }
      }

      @container fitted-card (aspect-ratio <= 1.0) and (148px <= height < 180px) {
        .fitted-blog-post {
          grid-template:
            'img' 80px
            'content' 1fr / 1fr;
        }
        .content {
          display: grid;
          grid-template:
            'title' max-content
            'date' 1fr / 1fr;
        }
        .title {
          -webkit-line-clamp: 2;
        }
        .description,
        .byline {
          display: none;
        }
        .date {
          align-self: end;
        }
      }

      @container fitted-card (aspect-ratio <= 1.0) and (128px <= height < 148px) {
        .fitted-blog-post {
          grid-template:
            'img' 68px
            'categories' max-content
            'content' 1fr / 1fr;
        }
        .content {
          display: block;
        }
        .title {
          -webkit-line-clamp: 3;
        }
        .description,
        .byline,
        .date {
          display: none;
        }
      }

      @container fitted-card (aspect-ratio <= 1.0) and (118px <= height < 128px) {
        .fitted-blog-post {
          grid-template:
            'img' 57px
            'content' 1fr / 1fr;
        }
        .title {
          -webkit-line-clamp: 3;
        }
        .description,
        .byline,
        .date {
          display: none;
        }
      }

      @container fitted-card ((aspect-ratio <= 1.0) and (400px <= height) and (226px < width)) {
        .title {
          font-size: var(--boxel-font-size);
        }
      }

      @container fitted-card ((aspect-ratio <= 1.0) and (400px <= height)) {
        .fitted-blog-post {
          grid-template:
            'img' 55%
            'categories' max-content
            'content' 1fr / 1fr;
        }
        .categories {
          display: flex;
        }
        .content {
          display: grid;
          grid-template:
            'title' max-content
            'byline' max-content
            'desc' max-content
            'date' 1fr / 1fr;
        }
        .description {
          -webkit-line-clamp: 5;
          margin-top: var(--boxel-sp-xxxs);
        }
        .date {
          align-self: end;
        }
      }

      /* 1.0 < Aspect ratio (Horizontal card) */
      @container fitted-card ((1.0 < aspect-ratio) and (180px <= height)) {
        .fitted-blog-post {
          grid-template: 'img content' 1fr / 40% 1fr;
        }
        .content {
          display: grid;
          grid-template:
            'title' max-content
            'desc' max-content
            'byline' 1fr
            'date' max-content / 1fr;
          gap: var(--boxel-sp-5xs);
        }
        .title {
          -webkit-line-clamp: 2;
        }
        .description {
          -webkit-line-clamp: 3;
          margin-top: var(--boxel-sp-xxxs);
        }
        .byline {
          align-self: end;
        }
      }

      @container fitted-card ((1.0 < aspect-ratio) and (151px <= height < 180px)) {
        .fitted-blog-post {
          grid-template: 'img content' 1fr / 34% 1fr;
        }
        .content {
          display: grid;
          grid-template:
            'title' max-content
            'byline' max-content
            'date' 1fr / 1fr;
        }
        .title {
          -webkit-line-clamp: 2;
        }
        .description {
          display: none;
        }
        .date {
          align-self: end;
        }
      }

      @container fitted-card ((1.0 < aspect-ratio) and (115px <= height <= 150px)) {
        .fitted-blog-post {
          grid-template: 'img content' 1fr / 26% 1fr;
        }
        .content {
          display: grid;
          grid-template:
            'title' max-content
            'byline' 1fr
            'date' max-content / 1fr;
          gap: var(--boxel-sp-5xs);
        }
        .title {
          -webkit-line-clamp: 2;
        }
        .description {
          display: none;
        }
        .byline {
          align-self: end;
          margin-top: var(--boxel-sp-xxxs);
        }
      }

      @container fitted-card ((1.0 < aspect-ratio) and (78px <= height <= 114px)) {
        .fitted-blog-post {
          grid-template: 'img content' 1fr / 35% 1fr;
        }
        .title {
          -webkit-line-clamp: 3;
          font-size: var(--boxel-font-size-xs);
        }
        .description,
        .byline,
        .date {
          display: none;
        }
      }

      @container fitted-card ((1.0 < aspect-ratio) and (500px <= width) and (58px <= height <= 77px)) {
        .fitted-blog-post {
          grid-template: 'img content' 1fr / max-content 1fr;
          align-items: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xxs);
        }
        .thumbnail {
          width: 45px;
          height: 45px;
          border-radius: 5px;
        }
        .content {
          padding: 0;
        }
        .title {
          -webkit-line-clamp: 1;
          text-wrap: nowrap;
        }
        .description,
        .byline,
        .date {
          display: none;
        }
      }

      @container fitted-card ((1.0 < aspect-ratio) and (226px <= width <= 499px) and (58px <= height <= 77px)) {
        .fitted-blog-post {
          grid-template: 'img content' 1fr / max-content 1fr;
          align-items: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xxs);
        }
        .thumbnail {
          width: 45px;
          height: 45px;
          border-radius: 5px;
        }
        .content {
          padding: 0;
        }
        .title {
          -webkit-line-clamp: 2;
        }
        .description,
        .byline,
        .date {
          display: none;
        }
      }

      @container fitted-card ((1.0 < aspect-ratio) and (width <= 225px) and (58px <= height <= 77px)) {
        .fitted-blog-post {
          grid-template: 'content' 1fr / 1fr;
          align-items: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xxs);
        }
        .thumbnail,
        .description,
        .byline,
        .date {
          display: none;
        }
        .content {
          padding: 0;
        }
        .title {
          -webkit-line-clamp: 2;
          font-size: var(--boxel-font-size-xs);
        }
      }

      @container fitted-card ((1.0 < aspect-ratio) and (height <= 57px)) {
        .fitted-blog-post {
          grid-template: 'content' 1fr / 1fr;
          align-items: center;
          padding: var(--boxel-sp-xxxs);
        }
        .thumbnail,
        .description,
        .byline,
        .date {
          display: none;
        }
        .content {
          padding: 0;
        }
        .title {
          -webkit-line-clamp: 2;
          font-size: 600 var(--boxel-font-size-xs);
        }
      }
    </style>
  </template>
}

class Status extends StringField {
  static displayName = 'Status';
  static icon = CalendarCog;
}

const DEFAULT_LAYOUT: BlogLayout = [
  { slots: [{ name: 'featuredImage', width: 12 }] },
  { slots: [{ name: 'categories', width: 12 }] },
  { slots: [{ name: 'headline', width: 12 }] },
  { slots: [{ name: 'cardDescription', width: 12 }] },
  { slots: [{ name: 'byline', width: 12 }] },
  { slots: [{ name: 'body', width: 12 }] },
  { slots: [{ name: 'authorBios', width: 12 }] },
];

class IsolatedBlogPost extends Component<typeof BlogPost> {
  get themeSearchQuery(): SearchEntryWireQuery {
    return {
      ...searchEntryWireQueryFromQuery(this.themeQuery),
      realms: this.realmHrefs,
    };
  }
  get canEdit(): boolean {
    const ctx = (this.args as any).context;
    // If context defines actions, trust its saveCard signal.
    // If context is missing entirely (some render paths), default to true.
    if (ctx && ctx.actions) {
      return Boolean(ctx.actions.saveCard);
    }
    return true;
  }

  @tracked editingField: string | null = null;
  @tracked drawerOpen = false;

  @action toggleDrawer() {
    this.drawerOpen = !this.drawerOpen;
  }

  @action maybeCloseDrawer() {
    if (this.drawerOpen) this.drawerOpen = false;
  }

  get layout(): BlogLayout {
    const raw = (this.args.model as any)?.layout;
    if (!raw) return DEFAULT_LAYOUT;
    try {
      const parsed = JSON.parse(raw);
      if (Array.isArray(parsed) && parsed.length > 0) return parsed;
    } catch {
      // fall through
    }
    return DEFAULT_LAYOUT;
  }

  @action onLayoutChange(next: BlogLayout) {
    const model = this.args.model as any;
    model.layout = JSON.stringify(next);
    const actions = (this.args as any).context?.actions;
    actions?.saveCard?.(this.args.model);
  }

  @action setEditing(field: string) {
    this.editingField = field;
  }

  @action onFieldBlur() {
    setTimeout(() => {
      this.editingField = null;
    }, 150);
  }

  @action togglePublished() {
    const model = this.args.model as any;
    model.published = !model.published;
    const actions = (this.args as any).context?.actions;
    actions?.saveCard?.(this.args.model);
  }

  get themeQuery(): Query {
    return {
      filter: {
        type: {
          module: rri('https://cardstack.com/base/style-reference'),
          name: 'default',
        },
      },
    };
  }

  // Local pending override so the radio reflects the click instantly,
  // before the network round-trip + save settles the model.
  // - undefined: read from model (default)
  // - '' (empty): explicitly Inherit
  // - non-empty string: explicit theme URL
  @tracked private _pendingThemeUrl: string | undefined = undefined;

  private normalizeUrl(u: string | null | undefined): string {
    if (!u) return '';
    return String(u)
      .replace(/\.json$/, '')
      .replace(/\/$/, '');
  }

  get currentThemeUrl(): string {
    if (this._pendingThemeUrl !== undefined) {
      return this.normalizeUrl(this._pendingThemeUrl);
    }
    const linked = (this.args.model as any)?.cardInfo?.theme;
    // Try card.id (when loaded) or the relationship href as a fallback.
    return this.normalizeUrl(linked?.id ?? linked?.url ?? '');
  }

  isThemeSelected = (url: string | null | undefined): boolean => {
    return this.normalizeUrl(url) === this.currentThemeUrl;
  };

  @action setTheme(url: string | null) {
    const model = this.args.model as any;
    const ctx = (this.args as any).context;
    this._pendingThemeUrl = url ?? '';
    if (!url) {
      if (model.cardInfo) model.cardInfo.theme = null;
      ctx?.actions?.saveCard?.(this.args.model);
      return;
    }
    const resource = ctx?.getCard?.(this, () => url);
    if (!resource) return;
    const started = Date.now();
    const poll = setInterval(() => {
      if (resource.card) {
        clearInterval(poll);
        if (model.cardInfo) model.cardInfo.theme = resource.card;
        ctx?.actions?.saveCard?.(this.args.model);
      } else if (Date.now() - started > 5000) {
        clearInterval(poll);
      }
    }, 60);
  }

  @action onThemeRadioChange(url: string | null, event: Event) {
    if ((event.target as HTMLInputElement).checked) {
      this.setTheme(url);
    }
  }

  get readMinutes(): number {
    const wc = (this.args.model as any)?.wordCount ?? 0;
    return Math.max(1, Math.round(wc / 220));
  }

  get realmHrefs(): string[] {
    const u = (this.args.model as any)?.[realmURL];
    return u ? [u.href] : [];
  }

  get relatedQuery() {
    const on = codeRef(here, './blog-post', 'BlogPost');
    return {
      filter: { on, eq: { published: true } },
      sort: [{ on, by: 'publishDate', direction: 'desc' as const }],
    };
  }

  get currentCardId(): string | undefined {
    return (this.args.model as any)?.id;
  }

  get themeStyle() {
    return htmlSafe(buildThemeCss((this.args.model as any)?.cardInfo?.theme));
  }

  <template>
    <style>
      {{this.themeStyle}}
    </style>
    <div class='post-shell'>
      <div class='reading-progress' aria-hidden='true'>
        <div class='reading-progress-fill' {{scrollProgress}}></div>
      </div>
      {{#if this.canEdit}}
        <aside
          class='post-drawer {{if this.drawerOpen "is-open"}}'
          {{onClickOutside this.maybeCloseDrawer}}
        >
          <button
            type='button'
            class='drawer-toggle'
            {{on 'click' this.toggleDrawer}}
            aria-label={{if this.drawerOpen 'Close panel' 'Open panel'}}
            aria-expanded='{{if this.drawerOpen "true" "false"}}'
          >
            {{#if this.drawerOpen}}✕{{else}}☰{{/if}}
          </button>
          <div class='drawer-content'>
            <h3 class='drawer-section-label'>Status</h3>
            <div class='post-controls'>
              <span
                class='status-badge
                  {{if @model.published "is-published" "is-draft"}}'
              >
                <span class='status-dot' aria-hidden='true'></span>
                {{if @model.published 'Published' 'Draft'}}
              </span>
              <button
                type='button'
                class='publish-btn
                  {{if @model.published "publish-btn--unpublish"}}'
                {{on 'click' this.togglePublished}}
              >
                {{if @model.published 'Unpublish' 'Publish'}}
              </button>
            </div>

            <h3 class='drawer-section-label'>Theme</h3>
            <div class='theme-list' role='radiogroup' aria-label='Theme'>
              <label
                class='theme-row theme-row--inherit
                  {{if (this.isThemeSelected "") "is-selected"}}'
              >
                <input
                  type='radio'
                  name='blog-theme'
                  class='theme-radio'
                  checked={{this.isThemeSelected ''}}
                  {{on 'change' (fn this.onThemeRadioChange null)}}
                />
                <span class='theme-row__text'>
                  <span class='theme-row__name'>Inherit from site</span>
                  <span class='theme-row__desc'>Use the parent blog's theme</span>
                </span>
              </label>
              {{#let (component @context.searchResultsComponent) as |Search|}}
                <Search @query={{this.themeSearchQuery}} as |results|>
                  {{#each results.entries key='id' as |card|}}
                    <label
                      class='theme-row
                        {{if (this.isThemeSelected card.id) "is-selected"}}'
                    >
                      <input
                        type='radio'
                        name='blog-theme'
                        class='theme-radio'
                        checked={{this.isThemeSelected card.id}}
                        {{on 'change' (fn this.onThemeRadioChange card.id)}}
                      />
                      <span class='theme-preview'>
                        <card.component />
                      </span>
                    </label>
                  {{else}}
                    {{#if results.isLoading}}
                      <div class='theme-loading'>Loading themes…</div>
                    {{/if}}
                  {{/each}}
                </Search>
              {{/let}}
            </div>
          </div>
        </aside>
      {{/if}}
      <div class='blog-post-page'>
        <article class='blog-article'>
          <LayoutCanvas
            @layout={{this.layout}}
            @canEdit={{this.canEdit}}
            @onLayoutChange={{this.onLayoutChange}}
            class='article-canvas'
          >
            <:slot as |slotName|>
              {{#if (eq slotName 'featuredImage')}}
                {{#if @model.featuredImage.imageUrl}}
                  <EditableField
                    @isEditing={{eq this.editingField 'featuredImage'}}
                    @canEdit={{this.canEdit}}
                    @onEdit={{fn this.setEditing 'featuredImage'}}
                    @onBlur={{this.onFieldBlur}}
                    class='hero-image-wrap fade-in'
                    {{fadeInOnView}}
                  >
                    <:display>
                      <@fields.featuredImage class='hero-image' />
                      {{#if @model.featuredImage.caption}}
                        <p
                          class='hero-caption'
                        >{{@model.featuredImage.caption}}</p>
                      {{/if}}
                    </:display>
                    <:edit>
                      <@fields.featuredImage @format='edit' />
                    </:edit>
                  </EditableField>
                {{/if}}
              {{else if (eq slotName 'categories')}}
                {{#if @model.categories.length}}
                  <div class='categories'>
                    {{#each @model.categories as |category|}}
                      <div class='category' style={{categoryStyle category}}>
                        {{category.shortName}}
                      </div>
                    {{/each}}
                  </div>
                {{/if}}
              {{else if (eq slotName 'headline')}}
                <EditableField
                  @isEditing={{eq this.editingField 'headline'}}
                  @canEdit={{this.canEdit}}
                  @onEdit={{fn this.setEditing 'headline'}}
                  @onBlur={{this.onFieldBlur}}
                  class='headline-wrap'
                >
                  <:display>
                    <h1 class='headline'><@fields.cardTitle /></h1>
                  </:display>
                  <:edit>
                    <@fields.headline @format='edit' />
                  </:edit>
                </EditableField>
              {{else if (eq slotName 'cardDescription')}}
                <EditableField
                  @isEditing={{eq this.editingField 'cardDescription'}}
                  @canEdit={{this.canEdit}}
                  @onEdit={{fn this.setEditing 'cardDescription'}}
                  @onBlur={{this.onFieldBlur}}
                  class='subtitle-wrap'
                >
                  <:display>
                    {{#if @model.cardDescription}}
                      <p class='subtitle'>{{@model.cardDescription}}</p>
                    {{else if this.canEdit}}
                      <p class='subtitle placeholder'>+ subtitle</p>
                    {{/if}}
                  </:display>
                  <:edit>
                    <@fields.cardDescription @format='edit' />
                  </:edit>
                </EditableField>
              {{else if (eq slotName 'byline')}}
                <div class='byline-row fade-in' {{fadeInOnView}}>
                  {{#if @model.authors.length}}
                    <span class='byline'>
                      <span class='byline-prefix'>By</span>
                      {{#each @fields.authors as |AuthorComponent|}}
                        <AuthorComponent
                          class='author'
                          @format='atom'
                          @displayContainer={{false}}
                        />
                      {{/each}}
                    </span>
                  {{/if}}
                  {{#if @model.datePublishedIsoTimestamp}}
                    <span class='byline-sep' aria-hidden='true'>·</span>
                    <time
                      class='pub-date'
                      datetime={{@model.datePublishedIsoTimestamp}}
                    >
                      {{@model.formattedDatePublished}}
                    </time>
                  {{/if}}
                  <span class='byline-sep' aria-hidden='true'>·</span>
                  <span class='read-time'>{{this.readMinutes}} min read</span>
                </div>
              {{else if (eq slotName 'body')}}
                <EditableField
                  @isEditing={{eq this.editingField 'body'}}
                  @canEdit={{this.canEdit}}
                  @onEdit={{fn this.setEditing 'body'}}
                  @onBlur={{this.onFieldBlur}}
                  class={{if
                    (eq this.editingField 'body')
                    'body-wrap body-zoomed fade-in'
                    'body-wrap fade-in'
                  }}
                  {{fadeInOnView}}
                >
                  <:display>
                    <div class='article-body'>
                      <@fields.body />
                    </div>
                  </:display>
                  <:edit>
                    <@fields.body @format='edit' />
                  </:edit>
                </EditableField>
              {{else if (eq slotName 'authorBios')}}
                {{#if @model.authors.length}}
                  <div class='author-bios fade-in' {{fadeInOnView}}>
                    <h3 class='author-bios-heading'>About the author{{if
                        (eq @model.authors.length 1)
                        ''
                        's'
                      }}</h3>
                    <@fields.authors @format='embedded' />
                  </div>
                {{/if}}
              {{/if}}
            </:slot>
          </LayoutCanvas>
        </article>
      </div>
    </div>
    <style scoped>
      .blog-post-page {
        --markdown-font-size: 1rem;
        --markdown-font-family: var(--blog-font-family);
        --markdown-heading-font-family: var(--blog-font-family);
        min-height: 100%;
        background-color: var(--blog-color-bg);
        color: var(--blog-color-text);
        font-family: var(--blog-font-family);
      }

      /* Drawer floats over the article; no layout impact on .blog-post-page. */
      .post-shell {
        position: relative;
        min-height: 100%;
      }
      .post-drawer {
        position: absolute;
        top: 0;
        left: 0;
        height: 100%;
        z-index: 200;
        width: 64px;
        pointer-events: none;
      }
      .post-drawer.is-open {
        width: 280px;
      }
      .post-drawer > * {
        pointer-events: auto;
      }
      .drawer-toggle {
        position: sticky;
        top: 12px;
        margin: 12px;
        width: 40px;
        height: 40px;
        display: grid;
        place-items: center;
        background: #2c2c2c;
        color: white;
        border: none;
        border-radius: 50%;
        cursor: pointer;
        font-size: 16px;
        box-shadow: 0 1px 3px rgba(0, 0, 0, 0.18);
        transition:
          background-color 0.15s,
          transform 0.1s;
      }
      .drawer-toggle:hover {
        background: #1a1a1a;
      }
      .drawer-toggle:active {
        transform: scale(0.94);
      }
      .drawer-content {
        display: none;
        position: sticky;
        top: 64px;
        margin: 0 12px 12px;
        padding: var(--boxel-sp);
        flex-direction: column;
        gap: 8px;
        background: white;
        border: 1px solid var(--boxel-300);
        border-radius: 12px;
        box-shadow: 0 8px 24px rgba(0, 0, 0, 0.08);
        max-height: calc(100vh - 80px);
        overflow-y: auto;
      }
      .post-drawer.is-open .drawer-content {
        display: flex;
      }
      .drawer-section-label {
        font:
          700 0.7rem 'Inter',
          system-ui,
          sans-serif;
        letter-spacing: 0.15em;
        text-transform: uppercase;
        color: #121212;
        margin: 0 0 4px;
      }
      /* Publish/draft controls (inside drawer) */
      .post-controls {
        display: flex;
        flex-direction: column;
        align-items: stretch;
        gap: 10px;
      }
      .status-badge {
        display: inline-flex;
        align-items: center;
        gap: 6px;
        font:
          600 11px/1 system-ui,
          -apple-system,
          sans-serif;
        letter-spacing: 0.05em;
        text-transform: uppercase;
        padding: 4px 10px;
        border-radius: 6px;
      }
      .status-badge.is-published {
        background: rgba(34, 197, 94, 0.12);
        color: #15803d;
      }
      .status-badge.is-draft {
        background: rgba(234, 179, 8, 0.15);
        color: #a16207;
      }
      .status-dot {
        width: 6px;
        height: 6px;
        border-radius: 50%;
        background: currentColor;
      }
      .publish-btn {
        padding: 6px 14px;
        background: #2c2c2c;
        color: white;
        border: 1px solid #2c2c2c;
        border-radius: 999px;
        cursor: pointer;
        font:
          600 11px/1 system-ui,
          -apple-system,
          sans-serif;
        letter-spacing: 0.04em;
        text-transform: uppercase;
        transition:
          background-color 0.15s,
          color 0.15s,
          transform 0.1s;
      }
      .publish-btn:hover {
        background: #1a1a1a;
        border-color: #1a1a1a;
      }
      .publish-btn:active {
        transform: scale(0.96);
      }
      .publish-btn--unpublish {
        background: transparent;
        color: #2c2c2c;
      }
      .publish-btn--unpublish:hover {
        background: rgba(0, 0, 0, 0.05);
        color: #1a1a1a;
      }
      .theme-list {
        display: flex;
        flex-direction: column;
        gap: 8px;
      }
      .theme-row {
        display: flex;
        align-items: center;
        gap: 10px;
        padding: 8px;
        background: white;
        border: 2px solid var(--boxel-300);
        border-radius: 10px;
        cursor: pointer;
        transition:
          border-color 0.15s,
          box-shadow 0.15s;
      }
      .theme-row:hover {
        border-color: var(--boxel-500);
        box-shadow: 0 2px 8px rgba(0, 0, 0, 0.06);
      }
      .theme-row.is-selected {
        border-color: var(--boxel-highlight, #7b61ff);
        box-shadow: 0 0 0 2px rgba(123, 97, 255, 0.18);
      }
      .theme-radio {
        flex-shrink: 0;
        width: 18px;
        height: 18px;
        margin: 0;
        accent-color: var(--boxel-highlight, #7b61ff);
        cursor: pointer;
      }
      .theme-preview {
        flex: 1;
        min-width: 0;
        height: 110px;
        border-radius: 6px;
        overflow: hidden;
        background: #f5f5f5;
        /* The fitted card is just a visual — kill all interactivity so
           clicks fall through to the surrounding <label>. */
        pointer-events: none;
        user-select: none;
      }
      .theme-preview :deep(*) {
        pointer-events: none !important;
      }
      .theme-row--inherit {
        padding: 12px;
      }
      .theme-row__text {
        display: flex;
        flex-direction: column;
        gap: 2px;
      }
      .theme-row__name {
        font:
          700 12px/1.2 'Inter',
          sans-serif;
        color: #2c2c2c;
      }
      .theme-row__desc {
        font:
          400 11px/1.3 'Inter',
          sans-serif;
        color: var(--boxel-500);
      }
      .theme-loading {
        padding: 12px;
        font:
          400 11px 'Inter',
          sans-serif;
        color: var(--boxel-500);
        text-align: center;
      }

      /* Reading progress bar */
      .reading-progress {
        position: sticky;
        top: 0;
        left: 0;
        right: 0;
        height: 3px;
        z-index: 250;
        background: transparent;
        pointer-events: none;
      }
      .reading-progress-fill {
        height: 100%;
        width: 0%;
        background: var(--blog-color-accent);
        transition: width 0.05s linear;
      }

      /* Article canvas — wider than reading column so 2D layouts have room */
      .article-canvas {
        max-width: var(--blog-canvas-max);
        margin: 0 auto;
        padding: var(--boxel-sp-xl) var(--boxel-sp-lg) var(--boxel-sp-xxl);
      }

      /* Hero image — contained within article canvas */
      .hero-image-wrap {
        margin: 0 0 var(--boxel-sp-lg);
      }
      .hero-image :deep(.image),
      .hero-image :deep(img) {
        width: 100%;
        max-height: 520px;
        object-fit: cover;
        border-radius: var(--boxel-border-radius);
        display: block;
      }
      .hero-caption {
        max-width: var(--blog-subtitle-max);
        margin: var(--boxel-sp-xs) auto 0;
        font: 400 0.85rem/1.4 var(--blog-font-family);
        color: var(--blog-color-subtle);
        text-align: center;
      }

      /* Categories */
      .categories {
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp-xxs);
        margin-bottom: var(--boxel-sp-sm);
        justify-content: center;
      }
      .category {
        display: inline-block;
        padding: 4px 10px;
        border-radius: var(--boxel-border-radius-sm);
        font: var(--blog-font-meta);
        letter-spacing: 0.08em;
        text-transform: uppercase;
      }

      /* Headline */
      .headline-wrap {
        margin-bottom: var(--boxel-sp-sm);
        max-width: var(--blog-headline-max);
        margin-left: auto;
        margin-right: auto;
        text-align: center;
      }
      .headline {
        font: var(--blog-font-headline);
        letter-spacing: var(--blog-tracking-tight);
        margin: 0;
        color: var(--blog-color-text);
      }
      @media (max-width: 720px) {
        .headline {
          font-size: 2.5rem;
        }
      }

      /* Subtitle */
      .subtitle-wrap {
        display: block;
        width: 100%;
        max-width: var(--blog-subtitle-max);
        margin: 0 auto var(--boxel-sp-md);
        justify-self: center;
        text-align: center;
      }
      .subtitle {
        display: block;
        font: var(--blog-font-subtitle);
        color: var(--blog-color-muted);
        margin: 0 auto;
        text-align: center;
      }
      .subtitle.placeholder {
        font: 500 0.75rem var(--blog-font-family);
        font-style: normal;
        letter-spacing: 0.06em;
        text-transform: uppercase;
        color: var(--blog-color-placeholder);
        opacity: 0;
        transition: opacity 0.15s ease;
      }
      .subtitle-wrap:hover .subtitle.placeholder {
        opacity: 0.7;
      }

      /* Byline row + reading metadata */
      .byline-row {
        display: flex;
        align-items: center;
        justify-content: center;
        gap: var(--boxel-sp-xs);
        flex-wrap: wrap;
        font: 500 0.85rem var(--blog-font-family);
        letter-spacing: 0.02em;
        color: var(--blog-color-muted);
        margin: 0 auto var(--boxel-sp-xl);
        padding: var(--boxel-sp-sm) 0 var(--boxel-sp-lg);
        max-width: var(--blog-subtitle-max);
        border-bottom: 1px solid var(--blog-color-divider);
        text-align: center;
      }
      .byline {
        display: inline-flex;
        align-items: center;
        gap: 6px;
        flex-wrap: wrap;
      }
      .byline-prefix {
        color: var(--blog-color-subtle);
        font-weight: 400;
      }
      .author {
        display: contents;
      }
      .byline-sep {
        color: var(--blog-color-placeholder);
      }
      .pub-date,
      .read-time {
        color: var(--blog-color-muted);
      }

      /* Body — narrower reading column for comfort */
      .body-wrap {
        max-width: var(--blog-reading-max);
        margin: 0 auto var(--boxel-sp-xl);
        --markdown-paragraph-spacing: var(--boxel-sp-lg);
      }
      .body-zoomed {
        min-height: 60vh;
      }
      .body-zoomed :deep(.field-edit) {
        min-height: 60vh;
      }
      .article-body {
        font: var(--blog-font-body);
        color: var(--blog-color-body);
      }
      .article-body :deep(p) {
        margin: 0 0 1.4em;
      }
      .article-body :deep(h2) {
        font: var(--blog-font-h2);
        letter-spacing: var(--blog-tracking-tighter);
        margin: 2em 0 0.6em;
        color: var(--blog-color-text);
      }
      .article-body :deep(h3) {
        font: var(--blog-font-h3);
        letter-spacing: -0.005em;
        margin: 1.6em 0 0.4em;
        color: var(--blog-color-text);
      }
      .article-body :deep(a) {
        color: var(--blog-color-text);
        text-decoration: underline;
        text-decoration-color: var(--blog-color-accent);
        text-decoration-thickness: 2px;
        text-underline-offset: 3px;
      }
      .article-body :deep(p:first-of-type)::first-letter {
        font: 800 4.2rem/0.9 var(--blog-font-family);
        float: left;
        margin: 6px 12px 0 0;
        color: var(--blog-color-text);
      }
      .article-body :deep(blockquote) {
        position: relative;
        font: var(--blog-font-pullquote);
        letter-spacing: var(--blog-tracking-tighter);
        color: var(--blog-color-text);
        max-width: 540px;
        margin: var(--boxel-sp-xl) auto;
        padding: 0 0 0 var(--boxel-sp-lg);
        border-left: 3px solid var(--blog-color-accent);
        text-align: left;
      }
      .article-body :deep(blockquote p) {
        margin: 0 0 0.4em;
      }

      /* Author bios */
      .author-bios {
        max-width: var(--blog-subtitle-max);
        margin: var(--boxel-sp-xxl) auto 0;
        padding-top: var(--boxel-sp-lg);
        border-top: 1px solid var(--blog-color-divider);
      }
      .author-bios-heading {
        font: var(--blog-font-eyebrow);
        letter-spacing: var(--blog-tracking-eyebrow);
        text-transform: uppercase;
        color: var(--blog-color-faint);
        margin: 0 0 var(--boxel-sp-sm);
      }

      /* Related posts */
      .related {
        max-width: 1100px;
        margin: var(--boxel-sp-xxl) auto 0;
        padding: var(--boxel-sp-xl) var(--boxel-sp-lg) var(--boxel-sp-xxl);
        border-top: 1px solid var(--boxel-300);
      }
      .related-heading {
        font:
          800 2rem/1.1 'Playfair Display',
          serif;
        margin: 0 0 var(--boxel-sp-lg);
        color: #121212;
      }
      .related-grid {
        display: grid;
        grid-template-columns: repeat(3, 1fr);
        gap: var(--boxel-sp-lg);
      }
      .related-card {
        aspect-ratio: 5 / 6;
        background: white;
        border-radius: 8px;
        overflow: hidden;
        box-shadow: 0 1px 3px rgba(0, 0, 0, 0.06);
        transition:
          transform 0.2s ease,
          box-shadow 0.2s ease;
      }
      .related-card:hover {
        transform: translateY(-2px);
        box-shadow: 0 6px 18px rgba(0, 0, 0, 0.1);
      }
      .related-loading {
        grid-column: 1 / -1;
        padding: var(--boxel-sp-lg);
        text-align: center;
        color: var(--boxel-500);
      }
      @media (max-width: 900px) {
        .related-grid {
          grid-template-columns: repeat(2, 1fr);
        }
      }
      @media (max-width: 600px) {
        .related-grid {
          grid-template-columns: 1fr;
        }
      }

      /* Scroll-triggered fade-ins */
      .fade-in {
        opacity: 0;
        transform: translateY(8px);
        transition:
          opacity 0.5s ease,
          transform 0.5s ease;
      }
      .fade-in.is-in-view {
        opacity: 1;
        transform: translateY(0);
      }
      @media (prefers-reduced-motion: reduce) {
        .fade-in {
          opacity: 1;
          transform: none;
          transition: none;
        }
      }

      h1,
      h2,
      h3,
      h4,
      h5,
      h6 {
        font-family: var(--blog-font-family);
      }
    </style>
  </template>
}

export class BlogPost extends CardDef {
  static displayName = 'Blog Post';
  static icon = BlogIcon;
  static prefersWideFormat = true;
  @field headline = contains(StringField);
  @field cardTitle = contains(StringField, {
    computeVia: function (this: BlogPost) {
      return this.headline?.length
        ? this.headline
        : `Untitled ${this.constructor.displayName}`;
    },
  });
  @field cardDescription = contains(StringField);
  @field slug = contains(StringField);
  @field body = contains(RichMarkdownField);
  @field layout = contains(StringField);
  @field published = contains(BooleanField);
  @field authors = linksToMany(Author);
  @field publishDate = contains(DateTimeField);
  @field status = contains(Status, {
    computeVia: function (this: BlogPost) {
      return this.published ? 'Published' : 'Draft';
    },
  });
  @field featuredImage = contains(FeaturedImageField);
  @field categories = linksToMany(BlogCategory);
  @field lastUpdated = contains(DateTimeField, {
    computeVia: function (this: BlogPost) {
      let lastModified = getCardMeta(this, 'lastModified');
      return lastModified ? new Date(lastModified * 1000) : undefined;
    },
  });
  @field wordCount = contains(NumberField, {
    computeVia: function (this: BlogPost) {
      const raw = (this.body as any)?.content ?? this.body;
      if (!raw) return 0;
      const text = String(raw)
        .replace(/```[\s\S]*?```/g, '')
        .replace(/`[^`]*`/g, '')
        .replace(/[#*_>-]/g, '')
        .replace(/\[([^\]]*)\]\([^)]*\)/g, '$1')
        .replace(/\s+/g, ' ');
      return text.trim().split(' ').filter(Boolean).length;
    },
  });
  @field editors = linksToMany(User);

  get formattedDatePublished() {
    if (this.status === 'Published' && this.publishDate) {
      return formatDatetime(this.publishDate, {
        year: 'numeric',
        month: 'short',
        day: 'numeric',
      });
    }
    return undefined;
  }

  get datePublishedIsoTimestamp() {
    if (this.status === 'Published' && this.publishDate) {
      return this.publishDate.toISOString();
    }
    return undefined;
  }

  get formattedLastUpdated() {
    return this.lastUpdated
      ? formatDatetime(this.lastUpdated, {
          year: 'numeric',
          month: 'short',
          day: 'numeric',
        })
      : undefined;
  }

  get lastUpdatedIsoTimestamp() {
    return this.lastUpdated ? this.lastUpdated.toISOString() : undefined;
  }

  get formattedAuthors() {
    const authors = this.authors ?? [];
    if (authors.length === 0) return undefined;

    const titles = authors.map((author) => author.cardTitle);

    if (titles.length === 2) {
      return `${titles[0]} and ${titles[1]}`;
    }

    return titles.length > 2
      ? `${titles.slice(0, -1).join(', ')}, and ${titles.at(-1)}`
      : titles[0];
  }

  static embedded = EmbeddedTemplate;
  static fitted = FittedTemplate;
  static isolated = IsolatedBlogPost;
}
