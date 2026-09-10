import Component from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { fn } from '@ember/helper';
import { on } from '@ember/modifier';
import { modifier } from 'ember-modifier';
import type { TemplateOnlyComponent } from '@ember/component/template-only';
import { eq } from '@cardstack/boxel-ui/helpers';
import PhotoPlusIcon from '@cardstack/boxel-icons/photo-plus';
import type { BoxComponent } from '@cardstack/base/card-api';
import { BoxelInputGroup, Button } from '@cardstack/boxel-ui/components';
import { IconLink, IconX } from '@cardstack/boxel-ui/icons';

import ImageSourceField from '../../image-source/image-source';

interface UrlAddFormSignature {
  Args: {
    urlDraft: string;
    onUrlInput: (value: string) => void;
    onSubmit: (event: Event) => void;
  };
}

// the "paste a URL" row — identical in the has-items and empty-state
// branches below, so it's factored out once instead of copy-pasted twice.
const UrlAddForm: TemplateOnlyComponent<UrlAddFormSignature> = <template>
  <form class='url-form' {{on 'submit' @onSubmit}}>
    <label class='visually-hidden' for='multi-url-input'>Image URL</label>
    <BoxelInputGroup
      id='multi-url-input'
      @placeholder='Paste image URL…'
      @value={{@urlDraft}}
      @onInput={{@onUrlInput}}
      data-test-multi-image-source-url-input
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
          data-test-multi-image-source-url-add
        >
          Add
        </Button>
      </:after>
    </BoxelInputGroup>
  </form>
</template>;

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
              <Button
                @kind='text-only'
                @size='auto'
                class='thumb-pick'
                data-test-multi-image-source-thumb
                aria-label='Show this image'
                aria-pressed={{if (eq index this.selectedIndex) 'true' 'false'}}
                {{on 'click' (fn this.selectAt index)}}
              >
                {{#if item.resolvedUrl}}
                  <img src={{item.resolvedUrl}} alt='' />
                {{/if}}
              </Button>
              <Button
                @kind='text-only'
                @size='auto'
                class='remove-btn'
                aria-label='Remove image'
                data-test-multi-image-source-remove
                {{on 'click' (fn this.removeAt index)}}
              >
                <IconX width='8' height='8' aria-hidden='true' />
              </Button>
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

        <UrlAddForm
          @urlDraft={{this.urlDraft}}
          @onUrlInput={{this.onUrlInput}}
          @onSubmit={{this.addUrl}}
        />
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
            <UrlAddForm
              @urlDraft={{this.urlDraft}}
              @onUrlInput={{this.onUrlInput}}
              @onSubmit={{this.addUrl}}
            />
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
        /* accent deliberately skips the app's global --primary (the boxel
           highlight green would take over every control) — hosts/themes
           re-skin it through the --img-source-accent knob instead, exactly like
           the single-image editor's --boxel-purple */

        --img-accent-bg: color-mix(in oklch, var(--primary) 8%, transparent);
        /* the input group's focus ring reads var(--ring);
           re-point both locally so focus matches the accent instead of the
           app's global highlight green */
        --boxel-highlight: var(--primary);
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-2xs);
        background-color: var(--card);
        font-family: var(--font-sans);
        color: var(--card-foreground);
        border: 1px solid var(--border);
        border-radius: var(--boxel-radius);
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
        border-radius: var(--boxel-border-radius-sm);
        overflow: hidden;
        background-color: var(--card);
        color: var(--card-foreground);
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
        padding: 0.25rem 2px;
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
        border-radius: var(--boxel-border-radius-sm);
        border: 1px solid var(--border);
        background-color: var(--card);
        color: var(--card-foreground);
      }
      .thumb.is-active .thumb-pick img {
        border-color: var(--primary);
        box-shadow: 0 0 0 1px var(--primary);
      }
      .remove-btn {
        position: absolute;
        top: -0.25rem;
        right: -0.25rem;
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

      /* ── the linksTo editor's Link Image button, re-skinned exactly like
         the single field's file-link-btn ── */
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
      /* bar variant: fills the row under the previews, dashed like an
         add tile */
      .file-link-btn--bar :deep(.links-to-editor),
      .file-link-btn--bar :deep(.add-new.boxel-button) {
        width: 100%;
      }
      .file-link-btn--bar :deep(.add-new.boxel-button) {
        --boxel-button-border: 1px dashed var(--border);
      }
      .file-link-btn--bar :deep(.add-new.boxel-button:hover) {
        --boxel-button-border: 1px dashed var(--primary);
      }

      /* ── url row (compact: shrink the input group via its own tokens) ── */
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
      /* input suffix, not a nested pill — a left rule instead of its own
         rounded border avoids double corners inside the input group */
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
        gap: var(--boxel-sp-5xs);
        padding: var(--boxel-sp-xs);
        border: 1px dashed var(--border);
        border-radius: var(--boxel-border-radius-sm);
        background-color: transparent;
        font-family: var(--font-sans);
      }
      /* soft accent tile around the icon (the mock's rounded chip) */
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
      /* line — (or) — line, running the full height of the empty state */
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
      .error {
        margin: 0;
        font-size: var(--boxel-font-size-xs);
        color: var(--destructive-ink);
      }
    </style>
  </template>
}
