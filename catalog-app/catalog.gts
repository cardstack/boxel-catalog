import { tracked } from '@glimmer/tracking';
import { action } from '@ember/object';
import { on } from '@ember/modifier';
import { debounce } from 'lodash';

import {
  contains,
  field,
  Component,
  CardDef,
  realmInfo,
  type BaseDef,
  linksToMany,
  realmURL,
} from 'https://cardstack.com/base/card-api';
import type { Query, AnyFilter, Filter } from '@cardstack/runtime-common';
import { isCardInstance } from '@cardstack/runtime-common';
import StringField from 'https://cardstack.com/base/string';

import FilterSidebar, { type FilterItem } from './components/filter-section';
import CategoryFilterGroup, {
  type SphereConfig,
} from './components/category-filter-group';
import ShowcaseView from './components/showcase-view';
import ListView from './components/list-view';
import TagFilterGroup from './components/tag-filter-group';

import CatalogLayout from './layouts/catalog-layout';

import BuildingBank from '@cardstack/boxel-icons/building-bank';
import BuildingIcon from '@cardstack/boxel-icons/building';
import HealthRecognition from '@cardstack/boxel-icons/health-recognition';
import LayoutGridPlusIcon from '@cardstack/boxel-icons/layout-grid-plus';
import UsersIcon from '@cardstack/boxel-icons/users';
import WorldIcon from '@cardstack/boxel-icons/world';
import { TabbedHeader, BoxelInput } from '@cardstack/boxel-ui/components';

import { Listing } from './listing/listing';

const SPHERES: SphereConfig[] = [
  {
    name: 'WORK',
    id: 'work',
    Icon: BuildingBank,
    query: {
      filter: {
        type: {
          // @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
          module: new URL('./listing/category', import.meta.url).href,
          name: 'Category',
        },
        eq: { 'sphere.name': 'WORK' },
      },
    },
  },
  {
    name: 'PLAY',
    id: 'play',
    Icon: WorldIcon,
    query: {
      filter: {
        type: {
          // @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
          module: new URL('./listing/category', import.meta.url).href,
          name: 'Category',
        },
        eq: { 'sphere.name': 'PLAY' },
      },
    },
  },
  {
    name: 'LIFE',
    id: 'life',
    Icon: HealthRecognition,
    query: {
      filter: {
        type: {
          // @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
          module: new URL('./listing/category', import.meta.url).href,
          name: 'Category',
        },
        eq: { 'sphere.name': 'LIFE' },
      },
    },
  },
  {
    name: 'LEARN',
    id: 'learn',
    Icon: UsersIcon,
    query: {
      filter: {
        type: {
          // @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
          module: new URL('./listing/category', import.meta.url).href,
          name: 'Category',
        },
        eq: { 'sphere.name': 'LEARN' },
      },
    },
  },
  {
    name: 'BUILD',
    id: 'build',
    Icon: BuildingIcon,
    query: {
      filter: {
        type: {
          // @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
          module: new URL('./listing/category', import.meta.url).href,
          name: 'Category',
        },
        eq: { 'sphere.name': 'BUILD' },
      },
    },
  },
];

// Catalog App
class Isolated extends Component<typeof Catalog> {
  tabFilterOptions = [
    {
      tabId: 'showcase',
      displayName: 'Showcase',
    },
    {
      tabId: 'app',
      displayName: 'Apps',
    },
    {
      tabId: 'card',
      displayName: 'Cards',
    },
    {
      tabId: 'field',
      displayName: 'Fields',
    },
    {
      tabId: 'skill',
      displayName: 'Skills',
    },
    {
      tabId: 'theme',
      displayName: 'Themes',
    },
  ];

  @tracked activeTabId: string = this.tabFilterOptions[0].tabId;

  @action
  setActiveTab(tabId: string) {
    this.activeTabId = tabId;
  }

  @tracked activeTags: string[] = [];

  @action
  handleTagSelect(tagUrl: string) {
    let id = tagUrl.replace(/\.json$/, '');
    this.activeTags = this.activeTags.includes(id)
      ? this.activeTags.filter((u) => u !== id)
      : [...this.activeTags, id];
  }

  // Filter Search
  @tracked searchValue: string | undefined = undefined;

  private debouncedSetSearchKey = debounce((value: string) => {
    this.searchValue = value;
  }, 300);

  @action
  onSearchInput(value: string) {
    this.debouncedSetSearchKey(value);
  }

  //query
  get query(): Query {
    return {
      filter: {
        on: {
          // @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
          module: new URL('./listing/listing', import.meta.url).href,
          name:
            this.activeTabId === 'showcase'
              ? 'Listing'
              : `${capitalize(this.activeTabId)}Listing`,
        },
        every: [
          this.sphereOrCategoryFilter,
          this.tagFilter,
          this.searchFilter,
        ].filter(Boolean) as Filter[],
      },
    };
  }

  // Sphere/category filter
  @tracked activeSphereOrCategory: FilterItem | undefined = undefined;

  @action
  handleSphereOrCategorySelect(filterItem: FilterItem) {
    this.activeSphereOrCategory = filterItem;
  }

  get sphereOrCategoryFilter(): Filter | undefined {
    if (
      !this.activeSphereOrCategory ||
      this.activeSphereOrCategory.kind === 'all'
    ) {
      return undefined;
    }

    if (this.activeSphereOrCategory.kind === 'sphere') {
      return this.filterListingsBySphere(this.activeSphereOrCategory.id);
    }

    return this.filterListingsByCategory(this.activeSphereOrCategory.id);
  }

  private filterListingsBySphere(sphereId: string): Filter {
    return {
      eq: { 'categories.sphere.id': sphereId },
    };
  }

  private filterListingsByCategory(categoryId: string): Filter {
    return {
      eq: { 'categories.id': categoryId },
    };
  }

  get tagQuery(): Query {
    return {
      filter: {
        type: {
          // @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
          module: new URL('./listing/tag', import.meta.url).href,
          name: 'Tag',
        },
      },
    };
  }

  get tagFilter(): AnyFilter | undefined {
    if (this.activeTags.length === 0) {
      return undefined;
    }
    return {
      any: this.activeTags.map((id) => ({
        eq: {
          'tags.id': id,
        },
      })),
    };
  }

  get searchFilter(): AnyFilter | undefined {
    if (!this.searchValue || this.searchValue.length === 0) {
      return undefined;
    }
    return {
      any: [{ contains: { cardTitle: this.searchValue } }],
    };
  }

  // end of listing query filter values

  @action resetFilters() {
    this.activeSphereOrCategory = undefined;
    this.searchValue = undefined;
    this.activeTags = [] as string[];
  }

  get shouldShowTab() {
    return (tabId: string) => {
      return this.activeTabId === tabId;
    };
  }

  get hasActiveFilters() {
    return (
      this.activeSphereOrCategory !== undefined ||
      this.searchValue !== undefined ||
      this.activeTags.length > 0
    );
  }

  get hasNoActiveFilters() {
    return !this.hasActiveFilters;
  }

  get isShowcaseView() {
    return this.activeTabId === 'showcase' && this.hasNoActiveFilters;
  }

  get navigationButtonText() {
    if (this.activeTabId === 'showcase') {
      return 'Catalog Home';
    }
    const tabOption = this.tabFilterOptions.find(
      (tab) => tab.tabId === this.activeTabId,
    );
    return tabOption ? `All ${tabOption.displayName}` : 'Catalog Home';
  }

  get headerColor() {
    return (
      Object.getPrototypeOf(this.args.model).constructor.headerColor ??
      undefined
    );
  }

  private get realms() {
    return [this.args.model[realmURL]!];
  }

  get realmHrefs() {
    return this.realms.map((realm) => realm.href);
  }

  <template>
    <CatalogLayout
      data-test-catalog-app
      class='catalog-layout {{this.activeTabId}}'
    >
      <:header>
        <TabbedHeader
          @tabs={{this.tabFilterOptions}}
          @setActiveTab={{this.setActiveTab}}
          @activeTabId={{this.activeTabId}}
          @headerBackgroundColor={{this.headerColor}}
          class='catalog-tab-header'
        >
          <:sideContent>
            <BoxelInput
              @type='search'
              @value={{this.searchValue}}
              @onInput={{this.onSearchInput}}
              placeholder='Search by Title'
              data-test-filter-search-input
              class='catalog-search-input'
            />
          </:sideContent>
        </TabbedHeader>
      </:header>
      <:sidebar>
        <div class='sidebar-content'>
          <button
            class='navigation-button
              {{if this.hasNoActiveFilters "is-selected"}}'
            {{on 'click' this.resetFilters}}
            data-test-navigation-reset-button={{this.activeTabId}}
          >
            <img
              src='https://boxel-images.boxel.ai/icons/icon_catalog_rounded.png'
              alt='Catalog Icon'
              class='catalog-icon'
            />
            <span class='button-text'>{{this.navigationButtonText}}</span>
          </button>

          <FilterSidebar>
            <:categories>
              <CategoryFilterGroup
                @activeSphereOrCategory={{this.activeSphereOrCategory}}
                @onSelect={{this.handleSphereOrCategorySelect}}
                @realmHrefs={{this.realmHrefs}}
                @spheres={{SPHERES}}
                @context={{@context}}
              />
            </:categories>
            <:tags>
              <TagFilterGroup
                @activeTags={{this.activeTags}}
                @onTagSelect={{this.handleTagSelect}}
                @realmHrefs={{this.realmHrefs}}
                @tagQuery={{this.tagQuery}}
                @context={{@context}}
              />
            </:tags>
          </FilterSidebar>
        </div>
      </:sidebar>
      <:content>
        <div class='content-area-container {{this.activeTabId}}'>
          <div class='content-area'>
            <div class='catalog-content'>
              <div class='catalog-listing info-box'>
                {{#if this.isShowcaseView}}
                  <ShowcaseView
                    @startHereListings={{@model.startHere}}
                    @newListings={{@model.new}}
                    @featuredListings={{@model.featured}}
                    @context={{@context}}
                    data-test-showcase-view
                  />
                {{else}}
                  <ListView
                    @query={{this.query}}
                    @realms={{this.realmHrefs}}
                    @context={{@context}}
                    data-test-catalog-list-view
                  />
                {{/if}}
              </div>
            </div>
          </div>
        </div>
      </:content>
    </CatalogLayout>

    <style scoped>
      .catalog-tab-header {
        position: sticky;
        top: 0;
        z-index: 10;
        container-name: catalog-tab-header;
        container-type: inline-size;
      }
      .catalog-tab-header :deep(.app-title-group) {
        display: none;
      }
      .catalog-tab-header :deep(.app-content) {
        gap: var(--boxel-sp-xxs);
      }
      .catalog-search-input {
        width: 300px;
        outline: 1px solid var(--boxel-light);
      }

      .info-box {
        width: 100%;
        height: auto;
        border-radius: var(--boxel-border-radius);
        background-color: var(--boxel-light);
      }

      /* Layout */
      .catalog-layout {
        --layout-theme-color: #a66efa;
        --layout-container-background-color: #eeedf7;
        --layout-sidebar-background-color: #eeedf7;
        --layout-content-padding: var(--boxel-sp-xl);
      }

      /* Sidebar */
      .sidebar-content {
        padding: var(--boxel-sp);
        overflow-y: auto;
      }
      .sidebar-content > * + * {
        margin-top: var(--boxel-sp);
      }

      /* Container */
      .content-area-container {
        flex: 1;
        height: auto;
        container-name: content-area-container;
        container-type: inline-size;
      }

      .content-area {
        height: 100%;
        display: grid;
        gap: var(--boxel-sp-lg);
      }
      .catalog-content {
        display: block;
      }
      .catalog-listing {
        background-color: transparent;
        display: flex;
        flex-direction: column;
      }

      /* Sidebar */
      .navigation-button {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        width: 100%;
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        border: none;
        background: var(--boxel-light);

        color: var(--boxel-dark);
        font: 500 var(--boxel-font-sm);
        letter-spacing: var(--boxel-lsp-xs);
        text-align: left;
        border-radius: var(--boxel-border-radius-sm);
        cursor: pointer;
      }
      .navigation-button:hover {
        background-color: var(--boxel-300);
      }
      .navigation-button.is-selected {
        background-color: var(--boxel-dark);
        color: var(--boxel-light);
      }
      .catalog-icon {
        width: 16px;
        height: 16px;
      }
      .button-text {
        white-space: nowrap;
        text-overflow: ellipsis;
        overflow: hidden;
      }

      @container catalog-tab-header (inline-size <= 500px) {
        .catalog-search-input {
          width: 100cqw;
        }
      }

      @container content-area-container (inline-size <= 768px) {
        .content-area {
          grid-template-columns: 1fr;
          overflow-y: auto;
        }
      }
    </style>
  </template>
}

export class Catalog extends CardDef {
  static displayName = 'Catalog';
  static icon = LayoutGridPlusIcon;
  static isolated = Isolated;
  static prefersWideFormat = true;
  static headerColor = '#9f3bf9';
  @field realmName = contains(StringField, {
    computeVia: function (this: Catalog) {
      return this[realmInfo]?.name;
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: Catalog) {
      return this.realmName;
    },
  });
  @field startHere = linksToMany(() => Listing);
  @field new = linksToMany(() => Listing);
  @field featured = linksToMany(() => Listing);

  static getDisplayName(instance: BaseDef) {
    if (isCardInstance(instance)) {
      return (instance as CardDef)[realmInfo]?.name ?? this.displayName;
    }
    return this.displayName;
  }
}

const capitalize = (str: string) => str[0].toUpperCase() + str.slice(1);
