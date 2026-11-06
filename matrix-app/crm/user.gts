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
          gap: 0.375rem;
          font-size: 0.8125rem;
          font-weight: 500;
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
          gap: 0.625rem;
          padding: 0.625rem 0.875rem;
        }
        .info {
          min-width: 0;
        }
        .name {
          font-weight: 600;
          font-size: 0.875rem;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .meta {
          font-size: 0.75rem;
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
      <div class='fitted'>
        <Avatar
          class='avatar-sm'
          @name={{if @model.name @model.name ''}}
          @hue={{avatarHue @model.name}}
          @size={{28}}
        />
        <Avatar
          class='avatar-lg'
          @name={{if @model.name @model.name ''}}
          @hue={{avatarHue @model.name}}
          @size={{40}}
        />
        <div class='info'>
          <span class='name'>{{this.name}}</span>
          {{#if @model.email}}
            <span class='meta line-email'>{{@model.email}}</span>
          {{/if}}
        </div>
      </div>
      <style scoped>
        .fitted {
          display: flex;
          align-items: center;
          gap: 0.625rem;
          width: 100%;
          height: 100%;
          padding: 0.625rem 0.75rem;
          box-sizing: border-box;
          overflow: hidden;
          color: var(--foreground);
        }
        /* Pret UI Avatar sizes itself from @size, so each tier mounts its own
           and the container query shows one. The parent class keeps these
           rules above Avatar's own display. */
        .fitted .avatar-lg {
          display: none;
        }
        .info {
          display: flex;
          flex-direction: column;
          gap: 0.125rem;
          min-width: 0;
        }
        .name {
          font-weight: 600;
          font-size: 0.8125rem;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .meta {
          font-size: 0.6875rem;
          color: var(--muted-foreground);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .line-email {
          display: none;
        }
        @container fitted-card (min-height: 65px) {
          .line-email {
            display: block;
          }
        }
        @container fitted-card (min-height: 170px) {
          .fitted {
            flex-direction: column;
            align-items: flex-start;
            justify-content: center;
            padding: 0.875rem;
          }
          .fitted .avatar-sm {
            display: none;
          }
          .fitted .avatar-lg {
            display: inline-flex;
          }
        }
      </style>
    </template>
  };

  static isolated = class Isolated extends Component<typeof User> {
    get name() {
      return this.args.model?.name?.trim() || 'Unnamed User';
    }
    contactRows = [{ key: 'Email', value: 'email' }];
    <template>
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
            <KeyValue class='details' @items={{this.contactRows}}>
              <:value><@fields.email /></:value>
            </KeyValue>
          </section>
        {{/if}}
      </article>
      <style scoped>
        .user-page {
          max-width: 40rem;
          margin: 0 auto;
          padding: 2rem 1.5rem;
          display: flex;
          flex-direction: column;
          gap: 1.25rem;
        }
        .uh {
          display: flex;
          align-items: center;
          gap: 1rem;
          border-bottom: 0.125rem solid var(--foreground);
          padding-bottom: 1.25rem;
        }
        .doc-kind {
          margin: 0 0 0.125rem;
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        h1 {
          font-size: 1.625rem;
          line-height: 1.1;
        }
        .panel {
          border: 1px solid var(--border);
          border-radius: 0.75rem;
          padding: 1rem 1.25rem;
          background-color: var(--card);
          color: var(--card-foreground);
        }
        h2 {
          margin: 0 0 0.75rem;
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        /* Pret UI KeyValue at the panel's text size and column gap */
        .details {
          --text-ui: 0.875rem;
          --text-ui-md: 0.875rem;
          --space-6: 1.25rem;
        }
      </style>
    </template>
  };
}
