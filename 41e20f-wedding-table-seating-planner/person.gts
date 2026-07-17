import {
  CardDef,
  Component,
  field,
  contains,
  type BaseDefComponent,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import UrlField from 'https://cardstack.com/base/url';
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
          gap: 12px;
          padding: 9px 12px;
          border: 1px solid
            var(--tsp-border, var(--border, rgba(220, 193, 136, 0.3)));
          border-radius: 11px;
          background: var(--tsp-background, var(--background, #ffffff));
          font-family: var(
            --tsp-font-sans,
            var(--font-sans, 'Jost', system-ui, sans-serif)
          );
          color: var(--tsp-foreground, var(--foreground, #22283f));
        }
        .p-avatar {
          width: 38px;
          height: 38px;
          border-radius: 50%;
          flex: none;
          object-fit: cover;
        }
        .p-initials {
          display: flex;
          align-items: center;
          justify-content: center;
          font: 600 13px
            var(
              --tsp-font-serif,
              var(--font-serif, 'Cormorant Garamond', serif)
            );
          color: var(--tsp-foreground, var(--foreground, #22283f));
          background: linear-gradient(
            135deg,
            #dcc188,
            var(--tsp-accent, var(--accent, #c5a35c))
          );
        }
        .p-main {
          flex: 1;
          min-width: 0;
          display: flex;
          flex-direction: column;
          gap: 3px;
        }
        .p-name {
          font-size: 14px;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
      </style>
    </template>
  };
}
