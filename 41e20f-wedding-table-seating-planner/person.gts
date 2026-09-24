import {
  CardDef,
  Component,
  field,
  contains,
  type BaseDefComponent,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import UrlField from '@cardstack/base/url';
import ImageSourceField from '@cardstack/catalog/fields/image-source/image-source';
import UserIcon from '@cardstack/boxel-icons/user';

import { initialsOf } from './utils/index';

export class Person extends CardDef {
  static displayName = 'Person';
  static icon = UserIcon;

  @field fullName = contains(StringField);
  @field photo = contains(ImageSourceField);

  @field photoURL = contains(UrlField, {
    computeVia: function (this: Person) {
      return this.photo?.resolvedUrl;
    },
  });

  @field title = contains(StringField, {
    computeVia: function (this: Person) {
      return this.fullName?.trim() || 'Unnamed Person';
    },
  });

  // Explicit `BaseDefComponent` annotation so subclass overrides (Guest,
  // Host) whose models require extra fields stay assignable to this base.
  static embedded: BaseDefComponent = class Embedded extends Component<
    typeof this
  > {
    get initials() {
      return initialsOf(this.args.model?.fullName);
    }

    <template>
      <div class='p-row'>
        {{#if @model.photoURL}}
          <img class='p-avatar' src={{@model.photoURL}} alt='' />
        {{else}}
          <span class='p-avatar p-initials'>{{this.initials}}</span>
        {{/if}}
        <span class='p-main'>
          <span class='p-name'>{{if
              @model.fullName
              @model.fullName
              'Unnamed Person'
            }}</span>
        </span>
      </div>
      <style scoped>
        .p-row {
          display: flex;
          align-items: center;
          gap: 0.75rem;
          padding: 0.5625rem 0.75rem;
          border: 1px solid var(--border);
          border-radius: 0.6875rem;
        }
        .p-avatar {
          width: 2.375rem;
          height: 2.375rem;
          border-radius: 50%;
          flex: none;
          object-fit: cover;
        }
        .p-initials {
          display: flex;
          align-items: center;
          justify-content: center;
          font: 600 0.8125rem var(--font-serif);
          color: var(--accent-foreground);
          background: linear-gradient(
            135deg,
            var(--accent) 0%,
            color-mix(in oklch, var(--accent) 84%, var(--shadow-color)) 100%
          );
        }
        .p-main {
          flex: 1;
          min-width: 0;
          display: flex;
          flex-direction: column;
          gap: 0.1875rem;
        }
        .p-name {
          font-size: 0.875rem;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
      </style>
    </template>
  };
}
