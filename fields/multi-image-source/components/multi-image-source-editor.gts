import Component from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { fn } from '@ember/helper';
import { on } from '@ember/modifier';
import { modifier } from 'ember-modifier';
import { eq } from '@cardstack/boxel-ui/helpers';
import PhotoPlusIcon from '@cardstack/boxel-icons/photo-plus';
import type { BoxComponent } from 'https://cardstack.com/base/card-api';
import { BoxelInputGroup } from '@cardstack/boxel-ui/components';
import { IconLink, IconX } from '@cardstack/boxel-ui/icons';

import ImageSourceField from '../../image-source/image-source';

interface MultiImageSourceModel {
  images: any[] | null | undefined;
  newImage: any;
}

interface MultiImageSourceEditorSignature {
  Args: {
    model: MultiImageSourceModel;
    // the linksTo editor for the field's `newImage` add slot — the exact
    // Link Image button the single field's edit template uses
    fileField: BoxComponent;
  };
}

// The multi-image counterpart of ImageSourceEditor. With images: a grid of
// landscape previews (link badge + remove), a full-width Link Image bar,
// and a paste-URL row. Empty: a two-panel invitation — link a workspace
// image, or add by URL. Styling resolves knob → semantic theme token →
// boxel/literal (three-scope), so themed hosts restyle it for free.
export default class MultiImageSourceEditor extends Component<MultiImageSourceEditorSignature> {
  @tracked urlDraft = '';
  @tracked errorMessage: string | null = null;

  get items(): any[] {
    return this.args.model?.images ?? [];
  }

  // gallery highlight: which image fills the hero preview
  @tracked selectedIndex = 0;

  get selectedItem() {
    return this.items[this.selectedIndex] ?? this.items[0];
  }

  selectAt = (index: number) => {
    this.selectedIndex = index;
  };

  removeAt = (index: number) => {
    if (!this.args.model) return;
    this.args.model.images = this.items.filter((_, i) => i !== index);
    this.selectedIndex = Math.max(
      0,
      Math.min(this.selectedIndex, this.items.length - 1),
    );
  };

  // BoxelInputGroup's @onInput passes the value itself, not an event
  onUrlInput = (value: string) => {
    this.urlDraft = value;
  };

  addUrl = (event: Event) => {
    event.preventDefault();
    let url = this.urlDraft.trim();
    if (!this.args.model || !url) return;
    this.args.model.images = [
      ...this.items,
      new ImageSourceField({ url, sourceMode: 'url' }),
    ];
    this.selectedIndex = this.items.length - 1;
    this.urlDraft = '';
    this.errorMessage = null;
  };

  // the linksTo editor writes the pick into the `newImage` add slot; this
  // moves it into the list and clears the slot for the next add. The
  // mutation is deferred to a microtask (mutating during render is dropped
  // by the renderer), and guarded so a slot that persisted before clearing
  // doesn't re-adopt the same image on the next edit.
  adoptPickedImage = modifier((_element: HTMLElement, [picked]: [any]) => {
    if (!picked?.url || !this.args.model) return;
    void Promise.resolve().then(() => {
      let last = this.items[this.items.length - 1];
      if (last?.resolvedUrl !== picked.url) {
        this.args.model.images = [
          ...this.items,
          new ImageSourceField({ file: picked, sourceMode: 'file' }),
        ];
        this.selectedIndex = this.items.length - 1;
      }
      this.args.model.newImage = null;
    });
  });

  <template>
    <div class='image-source-root' data-test-multi-image-source-edit>
      {{#if this.items.length}}
        {{! hero: the highlighted image; click a thumb below to swap it in }}
        <figure class='hero' data-test-multi-image-source-hero>
          {{#if this.selectedItem.resolvedUrl}}
            <img src={{this.selectedItem.resolvedUrl}} alt='' />
          {{/if}}
        </figure>
        <ul class='thumbs' aria-label='Images'>
          {{#each this.items as |item index|}}
            <li class='thumb {{if (eq index this.selectedIndex) "is-active"}}'>
              <button
                type='button'
                class='thumb-pick'
                data-test-multi-image-source-thumb
                aria-label='Show this image'
                aria-pressed={{if (eq index this.selectedIndex) 'true' 'false'}}
                {{on 'click' (fn this.selectAt index)}}
              >
                {{#if item.resolvedUrl}}
                  <img src={{item.resolvedUrl}} alt='' />
                {{/if}}
              </button>
              <button
                type='button'
                class='remove-btn'
                aria-label='Remove image'
                data-test-multi-image-source-remove
                {{on 'click' (fn this.removeAt index)}}
              >
                <IconX width='8' height='8' aria-hidden='true' />
              </button>
            </li>
          {{/each}}
        </ul>

        <div
          class='file-link-btn file-link-btn--bar'
          data-test-multi-image-source-link
          {{this.adoptPickedImage @model.newImage}}
        >
          <@fileField />
        </div>

        <form class='url-form' {{on 'submit' this.addUrl}}>
          <label class='visually-hidden' for='multi-url-input'>Image URL</label>
          <BoxelInputGroup
            id='multi-url-input'
            @placeholder='Paste image URL…'
            @value={{this.urlDraft}}
            @onInput={{this.onUrlInput}}
            data-test-multi-image-source-url-input
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
                data-test-multi-image-source-url-add
              >
                Add
              </button>
            </:after>
          </BoxelInputGroup>
        </form>
      {{else}}
        <div class='empty'>
          <div class='empty-pick' data-test-multi-image-source-link>
            <PhotoPlusIcon
              class='empty-pick-icon'
              width='20'
              height='20'
              aria-hidden='true'
            />
            <span class='empty-pick-title'>Add your first image</span>
            <div
              class='file-link-btn'
              {{this.adoptPickedImage @model.newImage}}
            >
              <@fileField />
            </div>
          </div>
          <div class='empty-divider' aria-hidden='true'>
            <span class='empty-or'>or</span>
          </div>
          <div class='empty-url'>
            <span class='empty-url-title'>Add image URL</span>
            <form class='url-form' {{on 'submit' this.addUrl}}>
              <label class='visually-hidden' for='multi-url-input'>Image URL</label>
              <BoxelInputGroup
                id='multi-url-input'
                @placeholder='Paste image URL…'
                @value={{this.urlDraft}}
                @onInput={{this.onUrlInput}}
                data-test-multi-image-source-url-input
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
                    data-test-multi-image-source-url-add
                  >
                    Add
                  </button>
                </:after>
              </BoxelInputGroup>
            </form>
          </div>
        </div>
      {{/if}}

      {{#if this.errorMessage}}
        <p class='error' role='alert'>{{this.errorMessage}}</p>
      {{/if}}
    </div>

    <style scoped>
      /* resolution order: --mlt-img-* (this editor only) → --img-source-*
         (shared with the single-image editor — one override re-skins both)
         → semantic theme token → boxel/literal fallback. The --img-* names
         are the resolved values every rule below reads. */
      .image-source-root {
        --img-bg: var(
          --mlt-img-bg,
          var(--img-source-bg, var(--card, var(--boxel-light, #fff)))
        );
        --img-text: var(
          --mlt-img-text,
          var(
            --img-source-text,
            var(--card-foreground, var(--boxel-700, #272330))
          )
        );
        --img-dim: var(
          --mlt-img-text-dim,
          var(
            --img-source-text-dim,
            var(--muted-foreground, var(--boxel-400, #afafb7))
          )
        );
        --img-border: var(
          --mlt-img-border,
          var(
            --img-source-border,
            var(--border, var(--boxel-border-color, #d3d3d3))
          )
        );
        /* accent deliberately skips the app's global --primary (the boxel
           highlight green would take over every control) — hosts/themes
           re-skin it through the --img-source-accent knob instead, exactly like
           the single-image editor's --boxel-purple */
        --img-accent: var(
          --mlt-img-accent,
          var(--img-source-accent, var(--boxel-purple, #6638ff))
        );
        --img-accent-fg: var(
          --mlt-img-accent-fg,
          var(--img-source-accent-fg, var(--boxel-light, #fff))
        );
        --img-danger: var(
          --mlt-img-danger,
          var(
            --img-source-danger,
            var(--destructive, var(--boxel-danger, #ff5050))
          )
        );
        --img-font: var(
          --mlt-img-font,
          var(
            --img-source-font,
            var(--font-sans, var(--boxel-font-family, sans-serif))
          )
        );

        --img-accent-bg: color-mix(in srgb, var(--img-accent) 8%, transparent);
        /* the input group's focus ring reads var(--ring, --boxel-highlight);
           re-point both locally so focus matches the accent instead of the
           app's global highlight green */
        --ring: var(--mlt-img-ring, var(--img-source-ring, var(--img-accent)));
        --boxel-highlight: var(
          --mlt-img-ring,
          var(--img-source-ring, var(--img-accent))
        );
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-2xs);
        background: var(--img-bg);
        font-family: var(--img-font);
        color: var(--img-text);
        border: 1px solid var(--img-border);
        border-radius: var(--boxel-radius, 10px);
        padding: var(--boxel-sp-xs);
        /* lets the empty-state layout respond to the host's width */
        container-type: inline-size;
      }

      /* ── hero: the highlighted image ── */
      .hero {
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
        /* contain, not cover — the highlight should show the whole image */
        object-fit: contain;
      }

      /* ── single-row thumbnail strip, scrolls sideways ── */
      .thumbs {
        display: flex;
        flex-wrap: nowrap;
        gap: var(--boxel-sp-2xs);
        margin: 0;
        padding: 4px 2px;
        list-style: none;
        overflow-x: auto;
      }
      .thumb {
        position: relative;
        flex: 0 0 auto;
        width: 3.25rem;
        aspect-ratio: 1;
      }
      .thumb-pick {
        display: block;
        width: 100%;
        height: 100%;
        padding: 0;
        border: none;
        background: none;
        cursor: pointer;
      }
      .thumb-pick img {
        display: block;
        width: 100%;
        height: 100%;
        object-fit: cover;
        border-radius: var(--boxel-border-radius-sm, 6px);
        border: 1px solid var(--img-border);
        background: var(--boxel-100, #f8f7fa);
      }
      .thumb.is-active .thumb-pick img {
        border-color: var(--img-accent);
        box-shadow: 0 0 0 1px var(--img-accent);
      }
      .remove-btn {
        position: absolute;
        top: -4px;
        right: -4px;
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

      /* ── the linksTo editor's Link Image button, re-skinned exactly like
         the single field's file-link-btn ── */
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
      /* bar variant: fills the row under the previews, dashed like an
         add tile */
      .file-link-btn--bar :deep(.links-to-editor),
      .file-link-btn--bar :deep(.add-new.boxel-button) {
        width: 100%;
      }
      .file-link-btn--bar :deep(.add-new.boxel-button) {
        --boxel-button-border: 1px dashed var(--img-border);
      }
      .file-link-btn--bar :deep(.add-new.boxel-button:hover) {
        --boxel-button-border: 1px dashed var(--img-accent);
      }

      /* ── url row (compact: shrink the input group via its own tokens) ── */
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
      /* input suffix, not a nested pill — a left rule instead of its own
         rounded border avoids double corners inside the input group */
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

      /* ── empty state: pick a card, or add by URL ── */
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
      /* soft accent tile around the icon (the mock's rounded chip) */
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
      /* line — (or) — line, running the full height of the empty state */
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
      /* narrow hosts (sidebars): stack the two paths, divider goes flat,
         and the dashed box drops — the divider already separates the two
         paths, so the extra frame is noise at this size */
      @container (max-width: 24rem) {
        .empty {
          grid-template-columns: 1fr;
        }
        /* icon tile + Link Image button, centered — no frame, no title
           (the mock's stacked layout) */
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
      .error {
        margin: 0;
        font-size: var(--boxel-font-size-xs, 12px);
        color: var(--img-danger);
      }
    </style>
  </template>
}
