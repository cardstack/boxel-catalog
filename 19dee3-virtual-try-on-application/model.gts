import {
  CardDef,
  Component,
  field,
  contains,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import enumField from 'https://cardstack.com/base/enum';
import ImageSourceField from '@cardstack/catalog/fields/image-source/image-source';

// How much of the body is visible in a model photo, detected once when the
// model is added. Unset = not yet detected.
export const BodyVisibilityField = enumField(StringField, {
  options: [
    { value: 'full', label: 'Full body' },
    { value: 'partial', label: 'Partial / cropped' },
  ],
  displayName: 'Body Visibility',
});

export class Model extends CardDef {
  static displayName = 'Model';

  @field photo = contains(ImageSourceField);

  // Detected once (cheaply) when the model is added. Drives the try-on UI hint
  // and lets generation know when it must invent a standard body.
  @field bodyVisibility = contains(BodyVisibilityField);

  static fitted = class Fitted extends Component<typeof Model> {
    <template>
      <div class='model-fitted'>
        {{#if @model.photo.resolvedUrl}}
          <img
            src={{@model.photo.resolvedUrl}}
            alt={{@model.cardTitle}}
            class='photo'
          />
        {{/if}}
        <div class='overlay'>
          <span class='name'>{{@model.cardTitle}}</span>
        </div>
      </div>
      <style scoped>
        .model-fitted {
          position: relative;
          width: 100%;
          height: 100%;
          overflow: hidden;
        }
        .photo {
          width: 100%;
          height: 100%;
          object-fit: cover;
          object-position: top;
        }
        .overlay {
          position: absolute;
          bottom: 0;
          left: 0;
          right: 0;
          background: linear-gradient(transparent, rgba(0, 0, 0, 0.5));
          padding: var(--boxel-sp-xs);
        }
        .name {
          color: white;
          font-size: var(--boxel-font-size-sm);
          font-weight: 600;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof Model> {
    <template>
      <div class='model-embedded'>
        {{#if @model.photo.resolvedUrl}}
          <img
            src={{@model.photo.resolvedUrl}}
            alt={{@model.cardTitle}}
            class='avatar'
          />
        {{/if}}
        <h3 class='name'>{{@model.cardTitle}}</h3>
      </div>
      <style scoped>
        .model-embedded {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-sm);
        }
        .avatar {
          width: 48px;
          height: 48px;
          object-fit: cover;
          object-position: top;
          border-radius: 50%;
          flex-shrink: 0;
        }
        .name {
          margin: 0;
          font-size: inherit;
          font-weight: 600;
        }
      </style>
    </template>
  };
}
