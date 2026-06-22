import GlimmerComponent from '@glimmer/component';

import { type CardContext } from 'https://cardstack.com/base/card-api';

import {
  type Query,
  type RenderableSearchEntryLike,
  type SearchEntryWireQuery,
  searchEntryWireQueryFromQuery,
} from '@cardstack/runtime-common';

type CardFormat = 'embedded' | 'fitted' | 'atom';

interface CardListSignature {
  Args: {
    query: Query;
    realms: string[];
    context?: CardContext;
    format?: CardFormat;
  };
  Blocks: {
    meta: [card: RenderableSearchEntryLike];
  };
  Element: HTMLElement;
}
export class CardList extends GlimmerComponent<CardListSignature> {
  // The v2 `search-entry`-rooted query, adapted from the incoming v1 `Query`.
  // The prerendered format (`embedded` by default) is bound through the query's
  // `htmlQuery` field — the v2 way to select it.
  get searchResultsQuery(): SearchEntryWireQuery {
    let query = searchEntryWireQueryFromQuery(this.args.query);
    let format = this.args.format ?? 'embedded';
    return {
      ...query,
      realms: this.args.realms,
      filter: {
        ...query.filter,
        eq: { ...query.filter?.eq, htmlQuery: { eq: { format } } },
      },
    };
  }
  <template>
    <ul class='card-list' ...attributes>
      {{#let (component @context.searchResultsComponent) as |SearchResults|}}
        <SearchResults @query={{this.searchResultsQuery}} as |results|>
          {{#each results.entries key='id' as |card|}}
            <li class='card-list-item'>
              <card.component class='card' />
              {{#if (has-block 'meta')}}
                {{yield card to='meta'}}
              {{/if}}
            </li>
          {{else}}
            {{#if results.isLoading}}
              Loading...
            {{/if}}
          {{/each}}
        </SearchResults>
      {{/let}}
    </ul>
    <style scoped>
      .card-list {
        display: grid;
        gap: var(--boxel-sp);
        list-style-type: none;
        margin: 0;
        padding: 0;
      }
      .card-list-item {
        display: flex;
        flex-wrap: wrap;
        gap: 0;
        margin: 0;
        padding: 0;
      }
      .card {
        height: auto;
        min-height: var(--embedded-card-min-height, 345px);
        max-width: var(--embedded-card-max-width, 100%);
        width: 100%;
      }
      .bordered-items > .card-list-item > * {
        border-radius: var(--boxel-border-radius);
        box-shadow: inset 0 0 0 1px var(--boxel-light-500);
      }
    </style>
  </template>
}
