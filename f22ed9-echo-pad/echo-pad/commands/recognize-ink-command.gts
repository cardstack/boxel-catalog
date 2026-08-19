import { CardDef, contains, field } from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import { Command } from '@cardstack/runtime-common';
import SendRequestViaProxyCommand from '@cardstack/boxel-host/commands/send-request-via-proxy';

import {
  asEchoMode,
  buildEchoPrompt,
  echoCacheKey,
  splitEchoResponse,
} from '../utils/index';

export class RecognizeInkInput extends CardDef {
  @field imageDataUrl = contains(StringField); // ephemeral PNG crop of the lassoed region, never persisted
  @field mode = contains(StringField);
  @field boardName = contains(StringField);
  // the marker's prose, read from the bundled Skill card by the board (a plain
  // realm Command has no store access); empty falls back to the local grammar
  @field instructions = contains(StringField);
}

export class RecognizeInkOutput extends CardDef {
  @field content = contains(StringField);
  @field mode = contains(StringField);
  @field sketchJson = contains(StringField); // polylines the model drew back, if any
  @field sceneJson = contains(StringField); // validated manim scene spec, if any
}

const VISION_MODEL = 'anthropic/claude-sonnet-5';
const CACHE_LIMIT = 24;
// Identical ink + mode must never be paid for twice: the region hash keys a
// small LRU of responses for the session.
const echoCache = new Map<
  string,
  { content: string; sketchJson: string; sceneJson: string }
>();

export class RecognizeInkCommand extends Command<
  typeof RecognizeInkInput,
  typeof RecognizeInkOutput
> {
  static actionVerb = 'Read';
  static displayName = 'Read Circled Ink';

  async getInputType() {
    return RecognizeInkInput;
  }

  protected async run(input: RecognizeInkInput): Promise<RecognizeInkOutput> {
    let { imageDataUrl, mode, boardName, instructions } = input;
    if (!imageDataUrl?.startsWith('data:image/')) {
      throw new Error('No ink image was captured.');
    }
    let modeKey = asEchoMode(mode);

    let cacheKey = echoCacheKey(imageDataUrl, modeKey, instructions ?? '');
    let hit = echoCache.get(cacheKey);
    if (hit) {
      // refresh recency
      echoCache.delete(cacheKey);
      echoCache.set(cacheKey, hit);
      let cached = new RecognizeInkOutput();
      cached.content = hit.content;
      cached.mode = modeKey;
      cached.sketchJson = hit.sketchJson;
      cached.sceneJson = hit.sceneJson;
      return cached;
    }

    let promptText =
      instructions && instructions.trim().length > 40
        ? `${instructions.trim()}\n\nMode: ${modeKey}.${
            boardName ? ` The board is titled "${boardName}".` : ''
          }`
        : buildEchoPrompt(modeKey, boardName);

    let result = await new SendRequestViaProxyCommand(
      this.commandContext,
    ).execute({
      url: 'https://openrouter.ai/api/v1/chat/completions',
      method: 'POST',
      requestBody: JSON.stringify({
        model: VISION_MODEL,
        messages: [
          {
            role: 'user',
            content: [
              { type: 'text', text: promptText },
              { type: 'image_url', image_url: { url: imageDataUrl } },
            ],
          },
        ],
      }),
    });

    if (!result.response.ok) {
      let body = '';
      try {
        body = await result.response.text();
      } catch {
        // fall through to statusText
      }
      throw new Error(
        `Echo request failed (${result.response.status}): ${
          body || result.response.statusText
        }`,
      );
    }

    let data = await result.response.json();
    let split = splitEchoResponse(data?.choices?.[0]?.message?.content);
    if (!split.text && !split.polylines && !split.labels && !split.scene) {
      throw new Error('The model returned an empty annotation.');
    }

    let output = new RecognizeInkOutput();
    output.content = split.text ?? '';
    output.mode = modeKey;
    output.sketchJson =
      split.polylines || split.labels
        ? JSON.stringify({
            polylines: split.polylines ?? [],
            labels: split.labels ?? [],
          })
        : '';
    output.sceneJson = split.scene ? JSON.stringify(split.scene) : '';

    echoCache.set(cacheKey, {
      content: output.content,
      sketchJson: output.sketchJson,
      sceneJson: output.sceneJson,
    });
    if (echoCache.size > CACHE_LIMIT) {
      echoCache.delete(echoCache.keys().next().value as string);
    }
    return output;
  }
}
