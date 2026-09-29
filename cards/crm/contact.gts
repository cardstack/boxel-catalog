import {
  Component,
  contains,
  field,
  linksTo,
} from 'https://cardstack.com/base/card-api';
import { on } from '@ember/modifier';
import StringField from 'https://cardstack.com/base/string';
import PhoneNumberField from 'https://cardstack.com/base/phone-number';
import enumField from 'https://cardstack.com/base/enum';
import ContactIcon from '@cardstack/boxel-icons/address-book';
import PhoneIcon from '@cardstack/boxel-icons/phone';
import MailIcon from '@cardstack/boxel-icons/mail';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Avatar } from '@cardstack/pretui/components/avatar';
import {
  KeyValue,
  type KeyValueItem,
} from '@cardstack/pretui/components/key-value';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import { Account } from './account';
import { PersonBase } from '../people/person-base';
import { avatarHue } from './utils';

const ContactRoleField = enumField(StringField, {
  options: ['decision maker', 'champion', 'influencer', 'user', 'billing'],
  displayName: 'Contact Role',
});

// A Contact is a Person: `email`, `photo`, `initials` and the base embedded
// row come from PersonBase. CRM keeps the split `firstName`/`lastName` it has
// always stored and satisfies the base's single `name` by computing it, so
// anything written against PersonBase (initials, avatars, the hire-copy in
// HR's Approve Offer) works on a Contact unchanged.
export class Contact extends PersonBase {
  static displayName = 'Contact';
  static icon = ContactIcon;

  @field firstName = contains(StringField);
  @field lastName = contains(StringField);
  @field phone = contains(PhoneNumberField);
  @field jobTitle = contains(StringField);
  @field role = contains(ContactRoleField);
  @field account = linksTo(Account);

  @field name = contains(StringField, {
    computeVia: function (this: Contact) {
      return [this.firstName, this.lastName].filter(Boolean).join(' ');
    },
  });

  @field cardTitle = contains(StringField, {
    computeVia: function (this: Contact) {
      return this.name?.trim()?.length
        ? this.name
        : `Untitled ${this.constructor.displayName}`;
    },
  });

  static atom = class Atom extends Component<typeof Contact> {
    <template>
      <span class='contact-atom'>
        <Avatar
          @name={{if @model.name @model.name ''}}
          @hue={{avatarHue @model.name}}
          @size={{18}}
        />
        <span class='cta-name'>{{if
            @model.name
            @model.name
            'Unnamed Contact'
          }}</span>
      </span>
      <style scoped>
        .contact-atom {
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
          font-size: 0.8125rem;
          font-weight: 500;
          color: var(--foreground);
        }
        .cta-name {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof Contact> {
    get subtitle() {
      return this.args.model?.jobTitle;
    }
    // A consumer may wrap this row in its own click target; reaching the person
    // should not also open their card.
    stopClick = (event: Event) => event.stopPropagation();
    <template>
      <div class='contact'>
        <Avatar
          @name={{if @model.name @model.name ''}}
          @hue={{avatarHue @model.name}}
          @size={{32}}
        />
        <div class='info'>
          <div class='name'>{{if @model.name @model.name 'Unnamed'}}</div>
          {{#if this.subtitle}}
            <div class='meta'>{{this.subtitle}}</div>
          {{/if}}
        </div>
        <span class='reach'>
          {{#if @model.phone}}
            <a
              class='reach-link'
              href='tel:{{@model.phone}}'
              title='Call {{@model.name}}'
              {{on 'click' this.stopClick}}
            ><PhoneIcon /></a>
          {{/if}}
          {{#if @model.email}}
            <a
              class='reach-link'
              href='mailto:{{@model.email}}'
              title='Email {{@model.name}}'
              {{on 'click' this.stopClick}}
            ><MailIcon /></a>
          {{/if}}
        </span>
        <StatePill class='role' @label={{@model.role}} />
      </div>
      <style scoped>
        .contact {
          display: flex;
          align-items: center;
          gap: 0.625rem;
          padding: 0.625rem 0.875rem;
        }
        .info {
          min-width: 0;
          flex: 1;
        }
        /* Constant-width slot so rows line up whether or not a contact is
           reachable — see the column-alignment rule. */
        .reach {
          display: inline-flex;
          gap: 0.25rem;
          width: 3.25rem;
          justify-content: flex-end;
          flex-shrink: 0;
        }
        .reach-link {
          display: inline-flex;
          align-items: center;
          justify-content: center;
          width: 1.375rem;
          height: 1.375rem;
          border-radius: 50%;
          color: var(--muted-foreground);
          background-color: var(--muted);
        }
        .reach-link:hover {
          color: var(--primary-foreground);
          background-color: var(--primary);
        }
        .reach-link :deep(svg) {
          width: 0.8125rem;
          height: 0.8125rem;
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
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .role {
          flex-shrink: 0;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof Contact> {
    get name() {
      return this.args.model?.name?.trim() || 'Unnamed Contact';
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
          {{#if @model.jobTitle}}
            <span class='meta line-title'>{{@model.jobTitle}}</span>
          {{/if}}
          {{#if @model.email}}
            <span class='meta line-email'>{{@model.email}}</span>
          {{/if}}
          {{#if @model.phone}}
            <span class='meta line-phone'>{{@model.phone}}</span>
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
        .line-title,
        .line-email,
        .line-phone {
          display: none;
        }
        @container fitted-card (min-height: 65px) {
          .line-title {
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
          .line-email {
            display: block;
          }
        }
        @container fitted-card (min-width: 400px) and (min-height: 170px) {
          .line-phone {
            display: block;
          }
        }
      </style>
    </template>
  };

  static isolated = class Isolated extends Component<typeof Contact> {
    get name() {
      return this.args.model?.name?.trim() || 'Unnamed Contact';
    }
    get reach(): KeyValueItem[] {
      let m = this.args.model;
      let rows: KeyValueItem[] = [];
      if (m?.email) rows.push({ key: 'Email', value: 'email' });
      if (m?.phone) rows.push({ key: 'Phone', value: 'phone' });
      return rows;
    }
    <template>
      <article class='contact-page'>
        <header class='ch'>
          <Avatar
            @name={{if @model.name @model.name ''}}
            @hue={{avatarHue @model.name}}
            @size={{56}}
          />
          <div class='ch-id'>
            <p class='doc-kind'>Contact</p>
            <h1>{{this.name}}</h1>
            {{#if @model.jobTitle}}
              <p class='job-title'>{{@model.jobTitle}}</p>
            {{/if}}
          </div>
          <StatePill @label={{@model.role}} />
        </header>
        <section class='panel'>
          <h2>Reach</h2>
          <KeyValue class='details' @items={{this.reach}}>
            <:value as |row|>
              {{#if (eq row.value 'email')}}
                <@fields.email />
              {{else}}
                <@fields.phone />
              {{/if}}
            </:value>
          </KeyValue>
        </section>
        {{#if @model.account}}
          <section class='panel'>
            <h2>Account</h2>
            <div class='acct'><@fields.account @format='embedded' /></div>
          </section>
        {{/if}}
      </article>
      <style scoped>
        .contact-page {
          max-width: 40rem;
          margin: 0 auto;
          padding: 2rem 1.5rem;
          display: flex;
          flex-direction: column;
          gap: 1.25rem;
        }
        .ch {
          display: flex;
          align-items: center;
          gap: 1rem;
          border-bottom: 0.125rem solid var(--foreground);
          padding-bottom: 1.25rem;
        }
        .ch-id {
          flex: 1;
          min-width: 0;
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
        .job-title {
          margin: 0.25rem 0 0;
          font-size: 0.875rem;
          color: var(--muted-foreground);
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
        .acct {
          border: 1px solid var(--border);
          border-radius: 0.5rem;
        }
      </style>
    </template>
  };
}
