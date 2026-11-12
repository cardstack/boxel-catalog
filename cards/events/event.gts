import { markDefinition } from '@cardstack/base/mark-definition';
import {
  CardDef,
  Component,
  contains,
  field,
  linksTo,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import DateTimeField from 'https://cardstack.com/base/datetime';
import MarkdownField from 'https://cardstack.com/base/markdown';
import CalendarEventIcon from '@cardstack/boxel-icons/calendar-event';
import { FormatDate } from '@cardstack/pretui/components/format-date';
import { EntityDisplay } from '@cardstack/pretui/components/entity-display';

import { Location } from './location';
import CapacityField from './capacity-field';
import { statusField } from '@cardstack/catalog/fields/status/status';
import { IsoFrame } from '../shared/compact-sheet';
import { RichFittedCard, Detail } from '../shared/rich-fitted-card';

/**
 * Event lifecycle. Draft is unannounced planning; Scheduled is public;
 * Live only matters to consumers that render "happening now"; Cancelled can
 * be reinstated (postponements do exactly this), Completed cannot un-happen.
 */
export const EventStatusField = markDefinition(
  statusField({
    displayName: 'Event Status',
    options: [
      { value: 'Draft', hue: 'slate', meaning: 'Being planned — not public' },
      { value: 'Scheduled', hue: 'teal', meaning: 'Announced and upcoming' },
      { value: 'Live', hue: 'green', meaning: 'Happening now' },
      {
        value: 'Completed',
        hue: 'slate',
        meaning: 'Took place',
        terminal: true,
        holds: true,
      },
      {
        value: 'Cancelled',
        hue: 'red',
        meaning: 'Called off — can be reinstated',
        holds: true,
      },
    ],
    transitions: {
      Draft: ['Scheduled', 'Cancelled'],
      Scheduled: ['Live', 'Completed', 'Cancelled'],
      Live: ['Completed'],
      Cancelled: ['Scheduled'],
    },
  }),
);

/**
 * Something that happens at a time, usually at a place, usually with an
 * audience — the generic block. What KIND of happening (a match, a gig, an
 * open day) is the consumer's `kind` label; the domain's extras (opponent,
 * headliner, home/away) live on the consumer's extending card.
 *
 * `capacity` is the configured ceiling and its named slices (see the
 * Capacity spec); how much is booked against it is live Booking data the
 * consumer queries. `startsAt`/`endsAt` are instants (DateTimeFields) — an
 * all-day event is one whose consumer chose not to render the times.
 */
export class Event extends CardDef {
  static displayName = 'Event';
  static icon = CalendarEventIcon;

  @field title = contains(StringField);
  @field kind = contains(StringField);
  @field startsAt = contains(DateTimeField);
  @field endsAt = contains(DateTimeField);
  @field venue = linksTo(Location);
  @field capacity = contains(CapacityField);
  @field status = contains(EventStatusField);
  @field description = contains(MarkdownField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: Event) {
      return this.title?.trim()?.length
        ? this.title
        : `Untitled ${this.constructor.displayName}`;
    },
  });

  static atom = class Atom extends Component<typeof Event> {
    <template>
      <span class='ev-atom'>
        <CalendarEventIcon class='ev-icon' />
        <span class='ev-name'>{{@model.cardTitle}}</span>
      </span>
      <style scoped>
        .ev-atom {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-4xs);
          font-size: var(--boxel-font-size-xs);
          font-weight: 500;
        }
        .ev-icon {
          width: 0.875rem;
          height: 0.875rem;
          flex-shrink: 0;
          color: var(--muted-foreground);
        }
        .ev-name {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  // The date tile formats in en-US, like the DateTimeField beside it, so the
  // tile and the line next to it never disagree on the month name.
  static embedded = class Embedded extends Component<typeof Event> {
    <template>
      <div class='ev'>
        <EntityDisplay
          class='ev-entity'
          @title={{@model.cardTitle}}
          @center={{true}}
        >
          <:visual>
            <div class='ev-date'>
              <FormatDate
                class='ev-day'
                @date={{@model.startsAt}}
                @locale='en-US'
                @day='numeric'
                @placeholder='?'
              />
              <FormatDate
                class='ev-month'
                @date={{@model.startsAt}}
                @locale='en-US'
                @month='short'
                @placeholder='TBD'
              />
            </div>
          </:visual>
          <:meta>
            {{#if @model.startsAt}}<@fields.startsAt />{{/if}}
            {{#if @model.venue.name}}· {{@model.venue.name}}{{/if}}
          </:meta>
        </EntityDisplay>
        <span class='ev-status'>
          {{#if @model.status}}<@fields.status @format='atom' />{{/if}}
        </span>
      </div>
      <style scoped>
        .ev {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-sm);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        /* Pret UI EntityDisplay: the date tile in its visual slot, sized and
           spaced through its own knobs, title and meta at the row's sizes. */
        .ev-entity {
          --pretui-entity-visual-size: 2.75rem;
          flex: 1;
        }
        /* The date block is the row's anchor: events are found by date
           first, name second. */
        .ev-date {
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          box-sizing: border-box;
          width: 100%;
          height: 100%;
          border: 1px solid var(--border);
          border-radius: 0.5rem;
          background-color: var(--muted);
          color: var(--foreground);
          flex-shrink: 0;
        }
        .ev-day {
          font-size: var(--boxel-font-size);
          font-weight: 700;
          line-height: 1.1;
          font-variant-numeric: tabular-nums;
        }
        .ev-month {
          font-size: 0.5625rem; /* ladder 9px label: no Boxel token below 11px */
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.08em;
          color: var(--muted-foreground);
        }
        /* Constant-width slot so event rows column-align whether or not a
           status is set. */
        .ev-status {
          width: 5.75rem;
          display: inline-flex;
          justify-content: flex-end;
          flex-shrink: 0;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof Event> {
    <template>
      <RichFittedCard>
        <:avatar><CalendarEventIcon class='mark' aria-hidden='true' /></:avatar>
        <:title>{{@model.cardTitle}}</:title>
        <:status>{{#if @model.status}}<@fields.status
              @format='atom'
            />{{/if}}</:status>
        <:subtitle>{{@model.kind}}</:subtitle>
        <:fact>{{#if @model.startsAt}}<@fields.startsAt />{{/if}}</:fact>
        <:details>{{#if @model.venue}}<Detail @label='Venue'><@fields.venue
                @format='atom'
                @displayContainer={{false}}
              /></Detail>{{/if}}</:details>
      </RichFittedCard>
      <style scoped>
        .mark {
          inline-size: var(--pretui-avatar-size);
          block-size: var(--pretui-avatar-size);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static isolated = class Isolated extends Component<typeof Event> {
    <template>
      <IsoFrame>
        <article class='ev-page'>
          <header class='eh'>
            <div class='eh-id'>
              <p class='doc-kind'>{{if @model.kind @model.kind 'Event'}}</p>
              <h1>{{@model.cardTitle}}</h1>
              <p class='eh-when'>
                {{#if @model.startsAt}}
                  <@fields.startsAt />
                  {{#if @model.endsAt}}&nbsp;–&nbsp;<@fields.endsAt />{{/if}}
                {{else}}
                  Date to be announced
                {{/if}}
              </p>
            </div>
            {{#if @model.status}}
              <span class='eh-status'><@fields.status
                  @format='embedded'
                /></span>
            {{/if}}
          </header>
          {{#if @model.venue}}
            <section class='panel'>
              <h2>Venue</h2>
              <div class='venue'><@fields.venue @format='embedded' /></div>
            </section>
          {{/if}}
          {{#if @model.capacity.total}}
            <section class='panel'>
              <h2>Capacity</h2>
              <@fields.capacity @format='embedded' />
            </section>
          {{/if}}
          {{#if @model.description}}
            <section class='panel'>
              <h2>About</h2>
              <div class='about'><@fields.description /></div>
            </section>
          {{/if}}
        </article>
      </IsoFrame>
      <style scoped>
        .ev-page {
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
        .eh {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp);
          border-bottom: 0.125rem solid var(--foreground);
          padding-bottom: var(--boxel-sp-lg);
        }
        .eh-id {
          flex: 1;
          min-width: 0;
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
        .eh-when {
          margin: var(--boxel-sp-4xs) 0 0;
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
        }
        .eh-status {
          flex-shrink: 0;
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
        .venue {
          border: 1px solid var(--border);
          border-radius: var(--radius);
        }
        .about {
          font-size: var(--boxel-font-size-sm);
          line-height: 1.6;
        }
      </style>
    </template>
  };
}
