import {
  CardDef,
  field,
  contains,
  containsMany,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';
import { Command } from '@cardstack/runtime-common';

import {
  ANALYZE_SYSTEM_PROMPT,
  VISION_MODEL,
  requestSpec,
  parseAnalysisJson,
} from '../util/generation';
import { fetchAsDataUrl } from '../util/realm-image';

// Stage 1 of the image-to-3D pipeline as its own command: study the
// reference view(s) and produce the construction plan (object type/class,
// per-part plan with measured bboxes, camera estimate, identity features,
// build recipe). Splitting it out makes the plan an inspectable, reusable
// artifact — the studio persists it, a human can review or correct it
// before the spec stage runs, an AI-assistant skill can call it as a tool,
// and a bad plan can be re-run without re-running the whole generation.

class AnalyzeReferenceInput extends CardDef {
  // Resolved reference image URLs, primary view first (up to 6 are used).
  @field imageUrls = containsMany(StringField);
  // OpenRouter vision model id; defaults to the studio's standard model.
  @field model = contains(StringField);
}

class AnalyzeReferenceOutput extends CardDef {
  // The full analysis document, verbatim — feed this to the spec stage.
  @field analysisJson = contains(StringField);
  // Headline facts, surfaced for logging / quick inspection.
  @field objectType = contains(StringField);
  @field objectClass = contains(StringField);
  @field partCount = contains(NumberField);
  @field identityFeatures = containsMany(StringField);
}

export class AnalyzeReferenceCommand extends Command<
  typeof AnalyzeReferenceInput,
  typeof AnalyzeReferenceOutput
> {
  static actionVerb = 'Analyze';
  static displayName = 'Analyze Reference Images';

  async getInputType() {
    return AnalyzeReferenceInput;
  }

  protected async run(
    input: AnalyzeReferenceInput,
  ): Promise<AnalyzeReferenceOutput> {
    let urls = (input.imageUrls ?? []).filter(Boolean).slice(0, 6);
    if (!urls.length) {
      throw new Error('At least one reference image URL is required.');
    }

    let imageParts = await Promise.all(
      urls.map(async (url) => ({
        type: 'image_url',
        image_url: { url: await fetchAsDataUrl(url) },
      })),
    );

    let analysis = await requestSpec(
      this.commandContext,
      input.model || VISION_MODEL,
      ANALYZE_SYSTEM_PROMPT,
      [
        {
          type: 'text',
          text: 'Analyze the object in these reference view(s) and write the construction plan.',
        },
        ...imageParts,
      ],
      undefined,
      parseAnalysisJson,
    );

    return new AnalyzeReferenceOutput({
      analysisJson: JSON.stringify(analysis),
      objectType: analysis.objectType ?? '',
      objectClass: analysis.objectClass ?? '',
      partCount: analysis.partPlan?.length ?? 0,
      identityFeatures: analysis.identityFeatures ?? [],
    });
  }
}
