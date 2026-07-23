import {
  FieldDef,
  field,
  contains,
  containsMany,
  linksTo,
  Component,
  ImageDef,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import PhotoIcon from '@cardstack/boxel-icons/photo';

import ImageSourceField from '../image-source/image-source';
import MultiImageSourceEditor from './components/multi-image-source-editor';

class EmbeddedTemplate extends Component<typeof MultiImageSourceField> {
  <template>
    {{#if @model.resolvedUrls.length}}
      <ul class='images' data-test-multi-image-source-embedded>
        {{#each @model.resolvedUrls as |url|}}
          <li class='image'>
            <img src={{url}} loading='lazy' alt='' />
          </li>
        {{/each}}
      </ul>
    {{/if}}
    <style scoped>
      .images {
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp-xs);
        margin: 0;
        padding: 0;
        list-style: none;
      }
      .image img {
        display: block;
        width: 4rem;
        aspect-ratio: 1;
        object-fit: cover;
        border-radius: var(--boxel-border-radius-sm, 6px);
        border: 1px solid var(--boxel-border-color, #d3d3d3);
      }
    </style>
  </template>
}

class EditTemplate extends Component<typeof MultiImageSourceField> {
  <template>
    <MultiImageSourceEditor @model={{@model}} @fileField={{@fields.newImage}} />
  </template>
}

// A list-of-images companion to ImageSourceField: each entry is a full
// ImageSourceField (url or linked file), so single-image consumers and
// multi-image consumers share the same per-image data model and chooser.
export default class MultiImageSourceField extends FieldDef {
  static displayName = 'Multi Image Source';
  static icon = PhotoIcon;

  @field images = containsMany(ImageSourceField);

  // add slot: the standard linksTo editor (the same Link Image button the
  // single field uses) writes a pick here, and the edit UI immediately moves
  // it into `images` and clears this — it never stays populated
  @field newImage = linksTo(() => ImageDef);

  // Output: every image's resolved URL, in order — consume this instead of
  // walking images yourself (mirrors ImageSourceField.resolvedUrl).
  @field resolvedUrls = containsMany(StringField, {
    computeVia: function (this: MultiImageSourceField) {
      return (this.images ?? [])
        .map((image) => image?.resolvedUrl)
        .filter(Boolean);
    },
  });

  // Output: the first image's resolved URL — the "cover" for consumers that
  // only show one.
  @field primaryUrl = contains(StringField, {
    computeVia: function (this: MultiImageSourceField) {
      return this.resolvedUrls?.[0] ?? '';
    },
  });

  static embedded = EmbeddedTemplate;
  static edit = EditTemplate;
}
