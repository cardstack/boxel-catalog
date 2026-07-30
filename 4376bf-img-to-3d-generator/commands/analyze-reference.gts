import {
  CardDef,
  field,
  contains,
  containsMany,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';
import enumField from 'https://cardstack.com/base/enum';
import { Command } from '@cardstack/runtime-common';

import { parseAnalysisJson } from '../util/spec-io';
import {
  VISION_MODEL,
  VISION_MODEL_OPTIONS,
  requestSpec,
  seedFromStrings,
} from '../util/llm-request';
import { ANALYZE_SYSTEM_PROMPT } from '../prompts/analyze';
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
  @field model = contains(
    enumField(StringField, {
      options: VISION_MODEL_OPTIONS,
      displayName: 'Vision Model',
    }),
  );
  // Longest-edge cap for the reference images this stage sends. Analysis is
  // pure structural perception, so a smaller cap trims input vision tokens and
  // speeds the stage up; left unset it falls back to the shared vision cap.
  @field maxEdge = contains(NumberField);
}

class AnalyzeReferenceOutput extends CardDef {
  // The full analysis document, verbatim — feed this to the spec stage.
  @field analysisJson = contains(StringField);
  // Headline facts, surfaced for logging / quick inspection.
  @field objectType = contains(StringField);
  @field objectClass = contains(StringField);
  // recommended build backend ("primitive" | "mesh") + a one-line reason, so a
  // caller can route (or warn) without re-parsing the full analysis document.
  @field buildBackend = contains(StringField);
  @field backendReason = contains(StringField);
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
        image_url: {
          url: await fetchAsDataUrl(url, {
            maxEdge: input.maxEdge || undefined,
            commandContext: this.commandContext,
          }),
        },
      })),
    );

    // the analysis is the gate for everything downstream (object type, part
    // count, bboxes, revolved flags), so it is the stage that must not drift:
    // the seed comes from the reference URLs, not from chance, so re-running
    // this command on one photo set reproduces the same plan.
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
      // analysis is pure structural perception. This model MAKES reasoning
      // mandatory (disabling it 400s), so instead push the thinking budget to
      // the floor — the stage was measured at ~29s with default reasoning.
      { seed: seedFromStrings(urls), reasoning: { effort: 'low' } },
    );

    return new AnalyzeReferenceOutput({
      analysisJson: JSON.stringify(analysis),
      objectType: analysis.objectType ?? '',
      objectClass: analysis.objectClass ?? '',
      buildBackend: analysis.buildBackend ?? '',
      backendReason: analysis.backendReason ?? '',
      partCount: analysis.partPlan?.length ?? 0,
      identityFeatures: analysis.identityFeatures ?? [],
    });
  }
}
