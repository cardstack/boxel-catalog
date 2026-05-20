import GlimmerComponent from '@glimmer/component';

import { type CardContext } from 'https://cardstack.com/base/card-api';

import {
  type Query,
  type PrerenderedCardLike,
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
    meta: [card: PrerenderedCardLike];
  };
  Element: HTMLElement;
}
export class CardList extends GlimmerComponent<CardListSignature> {
  <template>
    <ul class='card-list' ...attributes>
      {{#let
        (component @context.prerenderedCardSearchComponent)
        as |PrerenderedCardSearch|
      }}
        <PrerenderedCardSearch
          @query={{@query}}
          @format={{if @format @format 'embedded'}}
          @realms={{@realms}}
          @isLive={{true}}
        >
          <:loading>
            Loading...
          </:loading>
          <:response as |cards|>
            {{#each cards key='url' as |card|}}
              <li class='card-list-item'>
                <card.component class='card' />
                {{#if (has-block 'meta')}}
                  {{yield card to='meta'}}
                {{/if}}
              </li>
            {{/each}}
          </:response>
        </PrerenderedCardSearch>
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
