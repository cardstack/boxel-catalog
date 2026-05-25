import Component from '@glimmer/component';
import SparkleIcon from '@cardstack/boxel-icons/sparkle';
import type { BoxComponent } from 'https://cardstack.com/base/card-api';
import { fn } from '@ember/helper';
import { on } from '@ember/modifier';
import { eq } from '@cardstack/boxel-ui/helpers';
import {
  BoxelInputGroup,
  IconButton,
  Pill,
} from '@cardstack/boxel-ui/components';
import {
  File,
  IconMinusCircle,
  IconLink,
  ImagePlaceholder,
  Upload,
} from '@cardstack/boxel-ui/icons';

import type { ImageSourceMode } from '../../image-source';
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

  get defaultSourceLabel() {
    return this.sourceMode === 'url' ? 'Default: URL' : 'Default: File Upload';
  }

  <template>
    <div class='image-source-root' data-test-image-source-edit>
      <div class='editor' data-test-image-source-editor>
        <header class='header header--static'>
          <div class='header-text'>
            <span class='title'>Image source</span>
            <span class='description'>Choose where the image comes from.</span>
          </div>
          <Pill @tag='span' aria-hidden='true' class='default-pill'>
            <:iconLeft>
              <SparkleIcon width='10' height='10' />
            </:iconLeft>
            <:default>{{this.defaultSourceLabel}}</:default>
          </Pill>
        </header>

        <div class='body'>
          {{! template-lint-disable require-presentational-children }}
          <div class='tabs' role='tablist'>
            <button
              type='button'
              role='tab'
              id='tab-file'
              aria-controls='panel-file'
              class='tab {{if (eq this.sourceMode "file") "tab--active"}}'
              aria-selected={{if (eq this.sourceMode 'file') 'true' 'false'}}
              data-test-image-source-file-tab
              {{on 'click' (fn this.switchTo 'file')}}
            >
              <span class='tab-content'>
                <File width='14' height='14' aria-hidden='true' />
                File Upload
              </span>
            </button>
            <button
              type='button'
              role='tab'
              id='tab-url'
              aria-controls='panel-url'
              class='tab {{if (eq this.sourceMode "url") "tab--active"}}'
              aria-selected={{if (eq this.sourceMode 'url') 'true' 'false'}}
              data-test-image-source-url-tab
              {{on 'click' (fn this.switchTo 'url')}}
            >
              <span class='tab-content'>
                <IconLink width='14' height='14' aria-hidden='true' />
                URL
              </span>
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
              <label class='field-label' for='url-input'>URL (Image)</label>
              <BoxelInputGroup
                id='url-input'
                @placeholder='https://example.com/image.jpg'
                @value={{this.imageUrl}}
                @onInput={{this.onUrlChange}}
                data-test-image-source-url-input
              >
                <:before as |Accessories|>
                  <Accessories.Text>
                    <IconLink width='16' height='16' aria-hidden='true' />
                  </Accessories.Text>
                </:before>
              </BoxelInputGroup>

              <div class='preview-header'>
                <span class='field-label'>Preview</span>
                <span class='badge'>Optional</span>
              </div>
              {{#if this.hasUrl}}
                <figure class='media-box' data-test-image-source-url-preview>
                  <img src={{this.imageUrl}} alt='' />
                </figure>
              {{else}}
                <div class='media-box media-box--empty'>
                  <ImagePlaceholder
                    class='empty-icon'
                    width='30'
                    height='30'
                    aria-hidden='true'
                  />
                  <p class='empty-title'>No image to preview</p>
                  <p class='empty-hint'>Enter a URL above to see a preview</p>
                </div>
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
              <span class='field-label'>File (Image)</span>
              {{#if this.hasFile}}
                <figure class='media-box' data-test-image-source-file-preview>
                  <IconButton
                    @icon={{IconMinusCircle}}
                    @width='24'
                    @height='24'
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
                    width='20'
                    height='20'
                    aria-hidden='true'
                  />
                  <p class='empty-title'>No file linked</p>
                  <p class='empty-hint'>Link an image file to get started</p>
                  <div class='file-link-btn' data-test-image-source-file-field>
                    <@fileField />
                  </div>
                </div>
              {{/if}}
            </div>
          {{/if}}
        </div>
      </div>
    </div>

    <style scoped>
      .image-source-root {
        --accent: var(--boxel-purple, #6638ff);
        --accent-bg: color-mix(
          in srgb,
          var(--boxel-purple, #6638ff) 8%,
          transparent
        );

        background: var(--boxel-light, #fff);
        font-family: var(--boxel-font-family, sans-serif);
        color: var(--boxel-700, #272330);
        border: 1px solid var(--boxel-border-color, #d3d3d3);
        border-radius: var(--boxel-radius, 10px);
        overflow: hidden;
      }

      .editor {
        background: transparent;
      }

      .header {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp-sm) var(--boxel-sp);
        border-bottom: 1px solid var(--boxel-border-color, #d3d3d3);
      }

      .header--static {
        cursor: default;
      }

      .header-text {
        flex: 1;
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-6xs);
      }

      .title {
        font-size: var(--boxel-font-size-sm, 14px);
        font-weight: 600;
        color: var(--boxel-700, #272330);
        line-height: 1.4;
      }

      .description {
        font-size: var(--boxel-font-size-xs, 12px);
        color: var(--boxel-400, #afafb7);
        line-height: 1.4;
      }

      .default-pill {
        --boxel-pill-background-color: color-mix(
          in srgb,
          var(--boxel-purple, #6638ff) 12%,
          transparent
        );
        --boxel-pill-font-color: var(--accent, #6638ff);
        --boxel-pill-border-color: transparent;
        --icon-color: var(--accent, #6638ff);
        font-size: var(--boxel-font-size-xs, 12px);
      }

      .body {
        padding: var(--boxel-sp);
        padding-right: var(--boxel-sp-lg);
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-sm);
      }

      .tabs {
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: var(--boxel-sp-2xs);
      }

      .tab {
        display: flex;
        align-items: center;
        justify-content: center;
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        border: 1px solid var(--boxel-border-color, #d3d3d3);
        border-radius: var(--boxel-border-radius-sm, 6px);
        background: transparent;
        color: var(--boxel-400, #afafb7);
        font-size: var(--boxel-font-size-sm, 14px);
        font-weight: 500;
        font-family: var(--boxel-font-family, sans-serif);
        cursor: pointer;
        transition:
          background 0.15s,
          border-color 0.15s,
          color 0.15s;
      }

      .tab svg {
        flex-shrink: 0;
      }

      .tab:hover:not(.tab--active) {
        background: var(--boxel-100, #f8f7fa);
        color: var(--boxel-700, #272330);
      }

      .tab--active {
        background: var(
          --accent-bg,
          color-mix(in srgb, #6638ff 8%, transparent)
        );
        border-color: var(--accent, #6638ff);
        color: var(--accent, #6638ff);
        --icon-color: var(--accent, #6638ff);
      }

      .tab-content {
        display: inline-flex;
        align-items: center;
        gap: var(--boxel-sp-3xs);
        flex-wrap: wrap;
      }

      .panel {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
      }

      .field-label {
        font-size: var(--boxel-font-size-sm, 14px);
        font-weight: 600;
        color: var(--boxel-700, #272330);
      }

      .panel :deep(.text-accessory) {
        --icon-color: var(--accent, #6638ff);
        color: var(--accent, #6638ff);
      }

      .panel :deep(.text-accessory svg) {
        --icon-color: var(--accent, #6638ff);
        color: var(--accent, #6638ff);
        display: block;
      }

      .preview-header {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        margin-top: var(--boxel-sp-2xs);
      }

      .badge {
        display: inline-block;
        padding: var(--boxel-sp-6xs) var(--boxel-sp-xs);
        border-radius: 999px;
        border: 1px solid var(--boxel-border-color, #d3d3d3);
        font-size: var(--boxel-font-size-2xs, 11px);
        font-weight: 500;
        color: var(--boxel-400, #afafb7);
      }

      .media-box {
        margin: 0;
        width: 100%;
        height: 180px;
        position: relative;
        border-radius: var(--boxel-border-radius, 10px);
        overflow: hidden;
        border: 1px solid var(--boxel-border-color, #d3d3d3);
        background: var(--boxel-100, #f8f7fa);
        flex: none;
        display: flex;
        align-items: center;
        justify-content: center;
      }

      .remove-btn {
        --icon-color: var(--background, var(--boxel-light, #fff));
        --icon-border: var(--foreground, var(--boxel-dark, #000));
        --icon-bg: var(--foreground, var(--boxel-dark, #000));
        --boxel-icon-button-width: var(--boxel-icon-sm, 1.25rem);
        --boxel-icon-button-height: var(--boxel-icon-sm, 1.25rem);
        position: absolute;
        top: 5px;
        right: 5px;
        z-index: 1;
        border: 2px solid var(--boxel-light, #fff);
        border-radius: 50%;
        box-shadow: 0px 0px 6px var(--boxel-500, #5a586a);
        outline: 0;
      }

      .remove-btn:hover,
      .remove-btn:focus {
        --icon-bg: var(--boxel-danger, #ff5050);
        --icon-border: var(--boxel-danger, #ff5050);
      }

      .media-box--empty {
        border-style: dashed;
        border-color: var(--accent, #6638ff);
        color: var(--accent, #6638ff);
        flex-direction: column;
        gap: 0;
        padding: var(--boxel-sp-sm) var(--boxel-sp);
        text-align: center;
      }

      .empty-icon {
        --icon-color: var(--accent, #6638ff);
        color: var(--accent, #6638ff);
        opacity: 0.6;
      }

      .empty-title {
        margin: 0;
        font-size: var(--boxel-font-size-sm, 14px);
        font-weight: 600;
        color: var(--boxel-700, #272330);
        margin-top: var(--boxel-sp-xs);
      }

      .empty-hint {
        margin: 0;
        font-size: var(--boxel-font-size-xs, 12px);
        color: var(--boxel-400, #afafb7);
        margin-top: var(--boxel-sp-3xs);
      }

      .file-link-btn {
        margin-top: var(--boxel-sp-xs);
      }

      .file-link-btn :deep(.links-to-editor) {
        display: flex;
        justify-content: center;
      }

      .file-link-btn :deep(.add-new.boxel-button) {
        --boxel-button-text-color: var(--accent, #6638ff);
        --boxel-button-color: transparent;
        --boxel-button-border: 1px solid var(--accent, #6638ff);
        --boxel-button-padding: var(--boxel-sp-2xs) var(--boxel-sp-sm);
        font-size: var(--boxel-font-size-xs, 12px);
        font-weight: 500;
        letter-spacing: 0;
        border-radius: var(--boxel-border-radius-sm, 6px);
        width: auto;
        height: auto;
      }

      .file-link-btn :deep(.add-new.boxel-button:hover) {
        --boxel-button-color: var(
          --accent-bg,
          color-mix(in srgb, #6638ff 8%, transparent)
        );
      }
    </style>
  </template>
}
