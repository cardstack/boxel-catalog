import {
  CardDef,
  Component,
  contains,
  field,
  linksTo,
} from '@cardstack/base/card-api';
import { RichFittedCard, Detail } from '../shared/rich-fitted-card';
import { Chip } from '@cardstack/pretui/components/chip';
import StringField from '@cardstack/base/string';
import MarkdownField from '@cardstack/base/markdown';
import DatetimeField from '@cardstack/base/datetime';
import enumField from '@cardstack/base/enum';
import HistoryIcon from '@cardstack/boxel-icons/history';
import { array, hash } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { type KeyValueItem } from '@cardstack/pretui/components/key-value';

import { RecordEmbedded, RecordPage, shortDate } from './record-views';
import { User } from './user';
import { IsoFrame } from '../shared/compact-sheet';

const ActivityTypeField = enumField(StringField, {
  options: ['note', 'call', 'email', 'meeting', 'status change'],
  displayName: 'Activity Type',
});

export class Activity extends CardDef {
  static displayName = 'Activity';
  static icon = HistoryIcon;

  @field activityType = contains(ActivityTypeField);
  @field summary = contains(StringField);
  @field body = contains(MarkdownField);
  @field occurredAt = contains(DatetimeField);
  @field author = linksTo(User);
  @field about = linksTo(CardDef);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: Activity) {
      return this.summary?.trim()?.length
        ? this.summary
        : `Untitled ${this.constructor.displayName}`;
    },
  });

  static atom = class Atom extends Component<typeof Activity> {
    <template>
      <span class='atom'>
        <Avatar @name='A C' @shape='rounded' @size={{16}} />
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

  static embedded = class Embedded extends Component<typeof Activity> {
    get items(): KeyValueItem[] {
      let m = this.args.model;
      let rows: KeyValueItem[] = [];
      if (m?.occurredAt) rows.push({ key: 'When', value: when(m.occurredAt) });
      if (m?.about) rows.push({ key: 'About', value: '@about' });
      if (m?.author) rows.push({ key: 'Author', value: '@author' });
      return rows;
    }
    get subtitle() {
      let m = this.args.model;
      return [when(m?.occurredAt), m?.author?.name].filter(Boolean).join(' · ');
    }
    <template>
      <RecordEmbedded
        @mark='A C'
        @title={{@model.cardTitle}}
        @subtitle={{this.subtitle}}
        @chips={{if
          @model.activityType
          (array (hash label=@model.activityType hue='slate'))
        }}
        @items={{this.items}}
      >
        <:value as |row|>
          {{#if (eq row.value '@about')}}
            <@fields.about @format='atom' @displayContainer={{false}} />
          {{else if (eq row.value '@author')}}
            <@fields.author @format='atom' @displayContainer={{false}} />
          {{else}}{{row.value}}{{/if}}
        </:value>
      </RecordEmbedded>
    </template>
  };

  static fitted = class Fitted extends Component<typeof Activity> {
    get subtitle() {
      let m = this.args.model;
      return [when(m?.occurredAt), m?.author?.name].filter(Boolean).join(' · ');
    }
    <template>
      <RichFittedCard>
        <:avatar><Avatar
            @name='Activity'
            @shape='square'
            @size={{20}}
          /></:avatar>
        <:title>{{@model.cardTitle}}</:title>
        <:status>{{#each
            if @model.activityType (array (hash label=@model.activityType))
            as |t|
          }}<Chip
              @label={{t.label}}
              @tone={{t.tone}}
              @appearance='plain'
            />{{/each}}</:status>
        <:subtitle>{{this.subtitle}}</:subtitle>
        <:details>
          {{#if @model.activityType}}<Detail
              @label='Type'
              @value={{@model.activityType}}
            />{{/if}}
          {{#if @model.about}}<Detail @label='About'><@fields.about
                @format='atom'
                @displayContainer={{false}}
              /></Detail>{{/if}}
          {{#if @model.author}}<Detail @label='Author'><@fields.author
                @format='atom'
                @displayContainer={{false}}
              /></Detail>{{/if}}
        </:details>
      </RichFittedCard>
    </template>
  };

  static isolated = class Isolated extends Component<typeof Activity> {
    get stats() {
      let m = this.args.model;
      return [
        {
          label: 'Type',
          value: m?.activityType ?? '',
          hint: m?.author?.name ? `logged by ${m.author.name}` : '',
          tone: 'neutral',
        },
        {
          label: 'When',
          value: shortDate(m?.occurredAt),
          hint: m?.occurredAt
            ? new Date(m.occurredAt).toLocaleTimeString('en-US', {
                hour: 'numeric',
                minute: '2-digit',
              })
            : '',
          tone: 'neutral',
        },
        {
          label: 'Follow-up',
          value: this.followUp ? 'Open' : '—',
          hint: this.followUp ?? 'none noted',
          tone: this.followUp ? 'warning' : 'neutral',
        },
      ];
    }
    // The notes' commitment ("agreed to …", "… by Friday"), if one is written down.
    get followUp(): string | undefined {
      let body = String(this.args.model?.body ?? '');
      let s = body
        .split(/(?<=[.!?])\s+/)
        .find((x) =>
          /agreed to|follow|by (mon|tue|wed|thu|fri|next|end)/i.test(x),
        );
      return s?.replace(/^.*?(agreed to|will)\s+/i, '').replace(/[.]$/, '');
    }
    get details(): KeyValueItem[] {
      let m = this.args.model;
      let rows: KeyValueItem[] = [];
      if (m?.activityType) rows.push({ key: 'Type', value: m.activityType });
      if (m?.occurredAt) rows.push({ key: 'When', value: when(m.occurredAt) });
      if (m?.author?.name) rows.push({ key: 'Author', value: m.author.name });
      return rows;
    }
    get subtitle() {
      let m = this.args.model;
      return [when(m?.occurredAt), m?.author?.name].filter(Boolean).join(' · ');
    }
    <template>
      <IsoFrame>
        <RecordPage
          @mark='A C'
          @title={{@model.cardTitle}}
          @subtitle={{this.subtitle}}
          @chips={{if
            @model.activityType
            (array (hash label=@model.activityType hue='slate'))
          }}
          @stats={{this.stats}}
          @linked={{this.linked}}
          @details={{this.details}}
        >
          <:main>
            <h2 class='notes-h'>Notes</h2>
            <div class='notes'><@fields.body /></div>
          </:main>
          <:value as |row|>
            {{#if (eq row.value '@about')}}
              <@fields.about @format='atom' @displayContainer={{false}} />
            {{else if (eq row.value '@author')}}
              <@fields.author @format='atom' @displayContainer={{false}} />
            {{else}}{{row.value}}{{/if}}
          </:value>
        </RecordPage>
      </IsoFrame>
      <style scoped>
        .notes-h {
          margin: 0;
          padding: var(--boxel-sp-xs) var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-sm);
          font-weight: 700;
          border-block-end: 1px solid var(--border);
        }
        .notes {
          padding: var(--boxel-sp-xs) var(--boxel-sp-xs);
        }
      </style>
    </template>
    get linked(): KeyValueItem[] {
      let m = this.args.model;
      let rows: KeyValueItem[] = [];
      if (m?.about) rows.push({ key: 'About', value: '@about' });
      if (m?.author) rows.push({ key: 'Author', value: '@author' });
      return rows;
    }
  };
}

/** "Aug 6, 2026, 10:30" */
function when(d: Date | string | undefined) {
  return d
    ? `${shortDate(d, true)}, ${new Date(d).toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit', hour12: false })}`
    : '';
}

// style tags live at the template root
