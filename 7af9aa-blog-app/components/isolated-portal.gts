import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { action } from '@ember/object';
import { htmlSafe } from '@ember/template';
import { tracked } from '@glimmer/tracking';
import { Component, realmURL } from '@cardstack/base/card-api';
import {
  codeRef,
  rri,
  type Query,
  searchEntryWireQueryFromQuery,
  type SearchEntryWireQuery,
} from '@cardstack/runtime-common';
import { buildBlogThemeCss, onClickOutside } from '../blog-defaults';
import { Button, BoxelInput } from '@cardstack/boxel-ui/components';
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

  @action onSearchInput(value: string) {
    this.searchQuery = value;
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
        <Button
          @size='auto'
          @kind='text-only'
          class='drawer-toggle'
          {{on 'click' this.toggleDrawer}}
          aria-label={{if this.drawerOpen 'Close library' 'Open library'}}
          aria-expanded='{{if this.drawerOpen "true" "false"}}'
        >
          {{#if this.drawerOpen}}✕{{else}}☰{{/if}}
        </Button>

        <div class='drawer-content'>
          <Button
            @size='auto'
            @kind='text-only'
            class='view-toggle'
            {{on 'click' this.toggleViewMode}}
          >
            {{#if (eq this.viewMode 'site')}}
              View admin
            {{else}}
              View site
            {{/if}}
          </Button>

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
            <BoxelInput
              @type='search'
              class='lib-search'
              aria-label='Search posts'
              @placeholder='Search posts…'
              @value={{this.searchQuery}}
              @onInput={{this.onSearchInput}}
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
        color: var(--card-foreground);
      }

      .portal {
        position: relative;
        min-height: 100%;
        background-color: var(--card);
        color: var(--foreground);
      }
      .drawer {
        position: absolute;
        top: 0;
        left: 0;
        height: 100%;
        z-index: 200;
        width: 4rem;
        pointer-events: none;
      }
      .drawer.is-open {
        width: 20rem;
      }
      .drawer > * {
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
        gap: var(--boxel-sp);
        background-color: var(--card);
        color: var(--card-foreground);
        border: 1px solid var(--border);
        border-radius: 0.75rem;
        box-shadow: 0 8px 24px
          color-mix(in oklch, var(--foreground) 8%, transparent);
        max-height: calc(100vh - 5rem);
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
        gap: 0.375rem;
        padding: 0.5625rem 1rem;
        background-color: var(--card);
        color: var(--card-foreground);
        border: none;
        border-radius: 62.4375rem;
        cursor: pointer;
        font:
          600 0.75rem/1 system-ui,
          -apple-system,
          sans-serif;
        letter-spacing: 0.5px;
        text-transform: uppercase;
        box-shadow: 0 1px 3px
          color-mix(in oklch, var(--foreground) 15%, transparent);
        transition:
          background-color 0.15s,
          transform 0.1s;
      }
      .view-toggle:hover {
        background-color: var(--card);
        color: var(--card-foreground);
      }
      .view-toggle:active {
        transform: scale(0.97);
      }

      .lib-section {
        display: flex;
        flex-direction: column;
        gap: 0.5rem;
      }
      .lib-section-label {
        font:
          700 0.7rem 'Inter',
          system-ui,
          sans-serif;
        letter-spacing: 0.15em;
        text-transform: uppercase;
        color: var(--foreground);
        margin: 0;
      }
      .lib-section-hint {
        margin: 0;
        font:
          400 0.75rem 'Inter',
          system-ui,
          sans-serif;
        color: var(--subtle-foreground);
      }

      .theme-section {
        padding-bottom: 0.75rem;
        border-bottom: 1px solid var(--boxel-300);
        margin-bottom: 0.25rem;
      }
      .theme-list {
        display: flex;
        flex-direction: column;
        gap: 0.5rem;
        margin-top: 0.25rem;
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
      .lib-loading {
        font:
          600 0.75rem/1 'Inter',
          sans-serif;
        color: var(--boxel-500);
        padding: 0.5rem 0;
      }
      .lib-search {
        width: 100%;
        padding: 0.5rem 0.75rem;
        border: 1px solid var(--border);
        border-radius: 0.5rem;
        font:
          500 0.9rem/1 'Inter',
          sans-serif;
        outline: none;
        transition: border-color 0.15s;
        box-sizing: border-box;
        background-color: var(--card);
        color: var(--foreground);
      }
      .lib-search:focus {
        border-color: var(--primary);
      }
      .lib-search::placeholder {
        color: var(--subtle-foreground);
      }
      .lib-list {
        display: flex;
        flex-direction: column;
        gap: 0.5rem;
      }
      .lib-card {
        height: 4.75rem;
        border: 1px solid var(--border);
        border-radius: 0.625rem;
        overflow: hidden;
        cursor: grab;
        background-color: var(--card);
        color: var(--card-foreground);
        transition:
          border-color 0.12s,
          box-shadow 0.15s,
          transform 0.08s;
      }
      .lib-card:hover {
        border-color: var(--primary);
        box-shadow: 0 3px 10px
          color-mix(in oklch, var(--foreground) 8%, transparent);
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
        background-color: transparent;
        box-shadow: none !important;
        border: none;
      }
    </style>
  </template>
}
