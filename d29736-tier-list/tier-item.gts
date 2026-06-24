import {
  CardDef,
  Component,
  contains,
  field,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';

import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';

import ImageIcon from '@cardstack/boxel-icons/image';

// Catalog Field listing "Image Source": one field that is EITHER a pasted URL
// OR an uploaded ImageDef, with a toggle editor and a computed `resolvedUrl`.
import ImageSourceField from './fields/image-source/image-source';

class TierItemIsolated extends Component<typeof TierItem> {
  @tracked imgBroken = false;
  markBroken = () => {
    this.imgBroken = true;
  };
  get showImg(): boolean {
    return Boolean(this.args.model.image?.resolvedUrl) && !this.imgBroken;
  }

  <template>
    <article class='item'>
      {{#if this.showImg}}
        <img
          src={{@model.image.resolvedUrl}}
          alt={{@model.name}}
          class='hero'
          {{on 'error' this.markBroken}}
        />
      {{/if}}
      <h1><@fields.cardTitle /></h1>
    </article>
    <style scoped>
      .item {
        display: grid;
        gap: 1rem;
        justify-items: center;
        padding: 1.5rem;
        background: var(--background, #15161a);
        color: var(--foreground, #f4f5f7);
        font-family: var(--font-sans, system-ui, sans-serif);
      }
      .hero {
        max-width: 12rem;
        max-height: 12rem;
        object-fit: contain;
      }
      h1 {
        margin: 0;
        font-size: 1.25rem;
      }
    </style>
  </template>
}

class TierItemEmbedded extends Component<typeof TierItem> {
  @tracked imgBroken = false;
  markBroken = () => {
    this.imgBroken = true;
  };
  get showImg(): boolean {
    return Boolean(this.args.model.image?.resolvedUrl) && !this.imgBroken;
  }

  <template>
    <span class='item-chip'>
      {{#if this.showImg}}
        <img
          src={{@model.image.resolvedUrl}}
          alt={{@model.name}}
          class='thumb'
          {{on 'error' this.markBroken}}
        />
      {{/if}}
      <span>{{@model.name}}</span>
    </span>
    <style scoped>
      .item-chip {
        display: inline-flex;
        align-items: center;
        gap: 0.5rem;
      }
      .thumb {
        width: 1.5rem;
        height: 1.5rem;
        object-fit: contain;
      }
    </style>
  </template>
}

class TierItemFitted extends Component<typeof TierItem> {
  @tracked imgBroken = false;
  markBroken = () => {
    this.imgBroken = true;
  };
  get showImg(): boolean {
    return Boolean(this.args.model.image?.resolvedUrl) && !this.imgBroken;
  }

  <template>
    <div class='cq'>
      <article class='fit'>
        {{#if this.showImg}}
          <div class='r-hero'>
            <img
              src={{@model.image.resolvedUrl}}
              alt={{@model.name}}
              {{on 'error' this.markBroken}}
            />
          </div>
        {{/if}}
        <div class='r-head'>
          <span class='label'>{{@model.name}}</span>
        </div>
      </article>
    </div>
    <style scoped>
      .cq {
        container-type: size;
        container-name: card;
        width: 100%;
        height: 100%;
        overflow: hidden;
      }
      .fit {
        --type-base: clamp(10px, calc(4px + 2.4cqi + 1cqb), 16px);
        width: 100%;
        height: 100%;
        /* Flex-center so a name-only card (no image) sits dead center instead
           of pinned to a top grid row. With an image, the image fills and the
           label tucks underneath. */
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 2px;
        padding: 4px;
        box-sizing: border-box;
        overflow: hidden;
        background: var(--card, #1c1e24);
        color: var(--foreground, #f4f5f7);
        font-family: var(--font-sans, system-ui, sans-serif);
      }
      .r-hero {
        flex: 1 1 auto;
        width: 100%;
        min-height: 0;
        display: flex;
        align-items: center;
        justify-content: center;
        overflow: hidden;
      }
      .r-hero img {
        max-width: 100%;
        max-height: 100%;
        object-fit: contain;
      }
      .r-head {
        flex: 0 0 auto;
        width: 100%;
        min-height: 0;
        overflow: hidden;
      }
      .label {
        display: -webkit-box;
        -webkit-box-orient: vertical;
        -webkit-line-clamp: 3;
        font-size: var(--type-base, 11px);
        font-weight: 600;
        text-align: center;
        line-height: 1.15;
        overflow: hidden;
        overflow-wrap: anywhere;
      }
      @container card (height <= 56px) {
        .r-hero {
          display: none;
        }
      }
    </style>
  </template>
}

class TierItemAtom extends Component<typeof TierItem> {
  <template>
    <span><@fields.cardTitle /></span>
  </template>
}

// A rankable thing (a Pokémon, a movie, a logo). Its own card, so it can be
// edited (incl. image upload) on its own page. Created in bulk by a TierList's
// "Generate with AI" action and linked into its `items` pool. Ranking is NOT
// stored here — it lives on the TierList's placements, keyed by this card's id.
export class TierItem extends CardDef {
  static displayName = 'Tier Item';
  static icon = ImageIcon;

  @field name = contains(StringField);
  @field image = contains(ImageSourceField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: TierItem) {
      return this.cardInfo?.name?.trim() || this.name || 'Untitled Item';
    },
  });

  static isolated = TierItemIsolated;
  static embedded = TierItemEmbedded;
  static fitted = TierItemFitted;
  static atom = TierItemAtom;
}
