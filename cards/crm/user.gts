import {
  CardDef,
  Component,
  StringField,
  contains,
  field,
} from 'https://cardstack.com/base/card-api';
import EmailField from 'https://cardstack.com/base/email';
import UserIcon from '@cardstack/boxel-icons/user';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { KeyValue } from '@cardstack/pretui/components/key-value';
import { avatarHue } from './utils';
import { IsoFrame } from '../shared/compact-sheet';
import { RichFittedCard } from '../shared/rich-fitted-card';

export class User extends CardDef {
  static displayName = 'User';
  static icon = UserIcon;
  @field name = contains(StringField);
  @field email = contains(EmailField);
  @field cardTitle = contains(StringField, {
    computeVia: function (this: User) {
      return this.name?.trim()?.length
        ? this.name
        : `Untitled ${this.constructor.displayName}`;
    },
  });

  static atom = class Atom extends Component<typeof User> {
    <template>
      <span class='user-atom'>
        <Avatar
          @name={{if @model.name @model.name ''}}
          @hue={{avatarHue @model.name}}
          @size={{18}}
        />
        <span class='ua-name'>{{if @model.name @model.name 'Unassigned'}}</span>
      </span>
      <style scoped>
        .user-atom {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-2xs);
          font-size: var(--boxel-font-size-xs);
          font-weight: 600;
          color: var(--foreground);
        }
        .ua-name {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof User> {
    <template>
      <div class='user'>
        <Avatar
          @name={{if @model.name @model.name ''}}
          @hue={{avatarHue @model.name}}
          @size={{32}}
        />
        <div class='info'>
          <div class='name'>{{if @model.name @model.name 'Unnamed'}}</div>
          {{#if @model.email}}
            <div class='meta'>{{@model.email}}</div>
          {{/if}}
        </div>
      </div>
      <style scoped>
        .user {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .info {
          min-width: 0;
        }
        .name {
          font-weight: 600;
          font-size: var(--boxel-font-size-sm);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .meta {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof User> {
    get name() {
      return this.args.model?.name?.trim() || 'Unnamed User';
    }
    <template>
      <RichFittedCard>
        <:avatar><Avatar
            @name={{if @model.name @model.name ''}}
            @hue={{avatarHue @model.name}}
            aria-hidden='true'
          /></:avatar>
        <:title>{{this.name}}</:title>
        <:subtitle>{{@model.email}}</:subtitle>
      </RichFittedCard>
    </template>
  };

  static isolated = class Isolated extends Component<typeof User> {
    get name() {
      return this.args.model?.name?.trim() || 'Unnamed User';
    }
    contactRows = [{ key: 'Email', value: 'email' }];
    <template>
      <IsoFrame>
        <article class='user-page'>
          <header class='uh'>
            <Avatar
              @name={{if @model.name @model.name ''}}
              @hue={{avatarHue @model.name}}
              @size={{56}}
            />
            <div class='uh-id'>
              <p class='doc-kind'>{{@model.constructor.displayName}}</p>
              <h1>{{this.name}}</h1>
            </div>
          </header>
          {{#if @model.email}}
            <section class='panel'>
              <h2>Contact</h2>
              <KeyValue class='kv-pad' @items={{this.contactRows}}>
                <:value><@fields.email /></:value>
              </KeyValue>
            </section>
          {{/if}}
        </article>
      </IsoFrame>
      <style scoped>
        .kv-pad {
          --pretui-kv-pad-inline: var(--boxel-sp-sm);
        }

        .user-page {
          background: var(--card);
          color: var(--card-foreground);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          max-width: 40rem;
          margin: 0 auto;
          inline-size: 100%;
          padding: var(--boxel-sp-xl) var(--boxel-sp-lg);
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-lg);
        }
        .uh {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp);
          border-bottom: 0.125rem solid var(--foreground);
          padding-bottom: var(--boxel-sp-lg);
        }
        .doc-kind {
          margin: 0 0 var(--boxel-sp-6xs);
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        h1 {
          font-size: var(--boxel-font-size-lg);
          line-height: 1.1;
        }
        .panel {
          border: 1px solid var(--border);
          border-radius: var(--radius);
          padding: var(--boxel-sp) var(--boxel-sp-lg);
          background-color: var(--card);
          color: var(--card-foreground);
        }
        h2 {
          margin: 0 0 var(--boxel-sp-sm);
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };
}
