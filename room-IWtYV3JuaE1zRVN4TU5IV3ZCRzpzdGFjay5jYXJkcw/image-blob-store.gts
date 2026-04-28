/* eslint-disable */
// ═══ [EDIT TRACKING: ON] Mark all changes with ⁿ ═══
import {
  CardDef,
  field,
  contains,
  Component,
} from 'https://cardstack.com/base/card-api'; // ¹ Core
import StringField from 'https://cardstack.com/base/string';
import { SeparateImageField } from './separate-image-field'; // ² Uses your FieldDef

export class ImageBlobStore extends CardDef {
  // ³ Storage card for base64 image
  static displayName = 'Image Blob Store';

  // ⁴ Base64 image and minimal metadata
  @field image = contains(SeparateImageField);
  @field prompt = contains(StringField);
  @field providerModel = contains(StringField);

  static embedded = class Embedded extends Component<typeof this> {
    // ⁵ Quick preview
    <template>
      <div class='store-embedded'>
        {{#if @model.image}}
          {{#if @model.image.base64}}
            <img
              class='preview'
              src={{@model.image.base64}}
              alt='{{if
                @model.image.altText
                @model.image.altText
                "Generated image"
              }}'
            />
          {{else}}
            <div class='placeholder'>No image stored yet</div>
          {{/if}}
        {{else}}
          <div class='placeholder'>No image stored yet</div>
        {{/if}}

        {{#if @model.prompt}}
          <div class='meta'><strong>Prompt:</strong> {{@model.prompt}}</div>
        {{/if}}
        {{#if @model.providerModel}}
          <div class='meta'><strong>Model:</strong>
            {{@model.providerModel}}</div>
        {{/if}}
      </div>

      <style scoped>
        .store-embedded {
          display: flex;
          flex-direction: column;
          gap: 0.5rem;
        }
        .preview {
          width: 100%;
          height: auto;
          border-radius: 8px;
          border: 1px solid #e5e7eb;
        }
        .placeholder {
          font-size: 0.8125rem;
          color: #6b7280;
          border: 1px dashed #d1d5db;
          padding: 0.5rem;
          border-radius: 6px;
        }
        .meta {
          font-size: 0.8125rem;
          color: #374151;
        }
      </style>
    </template>
  };
}
