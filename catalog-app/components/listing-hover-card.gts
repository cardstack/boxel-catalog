import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { type CardContext } from 'https://cardstack.com/base/card-api';

import { type Listing } from '../listing/listing';
import { listingActions, isReady } from '../resources/listing-actions';
import { requestRemixFocus } from '../resources/remix-intent';

interface Signature {
  Args: {
    listing: Listing;
    context?: CardContext;
  };
  Blocks: {
    default: [];
  };
  Element: HTMLElement;
}

// Shared hover overlay (Remix / Preview / View details) for anything that
// spotlights a Listing — the gallery's fitted tile and the hero carousel
// both wrap their background content in this so the actions stay identical.
export default class ListingHoverCard extends GlimmerComponent<Signature> {
  actionsResource = listingActions(this, () => ({
    listing: this.args.listing,
  }));

  get actions() {
    return isReady(this.actionsResource)
      ? this.actionsResource.actions
      : undefined;
  }

  preview = (event: Event) => {
    event.stopPropagation();
    this.actions?.preview?.();
  };

  viewDetails = (event: Event) => {
    event.stopPropagation();
    this.actions?.view();
  };

  openRemix = (event: Event) => {
    event.stopPropagation();
    if (!this.actions?.view) {
      // Actions aren't ready yet — bail out without setting the pending
      // intent, or it could wrongly fire on a later, unrelated visit.
      return;
    }
    // Open the detail view and ask it to focus its remix panel on arrival.
    requestRemixFocus(this.args.listing.id);
    this.actions.view();
  };

  <template>
    <div class='hover-card' ...attributes>
      {{yield}}

      <div class='hover-layer'>
        <div class='hover-actions'>
          <button
            type='button'
            class='hover-btn hover-btn-primary'
            data-test-listing-fitted-remix
            {{on 'click' this.openRemix}}
          >↺ Remix</button>
          {{#if this.actions.preview}}
            <button
              type='button'
              class='hover-btn'
              data-test-listing-fitted-preview
              {{on 'click' this.preview}}
            >▷ Preview</button>
          {{/if}}
        </div>
        <button
          type='button'
          class='hover-details'
          data-test-listing-fitted-details
          {{on 'click' this.viewDetails}}
        >View details →</button>
      </div>
    </div>

    <style scoped>
      .hover-card {
        position: relative;
        width: 100%;
        height: 100%;
        overflow: hidden;
      }
      .hover-layer {
        position: absolute;
        inset: 0;
        z-index: 4;
        background: rgba(13, 13, 18, 0.62);
        backdrop-filter: blur(0.125rem);
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 0.6875rem;
        opacity: 0;
        transition: opacity 160ms ease;
        pointer-events: none;
      }
      .hover-card:hover .hover-layer,
      .hover-card:focus-within .hover-layer {
        opacity: 1;
        pointer-events: auto;
      }
      .hover-actions {
        display: flex;
        gap: 0.5625rem;
      }
      .hover-btn {
        padding: 0.6875rem 1.25rem;
        background: color-mix(in srgb, var(--card, #fff) 96%, transparent);
        color: var(--foreground, #16161c);
        border: none;
        border-radius: 999px;
        cursor: pointer;
        font: 600 0.8125rem/1 var(--font-sans, 'IBM Plex Sans', sans-serif);
        box-shadow: 0 6px 16px rgba(0, 0, 0, 0.3);
      }
      .hover-btn-primary {
        background: var(--accent, #16e098);
        color: var(--primary-foreground, #04231a);
        font-weight: 700;
      }
      .hover-details {
        font: 600 0.75rem/1 var(--font-sans, 'IBM Plex Sans', sans-serif);
        color: #fff;
        background: transparent;
        border: none;
        border-bottom: 1px solid rgba(255, 255, 255, 0.5);
        padding-bottom: 0.125rem;
        cursor: pointer;
      }
      @container fitted-card (height <= 105px) {
        .hover-details {
          display: none;
        }
      }
      @container fitted-card (height <= 65px) {
        .hover-layer {
          display: none;
        }
      }
      @media (prefers-reduced-motion: reduce) {
        .hover-layer {
          transition: none;
        }
      }
    </style>
  </template>
}
