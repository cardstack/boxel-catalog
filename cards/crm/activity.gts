import {
  CardDef,
  Component,
  contains,
  field,
  linksTo,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import MarkdownField from '@cardstack/base/markdown';
import DatetimeField from '@cardstack/base/datetime';
import enumField from '@cardstack/base/enum';
import HistoryIcon from '@cardstack/boxel-icons/history';
import NoteIcon from '@cardstack/boxel-icons/notes';
import PhoneIcon from '@cardstack/boxel-icons/phone';
import MailIcon from '@cardstack/boxel-icons/mail';
import CalendarIcon from '@cardstack/boxel-icons/calendar';
import ArrowRightIcon from '@cardstack/boxel-icons/arrow-right';
import { EntityDisplay } from '@cardstack/pretui/components/entity-display';
import { Panel } from '@cardstack/pretui/components/panel';
import { User } from '@cardstack/catalog/cards/crm/user';

const ActivityTypeField = enumField(StringField, {
  options: ['note', 'call', 'email', 'meeting', 'status change'],
  displayName: 'Activity Type',
});

const TYPE_ICONS: Record<string, typeof NoteIcon> = {
  note: NoteIcon,
  call: PhoneIcon,
  email: MailIcon,
  meeting: CalendarIcon,
  'status change': ArrowRightIcon,
};

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
      <span class='activity-atom'>
        <HistoryIcon class='aa-icon' />
        <span class='aa-name'>{{@model.cardTitle}}</span>
      </span>
      <style scoped>
        .activity-atom {
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
          font-size: 0.8125rem;
          font-weight: 500;
          color: var(--foreground);
        }
        .aa-icon {
          width: 0.875rem;
          height: 0.875rem;
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
        .aa-name {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof Activity> {
    get typeIcon() {
      return TYPE_ICONS[this.args.model?.activityType ?? ''] ?? NoteIcon;
    }
    <template>
      <div class='activity-row'>
        <EntityDisplay
          class='entity'
          @variant='thumbnail'
          @title={{@model.cardTitle}}
        >
          <:visual><this.typeIcon class='type-icon' /></:visual>
          <:meta>
            {{#if @model.activityType}}
              <span class='type'>{{@model.activityType}}</span>
            {{/if}}
            {{#if @model.author.name}}
              <span>· {{@model.author.name}}</span>
            {{/if}}
          </:meta>
        </EntityDisplay>
        {{#if @model.occurredAt}}
          <span class='when'><@fields.occurredAt /></span>
        {{/if}}
      </div>
      <style scoped>
        .activity-row {
          display: flex;
          align-items: flex-start;
          gap: 0.625rem;
          padding: 0.625rem 0.875rem;
        }
        /* EntityDisplay's thumbnail dress holds the type icon; these knobs
           size the visual, title, meta line and gap to the row's scale. */
        .entity {
          flex: 1;
          --pretui-entity-visual-size: 1.625rem;
          --text-ui-md: 0.8125rem;
          --text-ui-sm: 0.6875rem;
          --space-3: 0.625rem;
        }
        .type-icon {
          width: 0.875rem;
          height: 0.875rem;
          color: var(--muted-foreground);
        }
        .type {
          text-transform: capitalize;
        }
        .when {
          flex-shrink: 0;
          font-size: 0.6875rem;
          line-height: 1.625rem;
          color: var(--muted-foreground);
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof Activity> {
    get typeIcon() {
      return TYPE_ICONS[this.args.model?.activityType ?? ''] ?? NoteIcon;
    }
    <template>
      <div class='fitted'>
        <div class='top'>
          <this.typeIcon class='icon' />
          {{#if @model.activityType}}
            <span class='type'>{{@model.activityType}}</span>
          {{/if}}
        </div>
        <span class='summary'>{{@model.cardTitle}}</span>
        {{#if @model.occurredAt}}
          <span class='meta line-when'><@fields.occurredAt /></span>
        {{/if}}
        {{#if @model.author.name}}
          <span class='meta line-author'>by {{@model.author.name}}</span>
        {{/if}}
      </div>
      <style scoped>
        .fitted {
          display: flex;
          flex-direction: column;
          justify-content: center;
          gap: 0.25rem;
          width: 100%;
          height: 100%;
          padding: 0.625rem 0.75rem;
          box-sizing: border-box;
          overflow: hidden;
          color: var(--foreground);
        }
        .top {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: 0.5rem;
        }
        .icon {
          width: 1rem;
          height: 1rem;
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
        .type {
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
          white-space: nowrap;
        }
        .summary {
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
        .line-when,
        .line-author {
          display: none;
        }
        @container fitted-card (min-height: 65px) {
          .line-when {
            display: block;
          }
        }
        @container fitted-card (min-height: 170px) {
          .line-author {
            display: block;
          }
        }
      </style>
    </template>
  };

  static isolated = class Isolated extends Component<typeof Activity> {
    get typeIcon() {
      return TYPE_ICONS[this.args.model?.activityType ?? ''] ?? NoteIcon;
    }
    <template>
      <article class='activity-page'>
        <header class='ah'>
          <span class='marker'><this.typeIcon class='type-icon' /></span>
          <div class='ah-id'>
            <p class='doc-kind'>{{if
                @model.activityType
                @model.activityType
                'Activity'
              }}</p>
            <h1>{{@model.cardTitle}}</h1>
            <p class='byline'>
              {{#if @model.occurredAt}}<@fields.occurredAt />{{/if}}
              {{#if @model.author.name}}· {{@model.author.name}}{{/if}}
            </p>
          </div>
        </header>
        {{#if @model.body}}
          <Panel class='body'><@fields.body /></Panel>
        {{/if}}
        {{#if @model.about}}
          <Panel @title='About'><@fields.about @format='atom' /></Panel>
        {{/if}}
      </article>
      <style scoped>
        .activity-page {
          max-width: 40rem;
          margin: 0 auto;
          padding: 2rem 1.5rem;
          display: flex;
          flex-direction: column;
          gap: 1.25rem;
        }
        .ah {
          display: flex;
          align-items: center;
          gap: 1rem;
          border-bottom: 0.125rem solid var(--foreground);
          padding-bottom: 1.25rem;
        }
        .marker {
          display: inline-flex;
          align-items: center;
          justify-content: center;
          width: 3rem;
          height: 3rem;
          border-radius: 50%;
          background-color: var(--muted);
          flex-shrink: 0;
        }
        .type-icon {
          width: 1.375rem;
          height: 1.375rem;
          color: var(--muted-foreground);
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
          margin: 0;
          font-size: 1.5rem;
          line-height: 1.15;
        }
        .byline {
          margin: 0.25rem 0 0;
          font-size: 0.8125rem;
          color: var(--muted-foreground);
        }
        .body {
          font-size: 0.875rem;
        }
      </style>
    </template>
  };
}
