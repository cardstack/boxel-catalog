import {
  Component,
  contains,
  field,
  linksTo,
} from 'https://cardstack.com/base/card-api';
import { array, hash } from '@ember/helper';
import StringField from 'https://cardstack.com/base/string';
import PhoneNumberField from 'https://cardstack.com/base/phone-number';
import enumField from 'https://cardstack.com/base/enum';
import ContactIcon from '@cardstack/boxel-icons/address-book';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { type KeyValueItem } from '@cardstack/pretui/components/key-value';
import { CompactFitted, CompactRow } from '../commerce/compact-parts';
import { RecordEmbedded, RecordPage } from './record-views';
import { RelatedList, relatedSearch, shortDate, usd } from './record-views';
import { Account } from './account';
import { PersonBase } from '../people/person-base';

// @ts-expect-error TS1470 -- import.meta is valid in realm-served modules; only the CommonJS type-check rejects it
const moduleURL: string = import.meta.url;

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
      <span class='atom'>
        <Avatar
          @name={{if @model.cardTitle @model.cardTitle ''}}
          @shape='rounded'
          @size={{16}}
        />
        <span class='name'>{{@model.cardTitle}}</span>
      </span>
      <style scoped>
        .atom {
          font-size: 0.6875rem;
          font-weight: 600;
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
          min-inline-size: 0;
        }
        .name {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof Contact> {
    get items(): KeyValueItem[] {
      let m = this.args.model;
      let rows: KeyValueItem[] = [];
      if (m?.role) rows.push({ key: 'Role', value: m.role });
      if (m?.email) rows.push({ key: 'Email', value: m.email });
      if (m?.phone) rows.push({ key: 'Phone', value: m.phone });
      if (m?.account) rows.push({ key: 'Account', value: '@account' });
      return rows;
    }
    get subtitle() {
      let m = this.args.model;
      return [m?.jobTitle, m?.account?.name].filter(Boolean).join(' · ');
    }
    <template>
      <RecordEmbedded
        @mark={{if @model.cardTitle @model.cardTitle ''}}
        @title={{@model.cardTitle}}
        @subtitle={{this.subtitle}}
        @chips={{if @model.role (array (hash label=@model.role hue='slate'))}}
        @summary={{@model.jobTitle}}
        @items={{this.items}}
      >
        <:value as |row|>
          {{#if (eq row.value '@account')}}
            <@fields.account @format='atom' @displayContainer={{false}} />
          {{else}}{{row.value}}{{/if}}
        </:value>
      </RecordEmbedded>
    </template>
  };

  static fitted = class Fitted extends Component<typeof Contact> {
    get subtitle() {
      let m = this.args.model;
      return [m?.jobTitle, m?.account?.name].filter(Boolean).join(' · ');
    }
    <template>
      <CompactFitted
        @mark={{if @model.cardTitle @model.cardTitle ''}}
        @title={{@model.cardTitle}}
        @sub={{this.subtitle}}
        @fact={{@model.role}}
        @tags={{if @model.role (array (hash label=@model.role tone='info'))}}
      >
        <:rows>
          {{#if @model.role}}<CompactRow @k='Role' @v={{@model.role}} />{{/if}}
          {{#if @model.email}}<CompactRow
              @k='Email'
              @v={{@model.email}}
            />{{/if}}
          {{#if @model.account}}<CompactRow @k='Account'><@fields.account
                @format='atom'
                @displayContainer={{false}}
              /></CompactRow>{{/if}}
          {{#if @model.phone}}<CompactRow
              @k='Phone'
              @v={{@model.phone}}
            />{{/if}}
        </:rows>
      </CompactFitted>
    </template>
  };

  static isolated = class Isolated extends Component<typeof Contact> {
    activitySearch = relatedSearch(
      this,
      this.args.context,
      () => this.args.model,
      new URL('./activity', moduleURL).href,
      'Activity',
      'about.id',
    );
    get activityCards(): any[] {
      return ((this.activitySearch?.instances ?? []) as any[])
        .filter(Boolean)
        .sort(
          (a, b) => +new Date(b.occurredAt ?? 0) - +new Date(a.occurredAt ?? 0),
        );
    }
    dealSearch = relatedSearch(
      this,
      this.args.context,
      () => this.args.model,
      new URL('../commerce/deal', moduleURL).href,
      'Deal',
      'decisionMakers.id',
    );
    get openDeals(): any[] {
      return ((this.dealSearch?.instances ?? []) as any[]).filter(
        (d) => d && !['closed won', 'closed lost'].includes(d.stage ?? ''),
      );
    }
    get contactItems() {
      let m = this.args.model;
      let items: KeyValueItem[] = [];
      if (m?.email) items.push({ key: 'Email', value: m.email });
      if (m?.phone) items.push({ key: 'Phone', value: m.phone });
      return items.length ? { title: 'Contact', items } : undefined;
    }
    get stats() {
      let m = this.args.model;
      let last = this.activityCards[0];
      let total = this.openDeals.reduce(
        (a, d) => a + (d.value?.amount ?? 0),
        0,
      );
      return [
        {
          label: 'Role',
          value: m?.role ?? '—',
          hint: m?.jobTitle ?? '',
          tone: 'info',
        },
        {
          label: 'Open deals',
          value: String(this.openDeals.length),
          hint: usd(total),
          tone: 'neutral',
        },
        {
          label: 'Last touch',
          value: last ? shortDate(last.occurredAt) : '—',
          hint: last?.activityType ? `${last.activityType}` : 'no activity yet',
          tone: 'neutral',
        },
      ];
    }
    get details(): KeyValueItem[] {
      let m = this.args.model;
      let rows: KeyValueItem[] = [];
      if (m?.role) rows.push({ key: 'Role', value: m.role });
      if (m?.jobTitle) rows.push({ key: 'Job title', value: m.jobTitle });
      if (m?.email) rows.push({ key: 'Email', value: m.email });
      if (m?.phone) rows.push({ key: 'Phone', value: m.phone });
      if (m?.account?.name)
        rows.push({ key: 'Account', value: m.account.name });
      if (m?.firstName) rows.push({ key: 'First name', value: m.firstName });
      if (m?.lastName) rows.push({ key: 'Last name', value: m.lastName });
      return rows;
    }
    get subtitle() {
      let m = this.args.model;
      return [m?.jobTitle, m?.account?.name].filter(Boolean).join(' · ');
    }
    <template>
      <RecordPage
        @mark={{if @model.cardTitle @model.cardTitle ''}}
        @title={{@model.cardTitle}}
        @subtitle={{this.subtitle}}
        @chips={{if @model.role (array (hash label=@model.role hue='blue'))}}
        @stats={{this.stats}}
        @lead={{this.contactItems}}
        @linked={{if
          @model.account
          (array (hash key='Account' value='@account'))
        }}
        @details={{this.details}}
      >
        <:main>
          <RelatedList
            @title='Recent activity'
            @cards={{this.activityCards}}
            @empty='No activity logged'
          />
        </:main>
        <:value as |row|>
          {{#if (eq row.value '@account')}}
            <@fields.account @format='atom' @displayContainer={{false}} />
          {{else}}{{row.value}}{{/if}}
        </:value>
      </RecordPage>
    </template>
  };
}
