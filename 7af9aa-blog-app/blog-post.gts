import DateTimeField from '@cardstack/base/datetime';
import StringField from '@cardstack/base/string';
import RichMarkdownField from '@cardstack/base/rich-markdown';
import BooleanField from '@cardstack/base/boolean';
import NumberField from '@cardstack/base/number';
import {
  CardDef,
  field,
  contains,
  Component,
  getCardMeta,
  linksToMany,
  realmURL,
} from '@cardstack/base/card-api';
import {
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
import { bool, eq, or } from '@cardstack/boxel-ui/helpers';
import { Button } from '@cardstack/boxel-ui/components';

import {
  buildBlogThemeCss,
  formatDatetime,
  onClickOutside,
} from './blog-defaults';
import { modifier } from 'ember-modifier';

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
        padding: 0.1875rem var(--boxel-sp-xxxs);
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
        min-width: 6.25rem;
        min-height: 1.8125rem;
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
        color: var(--subtle-foreground);
      }

      .categories {
        margin-top: -1.6875rem;
        height: 1.25rem;
        margin-left: 0.4375rem;
        display: none;
        overflow: hidden;
      }

      .category {
        height: 1.25rem;
        padding: 0.1875rem 0.25rem;
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
            'img' 5.75rem
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
            'img' 5.75rem
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
            'img' 5rem
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
            'img' 4.25rem
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
            'img' 3.5625rem
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
          width: 2.8125rem;
          height: 2.8125rem;
          border-radius: 0.3125rem;
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
          width: 2.8125rem;
          height: 2.8125rem;
          border-radius: 0.3125rem;
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
          font-weight: 600;
          font-size: var(--boxel-font-size-xs);
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
  get hasLinkedTheme(): boolean {
    return Boolean((this.args.model as any)?.cardInfo?.theme);
  }

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
      if (this.isDestroying || this.isDestroyed) return;
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
          module: rri('@cardstack/base/style-reference'),
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
      if (this.isDestroying || this.isDestroyed) {
        clearInterval(poll);
      } else if (resource.card) {
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

  get currentCardId(): string | undefined {
    return (this.args.model as any)?.id;
  }

  get themeStyle() {
    return htmlSafe(
      buildBlogThemeCss((this.args.model as any)?.cardInfo?.theme),
    );
  }

  <template>
    {{! runtime-built theme CSS (defaults + linked theme) must be
        un-scoped so .blog-scope descendants can read it }}
    {{! template-lint-disable require-scoped-style }}
    <style>
      {{this.themeStyle}}
    </style>
    <div
      class='post-shell blog-scope
        {{unless this.hasLinkedTheme "blog-default-theme"}}'
    >
      <div class='reading-progress' aria-hidden='true'>
        <div class='reading-progress-fill' {{scrollProgress}}></div>
      </div>
      {{#if this.canEdit}}
        <aside
          class='post-drawer {{if this.drawerOpen "is-open"}}'
          {{onClickOutside this.maybeCloseDrawer}}
        >
          <Button
            @size='auto'
            @kind='text-only'
            class='drawer-toggle'
            {{on 'click' this.toggleDrawer}}
            aria-label={{if this.drawerOpen 'Close panel' 'Open panel'}}
            aria-expanded='{{if this.drawerOpen "true" "false"}}'
          >
            {{#if this.drawerOpen}}✕{{else}}☰{{/if}}
          </Button>
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
              <Button
                @size='auto'
                @kind='text-only'
                class='publish-btn
                  {{if @model.published "publish-btn--unpublish"}}'
                {{on 'click' this.togglePublished}}
              >
                {{if @model.published 'Unpublish' 'Publish'}}
              </Button>
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
                {{#if (or (bool @model.featuredImage.imageUrl) this.canEdit)}}
                  <EditableField
                    @isEditing={{eq this.editingField 'featuredImage'}}
                    @canEdit={{this.canEdit}}
                    @onEdit={{fn this.setEditing 'featuredImage'}}
                    @onBlur={{this.onFieldBlur}}
                    class='hero-image-wrap fade-in'
                    {{fadeInOnView}}
                  >
                    <:display>
                      {{#if @model.featuredImage.imageUrl}}
                        <@fields.featuredImage class='hero-image' />
                      {{else}}
                        <p class='placeholder'>+ cover image</p>
                      {{/if}}
                    </:display>
                    <:edit>
                      <@fields.featuredImage @format='edit' />
                    </:edit>
                  </EditableField>
                {{/if}}
              {{else if (eq slotName 'categories')}}
                <EditableField
                  @isEditing={{eq this.editingField 'categories'}}
                  @canEdit={{this.canEdit}}
                  @onEdit={{fn this.setEditing 'categories'}}
                  @onBlur={{this.onFieldBlur}}
                  class='categories-wrap'
                >
                  <:display>
                    {{#if @model.categories.length}}
                      <div class='categories'>
                        {{#each @model.categories as |category|}}
                          <div
                            class='category'
                            style={{categoryStyle category}}
                          >
                            {{category.shortName}}
                          </div>
                        {{/each}}
                      </div>
                    {{else if this.canEdit}}
                      <p class='placeholder'>+ categories</p>
                    {{/if}}
                  </:display>
                  <:edit>
                    <@fields.categories @format='edit' />
                  </:edit>
                </EditableField>
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
                  <EditableField
                    @isEditing={{eq this.editingField 'authors'}}
                    @canEdit={{this.canEdit}}
                    @onEdit={{fn this.setEditing 'authors'}}
                    @onBlur={{this.onFieldBlur}}
                    class='byline-wrap'
                  >
                    <:display>
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
                      {{else if this.canEdit}}
                        <span class='byline placeholder'>+ author</span>
                      {{/if}}
                    </:display>
                    <:edit>
                      <@fields.authors @format='edit' />
                    </:edit>
                  </EditableField>
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
                    {{#if @model.body}}
                      <div class='article-body'>
                        <@fields.body />
                      </div>
                    {{else if this.canEdit}}
                      <p class='placeholder'>+ write your story…</p>
                    {{/if}}
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
        --markdown-font-family: var(
          --blog-font-family,
          'Inter',
          system-ui,
          sans-serif
        );
        --markdown-heading-font-family: var(
          --blog-font-family,
          'Inter',
          system-ui,
          sans-serif
        );
        min-height: 100%;
        background-color: var(--card);
        color: var(--foreground);
        font-family: var(--blog-font-family, 'Inter', system-ui, sans-serif);
      }

      /* Drawer floats over the article; no layout impact on .blog-post-page. */
      /* Default semantic palette when NO theme is linked — pins the tokens
         the .blog-scope chain reads. A linked theme (or the parent BlogApp's
         injected site theme --blog-* overrides) wins when present. */
      .blog-default-theme {
        color: var(--card-foreground);
      }

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
        width: 4rem;
        pointer-events: none;
      }
      .post-drawer.is-open {
        width: 17.5rem;
      }
      .post-drawer > * {
        pointer-events: auto;
      }
      .drawer-toggle {
        position: sticky;
        top: 0.75rem;
        margin: 0.75rem;
        width: 2.5rem;
        height: 2.5rem;
        display: grid;
        place-items: center;
        background-color: var(--card);
        color: var(--card-foreground);
        border: none;
        border-radius: 50%;
        cursor: pointer;
        font-size: 1rem;
        box-shadow: 0 1px 3px
          color-mix(in oklch, var(--foreground) 18%, transparent);
        transition:
          background-color 0.15s,
          transform 0.1s;
      }
      .drawer-toggle:hover {
        background-color: var(--card);
        color: var(--card-foreground);
      }
      .drawer-toggle:active {
        transform: scale(0.94);
      }
      .drawer-content {
        display: none;
        position: sticky;
        top: 4rem;
        margin: 0 0.75rem 0.75rem;
        padding: var(--boxel-sp);
        flex-direction: column;
        gap: 0.5rem;
        background-color: var(--card);
        color: var(--card-foreground);
        border: 1px solid var(--boxel-300);
        border-radius: 0.75rem;
        box-shadow: 0 8px 24px
          color-mix(in oklch, var(--foreground) 8%, transparent);
        max-height: calc(100vh - 5rem);
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
        color: var(--foreground);
        margin: 0 0 0.25rem;
      }
      /* Publish/draft controls (inside drawer) */
      .post-controls {
        display: flex;
        flex-direction: column;
        align-items: stretch;
        gap: 0.625rem;
      }
      .status-badge {
        display: inline-flex;
        align-items: center;
        gap: 0.375rem;
        font:
          600 0.6875rem/1 system-ui,
          -apple-system,
          sans-serif;
        letter-spacing: 0.05em;
        text-transform: uppercase;
        padding: 0.25rem 0.625rem;
        border-radius: 0.375rem;
      }
      .status-badge.is-published {
        background-color: color-mix(in oklch, var(--success) 12%, transparent);
        color: var(--success-ink);
      }
      .status-badge.is-draft {
        background-color: color-mix(in oklch, var(--warning) 15%, transparent);
        color: var(--warning-ink);
      }
      .status-dot {
        width: 0.375rem;
        height: 0.375rem;
        border-radius: 50%;
        background-color: currentColor;
      }
      .publish-btn {
        padding: 0.375rem 0.875rem;
        background-color: var(--card);
        color: var(--card-foreground);
        border: 1px solid var(--border-strong);
        border-radius: 62.4375rem;
        cursor: pointer;
        font:
          600 0.6875rem/1 system-ui,
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
        background-color: var(--card);
        color: var(--card-foreground);
        border-color: var(--border-strong);
      }
      .publish-btn:active {
        transform: scale(0.96);
      }
      .publish-btn--unpublish {
        background-color: transparent;
        color: var(--foreground);
      }
      .publish-btn--unpublish:hover {
        background-color: color-mix(in oklch, var(--tooltip) 5%, transparent);
        color: var(--foreground);
      }
      .theme-list {
        display: flex;
        flex-direction: column;
        gap: 0.5rem;
      }
      .theme-row {
        display: flex;
        align-items: center;
        gap: 0.625rem;
        padding: 0.5rem;
        background-color: var(--card);
        color: var(--card-foreground);
        border: 2px solid var(--boxel-300);
        border-radius: 0.625rem;
        cursor: pointer;
        transition:
          border-color 0.15s,
          box-shadow 0.15s;
      }
      .theme-row:hover {
        border-color: var(--boxel-500);
        box-shadow: 0 2px 8px
          color-mix(in oklch, var(--foreground) 6%, transparent);
      }
      .theme-row.is-selected {
        border-color: var(--primary);
        box-shadow: 0 0 0 2px
          color-mix(in oklch, var(--primary) 18%, transparent);
      }
      .theme-radio {
        flex-shrink: 0;
        width: 1.125rem;
        height: 1.125rem;
        margin: 0;
        accent-color: var(--primary);
        cursor: pointer;
      }
      .theme-preview {
        flex: 1;
        min-width: 0;
        height: 6.875rem;
        border-radius: 0.375rem;
        overflow: hidden;
        background-color: var(--card);
        color: var(--card-foreground);
        /* The fitted card is just a visual — kill all interactivity so
           clicks fall through to the surrounding <label>. */
        pointer-events: none;
        user-select: none;
      }
      .theme-preview :deep(*) {
        pointer-events: none !important;
      }
      .theme-row--inherit {
        padding: 0.75rem;
      }
      .theme-row__text {
        display: flex;
        flex-direction: column;
        gap: 2px;
      }
      .theme-row__name {
        font:
          700 0.75rem/1.2 'Inter',
          sans-serif;
        color: var(--foreground);
      }
      .theme-row__desc {
        font:
          400 0.6875rem/1.3 'Inter',
          sans-serif;
        color: var(--boxel-500);
      }
      .theme-loading {
        padding: 0.75rem;
        font:
          400 0.6875rem 'Inter',
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
        height: 0.1875rem;
        z-index: 250;
        background-color: transparent;
        pointer-events: none;
      }
      .reading-progress-fill {
        height: 100%;
        width: 0%;
        background-color: var(--primary);
        color: var(--primary-foreground);
        transition: width 0.05s linear;
      }

      /* Article canvas — wider than reading column so 2D layouts have room */
      .article-canvas {
        max-width: var(--blog-canvas-max, 68.75rem);
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
        max-height: 32.5rem;
        object-fit: cover;
        border-radius: var(--boxel-border-radius);
        display: block;
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
        padding: 0.25rem 0.625rem;
        border-radius: var(--boxel-border-radius-sm);
        font: var(--blog-font-meta, 600 0.7rem/1 sans-serif);
        letter-spacing: 0.08em;
        text-transform: uppercase;
      }

      /* Headline */
      .headline-wrap {
        margin-bottom: var(--boxel-sp-sm);
        max-width: var(--blog-headline-max, 53.75rem);
        margin-left: auto;
        margin-right: auto;
        text-align: center;
      }
      .headline {
        font: var(--blog-font-headline, 800 4rem/1.05 sans-serif);
        letter-spacing: var(--blog-tracking-tight, -0.02em);
        margin: 0;
        color: var(--foreground);
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
        max-width: var(--blog-subtitle-max, 45rem);
        margin: 0 auto var(--boxel-sp-md);
        justify-self: center;
        text-align: center;
      }
      .subtitle {
        display: block;
        font: var(--blog-font-subtitle, 400 1.25rem/1.45 sans-serif);
        color: var(--muted-foreground);
        margin: 0 auto;
        text-align: center;
      }
      /* Generic add-affordance placeholder (cover image, body, categories,
         byline) — quiet until the region is hovered */
      .placeholder {
        font: 500 0.75rem var(--blog-font-family, sans-serif);
        letter-spacing: 0.06em;
        text-transform: uppercase;
        color: var(--subtle-foreground);
        opacity: 0;
        transition: opacity 0.15s ease;
        margin: 0;
      }
      .hero-image-wrap:hover .placeholder,
      .categories-wrap:hover .placeholder,
      .byline-wrap:hover .placeholder,
      .body-wrap:hover .placeholder {
        opacity: 0.7;
        cursor: pointer;
      }
      .subtitle.placeholder {
        font: 500 0.75rem
          var(--blog-font-family, 'Inter', system-ui, sans-serif);
        font-style: normal;
        letter-spacing: 0.06em;
        text-transform: uppercase;
        color: var(--subtle-foreground);
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
        font: 500 0.85rem
          var(--blog-font-family, 'Inter', system-ui, sans-serif);
        letter-spacing: 0.02em;
        color: var(--muted-foreground);
        margin: 0 auto var(--boxel-sp-xl);
        padding: var(--boxel-sp-sm) 0 var(--boxel-sp-lg);
        max-width: var(--blog-subtitle-max, 45rem);
        border-bottom: 1px solid var(--border);
        text-align: center;
      }
      .byline {
        display: inline-flex;
        align-items: center;
        gap: 0.375rem;
        flex-wrap: wrap;
      }
      .byline-prefix {
        color: var(--muted-foreground);
        font-weight: 400;
      }
      .author {
        display: contents;
      }
      .byline-sep {
        color: var(--subtle-foreground);
      }
      .pub-date,
      .read-time {
        color: var(--muted-foreground);
      }

      /* Body — narrower reading column for comfort */
      .body-wrap {
        max-width: var(--blog-reading-max, 42.5rem);
        margin: 0 auto var(--boxel-sp-xl);
      }
      .body-zoomed {
        min-height: 60vh;
      }
      .body-zoomed :deep(.field-edit) {
        min-height: 60vh;
      }
      .article-body {
        font: var(--blog-font-body, 400 1.0625rem/1.7 sans-serif);
        color: var(--foreground);
      }
      .article-body :deep(p) {
        margin: 0 0 1.4em;
      }
      .article-body :deep(h2) {
        font: var(--blog-font-h2, 800 1.75rem/1.2 sans-serif);
        letter-spacing: var(--blog-tracking-tighter, -0.01em);
        margin: 2em 0 0.6em;
        color: var(--foreground);
      }
      .article-body :deep(h3) {
        font: var(--blog-font-h3, 700 1.2rem/1.3 sans-serif);
        letter-spacing: -0.005em;
        margin: 1.6em 0 0.4em;
        color: var(--foreground);
      }
      .article-body :deep(a) {
        color: var(--foreground);
        text-decoration: underline;
        text-decoration-color: var(--primary-ink);
        text-decoration-thickness: 2px;
        text-underline-offset: 3px;
      }
      .article-body :deep(p:first-of-type)::first-letter {
        font: 800 4.2rem/0.9
          var(--blog-font-family, 'Inter', system-ui, sans-serif);
        float: left;
        margin: 0.375rem 0.75rem 0 0;
        color: var(--foreground);
      }
      .article-body :deep(blockquote) {
        position: relative;
        font: var(--blog-font-pullquote, 600 1.5rem/1.35 sans-serif);
        letter-spacing: var(--blog-tracking-tighter, -0.01em);
        color: var(--foreground);
        max-width: 33.75rem;
        margin: var(--boxel-sp-xl) auto;
        padding: 0 0 0 var(--boxel-sp-lg);
        border-left: 3px solid var(--primary);
        text-align: left;
      }
      .article-body :deep(blockquote p) {
        margin: 0 0 0.4em;
      }

      /* Author bios */
      .author-bios {
        max-width: var(--blog-subtitle-max, 45rem);
        margin: var(--boxel-sp-xxl) auto 0;
        padding-top: var(--boxel-sp-lg);
        border-top: 1px solid var(--border);
      }
      .author-bios-heading {
        font: var(--blog-font-eyebrow, 700 0.7rem/1 sans-serif);
        letter-spacing: var(--blog-tracking-eyebrow, 0.18em);
        text-transform: uppercase;
        color: var(--subtle-foreground);
        margin: 0 0 var(--boxel-sp-sm);
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
        font-family: var(--blog-font-family, 'Inter', system-ui, sans-serif);
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
  @field authors = linksToMany(Author, { searchable: true });
  @field publishDate = contains(DateTimeField);
  @field status = contains(Status, {
    computeVia: function (this: BlogPost) {
      return this.published ? 'Published' : 'Draft';
    },
  });
  @field featuredImage = contains(FeaturedImageField);
  @field categories = linksToMany(BlogCategory, { searchable: true });
  @field lastUpdated = contains(DateTimeField, {
    computeVia: function (this: BlogPost) {
      let lastModified = getCardMeta(this, 'lastModified');
      return lastModified ? new Date(lastModified * 1000) : undefined;
    },
  });
  @field wordCount = contains(NumberField, {
    computeVia: function (this: BlogPost) {
      const raw = (this.body as any)?.content ?? this.body;
      // only count actual markdown text — a non-string body (e.g. a field
      // object without .content) would stringify to "[object Object]" and
      // produce a bogus count
      if (!raw || typeof raw !== 'string') return 0;
      const text = raw
        .replace(/```[\s\S]*?```/g, '')
        .replace(/`[^`]*`/g, '')
        .replace(/[#*_>-]/g, '')
        .replace(/\[([^\]]*)\]\([^)]*\)/g, '$1')
        .replace(/\s+/g, ' ');
      return text.trim().split(' ').filter(Boolean).length;
    },
  });

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
    // A nested render can hand us author links that haven't resolved yet, so
    // the array has holes until they load.
    const titles = (this.authors ?? [])
      .map((author) => author?.cardTitle)
      .filter(Boolean);
    if (titles.length === 0) return undefined;

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
