// ═══ [EDIT TRACKING: ON] Mark all changes with ⁿ ═══
import { CardDef, FieldDef, field, contains, Component } from 'https://cardstack.com/base/card-api'; // ¹
import StringField from 'https://cardstack.com/base/string'; // ²
import EmailField from 'https://cardstack.com/base/email'; // ³
import UrlField from 'https://cardstack.com/base/url'; // ⁴
import PhoneNumberField from 'https://cardstack.com/base/phone-number'; // ⁵
import IdCardIcon from '@cardstack/boxel-icons/id-card'; // ⁶

// ⁷ Address field definition
export class AddressField extends FieldDef {
  static displayName = 'Address';

  @field street = contains(StringField);
  @field city = contains(StringField);
  @field state = contains(StringField);
  @field postalCode = contains(StringField);
  @field country = contains(StringField);

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <address class="address">
        {{#if @model.street}}<div class="street">{{@model.street}}</div>{{/if}}
        <div class="city-line">
          {{#if @model.city}}{{@model.city}}{{/if}}{{#if @model.state}}, {{@model.state}}{{/if}}{{#if @model.postalCode}} {{@model.postalCode}}{{/if}}
        </div>
        {{#if @model.country}}<div class="country">{{@model.country}}</div>{{/if}}
      </address>
      <style scoped>
        .address {
          font-style: normal;
          font-size: var(--boxel-font-size-sm, 0.875rem);
          line-height: 1.4;
          color: var(--muted-foreground, #6b7280);
        }
        .city-line:empty, .street:empty, .country:empty {
          display: none;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class="address-atom">
        {{#if @model.city}}{{@model.city}}{{#if @model.state}}, {{@model.state}}{{/if}}{{else}}No address{{/if}}
      </span>
    </template>
  };
}

// ⁸ Business Card definition
export class BusinessCard extends CardDef {
  static displayName = 'Business Card';
  static icon = IdCardIcon;

  // ⁹ Core identity fields
  @field fullName = contains(StringField);
  @field jobTitle = contains(StringField);
  @field company = contains(StringField);
  @field department = contains(StringField);

  // ¹⁰ Contact fields
  @field email = contains(EmailField);
  @field phone = contains(PhoneNumberField);
  @field mobile = contains(PhoneNumberField);
  @field website = contains(UrlField);

  // ¹¹ Location
  @field address = contains(AddressField);

  // ¹² Branding
  @field logoUrl = contains(UrlField);
  @field photoUrl = contains(UrlField);

  // ¹³ Computed title
  @field cardTitle = contains(StringField, {
    computeVia: function(this: BusinessCard) {
      return this.cardInfo?.title ?? this.fullName ?? 'Untitled Business Card';
    }
  });

  // ¹⁴ Isolated format - full detailed view
  static isolated = class Isolated extends Component<typeof this> {
    <template>
      <article class="business-card-isolated">
        <div class="card-front">
          {{#if @model.logoUrl}}
            <div class="logo-section">
              <img src={{@model.logoUrl}} alt="Company logo" class="logo" />
            </div>
          {{/if}}

          <div class="main-content">
            <div class="identity">
              {{#if @model.photoUrl}}
                <img src={{@model.photoUrl}} alt={{@model.fullName}} class="photo" />
              {{/if}}
              <div class="name-title">
                <h1 class="name">{{if @model.fullName @model.fullName "Your Name"}}</h1>
                {{#if @model.jobTitle}}
                  <p class="job-title">{{@model.jobTitle}}</p>
                {{/if}}
                {{#if @model.company}}
                  <p class="company">{{@model.company}}{{#if @model.department}} · {{@model.department}}{{/if}}</p>
                {{/if}}
              </div>
            </div>

            <div class="contact-info">
              {{#if @model.email}}
                <div class="contact-row">
                  <svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                    <rect x="2" y="4" width="20" height="16" rx="2"/>
                    <path d="m22 7-8.97 5.7a1.94 1.94 0 0 1-2.06 0L2 7"/>
                  </svg>
                  <span><@fields.email /></span>
                </div>
              {{/if}}

              {{#if @model.phone}}
                <div class="contact-row">
                  <svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                    <path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72 12.84 12.84 0 0 0 .7 2.81 2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7A2 2 0 0 1 22 16.92z"/>
                  </svg>
                  <span><@fields.phone @format="atom" /></span>
                </div>
              {{/if}}

              {{#if @model.mobile}}
                <div class="contact-row">
                  <svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                    <rect x="5" y="2" width="14" height="20" rx="2" ry="2"/>
                    <path d="M12 18h.01"/>
                  </svg>
                  <span><@fields.mobile @format="atom" /></span>
                </div>
              {{/if}}

              {{#if @model.website}}
                <div class="contact-row">
                  <svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                    <circle cx="12" cy="12" r="10"/>
                    <path d="M2 12h20M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"/>
                  </svg>
                  <span><@fields.website /></span>
                </div>
              {{/if}}

              {{#if @model.address}}
                <div class="contact-row address-row">
                  <svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                    <path d="M20 10c0 6-8 12-8 12s-8-6-8-12a8 8 0 0 1 16 0Z"/>
                    <circle cx="12" cy="10" r="3"/>
                  </svg>
                  <@fields.address @format="embedded" />
                </div>
              {{/if}}
            </div>
          </div>
        </div>
      </article>

      <style scoped>
        .business-card-isolated {
          --card-bg: var(--card, #ffffff);
          --card-fg: var(--card-foreground, #1a1a2e);
          --card-muted: var(--muted-foreground, #6b7280);
          --card-accent: var(--primary, #3b82f6);
          --card-border: var(--border, #e5e7eb);

          width: 100%;
          max-width: 480px;
          margin: 0 auto;
          padding: var(--boxel-sp-lg, 1.5rem);
        }

        .card-front {
          background: var(--card-bg);
          border: 1px solid var(--card-border);
          border-radius: var(--boxel-border-radius-lg, 12px);
          box-shadow: var(--shadow-lg, 0 10px 15px -3px rgba(0,0,0,0.1));
          padding: var(--boxel-sp-xl, 2rem);
          position: relative;
          overflow: hidden;
        }

        .card-front::before {
          content: '';
          position: absolute;
          top: 0;
          left: 0;
          right: 0;
          height: 4px;
          background: var(--card-accent);
        }

        .logo-section {
          margin-bottom: var(--boxel-sp-lg, 1.5rem);
        }

        .logo {
          max-height: 40px;
          max-width: 160px;
          object-fit: contain;
        }

        .main-content {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-lg, 1.5rem);
        }

        .identity {
          display: flex;
          align-items: flex-start;
          gap: var(--boxel-sp, 1rem);
        }

        .photo {
          width: 80px;
          height: 80px;
          border-radius: 50%;
          object-fit: cover;
          border: 3px solid var(--card-border);
          flex-shrink: 0;
        }

        .name-title {
          flex: 1;
        }

        .name {
          font-size: var(--boxel-font-size-xl, 1.5rem);
          font-weight: 700;
          color: var(--card-fg);
          margin: 0 0 var(--boxel-sp-4xs, 0.25rem) 0;
          line-height: 1.2;
        }

        .job-title {
          font-size: var(--boxel-font-size, 1rem);
          color: var(--card-accent);
          font-weight: 600;
          margin: 0 0 var(--boxel-sp-4xs, 0.25rem) 0;
        }

        .company {
          font-size: var(--boxel-font-size-sm, 0.875rem);
          color: var(--card-muted);
          margin: 0;
        }

        .contact-info {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-xs, 0.5rem);
          padding-top: var(--boxel-sp, 1rem);
          border-top: 1px solid var(--card-border);
        }

        .contact-row {
          display: flex;
          align-items: flex-start;
          gap: var(--boxel-sp-xs, 0.5rem);
          font-size: var(--boxel-font-size-sm, 0.875rem);
          color: var(--card-fg);
        }

        .contact-row .icon {
          width: 18px;
          height: 18px;
          flex-shrink: 0;
          color: var(--card-muted);
          margin-top: 2px;
        }

        .address-row {
          align-items: flex-start;
        }
      </style>
    </template>
  };

  // ¹⁵ Embedded format - compact for lists
  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class="business-card-embedded">
        {{#if @model.photoUrl}}
          <img src={{@model.photoUrl}} alt={{@model.fullName}} class="photo" />
        {{else}}
          <div class="photo-placeholder">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
              <circle cx="12" cy="8" r="4"/>
              <path d="M20 21a8 8 0 1 0-16 0"/>
            </svg>
          </div>
        {{/if}}

        <div class="info">
          <h3 class="name">{{if @model.fullName @model.fullName "Name"}}</h3>
          {{#if @model.jobTitle}}
            <p class="title">{{@model.jobTitle}}</p>
          {{/if}}
          {{#if @model.company}}
            <p class="company">{{@model.company}}</p>
          {{/if}}
          {{#if @model.email}}
            <p class="email">{{@model.email}}</p>
          {{/if}}
        </div>
      </div>

      <style scoped>
        .business-card-embedded {
          --card-fg: var(--card-foreground, #1a1a2e);
          --card-muted: var(--muted-foreground, #6b7280);
          --card-accent: var(--primary, #3b82f6);

          display: flex;
          align-items: center;
          gap: var(--boxel-sp, 1rem);
          padding: var(--boxel-sp-sm, 0.75rem);
        }

        .photo, .photo-placeholder {
          width: 56px;
          height: 56px;
          border-radius: 50%;
          flex-shrink: 0;
          object-fit: cover;
        }

        .photo-placeholder {
          background: var(--muted, #f3f4f6);
          display: flex;
          align-items: center;
          justify-content: center;
        }

        .photo-placeholder svg {
          width: 28px;
          height: 28px;
          color: var(--card-muted);
        }

        .info {
          flex: 1;
          min-width: 0;
        }

        .name {
          font-size: var(--boxel-font-size, 1rem);
          font-weight: 600;
          color: var(--card-fg);
          margin: 0 0 var(--boxel-sp-5xs, 0.125rem) 0;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }

        .title {
          font-size: var(--boxel-font-size-sm, 0.875rem);
          color: var(--card-accent);
          font-weight: 500;
          margin: 0;
        }

        .company, .email {
          font-size: var(--boxel-font-size-xs, 0.75rem);
          color: var(--card-muted);
          margin: 0;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
      </style>
    </template>
  };

  // ¹⁶ Fitted format - adaptive grid/gallery display
  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <div class="fitted-container">
        <!-- Badge: tiny display -->
        <div class="badge">
          {{#if @model.photoUrl}}
            <img src={{@model.photoUrl}} alt="" class="badge-photo" />
          {{else}}
            <div class="badge-initials">
              {{this.initials}}
            </div>
          {{/if}}
        </div>

        <!-- Strip: horizontal compact -->
        <div class="strip">
          {{#if @model.photoUrl}}
            <img src={{@model.photoUrl}} alt="" class="strip-photo" />
          {{else}}
            <div class="strip-initials">{{this.initials}}</div>
          {{/if}}
          <div class="strip-info">
            <span class="strip-name">{{if @model.fullName @model.fullName "Name"}}</span>
            <span class="strip-title">{{if @model.jobTitle @model.jobTitle "Title"}}</span>
          </div>
        </div>

        <!-- Tile: medium grid cell -->
        <div class="tile">
          <div class="tile-header">
            {{#if @model.photoUrl}}
              <img src={{@model.photoUrl}} alt="" class="tile-photo" />
            {{else}}
              <div class="tile-initials">{{this.initials}}</div>
            {{/if}}
          </div>
          <div class="tile-body">
            <h4 class="tile-name">{{if @model.fullName @model.fullName "Name"}}</h4>
            {{#if @model.jobTitle}}<p class="tile-title">{{@model.jobTitle}}</p>{{/if}}
            {{#if @model.company}}<p class="tile-company">{{@model.company}}</p>{{/if}}
          </div>
        </div>

        <!-- Card: larger display -->
        <div class="card">
          <div class="card-accent"></div>
          <div class="card-content">
            <div class="card-identity">
              {{#if @model.photoUrl}}
                <img src={{@model.photoUrl}} alt="" class="card-photo" />
              {{else}}
                <div class="card-initials">{{this.initials}}</div>
              {{/if}}
              <div class="card-name-block">
                <h3 class="card-name">{{if @model.fullName @model.fullName "Name"}}</h3>
                {{#if @model.jobTitle}}<p class="card-title">{{@model.jobTitle}}</p>{{/if}}
                {{#if @model.company}}<p class="card-company">{{@model.company}}</p>{{/if}}
              </div>
            </div>
            <div class="card-contact">
              {{#if @model.email}}<span class="card-email">{{@model.email}}</span>{{/if}}
              {{#if @model.phone}}<span class="card-phone"><@fields.phone @format="atom" /></span>{{/if}}
            </div>
          </div>
        </div>
      </div>

      <style scoped>
        .fitted-container {
          --card-fg: var(--card-foreground, #1a1a2e);
          --card-muted: var(--muted-foreground, #6b7280);
          --card-accent: var(--primary, #3b82f6);
          --card-bg: var(--card, #ffffff);

          container-type: size;
          width: 100%;
          height: 100%;
          overflow: hidden;
        }

        /* Hide all by default */
        .badge, .strip, .tile, .card {
          display: none;
          width: 100%;
          height: 100%;
        }

        /* Badge: ≤150px width, <170px height */
        @container (max-width: 150px) and (max-height: 169px) {
          .badge {
            display: flex;
            align-items: center;
            justify-content: center;
            padding: var(--boxel-sp-4xs, 0.25rem);
          }

          .badge-photo, .badge-initials {
            width: min(48px, 80%);
            height: min(48px, 80%);
            border-radius: 50%;
            object-fit: cover;
          }

          .badge-initials {
            background: var(--card-accent);
            color: white;
            display: flex;
            align-items: center;
            justify-content: center;
            font-weight: 700;
            font-size: clamp(0.75rem, 4cqw, 1.25rem);
          }
        }

        /* Strip: >150px width, <170px height */
        @container (min-width: 151px) and (max-height: 169px) {
          .strip {
            display: flex;
            align-items: center;
            gap: var(--boxel-sp-xs, 0.5rem);
            padding: var(--boxel-sp-xs, 0.5rem);
          }

          .strip-photo, .strip-initials {
            width: 40px;
            height: 40px;
            border-radius: 50%;
            flex-shrink: 0;
            object-fit: cover;
          }

          .strip-initials {
            background: var(--card-accent);
            color: white;
            display: flex;
            align-items: center;
            justify-content: center;
            font-weight: 600;
            font-size: 0.875rem;
          }

          .strip-info {
            flex: 1;
            min-width: 0;
            display: flex;
            flex-direction: column;
            gap: 2px;
          }

          .strip-name {
            font-weight: 600;
            font-size: var(--boxel-font-size-sm, 0.875rem);
            color: var(--card-fg);
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
          }

          .strip-title {
            font-size: var(--boxel-font-size-xs, 0.75rem);
            color: var(--card-muted);
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
          }
        }

        /* Tile: <400px width, ≥170px height */
        @container (max-width: 399px) and (min-height: 170px) {
          .tile {
            display: flex;
            flex-direction: column;
            padding: var(--boxel-sp-sm, 0.75rem);
          }

          .tile-header {
            display: flex;
            justify-content: center;
            margin-bottom: var(--boxel-sp-xs, 0.5rem);
          }

          .tile-photo, .tile-initials {
            width: 64px;
            height: 64px;
            border-radius: 50%;
            object-fit: cover;
          }

          .tile-initials {
            background: var(--card-accent);
            color: white;
            display: flex;
            align-items: center;
            justify-content: center;
            font-weight: 700;
            font-size: 1.25rem;
          }

          .tile-body {
            text-align: center;
            flex: 1;
          }

          .tile-name {
            font-size: var(--boxel-font-size, 1rem);
            font-weight: 600;
            color: var(--card-fg);
            margin: 0 0 var(--boxel-sp-5xs, 0.125rem) 0;
          }

          .tile-title {
            font-size: var(--boxel-font-size-sm, 0.875rem);
            color: var(--card-accent);
            margin: 0;
          }

          .tile-company {
            font-size: var(--boxel-font-size-xs, 0.75rem);
            color: var(--card-muted);
            margin: var(--boxel-sp-5xs, 0.125rem) 0 0 0;
          }
        }

        /* Card: ≥400px width, ≥170px height */
        @container (min-width: 400px) and (min-height: 170px) {
          .card {
            display: flex;
            flex-direction: column;
            position: relative;
          }

          .card-accent {
            height: 4px;
            background: var(--card-accent);
          }

          .card-content {
            flex: 1;
            padding: var(--boxel-sp, 1rem);
            display: flex;
            flex-direction: column;
            justify-content: space-between;
          }

          .card-identity {
            display: flex;
            align-items: flex-start;
            gap: var(--boxel-sp, 1rem);
          }

          .card-photo, .card-initials {
            width: 60px;
            height: 60px;
            border-radius: 50%;
            object-fit: cover;
            flex-shrink: 0;
          }

          .card-initials {
            background: var(--card-accent);
            color: white;
            display: flex;
            align-items: center;
            justify-content: center;
            font-weight: 700;
            font-size: 1.25rem;
          }

          .card-name-block {
            flex: 1;
          }

          .card-name {
            font-size: var(--boxel-font-size-lg, 1.125rem);
            font-weight: 600;
            color: var(--card-fg);
            margin: 0;
          }

          .card-title {
            font-size: var(--boxel-font-size-sm, 0.875rem);
            color: var(--card-accent);
            margin: var(--boxel-sp-5xs, 0.125rem) 0 0 0;
          }

          .card-company {
            font-size: var(--boxel-font-size-xs, 0.75rem);
            color: var(--card-muted);
            margin: var(--boxel-sp-5xs, 0.125rem) 0 0 0;
          }

          .card-contact {
            display: flex;
            gap: var(--boxel-sp, 1rem);
            font-size: var(--boxel-font-size-xs, 0.75rem);
            color: var(--card-muted);
            padding-top: var(--boxel-sp-xs, 0.5rem);
            border-top: 1px solid var(--border, #e5e7eb);
          }
        }
      </style>
    </template>

    get initials() {
      const name = this.args.model?.fullName ?? '';
      const parts = name.trim().split(/\s+/);
      if (parts.length >= 2) {
        return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
      }
      return name.slice(0, 2).toUpperCase() || '??';
    }
  };
}
