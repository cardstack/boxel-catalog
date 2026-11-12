import {
  CardDef,
  Component,
  contains,
  field,
  linksTo,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import AddressField from 'https://cardstack.com/base/address';
import PhoneNumberField from 'https://cardstack.com/base/phone-number';
import WebsiteField from 'https://cardstack.com/base/website';
import MarkdownField from 'https://cardstack.com/base/markdown';
import GeoPointField from '@cardstack/catalog/fields/geo-point/geo-point';
import MapPinIcon from '@cardstack/boxel-icons/map-pin';
import { concat } from '@ember/helper';
import { RichFittedCard, Detail } from '../shared/rich-fitted-card';
import { IsoFrame } from '../shared/compact-sheet';

// Walks `parent` from the root down to `loc`; capped so a cycle can't hang.
function chain(loc: Location | undefined): Location[] {
  let out: Location[] = [];
  let seen = new Set<Location>();
  for (let n = loc; n && !seen.has(n) && out.length < 12; n = n.parent) {
    seen.add(n);
    out.unshift(n);
  }
  return out;
}

function ancestorsLabel(loc: Location | undefined): string {
  return chain(loc)
    .slice(0, -1)
    .map((l) => l.name ?? 'Unnamed')
    .join(' › ');
}

function placeLabel(loc: Location | undefined): string {
  let a = loc?.address;
  return [a?.city, a?.country?.name ?? a?.state].filter(Boolean).join(', ');
}

function nameOf(loc: Location | undefined): string {
  return loc?.name?.trim() || 'Unnamed Location';
}

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

  // Places nest: a room is in a floor, in a building, on a site. Consumers
  // that need the full path walk `parent`; the one-hop label below is what a
  // fitted view can show without resolving links.
  @field parent = linksTo(() => Location);

  @field parentId = contains(StringField, {
    computeVia: function (this: Location) {
      return this.parent?.id;
    },
  });

  @field parentName = contains(StringField, {
    computeVia: function (this: Location) {
      return this.parent?.name;
    },
  });

  @field pathLabel = contains(StringField, {
    computeVia: function (this: Location) {
      let here = this.name ?? 'Unnamed';
      return this.parent?.name ? `${this.parent.name} › ${here}` : here;
    },
  });

  @field cardTitle = contains(StringField, {
    computeVia: function (this: Location) {
      return this.name?.trim()?.length
        ? this.name
        : `Untitled ${this.constructor.displayName}`;
    },
  });

  static atom = class Atom extends Component<typeof Location> {
    get name() {
      return nameOf(this.args.model as Location);
    }
    <template>
      <span class='loc-atom'>
        <span class='mark' aria-hidden='true'><MapPinIcon
            width='0.75rem'
            height='0.75rem'
          /></span>
        <span class='name'>{{this.name}}</span>
        {{#if @model.kind}}
          <span class='dot-text'><span class='dot'></span>{{@model.kind}}</span>
        {{/if}}
      </span>
      <style scoped>
        .loc-atom {
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
          max-width: 100%;
          min-width: 0;
          font-family: var(--font-sans);
          font-size: 0.75rem;
          color: var(--foreground);
        }
        .mark {
          display: inline-grid;
          place-items: center;
          flex-shrink: 0;
          width: 1.125rem;
          height: 1.125rem;
          border-radius: 0.25rem;
          background-color: var(--muted);
        }
        .name {
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          font-weight: 600;
        }
        .dot-text {
          display: inline-flex;
          align-items: center;
          gap: 0.25rem;
          flex-shrink: 0;
          color: var(--muted-foreground);
        }
        .dot {
          width: 0.375rem;
          height: 0.375rem;
          border-radius: 50%;
          background-color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof Location> {
    get name() {
      return nameOf(this.args.model as Location);
    }
    get ancestors() {
      return ancestorsLabel(this.args.model as Location);
    }
    get place() {
      return placeLabel(this.args.model as Location);
    }
    <template>
      <article class='loc-emb'>
        <header class='head'>
          <span class='mark' aria-hidden='true'><MapPinIcon
              width='0.875rem'
              height='0.875rem'
            /></span>
          <div class='id'>
            <p class='name'>{{this.name}}</p>
            {{#if this.ancestors}}<p class='meta'>{{this.ancestors}}</p>{{/if}}
          </div>
        </header>
        {{#if @model.kind}}
          <p class='status'><span class='dot'></span>{{@model.kind}}</p>
        {{/if}}
        <p class='fact'>{{if this.place this.place '—'}}</p>
        <dl class='kv'>
          <dt>Kind</dt><dd>{{if @model.kind @model.kind '—'}}</dd>
          <dt>Parent</dt><dd>{{if @model.parentName @model.parentName '—'}}</dd>
          <dt>Street</dt><dd>{{if
              @model.address.addressLine1
              @model.address.addressLine1
              '—'
            }}</dd>
          <dt>Phone</dt><dd class='mono'>{{if
              @model.phone
              @model.phone
              '—'
            }}</dd>
          {{#if @model.parent}}
            <dt>Parent</dt><dd><@fields.parent
                @format='atom'
                @displayContainer={{false}}
              /></dd>
          {{/if}}
        </dl>
      </article>
      <style scoped>
        .loc-emb {
          display: flex;
          flex-direction: column;
          gap: 0.375rem;
          padding: 0.625rem 0.75rem;
          font-family: var(--font-sans);
          font-size: 0.75rem;
          color: var(--card-foreground);
        }
        .head {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          min-width: 0;
        }
        .mark {
          display: inline-grid;
          place-items: center;
          flex-shrink: 0;
          width: 1.5rem;
          height: 1.5rem;
          border-radius: 0.25rem;
          background-color: var(--muted);
        }
        .id {
          min-width: 0;
        }
        .name {
          margin: 0;
          font-family: var(--font-sans);
          font-size: 0.75rem;
          font-weight: 700;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .meta {
          margin: 0;
          font-size: 0.6875rem;
          color: var(--muted-foreground);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .status,
        .fact {
          margin: 0;
        }
        .status {
          display: inline-flex;
          align-items: center;
          gap: 0.25rem;
          font-weight: 600;
        }
        .dot {
          width: 0.375rem;
          height: 0.375rem;
          border-radius: 50%;
          background-color: var(--muted-foreground);
        }
        .kv {
          display: grid;
          grid-template-columns: 5.5rem minmax(0, 1fr);
          margin: 0.25rem 0 0;
        }
        .kv dt,
        .kv dd {
          margin: 0;
          padding: 0.3125rem 0;
          border-top: 1px solid var(--border);
          min-width: 0;
        }
        .kv dt {
          font-family: var(--font-mono);
          font-size: 0.5625rem;
          font-weight: 600;
          letter-spacing: 0.13em;
          text-transform: uppercase;
          color: var(--muted-foreground);
          align-self: center;
        }
        .kv dd {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .mono {
          font-family: var(--font-mono);
          font-size: 0.6875rem;
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof Location> {
    get name() {
      return nameOf(this.args.model as Location);
    }
    get ancestors() {
      return ancestorsLabel(this.args.model as Location);
    }
    get place() {
      return placeLabel(this.args.model as Location);
    }
    <template>
      <RichFittedCard>
        <:avatar><span class='mark' aria-hidden='true'><MapPinIcon
              width='0.875rem'
              height='0.875rem'
            /></span></:avatar>
        <:title>{{this.name}}</:title>
        <:subtitle>{{if this.ancestors this.ancestors this.place}}</:subtitle>
        <:status>{{#if @model.kind}}<span class='dot-text'><span
                class='dot'
              ></span>{{@model.kind}}</span>{{/if}}</:status>
        <:fact>{{if this.place this.place '—'}}</:fact>
        <:details>
          {{#if @model.address.fullAddress}}<Detail
              @label='Address'
              @value={{@model.address.fullAddress}}
            />{{/if}}
          {{#if @model.phone}}<Detail
              @label='Phone'
              @value={{@model.phone}}
            />{{/if}}
          {{#if @model.website}}<Detail
              @label='Website'
              @value={{@model.website}}
            />{{/if}}
        </:details>
        <:relations>{{#if @model.parent}}<@fields.parent
              @format='atom'
              @displayContainer={{false}}
            />{{/if}}</:relations>
      </RichFittedCard>
      <style scoped>
        .mark {
          display: inline-grid;
          place-items: center;
          width: 1.5rem;
          height: 1.5rem;
          border-radius: 0.25rem;
          background-color: var(--muted);
        }
        .dot-text {
          display: inline-flex;
          align-items: center;
          gap: 0.25rem;
          font-size: 0.6875rem;
          font-weight: 600;
          white-space: nowrap;
        }
        .dot {
          width: 0.375rem;
          height: 0.375rem;
          border-radius: 50%;
          background-color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static isolated = class Isolated extends Component<typeof Location> {
    get model() {
      return this.args.model as Location;
    }
    get name() {
      return nameOf(this.model);
    }
    get path() {
      let all = chain(this.model);
      return all.map((l, i) => ({
        name: nameOf(l),
        kind: l.kind,
        current: i === all.length - 1,
      }));
    }
    get ancestors() {
      return ancestorsLabel(this.model);
    }
    get kindsLabel() {
      return chain(this.model)
        .map((l) => l.kind ?? '—')
        .join(' › ');
    }
    get place() {
      return placeLabel(this.model);
    }
    <template>
      <IsoFrame>
        <article class='loc-page'>
          <header class='head'>
            <span class='mark' aria-hidden='true'><MapPinIcon
                width='1.125rem'
                height='1.125rem'
              /></span>
            <div class='id'>
              <h1 class='name'>{{this.name}}</h1>
              <p class='meta'>{{if
                  this.ancestors
                  this.ancestors
                  (if this.place this.place 'Top-level place')
                }}</p>
            </div>
            {{#if @model.kind}}
              <span class='dot-text'><span
                  class='dot dot-primary'
                ></span>{{@model.kind}}</span>
            {{/if}}
          </header>

          <dl class='stats' aria-label='Key numbers'>
            <div class='stat'>
              <dt class='label'>Depth</dt>
              <dd class='value'>{{this.path.length}}</dd>
              <dd class='sub'>{{this.kindsLabel}}</dd>
            </div>
            <div class='stat'>
              <dt class='label'>Kind</dt>
              <dd class='value'>{{if @model.kind @model.kind '—'}}</dd>
              <dd class='sub'>{{if
                  @model.parentName
                  (concat 'in ' @model.parentName)
                  'no parent'
                }}</dd>
            </div>
            <div class='stat'>
              <dt class='label'>Place</dt>
              <dd class='value'>{{if
                  @model.address.city
                  @model.address.city
                  '—'
                }}</dd>
              <dd class='sub'>{{if
                  @model.address.country.name
                  @model.address.country.name
                  '—'
                }}</dd>
            </div>
          </dl>

          <div class='cols'>
            <div class='main'>
              <section class='sec'>
                <h2>Path</h2>
                <ul class='rows'>
                  {{#each this.path as |p|}}
                    <li class='row'>
                      <div class='row-id'>
                        <span class='row-name'>{{p.name}}</span>
                      </div>
                      {{#if p.kind}}
                        <span class='dot-text'><span
                            class='dot {{if p.current "dot-primary"}}'
                          ></span>{{p.kind}}</span>
                      {{/if}}
                    </li>
                  {{/each}}
                </ul>
              </section>
              <section class='sec'>
                <h2>Address</h2>
                <div class='body'>
                  {{#if @model.address.fullAddress}}
                    <@fields.address @format='embedded' />
                  {{else}}
                    <span class='muted'>—</span>
                  {{/if}}
                </div>
              </section>
              {{#if @model.description}}
                <section class='sec'>
                  <h2>About</h2>
                  <div class='body'><@fields.description /></div>
                </section>
              {{/if}}
            </div>

            <aside class='side'>
              <section class='sec'>
                <h2>Linked</h2>
                <dl class='kv'>
                  <dt>Parent</dt>
                  <dd>{{#if @model.parent}}<@fields.parent
                        @format='atom'
                      />{{else}}—{{/if}}</dd>
                </dl>
              </section>
              <section class='sec'>
                <h2>Details</h2>
                <dl class='kv'>
                  <dt>Kind</dt><dd>{{if @model.kind @model.kind '—'}}</dd>
                  <dt>Parent</dt><dd>{{if
                      @model.parentName
                      @model.parentName
                      '—'
                    }}</dd>
                  <dt>City</dt><dd>{{if
                      @model.address.city
                      @model.address.city
                      '—'
                    }}</dd>
                  <dt>Phone</dt><dd class='mono'>{{#if
                      @model.phone
                    }}<@fields.phone />{{else}}—{{/if}}</dd>
                  <dt>Website</dt><dd>{{#if @model.website}}<@fields.website
                      />{{else}}—{{/if}}</dd>
                  <dt>Geo</dt><dd class='mono'>{{if
                      @model.geo.lat
                      (concat @model.geo.lat ', ' @model.geo.lon)
                      '—'
                    }}</dd>
                </dl>
              </section>
            </aside>
          </div>
        </article>
      </IsoFrame>
      <style scoped>
        .loc-page {
          margin: var(--boxel-sp-sm);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          background-color: var(--card);
          color: var(--card-foreground);
          font-family: var(--font-sans);
          font-size: var(--boxel-font-size-xs);
          overflow: hidden;
        }
        .head {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-sm) var(--boxel-sp-xs);
          border-bottom: 1px solid var(--border);
        }
        .mark {
          display: inline-grid;
          place-items: center;
          flex-shrink: 0;
          width: 2rem;
          height: 2rem;
          border-radius: var(--radius);
          background-color: var(--muted);
        }
        .id {
          flex: 1;
          min-width: 0;
        }
        .name {
          margin: 0;
          font-family: var(--font-sans);
          font-size: var(--boxel-font-size-sm);
          font-weight: 700;
        }
        .meta {
          margin: 0;
          font-size: var(--boxel-font-size-2xs);
          color: var(--muted-foreground);
        }
        .dot-text {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-3xs);
          flex-shrink: 0;
          font-weight: 600;
        }
        .dot {
          width: 0.4375rem;
          height: 0.4375rem;
          border-radius: 50%;
          background-color: var(--muted-foreground);
        }
        .dot-primary {
          background-color: var(--primary);
        }
        .stats {
          margin: 0;
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(10rem, 1fr));
          overflow: hidden;
          border-bottom: 1px solid var(--border);
        }
        .stat dt,
        .stat dd {
          margin: 0;
        }
        .stat {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-6xs);
          padding: var(--boxel-sp-xs) var(--boxel-sp-xs);
          margin: 0 -1px -1px 0;
          border-right: 1px solid var(--border);
          border-bottom: 1px solid var(--border);
          min-width: 0;
        }
        .label,
        h2,
        .kv dt {
          font-family: var(--font-mono);
          font-size: 0.5625rem;
          font-weight: 600;
          letter-spacing: 0.13em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .value {
          font-size: var(--boxel-font-size-lg);
          font-weight: 700;
          font-variant-numeric: tabular-nums;
          line-height: 1.2;
        }
        .sub {
          font-size: var(--boxel-font-size-2xs);
          color: var(--muted-foreground);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .cols {
          display: grid;
          grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
        }
        .main {
          border-right: 1px solid var(--border);
        }
        @container (max-width: 44rem) {
          .cols {
            grid-template-columns: minmax(0, 1fr);
          }
          .main {
            border-right: 0;
            border-bottom: 1px solid var(--border);
          }
        }
        .sec + .sec {
          border-top: 1px solid var(--border);
        }
        h2 {
          margin: 0;
          padding: var(--boxel-sp-xs) var(--boxel-sp-xs) var(--boxel-sp-2xs);
          font-family: var(--font-sans);
          font-size: var(--boxel-font-size-xs);
          font-weight: 700;
          letter-spacing: 0;
          text-transform: none;
          color: var(--card-foreground);
        }
        .rows {
          margin: 0;
          padding: 0;
          list-style: none;
        }
        .row {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          min-height: 1.75rem;
          padding: var(--boxel-sp-3xs) var(--boxel-sp-xs);
          border-top: 1px solid var(--border);
        }
        .row-id {
          display: flex;
          flex-direction: column;
          flex: 1;
          min-width: 0;
        }
        .row-name {
          font-weight: 700;
        }
        .body {
          padding: var(--boxel-sp-2xs) var(--boxel-sp-xs) var(--boxel-sp-xs);
          border-top: 1px solid var(--border);
          line-height: 1.5;
        }
        .muted {
          color: var(--muted-foreground);
        }
        .kv {
          display: grid;
          grid-template-columns: 8rem minmax(0, 1fr);
          margin: 0;
          padding: 0 var(--boxel-sp-xs) var(--boxel-sp-2xs);
        }
        .kv dt,
        .kv dd {
          margin: 0;
          padding: var(--boxel-sp-2xs) 0;
          border-top: 1px solid var(--border);
          min-width: 0;
          align-self: stretch;
          display: flex;
          align-items: center;
          flex-wrap: wrap;
        }
        .mono {
          font-family: var(--font-mono);
          font-size: var(--boxel-font-size-2xs);
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
  };
}
