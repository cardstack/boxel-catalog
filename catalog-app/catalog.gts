import { tracked } from '@glimmer/tracking';
import { action } from '@ember/object';
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

import LayoutGridPlusIcon from '@cardstack/boxel-icons/layout-grid-plus';

import CatalogLayout from './layouts/catalog-layout';
import StorefrontHeader from './components/storefront-header';
import StorefrontHero from './components/storefront-hero';
import StorefrontHowItWorks from './components/storefront-how-it-works';
import StorefrontFooter from './components/storefront-footer';
import TypeFilterPills from './components/type-filter-pills';
import { CardsGrid } from './components/grid';

import { Listing } from './listing/listing';

const TAB_OPTIONS = [
  { tabId: 'showcase', displayName: 'Showcase' },
  { tabId: 'card', displayName: 'Cards' },
  { tabId: 'field', displayName: 'Fields' },
  { tabId: 'skill', displayName: 'Skills' },
  { tabId: 'component', displayName: 'Components' },
  { tabId: 'theme', displayName: 'Themes' },
];

const capitalize = (str: string) => str[0].toUpperCase() + str.slice(1);

class Isolated extends Component<typeof Catalog> {
  tabFilterOptions = TAB_OPTIONS;

  @tracked activeTabId = 'showcase';
  @tracked searchValue: string | undefined = undefined;

  @action setActiveTab(tabId: string) {
    this.activeTabId = tabId;
  }

  // Pill 'all' is the Showcase tab; the type pills mirror the nav tabs.
  get activePillKey() {
    return this.activeTabId === 'showcase' ? 'all' : this.activeTabId;
  }

  @action selectPill(key: string) {
    this.activeTabId = key === 'all' ? 'showcase' : key;
  }

  private debouncedSetSearchKey = debounce((value: string) => {
    this.searchValue = value || undefined;
  }, 300);

  @action onSearchInput(value: string) {
    this.debouncedSetSearchKey(value);
  }

  @action resetFilters() {
    this.activeTabId = 'showcase';
    this.searchValue = undefined;
  }

  get listingModule() {
    // @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
    return new URL('./listing/listing', import.meta.url).href;
  }

  get query(): Query {
    return {
      filter: {
        on: {
          // @ts-expect-error module href is a string; CodeRef typing is stricter
          module: this.listingModule,
          name:
            this.activeTabId === 'showcase'
              ? 'Listing'
              : `${capitalize(this.activeTabId)}Listing`,
        },
        every: [this.searchFilter].filter(Boolean) as Filter[],
      },
    };
  }

  get searchFilter(): AnyFilter | undefined {
    if (!this.searchValue || this.searchValue.length === 0) {
      return undefined;
    }
    return {
      any: [
        { matches: this.searchValue },
        { contains: { cardTitle: this.searchValue } },
      ],
    };
  }

  get hasActiveFilters() {
    return this.searchValue !== undefined;
  }

  get isShowcaseView() {
    return this.activeTabId === 'showcase' && !this.hasActiveFilters;
  }

  get galleryTitle() {
    if (this.activeTabId === 'showcase') {
      return 'The Catalog';
    }
    let tab = this.tabFilterOptions.find((t) => t.tabId === this.activeTabId);
    return tab ? tab.displayName : 'The Catalog';
  }

  private get realms() {
    return [this.args.model[realmURL]!];
  }

  get realmHrefs() {
    return this.realms.map((realm) => realm.href);
  }

  private scrollTo(selector: string) {
    if (typeof document === 'undefined') {
      return;
    }
    document
      .querySelector(selector)
      ?.scrollIntoView({ behavior: 'smooth', block: 'start' });
  }

  @action scrollToGallery() {
    this.scrollTo('[data-catalog-gallery]');
  }

  @action scrollToHowItWorks() {
    this.scrollTo('[data-catalog-howitworks]');
  }

  <template>
    <CatalogLayout
      class='catalog-storefront'
      @showSidebar={{false}}
      data-test-catalog-app
    >
      <:header>
        <StorefrontHeader
          @tabs={{this.tabFilterOptions}}
          @activeTabId={{this.activeTabId}}
          @onSelectTab={{this.setActiveTab}}
          @searchValue={{this.searchValue}}
          @onSearchInput={{this.onSearchInput}}
        />
      </:header>
      <:content>
        <div class='storefront-body'>
          {{#if this.isShowcaseView}}
            <StorefrontHero
              @featured={{@model.featured}}
              @onBrowse={{this.scrollToGallery}}
              @onHowItWorks={{this.scrollToHowItWorks}}
              @context={{@context}}
            />
            <StorefrontHowItWorks />
          {{/if}}

          <section
            class='gallery'
            data-catalog-gallery
            data-test-catalog-gallery
          >
            <div class='gallery-head'>
              <div>
                <h2 class='gallery-title'>{{this.galleryTitle}}</h2>
                <p class='gallery-sub'>Hand-built, fork-ready. Hover any card to
                  preview it live — then remix.</p>
              </div>
              <TypeFilterPills
                @listingModule={{this.listingModule}}
                @activeKey={{this.activePillKey}}
                @onSelect={{this.selectPill}}
                @realms={{this.realmHrefs}}
                @context={{@context}}
              />
            </div>

            <CardsGrid
              @query={{this.query}}
              @realms={{this.realmHrefs}}
              @selectedView='grid'
              @onClear={{this.resetFilters}}
              @context={{@context}}
              data-test-catalog-grid
            />
          </section>

          <StorefrontFooter />
        </div>
      </:content>
    </CatalogLayout>

    <style scoped>
      .catalog-storefront {
        /* Catalog-domain signal colors (the general palette/fonts come from the
           linked Catalog Storefront theme via cardInfo.theme). */
        --type-card: var(--chart-1, #ff5b9c);
        --type-component: var(--chart-2, #2bb3ff);
        --type-field: var(--chart-3, #7b5bff);
        --type-skill: var(--chart-4, #c2e23f);
        --type-theme: var(--chart-5, #ff9d3d);
        --type-app: var(--brand, #6c4bf5);
        --brand: #6c4bf5;
        --layout-container-background-color: var(--background, #ece9e1);
        --layout-content-padding: 0;
        background: var(--background, #ece9e1);
        color: var(--foreground, #16161c);
        font-family: var(--font-sans, 'IBM Plex Sans', sans-serif);
      }

      .storefront-body {
        min-height: 100%;
      }
      .gallery {
        max-width: 80rem;
        margin: 0 auto;
        padding: 3rem 2rem 5.625rem;
        scroll-margin-top: 0;
      }
      .gallery-head {
        display: flex;
        align-items: flex-end;
        justify-content: space-between;
        gap: 1.25rem;
        flex-wrap: wrap;
        margin-bottom: 1.625rem;
      }
      .gallery-title {
        margin: 0;
        font: 700 1.875rem/1 var(--font-sans, 'IBM Plex Sans', sans-serif);
        letter-spacing: -0.025em;
        color: var(--foreground, #16161c);
      }
      .gallery-sub {
        margin: 0.5rem 0 0;
        font: 400 0.875rem/1.4 var(--font-sans, 'IBM Plex Sans', sans-serif);
        color: var(--muted-foreground, #6b675e);
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
