import {
  FieldDef,
  field,
  contains,
  linksTo,
  Component,
  ImageDef,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import UrlField from 'https://cardstack.com/base/url';
import ImageIcon from '@cardstack/boxel-icons/image';
import ImageSourceEditor from './image-source/components/image-source-editor';

export type ImageSourceMode = 'url' | 'file';

function selectedImageURL(
  sourceMode: ImageSourceMode | null | undefined,
  url: string | null | undefined,
  fileUrl: string | null | undefined,
): string {
  if (sourceMode === 'url') {
    return url || '';
  }
  if (sourceMode === 'file') {
    return fileUrl || '';
  }
  return url || fileUrl || '';
}

class EmbeddedTemplate extends Component<typeof ImageSourceField> {
  <template>
    {{#if @model.resolvedUrl}}
      <img
        src={{@model.resolvedUrl}}
        loading='lazy'
        alt=''
        data-test-image-source-embedded
      />
    {{/if}}
  </template>
}

class EditTemplate extends Component<typeof ImageSourceField> {
  <template>
    <ImageSourceEditor @model={{@model}} @fileField={{@fields.file}} />
  </template>
}

export default class ImageSourceField extends FieldDef {
  static displayName = 'Image Source';
  static icon = ImageIcon;

  // Input: direct image URL string (used when sourceMode is 'url')
  @field url = contains(UrlField);
  // Input: linked image file uploaded to the realm (used when sourceMode is 'file')
  @field file = linksTo(() => ImageDef);
  // Controls which input is active — 'url' | 'file' (defaults to 'file' when unset)
  @field sourceMode = contains(StringField);

  // Output: the resolved image URL derived from sourceMode — use this in consuming
  // cards instead of accessing url/file directly, e.g. for CSS background-image vars.
  @field resolvedUrl = contains(StringField, {
    computeVia: function (this: ImageSourceField) {
      return selectedImageURL(
        this.sourceMode as ImageSourceMode | null | undefined,
        this.url,
        this.file?.url,
      );
    },
  });

  static embedded = EmbeddedTemplate;
  static edit = EditTemplate;
}
