import { action } from '@ember/object';
import { fn } from '@ember/helper';
import { on } from '@ember/modifier';
import { tracked } from '@glimmer/tracking';
import GlimmerComponent from '@glimmer/component';

import type { CardContext } from 'https://cardstack.com/base/card-api';
import type { Query, PrerenderedCardLike } from '@cardstack/runtime-common';
import {
  Button,
  Pill,
  SkeletonPlaceholder,
} from '@cardstack/boxel-ui/components';
import { eq } from '@cardstack/boxel-ui/helpers';

import ChevronDown from '@cardstack/boxel-icons/chevron-down';
import FolderIcon from '@cardstack/boxel-icons/folder';
import LayoutGridPlusIcon from '@cardstack/boxel-icons/layout-grid-plus';
import type IconComponent from '@cardstack/boxel-icons/captions';

import type { FilterItem } from './filter-section';

export type SphereConfig = {
  name: string;
  id: string;
  Icon: typeof IconComponent;
  query: Query;
};

interface CategoryFilterGroupArgs {
  Args: {
    activeSphereOrCategory?: FilterItem;
    onSelect: (filterItem: FilterItem) => void;
    realmHrefs: string[];
    spheres: SphereConfig[];
    context?: CardContext;
  };
}

export default class CategoryFilterGroup extends GlimmerComponent<CategoryFilterGroupArgs> {
  @tracked expandedSpheres: Set<string> = new Set();

  isSphereExpanded = (id: string) => this.expandedSpheres.has(id);

  sphereUrl = (sphereId: string) =>
    `${this.args.realmHrefs[0]}Sphere/${sphereId}`;

  categoryIdFromUrl = (url: string) => url.replace(/\.json$/, '');

  @action toggleSphere(sphereId: string) {
    const next = new Set(this.expandedSpheres);
    next.has(sphereId) ? next.delete(sphereId) : next.add(sphereId);
    this.expandedSpheres = next;
  }

  @action selectAll() {
    this.args.onSelect({
      id: 'all',
      displayName: 'All',
      kind: 'all',
    });
  }

  @action selectSphere(sphere: SphereConfig) {
    this.args.onSelect({
      id: this.sphereUrl(sphere.id),
      displayName: sphere.name,
      kind: 'sphere',
    });
  }

  @action selectCategory(cat: PrerenderedCardLike) {
    this.args.onSelect({
      id: cat.url.replace(/\.json$/, ''),
      displayName: displayNameFromUrl(cat.url),
      kind: 'category',
    });
  }

  <template>
    <ul class='filter-list'>
      <li
        class='filter-list-item'
      >
        <span
          class='list-item-buttons
            {{if (eq @activeSphereOrCategory.id "all") "is-selected"}}'
        >
          <Button
            @kind='text-only'
            @size='small'
            class='filter-list__button'
            {{on 'click' this.selectAll}}
          >
            <LayoutGridPlusIcon class='filter-list__icon' role='presentation' />
            <span class='filter-name boxel-ellipsize'>All</span>
          </Button>
        </span>
      </li>

      {{#let
        (component @context.prerenderedCardSearchComponent)
        as |PrerenderedCardSearch|
      }}
        {{#each @spheres as |sphere|}}
          <PrerenderedCardSearch
            @query={{sphere.query}}
            @format='atom'
            @realms={{@realmHrefs}}
            @isLive={{true}}
          >
            <:loading>
              <li class='filter-list-item'>
                <SkeletonPlaceholder class='sphere-skeleton' />
              </li>
            </:loading>
            <:response as |categories|>
              <li
                class='filter-list-item'
              >
                <span
                  class='list-item-buttons
                    {{if
                      (eq @activeSphereOrCategory.id (this.sphereUrl sphere.id))
                      "is-selected"
                    }}
                    {{if (this.isSphereExpanded sphere.id) "is-expanded"}}'
                >
                  <Button
                    @kind='text-only'
                    @size='small'
                    class='filter-list__button'
                    {{on 'click' (fn this.selectSphere sphere)}}
                  >
                    <sphere.Icon
                      class='filter-list__icon'
                      role='presentation'
                    />
                    <span
                      class='filter-name boxel-ellipsize'
                    >{{sphere.name}}</span>
                  </Button>
                  <button
                    class='dropdown-toggle'
                    aria-label='Toggle {{sphere.name}} group'
                    {{on 'click' (fn this.toggleSphere sphere.id)}}
                  >
                    <ChevronDown class='caret-icon' />
                  </button>
                </span>
                {{#if (this.isSphereExpanded sphere.id)}}
                  <div class='category-pill-list'>
                    {{#each categories key='url' as |cat|}}
                      <Pill
                        @kind='button'
                        class='category-pill-btn
                          {{if
                            (eq
                              @activeSphereOrCategory.id (this.categoryIdFromUrl cat.url)
                            )
                            "is-active"
                          }}'
                        {{on 'click' (fn this.selectCategory cat)}}
                      >
                        <FolderIcon
                          class='category-pill-icon'
                          role='presentation'
                        />
                        <cat.component class='hide-boundaries' />
                      </Pill>
                    {{/each}}
                  </div>
                {{/if}}
              </li>
            </:response>
          </PrerenderedCardSearch>
        {{/each}}
      {{/let}}
    </ul>

    <style scoped>
      .filter-list {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-4xs);
        list-style-type: none;
        padding-inline-start: 0;
        margin-block: 0;
      }

      .list-item-buttons {
        display: flex;
        border-radius: var(--boxel-border-radius-sm);
        color: inherit;
        background-color: inherit;
      }
      .list-item-buttons.is-expanded {
        background-color: var(--boxel-filter-expanded-background, transparent);
      }
      .list-item-buttons:not(.is-selected):hover {
        background-color: var(
          --boxel-filter-hover-background,
          var(--boxel-300)
        );
      }
      .list-item-buttons.is-selected {
        background-color: var(
          --boxel-filter-selected-background,
          var(--foreground, var(--boxel-dark))
        );
        color: var(
          --boxel-filter-selected-foreground,
          var(--background, var(--boxel-light))
        );
      }

      .filter-list__button {
        flex-grow: 1;
        width: 100%;
        display: flex;
        justify-content: flex-start;
        gap: var(--boxel-sp-xs);
        font: 500 var(--boxel-font-sm);
        font-family: inherit;
        letter-spacing: var(--boxel-lsp-xs);
        border-radius: var(--boxel-border-radius-sm);
        max-width: 100%;
        overflow: hidden;
        text-align: left;
        border: none;
        background: transparent;
        cursor: pointer;
        padding: var(--boxel-sp-4xs) var(--boxel-sp-xs);
        color: inherit;
      }
      .filter-list__button:hover,
      .filter-list__button:focus {
        color: inherit;
        background-color: transparent;
      }

      .filter-list__icon {
        flex-shrink: 0;
        width: var(--boxel-icon-xs);
        height: var(--boxel-icon-xs);
        vertical-align: top;
      }

      .filter-name {
        flex-grow: 1;
      }

      .dropdown-toggle {
        display: flex;
        align-items: center;
        justify-content: center;
        width: 2rem;
        height: 2rem;
        flex-shrink: 0;
        border: none;
        background: transparent;
        cursor: pointer;
        color: inherit;
        border-radius: var(--boxel-border-radius-sm);
      }
      .is-expanded > .dropdown-toggle {
        transform: rotate(180deg);
      }
      .caret-icon {
        width: 10px;
        height: 10px;
      }

      .sphere-skeleton {
        height: 20px;
        width: 100%;
      }

      .category-pill-list {
        display: flex;
        flex-direction: column;
        padding-inline-start: var(--boxel-sp);
      }
      .category-pill-btn {
        --boxel-pill-background-color: transparent;
        --boxel-pill-border-color: transparent;
        width: 100%;
        padding: var(--boxel-sp-4xs) var(--boxel-sp-xs);
        margin: 0;
        display: flex;
        align-items: center;
        text-align: left;
      }
      .category-pill-btn :deep(.atom-format) {
        box-shadow: none;
        background: transparent;
      }
      .category-pill-btn:hover {
        --boxel-pill-background-color: var(--boxel-300);
      }
      .category-pill-btn.is-active {
        --boxel-pill-background-color: var(--boxel-dark);
        --boxel-pill-border-color: var(--boxel-dark);
        color: var(--boxel-light);
      }
      .category-pill-btn.is-active :deep(.atom-format) {
        color: var(--boxel-light);
      }
      .category-pill-icon {
        flex-shrink: 0;
        width: var(--boxel-icon-xs);
        height: var(--boxel-icon-xs);
      }
    </style>
  </template>
}

function displayNameFromUrl(url: string): string {
  const slug = url.replace(/\.json$/, '').split('/').pop() ?? '';
  return slug.replace(/-/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());
}
