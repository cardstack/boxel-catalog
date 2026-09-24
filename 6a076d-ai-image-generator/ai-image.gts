import {
  CardDef,
  Component,
  field,
  contains,
  linksTo,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import DateTimeField from '@cardstack/base/datetime';
import enumField from '@cardstack/base/enum';
import ImageDef from '@cardstack/base/image-file-def';
import AspectRatioField from '@cardstack/catalog/fields/aspect-ratio/aspect-ratio';
import SparklesIcon from '@cardstack/boxel-icons/sparkles';

export type AiImageMode = 'generate' | 'edit' | 'inpaint';

// Image-generation models served via the OpenRouter passthrough: the Google
// "Nano Banana" family plus the OpenAI GPT image family. The default
// (Gemini 2.5 Flash Image) is fast, cheap, and generally available; the
// others trade speed for fidelity.
// The gemini-3.x *-preview models are gated on Google Vertex and 404 in
// production unless the Vertex project is allowlisted. The OpenAI GPT image
// models likewise 404 unless the provider account has access. Gated models
// stay selectable for realms whose provider does have access.
const IMAGE_MODEL_OPTIONS = [
  {
    value: 'google/gemini-2.5-flash-image',
    label: 'Nano Banana — Gemini 2.5 Flash Image (default)',
  },
  {
    value: 'google/gemini-3.1-flash-image-preview',
    label: 'Nano Banana 2 — Gemini 3.1 Flash Image (preview)',
  },
  {
    value: 'google/gemini-3-pro-image-preview',
    label: 'Nano Banana Pro — Gemini 3 Pro Image (preview)',
  },
  {
    value: 'openai/gpt-5-image',
    label: 'GPT-5 Image',
  },
  {
    value: 'openai/gpt-5-image-mini',
    label: 'GPT-5 Image Mini',
  },
  {
    value: 'openai/gpt-5.4-image-2',
    label: 'GPT-5.4 Image 2',
  },
];

export const AiImageModelField = enumField(StringField, {
  options: IMAGE_MODEL_OPTIONS,
});

// How this image was produced. Constrained to the three modes so the value is
// always valid and the edit UI is a proper dropdown.
export const AiImageModeField = enumField(StringField, {
  options: [
    { value: 'generate', label: 'Generate' },
    { value: 'edit', label: 'Reprompt' },
    { value: 'inpaint', label: 'Inpaint' },
  ],
});

export function modeLabel(mode: string | null | undefined): string {
  switch (mode) {
    case 'edit':
      return 'Reprompt';
    case 'inpaint':
      return 'Inpaint';
    default:
      return 'Generate';
  }
}

// Compact, locale-aware timestamp for the history thread.
export function formatTime(value: Date | string | null | undefined): string {
  if (!value) return '';
  let d = value instanceof Date ? value : new Date(value);
  if (isNaN(d.getTime())) return '';
  return d.toLocaleString(undefined, {
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  });
}

// ---------------------------------------------------------------------------
// A single generated image — one entry in an AI Image Generator's history.
// Because each generation is its own card (not a containsMany field), the
// prompt, model, aspect ratio, and lineage are all recoverable, and any image
// can be referenced or reused on its own. `edit` / `inpaint` images link back
// to the `parent` they were derived from, forming a version tree.
// ---------------------------------------------------------------------------
class AiImageEmbedded extends Component<typeof AiImage> {
  <template>
    <div class='ai-image-piece'>
      {{#if @model.image.url}}
        <img
          class='piece-image'
          src={{@model.image.url}}
          alt={{@model.prompt}}
          loading='lazy'
        />
      {{else}}
        <div class='piece-placeholder'><SparklesIcon /></div>
      {{/if}}
      <div class='piece-body'>
        <span class='piece-badge badge-{{@model.mode}}'>{{modeLabel
            @model.mode
          }}</span>
        <p class='piece-prompt'>{{if
            @model.prompt
            @model.prompt
            'AI image'
          }}</p>
        {{#if @model.createdAt}}
          <time class='piece-when'>{{formatTime @model.createdAt}}</time>
        {{/if}}
      </div>
    </div>
    <style scoped>
      .ai-image-piece {
        --c-fg: var(--card-foreground);
        container-type: inline-size;
        display: flex;
        flex-direction: column;
        height: 100%;
        min-height: 0;
        border-radius: var(--radius);
        overflow: hidden;
        background-color: var(--card);
        color: var(--card-foreground);
      }
      .piece-image {
        width: 100%;
        flex: 1 1 auto;
        min-height: 0;
        object-fit: cover;
        display: block;
      }
      .piece-placeholder {
        display: flex;
        align-items: center;
        justify-content: center;
        flex: 1 1 auto;
        color: var(--muted-foreground);
        background-color: var(--border);
      }
      .piece-body {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xxs);
        padding: var(--boxel-sp-xs);
        border-top: 1px solid var(--border);
      }
      .piece-badge {
        flex-shrink: 0;
        font-size: var(--boxel-font-size-xs);
        font-weight: 600;
        border-radius: var(--boxel-border-radius-sm);
        padding: 2px var(--boxel-sp-xxs);
        background-color: color-mix(in oklch, var(--c-fg) 10%, transparent);
        color: var(--c-fg);
      }
      .badge-inpaint {
        background-color: color-mix(in oklch, var(--warning) 16%, transparent);
        color: color-mix(in oklch, var(--warning-ink), var(--c-fg) 40%);
      }
      .badge-edit {
        background-color: color-mix(in oklch, var(--primary) 14%, transparent);
        color: color-mix(in oklch, var(--primary-ink), var(--c-fg) 40%);
      }
      .piece-prompt {
        flex: 1 1 auto;
        margin: 0;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        font-size: var(--boxel-font-size-sm);
        color: var(--c-fg);
      }
      .piece-when {
        flex-shrink: 0;
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
    </style>
  </template>
}

class AiImageIsolated extends Component<typeof AiImage> {
  <template>
    <div class='ai-image-detail'>
      {{#if @model.image.url}}
        <img
          class='detail-image'
          src={{@model.image.url}}
          alt={{@model.prompt}}
        />
      {{else}}
        <div class='detail-placeholder'><SparklesIcon /></div>
      {{/if}}
      <div class='detail-meta'>
        <span class='piece-badge badge-{{@model.mode}}'>{{modeLabel
            @model.mode
          }}</span>
        {{#if @model.createdAt}}
          <time class='detail-when'>{{formatTime @model.createdAt}}</time>
        {{/if}}
      </div>
      <p class='detail-prompt'>{{@model.prompt}}</p>
      <dl class='detail-record'>
        {{#if @model.llmModel}}
          <dt>Model</dt>
          <dd>{{@model.llmModel}}</dd>
        {{/if}}
        {{#if @model.aspectRatio}}
          <dt>Aspect ratio</dt>
          <dd>{{@model.aspectRatio}}</dd>
        {{/if}}
      </dl>
      {{#if @model.mask.url}}
        <div class='detail-mask'>
          <span class='detail-record-label'>Inpaint mask</span>
          <img
            class='detail-mask-image'
            src={{@model.mask.url}}
            alt='Inpaint mask — white regions were repainted'
            loading='lazy'
          />
        </div>
      {{/if}}
      {{#if @model.parent}}
        <div class='detail-parent'>
          <span class='detail-parent-label'>Edited from</span>
          <@fields.parent @format='atom' />
        </div>
      {{/if}}
    </div>
    <style scoped>
      .ai-image-detail {
        --c-fg: var(--card-foreground);
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
        height: 100%;
        padding: var(--boxel-sp);
        overflow-y: auto;
        background-color: var(--card);
        color: var(--c-fg);
        font: var(--boxel-font-sm);
        font-family: var(--font-sans);
      }
      .detail-image {
        max-width: 40rem;
        width: 100%;
        border-radius: var(--radius);
        border: 1px solid var(--border);
      }
      .detail-placeholder {
        display: grid;
        place-items: center;
        aspect-ratio: 16 / 9;
        max-width: 40rem;
        border-radius: var(--radius);
        background-color: var(--border);
        color: var(--muted-foreground);
      }
      .detail-meta {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xxs);
      }
      .piece-badge {
        font-size: var(--boxel-font-size-xs);
        font-weight: 600;
        border-radius: var(--boxel-border-radius-sm);
        padding: 2px var(--boxel-sp-xxs);
        background-color: color-mix(in oklch, var(--c-fg) 10%, transparent);
        color: var(--c-fg);
      }
      .badge-inpaint {
        background-color: color-mix(in oklch, var(--warning) 16%, transparent);
        color: color-mix(in oklch, var(--warning-ink), var(--c-fg) 40%);
      }
      .badge-edit {
        background-color: color-mix(in oklch, var(--primary) 14%, transparent);
        color: color-mix(in oklch, var(--primary-ink), var(--c-fg) 40%);
      }
      .detail-when {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
      .detail-prompt {
        margin: 0;
        font-size: var(--boxel-font-size);
      }
      .detail-parent {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xxs);
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
      .detail-record {
        display: grid;
        grid-template-columns: max-content 1fr;
        gap: var(--boxel-sp-5xs) var(--boxel-sp-xs);
        margin: 0;
        font-size: var(--boxel-font-size-xs);
      }
      .detail-record dt {
        font-weight: 600;
        color: var(--muted-foreground);
      }
      .detail-record dd {
        margin: 0;
        overflow-wrap: anywhere;
      }
      .detail-record-label {
        font-size: var(--boxel-font-size-xs);
        font-weight: 600;
        color: var(--muted-foreground);
      }
      .detail-mask {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-4xs);
      }
      .detail-mask-image {
        max-width: 10rem;
        border-radius: var(--boxel-border-radius-sm);
        border: 1px solid var(--border);
        /* The mask's black pixels mean "keep" — always render on black. */
        background-color: var(--card);
        color: var(--card-foreground);
      }
    </style>
  </template>
}

export class AiImage extends CardDef {
  static displayName = 'AI Image';
  static icon = SparklesIcon;

  @field prompt = contains(StringField);
  @field mode = contains(AiImageModeField); // 'generate' | 'edit' | 'inpaint'
  // The persisted webp, wrapped as an ImageDef so it can be previewed and
  // reused anywhere a linked image is accepted.
  @field image = linksTo(() => ImageDef);
  // The image this one was derived from (edit / inpaint). Forms a version tree.
  @field parent = linksTo(() => AiImage);
  // The painted inpaint mask (white = repaint, black = keep), persisted as its
  // own realm file so the record shows WHERE the repaint happened.
  @field mask = linksTo(() => ImageDef);
  // Settings that produced this image, kept per-image for traceability.
  @field llmModel = contains(AiImageModelField);
  @field aspectRatio = contains(AspectRatioField);
  @field createdAt = contains(DateTimeField);

  static embedded = AiImageEmbedded;
  static fitted = AiImageEmbedded;
  static isolated = AiImageIsolated;
}
