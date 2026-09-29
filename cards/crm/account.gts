import {
  CardDef,
  Component,
  contains,
  field,
  linksTo,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import BooleanField from 'https://cardstack.com/base/boolean';
import DateField from 'https://cardstack.com/base/date';
import EmailField from 'https://cardstack.com/base/email';
import PhoneNumberField from 'https://cardstack.com/base/phone-number';
import AddressField from 'https://cardstack.com/base/address';
import UsersIcon from '@cardstack/boxel-icons/users';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Avatar } from '@cardstack/pretui/components/avatar';
import {
  KeyValue,
  type KeyValueItem,
} from '@cardstack/pretui/components/key-value';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import { User } from './user';
import { avatarHue } from './utils';

export class Account extends CardDef {
  static displayName = 'Account';
  static icon = UsersIcon;

  @field name = contains(StringField);
  @field domain = contains(StringField);
  @field industry = contains(StringField);
  @field email = contains(EmailField);
  @field phone = contains(PhoneNumberField);
  @field billingAddress = contains(AddressField);
  @field owner = linksTo(User);
  @field firstPaidAt = contains(DateField);

  @field isCustomer = contains(BooleanField, {
    computeVia: function (this: Account) {
      return Boolean(this.firstPaidAt);
    },
  });

  @field cardTitle = contains(StringField, {
    computeVia: function (this: Account) {
      return this.name?.trim()?.length
        ? this.name
        : `Untitled ${this.constructor.displayName}`;
    },
  });

  static embedded = class Embedded extends Component<typeof Account> {
    <template>
      <div class='account'>
        <UsersIcon class='icon' />
        <div>
          <div class='name'>{{@model.cardTitle}}</div>
          <div class='meta'><@fields.email /></div>
        </div>
      </div>
      <style scoped>
        .account {
          display: flex;
          align-items: center;
          gap: 0.75rem;
          padding: 0.625rem 0.875rem;
        }
        .icon {
          width: 1.375rem;
          height: 1.375rem;
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
        .name {
          font-weight: 600;
          font-size: 0.9375rem;
        }
        .meta {
          font-size: 0.75rem;
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof Account> {
    <template>
      <span class='account-atom'>
        <UsersIcon class='ca-icon' />
        <span class='ca-name'>{{if
            @model.name
            @model.name
            'Unnamed Account'
          }}</span>
      </span>
      <style scoped>
        .account-atom {
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
          font-size: 0.8125rem;
          font-weight: 500;
          color: var(--foreground);
        }
        .ca-icon {
          width: 0.875rem;
          height: 0.875rem;
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
        .ca-name {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof Account> {
    get name() {
      return this.args.model?.name?.trim() || 'Unnamed Account';
    }
    get location() {
      let a = this.args.model?.billingAddress;
      return [a?.city, a?.country?.name].filter(Boolean).join(', ');
    }
    <template>
      <div class='fitted'>
        <div class='fmt badge'>
          <Avatar
            @name={{this.name}}
            @hue={{avatarHue this.name}}
            @size={{28}}
          />
          <span class='name'>{{this.name}}</span>
        </div>
        <div class='fmt strip'>
          <Avatar
            @name={{this.name}}
            @hue={{avatarHue this.name}}
            @size={{28}}
          />
          <div class='info'>
            <span class='name'>{{this.name}}</span>
            {{#if @model.email}}
              <span class='meta'>{{@model.email}}</span>
            {{/if}}
          </div>
        </div>
        <div class='fmt tile'>
          <Avatar
            class='avatar-lg'
            @name={{this.name}}
            @hue={{avatarHue this.name}}
            @size={{40}}
          />
          <span class='name'>{{this.name}}</span>
          {{#if @model.industry}}
            <span class='meta'>{{@model.industry}}</span>
          {{/if}}
          {{#if @model.email}}
            <span class='meta'>{{@model.email}}</span>
          {{/if}}
          {{#if this.location}}
            <span class='meta'>{{this.location}}</span>
          {{/if}}
        </div>
        <div class='fmt card'>
          <Avatar
            class='avatar-lg'
            @name={{this.name}}
            @hue={{avatarHue this.name}}
            @size={{40}}
          />
          <div class='info'>
            <span class='name name-lg'>{{this.name}}</span>
            {{#if @model.industry}}
              <span class='meta'>{{@model.industry}}</span>
            {{/if}}
            {{#if @model.email}}
              <span class='meta'>{{@model.email}}</span>
            {{/if}}
            {{#if @model.phone}}
              <span class='meta'>{{@model.phone}}</span>
            {{/if}}
            {{#if this.location}}
              <span class='meta'>{{this.location}}</span>
            {{/if}}
          </div>
          {{#if @model.isCustomer}}
            <StatePill class='badge-pill' @label='Customer' @hue='green' />
          {{/if}}
        </div>
      </div>
      <style scoped>
        .fitted {
          width: 100%;
          height: 100%;
          color: var(--foreground);
        }
        .fmt {
          display: none;
          width: 100%;
          height: 100%;
          box-sizing: border-box;
          overflow: hidden;
        }
        .name {
          font-weight: 600;
          font-size: 0.8125rem;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          max-width: 100%;
        }
        .name-lg {
          font-size: 1rem;
        }
        .meta {
          font-size: 0.6875rem;
          color: var(--muted-foreground);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          max-width: 100%;
        }
        .info {
          display: flex;
          flex-direction: column;
          gap: 0.125rem;
          min-width: 0;
          flex: 1;
        }
        .badge-pill {
          align-self: flex-start;
          flex-shrink: 0;
        }
        @container fitted-card (max-width: 150px) and (max-height: 169px) {
          .badge {
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            gap: 0.375rem;
            padding: 0.5rem;
            text-align: center;
          }
        }
        @container fitted-card (min-width: 151px) and (max-height: 169px) {
          .strip {
            display: flex;
            align-items: center;
            gap: 0.625rem;
            padding: 0.625rem 0.75rem;
          }
        }
        @container fitted-card (max-width: 399px) and (min-height: 170px) {
          .tile {
            display: flex;
            flex-direction: column;
            align-items: flex-start;
            justify-content: center;
            gap: 0.25rem;
            padding: 0.875rem;
          }
          .tile .avatar-lg {
            margin-bottom: 0.25rem;
          }
        }
        @container fitted-card (min-width: 400px) and (min-height: 170px) {
          .card {
            display: flex;
            align-items: center;
            gap: 1rem;
            padding: 1.25rem;
          }
        }
      </style>
    </template>
  };

  static isolated = class Isolated extends Component<typeof Account> {
    get name() {
      return this.args.model?.name?.trim() || 'Unnamed Account';
    }
    get company(): KeyValueItem[] {
      let m = this.args.model;
      let rows: KeyValueItem[] = [];
      if (m?.industry) rows.push({ key: 'Industry', value: 'industry' });
      if (m?.domain) rows.push({ key: 'Domain', value: 'domain' });
      if (m?.owner) rows.push({ key: 'Owner', value: 'owner' });
      return rows;
    }
    get contact(): KeyValueItem[] {
      let m = this.args.model;
      let rows: KeyValueItem[] = [];
      if (m?.email) rows.push({ key: 'Email', value: 'email' });
      if (m?.phone) rows.push({ key: 'Phone', value: 'phone' });
      return rows;
    }
    <template>
      <article class='account-page'>
        <header class='ch'>
          <Avatar
            @name={{this.name}}
            @hue={{avatarHue this.name}}
            @size={{56}}
          />
          <div class='ch-id'>
            <p class='doc-kind'>Account</p>
            <h1>{{this.name}}</h1>
            {{#if @model.isCustomer}}
              <p class='status-line customer'>Customer since
                <@fields.firstPaidAt /></p>
            {{else}}
              <p class='status-line'>Prospect</p>
            {{/if}}
          </div>
        </header>
        <section class='panel'>
          <h2>Company</h2>
          <KeyValue class='details' @items={{this.company}}>
            <:value as |row|>
              {{#if (eq row.value 'industry')}}
                <@fields.industry />
              {{else if (eq row.value 'domain')}}
                <@fields.domain />
              {{else}}
                <@fields.owner @format='atom' />
              {{/if}}
            </:value>
          </KeyValue>
        </section>
        <section class='panel'>
          <h2>Contact</h2>
          <KeyValue class='details' @items={{this.contact}}>
            <:value as |row|>
              {{#if (eq row.value 'email')}}
                <@fields.email />
              {{else}}
                <@fields.phone />
              {{/if}}
            </:value>
          </KeyValue>
        </section>
        <section class='panel'>
          <h2>Billing Address</h2>
          <@fields.billingAddress />
        </section>
      </article>
      <style scoped>
        .account-page {
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
        .status-line {
          margin: 0.25rem 0 0;
          font-size: 0.75rem;
          font-weight: 600;
          color: var(--muted-foreground);
        }
        .status-line.customer {
          color: var(--success-ink);
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
