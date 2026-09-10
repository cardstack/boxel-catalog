import Component from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { isDestroyed, isDestroying } from '@ember/destroyable';
import { on } from '@ember/modifier';
import { modifier } from 'ember-modifier';
import PhotoPlusIcon from '@cardstack/boxel-icons/photo-plus';
import type { BoxComponent } from '@cardstack/base/card-api';
import { BoxelInputGroup, Button } from '@cardstack/boxel-ui/components';
import { IconLink, IconX } from '@cardstack/boxel-ui/icons';

import type { ImageSourceMode } from '../image-source';
import { selectedSourceMode } from '../utils';

interface ImageSourceModel {
  url: string | null | undefined;
  file: { url?: string | null } | null | undefined;
  sourceMode: string | null | undefined;
}

interface ImageSourceEditorSignature {
  Args: {
    model: ImageSourceModel;
    fileField: BoxComponent;
  };
}

// One surface, two moves — the same design language as the Multi Image
// Source editor. With an image: a hero preview with a remove button. Empty:
// a two-panel invitation — link a workspace image, or add by URL. Styling
// resolves --img-source-* knob → semantic theme token → boxel/literal (three-scope),
// so themed hosts restyle both editors at once.
export default class ImageSourceEditor extends Component<ImageSourceEditorSignature> {
  @tracked urlDraft = '';

  get sourceMode(): ImageSourceMode {
    return selectedSourceMode(
      this.args.model?.sourceMode,
      this.args.model?.url,
    );
  }

  get resolvedUrl(): string {
    return this.sourceMode === 'url'
      ? (this.args.model?.url ?? '')
      : (this.args.model?.file?.url ?? '');
  }

  get hasImage() {
    return Boolean(this.resolvedUrl);
  }

  // BoxelInputGroup's @onInput passes the value itself, not an event
  onUrlInput = (value: string) => {
    this.urlDraft = value;
  };

  addUrl = (event: Event) => {
    event.preventDefault();
    let model = this.args.model;
    let url = this.urlDraft.trim();
    if (!model || !url) return;
    model.url = url;
    model.sourceMode = 'url';
    this.urlDraft = '';
  };

  removeImage = () => {
    let model = this.args.model;
    if (!model) return;
    model.file = undefined;
    model.url = null;
  };

  // picking a file through the linksTo editor makes file the active source
  // (deferred to a microtask — mutating during render is dropped). This also
  // self-heals instances persisted as { file: set, sourceMode: 'url' }: the
  // first edit render flips them to file — an intentional write-on-open.
  adoptPickedFile = modifier((_element: HTMLElement, [file]: [any]) => {
    if (file?.url && this.sourceMode !== 'file') {
      void Promise.resolve().then(() => {
        if (isDestroyed(this) || isDestroying(this)) return;
        this.args.model.sourceMode = 'file';
      });
    }
  });

  <template>
    <div class='image-source-root' data-test-image-source-edit>
      <div class='editor' data-test-image-source-editor>
        {{#if this.hasImage}}
          <figure class='hero' data-test-image-source-preview>
            <img src={{this.resolvedUrl}} alt='' />
            <Button
              @kind='text-only'
              @size='auto'
              class='remove-btn'
              aria-label='Remove image'
              data-test-image-source-remove
              {{on 'click' this.removeImage}}
            >
              <IconX width='8' height='8' aria-hidden='true' />
            </Button>
          </figure>
        {{else}}
          <div class='empty'>
            <div
              class='empty-pick'
              data-test-image-source-file-field
              {{this.adoptPickedFile @model.file}}
            >
              <PhotoPlusIcon
                class='empty-pick-icon'
                width='20'
                height='20'
                aria-hidden='true'
              />
              <span class='empty-pick-title'>Add an image</span>
              <div class='file-link-btn'>
                <@fileField />
              </div>
            </div>
            <div class='empty-divider' aria-hidden='true'>
              <span class='empty-or'>or</span>
            </div>
            <div class='empty-url'>
              <span class='empty-url-title'>Add image URL</span>
              <form class='url-form' {{on 'submit' this.addUrl}}>
                <label class='visually-hidden' for='is-url-input'>Image URL</label>
                <BoxelInputGroup
                  id='is-url-input'
                  @placeholder='Paste image URL…'
                  @value={{this.urlDraft}}
                  @onInput={{this.onUrlInput}}
                  data-test-image-source-url-input
                >
                  <:before as |Accessories|>
                    <Accessories.Text>
                      <IconLink width='14' height='14' aria-hidden='true' />
                    </Accessories.Text>
                  </:before>
                  <:after>
                    <Button
                      @kind='text-only'
                      @size='auto'
                      type='submit'
                      class='add-url-btn'
                      data-test-image-source-url-add
                    >
                      Add
                    </Button>
                  </:after>
                </BoxelInputGroup>
              </form>
            </div>
          </div>
        {{/if}}
      </div>
    </div>

    <style scoped>
      /* three-scope resolution: --img-source-* component knob → semantic theme
         token → boxel/literal fallback — the SAME knob namespace as the
         Multi Image Source editor, so a host re-skins both at once. Accent
         deliberately skips the app's global --primary (the boxel highlight
         green would take over every control). The --img-* names are the
         resolved values every rule below reads. */
      .image-source-root {
        --img-accent-bg: color-mix(in oklch, var(--primary) 8%, transparent);
        /* the input group's focus ring reads var(--ring);
           re-point both locally so focus matches the accent */
        --boxel-highlight: var(--primary);

        background-color: var(--card);
        font-family: var(--font-sans);
        color: var(--card-foreground);
        border: 1px solid var(--border);
        border-radius: var(--boxel-radius);
        padding: var(--boxel-sp-xs);
        /* lets the empty-state layout respond to the host's width */
        container-type: inline-size;
      }

      /* ── hero: the current image ── */
      .hero {
        position: relative;
        margin: 0;
        aspect-ratio: 16 / 9;
        max-height: 12rem;
        width: 100%;
        padding: var(--boxel-sp-2xs);
        border-radius: var(--boxel-border-radius-sm);
        overflow: hidden;
        /* letterbox surface derives from the themed bg/text pair instead of
           a raw boxel gray, so dark-themed hosts stay dark */
        background-color: color-mix(
          in oklch,
          var(--card) 94%,
          var(--card-foreground)
        );
      }
      .hero img {
        display: block;
        width: 100%;
        height: 100%;
        /* contain, not cover — show the whole image */
        object-fit: contain;
      }
      .remove-btn {
        position: absolute;
        top: 0.375rem;
        right: 0.375rem;
        z-index: 1;
        display: grid;
        place-items: center;
        width: 1rem;
        height: 1rem;
        padding: 0;
        border: 1px solid var(--border);
        border-radius: 50%;
        background-color: var(--card);
        color: var(--card-foreground);
        --icon-color: var(--card-foreground);
        box-shadow: 0 1px 3px
          color-mix(in oklch, var(--shadow-color) 15%, transparent);
        cursor: pointer;
      }
      .remove-btn:hover,
      .remove-btn:focus {
        background-color: var(--destructive);
        color: var(--destructive-foreground);
        --icon-color: var(--card);
      }

      /* ── the linksTo editor's Link Image button ── */
      .file-link-btn :deep(.links-to-editor) {
        display: flex;
        justify-content: center;
      }
      .file-link-btn :deep(.add-new.boxel-button) {
        --boxel-button-text-color: var(--primary-ink);
        --boxel-button-color: transparent;
        --boxel-button-border: 1px solid var(--primary);
        --boxel-button-padding: var(--boxel-sp-5xs) var(--boxel-sp-xs);
        --boxel-button-min-height: 0;
        min-height: 0;
        font-size: var(--boxel-font-size-xs);
        font-weight: 500;
        letter-spacing: 0;
        border-radius: var(--boxel-border-radius-sm);
        width: auto;
        height: auto;
      }
      .file-link-btn :deep(.add-new.boxel-button:hover) {
        --boxel-button-color: var(--img-accent-bg);
      }

      /* ── url row (compact) ── */
      .url-form {
        margin: 0;
        --boxel-input-group-padding-x: var(--boxel-sp-xs);
        --boxel-input-group-padding-y: var(--boxel-sp-5xs);
        --boxel-input-height: 1.75rem;
      }
      .url-form :deep(.boxel-input-group),
      .url-form :deep(.form-control) {
        font-size: var(--boxel-font-size-xs);
      }
      .url-form :deep(.text-accessory) {
        --icon-color: var(--primary);
        color: var(--primary-ink);
      }
      .url-form :deep(.text-accessory svg) {
        --icon-color: var(--primary);
        color: var(--primary-ink);
        display: block;
      }
      /* input suffix, not a nested pill */
      /* A suffix inside the input group, not a nested pill. BoxelButton
         defaults to a 100px radius and supplies its own padding / border /
         background, which out-specify element-level rules here and push the
         label past the group's rounded corner — so drive it through the
         button's own knobs, and draw the divider with the shadow knob where
         no border rule can contest it. */
      .add-url-btn {
        --boxel-button-border-radius: 0;
        --boxel-button-color: transparent;
        --boxel-button-border: none;
        --boxel-button-box-shadow: inset 1px 0 0 var(--border);
        --boxel-button-ghost-foreground: var(--primary-ink);
        --boxel-button-padding: 0 var(--boxel-sp-sm);
        --boxel-button-min-height: 0;
        --boxel-button-min-width: 0;
        --boxel-button-font: 600 var(--boxel-font-size-xs) / 1 var(--font-sans);
        --boxel-button-letter-spacing: normal;
        align-self: stretch;
        cursor: pointer;
      }

      /* ── empty state: link a card, or add by URL ── */
      .empty {
        display: grid;
        grid-template-columns: 1fr auto 1fr;
        align-items: center;
        gap: var(--boxel-sp-xs);
      }
      .empty-pick {
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: var(--boxel-sp-5xs);
        padding: var(--boxel-sp-xs);
        border: 1px dashed var(--border);
        border-radius: var(--boxel-border-radius-sm);
        background-color: transparent;
        font-family: var(--font-sans);
      }
      /* soft accent tile around the icon */
      .empty-pick-icon {
        box-sizing: content-box;
        padding: var(--boxel-sp-xs);
        border-radius: var(--boxel-border-radius);
        background-color: var(--img-accent-bg);
        color: var(--primary-ink);
        --icon-color: var(--primary);
      }
      .empty-pick-title {
        font-size: var(--boxel-font-size-xs);
        font-weight: 600;
        color: var(--card-foreground);
      }
      .empty-pick .file-link-btn {
        margin-top: var(--boxel-sp-4xs);
      }
      /* line — (or) — line */
      .empty-divider {
        align-self: stretch;
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: var(--boxel-sp-5xs);
      }
      .empty-divider::before,
      .empty-divider::after {
        content: '';
        width: 1px;
        flex: 1;
        background-color: var(--border);
      }
      .empty-or {
        display: grid;
        place-items: center;
        width: 1.75rem;
        height: 1.75rem;
        border: 1px solid var(--border);
        border-radius: 50%;
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
        background-color: var(--card);
      }
      .empty-url {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-4xs);
        min-width: 0;
      }
      .empty-url-title {
        font-size: var(--boxel-font-size-xs);
        font-weight: 600;
        color: var(--card-foreground);
      }
      /* narrow hosts: stack the two paths, divider goes flat, frame drops */
      @container (max-width: 24rem) {
        .empty {
          grid-template-columns: 1fr;
        }
        .empty-pick {
          border: none;
          padding: var(--boxel-sp-5xs);
          gap: var(--boxel-sp-xs);
        }
        .empty-pick-title {
          display: none;
        }
        .empty-pick-icon {
          padding: var(--boxel-sp-sm);
        }
        .empty-divider {
          flex-direction: row;
          align-self: center;
          width: 100%;
        }
        .empty-divider::before,
        .empty-divider::after {
          width: auto;
          height: 1px;
        }
      }

      .visually-hidden {
        position: absolute;
        width: 1px;
        height: 1px;
        overflow: hidden;
        clip: rect(0 0 0 0);
      }
    </style>
  </template>
}
