import Component from '@glimmer/component';
import type { BoxComponent } from 'https://cardstack.com/base/card-api';
import { fn } from '@ember/helper';
import { on } from '@ember/modifier';
import { eq } from '@cardstack/boxel-ui/helpers';
import { BoxelInputGroup, IconButton } from '@cardstack/boxel-ui/components';
import {
  File,
  IconMinusCircle,
  IconLink,
  Upload,
} from '@cardstack/boxel-ui/icons';

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

export default class ImageSourceEditor extends Component<ImageSourceEditorSignature> {
  get sourceMode(): ImageSourceMode {
    return selectedSourceMode(
      this.args.model?.sourceMode,
      this.args.model?.url,
    );
  }

  switchTo = (mode: ImageSourceMode) => {
    this.args.model.sourceMode = mode;
  };

  onUrlChange = (val: string) => {
    this.args.model.url = val;
  };

  onFileRemove = () => {
    this.args.model.file = undefined;
  };

  get hasFile() {
    return Boolean(this.filePreviewSrc);
  }

  get hasUrl() {
    return Boolean(this.args.model?.url);
  }

  get imageUrl() {
    return this.args.model?.url ?? '';
  }

  get filePreviewSrc() {
    return this.args.model?.file?.url ?? '';
  }

  <template>
    <div class='image-source-root' data-test-image-source-edit>
      <div class='editor' data-test-image-source-editor>
        {{! template-lint-disable require-presentational-children }}
        <div class='seg' role='tablist'>
          <button
            type='button'
            role='tab'
            id='tab-file'
            aria-controls='panel-file'
            class='seg-btn {{if (eq this.sourceMode "file") "is-active"}}'
            aria-selected={{if (eq this.sourceMode 'file') 'true' 'false'}}
            data-test-image-source-file-tab
            {{on 'click' (fn this.switchTo 'file')}}
          >
            <File width='13' height='13' aria-hidden='true' />
            File
          </button>
          <button
            type='button'
            role='tab'
            id='tab-url'
            aria-controls='panel-url'
            class='seg-btn {{if (eq this.sourceMode "url") "is-active"}}'
            aria-selected={{if (eq this.sourceMode 'url') 'true' 'false'}}
            data-test-image-source-url-tab
            {{on 'click' (fn this.switchTo 'url')}}
          >
            <IconLink width='13' height='13' aria-hidden='true' />
            URL
          </button>
        </div>
        {{! template-lint-enable require-presentational-children }}

        {{#if (eq this.sourceMode 'url')}}
          <div
            role='tabpanel'
            id='panel-url'
            aria-labelledby='tab-url'
            tabindex='0'
            class='panel'
            data-test-image-source-url-panel
          >
            <BoxelInputGroup
              id='url-input'
              aria-label='Image URL'
              @placeholder='https://example.com/image.jpg'
              @value={{this.imageUrl}}
              @onInput={{this.onUrlChange}}
              data-test-image-source-url-input
            >
              <:before as |Accessories|>
                <Accessories.Text>
                  <IconLink width='15' height='15' aria-hidden='true' />
                </Accessories.Text>
              </:before>
            </BoxelInputGroup>

            {{#if this.hasUrl}}
              <figure class='media-box' data-test-image-source-url-preview>
                <img src={{this.imageUrl}} alt='' />
              </figure>
            {{/if}}
          </div>
        {{else}}
          <div
            role='tabpanel'
            id='panel-file'
            aria-labelledby='tab-file'
            tabindex='0'
            class='panel'
            data-test-image-source-file-panel
          >
            {{#if this.hasFile}}
              <figure class='media-box' data-test-image-source-file-preview>
                <IconButton
                  @icon={{IconMinusCircle}}
                  @width='22'
                  @height='22'
                  class='remove-btn'
                  {{on 'click' this.onFileRemove}}
                  aria-label='Remove image file'
                  data-test-image-source-file-remove
                />
                <img src={{this.filePreviewSrc}} alt='' />
              </figure>
            {{else}}
              <div class='media-box media-box--empty'>
                <Upload
                  class='empty-icon'
                  width='18'
                  height='18'
                  aria-hidden='true'
                />
                <span class='empty-hint'>Link an image file</span>
                <div class='file-link-btn' data-test-image-source-file-field>
                  <@fileField />
                </div>
              </div>
            {{/if}}
          </div>
        {{/if}}
      </div>
    </div>

    <style scoped>
      .image-source-root {
        /* Accent inherits the surrounding theme when a host sets
           --image-source-accent; falls back to the Boxel highlight. */
        --accent: var(--image-source-accent, var(--boxel-highlight, #635bff));
        --edge: var(--boxel-border-color, #e0e0e5);
        display: block;
        max-width: 340px;
        font-family: var(--boxel-font-family, sans-serif);
        color: var(--boxel-700, #272330);
      }

      .editor {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
      }

      .seg {
        display: inline-flex;
        align-self: start;
        gap: 2px;
        padding: 3px;
        border: 1px solid var(--edge);
        border-radius: 999px;
        background: var(--boxel-100, #f6f5f9);
      }

      .seg-btn {
        display: inline-flex;
        align-items: center;
        gap: var(--boxel-sp-3xs);
        padding: 5px 13px;
        border: none;
        border-radius: 999px;
        background: transparent;
        color: var(--boxel-450, #92929b);
        font-family: var(--boxel-font-family, sans-serif);
        font-size: var(--boxel-font-size-xs, 12px);
        font-weight: 500;
        line-height: 1;
        cursor: pointer;
        transition:
          background 0.15s,
          color 0.15s;
        --icon-color: currentColor;
      }

      .seg-btn svg {
        flex-shrink: 0;
      }

      .seg-btn.is-active {
        background: var(--boxel-light, #fff);
        color: var(--accent);
        box-shadow: 0 1px 2px rgba(0, 0, 0, 0.09);
        --icon-color: var(--accent);
      }

      .panel {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-2xs);
      }

      .panel :deep(.text-accessory),
      .panel :deep(.text-accessory svg) {
        --icon-color: var(--accent);
        color: var(--accent);
      }

      .media-box {
        position: relative;
        margin: 0;
        width: 100%;
        height: 120px;
        display: flex;
        align-items: center;
        justify-content: center;
        border: 1px solid var(--edge);
        border-radius: var(--boxel-border-radius, 8px);
        overflow: hidden;
        background: var(--boxel-100, #f6f5f9);
      }

      .media-box img {
        width: 100%;
        height: 100%;
        object-fit: cover;
      }

      .media-box--empty {
        flex-direction: column;
        gap: var(--boxel-sp-3xs);
        padding: var(--boxel-sp-sm);
        border-style: dashed;
        border-color: var(--accent);
        text-align: center;
      }

      .empty-icon {
        --icon-color: var(--accent);
        color: var(--accent);
        opacity: 0.6;
      }

      .empty-hint {
        font-size: var(--boxel-font-size-xs, 12px);
        color: var(--boxel-450, #92929b);
      }

      .remove-btn {
        --icon-color: var(--boxel-light, #fff);
        --icon-border: var(--boxel-dark, #000);
        --icon-bg: var(--boxel-dark, #000);
        --boxel-icon-button-width: var(--boxel-icon-sm, 1.25rem);
        --boxel-icon-button-height: var(--boxel-icon-sm, 1.25rem);
        position: absolute;
        top: 5px;
        right: 5px;
        z-index: 1;
        border: 2px solid var(--boxel-light, #fff);
        border-radius: 50%;
        box-shadow: 0 0 6px var(--boxel-500, #5a586a);
        outline: 0;
      }

      .remove-btn:hover,
      .remove-btn:focus {
        --icon-bg: var(--boxel-danger, #ff5050);
        --icon-border: var(--boxel-danger, #ff5050);
      }

      .file-link-btn :deep(.links-to-editor) {
        display: flex;
        justify-content: center;
      }

      .file-link-btn :deep(.add-new.boxel-button) {
        --boxel-button-text-color: var(--accent);
        --boxel-button-color: transparent;
        --boxel-button-border: 1px solid var(--accent);
        --boxel-button-padding: var(--boxel-sp-5xs) var(--boxel-sp-xs);
        font-size: var(--boxel-font-size-xs, 12px);
        font-weight: 500;
        letter-spacing: 0;
        border-radius: var(--boxel-border-radius-sm, 6px);
        width: auto;
        height: auto;
      }

      .file-link-btn :deep(.add-new.boxel-button:hover) {
        --boxel-button-color: color-mix(in srgb, var(--accent) 8%, transparent);
      }
    </style>
  </template>
}
