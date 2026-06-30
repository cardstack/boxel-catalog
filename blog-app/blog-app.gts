import { on } from '@ember/modifier';
import { fn, get } from '@ember/helper';
import { action } from '@ember/object';
import type Owner from '@ember/owner';
import { htmlSafe } from '@ember/template';
import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { restartableTask } from 'ember-concurrency';
import { modifier } from 'ember-modifier';

// Fires `callback` on a mousedown that lands outside `element`.
const onClickOutside = modifier(
  (element: HTMLElement, positional: unknown[]) => {
    const callback = positional[0] as () => void;
    const handler = (event: MouseEvent) => {
      if (!element.contains(event.target as Node)) {
        callback();
      }
    };
    // Delay attaching so the click that opened us isn't caught.
    const timer = setTimeout(() => {
      document.addEventListener('mousedown', handler);
    }, 50);
    return () => {
      clearTimeout(timer);
      document.removeEventListener('mousedown', handler);
    };
  },
);

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

function buildSiteThemeCss(theme: any): string {
  // Site-level: emit un-layered :root so descendants (including BlogPosts
  // rendered inside this portal) inherit these as their cascaded values.
  if (!theme || !theme.cssVariables) {
    return DEFAULT_BLOG_THEME_CSS;
  }
  const imports = (theme.cssImports ?? [])
    .filter(Boolean)
    .map((u: string) => `@import url('${u}');`)
    .join('\n');
  return `${DEFAULT_BLOG_THEME_CSS}\n${imports}\n${theme.cssVariables}`;
}

import {
  CardDef,
  Component,
  realmURL,
  field,
  contains,
  linksTo,
  linksToMany,
  StringField,
  type CardContext,
} from 'https://cardstack.com/base/card-api';

import {
  codeRef,
  rri,
  type LooseSingleCardDocument,
  ResolvedCodeRef,
  TypedFilter,
  type Query,
  searchEntryWireQueryFromQuery,
  type SearchEntryWireQuery,
} from '@cardstack/runtime-common';

// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
const here: string = import.meta.url;
import {
  type SortOption,
  sortByCardTitleAsc,
  SortMenu,
} from '../components/sort';
import { CardList } from '../components/card-list';
import { CardsGrid } from '../components/grid';
import { TitleGroup, Layout, type LayoutFilter } from '../components/layout';

import {
  BasicFitted,
  BoxelButton,
  FieldContainer,
  ViewSelector,
} from '@cardstack/boxel-ui/components';
import { eq } from '@cardstack/boxel-ui/helpers';
import { IconPlus } from '@cardstack/boxel-ui/icons';

import CategoriesIcon from '@cardstack/boxel-icons/hierarchy-3';
import BlogPostIcon from '@cardstack/boxel-icons/newspaper';
import BlogAppIcon from '@cardstack/boxel-icons/notebook';
import AuthorIcon from '@cardstack/boxel-icons/square-user';

import { BlogPost } from './blog-post';
import { Game } from './games/game';

type ViewOption = 'card' | 'strip' | 'grid';

export const toISOString = (datetime: Date) => datetime.toISOString();

export const formatDatetime = (
  datetime: Date,
  opts: Intl.DateTimeFormatOptions,
) => {
  const Format = new Intl.DateTimeFormat('en-US', opts);
  return Format.format(datetime);
};

const or = function (item1: any, item2: any) {
  if (item1) {
    return item1;
  } else if (item2) {
    return item2;
  }
  return;
};

interface CardAdminViewSignature {
  Args: {
    cardId: string;
    context?: CardContext<BlogPost>;
  };
  Element: HTMLElement;
}
class BlogAdminData extends GlimmerComponent<CardAdminViewSignature> {
  <template>
    {{#if this.resource.cardError}}
      Error: Could not load additional info
    {{else if this.resource.card}}
      <div class='blog-admin' ...attributes>
        {{#let this.resource.card as |card|}}
          <FieldContainer
            class='admin-data'
            @label='Publish Date'
            @vertical={{true}}
          >
            {{#if card.publishDate}}
              <time datetime={{toISOString card.publishDate}}>
                {{this.formattedDate card.publishDate}}
              </time>
            {{else}}
              N/A
            {{/if}}
          </FieldContainer>
          <FieldContainer
            class='admin-data'
            @label='Last Updated'
            @vertical={{true}}
          >
            {{#if card.lastUpdated}}
              <time datetime={{toISOString card.lastUpdated}}>
                {{this.formattedDate card.lastUpdated}}
              </time>
            {{else}}
              N/A
            {{/if}}
          </FieldContainer>
          <FieldContainer
            class='admin-data'
            @label='Word Count'
            @vertical={{true}}
          >
            {{if card.wordCount card.wordCount 0}}
          </FieldContainer>
          <FieldContainer class='admin-data' @label='Author' @vertical={{true}}>
            {{this.authorLabel}}
          </FieldContainer>
          <FieldContainer class='admin-data' @label='Status' @vertical={{true}}>
            <div class='status-row'>
              <span class='status-pill {{this.statusModifier}}'>
                <span class='status-dot' aria-hidden='true'></span>
                {{card.status}}
              </span>
              <button
                type='button'
                class='publish-toggle
                  {{if card.published "publish-toggle--unpublish"}}'
                {{on 'click' this.togglePublished}}
              >
                {{if card.published 'Unpublish' 'Publish'}}
              </button>
            </div>
          </FieldContainer>
        {{/let}}
      </div>
    {{/if}}
    <style scoped>
      .blog-admin {
        display: inline-flex;
        flex-direction: column;
        gap: var(--boxel-sp);
      }
      .admin-data {
        --boxel-label-font: 600 var(--boxel-font-sm);
      }
      .status-row {
        display: inline-flex;
        align-items: center;
        gap: 10px;
        flex-wrap: wrap;
      }
      .status-pill {
        display: inline-flex;
        align-items: center;
        gap: 6px;
        padding: 4px 10px;
        border-radius: 999px;
        font:
          600 11px/1 system-ui,
          -apple-system,
          sans-serif;
        letter-spacing: 0.05em;
        text-transform: uppercase;
        background: #e5e7eb;
        color: #4b5563;
      }
      .status-dot {
        width: 6px;
        height: 6px;
        border-radius: 50%;
        background: currentColor;
      }
      .status-pill.is-published {
        background: rgba(34, 197, 94, 0.15);
        color: #15803d;
      }
      .status-pill.is-draft {
        background: #e5e7eb;
        color: #4b5563;
      }
      .publish-toggle {
        padding: 5px 12px;
        background: #2c2c2c;
        color: white;
        border: 1px solid #2c2c2c;
        border-radius: 999px;
        cursor: pointer;
        font:
          600 11px/1 system-ui,
          -apple-system,
          sans-serif;
        text-transform: uppercase;
        letter-spacing: 0.04em;
        transition:
          background-color 0.15s,
          color 0.15s,
          transform 0.1s;
      }
      .publish-toggle:hover {
        background: #1a1a1a;
        border-color: #1a1a1a;
      }
      .publish-toggle:active {
        transform: scale(0.96);
      }
      .publish-toggle--unpublish {
        background: transparent;
        color: #2c2c2c;
      }
      .publish-toggle--unpublish:hover {
        background: rgba(0, 0, 0, 0.05);
        color: #1a1a1a;
      }
    </style>
  </template>

  @tracked resource = this.args.context
    ? this.args.context.getCard(this, () => this.args.cardId)
    : undefined;

  formattedDate = (datetime: Date) => {
    return formatDatetime(datetime, {
      year: 'numeric',
      month: 'numeric',
      day: 'numeric',
      hour12: true,
      hour: 'numeric',
      minute: '2-digit',
    });
  };

  get authorLabel() {
    const card = this.resource?.card as any;
    if (!card) return 'N/A';
    return card.formattedAuthors ?? 'N/A';
  }

  get statusModifier() {
    const status = (this.resource?.card as any)?.status;
    return status === 'Published' ? 'is-published' : 'is-draft';
  }

  @action togglePublished() {
    const card = this.resource?.card as any;
    if (!card) return;
    card.published = !card.published;
    (this.args.context as any)?.actions?.saveCard?.(card);
  }
}

class BlogAppTemplate extends Component<typeof BlogApp> {
  <template>
    <Layout
      @filters={{this.filters}}
      @activeFilter={{this.activeFilter}}
      @onFilterChange={{this.onFilterChange}}
      class='blog-app'
    >
      <:sidebar>
        <TitleGroup
          @title={{or @model.cardTitle ''}}
          @tagline={{or @model.cardDescription ''}}
          @thumbnailURL={{or @model.cardThumbnailURL ''}}
          @icon={{@model.constructor.icon}}
          @element='header'
          aria-label='Sidebar Header'
        />
        {{#if @createCard}}
          <BoxelButton
            class='sidebar-create-button'
            @kind='primary'
            @disabled={{this.activeFilter.isCreateNewDisabled}}
            @loading={{this.createCard.isRunning}}
            {{on 'click' this.createNew}}
          >
            {{#unless this.createCard.isRunning}}
              <IconPlus
                class='sidebar-create-button-icon'
                width='15'
                height='15'
              />
            {{/unless}}
            New
            {{this.activeFilter.createNewButtonText}}
          </BoxelButton>
        {{/if}}
      </:sidebar>
      <:contentHeader>
        <h2 class='content-title'>{{this.activeFilter.displayName}}</h2>
        <ViewSelector
          @selectedId={{this.selectedView}}
          @onChange={{this.onChangeView}}
        />
        {{#if this.activeFilter.sortOptions.length}}
          {{#if this.selectedSort}}
            <SortMenu
              @options={{this.activeFilter.sortOptions}}
              @selected={{this.selectedSort}}
              @onSort={{this.onSort}}
            />
          {{/if}}
        {{/if}}
      </:contentHeader>
      <:grid>
        {{#if this.query}}
          {{#if (eq this.selectedView 'card')}}
            <CardList
              @context={{@context}}
              @query={{this.query}}
              @realms={{this.realmHrefs}}
              class='blog-app-card-list {{this.gridClass}}'
            >
              <:meta as |card|>
                {{#if this.showAdminData}}
                  <BlogAdminData
                    @cardId={{card.id}}
                    @context={{this.context}}
                  />
                {{/if}}
              </:meta>
            </CardList>
          {{else}}
            <CardsGrid
              @selectedView={{this.selectedView}}
              @context={{@context}}
              @query={{this.query}}
              @realms={{this.realmHrefs}}
              class={{this.gridClass}}
            />
          {{/if}}
        {{/if}}
      </:grid>
    </Layout>
    <style scoped>
      .blog-app {
        --grid-view-height: max-content;
      }
      .blog-app :where(.grid-view-container) {
        aspect-ratio: 5 / 6;
      }
      .sidebar-create-button {
        --icon-color: currentColor;
        --boxel-loading-indicator-size: 15px;
        gap: var(--boxel-sp-xs);
        font-weight: 600;
      }
      .sidebar-create-button-icon {
        flex-shrink: 0;
      }
      .sidebar-create-button :deep(.loading-indicator) {
        margin: 0;
      }

      .content-title {
        flex-grow: 1;
        margin: 0;
        font: 600 var(--boxel-font-lg);
        letter-spacing: var(--boxel-lsp-xxs);
      }
      .blog-app-card-list {
        --embedded-card-max-width: 715px;
      }
      .blog-app-card-list :deep(.card-list-item) {
        gap: var(--boxel-sp-xl);
        align-items: flex-start;
        padding: var(--boxel-sp-xs) 0;
      }
      .categories-grid {
        --embedded-card-min-height: 150px;
      }
    </style>
  </template>

  @tracked private selectedView: ViewOption = 'card';
  @tracked private activeFilter: LayoutFilter;
  @tracked private filters: LayoutFilter[] = [];

  constructor(owner: Owner, args: any) {
    super(owner, args);
    this.setFilters();
    this.activeFilter = this.filters[0];
  }

  private get context() {
    return this.args.context as CardContext<BlogPost>;
  }

  private get gridClass() {
    let displayName = this.activeFilter.displayName;
    let gridName =
      displayName === 'Blog Posts'
        ? 'blog-posts-grid'
        : displayName === 'Author Bios'
          ? 'author-bios-grid'
          : displayName === 'Categories'
            ? 'categories-grid'
            : '';
    return gridName ? `bordered-items ${gridName}` : '';
  }

  private setFilters() {
    let makeQuery = (codeRef: ResolvedCodeRef) => ({
      filter: { type: codeRef },
    });

    this.filters =
      this.args.model.filters?.map((filter) => {
        if (!filter.query && filter.cardRef) {
          return {
            ...filter,
            query: makeQuery(filter.cardRef),
          };
        }
        return filter;
      }) ?? [];
  }

  private get selectedSort() {
    if (!this.activeFilter.sortOptions?.length) {
      return undefined;
    }
    return this.activeFilter.selectedSort ?? this.activeFilter.sortOptions[0];
  }

  private get showAdminData() {
    return this.activeFilter.showAdminData && this.selectedView === 'card';
  }

  private get realms() {
    return [this.args.model[realmURL]!];
  }

  private get realmHrefs() {
    return this.realms.map((url) => url.href);
  }

  private get query() {
    return {
      ...this.activeFilter.query,
      sort: this.selectedSort?.sort ?? sortByCardTitleAsc,
    };
  }

  @action private onChangeView(id: ViewOption) {
    this.selectedView = id;
  }

  @action private onSort(option: SortOption) {
    this.activeFilter = { ...this.activeFilter, selectedSort: option };
  }

  @action private onFilterChange(filter: LayoutFilter) {
    this.activeFilter = filter;
  }

  @action private createNew() {
    this.createCard.perform();
  }

  private createCard = restartableTask(async () => {
    if (!this.activeFilter?.query?.filter) {
      throw new Error('Missing active filter');
    }
    let ref = (this.activeFilter.query.filter as TypedFilter).on;

    if (!ref) {
      throw new Error('Missing card ref');
    }
    let currentRealm = this.realms[0];
    let doc: LooseSingleCardDocument = {
      data: {
        type: 'card',
        relationships: {
          blog: {
            links: {
              self: this.args.model.id!,
            },
          },
        },
        meta: {
          adoptsFrom: ref,
        },
      },
    };
    await this.args.createCard?.(ref, currentRealm, {
      realmURL: currentRealm,
      doc,
    });
  });
}

type LatestFilter = 'all' | 'latest' | 'news' | 'new-york' | 'tech';

// Reader-facing view: NYT-inspired magazine layout, lists BlogPosts via search.
class BlogSiteView extends Component<typeof BlogApp> {
  get latestSearchQuery(): SearchEntryWireQuery {
    return {
      ...searchEntryWireQueryFromQuery(this.latestQuery),
      realms: this.realmHrefs,
    };
  }
  get picksSearchQuery(): SearchEntryWireQuery {
    return {
      ...searchEntryWireQueryFromQuery(this.picksQuery),
      realms: this.realmHrefs,
    };
  }
  @tracked activeFilter: LatestFilter = 'all';
  @tracked dragOverSlot: string | null = null;

  private waitForCardLoad(resource: any): Promise<void> {
    return new Promise((resolve) => {
      const check = () => {
        if (resource.card || resource.cardError) {
          resolve();
        } else {
          setTimeout(check, 50);
        }
      };
      check();
    });
  }

  private async resolveCardFromUrl(url: string): Promise<BlogPost | null> {
    const context = (this.args as any).context;
    if (!context?.getCard) return null;
    const resource = context.getCard(this, () => url);
    await this.waitForCardLoad(resource);
    return (resource?.card as BlogPost) ?? null;
  }

  @tracked draggingFeaturedIndex: number | null = null;
  @tracked dragOverFeaturedIndex: number | null = null;
  @tracked draggingLead = false;

  private hasInternalFeaturedDrag(event: DragEvent): boolean {
    const dt = event.dataTransfer;
    if (!dt) return false;
    const types = Array.from(dt.types ?? []);
    return types.includes('application/x-featured-index');
  }

  private hasInternalLeadDrag(event: DragEvent): boolean {
    const dt = event.dataTransfer;
    if (!dt) return false;
    const types = Array.from(dt.types ?? []);
    return types.includes('application/x-lead-slot');
  }

  @action onLeadDragStart(event: Event) {
    const ev = event as DragEvent;
    this.draggingLead = true;
    if (ev.dataTransfer) {
      ev.dataTransfer.setData('application/x-lead-slot', '1');
      ev.dataTransfer.setData('text/plain', 'lead');
      ev.dataTransfer.effectAllowed = 'move';
    }
  }

  @action onLeadDragEnd() {
    this.draggingLead = false;
  }

  private swapLeadWithFeatured(featuredIdx: number) {
    const model = this.args.model as any;
    const featured = [...((model.featured as BlogPost[]) ?? [])];
    if (featuredIdx < 0 || featuredIdx >= featured.length) return;
    const promoted = featured[featuredIdx];
    const oldLead = model.lead as BlogPost | undefined;
    if (oldLead) {
      featured[featuredIdx] = oldLead;
    } else {
      // No prior lead — pull the card out of featured entirely.
      featured.splice(featuredIdx, 1);
    }
    model.lead = promoted;
    model.featured = featured;
    const actions = (this.args as any).context?.actions;
    actions?.saveCard?.(this.args.model);
  }

  @action onFeaturedDragStart(index: number, event: DragEvent) {
    this.draggingFeaturedIndex = index;
    if (event.dataTransfer) {
      event.dataTransfer.setData('application/x-featured-index', String(index));
      event.dataTransfer.setData('text/plain', `featured:${index}`);
      event.dataTransfer.effectAllowed = 'move';
    }
  }

  @action onFeaturedDragOver(index: number, event: DragEvent) {
    // Intercept in-list reorders AND lead-to-featured swaps. External
    // drags (URL from the library drawer) fall through to the
    // .featured-list's 'featured-append' handler.
    if (
      !this.hasInternalFeaturedDrag(event) &&
      !this.hasInternalLeadDrag(event)
    ) {
      return;
    }
    event.preventDefault();
    event.stopPropagation();
    this.dragOverFeaturedIndex = index;
    if (event.dataTransfer) event.dataTransfer.dropEffect = 'move';
  }

  @action onFeaturedDragLeave(index: number) {
    if (this.dragOverFeaturedIndex === index) {
      this.dragOverFeaturedIndex = null;
    }
  }

  @action onFeaturedDrop(index: number, event: DragEvent) {
    // Lead → featured swap
    if (this.hasInternalLeadDrag(event)) {
      event.preventDefault();
      event.stopPropagation();
      this.draggingLead = false;
      this.dragOverFeaturedIndex = null;
      this.swapLeadWithFeatured(index);
      return;
    }
    if (!this.hasInternalFeaturedDrag(event)) {
      // External drop — let .featured-list's handler turn it into an append.
      return;
    }
    event.preventDefault();
    event.stopPropagation();
    const raw =
      event.dataTransfer?.getData('application/x-featured-index') ?? '';
    const sourceIdx = parseInt(raw, 10);
    this.draggingFeaturedIndex = null;
    this.dragOverFeaturedIndex = null;
    if (Number.isNaN(sourceIdx) || sourceIdx === index) return;
    const model = this.args.model as any;
    const arr = [...((model.featured as BlogPost[]) ?? [])];
    if (sourceIdx < 0 || sourceIdx >= arr.length) return;
    const [moving] = arr.splice(sourceIdx, 1);
    const insertAt = Math.min(Math.max(0, index), arr.length);
    arr.splice(insertAt, 0, moving);
    model.featured = arr;
    const actions = (this.args as any).context?.actions;
    actions?.saveCard?.(this.args.model);
  }

  @action onFeaturedDragEnd() {
    this.draggingFeaturedIndex = null;
    this.dragOverFeaturedIndex = null;
  }

  @action onSlotDragOver(slotId: string, event: DragEvent) {
    event.preventDefault();
    event.stopPropagation();
    this.dragOverSlot = slotId;
    if (event.dataTransfer) event.dataTransfer.dropEffect = 'copy';
  }

  @action onSlotDragLeave(slotId: string) {
    if (this.dragOverSlot === slotId) {
      this.dragOverSlot = null;
    }
  }

  @action onSlotDrop(slotId: string, event: DragEvent) {
    event.preventDefault();
    event.stopPropagation();
    this.dragOverSlot = null;
    // Featured → lead swap
    if (slotId === 'lead' && this.hasInternalFeaturedDrag(event)) {
      const sourceIdx = parseInt(
        event.dataTransfer?.getData('application/x-featured-index') ?? '-1',
        10,
      );
      this.draggingFeaturedIndex = null;
      this.dragOverFeaturedIndex = null;
      if (!Number.isNaN(sourceIdx)) {
        this.swapLeadWithFeatured(sourceIdx);
      }
      return;
    }
    // An internal lead drag dropped on its own slot — no-op, just clean up.
    if (this.hasInternalLeadDrag(event)) {
      this.draggingLead = false;
      return;
    }
    const dt = event.dataTransfer;
    const url =
      dt?.getData('text/uri-list')?.split('\n')[0]?.trim() ||
      dt?.getData('text/plain') ||
      '';
    if (!url || url.startsWith('lead') || url.startsWith('featured:')) return;
    this.assignSlot(slotId, url);
  }

  @action async assignSlot(slotId: string, url: string) {
    const card = await this.resolveCardFromUrl(url);
    if (!card) return;
    const model = this.args.model as any;
    if (slotId === 'lead') {
      model.lead = card;
    } else if (slotId === 'featured-append') {
      const next = [...((model.featured as BlogPost[]) ?? [])];
      const url = (card as any).id;
      if (!next.some((p) => (p as any).id === url)) {
        next.push(card);
        model.featured = next;
      }
    } else if (slotId === 'games-append') {
      const next = [...((model.games as Game[]) ?? [])];
      // Avoid duplicates — if this game is already linked, do nothing.
      const url = (card as any).id;
      if (!next.some((g) => (g as any).id === url)) {
        next.push(card as unknown as Game);
        model.games = next;
      }
    }
    const actions = (this.args as any).context?.actions;
    actions?.saveCard?.(this.args.model);
  }

  get hasFeatured(): boolean {
    return Boolean((this.args.model as any).featured?.length);
  }

  get hasGames(): boolean {
    return Boolean((this.args.model as any).games?.length);
  }

  get realmHrefs(): string[] {
    const u = this.args.model[realmURL];
    return u ? [u.href] : [];
  }

  get query() {
    const on = codeRef(here, './blog-post', 'BlogPost');
    return {
      filter: { on, eq: { published: true } },
      sort: [{ on, by: 'publishDate', direction: 'desc' as const }],
    };
  }

  get picksQuery(): Query {
    const on = codeRef(here, './blog-post', 'BlogPost');
    return {
      filter: {
        on,
        eq: { published: true, 'categories.slug': 'writers-pick' },
      },
      sort: [{ on, by: 'publishDate', direction: 'desc' as const }],
    };
  }

  get latestQuery(): Query {
    const on = codeRef(here, './blog-post', 'BlogPost');
    const categorySlug =
      this.activeFilter === 'news'
        ? 'news'
        : this.activeFilter === 'new-york'
          ? 'new-york'
          : this.activeFilter === 'tech'
            ? 'future-tech'
            : undefined;
    return {
      filter: {
        on,
        eq: categorySlug
          ? { published: true, 'categories.slug': categorySlug }
          : { published: true },
      },
      sort: [{ on, by: 'publishDate', direction: 'desc' }],
    };
  }

  @action setFilter(f: LatestFilter) {
    this.activeFilter = f;
  }

  get todayLabel(): string {
    return new Date()
      .toLocaleDateString('en-US', {
        weekday: 'long',
        year: 'numeric',
        month: 'long',
        day: 'numeric',
      })
      .toUpperCase();
  }

  <template>
    <article class='site'>
      <header class='site-header'>
        <div class='brand'>
          {{#if @model.cardThumbnailURL}}
            <img src={{@model.cardThumbnailURL}} alt='' class='brand-logo' />
          {{/if}}
          <div class='brand-text'>
            <h1 class='brand-title'><@fields.cardTitle /></h1>
            {{#if @model.cardDescription}}
              <p class='brand-tag'>{{@model.cardDescription}}</p>
            {{/if}}
          </div>
        </div>
      </header>

      <section class='hero'>
        <div class='hero-grid'>
          <div
            class='hero-lead
              {{if (eq this.dragOverSlot "lead") "is-drop-target"}}'
            {{on 'dragover' (fn this.onSlotDragOver 'lead')}}
            {{on 'dragleave' (fn this.onSlotDragLeave 'lead')}}
            {{on 'drop' (fn this.onSlotDrop 'lead')}}
          >
            {{#if @model.lead.published}}
              <div
                class='lead-list lead-pinned
                  {{if this.draggingLead "is-dragging"}}'
                draggable='true'
                title='Drag to swap with a featured post'
                {{on 'dragstart' this.onLeadDragStart}}
                {{on 'dragend' this.onLeadDragEnd}}
              >
                <@fields.lead @format='embedded' />
              </div>
            {{else}}
              <div class='lead-empty'>
                <span class='lead-empty-label'>Lead</span>
                <p>{{#if @model.lead}}Lead post is unpublished. Publish it to
                    feature it here.{{else}}Drag a post here to set the lead
                    story.{{/if}}</p>
              </div>
            {{/if}}
          </div>
          <aside class='hero-aside'>
            <h2 class='aside-heading'>Featured</h2>
            <div
              class='featured-list manual
                {{if
                  (eq this.dragOverSlot "featured-append")
                  "is-drop-target"
                }}'
              {{on 'dragover' (fn this.onSlotDragOver 'featured-append')}}
              {{on 'dragleave' (fn this.onSlotDragLeave 'featured-append')}}
              {{on 'drop' (fn this.onSlotDrop 'featured-append')}}
            >
              {{#if this.hasFeatured}}
                {{#each @fields.featured as |Field index|}}
                  {{#let (get @model.featured index) as |post|}}
                    {{#if post.published}}
                      <div
                        class='featured-slot
                          {{if
                            (eq this.draggingFeaturedIndex index)
                            "is-dragging"
                          }}
                          {{if
                            (eq this.dragOverFeaturedIndex index)
                            "is-drop-target"
                          }}'
                        draggable='true'
                        title='Drag to reorder'
                        {{on 'dragstart' (fn this.onFeaturedDragStart index)}}
                        {{on 'dragend' this.onFeaturedDragEnd}}
                        {{on 'dragover' (fn this.onFeaturedDragOver index)}}
                        {{on 'dragleave' (fn this.onFeaturedDragLeave index)}}
                        {{on 'drop' (fn this.onFeaturedDrop index)}}
                      >
                        <Field @format='fitted' />
                      </div>
                    {{/if}}
                  {{/let}}
                {{/each}}
              {{else}}
                <div class='featured-empty'>
                  Drop a post here
                </div>
              {{/if}}
            </div>
            <h2 class='aside-heading aside-heading--games'>Games</h2>
            <div
              class='games-list
                {{if (eq this.dragOverSlot "games-append") "is-drop-target"}}'
              {{on 'dragover' (fn this.onSlotDragOver 'games-append')}}
              {{on 'dragleave' (fn this.onSlotDragLeave 'games-append')}}
              {{on 'drop' (fn this.onSlotDrop 'games-append')}}
            >
              {{#if this.hasGames}}
                {{#each @fields.games as |Field|}}
                  <div class='games-card'>
                    <Field @format='fitted' />
                  </div>
                {{/each}}
              {{else}}
                <div class='games-empty'>
                  Drop a game here
                </div>
              {{/if}}
            </div>
          </aside>
        </div>
      </section>

      <section class='picks'>
        <header class='picks-head'>
          <h2 class='picks-title'>Writer's Picks</h2>
          <p class='picks-subtitle'>
            Strange, extreme, hand-picked stories the editors couldn't stop
            reading.
          </p>
        </header>
        <div class='picks-carousel'>
          {{#let (component @context.searchResultsComponent) as |Search|}}
            <Search @query={{this.picksSearchQuery}} as |results|>
              {{#each results.entries key='id' as |card|}}
                <div class='picks-card'>
                  <card.component />
                </div>
              {{else}}
                {{#if results.isLoading}}
                  <div class='aside-loading'>Loading…</div>
                {{/if}}
              {{/each}}
            </Search>
          {{/let}}
        </div>
      </section>

      <section class='recent'>
        <header class='recent-head'>
          <h2 class='recent-title'>Latest Posts</h2>
          <nav class='filter-pills' aria-label='Filter posts'>
            <button
              type='button'
              class='pill {{if (eq this.activeFilter "all") "is-active"}}'
              {{on 'click' (fn this.setFilter 'all')}}
            >All</button>
            <button
              type='button'
              class='pill {{if (eq this.activeFilter "latest") "is-active"}}'
              {{on 'click' (fn this.setFilter 'latest')}}
            >Latest</button>
            <button
              type='button'
              class='pill {{if (eq this.activeFilter "news") "is-active"}}'
              {{on 'click' (fn this.setFilter 'news')}}
            >News</button>
            <button
              type='button'
              class='pill {{if (eq this.activeFilter "new-york") "is-active"}}'
              {{on 'click' (fn this.setFilter 'new-york')}}
            >New York</button>
            <button
              type='button'
              class='pill {{if (eq this.activeFilter "tech") "is-active"}}'
              {{on 'click' (fn this.setFilter 'tech')}}
            >Tech</button>
          </nav>
        </header>
        <div class='recent-grid filter-{{this.activeFilter}}'>
          {{#let (component @context.searchResultsComponent) as |Search|}}
            <Search @query={{this.latestSearchQuery}} as |results|>
              {{#each results.entries key='id' as |card|}}
                <div class='recent-card'>
                  <card.component />
                </div>
              {{else}}
                {{#if results.isLoading}}
                  <div class='recent-loading'>Loading…</div>
                {{/if}}
              {{/each}}
            </Search>
          {{/let}}
        </div>
      </section>
    </article>
    <style scoped>
      @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap');

      .site {
        min-height: 100%;
        background: var(--blog-color-bg, #ffffff);
        color: var(--blog-color-text, #121212);
        font-family: var(--blog-font-family, var(--blog-font-family));
        padding-bottom: var(--boxel-sp-xxl);
      }

      /* ── Site header ────────────────────────────────────── */
      .site-header {
        max-width: 1240px;
        margin: 0 auto;
        padding: var(--boxel-sp-xxl) var(--boxel-sp-lg) var(--boxel-sp-lg);
      }
      .brand {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp);
      }
      .brand-logo {
        width: 64px;
        height: 64px;
        flex-shrink: 0;
        border-radius: 12px;
        object-fit: cover;
        background: var(--blog-color-thumb-bg);
      }
      .brand-text {
        min-width: 0;
      }
      .brand-title {
        font: 800 2.25rem/1.05 var(--blog-font-family);
        letter-spacing: -0.02em;
        margin: 0 0 8px;
        color: var(--blog-color-text);
      }
      .brand-tag {
        font: 400 1rem/1.45 var(--blog-font-family);
        color: var(--blog-color-subtle);
        margin: 0;
        max-width: 640px;
      }

      /* ── Hero section ───────────────────────────────────── */
      .hero {
        max-width: 1240px;
        margin: 0 auto;
        padding: 0 var(--boxel-sp-lg);
      }
      .hero-grid {
        display: grid;
        grid-template-columns: 1.55fr 1fr;
        gap: 28px;
        align-items: stretch;
      }
      .aside-heading {
        font: 700 1.4rem/1.2 var(--blog-font-family);
        letter-spacing: -0.015em;
        color: var(--blog-color-text);
        margin: 0 0 16px;
      }

      /* Empty lead placeholder — shown when no lead is pinned */
      .lead-empty {
        height: 100%;
        min-height: 520px;
        border-radius: 18px;
        background: var(--blog-color-thumb-bg);
        border: 2px dashed #d3d3d3;
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 12px;
        padding: var(--boxel-sp-xl);
        text-align: center;
      }
      .lead-empty-label {
        font: 700 0.75rem var(--blog-font-family);
        text-transform: uppercase;
        letter-spacing: 0.18em;
        color: var(--blog-color-faint);
      }
      .lead-empty p {
        margin: 0;
        font: 500 0.95rem/1.5 var(--blog-font-family);
        color: var(--blog-color-subtle);
      }

      /* Lead drop zone — highlights when a card is dragged over */
      .hero-lead {
        border-radius: 18px;
        transition:
          outline-color 0.15s,
          outline-offset 0.15s;
        outline: 0 dashed transparent;
        outline-offset: 0;
      }
      .hero-lead.is-drop-target {
        outline: 3px dashed var(--boxel-highlight, #7b61ff);
        outline-offset: 8px;
      }

      /* Lead — single embedded card, big image overlay */
      .lead-list {
        cursor: grab;
        transition:
          opacity 0.15s,
          transform 0.15s;
      }
      .lead-list:active {
        cursor: grabbing;
      }
      .lead-list.is-dragging {
        opacity: 0.4;
        transform: scale(0.99);
      }
      .lead-list :deep(ul) {
        display: block;
        list-style: none;
        padding: 0;
        margin: 0;
      }
      .lead-list :deep(li) {
        margin: 0;
        padding: 0;
        border: none;
        gap: 0 !important;
      }
      .lead-list :deep(li ~ li) {
        display: none;
      }
      .lead-list :deep(.card) {
        min-height: 600px !important;
        max-width: 100% !important;
        border-radius: 18px;
        overflow: hidden;
        box-shadow: none !important;
        cursor: pointer;
      }
      .lead-list :deep(.embedded-blog-post) {
        display: block !important;
        grid-template: none !important;
        padding: 0 !important;
        position: relative;
        height: 100%;
        min-height: 600px;
        border-radius: 18px;
        overflow: hidden !important;
        background: #1a1a1a;
        isolation: isolate;
      }
      .lead-list :deep(.thumbnail) {
        position: absolute !important;
        inset: 0;
        width: 100% !important;
        height: 100% !important;
        margin: 0 !important;
        background-color: #1a1a1a;
        transition: transform 0.35s ease;
        z-index: 0;
      }
      .lead-list :deep(li):hover .thumbnail {
        transform: scale(1.03);
      }
      .lead-list :deep(.embedded-blog-post)::after {
        content: '';
        position: absolute;
        inset: 0;
        background: linear-gradient(
          to top,
          rgba(0, 0, 0, 0.88) 0%,
          rgba(0, 0, 0, 0.4) 45%,
          transparent 75%
        );
        z-index: 1;
        pointer-events: none;
      }
      .lead-list :deep(.categories) {
        position: absolute;
        left: 28px;
        bottom: 100px;
        z-index: 2;
        margin: 0 !important;
        display: flex !important;
        gap: 6px !important;
      }
      .lead-list :deep(.category) {
        background: rgba(255, 255, 255, 0.95) !important;
        color: var(--blog-color-text) !important;
        padding: 5px 14px !important;
        border-radius: 999px !important;
        font: 600 11px/1 var(--blog-font-family) !important;
        letter-spacing: 0 !important;
        text-transform: capitalize !important;
        border: none;
      }
      .lead-list :deep(.title) {
        position: absolute;
        left: 28px;
        right: 28px;
        bottom: 28px;
        z-index: 2;
        font: 700 2rem/1.15 var(--blog-font-family) !important;
        letter-spacing: -0.015em !important;
        color: #ffffff !important;
        margin: 0 !important;
        display: -webkit-box;
        -webkit-line-clamp: 3;
        -webkit-box-orient: vertical;
        overflow: hidden;
      }
      .lead-list :deep(.description),
      .lead-list :deep(.byline),
      .lead-list :deep(.date) {
        display: none !important;
      }

      /* Right column — fitted format, horizontal thumb + title */
      .hero-aside {
        display: flex;
        flex-direction: column;
      }
      .featured-list {
        flex: 1;
      }
      .featured-list :deep(ul) {
        display: flex;
        flex-direction: column;
        gap: 0;
        list-style: none;
        padding: 0;
        margin: 0;
      }
      .featured-list :deep(li) {
        margin: 0;
        padding: 14px 0;
        border: none;
        border-top: 1px solid #ececec;
        gap: 0 !important;
      }
      .featured-list :deep(li:first-child) {
        display: none;
      }
      .featured-list :deep(li:nth-child(2)) {
        border-top: none;
        padding-top: 0;
      }
      .featured-list :deep(li:nth-child(n + 5)) {
        display: none;
      }
      .featured-list :deep(.card) {
        min-height: 0 !important;
        max-width: 100% !important;
        width: 100%;
        height: 220px;
        aspect-ratio: auto;
        cursor: pointer;
        box-shadow: none !important;
        border-radius: 12px;
        overflow: hidden;
        background: transparent;
      }
      .featured-list :deep(.fitted-blog-post) {
        padding: 0 !important;
        gap: 16px !important;
      }
      .featured-list :deep(.fitted-blog-post .thumbnail) {
        width: 160px !important;
        height: 220px !important;
        border-radius: 12px !important;
        flex-shrink: 0;
      }
      .featured-list :deep(.fitted-blog-post .title) {
        font: 600 0.95rem/1.32 var(--blog-font-family) !important;
        letter-spacing: -0.005em !important;
        color: var(--blog-color-text) !important;
        -webkit-line-clamp: 3 !important;
      }
      .featured-list :deep(.card):hover .title {
        color: var(--blog-color-accent) !important;
      }

      /* Manual featured: one drop zone, any number of cards */
      .featured-list.manual {
        display: flex;
        flex-direction: column;
        gap: 0;
        border-radius: 12px;
        transition:
          outline-color 0.15s,
          outline-offset 0.15s,
          background-color 0.15s;
      }
      .featured-list.manual.is-drop-target {
        outline: 2px dashed var(--boxel-highlight, #7b61ff);
        outline-offset: 4px;
        background: rgba(123, 97, 255, 0.04);
      }
      .featured-slot {
        padding: 12px 0;
        border-top: 1px solid #ececec;
        height: 220px;
        cursor: grab;
        transition:
          opacity 0.15s,
          transform 0.15s;
      }
      .featured-slot:first-child {
        border-top: none;
        padding-top: 0;
        height: 208px;
      }
      .featured-slot:active {
        cursor: grabbing;
      }
      .featured-slot.is-dragging {
        opacity: 0.4;
        transform: scale(0.98);
      }
      .featured-slot.is-drop-target {
        outline: 2px dashed var(--blog-color-accent, #7b61ff);
        outline-offset: 2px;
        border-radius: 6px;
      }
      .featured-slot :deep(.fitted-blog-post) {
        height: 100%;
        width: 100%;
        padding: 0 !important;
        gap: 16px !important;
        display: grid !important;
        grid-template-columns: 160px 1fr !important;
        align-items: center;
      }
      .featured-slot :deep(.fitted-blog-post .thumbnail) {
        width: 160px !important;
        height: 100% !important;
        border-radius: 12px !important;
        flex-shrink: 0;
        background-size: cover !important;
        background-position: center !important;
      }
      .featured-slot :deep(.fitted-blog-post .title) {
        font: 600 1.05rem/1.3 var(--blog-font-family) !important;
        letter-spacing: -0.005em !important;
        color: var(--blog-color-text) !important;
        -webkit-line-clamp: 3 !important;
        display: -webkit-box;
        -webkit-box-orient: vertical;
        overflow: hidden;
      }
      .featured-slot :deep(.fitted-blog-post .description) {
        display: -webkit-box !important;
        -webkit-line-clamp: 2 !important;
        -webkit-box-orient: vertical;
        font: 400 0.85rem/1.4 var(--blog-font-family) !important;
        color: var(--blog-color-subtle) !important;
        margin-top: 4px !important;
      }
      .featured-slot :hover :deep(.fitted-blog-post .title) {
        color: var(--blog-color-accent) !important;
      }
      .featured-empty {
        display: flex;
        align-items: center;
        justify-content: center;
        height: 84px;
        padding: 0 14px;
        background: var(--blog-color-thumb-bg);
        border: 2px dashed #d3d3d3;
        border-radius: 12px;
        color: var(--blog-color-faint);
        font: 500 0.85rem/1.3 var(--blog-font-family);
      }

      /* Games subsection — horizontal strip of fitted preview tiles */
      .aside-heading--games {
        margin-top: var(--boxel-sp-xl);
      }
      .games-list {
        display: flex;
        flex-direction: row;
        gap: 12px;
        overflow-x: auto;
        scroll-snap-type: x mandatory;
        scroll-behavior: smooth;
        padding: 4px 2px 12px;
        margin: 0 -2px;
        scrollbar-width: thin;
      }
      .games-list::-webkit-scrollbar {
        height: 6px;
      }
      .games-list::-webkit-scrollbar-thumb {
        background: var(--blog-color-divider);
        border-radius: 3px;
      }
      .games-list::-webkit-scrollbar-thumb:hover {
        background: #999;
      }
      .games-card {
        flex: 0 0 200px;
        scroll-snap-align: start;
        height: 84px;
        border: 1px solid #ececec;
        border-radius: 12px;
        overflow: hidden;
        cursor: pointer;
        background: white;
        transition:
          border-color 0.15s,
          box-shadow 0.15s,
          transform 0.1s;
      }
      .games-card:hover {
        border-color: var(--blog-color-accent);
        box-shadow: 0 3px 10px rgba(0, 0, 0, 0.08);
        transform: translateY(-1px);
      }
      .games-card :deep(.card) {
        min-height: 0 !important;
        max-width: 100% !important;
        width: 100%;
        height: 100%;
        background: transparent;
        box-shadow: none !important;
        border: none;
      }
      .games-list.is-drop-target {
        outline: 2px dashed var(--boxel-highlight, #7b61ff);
        outline-offset: 4px;
        background: rgba(123, 97, 255, 0.04);
        border-radius: 12px;
      }
      .games-empty {
        display: flex;
        align-items: center;
        justify-content: center;
        height: 84px;
        flex: 1;
        padding: 0 14px;
        background: var(--blog-color-thumb-bg);
        border: 2px dashed #d3d3d3;
        border-radius: 12px;
        color: var(--blog-color-faint);
        font: 500 0.85rem/1.3 var(--blog-font-family);
      }
      .aside-loading {
        color: var(--boxel-500);
        font: 600 12px/1 var(--blog-font-family);
        padding: 12px 0;
      }

      /* Writer's Picks — horizontal scroll carousel */
      .picks {
        max-width: 1240px;
        margin: 0 auto;
        padding: var(--boxel-sp-xxl) var(--boxel-sp-lg) 0;
      }
      .picks-head {
        margin-bottom: var(--boxel-sp-lg);
      }
      .picks-title {
        font: 800 2rem/1.1 var(--blog-font-family);
        letter-spacing: -0.02em;
        margin: 0 0 6px;
        color: var(--blog-color-text);
      }
      .picks-subtitle {
        font: 400 1rem/1.4 var(--blog-font-family);
        color: var(--blog-color-subtle);
        margin: 0;
      }
      /* Carousel — manual horizontal scroll, both directions */
      .picks-carousel {
        display: flex;
        gap: 20px;
        overflow-x: auto;
        overflow-y: hidden;
        scroll-snap-type: x mandatory;
        scroll-behavior: smooth;
        scroll-padding: var(--boxel-sp-lg);
        padding: 6px var(--boxel-sp-lg) 28px;
        margin: 0 calc(-1 * var(--boxel-sp-lg));
        scrollbar-width: thin;
        scrollbar-color: #c5c5c5 transparent;
      }
      .picks-carousel::-webkit-scrollbar {
        height: 10px;
      }
      .picks-carousel::-webkit-scrollbar-track {
        background: transparent;
      }
      .picks-carousel::-webkit-scrollbar-thumb {
        background: var(--blog-color-divider);
        border-radius: 5px;
      }
      .picks-carousel::-webkit-scrollbar-thumb:hover {
        background: #999;
      }
      .picks-card {
        flex: 0 0 360px;
        scroll-snap-align: start;
        height: 200px;
        border-radius: 14px;
        overflow: hidden;
        box-shadow: 0 2px 6px rgba(0, 0, 0, 0.08);
        cursor: pointer;
        transition:
          box-shadow 0.15s,
          transform 0.15s;
      }
      .picks-card:hover {
        box-shadow: 0 8px 24px rgba(0, 0, 0, 0.14);
        transform: translateY(-2px);
      }
      .picks-card :deep(.card) {
        height: 100% !important;
        min-height: 100% !important;
        max-width: 100% !important;
        width: 100%;
      }
      /* Force the horizontal "image | content" layout so cards always
         render their thumbnail, regardless of container-query timing. */
      .picks-card :deep(.fitted-blog-post) {
        display: grid !important;
        grid-template: 'img content' 1fr / 42% 1fr !important;
        gap: 0 !important;
        padding: 0 !important;
        height: 100%;
        width: 100%;
      }
      .picks-card :deep(.fitted-blog-post .thumbnail) {
        grid-area: img !important;
        width: 100% !important;
        height: 100% !important;
        margin: 0 !important;
        background-color: var(--blog-color-thumb-bg) !important;
        background-position: center !important;
        background-size: cover !important;
        background-repeat: no-repeat !important;
      }
      .picks-card :deep(.fitted-blog-post .content) {
        grid-area: content !important;
        padding: var(--boxel-sp-sm) var(--boxel-sp) !important;
        display: flex !important;
        flex-direction: column;
        gap: 4px;
        overflow: hidden;
        min-width: 0;
      }
      .picks-card :deep(.fitted-blog-post .categories) {
        display: none !important;
      }
      .picks-card :deep(.fitted-blog-post .title) {
        font: 700 1rem/1.25 var(--blog-font-family) !important;
        letter-spacing: -0.005em !important;
        color: var(--blog-color-text) !important;
        margin: 0 !important;
        display: -webkit-box;
        -webkit-line-clamp: 3;
        -webkit-box-orient: vertical;
      }
      .picks-card :deep(.fitted-blog-post .description) {
        font: 400 0.82rem/1.4 var(--blog-font-family) !important;
        color: var(--blog-color-subtle) !important;
        margin: 0 !important;
        display: -webkit-box;
        -webkit-line-clamp: 2;
        -webkit-box-orient: vertical;
        overflow: hidden;
      }
      .picks-card :deep(.fitted-blog-post .byline),
      .picks-card :deep(.fitted-blog-post .date) {
        font: 600 0.7rem/1 var(--blog-font-family) !important;
        color: var(--blog-color-faint) !important;
        text-transform: uppercase;
        letter-spacing: 0.05em;
        margin: 0 !important;
      }

      /* ── Recent Posts section ──────────────────────────── */
      .recent {
        max-width: 1240px;
        margin: 0 auto;
        padding: var(--boxel-sp-xxl) var(--boxel-sp-lg) var(--boxel-sp-xxl);
      }
      .recent-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: var(--boxel-sp);
        margin-bottom: var(--boxel-sp-lg);
        flex-wrap: wrap;
      }
      .recent-title {
        font: 800 2rem/1.1 var(--blog-font-family);
        letter-spacing: -0.02em;
        margin: 0;
        color: var(--blog-color-text);
      }
      .filter-pills {
        display: inline-flex;
        gap: 10px;
        flex-wrap: wrap;
      }
      .filter-pills .pill {
        padding: 9px 20px;
        background: white;
        color: var(--blog-color-text);
        border: 1px solid #121212;
        border-radius: 999px;
        cursor: pointer;
        font: 600 13px/1 var(--blog-font-family);
        letter-spacing: 0;
        transition:
          background-color 0.15s,
          color 0.15s,
          transform 0.1s;
      }
      .filter-pills .pill:hover {
        background: #f5f5f5;
      }
      .filter-pills .pill:active {
        transform: scale(0.97);
      }
      .filter-pills .pill.is-active {
        background: #121212;
        color: white;
        border-color: var(--blog-color-text);
      }
      .filter-pills .pill.is-active:hover {
        background: #000;
      }
      /* Recent grid — 2 rows × 3 columns of fitted cards.
         Hides hero items 1-6 and overflow items 13+, leaving 7-12. */
      .recent-grid {
        display: grid;
        grid-template-columns: repeat(3, 1fr);
        gap: var(--boxel-sp-lg);
      }
      .recent-card {
        height: 420px;
        border-radius: 14px;
        overflow: hidden;
        box-shadow: 0 1px 3px rgba(0, 0, 0, 0.08);
        cursor: pointer;
        transition:
          box-shadow 0.15s,
          transform 0.15s;
      }
      .recent-card:hover {
        box-shadow: 0 6px 18px rgba(0, 0, 0, 0.12);
        transform: translateY(-2px);
      }
      .recent-card :deep(.card) {
        height: 100% !important;
        min-height: 100% !important;
        max-width: 100% !important;
        width: 100%;
      }
      /* Cap at 12 items always so the grid stays bounded */
      .recent-grid .recent-card:nth-child(n + 13) {
        display: none;
      }
      /* "Latest" pill: show only top 6 (2×3) */
      .recent-grid.filter-latest .recent-card:nth-child(n + 7) {
        display: none;
      }
      .recent-loading {
        grid-column: 1 / -1;
        color: var(--boxel-500);
        font: 600 13px/1 var(--blog-font-family);
        padding: var(--boxel-sp-lg) 0;
        text-align: center;
      }

      /* ── Responsive ─────────────────────────────────────── */
      @media (max-width: 900px) {
        .hero-list :deep(ul) {
          grid-template-columns: 1fr;
        }
        .hero-list :deep(ul)::before {
          display: none;
        }
        .hero-list :deep(li:first-child) {
          grid-column: 1;
          grid-row: 1;
        }
        .hero-list :deep(li:nth-child(2)) {
          grid-column: 1;
          grid-row: 2;
        }
        .hero-list :deep(li:nth-child(3)) {
          grid-column: 1;
          grid-row: 3;
        }
        .hero-list :deep(li:nth-child(4)) {
          grid-column: 1;
          grid-row: 4;
        }
        .hero-list :deep(li:nth-child(5)) {
          grid-column: 1;
          grid-row: 5;
        }
        .hero-list :deep(li:nth-child(6)) {
          grid-column: 1;
          grid-row: 6;
        }
        .hero-list :deep(li:first-child .embedded-blog-post) {
          min-height: 380px;
        }
        .hero-list :deep(li:first-child .title) {
          font-size: 1.6rem !important;
        }
      }
      @media (max-width: 700px) {
        .brand-title {
          font-size: 1.75rem;
        }
        .recent-title {
          font-size: 1.5rem;
        }
        .recent-grid {
          grid-template-columns: 1fr;
        }
        .hero-list :deep(li:first-child .embedded-blog-post) {
          min-height: 320px;
        }
      }
    </style>
  </template>
}

// Portal wrapper: collapsible left drawer + main content (site or admin).
class IsolatedPortal extends Component<typeof BlogApp> {
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
    const on = codeRef(here, './blog-post', 'BlogPost');
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
      buildSiteThemeCss((this.args.model as any)?.cardInfo?.theme),
    );
  }

  <template>
    <style>
      {{this.themeStyle}}
    </style>
    <div class='portal'>
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

          <section class='lib-section theme-section'>
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

          <section class='lib-section'>
            <h3 class='lib-section-label'>All posts</h3>
            <p class='lib-section-hint'>Drag a card to place it</p>
            <input
              type='search'
              class='lib-search'
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

// TODO: BlogApp should extend AppCard
// Using type CardDef instead of AppCard from catalog because of
// the many type issues resulting from the lack types from catalog realm
export class BlogApp extends CardDef {
  @field website = contains(StringField);
  // Manually-pinned posts; if unset, the Site view falls back to the
  // newest-first auto query.
  @field lead = linksTo(() => BlogPost, {
    searchable: ['authors', 'categories'],
  });
  @field featured = linksToMany(() => BlogPost, {
    searchable: ['authors', 'categories'],
  });
  @field games = linksToMany(() => Game, { searchable: true });
  static displayName = 'Blog App';
  static icon = BlogAppIcon;
  static prefersWideFormat = true;
  static headerColor = '#fff500';

  static sortOptionList: SortOption[] = [
    {
      id: 'datePubDesc',
      displayName: 'Date Published',
      sort: [
        {
          on: codeRef(here, './blog-post', 'BlogPost'),
          by: 'publishDate',
          direction: 'desc',
        },
      ],
    },
    {
      id: 'lastUpdatedDesc',
      displayName: 'Last Updated',
      sort: [
        {
          by: 'lastModified',
          direction: 'desc',
        },
      ],
    },
    {
      id: 'cardTitleAsc',
      displayName: 'A-Z',
      sort: sortByCardTitleAsc,
    },
  ];

  static filterList: LayoutFilter[] = [
    {
      displayName: 'Blog Posts',
      icon: BlogPostIcon,
      cardTypeName: 'Blog Post',
      createNewButtonText: 'Post',
      showAdminData: true,
      sortOptions: BlogApp.sortOptionList,
      cardRef: codeRef(here, './blog-post', 'BlogPost'),
    },
    {
      displayName: 'Author Bios',
      icon: AuthorIcon,
      cardTypeName: 'Author',
      createNewButtonText: 'Author',
      cardRef: codeRef(here, './author', 'Author'),
    },
    {
      displayName: 'Categories',
      icon: CategoriesIcon,
      cardTypeName: 'Category',
      createNewButtonText: 'Category',
      cardRef: codeRef(here, './blog-category', 'BlogCategory'),
    },
  ];

  get filters(): LayoutFilter[] {
    if (this.constructor && 'filterList' in this.constructor) {
      return this.constructor.filterList as LayoutFilter[];
    }
    return BlogApp.filterList;
  }

  static isolated = IsolatedPortal;
  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <BasicFitted
        class='fitted-blog'
        @thumbnailURL={{@model.cardThumbnailURL}}
        @iconComponent={{@model.constructor.icon}}
        @primary={{@model.cardTitle}}
        @secondary={{@model.website}}
      />
      <style scoped>
        .fitted-blog :deep(.card-description) {
          display: none;
        }

        @container fitted-card ((2.0 < aspect-ratio) and (400px <= width ) and (height < 115px)) {
          .fitted-blog {
            padding: var(--boxel-sp-xxxs);
            align-items: center;
          }
          .fitted-blog :deep(.thumbnail-section) {
            border: 1px solid var(--boxel-450);
            border-radius: var(--boxel-border-radius-lg);
            width: 40px;
            height: 40px;
            overflow: hidden;
          }
          .fitted-blog :deep(.card-thumbnail) {
            width: 100%;
            height: 100%;
          }
          .fitted-blog :deep(.card-type-icon) {
            width: 20px;
            height: 20px;
          }
          .fitted-blog :deep(.info-section) {
            display: flex;
            justify-content: space-between;
            align-items: center;
            gap: var(--boxel-sp-xs);
          }
          .fitted-blog :deep(.card-title) {
            -webkit-line-clamp: 2;
            font: 600 var(--boxel-font-sm);
            letter-spacing: var(--boxel-lsp-xs);
          }
          .fitted-blog :deep(.card-display-name) {
            margin: 0;
            overflow: hidden;
          }
        }
      </style>
    </template>
  };
}
