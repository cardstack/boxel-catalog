// ═══ [EDIT TRACKING: ON] Mark all changes with ⁿ ═══
import { CardDef, FieldDef, field, contains, containsMany, Component } from 'https://cardstack.com/base/card-api'; // ¹
import StringField from 'https://cardstack.com/base/string'; // ²
import NumberField from 'https://cardstack.com/base/number'; // ³
import MarkdownField from 'https://cardstack.com/base/markdown'; // ⁴
import BooleanField from 'https://cardstack.com/base/boolean'; // ⁵
import HomeIcon from '@cardstack/boxel-icons/home'; // ⁶
import { concat } from '@ember/helper'; // ⁷ Added missing concat import

// ⁸ Amenity field
export class AmenityField extends FieldDef {
  static displayName = 'Amenity';
  @field name = contains(StringField);

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <span class='amenity-tag'>{{if @model.name @model.name 'Amenity'}}</span>
      <style scoped>
        .amenity-tag {
          display: inline-block;
          padding: 0.25rem 0.625rem;
          background-color: var(--accent);
          color: var(--accent-foreground);
          border-radius: var(--radius);
          font-size: 0.75rem;
          font-weight: 500;
        }
      </style>
    </template>
  };
}

// ⁹ Main Airbnb listing card
export class Airbnb extends CardDef {
  static displayName = 'Airbnb';
  static icon = HomeIcon;

  @field title = contains(StringField); // ¹⁰
  @field location = contains(StringField); // ¹¹
  @field pricePerNight = contains(NumberField); // ¹²
  @field maxGuests = contains(NumberField); // ¹³
  @field bedrooms = contains(NumberField); // ¹⁴
  @field bathrooms = contains(NumberField); // ¹⁵
  @field description = contains(MarkdownField); // ¹⁶
  @field amenities = containsMany(AmenityField); // ¹⁷
  @field rating = contains(NumberField); // ¹⁸
  @field isAvailable = contains(BooleanField); // ¹⁹
  @field imageUrl = contains(StringField); // ²⁰

  // ²¹ Isolated format - full detail view
  static isolated = class Isolated extends Component<typeof Airbnb> {
    <template>
      <article class='listing'>
        {{#if @model.imageUrl}}
          <div class='listing-image'>
            <img src={{@model.imageUrl}} alt={{if @model.title @model.title 'Listing image'}} />
          </div>
        {{/if}}

        <div class='listing-body'>
          <div class='listing-header'>
            <div class='header-top'>
              <h1 class='listing-title'>{{if @model.title @model.title 'Untitled Listing'}}</h1>
              <span class='availability {{if @model.isAvailable "available" "unavailable"}}'>
                {{if @model.isAvailable 'Available' 'Unavailable'}}
              </span>
            </div>
            <p class='listing-location'>
              <svg width='14' height='14' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2'><path d='M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z'/><circle cx='12' cy='10' r='3'/></svg>
              {{if @model.location @model.location 'Location not set'}}
            </p>
            {{#if @model.rating}}
              <div class='listing-rating'>
                <svg width='14' height='14' viewBox='0 0 24 24' fill='currentColor'><polygon points='12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2'/></svg>
                {{@model.rating}}
              </div>
            {{/if}}
          </div>

          <div class='listing-stats'>
            <div class='stat'>
              <span class='stat-value'>{{if @model.maxGuests @model.maxGuests '–'}}</span>
              <span class='stat-label'>Guests</span>
            </div>
            <div class='stat'>
              <span class='stat-value'>{{if @model.bedrooms @model.bedrooms '–'}}</span>
              <span class='stat-label'>Bedrooms</span>
            </div>
            <div class='stat'>
              <span class='stat-value'>{{if @model.bathrooms @model.bathrooms '–'}}</span>
              <span class='stat-label'>Bathrooms</span>
            </div>
            <div class='stat'>
              <span class='stat-value'>${{if @model.pricePerNight @model.pricePerNight '–'}}</span>
              <span class='stat-label'>/ night</span>
            </div>
          </div>

          {{#if @model.description}}
            <section class='listing-description'>
              <h2>About this place</h2>
              <@fields.description />
            </section>
          {{/if}}

          {{#if @model.amenities.length}}
            <section class='listing-amenities'>
              <h2>Amenities</h2>
              <div class='amenities-list'>
                <@fields.amenities @format='embedded' />
              </div>
            </section>
          {{/if}}
        </div>
      </article>

      <style scoped>
        /* ²² Isolated styles */
        .listing {
          height: 100%;
          overflow-y: auto;
          background-color: var(--background);
          color: var(--foreground);
          font-family: var(--font-sans);
        }
        .listing-image img {
          width: 100%;
          height: 280px;
          object-fit: cover;
        }
        .listing-body {
          padding: var(--boxel-sp-xl);
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-lg);
        }
        .header-top {
          display: flex;
          align-items: flex-start;
          justify-content: space-between;
          gap: var(--boxel-sp);
        }
        .listing-title {
          font-size: var(--boxel-font-size-xl);
          font-weight: 700;
          margin: 0;
        }
        .availability {
          padding: 0.25rem 0.75rem;
          border-radius: var(--radius);
          font-size: 0.75rem;
          font-weight: 600;
          white-space: nowrap;
        }
        .available { background: #dcfce7; color: #166534; }
        .unavailable { background: #fee2e2; color: #991b1b; }
        .listing-location {
          display: flex;
          align-items: center;
          gap: 0.25rem;
          color: var(--muted-foreground);
          font-size: var(--boxel-font-size-sm);
          margin: 0.5rem 0 0;
        }
        .listing-rating {
          display: flex;
          align-items: center;
          gap: 0.25rem;
          color: #f59e0b;
          font-size: var(--boxel-font-size-sm);
          font-weight: 600;
          margin-top: 0.25rem;
        }
        .listing-stats {
          display: grid;
          grid-template-columns: repeat(4, 1fr);
          gap: var(--boxel-sp-sm);
          padding: var(--boxel-sp) 0;
          border-top: 1px solid var(--border);
          border-bottom: 1px solid var(--border);
        }
        .stat {
          display: flex;
          flex-direction: column;
          align-items: center;
          gap: 0.25rem;
        }
        .stat-value {
          font-size: var(--boxel-font-size-lg);
          font-weight: 700;
        }
        .stat-label {
          font-size: 0.7rem;
          color: var(--muted-foreground);
          text-transform: uppercase;
          letter-spacing: 0.05em;
        }
        .listing-description h2,
        .listing-amenities h2 {
          font-size: var(--boxel-font-size);
          font-weight: 600;
          margin: 0 0 var(--boxel-sp-sm);
        }
        .amenities-list > .containsMany-field {
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-xs);
        }
      </style>
    </template>
  };

  // ²³ Embedded format
  static embedded = class Embedded extends Component<typeof Airbnb> {
    <template>
      <div class='embedded-listing'>
        {{#if @model.imageUrl}}
          <img src={{@model.imageUrl}} alt='listing' class='embed-img' />
        {{/if}}
        <div class='embed-info'>
          <p class='embed-title'>{{if @model.title @model.title 'Untitled Listing'}}</p>
          <p class='embed-loc'>{{if @model.location @model.location 'No location'}}</p>
          {{#if @model.pricePerNight}}
            <p class='embed-price'>{{concat '$' @model.pricePerNight ' / night'}}</p>
          {{else}}
            <p class='embed-price'>Price TBD</p>
          {{/if}}
        </div>
      </div>
      <style scoped>
        .embedded-listing {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-sm);
          padding: var(--boxel-sp-sm);
          background: var(--card);
          color: var(--card-foreground);
          border-radius: var(--radius);
          font-family: var(--font-sans);
        }
        .embed-img {
          width: 60px;
          height: 60px;
          object-fit: cover;
          border-radius: var(--boxel-border-radius-sm);
          flex-shrink: 0;
        }
        .embed-info {
          display: flex;
          flex-direction: column;
          gap: 0.2rem;
          min-width: 0;
        }
        .embed-title {
          font-weight: 600;
          font-size: var(--boxel-font-size-sm);
          margin: 0;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .embed-loc, .embed-price {
          font-size: 0.75rem;
          color: var(--muted-foreground);
          margin: 0;
        }
        .embed-price { color: var(--foreground); font-weight: 500; }
      </style>
    </template>
  };

  // ²⁴ Fitted format
  static fitted = class Fitted extends Component<typeof Airbnb> {
    <template>
      <div class='fitted-listing'>
        <div class='badge'>
          <span class='badge-title'>{{if @model.title @model.title 'Listing'}}</span>
          {{#if @model.pricePerNight}}<span class='badge-price'>${{@model.pricePerNight}}</span>{{/if}}
        </div>
        <div class='strip'>
          {{#if @model.imageUrl}}<img src={{@model.imageUrl}} alt='listing' class='strip-img' />{{/if}}
          <div class='strip-info'>
            <span class='strip-title'>{{if @model.title @model.title 'Untitled'}}</span>
            <span class='strip-loc'>{{if @model.location @model.location ''}}</span>
          </div>
          {{#if @model.pricePerNight}}<span class='strip-price'>${{@model.pricePerNight}}/night</span>{{/if}}
        </div>
        <div class='tile'>
          {{#if @model.imageUrl}}<img src={{@model.imageUrl}} alt='listing' class='tile-img' />{{/if}}
          <div class='tile-info'>
            <p class='tile-title'>{{if @model.title @model.title 'Untitled Listing'}}</p>
            <p class='tile-loc'>{{if @model.location @model.location 'No location'}}</p>
            {{#if @model.pricePerNight}}<p class='tile-price'>${{@model.pricePerNight}} / night</p>{{/if}}
            {{#if @model.rating}}<p class='tile-rating'>★ {{@model.rating}}</p>{{/if}}
          </div>
        </div>
        <div class='card'>
          {{#if @model.imageUrl}}<img src={{@model.imageUrl}} alt='listing' class='card-img' />{{/if}}
          <div class='card-info'>
            <div class='card-header'>
              <p class='card-title'>{{if @model.title @model.title 'Untitled Listing'}}</p>
              {{#if @model.isAvailable}}<span class='card-badge'>Available</span>{{/if}}
            </div>
            <p class='card-loc'>{{if @model.location @model.location 'No location'}}</p>
            <div class='card-meta'>
              {{#if @model.pricePerNight}}<span>${{@model.pricePerNight}}/night</span>{{/if}}
              {{#if @model.maxGuests}}<span>· {{@model.maxGuests}} guests</span>{{/if}}
              {{#if @model.rating}}<span>· ★ {{@model.rating}}</span>{{/if}}
            </div>
          </div>
        </div>
      </div>
      <style scoped>
        /* ²⁵ Fitted styles - four sub-formats */
        .fitted-listing { width: 100%; height: 100%; font-family: var(--font-sans); }

        /* Hide all by default */
        .badge, .strip, .tile, .card { display: none; width: 100%; height: 100%; }

        /* Badge ≤150w, <170h */
        @container fitted-card (max-width: 150px) and (max-height: 169px) {
          .badge {
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            gap: 0.2rem;
            padding: 0.5rem;
            background: var(--card);
            color: var(--card-foreground);
            text-align: center;
          }
          .badge-title { font-size: 0.65rem; font-weight: 600; line-height: 1.2; }
          .badge-price { font-size: 0.6rem; color: var(--muted-foreground); }
        }

        /* Strip >150w, <170h */
        @container fitted-card (min-width: 151px) and (max-height: 169px) {
          .strip {
            display: flex;
            align-items: center;
            gap: 0.5rem;
            padding: 0.5rem;
            background: var(--card);
            color: var(--card-foreground);
            overflow: hidden;
          }
          .strip-img { width: 48px; height: 48px; object-fit: cover; border-radius: 4px; flex-shrink: 0; }
          .strip-info { flex: 1; min-width: 0; }
          .strip-title { display: block; font-size: 0.8rem; font-weight: 600; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
          .strip-loc { display: block; font-size: 0.7rem; color: var(--muted-foreground); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
          .strip-price { font-size: 0.75rem; font-weight: 600; white-space: nowrap; color: var(--foreground); }
        }

        /* Tile <400w, ≥170h */
        @container fitted-card (max-width: 399px) and (min-height: 170px) {
          .tile { display: flex; flex-direction: column; background: var(--card); color: var(--card-foreground); overflow: hidden; }
          .tile-img { width: 100%; flex: 1; object-fit: cover; min-height: 0; }
          .tile-info { padding: 0.5rem; }
          .tile-title { font-size: 0.8rem; font-weight: 700; margin: 0 0 0.15rem; }
          .tile-loc { font-size: 0.7rem; color: var(--muted-foreground); margin: 0 0 0.15rem; }
          .tile-price { font-size: 0.75rem; font-weight: 600; margin: 0; }
          .tile-rating { font-size: 0.7rem; color: #f59e0b; margin: 0.15rem 0 0; }
          .tile-title, .tile-loc { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
        }

        /* Card ≥400w, ≥170h */
        @container fitted-card (min-width: 400px) and (min-height: 170px) {
          .card { display: flex; background: var(--card); color: var(--card-foreground); overflow: hidden; }
          .card-img { width: 200px; object-fit: cover; flex-shrink: 0; }
          .card-info { padding: var(--boxel-sp); display: flex; flex-direction: column; gap: 0.4rem; min-width: 0; }
          .card-header { display: flex; align-items: flex-start; justify-content: space-between; gap: 0.5rem; }
          .card-title { font-size: 0.9rem; font-weight: 700; margin: 0; }
          .card-badge { padding: 0.15rem 0.5rem; background: #dcfce7; color: #166534; border-radius: 9999px; font-size: 0.65rem; font-weight: 600; white-space: nowrap; }
          .card-loc { font-size: 0.75rem; color: var(--muted-foreground); margin: 0; }
          .card-meta { display: flex; gap: 0.4rem; flex-wrap: wrap; font-size: 0.75rem; color: var(--foreground); }
        }
      </style>
    </template>
  };
}
