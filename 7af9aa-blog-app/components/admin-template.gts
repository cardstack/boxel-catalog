import { on } from '@ember/modifier';
import { action } from '@ember/object';
import type Owner from '@ember/owner';
import { tracked } from '@glimmer/tracking';
import { restartableTask } from 'ember-concurrency';
import {
  Component,
  realmURL,
  type CardContext,
} from '@cardstack/base/card-api';
import {
  type LooseSingleCardDocument,
  type ResolvedCodeRef,
} from '@cardstack/runtime-common';
import {
  type SortOption,
  sortByCardTitleAsc,
  SortMenu,
} from '../../components/sort';
import { CardList } from '../../components/card-list';
import { CardsGrid } from '../../components/grid';
import { TitleGroup, Layout, type LayoutFilter } from '../../components/layout';
import { BoxelButton, ViewSelector } from '@cardstack/boxel-ui/components';
import { eq } from '@cardstack/boxel-ui/helpers';
import { IconPlus } from '@cardstack/boxel-ui/icons';
import { BlogAdminData } from './admin-view';
import type { BlogApp } from '../blog-app';
import type { BlogPost } from '../blog-post';

// ViewSelector is used here without @items, so these mirror its own defaults.
const VIEW_OPTION_IDS = ['card', 'strip', 'grid'] as const;
type ViewOption = (typeof VIEW_OPTION_IDS)[number];

function isViewOption(id: string): id is ViewOption {
  return VIEW_OPTION_IDS.some((option) => option === id);
}

const or = function (item1: any, item2: any) {
  if (item1) {
    return item1;
  } else if (item2) {
    return item2;
  }
  return;
};

export class BlogAppTemplate extends Component<typeof BlogApp> {
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
        --boxel-loading-indicator-size: 0.9375rem;
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
        --embedded-card-max-width: 44.6875rem;
      }
      .blog-app-card-list :deep(.card-list-item) {
        gap: var(--boxel-sp-xl);
        align-items: flex-start;
        padding: var(--boxel-sp-xs) 0;
      }
      .categories-grid {
        --embedded-card-min-height: 9.375rem;
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

  @action private onChangeView(id: string) {
    if (isViewOption(id)) {
      this.selectedView = id;
    }
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
    // the filter's cardRef is the source of truth; fall back to whichever
    // shape the query filter carries (type filters here, on-filters if a
    // custom query is supplied)
    let filter = this.activeFilter?.query?.filter as
      | { type?: ResolvedCodeRef; on?: ResolvedCodeRef }
      | undefined;
    let ref = this.activeFilter?.cardRef ?? filter?.type ?? filter?.on;

    if (!ref) {
      throw new Error('Missing card ref');
    }
    let currentRealm = this.realms[0];
    let doc: LooseSingleCardDocument = {
      data: {
        type: 'card',
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
