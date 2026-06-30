import {
  CardDef,
  Component,
  field,
  contains,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import enumField from 'https://cardstack.com/base/enum';
import ImageSourceField from '@cardstack/catalog/fields/image-source/image-source';
import ShirtIcon from '@cardstack/boxel-icons/shirt';

// Garment slot categories. full-body = one-piece dress/jumpsuit, mutually
// exclusive with a separate top + bottom. Single source of truth — the
// try-on app derives its category filters and slot labels from this list.
export const GARMENT_CATEGORIES = [
  { value: 'full-body', label: 'Full Body' },
  { value: 'top', label: 'Top' },
  { value: 'bottom', label: 'Bottom' },
  { value: 'shoes', label: 'Shoes' },
  { value: 'outerwear', label: 'Outerwear' },
  { value: 'accessory', label: 'Accessory' },
] as const;

export const CategoryField = enumField(StringField, {
  options: GARMENT_CATEGORIES,
  displayName: 'Category',
});

export class Garment extends CardDef {
  static displayName = 'Garment';

  @field image = contains(ImageSourceField, { searchable: 'file' });
  @field category = contains(CategoryField);

  static fitted = class Fitted extends Component<typeof Garment> {
    <template>
      {{! A garment is a visual item — its identity IS the image, so every
          fitted size simply fills with the product photo. The name only
          surfaces as a caption overlay in the largest `card` size, where a
          full grid cell has room for it; the icon stands in when there's no
          image. Choosers, tiles, and badges therefore read as pure imagery. }}
      <div class='garment-fitted'>
        {{#if @model.image.resolvedUrl}}
          <img
            src={{@model.image.resolvedUrl}}
            alt={{@model.cardTitle}}
            class='garment-img'
          />
        {{else}}
          <ShirtIcon class='garment-fallback' />
        {{/if}}
        <span class='garment-caption'>{{@model.cardTitle}}</span>
      </div>
      <style scoped>
        /* Mirror the virtual-try-on app's warm palette so a Garment looks the
           same whether rendered standalone or inside the app's tiles (the card
           is scoped, so it can't read the app's .app tokens — restate them). */
        .garment-fitted {
          --surface2: #f1efea;
          --muted: #8c887d;
          position: relative;
          display: flex;
          align-items: center;
          justify-content: center;
          width: 100%;
          height: 100%;
          overflow: hidden;
          background-color: var(--surface2);
        }
        .garment-img {
          width: 100%;
          height: 100%;
          object-fit: cover;
        }
        .garment-fallback {
          width: 20%;
          height: 20%;
          color: var(--muted);
        }
        /* Caption hidden by default; only the `card` size reveals it. */
        .garment-caption {
          display: none;
        }

        /* ── Card: ≥400px wide, ≥170px tall — name caption over the image ── */
        @container fitted-card (min-width: 400px) and (min-height: 170px) {
          .garment-caption {
            display: block;
            position: absolute;
            inset-inline: 0;
            inset-block-end: 0;
            padding: var(--boxel-sp-xl) var(--boxel-sp) var(--boxel-sp-xs);
            font: 700 15px/1.2 var(--boxel-font-family, system-ui, sans-serif);
            color: #fff;
            background: linear-gradient(to top, rgb(0 0 0 / 65%), transparent);
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
          }
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof Garment> {
    <template>
      <div class='garment-embedded'>
        {{#if @model.image.resolvedUrl}}
          <img
            src={{@model.image.resolvedUrl}}
            alt={{@model.cardTitle}}
            class='thumb'
          />
        {{/if}}
        <div class='details'>
          <h3 class='name'>{{@model.cardTitle}}</h3>
          <span class='category'>{{@model.category}}</span>
        </div>
      </div>
      <style scoped>
        /* Same warm palette as the fitted format / the virtual-try-on app, so
           an embedded Garment reads consistently wherever it appears. */
        .garment-embedded {
          --surface2: #f1efea;
          --text: #1a1a1c;
          --muted: #8c887d;
          display: flex;
          align-items: flex-start;
          gap: var(--boxel-sp-sm);
          color: var(--text);
        }
        .thumb {
          width: 64px;
          height: 64px;
          object-fit: cover;
          border-radius: 10px;
          background-color: var(--surface2);
          flex-shrink: 0;
        }
        .details {
          display: flex;
          flex-direction: column;
          gap: 2px;
        }
        .name {
          margin: 0;
          font-size: inherit;
          font-weight: 600;
        }
        .category {
          font-size: var(--boxel-font-size-sm);
          color: var(--muted);
          text-transform: capitalize;
        }
      </style>
    </template>
  };
}
