import {
  CardDef,
  contains,
  containsMany,
  field,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import BooleanField from '@cardstack/base/boolean';
import { Command } from '@cardstack/runtime-common';
import SendRequestViaProxyCommand from '@cardstack/boxel-host/commands/send-request-via-proxy';
import ReadBinaryFileCommand from '@cardstack/boxel-host/commands/read-binary-file';
import { isoDayOf } from '../claim-logic';
import {
  DEFAULT_SCAN_MODEL,
  SCAN_MAX_EDGE,
  parseReceiptRead,
  readerError,
  replyText,
  scanPrompt,
} from '../scan-logic';

export class ReadReceiptInput extends CardDef {
  static displayName = 'Read Receipt Input';
  /** The receipt picture: a realm file URL, a web URL or a data: URL. */
  @field imageUrl = contains(StringField);
  /** The category labels the reader may choose from (the policy's). */
  @field categories = containsMany(StringField);
  /** OpenRouter model id; empty = DEFAULT_SCAN_MODEL. */
  @field llmModel = contains(StringField);
}

export class ReadReceiptResult extends CardDef {
  static displayName = 'Read Receipt Result';
  @field isReceipt = contains(BooleanField);
  @field merchant = contains(StringField);
  /** yyyy-mm-dd */
  @field date = contains(StringField);
  /** The amount paid, in the receipt's own currency. */
  @field total = contains(NumberField);
  @field currency = contains(StringField);
  @field category = contains(StringField);
  @field model = contains(StringField);
  /** What the call cost in USD, when OpenRouter reports it. */
  @field costUsd = contains(NumberField);
  /** The model's reply as text, to check a read. */
  @field reply = contains(StringField);
}

/**
 * Reads one receipt picture with a vision model (the catalog's floor-plan pattern:
 * a data URL in an OpenRouter chat request through the Boxel proxy). Saves nothing:
 * ScanReceiptCommand decides what to write, and this alone is how models are compared.
 */
export class ReadReceiptCommand extends Command<
  typeof ReadReceiptInput,
  typeof ReadReceiptResult
> {
  static actionVerb = 'Read';
  static displayName = 'Read Receipt';

  async getInputType() {
    return ReadReceiptInput;
  }

  protected async run(input: ReadReceiptInput): Promise<ReadReceiptResult> {
    let url = input.imageUrl?.trim();
    if (!url) {
      throw new Error('Choose a receipt picture to read.');
    }
    let categories = (input.categories ?? []).filter(
      (c): c is string => typeof c === 'string' && c.trim().length > 0,
    );
    let model = input.llmModel?.trim() || DEFAULT_SCAN_MODEL;
    let picture = await this.pictureFor(url);

    let result = await new SendRequestViaProxyCommand(
      this.commandContext,
    ).execute({
      url: 'https://openrouter.ai/api/v1/chat/completions',
      method: 'POST',
      requestBody: JSON.stringify({
        model,
        messages: [
          {
            role: 'user',
            content: [
              {
                type: 'text',
                text: scanPrompt({ categories, today: isoDayOf(new Date()) }),
              },
              { type: 'image_url', image_url: { url: picture } },
            ],
          },
        ],
        usage: { include: true },
      }),
    });
    if (!result.response.ok) {
      let body = '';
      try {
        body = await result.response.text();
      } catch {
        // no body: the status says enough
      }
      throw new Error(readerError(result.response.status, body));
    }
    let data = await result.response.json();
    let reply = replyText(data?.choices?.[0]?.message?.content);
    let read = parseReceiptRead(reply, categories);
    let cost = data?.usage?.cost;
    return new ReadReceiptResult({
      ...read,
      model: data?.model || model,
      costUsd: typeof cost === 'number' ? cost : null,
      reply,
    });
  }

  // A realm file is read with the user's own access (private realms work), then made
  // small: phone photos are several MB, which costs tokens and can pass model limits.
  // A web picture that can't be read here is handed to the model as its URL.
  private async pictureFor(url: string): Promise<string> {
    if (url.startsWith('data:image/')) {
      return shrink(url);
    }
    let file: any;
    try {
      file = await new ReadBinaryFileCommand(this.commandContext).execute({
        fileIdentifier: url,
      });
    } catch (e: any) {
      if (/^https?:\/\//.test(url)) {
        return url;
      }
      throw new Error(
        `The receipt picture couldn't be opened (${e?.message ?? e}).`,
      );
    }
    let type = String(file?.contentType ?? '')
      .split(';')[0]
      .trim();
    if (!type.startsWith('image/')) {
      throw new Error(
        `The receipt file is not a picture (${type || 'unknown type'}).`,
      );
    }
    return shrink(`data:${type};base64,${file.base64Content}`);
  }
}

/** The picture with its long edge at most SCAN_MAX_EDGE, as JPEG; the original if it can't be drawn. */
async function shrink(dataUrl: string): Promise<string> {
  try {
    let blob = await (await fetch(dataUrl)).blob();
    let bitmap = await createImageBitmap(blob);
    let scale = Math.min(
      1,
      SCAN_MAX_EDGE / Math.max(bitmap.width, bitmap.height, 1),
    );
    if (scale === 1 && dataUrl.length < 1_500_000) {
      bitmap.close();
      return dataUrl;
    }
    let canvas = document.createElement('canvas');
    canvas.width = Math.round(bitmap.width * scale);
    canvas.height = Math.round(bitmap.height * scale);
    canvas
      .getContext('2d')
      ?.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
    bitmap.close();
    return canvas.toDataURL('image/jpeg', 0.85);
  } catch {
    return dataUrl;
  }
}
