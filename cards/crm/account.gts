import { Button } from '@cardstack/pretui/components/button';
import { RichFittedCard, Detail } from '../shared/rich-fitted-card';
import { Chip } from '@cardstack/pretui/components/chip';
import { on } from '@ember/modifier';
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
import { array, hash } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { type KeyValueItem } from '@cardstack/pretui/components/key-value';

import {
  RecordEmbedded,
  RecordPage,
  RelatedList,
  relatedSearch,
  shortDate,
  usd,
} from './record-views';
import { createLinked } from './record-views';
import { User } from './user';
import { IsoFrame } from '../shared/compact-sheet';

// @ts-expect-error TS1470 -- import.meta is valid in realm-served modules; only the CommonJS type-check rejects it
const moduleURL: string = import.meta.url;

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
    get items(): KeyValueItem[] {
      let m = this.args.model;
      let rows: KeyValueItem[] = [];
      if (m?.industry) rows.push({ key: 'Industry', value: m.industry });
      if (m?.firstPaidAt)
        rows.push({ key: 'First paid', value: shortDate(m.firstPaidAt, true) });
      if (m?.phone) rows.push({ key: 'Phone', value: m.phone });
      if (m?.owner) rows.push({ key: 'Owner', value: '@owner' });
      return rows;
    }
    get subtitle() {
      let m = this.args.model;
      return [m?.industry, m?.domain].filter(Boolean).join(' · ');
    }
    get chips() {
      return [
        this.args.model?.isCustomer
          ? { label: 'customer', hue: 'green' }
          : { label: 'prospect', hue: 'slate' },
      ];
    }
    <template>
      <RecordEmbedded
        @mark={{if @model.cardTitle @model.cardTitle ''}}
        @title={{@model.cardTitle}}
        @subtitle={{this.subtitle}}
        @chips={{this.chips}}
        @items={{this.items}}
      >
        <:value as |row|>
          {{#if (eq row.value '@owner')}}
            <@fields.owner @format='atom' @displayContainer={{false}} />
          {{else}}{{row.value}}{{/if}}
        </:value>
      </RecordEmbedded>
    </template>
  };

  static atom = class Atom extends Component<typeof Account> {
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

  static fitted = class Fitted extends Component<typeof Account> {
    get subtitle() {
      let m = this.args.model;
      return [m?.industry, m?.domain].filter(Boolean).join(' · ');
    }
    <template>
      <RichFittedCard>
        <:avatar><Avatar
            @name={{if @model.cardTitle @model.cardTitle ''}}
            @shape='square'
          /></:avatar>
        <:title>{{@model.cardTitle}}</:title>
        <:status>{{#each
            if
            @model.isCustomer
            (array (hash label='customer' tone='success'))
            (array (hash label='prospect'))
            as |t|
          }}<Chip
              @label={{t.label}}
              @tone={{t.tone}}
              @appearance='plain'
            />{{/each}}</:status>
        <:subtitle>{{this.subtitle}}</:subtitle>
        <:fact>{{@model.email}}</:fact>
        <:details>
          {{#if @model.industry}}<Detail
              @label='Industry'
              @value={{@model.industry}}
            />{{/if}}
          {{#if @model.domain}}<Detail
              @label='Domain'
              @value={{@model.domain}}
            />{{/if}}
          {{#if @model.phone}}<Detail
              @label='Phone'
              @value={{@model.phone}}
            />{{/if}}
          {{#if @model.owner}}<Detail @label='Owner'><@fields.owner
                @format='atom'
                @displayContainer={{false}}
              /></Detail>{{/if}}
        </:details>
      </RichFittedCard>
    </template>
  };

  static isolated = class Isolated extends Component<typeof Account> {
    logActivity = () =>
      createLinked(
        this.args,
        new URL('./activity', moduleURL).href,
        'Activity',
        'about',
        { activityType: 'note', occurredAt: new Date().toISOString() },
      );
    newDeal = () =>
      createLinked(
        this.args,
        new URL('./opportunity', moduleURL).href,
        'Opportunity',
        'account',
        { stage: 'new lead' },
      );
    private here = (path: string) => new URL(path, moduleURL).href;
    private rel = (path: string, name: string) =>
      relatedSearch(
        this,
        this.args.context,
        () => this.args.model,
        this.here(path),
        name,
        'account.id',
      );
    deals = this.rel('./opportunity', 'Opportunity');
    invoices = this.rel('../commerce/invoice', 'Invoice');
    subs = this.rel('../commerce/subscription', 'Subscription');
    contacts = this.rel('./contact', 'Contact');
    private list(r: any): any[] {
      return ((r?.instances ?? []) as any[]).filter(Boolean);
    }
    dealMeta = (d: any) =>
      d.closeDate ? `closes ${shortDate(d.closeDate)}` : undefined;
    dealStage = (d: any) => d.stage;
    dealAmount = (d: any) => usd(d.value?.amount);
    subMeta = (x: any) =>
      [
        x.billingCycle,
        x.startDate ? `since ${shortDate(x.startDate, true)}` : '',
      ]
        .filter(Boolean)
        .join(' · ');
    subStatus = (x: any) => x.status;
    subAmount = (x: any) =>
      `${usd(x.price?.amount)}${x.billingCycle === 'yearly' ? '/yr' : '/mo'}`;
    get dealCards() {
      return this.list(this.deals);
    }
    get subCards() {
      return this.list(this.subs);
    }
    get contactCards() {
      return this.list(this.contacts);
    }
    get money() {
      let mrr = 0;
      for (let s of this.subCards) {
        if (!['active', 'trial'].includes(s.status ?? '')) continue;
        let p = s.price?.amount ?? 0;
        mrr += s.billingCycle === 'yearly' ? p / 12 : p;
      }
      let outstanding = 0;
      for (let inv of this.list(this.invoices)) {
        if (!['sent', 'viewed', 'partial'].includes(inv.status ?? '')) continue;
        // Invoice.balanceDue: tax, payments and variance resolutions included.
        outstanding += inv.balanceDue ?? 0;
      }
      let open = this.dealCards.filter(
        (d) => !['closed won', 'closed lost'].includes(d.stage ?? ''),
      );
      let pipeline = open.reduce((a, d) => a + (d.value?.amount ?? 0), 0);
      return { mrr, outstanding, pipeline, openCount: open.length };
    }
    get subtitle() {
      let m = this.args.model;
      return [m?.industry, m?.domain].filter(Boolean).join(' · ');
    }
    get stats() {
      let m = this.args.model;
      let x = this.money;
      return [
        {
          label: 'MRR',
          value: usd(x.mrr),
          hint: `${usd(x.mrr * 12)} ARR`,
          tone: 'info',
        },
        {
          label: 'Outstanding',
          value: usd(x.outstanding),
          hint: 'unpaid invoices',
          tone: x.outstanding ? 'danger' : 'neutral',
        },
        {
          label: 'Open pipeline',
          value: usd(x.pipeline),
          hint: `${x.openCount} open deals`,
          tone: 'neutral',
        },
        {
          label: 'Customer since',
          value: m?.firstPaidAt ? shortDate(m.firstPaidAt, true) : '—',
          hint: m?.firstPaidAt ? 'first paid' : 'no payment yet',
          tone: 'success',
        },
      ];
    }
    get details(): KeyValueItem[] {
      let m = this.args.model;
      let rows: KeyValueItem[] = [];
      if (m?.industry) rows.push({ key: 'Industry', value: m.industry });
      if (m?.domain) rows.push({ key: 'Domain', value: m.domain });
      if (m?.firstPaidAt)
        rows.push({ key: 'First paid', value: shortDate(m.firstPaidAt, true) });
      if (m?.phone) rows.push({ key: 'Phone', value: m.phone });
      if (m?.email) rows.push({ key: 'Email', value: m.email });
      return rows;
    }
    <template>
      <IsoFrame>
        <RecordPage
          @mark={{if @model.cardTitle @model.cardTitle ''}}
          @title={{@model.cardTitle}}
          @subtitle={{this.subtitle}}
          @chips={{array
            (hash
              label=(if @model.isCustomer 'customer' 'prospect')
              hue=(if @model.isCustomer 'green' 'slate')
            )
          }}
          @stats={{this.stats}}
          @linked={{if @model.owner (array (hash key='Owner' value='@owner'))}}
          @details={{this.details}}
        >
          <:actions>
            <Button @appearance='outlined' {{on 'click' this.logActivity}}>Log
              activity</Button>
            <Button @appearance='accent' {{on 'click' this.newDeal}}>New deal</Button>
          </:actions>
          <:main>
            <RelatedList
              @title='Deals'
              @cards={{this.dealCards}}
              @empty='No deals yet'
              @meta={{this.dealMeta}}
              @status={{this.dealStage}}
              @amount={{this.dealAmount}}
            />
            <RelatedList
              @title='Subscriptions'
              @cards={{this.subCards}}
              @empty='No subscriptions'
              @meta={{this.subMeta}}
              @status={{this.subStatus}}
              @amount={{this.subAmount}}
            />
            <RelatedList
              @title='Contacts'
              @cards={{this.contactCards}}
              @empty='No contacts'
            />
            <h2 class='h'>Billing address</h2>
            <div class='addr'><@fields.billingAddress /></div>
          </:main>
          <:value as |row|>
            {{#if (eq row.value '@owner')}}
              <@fields.owner @format='atom' @displayContainer={{false}} />
            {{else}}{{row.value}}{{/if}}
          </:value>
        </RecordPage>
      </IsoFrame>
      <style scoped>
        .h {
          margin: 0;
          padding: var(--boxel-sp-2xs) var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-xs);
          font-weight: 700;
          border-block-end: 1px solid var(--border);
        }
        .addr {
          padding: var(--boxel-sp-xs) var(--boxel-sp-xs);
        }
      </style>
    </template>
  };
}

// style tags live at the template root
