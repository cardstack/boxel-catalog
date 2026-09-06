import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { action } from '@ember/object';
import { htmlSafe } from '@ember/template';
import { tracked } from '@glimmer/tracking';
import { Component, realmURL } from 'https://cardstack.com/base/card-api';
import {
  codeRef,
  rri,
  type Query,
  searchEntryWireQueryFromQuery,
  type SearchEntryWireQuery,
} from '@cardstack/runtime-common';
import { buildBlogThemeCss, onClickOutside } from '../blog-defaults';
import { eq } from '@cardstack/boxel-ui/helpers';
import { BlogSiteView } from './site-view';
import { BlogAppTemplate } from './admin-template';
import type { BlogApp } from '../blog-app';

// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
const here: string = import.meta.url;

export class IsolatedPortal extends Component<typeof BlogApp> {
  get hasLinkedTheme(): boolean {
    return Boolean((this.args.model as any)?.cardInfo?.theme);
  }

  get themeSearchQuery(): SearchEntryWireQuery {
    return {
      ...searchEntryWireQueryFromQuery(this.themeQuery),
      realms: this.realmHrefs,
    };
  }
  get libraryPostsSearchQuery(): SearchEntryWireQuery {
    return {
      ...searchEntryWireQueryFromQuery(this.libraryPostsQuery),
      realms: this.realmHrefs,
    };
  }
  @tracked viewMode: 'site' | 'admin' = 'site';
  @tracked drawerOpen = false;
  @tracked searchQuery = '';
  @tracked private _pendingThemeUrl: string | undefined = undefined;

  @action toggleViewMode() {
    this.viewMode = this.viewMode === 'site' ? 'admin' : 'site';
  }

  @action toggleDrawer() {
    this.drawerOpen = !this.drawerOpen;
  }

  @action closeDrawer() {
    this.drawerOpen = false;
  }

  @action maybeCloseDrawer() {
    if (this.drawerOpen) this.drawerOpen = false;
  }

  @action onSearchInput(event: Event) {
    this.searchQuery = (event.target as HTMLInputElement).value;
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

  @action onLibraryDragStart(url: string, event: DragEvent) {
    if (event.dataTransfer) {
      event.dataTransfer.setData('text/uri-list', url);
      event.dataTransfer.setData('text/plain', url);
      event.dataTransfer.effectAllowed = 'copyMove';
    }
  }

  get realmHrefs(): string[] {
    const u = this.args.model[realmURL];
    return u ? [u.href] : [];
  }

  get libraryPostsQuery(): Query {
    const on = codeRef(here, '../blog-post', 'BlogPost');
    const sort = [{ on, by: 'publishDate', direction: 'desc' as const }];
    const q = this.searchQuery.trim();
    if (!q) {
      return { filter: { type: on }, sort };
    }
    return {
      filter: {
        every: [
          { type: on },
          {
            any: [{ matches: q }, { contains: { cardTitle: q } }],
          },
        ],
      },
      sort,
    };
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
      class='portal blog-scope
        {{unless this.hasLinkedTheme "blog-default-theme"}}'
    >
      <aside
        class='drawer {{if this.drawerOpen "is-open"}}'
        {{onClickOutside this.maybeCloseDrawer}}
      >
        <button
          type='button'
          class='drawer-toggle'
          {{on 'click' this.toggleDrawer}}
          aria-label={{if this.drawerOpen 'Close library' 'Open library'}}
          aria-expanded='{{if this.drawerOpen "true" "false"}}'
        >
          {{#if this.drawerOpen}}✕{{else}}☰{{/if}}
        </button>

        <div class='drawer-content'>
          <button
            type='button'
            class='view-toggle'
            {{on 'click' this.toggleViewMode}}
          >
            {{#if (eq this.viewMode 'site')}}
              View admin
            {{else}}
              View site
            {{/if}}
          </button>

          <section class='lib-section theme-section' aria-label='Theme picker'>
            <h3 class='lib-section-label'>Theme</h3>
            <p class='lib-section-hint'>Applies to the whole site and to any
              post that doesn't define its own.</p>
            <div class='theme-list' role='radiogroup' aria-label='Site theme'>
              <label
                class='theme-row theme-row--inherit
                  {{if (this.isThemeSelected "") "is-selected"}}'
              >
                <input
                  type='radio'
                  name='blog-site-theme'
                  class='theme-radio'
                  checked={{this.isThemeSelected ''}}
                  {{on 'change' (fn this.onThemeRadioChange null)}}
                />
                <span class='theme-row__text'>
                  <span class='theme-row__name'>No theme</span>
                  <span class='theme-row__desc'>Use built-in defaults</span>
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
                        name='blog-site-theme'
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
          </section>

          <section class='lib-section' aria-label='Post library'>
            <h3 class='lib-section-label'>All posts</h3>
            <p class='lib-section-hint'>Drag a card to place it</p>
            <input
              type='search'
              class='lib-search'
              aria-label='Search posts'
              placeholder='Search posts…'
              value={{this.searchQuery}}
              {{on 'input' this.onSearchInput}}
            />
            <@context.searchResultsComponent
              @query={{this.libraryPostsSearchQuery}}
              as |results|
            >
              {{#if results.entries.length}}
                <div class='lib-list'>
                  {{#each results.entries key='id' as |card|}}
                    <div
                      class='lib-card'
                      draggable='true'
                      {{on 'dragstart' (fn this.onLibraryDragStart card.id)}}
                      title='Drag {{card.id}}'
                    >
                      <card.component />
                    </div>
                  {{/each}}
                </div>
              {{else if results.isLoading}}
                <div class='lib-loading'>Loading posts…</div>
              {{else}}
                <div class='lib-loading'>No posts found{{if
                    this.searchQuery
                    ' for this search'
                    ' — create one from Admin mode'
                  }}.</div>
              {{/if}}
            </@context.searchResultsComponent>
          </section>
        </div>
      </aside>

      <main class='portal-main'>
        {{#if (eq this.viewMode 'site')}}
          {{! @glint-expect-error sub-component reuses BlogApp Component sig but isn't a format-template, so it lacks fieldName }}
          <BlogSiteView
            @model={{@model}}
            @fields={{@fields}}
            @set={{@set}}
            @context={{@context}}
          />
        {{else}}
          {{! @glint-expect-error sub-component reuses BlogApp Component sig but isn't a format-template, so it lacks fieldName }}
          <BlogAppTemplate
            @model={{@model}}
            @fields={{@fields}}
            @set={{@set}}
            @context={{@context}}
          />
        {{/if}}
      </main>
    </div>
    <style scoped>
      /* Drawer floats over the page; no layout impact on .portal-main. */
      /* Default semantic palette when NO theme is linked — pins the tokens
         the .blog-scope chain reads, so app-level ambient values can't
         restyle the blog. A linked theme omits this class. */
      .blog-default-theme {
        --background: #ffffff;
        --foreground: #121212;
        --card: #ffffff;
        --card-foreground: #121212;
        --muted: #f3f4f6;
        --muted-foreground: #6b7280;
        --border: #e5e7eb;
        --primary: #7b61ff;
        --primary-foreground: #ffffff;
        --font-sans: 'Inter', system-ui, -apple-system, sans-serif;
        --radius: 12px;
      }

      .portal {
        position: relative;
        min-height: 100%;
        background: var(--blog-color-bg, #fafafa);
        color: var(--blog-color-text, #121212);
      }
      .drawer {
        position: absolute;
        top: 0;
        left: 0;
        height: 100%;
        z-index: 200;
        width: 64px;
        pointer-events: none;
      }
      .drawer.is-open {
        width: 320px;
      }
      .drawer > * {
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
        gap: var(--boxel-sp);
        background: white;
        border: 1px solid #ececec;
        border-radius: 12px;
        box-shadow: 0 8px 24px rgba(0, 0, 0, 0.08);
        max-height: calc(100vh - 80px);
        overflow-y: auto;
      }
      .drawer.is-open .drawer-content {
        display: flex;
      }
      .portal-main {
        min-width: 0;
      }
      .view-toggle {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        gap: 6px;
        padding: 9px 16px;
        background: #2c2c2c;
        color: white;
        border: none;
        border-radius: 999px;
        cursor: pointer;
        font:
          600 12px/1 system-ui,
          -apple-system,
          sans-serif;
        letter-spacing: 0.5px;
        text-transform: uppercase;
        box-shadow: 0 1px 3px rgba(0, 0, 0, 0.15);
        transition:
          background-color 0.15s,
          transform 0.1s;
      }
      .view-toggle:hover {
        background: #1a1a1a;
      }
      .view-toggle:active {
        transform: scale(0.97);
      }

      .lib-section {
        display: flex;
        flex-direction: column;
        gap: 8px;
      }
      .lib-section-label {
        font:
          700 0.7rem 'Inter',
          system-ui,
          sans-serif;
        letter-spacing: 0.15em;
        text-transform: uppercase;
        color: #121212;
        margin: 0;
      }
      .lib-section-hint {
        margin: 0;
        font:
          400 0.75rem 'Inter',
          system-ui,
          sans-serif;
        color: #999;
      }

      .theme-section {
        padding-bottom: 12px;
        border-bottom: 1px solid var(--boxel-300);
        margin-bottom: 4px;
      }
      .theme-list {
        display: flex;
        flex-direction: column;
        gap: 8px;
        margin-top: 4px;
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
      .lib-loading {
        font:
          600 12px/1 'Inter',
          sans-serif;
        color: var(--boxel-500);
        padding: 8px 0;
      }
      .lib-search {
        width: 100%;
        padding: 8px 12px;
        border: 1px solid #d3d6da;
        border-radius: 8px;
        font:
          500 0.9rem/1 'Inter',
          sans-serif;
        outline: none;
        transition: border-color 0.15s;
        box-sizing: border-box;
        background: white;
        color: #121212;
      }
      .lib-search:focus {
        border-color: var(--boxel-highlight, #7b61ff);
      }
      .lib-search::placeholder {
        color: #999;
      }
      .lib-list {
        display: flex;
        flex-direction: column;
        gap: 8px;
      }
      .lib-card {
        height: 76px;
        border: 1px solid #ececec;
        border-radius: 10px;
        overflow: hidden;
        cursor: grab;
        background: white;
        transition:
          border-color 0.12s,
          box-shadow 0.15s,
          transform 0.08s;
      }
      .lib-card:hover {
        border-color: var(--boxel-highlight, #7b61ff);
        box-shadow: 0 3px 10px rgba(0, 0, 0, 0.08);
      }
      .lib-card:active {
        cursor: grabbing;
        transform: scale(0.98);
      }
      .lib-card :deep(.card) {
        height: 100% !important;
        min-height: 0 !important;
        max-width: 100% !important;
        width: 100%;
        background: transparent;
        box-shadow: none !important;
        border: none;
      }
    </style>
  </template>
}
