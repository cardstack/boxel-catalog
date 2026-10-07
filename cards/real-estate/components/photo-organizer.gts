import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Button } from '@cardstack/pretui/components/button';
import { IconButton } from '@cardstack/pretui/components/icon-button';
import { Input } from '@cardstack/pretui/components/input';

// Photo Organizer — the edit-side companion to PropertyGallery. Reordering,
// hero selection, and captions all live here so the three stay coupled: a
// reorder moves the photo, its caption, and the hero mark together, which a
// parallel-array model cannot guarantee if each is edited on its own.
// Mutates the passed model directly (containsMany arrays replace
// wholesale — the MultiImageSourceField editor's own idiom).

// Structural type instead of importing PropertyListing — this component is
// consumed by property-listing.gts, so a real import would be a cycle.
interface OrganizerModel {
  photos?: {
    resolvedUrls?: string[];
    images?: any[];
  };
  photoCaptions?: string[];
  heroIndex?: number | null;
}

interface Signature {
  Args: {
    model: OrganizerModel | undefined;
  };
  Element: HTMLElement;
}

export class PhotoOrganizer extends GlimmerComponent<Signature> {
  @tracked dragIndex: number | undefined;

  // Unfiltered: moves and captions are applied by index to `photos.images`,
  // so a photo whose URL has not resolved keeps its slot here too.
  get urls(): (string | undefined)[] {
    return this.args.model?.photos?.resolvedUrls ?? [];
  }

  get heroIndex(): number {
    let hero = this.args.model?.heroIndex ?? 0;
    return Math.max(0, Math.min(hero, this.urls.length - 1));
  }

  captionAt = (index: number): string => {
    return this.args.model?.photoCaptions?.[index] ?? '';
  };

  /** Captions padded to the photo count, so index writes are stable. */
  private paddedCaptions(length: number): string[] {
    let current = this.args.model?.photoCaptions ?? [];
    return Array.from({ length }, (_, i) => current[i] ?? '');
  }

  setCaption = (index: number, event: Event) => {
    let model = this.args.model;
    if (!model) {
      return;
    }
    let value = (event.target as HTMLInputElement).value;
    let captions = this.paddedCaptions(this.urls.length);
    captions[index] = value;
    model.photoCaptions = captions;
  };

  setHero = (index: number) => {
    let model = this.args.model;
    if (!model) {
      return;
    }
    model.heroIndex = index;
  };

  /** Move the photo at `from` to position `to`, carrying caption and hero. */
  reorder = (from: number, to: number) => {
    let model = this.args.model;
    let images = model?.photos?.images;
    if (!model || !images || from === to || from < 0 || to < 0) {
      return;
    }
    if (from >= images.length || to >= images.length) {
      return;
    }
    let nextImages = [...images];
    let [moved] = nextImages.splice(from, 1);
    nextImages.splice(to, 0, moved);

    let captions = this.paddedCaptions(images.length);
    let [movedCaption] = captions.splice(from, 1);
    captions.splice(to, 0, movedCaption);

    let hero = this.heroIndex;
    let nextHero = hero;
    if (hero === from) {
      nextHero = to;
    } else if (from < hero && hero <= to) {
      nextHero = hero - 1;
    } else if (to <= hero && hero < from) {
      nextHero = hero + 1;
    }

    model.photos!.images = nextImages;
    model.photoCaptions = captions;
    model.heroIndex = nextHero;
  };

  moveLeft = (index: number) => {
    this.reorder(index, index - 1);
  };

  moveRight = (index: number) => {
    this.reorder(index, index + 1);
  };

  onDragStart = (index: number, event: DragEvent) => {
    this.dragIndex = index;
    event.dataTransfer?.setData('text/plain', String(index));
    if (event.dataTransfer) {
      event.dataTransfer.effectAllowed = 'move';
    }
  };

  onDragOver = (e: Event) => {
    let event = e as DragEvent;
    event.preventDefault();
    if (event.dataTransfer) {
      event.dataTransfer.dropEffect = 'move';
    }
  };

  onDrop = (index: number, event: DragEvent) => {
    event.preventDefault();
    let from = this.dragIndex;
    this.dragIndex = undefined;
    if (from !== undefined) {
      this.reorder(from, index);
    }
  };

  onDragEnd = () => {
    this.dragIndex = undefined;
  };

  get lastIndex() {
    return this.urls.length - 1;
  }

  <template>
    {{#if this.urls.length}}
      <ul class='organizer' ...attributes>
        {{#each this.urls as |url index|}}
          <li
            class='item {{if (eq index this.dragIndex) "dragging"}}'
            draggable='true'
            {{on 'dragstart' (fn this.onDragStart index)}}
            {{on 'dragover' this.onDragOver}}
            {{on 'drop' (fn this.onDrop index)}}
            {{on 'dragend' this.onDragEnd}}
          >
            <div class='thumb-wrap'>
              {{#if url}}
                <img src={{url}} alt='Photo {{index}}' loading='lazy' />
              {{else}}
                <span class='no-url'>Photo {{index}} has no URL yet</span>
              {{/if}}
              {{#if (eq index this.heroIndex)}}
                <span class='hero-badge'>HERO</span>
              {{/if}}
            </div>
            {{! the caption commits on change, as a typed caption is one edit;
                the listener rides ...attributes onto Input's own <input> }}
            <Input
              @value={{this.captionAt index}}
              @placeholder='Caption'
              aria-label='Caption for photo {{index}}'
              {{on 'change' (fn this.setCaption index)}}
            />
            <div class='controls'>
              <IconButton
                @label='Move photo {{index}} left'
                @size='s'
                @disabled={{eq index 0}}
                {{on 'click' (fn this.moveLeft index)}}
              >‹</IconButton>
              {{#if (eq index this.heroIndex)}}
                <span class='hero-mark'>Hero</span>
              {{else}}
                <Button
                  class='hero-ctl'
                  @variant='secondary'
                  @size='s'
                  {{on 'click' (fn this.setHero index)}}
                >Set as hero</Button>
              {{/if}}
              <IconButton
                @label='Move photo {{index}} right'
                @size='s'
                @disabled={{eq index this.lastIndex}}
                {{on 'click' (fn this.moveRight index)}}
              >›</IconButton>
            </div>
          </li>
        {{/each}}
      </ul>
    {{/if}}
    <style scoped>
      /* Pret UI Input sets its placeholder in --ink-3, which the theme does
         not declare; the muted ink keeps "Caption" readable */
      .organizer {
        --ink-3: var(--muted-foreground);
        display: flex;
        gap: var(--boxel-sp-xs);
        overflow-x: auto;
        margin: 0;
        padding: var(--boxel-sp-5xs) 0;
        list-style: none;
      }
      .item {
        flex: 0 0 auto;
        width: 10rem;
        display: grid;
        gap: var(--boxel-sp-5xs);
        border: 1px solid var(--border);
        border-radius: var(--radius);
        padding: var(--boxel-sp-5xs);
        background-color: var(--card);
        color: var(--card-foreground);
        cursor: grab;
      }
      .item.dragging {
        opacity: 0.5;
      }
      .thumb-wrap {
        position: relative;
        border-radius: calc(var(--radius) / 1.5);
        overflow: hidden;
        aspect-ratio: 16 / 10;
        background-color: var(--muted);
      }
      .thumb-wrap img {
        width: 100%;
        height: 100%;
        object-fit: cover;
        display: block;
      }
      .hero-badge {
        position: absolute;
        top: 0.25rem;
        left: 0.25rem;
        font-size: 0.5625rem;
        font-weight: 700;
        letter-spacing: 0.08em;
        padding: 0.0625rem 0.375rem;
        border-radius: 999px;
        background-color: var(--foreground);
        color: var(--background);
      }
      .controls {
        display: flex;
        gap: 0.125rem;
        align-items: center;
      }
      .hero-ctl,
      .hero-mark {
        flex: 1;
      }
      .hero-mark {
        text-align: center;
        font-size: 0.6875rem;
        font-weight: 600;
        color: var(--card-foreground);
      }
    </style>
  </template>
}
