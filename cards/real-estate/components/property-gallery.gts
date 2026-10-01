import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { modifier } from 'ember-modifier';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Button } from '@cardstack/pretui/components/button';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { IconButton } from '@cardstack/pretui/components/icon-button';
import { PAUSE_BUTTON_STYLE, SCRIM_BUTTON_STYLE } from '../real-estate-ui';

// Property Gallery — the listing's photo showcase. Render-only and
// domain-neutral about storage: the consumer hands it resolved image URLs
// (Property Listing feeds it MultiImageSourceField.resolvedUrls), an
// optional parallel captions array, and an optional persisted hero index.
// The gallery owns selection state, the empty state, keyboard-reachable
// thumbnails, and four viewing modes (hero / grid / slideshow /
// fullscreen); it never writes anything back.

interface Signature {
  Args: {
    urls: string[] | undefined;
    alt?: string;
    captions?: (string | undefined)[];
    heroIndex?: number;
  };
  Element: HTMLElement;
}

type GalleryMode = 'hero' | 'grid' | 'slideshow' | 'fullscreen';

const SLIDESHOW_INTERVAL_MS = 4000;

// Show the lightbox <dialog> modally as it appears: showModal() puts it in
// the browser's top layer (immune to the stack item's transformed
// ancestors) and focuses it, so its keydown handler hears the arrow keys
// without a document-level listener.
const openModal = modifier((element: HTMLDialogElement) => {
  element.showModal();
  return () => {
    if (element.open) {
      element.close();
    }
  };
});

export class PropertyGallery extends GlimmerComponent<Signature> {
  // undefined until the reader picks a photo; before that the persisted
  // hero (args.heroIndex) fronts the gallery.
  @tracked userSelectedIndex: number | undefined;
  @tracked mode: GalleryMode = 'hero';
  @tracked slideshowPaused = false;

  private slideshowTimer: ReturnType<typeof setInterval> | undefined;

  willDestroy() {
    super.willDestroy();
    this.stopSlideshowTimer();
  }

  get urls(): string[] {
    return (this.args.urls ?? []).filter(Boolean);
  }

  get selectedIndex(): number {
    let max = this.urls.length - 1;
    if (max < 0) {
      return 0;
    }
    let index = this.userSelectedIndex ?? this.args.heroIndex ?? 0;
    return Math.max(0, Math.min(index, max));
  }

  get selectedUrl(): string | undefined {
    return this.urls[this.selectedIndex];
  }

  // Keyed list of one — recreates the <img> on selection change so the
  // crossfade animation replays (a same-element src swap would not).
  get selectedUrlList(): string[] {
    return this.selectedUrl ? [this.selectedUrl] : [];
  }

  captionAt = (index: number): string | undefined => {
    let caption = this.args.captions?.[index];
    return caption?.trim() ? caption : undefined;
  };

  get selectedCaption(): string | undefined {
    return this.captionAt(this.selectedIndex);
  }

  select = (index: number) => {
    this.userSelectedIndex = index;
  };

  selectFromGrid = (index: number) => {
    this.userSelectedIndex = index;
    this.setMode('hero');
  };

  get hasMultiple() {
    return this.urls.length > 1;
  }

  get selectedIndexDisplay() {
    return this.selectedIndex + 1;
  }

  get prefersReducedMotion(): boolean {
    return (
      typeof matchMedia === 'function' &&
      matchMedia('(prefers-reduced-motion: reduce)').matches
    );
  }

  get overlayOpen() {
    return this.mode === 'fullscreen' || this.mode === 'slideshow';
  }

  setMode = (mode: GalleryMode) => {
    this.mode = mode;
    if (mode === 'slideshow') {
      this.slideshowPaused = this.prefersReducedMotion;
      this.startSlideshowTimer();
    } else {
      this.stopSlideshowTimer();
    }
  };

  closeOverlay = () => {
    this.setMode('hero');
  };

  // The native dialog's own Escape path: swallow it (the host closes the
  // whole card stack on Escape) and route through our state instead.
  onDialogCancel = (event: Event) => {
    event.preventDefault();
    this.closeOverlay();
  };

  // Any other native close (e.g. form method=dialog) — keep state in sync.
  onDialogClose = () => {
    if (this.overlayOpen) {
      this.closeOverlay();
    }
  };

  next = () => {
    if (!this.urls.length) {
      return;
    }
    this.userSelectedIndex = (this.selectedIndex + 1) % this.urls.length;
  };

  previous = () => {
    if (!this.urls.length) {
      return;
    }
    this.userSelectedIndex =
      (this.selectedIndex - 1 + this.urls.length) % this.urls.length;
  };

  onOverlayKeydown = (e: Event) => {
    let event = e as KeyboardEvent;
    if (event.key === 'ArrowRight') {
      event.preventDefault();
      event.stopPropagation();
      this.next();
    } else if (event.key === 'ArrowLeft') {
      event.preventDefault();
      event.stopPropagation();
      this.previous();
    } else if (event.key === 'Escape') {
      // Swallow the key entirely — the host also closes the whole card
      // stack on Escape, and closing the lightbox must not close the card.
      event.preventDefault();
      event.stopPropagation();
      this.closeOverlay();
    }
  };

  toggleSlideshowPause = () => {
    this.slideshowPaused = !this.slideshowPaused;
    if (this.slideshowPaused) {
      this.stopSlideshowTimer();
    } else {
      this.startSlideshowTimer();
    }
  };

  private startSlideshowTimer() {
    this.stopSlideshowTimer();
    if (this.slideshowPaused || this.prefersReducedMotion) {
      return;
    }
    this.slideshowTimer = setInterval(() => this.next(), SLIDESHOW_INTERVAL_MS);
  }

  private stopSlideshowTimer() {
    if (this.slideshowTimer) {
      clearInterval(this.slideshowTimer);
      this.slideshowTimer = undefined;
    }
  }

  <template>
    <div class='gallery' ...attributes>
      {{#if this.urls.length}}
        {{#if (eq this.mode 'grid')}}
          <div class='grid-head'>
            <Button
              @variant='ghost'
              @size='s'
              {{on 'click' (fn this.setMode 'hero')}}
            >‹ Hero view</Button>
            <span class='grid-count'>{{this.urls.length}} photos</span>
          </div>
          <div class='grid'>
            {{#each this.urls as |url index|}}
              <figure class='tile'>
                <button
                  type='button'
                  class='tile-btn'
                  aria-label='Photo {{index}}'
                  {{on 'click' (fn this.selectFromGrid index)}}
                >
                  <img
                    src={{url}}
                    alt={{if @alt @alt 'Property photo'}}
                    loading='lazy'
                  />
                </button>
                {{#if (this.captionAt index)}}
                  <figcaption class='tile-caption'>{{this.captionAt
                      index
                    }}</figcaption>
                {{/if}}
              </figure>
            {{/each}}
          </div>
        {{else}}
          <figure class='hero'>
            {{#each this.selectedUrlList as |url|}}
              <img
                class='hero-img'
                src={{url}}
                alt={{if @alt @alt 'Property photo'}}
              />
            {{/each}}
            {{#if this.selectedCaption}}
              <figcaption
                class='hero-caption'
              >{{this.selectedCaption}}</figcaption>
            {{/if}}
            <figcaption class='counter'>{{this.selectedIndexDisplay}}
              /
              {{this.urls.length}}</figcaption>
          </figure>
          {{#if this.hasMultiple}}
            <div class='strip' role='tablist' aria-label='Property photos'>
              {{#each this.urls as |url index|}}
                <button
                  type='button'
                  role='tab'
                  aria-selected='{{if
                    (eq index this.selectedIndex)
                    "true"
                    "false"
                  }}'
                  class='thumb {{if (eq index this.selectedIndex) "active"}}'
                  {{on 'click' (fn this.select index)}}
                >
                  <img src={{url}} alt='Photo {{index}}' loading='lazy' />
                </button>
              {{/each}}
            </div>
            <div class='modes'>
              <Button
                @variant='ghost'
                @size='s'
                {{on 'click' (fn this.setMode 'grid')}}
              >Grid view</Button>
              <Button
                @variant='ghost'
                @size='s'
                {{on 'click' (fn this.setMode 'slideshow')}}
              >Slideshow</Button>
              <Button
                @variant='ghost'
                @size='s'
                {{on 'click' (fn this.setMode 'fullscreen')}}
              >Fullscreen</Button>
            </div>
          {{/if}}
        {{/if}}

        {{#if this.overlayOpen}}
          {{! A native <dialog> shown modally: the top layer escapes the
              stack item's transformed ancestors, which turn position:fixed
              into position-relative-to-the-card (the overlay used to render
              sheared inside the card instead of over the viewport). }}
          <dialog
            class='lightbox'
            aria-label='Photo viewer'
            {{openModal}}
            {{on 'keydown' this.onOverlayKeydown}}
            {{on 'cancel' this.onDialogCancel}}
            {{on 'close' this.onDialogClose}}
          >
            <IconButton
              @label='Close'
              @variant='ghost'
              @size='xl'
              class='lb-close'
              style={{SCRIM_BUTTON_STYLE}}
              {{on 'click' this.closeOverlay}}
            >✕</IconButton>
            {{#if this.hasMultiple}}
              <IconButton
                @label='Previous photo'
                @variant='ghost'
                @size='xl'
                class='lb-nav lb-prev'
                style={{SCRIM_BUTTON_STYLE}}
                {{on 'click' this.previous}}
              >‹</IconButton>
            {{/if}}
            <figure class='lb-figure'>
              <img
                class='lb-img'
                src={{this.selectedUrl}}
                alt={{if @alt @alt 'Property photo'}}
              />
              <figcaption class='lb-caption'>
                {{#if this.selectedCaption}}
                  <span class='lb-caption-text'>{{this.selectedCaption}}</span>
                {{/if}}
                <span class='lb-counter'>{{this.selectedIndexDisplay}}
                  /
                  {{this.urls.length}}</span>
              </figcaption>
            </figure>
            {{#if this.hasMultiple}}
              <IconButton
                @label='Next photo'
                @variant='ghost'
                @size='xl'
                class='lb-nav lb-next'
                style={{SCRIM_BUTTON_STYLE}}
                {{on 'click' this.next}}
              >›</IconButton>
            {{/if}}
            {{#if (eq this.mode 'slideshow')}}
              <Button
                @variant='ghost'
                @size='s'
                class='lb-pause'
                style={{PAUSE_BUTTON_STYLE}}
                {{on 'click' this.toggleSlideshowPause}}
              >{{if this.slideshowPaused 'Resume' 'Pause'}}</Button>
            {{/if}}
          </dialog>
        {{/if}}
      {{else}}
        <EmptyState
          class='empty'
          @title='No photos yet'
          @message='A listing without photos does not get viewings.'
          @texture={{false}}
        />
      {{/if}}
    </div>
    <style scoped>
      .gallery {
        display: grid;
        gap: var(--boxel-sp-xs);
      }
      .hero {
        margin: 0;
        position: relative;
        border-radius: var(--radius);
        overflow: hidden;
        aspect-ratio: 16 / 10;
        background-color: var(--muted);
      }
      .hero-img {
        width: 100%;
        height: 100%;
        object-fit: cover;
        display: block;
        animation: gallery-fade 300ms ease-out;
      }
      @keyframes gallery-fade {
        from {
          opacity: 0;
        }
        to {
          opacity: 1;
        }
      }
      /* caption and counter sit on the photo, so they ride a black scrim
         with white text in both schemes */
      .hero-caption,
      .counter {
        position: absolute;
        bottom: var(--boxel-sp-xs);
        background-color: color-mix(in oklch, transparent, black 55%);
        color: white;
        font-size: 0.75rem;
        border-radius: 999px;
      }
      .hero-caption {
        left: var(--boxel-sp-xs);
        max-width: 60%;
        padding: 0.125rem 0.625rem;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .counter {
        right: var(--boxel-sp-xs);
        padding: 0.125rem 0.5rem;
        font-variant-numeric: tabular-nums;
      }
      .strip {
        display: flex;
        gap: var(--boxel-sp-5xs);
        overflow-x: auto;
        padding-bottom: 0.125rem;
      }
      /* reset: a bare image button, no UA fill */
      .thumb {
        flex: 0 0 auto;
        width: 4.5rem;
        height: 3rem;
        padding: 0;
        border: 0.125rem solid transparent;
        border-radius: calc(var(--radius) / 1.5);
        overflow: hidden;
        cursor: pointer;
        background: none;
        opacity: 0.7;
      }
      .thumb img {
        width: 100%;
        height: 100%;
        object-fit: cover;
        display: block;
      }
      .thumb.active {
        border-color: var(--primary);
        opacity: 1;
      }
      .thumb:hover {
        opacity: 1;
      }
      .modes {
        display: flex;
        gap: var(--boxel-sp-xs);
      }
      .grid-head {
        display: flex;
        justify-content: space-between;
        align-items: baseline;
      }
      .grid-count {
        font-size: 0.75rem;
        color: var(--muted-foreground);
        font-variant-numeric: tabular-nums;
      }
      .grid {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(13.75rem, 1fr));
        gap: var(--boxel-sp-xs);
      }
      .tile {
        margin: 0;
        display: grid;
        gap: var(--boxel-sp-6xs);
      }
      /* reset: a bare image button, no UA fill */
      .tile-btn {
        padding: 0;
        border: 0;
        background: none;
        cursor: pointer;
        border-radius: calc(var(--radius) / 1.5);
        overflow: hidden;
        aspect-ratio: 16 / 10;
      }
      .tile-btn img {
        width: 100%;
        height: 100%;
        object-fit: cover;
        display: block;
      }
      .tile-caption {
        font-size: 0.75rem;
        color: var(--muted-foreground);
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      /* a top-layer modal <dialog>: override the UA's fit-content box so it
         covers the whole viewport, and paint the photo viewer's black scrim
         on the dialog itself (the ::backdrop stays transparent). The scrim
         and its white text hold in both schemes. */
      .lightbox {
        --pretui-size-xl: 1.75rem;
        width: 100vw;
        height: 100vh;
        max-width: 100vw;
        max-height: 100vh;
        margin: 0;
        border: 0;
        display: grid;
        grid-template-columns: auto 1fr auto;
        align-items: center;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp-lg);
        background-color: color-mix(in oklch, transparent, black 90%);
        color: white;
        outline: none;
      }
      .lightbox::backdrop {
        background-color: transparent;
      }
      .lb-figure {
        grid-column: 2;
        margin: 0;
        display: grid;
        justify-items: center;
        gap: var(--boxel-sp-xs);
        min-width: 0;
      }
      .lb-img {
        max-width: 90vw;
        max-height: 85vh;
        object-fit: contain;
        border-radius: var(--radius);
      }
      .lb-caption {
        display: flex;
        gap: var(--boxel-sp-sm);
        align-items: baseline;
        font-size: 0.8125rem;
        max-width: 90vw;
      }
      .lb-caption-text {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .lb-counter {
        font-variant-numeric: tabular-nums;
        opacity: 0.7;
        flex: 0 0 auto;
      }
      .lb-prev {
        grid-column: 1;
      }
      .lb-next {
        grid-column: 3;
      }
      .lb-close {
        position: absolute;
        top: var(--boxel-sp);
        right: var(--boxel-sp);
      }
      /* Centred with the translate property, which composes with the
         transform Pret UI's Button sets on press instead of being replaced. */
      .lb-pause {
        position: absolute;
        bottom: var(--boxel-sp);
        left: 50%;
        translate: -50% 0;
      }
      .empty {
        border: 1px dashed var(--border);
      }
      @media (prefers-reduced-motion: reduce) {
        .hero-img {
          animation: none;
        }
      }
    </style>
  </template>
}
