import { fn } from '@ember/helper';
import { on } from '@ember/modifier';
import GlimmerComponent from '@glimmer/component';

import type { CardContext } from 'https://cardstack.com/base/card-api';
import type { Query } from '@cardstack/runtime-common';
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

  <template>
    {{#let
      (component @context.prerenderedCardSearchComponent)
      as |PrerenderedCardSearch|
    }}
      <PrerenderedCardSearch
        @query={{@tagQuery}}
        @format='atom'
        @realms={{@realmHrefs}}
        @isLive={{true}}
      >
        <:loading>
          <SkeletonPlaceholder class='tag-skeleton' />
        </:loading>
        <:response as |tags|>
          <div class='tag-pill-list'>
            {{#each tags key='url' as |tag|}}
              <Pill
                @kind='button'
                class='tag-pill-btn
                  {{if (this.isTagActive tag.url) "is-active"}}'
                {{on 'click' (fn @onTagSelect tag.url)}}
              >
                <tag.component class='hide-boundaries' />
              </Pill>
            {{/each}}
          </div>
        </:response>
      </PrerenderedCardSearch>
    {{/let}}

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
