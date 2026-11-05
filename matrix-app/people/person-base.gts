import {
  CardDef,
  Component,
  field,
  contains,
  StringField,
  type BaseDefComponent,
} from 'https://cardstack.com/base/card-api';
import ImageSourceField from '@cardstack/catalog/fields/image-source/image-source';
import EmailField from 'https://cardstack.com/base/email';
import UserIcon from '@cardstack/boxel-icons/user';
import { Avatar } from '@cardstack/pretui/components/avatar';

export class PersonBase extends CardDef {
  static displayName = 'Person';
  static icon = UserIcon;

  @field name = contains(StringField);
  @field email = contains(EmailField);
  @field phone = contains(StringField);
  // The catalog's ImageSourceField rather than a bare UrlField: it accepts
  // either a pasted URL or a file uploaded into the realm, and exposes the
  // winner as `resolvedUrl`. Named `photo`, not `photoUrl`, because it is no
  // longer a URL — consumers read `photo.resolvedUrl`.
  @field photo = contains(ImageSourceField);

  @field initials = contains(StringField, {
    computeVia: function (this: PersonBase) {
      return initialsOf(this.name);
    },
  });

  @field title = contains(StringField, {
    computeVia: function (this: PersonBase) {
      return this.name?.trim() || 'Unnamed Person';
    },
  });

  // `BaseDefComponent` keeps subclass overrides assignable to this base.
  static embedded: BaseDefComponent = class Embedded extends Component<
    typeof this
  > {
    <template>
      <div class='person-row'>
        {{! Pret UI Avatar: the photo when there is one, falling back to the
            initials if it fails to load. The hue is --primary-ink, so the
            initials keep the primary identity and clear 4.5:1 on Avatar's
            16% tint of it. Hidden from assistive tech, because the name is
            the next thing read. }}
        <Avatar
          @name={{if @model.name @model.name '?'}}
          @src={{@model.photo.resolvedUrl}}
          @hue='var(--primary-ink)'
          @size={{38}}
          aria-hidden='true'
        />
        <span class='person-main'>
          <span class='person-name'>{{@model.title}}</span>
          {{#if @model.email}}
            <span class='person-sub'>{{@model.email}}</span>
          {{/if}}
        </span>
      </div>
      <style scoped>
        .person-row {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-sm);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          border: 1px solid var(--border);
          border-radius: var(--boxel-border-radius);
          background-color: var(--background);
          color: var(--foreground);
          transition: box-shadow 0.15s ease-out;
        }
        .person-main {
          flex: 1;
          min-width: 0;
          display: flex;
          flex-direction: column;
          gap: 0.125rem;
        }
        .person-name {
          font-size: var(--boxel-font-size-sm);
          font-weight: 600;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .person-sub {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
      </style>
    </template>
  };
}

/** "Sofia Reyes" -> "SR"; the first letters of the first two words, "?" when there is no name. */
export function initialsOf(name?: string | null): string {
  if (!name) {
    return '?';
  }
  return name
    .trim()
    .split(/\s+/)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase() ?? '')
    .join('');
}
