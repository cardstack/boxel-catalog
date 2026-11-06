import { Button } from '@cardstack/pretui/components/button';
import { on } from '@ember/modifier';
import { tracked } from '@glimmer/tracking';
import {
  CardDef,
  Component,
  contains,
  field,
  linksTo,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';
import EmailField from 'https://cardstack.com/base/email';
import PhoneNumberField from 'https://cardstack.com/base/phone-number';
import enumField from 'https://cardstack.com/base/enum';
import { array, concat, hash } from '@ember/helper';
import TargetIcon from '@cardstack/boxel-icons/target';
import { eq } from '@cardstack/boxel-ui/helpers';
import { type KeyValueItem } from '@cardstack/pretui/components/key-value';
import { Avatar } from '@cardstack/pretui/components/avatar';
import {
  StepList,
  type StepItem,
  type StepState,
} from '@cardstack/pretui/components/step-list';
import { CompactFitted, CompactRow } from '../commerce/compact-parts';
import { RecordEmbedded, RecordPage } from './record-views';
import { relatedRealm } from './record-views';
import { type Hue } from '@cardstack/catalog/components/state-pill';
import { Campaign } from './campaign';
import { hasNumber } from './utils';

const LEAD_STATUSES = [
  'new',
  'contacted',
  'qualified',
  'converted',
  'disqualified',
];

/** Why a lead in this status can't be converted, or undefined when it can. */
export function convertBlocker(status: string | null | undefined) {
  if (status === 'disqualified') {
    return 'A disqualified lead cannot be converted';
  }
  if (status === 'converted') return 'This lead has already been converted';
  return undefined;
}

const LeadStatusField = enumField(StringField, {
  options: ['new', 'contacted', 'qualified', 'converted', 'disqualified'],
  displayName: 'Lead Status',
});

const LeadSourceField = enumField(StringField, {
  options: [
    'website',
    'referral',
    'webinar',
    'ad',
    'event',
    'cold outreach',
    'other',
  ],
  displayName: 'Lead Source',
});

// Status hues for the pill. Qualified and converted are good news and
// disqualified bad news; new is the one open state that stands out, so it
// takes a category hue rather than a status one; contacted is neutral.
const STATUS_HUE: Record<string, Hue> = {
  new: 'blue',
  contacted: 'slate',
  qualified: 'green',
  converted: 'green',
  disqualified: 'red',
};

function statusHue(status: string | undefined): Hue {
  return (status && STATUS_HUE[status]) || 'slate';
}

class LeadIsolated extends Component<typeof Lead> {
  @tracked converting = false;
  @tracked error: string | undefined;
  get canConvert() {
    return !convertBlocker(this.args.model?.status);
  }
  convert = async () => {
    let ctx = (this.args.context as any)?.commandContext;
    if (!ctx || this.converting) return;
    this.converting = true;
    this.error = undefined;
    try {
      let { default: Convert } = await import('./commands/convert-lead.gts');
      await new Convert(ctx).execute({
        lead: this.args.model,
        realm: relatedRealm(this.args.model),
      } as any);
    } catch (e) {
      this.error = e instanceof Error ? e.message : String(e);
    } finally {
      this.converting = false;
    }
  };
  get steps(): StepItem[] {
    let idx = LEAD_STATUSES.indexOf(this.args.model?.status ?? '');
    return LEAD_STATUSES.map((label, i) => ({
      label,
      state: (i < idx
        ? 'complete'
        : i === idx
          ? 'current'
          : 'upcoming') as StepState,
    }));
  }
  get stats() {
    let m = this.args.model;
    return [
      {
        label: 'Score',
        value: m?.score ?? 0,
        hint: 'of 100',
        tone: 'success',
      },
      { label: 'Status', value: m?.status ?? '', tone: 'neutral' },
      { label: 'Source', value: m?.source ?? '', tone: 'neutral' },
    ];
  }
  get details(): KeyValueItem[] {
    let m = this.args.model;
    let rows: KeyValueItem[] = [];
    if (hasNumber(m?.score))
      rows.push({ key: 'Score', value: `${m?.score} / 100` });
    if (m?.status) rows.push({ key: 'Status', value: m.status });
    if (m?.source) rows.push({ key: 'Source', value: m.source });
    if (m?.company) rows.push({ key: 'Company', value: m.company });
    if (m?.email) rows.push({ key: 'Email', value: m.email });
    if (m?.phone) rows.push({ key: 'Phone', value: m.phone });
    return rows;
  }
  get subtitle() {
    let m = this.args.model;
    return [m?.company, m?.source].filter(Boolean).join(' · ');
  }
  <template>
    <RecordPage
      @mark={{@model.name}}
      @title={{@model.cardTitle}}
      @subtitle={{this.subtitle}}
      @chips={{array
        (hash label=@model.status hue=(statusHue @model.status))
        (hash label=(concat 'score ' @model.score))
      }}
      @stats={{this.stats}}
      @linked={{if
        @model.campaign
        (array (hash key='Campaign' value='@campaign'))
      }}
      @details={{this.details}}
    >
      <:actions>
        {{#if this.canConvert}}<Button
            @appearance='accent'
            @disabled={{this.converting}}
            {{on 'click' this.convert}}
          >Convert</Button>{{/if}}
      </:actions>
      <:main>
        <StepList @steps={{this.steps}} />
        {{#if this.error}}
          <p class='action-error' role='alert'>{{this.error}}</p>
        {{/if}}
      </:main>
      <:value as |row|>
        {{#if (eq row.value '@campaign')}}
          <@fields.campaign @format='atom' @displayContainer={{false}} />
        {{else}}{{row.value}}{{/if}}
      </:value>
    </RecordPage>
    <style scoped>
      .action-error {
        margin: 0;
        padding: 0.4375rem 0.625rem;
        font-size: 0.75rem;
        color: var(--destructive);
      }
    </style>
  </template>
}

export class Lead extends CardDef {
  static displayName = 'Lead';
  static icon = TargetIcon;

  @field name = contains(StringField);
  @field company = contains(StringField);
  @field email = contains(EmailField);
  @field phone = contains(PhoneNumberField);
  @field source = contains(LeadSourceField);
  @field status = contains(LeadStatusField);
  @field score = contains(NumberField);
  // Which specific activity produced this lead. `source` names the channel;
  // this names the campaign. The lead points at the campaign, never the
  // reverse — a campaign's lead count is a query, not a stored list.
  @field campaign = linksTo(Campaign);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: Lead) {
      return this.name?.trim()?.length
        ? this.name
        : `Untitled ${this.constructor.displayName}`;
    },
  });

  static atom = class Atom extends Component<typeof Lead> {
    <template>
      <span class='atom'>
        <Avatar
          @name={{if @model.name @model.name 'Unnamed'}}
          @shape='rounded'
          @size={{16}}
        />
        <span class='name'>{{if @model.name @model.name 'Unnamed Lead'}}</span>
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

  static embedded = class Embedded extends Component<typeof Lead> {
    get items(): KeyValueItem[] {
      let m = this.args.model;
      let rows: KeyValueItem[] = [];
      if (m?.source) rows.push({ key: 'Source', value: m.source });
      if (m?.company) rows.push({ key: 'Company', value: m.company });
      if (m?.email) rows.push({ key: 'Email', value: m.email });
      if (m?.phone) rows.push({ key: 'Phone', value: m.phone });
      if (m?.campaign) rows.push({ key: 'Campaign', value: '@campaign' });
      return rows;
    }
    get subtitle() {
      let m = this.args.model;
      return [m?.company, m?.source].filter(Boolean).join(' · ');
    }
    <template>
      <RecordEmbedded
        @mark={{@model.name}}
        @title={{@model.cardTitle}}
        @subtitle={{this.subtitle}}
        @chips={{array
          (hash label=@model.status hue=(statusHue @model.status))
        }}
        @summary={{if
          (hasNumber @model.score)
          (concat 'Score ' @model.score ' of 100')
        }}
        @items={{this.items}}
      >
        <:value as |row|>
          {{#if (eq row.value '@campaign')}}
            <@fields.campaign @format='atom' @displayContainer={{false}} />
          {{else}}{{row.value}}{{/if}}
        </:value>
      </RecordEmbedded>
    </template>
  };

  static fitted = class Fitted extends Component<typeof Lead> {
    get subtitle() {
      let m = this.args.model;
      return [m?.company, m?.source].filter(Boolean).join(' · ');
    }
    <template>
      <CompactFitted
        @mark={{if @model.cardTitle @model.cardTitle ''}}
        @title={{@model.cardTitle}}
        @sub={{this.subtitle}}
        @fact={{if
          (hasNumber @model.score)
          (concat 'Score ' @model.score ' of 100')
        }}
        @big={{if (hasNumber @model.score) (concat '' @model.score)}}
        @bigLabel='Score of 100'
        @tags={{if
          @model.status
          (array (hash label=@model.status tone='info'))
        }}
      >
        <:rows>
          {{#if @model.company}}<CompactRow
              @k='Company'
              @v={{@model.company}}
            />{{/if}}
          {{#if @model.source}}<CompactRow
              @k='Source'
              @v={{@model.source}}
            />{{/if}}
          {{#if @model.email}}<CompactRow
              @k='Email'
              @v={{@model.email}}
            />{{/if}}
          {{#if @model.campaign}}<CompactRow @k='Campaign'><@fields.campaign
                @format='atom'
                @displayContainer={{false}}
              /></CompactRow>{{/if}}
        </:rows>
      </CompactFitted>
    </template>
  };

  static isolated = LeadIsolated;
}
