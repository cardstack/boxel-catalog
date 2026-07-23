import Component from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { modifier } from 'ember-modifier';
import PhotoPlusIcon from '@cardstack/boxel-icons/photo-plus';
import type { BoxComponent } from 'https://cardstack.com/base/card-api';
import { BoxelInputGroup } from '@cardstack/boxel-ui/components';
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
  // (deferred to a microtask — mutating during render is dropped)
  adoptPickedFile = modifier((_element: HTMLElement, [file]: [any]) => {
    if (file?.url && this.sourceMode !== 'file') {
      void Promise.resolve().then(() => {
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
            <button
              type='button'
              class='remove-btn'
              aria-label='Remove image'
              data-test-image-source-remove
              {{on 'click' this.removeImage}}
            >
              <IconX width='8' height='8' aria-hidden='true' />
            </button>
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
                    <button
                      type='submit'
                      class='add-url-btn'
                      data-test-image-source-url-add
                    >
                      Add
                    </button>
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
        --img-bg: var(--img-source-bg, var(--card, var(--boxel-light, #fff)));
        --img-text: var(
          --img-source-text,
          var(--card-foreground, var(--boxel-700, #272330))
        );
        --img-dim: var(
          --img-source-text-dim,
          var(--muted-foreground, var(--boxel-400, #afafb7))
        );
        --img-border: var(
          --img-source-border,
          var(--border, var(--boxel-border-color, #d3d3d3))
        );
        --img-accent: var(--img-source-accent, var(--boxel-purple, #6638ff));
        --img-accent-fg: var(--img-source-accent-fg, var(--boxel-light, #fff));
        --img-danger: var(
          --img-source-danger,
          var(--destructive, var(--boxel-danger, #ff5050))
        );
        --img-font: var(
          --img-source-font,
          var(--font-sans, var(--boxel-font-family, sans-serif))
        );
        --img-accent-bg: color-mix(in srgb, var(--img-accent) 8%, transparent);
        /* the input group's focus ring reads var(--ring, --boxel-highlight);
           re-point both locally so focus matches the accent */
        --ring: var(--img-source-ring, var(--img-accent));
        --boxel-highlight: var(--img-source-ring, var(--img-accent));

        background: var(--img-bg);
        font-family: var(--img-font);
        color: var(--img-text);
        border: 1px solid var(--img-border);
        border-radius: var(--boxel-radius, 10px);
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
        border-radius: var(--boxel-border-radius-sm, 6px);
        overflow: hidden;
        background: var(--boxel-100, #f8f7fa);
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
        top: 6px;
        right: 6px;
        z-index: 1;
        display: grid;
        place-items: center;
        width: 1rem;
        height: 1rem;
        padding: 0;
        border: 1px solid var(--img-border);
        border-radius: 50%;
        background: var(--img-bg);
        color: var(--img-text);
        --icon-color: var(--img-text);
        box-shadow: 0 1px 3px rgba(0, 0, 0, 0.15);
        cursor: pointer;
      }
      .remove-btn:hover,
      .remove-btn:focus {
        background: var(--img-danger);
        color: var(--img-bg);
        --icon-color: var(--img-bg);
      }

      /* ── the linksTo editor's Link Image button ── */
      .file-link-btn :deep(.links-to-editor) {
        display: flex;
        justify-content: center;
      }
      .file-link-btn :deep(.add-new.boxel-button) {
        --boxel-button-text-color: var(--img-accent);
        --boxel-button-color: transparent;
        --boxel-button-border: 1px solid var(--img-accent);
        --boxel-button-padding: var(--boxel-sp-5xs, 2px) var(--boxel-sp-xs);
        --boxel-button-min-height: 0;
        min-height: 0;
        font-size: var(--boxel-font-size-xs, 12px);
        font-weight: 500;
        letter-spacing: 0;
        border-radius: var(--boxel-border-radius-sm, 6px);
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
        --boxel-input-group-padding-y: var(--boxel-sp-5xs, 2px);
        --boxel-input-height: 1.75rem;
      }
      .url-form :deep(.boxel-input-group),
      .url-form :deep(.form-control) {
        font-size: var(--boxel-font-size-xs, 12px);
      }
      .url-form :deep(.text-accessory) {
        --icon-color: var(--img-accent);
        color: var(--img-accent);
      }
      .url-form :deep(.text-accessory svg) {
        --icon-color: var(--img-accent);
        color: var(--img-accent);
        display: block;
      }
      /* input suffix, not a nested pill */
      .add-url-btn {
        align-self: stretch;
        padding: 0 var(--boxel-sp-sm);
        border: none;
        border-left: 1px solid var(--img-border);
        background: transparent;
        color: var(--img-accent);
        font-size: var(--boxel-font-size-xs, 12px);
        font-weight: 600;
        font-family: var(--img-font);
        cursor: pointer;
      }
      .add-url-btn:hover {
        background: var(--img-accent-bg);
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
        gap: var(--boxel-sp-5xs, 2px);
        padding: var(--boxel-sp-xs);
        border: 1px dashed var(--img-border);
        border-radius: var(--boxel-border-radius-sm, 6px);
        background: transparent;
        font-family: var(--img-font);
      }
      /* soft accent tile around the icon */
      .empty-pick-icon {
        box-sizing: content-box;
        padding: var(--boxel-sp-xs);
        border-radius: var(--boxel-border-radius, 10px);
        background: var(--img-accent-bg);
        color: var(--img-accent);
        --icon-color: var(--img-accent);
      }
      .empty-pick-title {
        font-size: var(--boxel-font-size-xs, 12px);
        font-weight: 600;
        color: var(--img-text);
      }
      .empty-pick .file-link-btn {
        margin-top: var(--boxel-sp-4xs, 4px);
      }
      /* line — (or) — line */
      .empty-divider {
        align-self: stretch;
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: var(--boxel-sp-5xs, 2px);
      }
      .empty-divider::before,
      .empty-divider::after {
        content: '';
        width: 1px;
        flex: 1;
        background: var(--img-border);
      }
      .empty-or {
        display: grid;
        place-items: center;
        width: 1.75rem;
        height: 1.75rem;
        border: 1px solid var(--img-border);
        border-radius: 50%;
        font-size: var(--boxel-font-size-2xs, 11px);
        color: var(--img-dim);
        background: var(--img-bg);
      }
      .empty-url {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-4xs, 4px);
        min-width: 0;
      }
      .empty-url-title {
        font-size: var(--boxel-font-size-xs, 12px);
        font-weight: 600;
        color: var(--img-text);
      }
      /* narrow hosts: stack the two paths, divider goes flat, frame drops */
      @container (max-width: 24rem) {
        .empty {
          grid-template-columns: 1fr;
        }
        .empty-pick {
          border: none;
          padding: var(--boxel-sp-5xs, 2px);
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
