import { fn } from '@ember/helper';
import { on } from '@ember/modifier';
import GlimmerComponent from '@glimmer/component';

import type { CardContext } from 'https://cardstack.com/base/card-api';
import type { Query } from '@cardstack/runtime-common';
import {
  searchEntryWireQueryFromQuery,
  type SearchEntryWireQuery,
} from '@cardstack/runtime-common';
import { Pill, SkeletonPlaceholder } from '@cardstack/boxel-ui/components';

interface TagFilterGroupArgs {
  Args: {
    activeTags: string[];
    onTagSelect: (tagUrl: string) => void;
    realmHrefs: string[];
    tagQuery: Query;
    context?: CardContext;
  };
}

export default class TagFilterGroup extends GlimmerComponent<TagFilterGroupArgs> {
  isTagActive = (url: string) =>
    this.args.activeTags.includes(url.replace(/\.json$/, ''));

  // The v2 `search-entry`-rooted query, adapted from the incoming v1 `tagQuery`.
  // `atom` is bound through the query's `htmlQuery` field — the v2 way to select
  // a prerendered format.
  get searchResultsQuery(): SearchEntryWireQuery {
    let query = searchEntryWireQueryFromQuery(this.args.tagQuery);
    return {
      ...query,
      realms: this.args.realmHrefs,
      filter: {
        ...query.filter,
        eq: { ...query.filter?.eq, htmlQuery: { eq: { format: 'atom' } } },
      },
    };
  }

  <template>
    <@context.searchResultsComponent
      @query={{this.searchResultsQuery}}
      as |results|
    >
      {{#if results.entries.length}}
        <div class='tag-pill-list'>
          {{#each results.entries key='id' as |tag|}}
            <Pill
              @kind='button'
              class='tag-pill-btn {{if (this.isTagActive tag.id) "is-active"}}'
              {{on 'click' (fn @onTagSelect tag.id)}}
            >
              <tag.component class='hide-boundaries' />
            </Pill>
          {{/each}}
        </div>
      {{else if results.isLoading}}
        <SkeletonPlaceholder class='tag-skeleton' />
      {{/if}}
    </@context.searchResultsComponent>

    <style scoped>
      .tag-pill-list {
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp-2xs);
      }
      .tag-pill-btn {
        padding: 0;
        margin: 0;
      }
      .tag-pill-btn :deep(.atom-format) {
        box-shadow: none;
        background: transparent;
      }
      .tag-pill-btn.is-active {
        --boxel-pill-background-color: var(--boxel-dark);
        --boxel-pill-border-color: var(--boxel-dark);
      }
      .tag-pill-btn.is-active :deep(.atom-format) {
        color: var(--boxel-light);
      }

      .tag-skeleton {
        height: 20px;
        width: 100%;
      }
    </style>
  </template>
}
