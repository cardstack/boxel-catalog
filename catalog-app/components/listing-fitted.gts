import { Component, CardDef } from 'https://cardstack.com/base/card-api';

import { htmlSafe } from '@ember/template';

import { type Listing } from '../listing/listing';
import { typeMetaForDisplayName } from '../listing/listing-type-meta';

import ListingHoverCard from './listing-hover-card';

export class ListingFittedTemplate extends Component<typeof Listing> {
  get listing(): Listing {
    return this.args.model as Listing;
  }

  get typeMeta() {
    return typeMetaForDisplayName(
      (this.args.model.constructor as typeof CardDef).displayName,
    );
  }

  get imageUrl(): string | undefined {
    // Screenshot only — no thumbnail fallback; the monogram cover handles the
    // no-screenshot case.
    return (this.args.model.images ?? [])
      .map((image) => image?.url)
      .find((url): url is string => Boolean(url));
  }

  get hasNoImage(): 'true' | 'false' {
    return this.imageUrl ? 'false' : 'true';
  }

  get monogram(): string {
    return (this.args.model.name?.trim()[0] ?? '?').toUpperCase();
  }

  get publisherHandle(): string {
    let name = this.args.model.publisher?.name;
    return name ? '@' + name : '';
  }

  get blurb(): string | undefined {
    // cardDescription is empty on catalog listings; the real prose is in summary.
    return this.args.model.cardDescription || this.args.model.summary;
  }

  get chipDotStyle() {
    return htmlSafe(`background: var(${this.typeMeta.colorVar}, #ff5b9c);`);
  }

  get coverStyle() {
    let v = this.typeMeta.colorVar;
    return htmlSafe(
      `background: linear-gradient(135deg, color-mix(in srgb, var(${v}, #ff5b9c) 22%, transparent), color-mix(in srgb, var(${v}, #ff5b9c) 6%, transparent)), #fbfaf5;`,
    );
  }

  get monogramStyle() {
    return htmlSafe(`color: var(${this.typeMeta.colorVar}, #ff5b9c);`);
  }

  <template>
    <div
      class='listing-card'
      data-test-listing-fitted
      data-no-image={{this.hasNoImage}}
    >
      <ListingHoverCard @listing={{this.listing}} @context={{@context}}>
        <div class='media'>
          {{#if this.imageUrl}}
            <img src={{this.imageUrl}} alt={{@model.name}} class='media-img' />
          {{else}}
            <div class='cover' style={{this.coverStyle}}>
              <span
                class='monogram'
                style={{this.monogramStyle}}
              >{{this.monogram}}</span>
            </div>
          {{/if}}

          <span class='type-chip'>
            <span class='type-dot' style={{this.chipDotStyle}}></span>
            <span class='type-label'>{{this.typeMeta.label}}</span>
          </span>

          <div class='caption'>
            <div class='caption-head'>
              <h3 class='caption-title' data-test-card-title={{@model.name}}>
                {{@model.name}}
              </h3>
              {{#if this.publisherHandle}}
                <span class='caption-author'>{{this.publisherHandle}}</span>
              {{/if}}
            </div>
            {{#if this.blurb}}
              <p class='caption-blurb'>{{this.blurb}}</p>
            {{/if}}
          </div>
        </div>
      </ListingHoverCard>
    </div>

    <style scoped>
      @layer {
        .listing-card {
          width: 100%;
          height: 100%;
          overflow: hidden;
        }
        .media {
          position: relative;
          width: 100%;
          height: 100%;
          background: #1c1c22;
          overflow: hidden;
        }
        .media-img {
          width: 100%;
          height: 100%;
          object-fit: cover;
          object-position: top center;
          display: block;
          transition: transform 240ms ease;
        }
        .listing-card:hover .media-img {
          transform: scale(1.05);
        }
        .cover {
          width: 100%;
          height: 100%;
          display: flex;
          align-items: center;
          justify-content: center;
        }
        .monogram {
          font: 600 4rem/1 var(--font-serif, 'IBM Plex Serif', serif);
        }
        .type-chip {
          position: absolute;
          top: 0.75rem;
          left: 0.75rem;
          z-index: 3;
          display: flex;
          align-items: center;
          gap: 0.375rem;
          padding: 0.3125rem 0.625rem;
          background: color-mix(in srgb, var(--card, #fff) 92%, transparent);
          backdrop-filter: blur(0.25rem);
          border-radius: 999px;
          box-shadow: 0 2px 6px rgba(0, 0, 0, 0.12);
        }
        .type-dot {
          width: 0.375rem;
          height: 0.375rem;
          border-radius: 50%;
        }
        .type-label {
          font: 600 0.59rem/1 var(--font-mono, 'IBM Plex Mono', monospace);
          letter-spacing: 0.08em;
          text-transform: uppercase;
          color: var(--foreground, #16161c);
        }
        .caption {
          position: absolute;
          left: 0;
          right: 0;
          bottom: 0;
          z-index: 2;
          padding: 2.375rem 0.9375rem 0.875rem;
          background: linear-gradient(
            to top,
            rgba(13, 13, 18, 0.94),
            rgba(13, 13, 18, 0.74) 42%,
            rgba(13, 13, 18, 0)
          );
          color: #fff;
          pointer-events: none;
        }
        .caption-head {
          display: flex;
          align-items: baseline;
          justify-content: space-between;
          gap: 0.625rem;
        }
        .caption-title {
          margin: 0;
          font: 600 1rem/1.15 var(--font-sans, 'IBM Plex Sans', sans-serif);
          color: #fff;
        }
        .caption-author {
          font: 500 0.6875rem/1 var(--font-mono, 'IBM Plex Mono', monospace);
          color: #b8b4ab;
          white-space: nowrap;
        }
        .caption-blurb {
          margin: 0.375rem 0 0;
          font: 400 0.75rem/1.4 var(--font-sans, 'IBM Plex Sans', sans-serif);
          color: #d8d5cc;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      }

      /* Degrade for small/strip/badge sizes: caption de-emphasized */
      @container fitted-card (height <= 170px) {
        .caption-blurb {
          display: none;
        }
      }
      @container fitted-card (height <= 105px) {
        .caption {
          padding: 1rem 0.625rem 0.5rem;
        }
        .caption-author {
          display: none;
        }
      }
      @container fitted-card (height <= 65px) {
        .caption {
          background: none;
          position: static;
          padding: 0.375rem 0.625rem;
          color: var(--foreground, #16161c);
        }
        .caption-title {
          color: var(--foreground, #16161c);
          -webkit-line-clamp: 1;
        }
        .type-chip {
          display: none;
        }
      }
      @media (prefers-reduced-motion: reduce) {
        .media-img {
          transition: none;
        }
      }
    </style>
  </template>
}
