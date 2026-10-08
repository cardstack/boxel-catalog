import {
  FieldDef,
  field,
  contains,
  StringField,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import BooleanField from '@cardstack/base/boolean';
import UrlField from '@cardstack/base/url';
import { formatDuration } from '../../utils/file-metadata';
import { Component } from '@cardstack/base/card-api';

/**
 * Which frame stands for a video, and where that still came from.
 *
 * ### The gap this fills
 *
 * `base/video-metadata.ts` and the three video FileDefs (`mp4-video-def`,
 * `webm-video-def`, `mov-video-def`) carry duration, dimensions and encoding —
 * and **no poster concept at all**. A video with no poster falls back to the
 * family glyph, so a grid of videos reads as a grid of identical icons.
 *
 * ### Why a field and not a capture declaration
 *
 * The platform's `static screenshots: Record<string, ScreenshotSpec>` pipeline
 * already renders and stores captures, keyed by `'file-content'` so a
 * metadata-only edit skips re-encoding. Only `ImageDef` declares any.
 *
 * Declaring a `poster` slot on the video defs is the eventual fix, and it lives
 * in `packages/base`. This field is the part that does **not** require touching
 * base: it records *which* frame was chosen and *why*, which a capture
 * declaration does not express. `ScreenshotMetaEntry` tells you a capture's
 * url, hash and box; it cannot tell you that the frame was picked at 4.5s
 * because the first two seconds are a black fade.
 *
 * The two compose: once a slot exists, `posterUrl` here points at the capture
 * and `timestampSeconds` explains the choice.
 *
 * ### Deterministic by construction
 *
 * `timestampSeconds` is an exact seek, never "current frame". The capture
 * pipeline's own guidance is explicit about this: nondeterministic decoding
 * breaks nothing visibly, but every reindex captures "new" bytes, changing the
 * ETag so every viewer re-downloads an image that looks identical. A poster
 * defined by a timestamp is reproducible; one defined by "grab whatever is
 * showing" is not.
 */
export class VideoPosterMetadataField extends FieldDef {
  static displayName = 'Video Poster Metadata';

  @field timestampSeconds = contains(NumberField, {
    description:
      'Exact seek position for the frame. Never "current frame" — the capture must be reproducible.',
  });
  @field posterUrl = contains(UrlField, {
    description:
      'The still itself, once one exists. Points at a stored capture when the video def declares a poster slot.',
  });
  @field width = contains(NumberField);
  @field height = contains(NumberField);
  @field contentType = contains(StringField, {
    description: "Encoded type of the still: 'image/webp', 'image/jpeg'.",
  });

  // Why this frame. A human choice worth recording, because the next person
  // regenerating posters needs to know the first two seconds are a black fade.
  @field reason = contains(StringField);

  // Authored by a person, or produced by a rule. Distinguishing them stops a
  // bulk regeneration from silently overwriting a deliberate choice.
  @field isAuthored = contains(BooleanField);

  @field hasPoster = contains(BooleanField, {
    computeVia: function (this: VideoPosterMetadataField) {
      return Boolean(this.posterUrl);
    },
  });

  @field aspectRatio = contains(NumberField, {
    computeVia: function (this: VideoPosterMetadataField) {
      if (!this.width || !this.height) {
        return undefined;
      }
      return Number((this.width / this.height).toFixed(4));
    },
  });

  // mm:ss, so a caption can print the seek position without reformatting it.
  // Tabular by convention wherever it is rendered in a column.
  @field timestampLabel = contains(StringField, {
    computeVia: function (this: VideoPosterMetadataField) {
      return formatDuration(this.timestampSeconds);
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='poster'>
        <span class='ts'>{{if
            @model.timestampLabel
            @model.timestampLabel
            'no frame chosen'
          }}</span>
        <span class='meta'>
          {{#if @model.width}}{{@model.width}}×{{@model.height}}{{/if}}
          {{#if @model.isAuthored}} · chosen by hand{{/if}}
          {{#unless @model.hasPoster}} · not captured yet{{/unless}}
        </span>
        {{#if @model.reason}}
          <span class='why'>{{@model.reason}}</span>
        {{/if}}
      </div>
      <style scoped>
        .poster {
          display: flex;
          flex-direction: column;
          gap: 1px;
          color: var(--foreground);
        }
        .ts {
          font: 600 var(--boxel-font-sm);
          font-variant-numeric: tabular-nums;
        }
        .meta,
        .why {
          font: var(--boxel-font-xs);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };
}

export default VideoPosterMetadataField;
