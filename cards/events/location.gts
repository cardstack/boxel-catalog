import {
  CardDef,
  Component,
  contains,
  field,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import AddressField from 'https://cardstack.com/base/address';
import PhoneNumberField from 'https://cardstack.com/base/phone-number';
import WebsiteField from 'https://cardstack.com/base/website';
import MarkdownField from 'https://cardstack.com/base/markdown';
import GeoPointField from '@cardstack/catalog/fields/geo-point/geo-point';
import MapPinIcon from '@cardstack/boxel-icons/map-pin';
import { eq } from '@cardstack/boxel-ui/helpers';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { EntityDisplay } from '@cardstack/pretui/components/entity-display';
import {
  KeyValue,
  type KeyValueItem,
} from '@cardstack/pretui/components/key-value';

import { StatePill } from '@cardstack/catalog/components/state-pill';

/**
 * A named physical place — somewhere things happen, ship to, or are held at.
 *
 * The block is the place itself: name, what kind of place it is, where it
 * stands and how to reach it. Everything a place means to one domain — a
 * stadium's capacity, a warehouse's racking, an office's desks — belongs on
 * the consumer's card, which links here or extends this. That split is what
 * lets one Location serve an event's venue and an order's pickup point
 * without either seeing the other's baggage.
 *
 * `kind` is a label in the consumer's vocabulary (Stadium, Office, Warehouse,
 * Clinic) — deliberately free text and never a lifecycle, so it is not
 * colour-coded.
 */
export class Location extends CardDef {
  static displayName = 'Location';
  static icon = MapPinIcon;

  @field name = contains(StringField);
  @field kind = contains(StringField);
  @field address = contains(AddressField);
  @field geo = contains(GeoPointField);
  @field phone = contains(PhoneNumberField);
  @field website = contains(WebsiteField);
  @field description = contains(MarkdownField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: Location) {
      return this.name?.trim()?.length
        ? this.name
        : `Untitled ${this.constructor.displayName}`;
    },
  });

  static atom = class Atom extends Component<typeof Location> {
    <template>
      <span class='loc-atom'>
        <MapPinIcon class='pin' />
        <span class='loc-name'>{{if
            @model.name
            @model.name
            'Unnamed Location'
          }}</span>
      </span>
      <style scoped>
        .loc-atom {
          display: inline-flex;
          align-items: center;
          gap: 0.25rem;
          font-size: 0.8125rem;
          font-weight: 500;
          color: var(--foreground);
        }
        .pin {
          width: 0.875rem;
          height: 0.875rem;
          flex-shrink: 0;
          color: var(--muted-foreground);
        }
        .loc-name {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof Location> {
    get place() {
      let a = this.args.model?.address;
      return [a?.city, a?.country?.name ?? a?.state].filter(Boolean).join(', ');
    }
    <template>
      <EntityDisplay
        class='loc'
        @title={{if @model.name @model.name 'Unnamed'}}
        @tag={{@model.kind}}
        @center={{true}}
      >
        <:visual>
          <span class='pin-disc'><MapPinIcon class='pin' /></span>
        </:visual>
        <:meta>
          {{#if this.place}}
            {{this.place}}
          {{else}}
            <span class='muted-em'>No address on file</span>
          {{/if}}
        </:meta>
      </EntityDisplay>
      <style scoped>
        /* Pret UI EntityDisplay: the pin disc in its visual slot, the kind
           as its tag Chip on StatePill's 14% / 62% recipe (15.20:1 light /
           6.81:1 dark), title and meta at the row's sizes. */
        .loc {
          --pretui-entity-visual-size: 2rem;
          --pretui-chip-mix: 14%;
          --pretui-ink-mix: 62%;
          --space-3: 0.625rem;
          --text-ui-md: 0.875rem;
          --text-ui-sm: 0.75rem;
          padding: 0.625rem 0.875rem;
        }
        /* EntityDisplay sizes the slot's svg to 100%, so the disc's padding
           is what keeps the pin at half the disc. */
        .pin-disc {
          display: inline-flex;
          align-items: center;
          justify-content: center;
          box-sizing: border-box;
          width: 100%;
          height: 100%;
          padding: 25%;
          border-radius: 50%;
          background-color: var(--muted);
          color: var(--muted-foreground);
        }
        .muted-em {
          font-style: italic;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof Location> {
    get name() {
      return this.args.model?.name?.trim() || 'Unnamed Location';
    }
    get place() {
      let a = this.args.model?.address;
      return [a?.city, a?.country?.name ?? a?.state].filter(Boolean).join(', ');
    }
    get street() {
      return this.args.model?.address?.addressLine1;
    }
    <template>
      <div class='fitted'>
        <span class='pin-disc'><MapPinIcon class='pin' /></span>
        <div class='info'>
          <span class='name'>{{this.name}}</span>
          {{#if @model.kind}}
            <span class='meta line-kind'>{{@model.kind}}</span>
          {{/if}}
          {{#if this.place}}
            <span class='meta line-place'>{{this.place}}</span>
          {{/if}}
          {{#if this.street}}
            <span class='meta line-street'>{{this.street}}</span>
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
        .pin-disc {
          display: inline-flex;
          align-items: center;
          justify-content: center;
          width: 1.75rem;
          height: 1.75rem;
          border-radius: 50%;
          background-color: var(--muted);
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
        .pin {
          width: 0.875rem;
          height: 0.875rem;
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
        .line-kind,
        .line-place,
        .line-street {
          display: none;
        }
        /* Badge degradation: strip height keeps only the first line. */
        @container fitted-card (max-height: 50px) {
          .fitted {
            padding: 0.25rem 0.5rem;
            gap: 0.125rem;
          }
        }
        @container fitted-card (min-height: 65px) {
          .line-place {
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
          .pin-disc {
            width: 2.25rem;
            height: 2.25rem;
          }
          .line-kind {
            display: block;
          }
        }
        @container fitted-card (min-width: 400px) and (min-height: 170px) {
          .line-street {
            display: block;
          }
        }
      </style>
    </template>
  };

  static isolated = class Isolated extends Component<typeof Location> {
    get name() {
      return this.args.model?.name?.trim() || 'Unnamed Location';
    }
    get hasGeo() {
      return (
        this.args.model?.geo?.lat != null && this.args.model?.geo?.lon != null
      );
    }
    get reach(): KeyValueItem[] {
      let m = this.args.model;
      let rows: KeyValueItem[] = [];
      if (m?.phone) rows.push({ key: 'Phone', value: 'phone' });
      if (m?.website) rows.push({ key: 'Website', value: 'website' });
      return rows;
    }
    <template>
      <article class='loc-page'>
        <header class='lh'>
          <span class='pin-disc'><MapPinIcon class='pin' /></span>
          <div class='lh-id'>
            <p class='doc-kind'>Location</p>
            <h1>{{this.name}}</h1>
          </div>
          <StatePill @label={{@model.kind}} />
        </header>
        {{#if this.hasGeo}}
          <div class='map'><@fields.geo @format='embedded' /></div>
        {{/if}}
        <section class='panel'>
          <h2>Address</h2>
          {{#if @model.address.fullAddress}}
            <div class='addr'><@fields.address @format='embedded' /></div>
          {{else}}
            <EmptyState
              class='empty'
              @title='No address on file'
              @texture={{false}}
            />
          {{/if}}
        </section>
        {{#if this.reach.length}}
          <section class='panel'>
            <h2>Reach</h2>
            <KeyValue class='details' @items={{this.reach}}>
              <:value as |row|>
                {{#if (eq row.value 'phone')}}
                  <@fields.phone />
                {{else}}
                  <@fields.website />
                {{/if}}
              </:value>
            </KeyValue>
          </section>
        {{/if}}
        {{#if @model.description}}
          <section class='panel'>
            <h2>About</h2>
            <div class='about'><@fields.description /></div>
          </section>
        {{/if}}
      </article>
      <style scoped>
        .loc-page {
          max-width: 40rem;
          margin: 0 auto;
          padding: 2rem 1.5rem;
          display: flex;
          flex-direction: column;
          gap: 1.25rem;
        }
        .lh {
          display: flex;
          align-items: center;
          gap: 1rem;
          border-bottom: 0.125rem solid var(--foreground);
          padding-bottom: 1.25rem;
        }
        .pin-disc {
          display: inline-flex;
          align-items: center;
          justify-content: center;
          width: 3.5rem;
          height: 3.5rem;
          border-radius: 50%;
          background-color: var(--muted);
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
        .pin {
          width: 1.625rem;
          height: 1.625rem;
        }
        .lh-id {
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
        .map {
          border: 1px solid var(--border);
          border-radius: 0.75rem;
          overflow: hidden;
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
          overflow-wrap: anywhere;
        }
        /* Pret UI EmptyState, tuned through its spacing and title knobs to a
           compact well inside the panel. */
        .empty {
          --space-9: 1rem;
          --space-6: 1rem;
          --text-heading: var(--boxel-font-size);
        }
        .about {
          font-size: 0.875rem;
          line-height: 1.6;
        }
      </style>
    </template>
  };
}
