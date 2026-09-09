import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { BoxelButton } from '@cardstack/boxel-ui/components';
import { type CardContext } from '@cardstack/base/card-api';

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
          <BoxelButton
            @kind='text-only'
            @size='auto'
            class='hover-btn hover-btn-primary'
            data-test-listing-fitted-remix
            {{on 'click' this.openRemix}}
          >↺ Remix</BoxelButton>
          {{#if this.actions.preview}}
            <BoxelButton
              @kind='text-only'
              @size='auto'
              class='hover-btn'
              data-test-listing-fitted-preview
              {{on 'click' this.preview}}
            >▷ Preview</BoxelButton>
          {{/if}}
        </div>
        <BoxelButton
          @kind='text-only'
          @size='auto'
          class='hover-details'
          data-test-listing-fitted-details
          {{on 'click' this.viewDetails}}
        >View details →</BoxelButton>
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
        background-color: var(--overlay);
        color: var(--tooltip-foreground);
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
        background-color: var(--card);
        color: var(--foreground);
        border: none;
        border-radius: 62.4375rem;
        cursor: pointer;
        font: 600 0.8125rem/1 var(--font-sans);
        box-shadow: 0 6px 16px
          color-mix(in oklch, var(--shadow-color) 30%, transparent);
      }
      .hover-btn-primary {
        background-color: var(--accent);
        color: var(--accent-foreground);
        font-weight: 700;
      }
      .hover-details {
        font: 600 0.75rem/1 var(--font-sans);
        color: var(--tooltip-foreground);
        --boxel-button-text-color: var(--tooltip-foreground);
        --boxel-button-background: transparent;
        background-color: transparent;
        border: none;
        border-bottom: 1px solid
          color-mix(in oklch, var(--tooltip-foreground) 50%, transparent);
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
