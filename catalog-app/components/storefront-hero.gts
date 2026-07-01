import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { htmlSafe } from '@ember/template';
import { CardDef, CardContext } from 'https://cardstack.com/base/card-api';

import { type Listing } from '../listing/listing';
import { typeMetaForDisplayName } from '../listing/listing-type-meta';
import ListingHoverCard from './listing-hover-card';

interface SlideSignature {
  Args: {
    listing: Listing;
    index: number;
    context?: CardContext;
  };
  Element: HTMLElement;
}

// One spotlight in the hero carousel. `@listing` comes off the Catalog's own
// `featured` field, which is two hops away from the card actually being
// rendered — that link resolves the Listing itself but not ITS OWN
// relationships (e.g. `images`), so we re-resolve it by id through the
// store (`getCard`, the same path a search result or direct navigation
// uses) to get a fully hydrated instance to read the screenshot from.
class HeroSpotlightSlide extends GlimmerComponent<SlideSignature> {
  liveListingResource = this.args.context?.getCard(
    this,
    () => this.args.listing.id,
  );

  get listing(): Listing {
    return (this.liveListingResource?.card as Listing) ?? this.args.listing;
  }

  get imageUrl(): string | undefined {
    // Screenshot only — no thumbnail fallback; the monogram cover handles the
    // no-screenshot case.
    return (this.listing.images ?? [])
      .map((image) => image?.url)
      .find((url): url is string => Boolean(url));
  }

  get monogram(): string {
    return (this.listing.name?.trim()[0] ?? '?').toUpperCase();
  }

  get typeMeta() {
    return typeMetaForDisplayName(
      (this.listing.constructor as typeof CardDef).displayName,
    );
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
    <div class='slide' data-test-hero-slide={{@index}} ...attributes>
      <ListingHoverCard @listing={{this.listing}} @context={{@context}}>
        {{#if this.imageUrl}}
          <img
            src={{this.imageUrl}}
            alt={{this.listing.name}}
            class='preview-img'
          />
        {{else}}
          <div class='cover' style={{this.coverStyle}}>
            <span
              class='monogram'
              style={{this.monogramStyle}}
            >{{this.monogram}}</span>
          </div>
        {{/if}}
      </ListingHoverCard>
    </div>

    <style scoped>
      .slide {
        display: block;
        height: 100%;
      }
      .preview-img {
        width: 100%;
        height: 100%;
        object-fit: cover;
        object-position: top center;
        display: block;
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
    </style>
  </template>
}

interface HeroSignature {
  Args: {
    featured?: CardDef[];
    onBrowse: () => void;
    onHowItWorks: () => void;
    context?: CardContext;
  };
  Element: HTMLElement;
}

export default class StorefrontHero extends GlimmerComponent<HeroSignature> {
  get spotlights(): Listing[] {
    // linksToMany can hold not-yet-loaded placeholders during indexing/load;
    // drop them so a slide never renders against an undefined listing.
    return ((this.args.featured ?? []) as Listing[])
      .filter((listing) => Boolean(listing))
      .slice(0, 3);
  }

  get hasSpotlights() {
    return this.spotlights.length > 0;
  }

  // Only auto-rotate when there is more than one curated spotlight.
  get isRotating() {
    return this.spotlights.length > 1;
  }

  <template>
    <section class='hero' data-test-storefront-hero>
      <div class='grid-paper' aria-hidden='true'></div>
      <div class='glow hpa' aria-hidden='true'></div>

      <div class='hero-inner'>
        <div class='copy'>
          <h1 class='headline'>Remix<br /><span
              class='headline-accent'
            >everything.</span></h1>
          <p class='lead'>Don't build it twice.</p>
          <p class='sub'>Browse apps and cards the community has already built
            and shipped. Fork any of them into your realm — full source, ready
            to run.</p>

          <div class='chips'>
            <span class='chip chip-live'><span class='chip-dot'></span>Free to
              remix</span>
            <span class='chip'>Full source</span>
            <span class='chip'>Public realm</span>
          </div>

          <div class='ctas'>
            <button
              type='button'
              class='cta-primary'
              data-test-hero-browse
              {{on 'click' @onBrowse}}
            >Browse the catalog</button>
            <button
              type='button'
              class='cta-link'
              {{on 'click' @onHowItWorks}}
            >See how remixing works →</button>
          </div>
        </div>

        {{#if this.hasSpotlights}}
          <div class='stage {{if this.isRotating "rotating"}}'>
            {{#each this.spotlights as |listing index|}}
              <HeroSpotlightSlide
                @listing={{listing}}
                @index={{index}}
                @context={{@context}}
              />
            {{/each}}
          </div>
        {{/if}}
      </div>
    </section>

    <style scoped>
      @keyframes hglow {
        0% {
          opacity: 0.85;
        }
        35% {
          opacity: 0.6;
        }
        70% {
          opacity: 0.6;
        }
        100% {
          opacity: 0.85;
        }
      }
      @keyframes hslide {
        0% {
          opacity: 0;
          transform: scale(1.04);
          pointer-events: none;
        }
        4% {
          opacity: 1;
          transform: scale(1);
          pointer-events: auto;
        }
        29% {
          opacity: 1;
          transform: scale(1);
          pointer-events: auto;
        }
        33% {
          opacity: 0;
          transform: scale(1.04);
          pointer-events: none;
        }
        100% {
          opacity: 0;
          transform: scale(1.04);
          pointer-events: none;
        }
      }
      .hero {
        position: relative;
        overflow: hidden;
        background: color-mix(in srgb, var(--background, #f0ede4) 92%, #fff);
        border-bottom: 1px solid var(--border, #ddd8cb);
      }
      .grid-paper {
        position: absolute;
        inset: 0;
        background-image:
          linear-gradient(#15151b0a 1px, transparent 1px),
          linear-gradient(90deg, #15151b0a 1px, transparent 1px);
        background-size: 1.875rem 1.875rem;
        pointer-events: none;
      }
      .glow {
        position: absolute;
        top: -10rem;
        right: -7.5rem;
        width: 47.5rem;
        height: 47.5rem;
        border-radius: 50%;
        filter: blur(2.5rem);
        pointer-events: none;
        background: radial-gradient(
          circle,
          color-mix(in srgb, var(--primary, #11cf8a) 30%, transparent) 0%,
          transparent 70%
        );
        animation: hglow 12s infinite;
      }
      .hero-inner {
        max-width: 80rem;
        margin: 0 auto;
        padding: 5.25rem 2rem 5.75rem;
        position: relative;
        display: grid;
        grid-template-columns: 1.04fr 1fr;
        gap: 3.5rem;
        align-items: center;
      }
      .headline {
        margin: 0;
        font: 700 4.875rem/0.92 var(--font-sans, 'IBM Plex Sans', sans-serif);
        letter-spacing: -0.045em;
        color: var(--foreground, #15151b);
      }
      .headline-accent {
        /* Text reads better a shade dimmer than the true, neon --primary
           brand color (#00ffba) — that hue is reserved for button fills. */
        color: #11cf8a;
      }
      .lead {
        margin: 1.625rem 0 0;
        font: 600 1.375rem/1.25 var(--font-sans, 'IBM Plex Sans', sans-serif);
        letter-spacing: -0.01em;
        color: var(--foreground, #15151b);
      }
      .sub {
        margin: 0.75rem 0 0;
        max-width: 27.5rem;
        font: 400 0.97rem/1.6 var(--font-sans, 'IBM Plex Sans', sans-serif);
        color: var(--muted-foreground, #5f5b52);
      }
      .chips {
        display: inline-flex;
        align-items: center;
        margin-top: 1.625rem;
        border: 1px solid var(--border, #d3cdbf);
        border-radius: 0.625rem;
        overflow: hidden;
        background: var(--card, #fff);
      }
      .chip {
        padding: 0.625rem 0.875rem;
        font: 600 0.6875rem/1 var(--font-mono, 'IBM Plex Mono', monospace);
        letter-spacing: 0.06em;
        text-transform: uppercase;
        color: var(--muted-foreground, #6f6c64);
        border-left: 1px solid var(--border, #e7e3d8);
      }
      .chip-live {
        display: inline-flex;
        align-items: center;
        gap: 0.5rem;
        color: var(--foreground, #15151b);
        border-left: none;
      }
      .chip-dot {
        width: 0.4375rem;
        height: 0.4375rem;
        border-radius: 50%;
        background: #11cf8a;
      }
      .ctas {
        display: flex;
        align-items: center;
        gap: 1.125rem;
        margin-top: 1.875rem;
      }
      .cta-primary {
        padding: 0.9375rem 1.625rem;
        background: var(--primary, #00ffba);
        color: var(--primary-foreground, #04231a);
        border: none;
        border-radius: 0.75rem;
        cursor: pointer;
        font: 700 0.875rem/1 var(--font-sans, 'IBM Plex Sans', sans-serif);
      }
      .cta-primary:hover {
        filter: brightness(0.94);
        transform: translateY(-1px);
      }
      .cta-link {
        border: none;
        background: transparent;
        cursor: pointer;
        font: 600 0.875rem/1 var(--font-sans, 'IBM Plex Sans', sans-serif);
        color: var(--foreground, #15151b);
      }
      .cta-link:hover {
        color: #11cf8a;
      }

      /* Spotlight carousel: a fixed-ratio stage crossfading between 1-3
         screenshots. Fixed-ratio is safe here — unlike a live embedded card,
         a screenshot always fills the box the same way via object-fit. */
      .stage {
        position: relative;
        aspect-ratio: 4 / 3;
        border-radius: 1.125rem;
        overflow: hidden;
        box-shadow: var(--shadow-xl, 0 30px 70px -24px rgba(0, 0, 0, 0.4));
      }
      .stage.rotating .slide {
        position: absolute;
        inset: 0;
        opacity: 0;
        animation: hslide 12s infinite;
      }
      .stage.rotating .slide:first-child {
        position: relative;
      }
      .stage.rotating .slide:nth-child(1) {
        animation-delay: 0s;
      }
      .stage.rotating .slide:nth-child(2) {
        animation-delay: -4s;
      }
      .stage.rotating .slide:nth-child(3) {
        animation-delay: -8s;
      }
      .stage.rotating:hover .slide {
        animation-play-state: paused;
      }

      @media (prefers-reduced-motion: reduce) {
        .glow,
        .stage.rotating .slide {
          animation: none;
        }
        .stage.rotating .slide {
          position: relative;
          opacity: 1;
        }
      }

      @container (max-width: 56rem) {
        .hero-inner {
          grid-template-columns: 1fr;
          padding: 3rem 1.5rem;
        }
        .headline {
          font-size: 3.5rem;
        }
      }
    </style>
  </template>
}
