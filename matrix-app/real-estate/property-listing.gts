import {
  CardDef,
  Component,
  field,
  contains,
  containsMany,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import DateTimeField from '@cardstack/base/datetime';
import BooleanField from '@cardstack/base/boolean';
import MarkdownField from '@cardstack/base/markdown';
import AmountWithCurrency from '@cardstack/base/amount-with-currency';
import AddressField from '@cardstack/base/address';
import enumField from '@cardstack/base/enum';
import MultiImageSourceField from '@cardstack/catalog/fields/multi-image-source/multi-image-source';
import { tracked } from '@glimmer/tracking';
import { concat } from '@ember/helper';
import { on } from '@ember/modifier';
import { Alert } from '@cardstack/pretui/components/alert';
import { Button } from '@cardstack/pretui/components/button';
import { Stat } from '@cardstack/pretui/components/stat';
import type { Hue } from '@cardstack/catalog/components/state-pill';

import { Employee } from '../hr/employee';
import { DotLabel, dotEnumField } from '../hr/dot-enum-field';
import { daysBetween } from '../hr/utils';
import { FitTile } from '../shared/fit-tile';
import { PublishChecklist } from './components/publish-checklist';
import { ChannelSelector } from './components/channel-selector';
import { SchedulePicker } from './components/schedule-picker';

export const PROPERTY_TYPES = [
  'house',
  'apartment',
  'condo',
  'townhouse',
  'land',
  'commercial',
];

export const PropertyTypeField = enumField(StringField, {
  options: PROPERTY_TYPES.map((value) => ({ value, label: value })),
  displayName: 'Property Type',
});

// The ladder: draft → prepared → published → under-offer → sold, with
// withdrawn/expired as exits. Values are never renamed once instances carry
// them.
export const PROPERTY_LISTING_STATUSES = [
  'draft',
  'prepared',
  'published',
  'under-offer',
  'sold',
  'withdrawn',
  'expired',
];

export const PROPERTY_LISTING_STATUS_LABELS: Record<string, string> = {
  draft: 'Draft',
  prepared: 'Prepared',
  published: 'Published',
  'under-offer': 'Under Offer',
  sold: 'Sold',
  withdrawn: 'Withdrawn',
  expired: 'Expired',
};

export const PROPERTY_LISTING_STATUS_HUES: Record<string, Hue> = {
  draft: 'slate',
  prepared: 'blue',
  published: 'green',
  'under-offer': 'amber',
  sold: 'teal',
  withdrawn: 'red',
  expired: 'red',
};

export const PropertyListingStatusField = dotEnumField(
  {
    options: PROPERTY_LISTING_STATUSES.map((value) => ({
      value,
      label: PROPERTY_LISTING_STATUS_LABELS[value],
    })),
    displayName: 'Property Listing Status',
  },
  PROPERTY_LISTING_STATUS_HUES,
);

// Whole-dollar money: listings are priced in round amounts.
export function money(amount?: number | null, code = 'USD'): string {
  if (amount == null || !Number.isFinite(amount)) {
    return '—';
  }
  try {
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: code,
      maximumFractionDigits: 0,
    }).format(amount);
  } catch {
    return amount.toLocaleString('en-US');
  }
}

const num = (n?: number | null, unit = '') =>
  n == null ? '—' : `${n.toLocaleString('en-US')}${unit}`;

const shortDate = (at?: Date | string | null) =>
  at
    ? new Date(at).toLocaleDateString('en-US', {
        month: 'short',
        day: 'numeric',
        year: 'numeric',
      })
    : '—';

// The read-only facts every format shows, derived once per render.
class ListingFacts {
  private m: PropertyListing | undefined;
  constructor(m: PropertyListing | undefined) {
    this.m = m;
  }
  get status() {
    return this.m?.status ?? 'draft';
  }
  get statusLabel() {
    return PROPERTY_LISTING_STATUS_LABELS[this.status] ?? 'Draft';
  }
  get statusHue(): Hue {
    return PROPERTY_LISTING_STATUS_HUES[this.status] ?? 'slate';
  }
  get code() {
    return this.m?.askingPrice?.currency?.code ?? 'USD';
  }
  get price() {
    return money(this.m?.askingPrice?.amount, this.code);
  }
  get perSqft() {
    return money(this.m?.pricePerSqft, this.code);
  }
  get bedBath() {
    let m = this.m;
    return [
      m?.bedrooms != null ? `${m.bedrooms} bd` : null,
      m?.bathrooms != null ? `${m.bathrooms} ba` : null,
    ]
      .filter(Boolean)
      .join(' · ');
  }
  get headline() {
    return [
      this.m?.askingPrice?.amount != null ? this.price : null,
      this.bedBath,
    ]
      .filter(Boolean)
      .join(' · ');
  }
  get area() {
    return num(this.m?.areaSqft, ' sqft');
  }
  get lot() {
    return num(this.m?.lotSizeSqft, ' sqft');
  }
  get built() {
    return this.m?.yearBuilt ? String(this.m.yearBuilt) : '—';
  }
  get dom() {
    let d = this.m?.daysOnMarket;
    return d == null ? '—' : `${d} days`;
  }
  get listed() {
    return shortDate(this.m?.publishedAt);
  }
  get place() {
    let a = this.m?.address;
    let cityLine = [
      a?.city,
      [a?.state, a?.postalCode].filter(Boolean).join(' '),
    ]
      .filter(Boolean)
      .join(', ');
    return [this.m?.neighborhood, cityLine].filter(Boolean).join(' · ');
  }
  // The chosen hero fronts every face, not only the first photo.
  get hero() {
    let urls = this.m?.photos?.resolvedUrls ?? [];
    return urls[this.m?.heroIndex ?? 0] || urls[0];
  }
  get type() {
    let t = this.m?.propertyType;
    return t ? t[0].toUpperCase() + t.slice(1) : '—';
  }
}

class PropertyListingIsolated extends Component<typeof PropertyListing> {
  @tracked publishing = false;
  @tracked publishProblem: string | undefined;
  @tracked publishPanelOpen = false;
  @tracked selectedChannels: string[] = ['mls', 'zillow', 'realtor', 'redfin'];
  @tracked scheduleIso: string | undefined;
  @tracked publishOutcome: string | undefined;
  @tracked publishScheduled = false;

  get f() {
    return new ListingFacts(this.args.model as PropertyListing);
  }

  get photoRows() {
    let m = this.args.model;
    let count = m?.photoCount ?? 0;
    let hero = m?.heroIndex ?? 0;
    return Array.from({ length: count }, (_, i) => ({
      caption: m?.photoCaptions?.[i] || `Photo ${i + 1}`,
      position: `${i + 1} of ${count}`,
      hero: i === hero,
    }));
  }

  /** The publish affordance shows only where the ladder allows it. */
  get canPublish(): boolean {
    let m = this.args.model;
    return Boolean(
      this.args.context?.commandContext &&
      m?.id &&
      (m.status === 'draft' || m.status === 'prepared' || !m.status),
    );
  }

  togglePanel = () => {
    this.publishPanelOpen = !this.publishPanelOpen;
    this.publishProblem = undefined;
    this.publishOutcome = undefined;
  };

  toggleChannel = (channel: string) => {
    if (channel === 'mls') {
      return;
    }
    this.selectedChannels = this.selectedChannels.includes(channel)
      ? this.selectedChannels.filter((c) => c !== channel)
      : [...this.selectedChannels, channel];
  };

  setSchedule = (iso: string | undefined) => {
    this.scheduleIso = iso;
  };

  publish = async () => {
    let context = this.args.context?.commandContext;
    if (!context || !this.args.model?.id) {
      return;
    }
    this.publishing = true;
    this.publishProblem = undefined;
    this.publishOutcome = undefined;
    try {
      // Literal lazy import: the command imports PropertyListing back, so
      // a static import here would be a module cycle.
      let { default: PublishListingCommand } =
        await import('./commands/publish-listing-command.gts');
      let result: any = await new PublishListingCommand(context).execute({
        listing: this.args.model,
        channels: this.selectedChannels,
        scheduledDate: this.scheduleIso
          ? new Date(this.scheduleIso)
          : undefined,
      } as any);
      this.publishOutcome = result?.message;
      this.publishScheduled = Boolean(result?.scheduled);
      if (!result?.scheduled) {
        this.publishPanelOpen = false;
      }
    } catch (e: any) {
      this.publishProblem = e?.message ?? 'Publish failed';
    } finally {
      this.publishing = false;
    }
  };

  <template>
    <article class='pl'>
      <header class='pl-head'>
        {{#if this.f.hero}}
          <img class='pl-thumb' src={{this.f.hero}} alt='' />
        {{/if}}
        <div class='pl-who'>
          <h1 class='pl-name'>{{@model.cardTitle}}</h1>
          <p class='pl-meta'>{{this.f.place}}</p>
        </div>
        <div class='pl-head-side'>
          <DotLabel @label={{this.f.statusLabel}} @hue={{this.f.statusHue}} />
          <span class='pl-meta'>{{this.f.type}}</span>
          {{#if this.canPublish}}
            <Button
              @tone='primary'
              @appearance={{if this.publishPanelOpen 'outlined' 'accent'}}
              @size='s'
              {{on 'click' this.togglePanel}}
            >{{if this.publishPanelOpen 'Close' 'Publish'}}</Button>
          {{/if}}
        </div>
      </header>

      {{#if this.publishOutcome}}
        <Alert
          class='pl-alert'
          @tone={{if this.publishScheduled 'info' 'success'}}
        >{{this.publishOutcome}}</Alert>
      {{/if}}

      {{#if this.publishPanelOpen}}
        <section class='pl-publish' aria-label='Publish listing'>
          <div class='pl-sect'>
            <h2 class='pl-h'>Ready to publish to</h2>
            <ChannelSelector
              @selected={{this.selectedChannels}}
              @onToggle={{this.toggleChannel}}
            />
            <SchedulePicker
              @value={{this.scheduleIso}}
              @onChange={{this.setSchedule}}
            />
          </div>
          <div class='pl-sect'>
            <h2 class='pl-h'>Pre-publish checklist</h2>
            <PublishChecklist @model={{@model}} />
            <Button
              @tone='primary'
              @appearance='accent'
              @size='s'
              @busy={{this.publishing}}
              {{on 'click' this.publish}}
            >{{if this.publishing 'Publishing…' 'Publish now'}}</Button>
            {{#if this.publishProblem}}
              <Alert @tone='danger'>{{this.publishProblem}}</Alert>
            {{/if}}
          </div>
        </section>
      {{/if}}

      <section class='pl-stats' aria-label='Key numbers'>
        <div class='pl-stat'><Stat
            @label='Asking'
            @value={{this.f.price}}
            @hint='{{this.f.code}} · {{@model.propertyType}}'
            @tone='success'
            @roll={{false}}
          /></div>
        <div class='pl-stat'><Stat
            @label='Days on market'
            @value={{if @model.daysOnMarket @model.daysOnMarket '—'}}
            @hint='listed {{this.f.listed}}'
            @tone='warning'
            @roll={{false}}
          /></div>
        <div class='pl-stat'><Stat
            @label='Price / sqft'
            @value={{this.f.perSqft}}
            @hint={{this.f.area}}
            @tone='info'
            @roll={{false}}
          /></div>
        <div class='pl-stat'><Stat
            @label='Bedrooms'
            @value={{if @model.bedrooms @model.bedrooms '—'}}
            @hint='{{if @model.bathrooms @model.bathrooms "—"}} baths'
            @tone='neutral'
            @roll={{false}}
          /></div>
      </section>

      <div class='pl-cols'>
        <div class='pl-main'>
          <section class='pl-sect'>
            <h2 class='pl-h'>About this property</h2>
            {{#if @model.description}}
              <div class='pl-prose'><@fields.description /></div>
            {{else}}
              <p class='pl-meta'>—</p>
            {{/if}}
          </section>
          <section class='pl-sect pl-flush'>
            <h2 class='pl-h pl-h-row'>Features
              <span class='pl-count'>{{@model.features.length}}</span></h2>
            <ul class='pl-grid'>
              {{#each @model.features as |feature|}}
                <li>{{feature}}</li>
              {{else}}
                <li class='pl-meta'>—</li>
              {{/each}}
            </ul>
          </section>
          <section class='pl-sect pl-flush'>
            <h2 class='pl-h pl-h-row'>Photos
              <span class='pl-count'>{{this.photoRows.length}}</span></h2>
            <ul class='pl-rows'>
              {{#each this.photoRows as |p|}}
                <li class='pl-row'>
                  <strong>{{p.caption}}</strong>
                  <span class='pl-row-side'>
                    <span class='pl-meta'>{{if
                        p.hero
                        (concat 'Hero photo · ' p.position)
                        p.position
                      }}</span>
                    {{#if p.hero}}<DotLabel @label='hero' @hue='blue' />{{/if}}
                  </span>
                </li>
              {{else}}
                <li class='pl-row pl-meta'>No photos yet</li>
              {{/each}}
            </ul>
          </section>
        </div>

        <aside class='pl-side'>
          <section class='pl-sect pl-flush'>
            <h2 class='pl-h'>Linked</h2>
            <dl class='pl-kv'>
              <div><dt>Listing agent</dt>
                <dd>{{#if @model.agent}}<@fields.agent
                      @format='atom'
                    />{{else}}—{{/if}}</dd></div>
            </dl>
          </section>
          <section class='pl-sect pl-flush'>
            <h2 class='pl-h'>Details</h2>
            <dl class='pl-kv pl-mono'>
              <div><dt>Price / sqft</dt><dd>{{this.f.perSqft}}</dd></div>
              <div><dt>Area</dt><dd>{{this.f.area}}</dd></div>
              <div><dt>Year built</dt><dd>{{this.f.built}}</dd></div>
              <div><dt>Lot</dt><dd>{{this.f.lot}}</dd></div>
              <div><dt>MLS#</dt><dd>{{if
                    @model.mlsNumber
                    @model.mlsNumber
                    '—'
                  }}</dd></div>
              <div><dt>Listed</dt><dd>{{this.f.listed}}</dd></div>
              <div><dt>Photos</dt><dd>{{this.photoRows.length}}</dd></div>
              <div><dt>Features</dt><dd>{{@model.features.length}}</dd></div>
            </dl>
          </section>
        </aside>
      </div>
    </article>
    <style scoped>
      .pl {
        container-type: inline-size;
        min-block-size: 100%;
        background: var(--card);
        color: var(--card-foreground);
        font-family: var(--font-sans);
        font-size: var(--boxel-font-size-xs);
      }
      .pl-head {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        border-block-end: 1px solid var(--border);
      }
      .pl-thumb {
        flex: none;
        inline-size: 2.5rem;
        block-size: 2.5rem;
        object-fit: cover;
        border-radius: var(--radius);
      }
      .pl-who {
        flex: 1;
        min-inline-size: 0;
      }
      .pl-name {
        margin: 0;
        font-family: var(--font-sans);
        font-size: var(--boxel-font-size-sm);
        font-weight: 700;
        line-height: 1.3;
      }
      .pl-meta {
        margin: 0;
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
      }
      .pl-head-side {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        flex-wrap: wrap;
        justify-content: flex-end;
      }
      .pl-alert {
        margin: var(--boxel-sp-xs) var(--boxel-sp-sm) 0;
      }
      .pl-publish {
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
        border-block-end: 1px solid var(--border);
      }
      .pl-publish > .pl-sect + .pl-sect {
        border-inline-start: 1px solid var(--border);
      }
      /* stat strip: each cell draws its right and bottom line and the frame
         clips the overhang, so a wrapped row keeps all its dividers */
      .pl-stats {
        --text-stat: 1.375rem;
        display: grid;
        grid-template-columns: repeat(4, minmax(0, 1fr));
        overflow: hidden;
        border-block-end: 1px solid var(--border);
      }
      .pl-stat {
        min-inline-size: 0;
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        box-shadow:
          1px 0 0 var(--border),
          0 1px 0 var(--border);
      }
      .pl-cols {
        display: grid;
        grid-template-columns: minmax(0, 2fr) minmax(0, 1fr);
      }
      .pl-side {
        border-inline-start: 1px solid var(--border);
      }
      .pl-sect {
        display: grid;
        gap: var(--boxel-sp-xs);
        align-content: start;
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        min-inline-size: 0;
      }
      .pl-main > .pl-sect + .pl-sect,
      .pl-side > .pl-sect + .pl-sect {
        border-block-start: 1px solid var(--border);
      }
      /* a section of ruled rows: rows run edge to edge under the title */
      .pl-flush {
        padding-inline: 0;
        padding-block-end: 0;
        gap: 0;
      }
      .pl-flush > .pl-h {
        padding: 0 var(--boxel-sp-sm) var(--boxel-sp-xs);
        border-block-end: 1px solid var(--border);
      }
      .pl-h {
        margin: 0;
        font-size: var(--boxel-font-size-xs);
        font-weight: 700;
      }
      .pl-h-row {
        display: flex;
        justify-content: space-between;
      }
      .pl-count {
        font-family: var(--font-mono);
        font-weight: 400;
        color: var(--muted-foreground);
      }
      .pl-prose {
        line-height: 1.5;
      }
      .pl-grid,
      .pl-rows {
        margin: 0;
        padding: 0;
        list-style: none;
      }
      .pl-grid {
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }
      .pl-grid > li,
      .pl-row {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: var(--boxel-sp-xs);
        min-block-size: 1.75rem;
        padding-inline: var(--boxel-sp-sm);
        border-block-end: 1px solid var(--border);
      }
      .pl-rows > .pl-row:last-child {
        border-block-end: 0;
      }
      .pl-row-side {
        display: inline-flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
      }
      .pl-kv {
        margin: 0;
      }
      .pl-kv > div {
        display: grid;
        grid-template-columns: 7rem minmax(0, 1fr);
        align-items: center;
        min-block-size: 1.75rem;
        border-block-end: 1px solid var(--border);
      }
      .pl-kv > div:last-child {
        border-block-end: 0;
      }
      .pl-kv dt {
        padding-inline: var(--boxel-sp-sm);
        color: var(--muted-foreground);
      }
      .pl-kv dd {
        margin: 0;
        padding-inline: var(--boxel-sp-xs);
        min-inline-size: 0;
      }
      .pl-mono dd {
        font-family: var(--font-mono);
        font-variant-numeric: tabular-nums;
        font-size: var(--boxel-font-size-2xs);
      }
      @container (width < 40rem) {
        .pl-cols,
        .pl-publish {
          grid-template-columns: minmax(0, 1fr);
        }
        .pl-side {
          border-inline-start: 0;
          border-block-start: 1px solid var(--border);
        }
        .pl-publish > .pl-sect + .pl-sect {
          border-inline-start: 0;
          border-block-start: 1px solid var(--border);
        }
        .pl-stats {
          grid-template-columns: repeat(2, minmax(0, 1fr));
        }
      }
    </style>
  </template>
}

// A real-estate listing: the property's facts, its asking price, its photo
// gallery, and a publish lifecycle. A property is located, measured in
// beds/baths/area, and sold once — unlike a product listing, which is shipped
// and priced per unit.
// `publishedAt` is an event fact written once by PublishListingCommand;
// the isolated view IS the property page a buyer would read.
export class PropertyListing extends CardDef {
  static displayName = 'Property Listing';
  static prefersWideFormat = true;

  @field headline = contains(StringField);
  @field address = contains(AddressField);
  @field propertyType = contains(PropertyTypeField);
  @field askingPrice = contains(AmountWithCurrency);
  @field bedrooms = contains(NumberField);
  @field bathrooms = contains(NumberField);
  @field areaSqft = contains(NumberField);
  @field yearBuilt = contains(NumberField);
  @field photos = contains(MultiImageSourceField);
  @field description = contains(MarkdownField);
  @field status = contains(PropertyListingStatusField);
  @field publishedAt = contains(DateTimeField);
  @field agent = linksTo(() => Employee);
  @field lotSizeSqft = contains(NumberField);
  @field neighborhood = contains(StringField);
  @field features = containsMany(StringField);
  @field mlsNumber = contains(StringField);
  @field hoaFee = contains(AmountWithCurrency);
  // Which photo fronts the property page and every card face. Ordered by
  // `photos.images`; captions ride in a parallel array kept in step by the
  // photo organizer, never edited on their own.
  @field heroIndex = contains(NumberField);
  @field photoCaptions = containsMany(StringField);

  @field isPublished = contains(BooleanField, {
    computeVia: function (this: PropertyListing) {
      return Boolean(this.publishedAt);
    },
  });

  // How long the listing has been live. Counted from `publishedAt` (the
  // event fact) only while the listing is on the market — a draft has no
  // clock and a sold listing's final DOM is a story for its audit trail.
  @field daysOnMarket = contains(NumberField, {
    computeVia: function (this: PropertyListing) {
      if (!this.publishedAt) {
        return null;
      }
      if (this.status !== 'published' && this.status !== 'under-offer') {
        return null;
      }
      return daysBetween(this.publishedAt, new Date());
    },
  });

  @field pricePerSqft = contains(NumberField, {
    computeVia: function (this: PropertyListing) {
      let amount = this.askingPrice?.amount;
      let area = this.areaSqft;
      if (amount == null || !area) {
        return null;
      }
      return Math.round(amount / area);
    },
  });

  // For the pre-publish checklist ("at least N photos").
  @field photoCount = contains(NumberField, {
    computeVia: function (this: PropertyListing) {
      return (this.photos?.resolvedUrls ?? []).filter(Boolean).length;
    },
  });

  @field cardTitle = contains(StringField, {
    computeVia: function (this: PropertyListing) {
      // The street address names a property on every face; the headline is
      // the fallback for a listing not yet located.
      let addr = this.address?.addressLine1?.trim();
      return addr || this.headline?.trim() || 'Untitled Property';
    },
  });

  static isolated = PropertyListingIsolated;

  static embedded = class Embedded extends Component<typeof this> {
    get f() {
      return new ListingFacts(this.args.model as PropertyListing);
    }
    <template>
      <article class='pe'>
        <header class='pe-head'>
          {{#if this.f.hero}}
            <img class='pe-thumb' src={{this.f.hero}} alt='' />
          {{/if}}
          <span class='pe-who'>
            <strong class='pe-name'>{{@model.cardTitle}}</strong>
            <span class='pe-meta'>{{this.f.place}}</span>
          </span>
          <DotLabel @label={{this.f.statusLabel}} @hue={{this.f.statusHue}} />
        </header>
        <dl class='pe-kv'>
          <div><dt>Asking</dt><dd class='pe-strong'>{{this.f.price}}</dd></div>
          <div><dt>Bed / bath</dt><dd>{{if
                this.f.bedBath
                this.f.bedBath
                '—'
              }}</dd></div>
          <div><dt>On market</dt><dd>{{this.f.dom}}</dd></div>
          <div><dt>Price / sqft</dt><dd>{{this.f.perSqft}}</dd></div>
          <div><dt>Area</dt><dd>{{this.f.area}}</dd></div>
          <div><dt>Year built</dt><dd>{{this.f.built}}</dd></div>
          <div><dt>Lot</dt><dd>{{this.f.lot}}</dd></div>
          <div><dt>MLS#</dt><dd>{{if
                @model.mlsNumber
                @model.mlsNumber
                '—'
              }}</dd></div>
          <div><dt>Listed</dt><dd>{{this.f.listed}}</dd></div>
          <div><dt>Agent</dt><dd class='pe-sans'>{{#if
                @model.agent
              }}<@fields.agent
                  @format='atom'
                  @displayContainer={{false}}
                />{{else}}—{{/if}}</dd></div>
        </dl>
      </article>
      <style scoped>
        .pe {
          background: var(--card);
          color: var(--card-foreground);
          font-family: var(--font-sans);
          font-size: var(--boxel-font-size-xs);
        }
        .pe-head {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          border-block-end: 1px solid var(--border);
        }
        .pe-thumb {
          flex: none;
          inline-size: 1.5rem;
          block-size: 1.5rem;
          object-fit: cover;
          border-radius: var(--radius);
        }
        .pe-who {
          flex: 1;
          display: grid;
          min-inline-size: 0;
        }
        .pe-name,
        .pe-meta {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .pe-name {
          font-weight: 600;
        }
        .pe-meta {
          font-size: var(--boxel-font-size-2xs);
          color: var(--muted-foreground);
        }
        .pe-kv {
          margin: 0;
        }
        .pe-kv > div {
          display: grid;
          grid-template-columns: 7.5rem minmax(0, 1fr);
          align-items: center;
          min-block-size: 1.75rem;
          border-block-end: 1px solid var(--border);
        }
        .pe-kv > div:last-child {
          border-block-end: 0;
        }
        .pe-kv dt {
          padding-inline: var(--boxel-sp-sm);
          color: var(--muted-foreground);
        }
        .pe-kv dd {
          margin: 0;
          padding-inline: var(--boxel-sp-xs);
          min-inline-size: 0;
          font-family: var(--font-mono);
          font-size: var(--boxel-font-size-2xs);
          font-variant-numeric: tabular-nums;
        }
        .pe-kv dd.pe-strong {
          font-family: var(--font-sans);
          font-size: var(--boxel-font-size-xs);
          font-weight: 700;
        }
        .pe-kv dd.pe-sans {
          font-family: var(--font-sans);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    get hero() {
      return new ListingFacts(this.args.model as PropertyListing).hero;
    }
    <template>
      <span class='pa'>
        {{#if this.hero}}<img
            class='pa-thumb'
            src={{this.hero}}
            alt=''
          />{{/if}}
        <span class='pa-name'>{{@model.cardTitle}}</span>
      </span>
      <style scoped>
        .pa {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-5xs);
          max-inline-size: 100%;
          min-inline-size: 0;
          font-size: var(--boxel-font-size-xs);
        }
        .pa-thumb {
          flex: none;
          inline-size: 1rem;
          block-size: 1rem;
          object-fit: cover;
          border-radius: var(--boxel-border-radius-xs);
        }
        .pa-name {
          min-inline-size: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  // Fitted, by priority: who → stage → asking and size → the agent.
  static fitted = class Fitted extends Component<typeof this> {
    get f() {
      return new ListingFacts(this.args.model as PropertyListing);
    }
    <template>
      <FitTile>
        <:avatar>{{#if this.f.hero}}<img
              class='pf-thumb'
              src={{this.f.hero}}
              alt=''
            />{{/if}}</:avatar>
        <:title>{{@model.cardTitle}}</:title>
        <:subtitle>{{this.f.place}}</:subtitle>
        <:status><DotLabel
            @label={{this.f.statusLabel}}
            @hue={{this.f.statusHue}}
          /></:status>
        <:fact>{{this.f.headline}}</:fact>
        <:relations>
          {{#if @model.agent}}
            <@fields.agent @format='atom' @displayContainer={{false}} />
          {{/if}}
        </:relations>
      </FitTile>
      <style scoped>
        .pf-thumb {
          display: block;
          inline-size: 2rem;
          block-size: 2rem;
          object-fit: cover;
          border-radius: var(--radius);
        }
      </style>
    </template>
  };
}
