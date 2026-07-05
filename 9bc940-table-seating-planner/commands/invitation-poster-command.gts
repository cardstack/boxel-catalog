import { CardDef, field, contains } from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import enumField from 'https://cardstack.com/base/enum';
import { Command } from '@cardstack/runtime-common';
import SendRequestViaProxyCommand from '@cardstack/boxel-host/commands/send-request-via-proxy';
import WriteBinaryFileCommand from '@cardstack/boxel-host/commands/write-binary-file';

export const POSTER_ASPECTS = [
  { value: '9:16', label: 'Story 9:16' },
  { value: '2:3', label: 'Portrait 2:3' },
  { value: '4:5', label: 'Card 4:5' },
  { value: '1:1', label: 'Square 1:1' },
  { value: '3:2', label: 'Landscape 3:2' },
  { value: '16:9', label: 'Wide 16:9' },
];

export const PosterAspectField = enumField(StringField, {
  options: POSTER_ASPECTS,
});

class PosterInput extends CardDef {
  @field prompt = contains(StringField);
  @field aspect = contains(PosterAspectField);
  @field targetRealmIdentifier = contains(StringField);
  @field targetPath = contains(StringField);
}

class PosterOutput extends CardDef {
  @field imageUrl = contains(StringField);
}

function loadImage(dataUrl: string): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = () => reject(new Error('Failed to decode generated image.'));
    img.src = dataUrl;
  });
}

async function compressDataUrl(
  dataUrl: string,
  maxBytes: number,
): Promise<string | null> {
  let img: HTMLImageElement;
  try {
    img = await loadImage(dataUrl);
  } catch {
    return null;
  }

  let width = img.naturalWidth || img.width;
  let height = img.naturalHeight || img.height;
  if (!width || !height) return null;

  const encode = (w: number, h: number, quality: number): string | null => {
    const canvas = document.createElement('canvas');
    canvas.width = w;
    canvas.height = h;
    const ctx = canvas.getContext('2d');
    if (!ctx) return null;
    ctx.drawImage(img, 0, 0, w, h);
    const url = canvas.toDataURL('image/webp', quality);
    return url.startsWith('data:image/webp') ? url : null;
  };

  const byteSize = (url: string) => {
    const idx = url.indexOf(',');
    return Math.floor((url.length - idx - 1) * 0.75);
  };

  let best: string | null = null;
  for (let scale = 1; scale >= 0.4; scale -= 0.2) {
    const w = Math.max(1, Math.round(width * scale));
    const h = Math.max(1, Math.round(height * scale));
    for (let q = 0.9; q >= 0.4; q -= 0.1) {
      const candidate = encode(w, h, q);
      if (!candidate) return best;
      best = candidate;
      if (byteSize(candidate) <= maxBytes) return candidate;
    }
  }
  return best;
}

export class InvitationPosterCommand extends Command<
  typeof PosterInput,
  typeof PosterOutput
> {
  static actionVerb = 'Generate';
  static displayName = 'Generate Invitation Poster';

  async getInputType() {
    return PosterInput;
  }

  protected async run(input: PosterInput): Promise<PosterOutput> {
    if (!input.prompt?.trim()) {
      throw new Error('A prompt is required.');
    }

    let aspect = input.aspect?.trim() || '1:1';
    let fullPrompt = `${input.prompt.trim()}\n\nProduce a single poster image with an aspect ratio of ${aspect}. Any text on the poster must be spelled exactly as given above — no gibberish or invented lettering.`;

    let result = await new SendRequestViaProxyCommand(
      this.commandContext,
    ).execute({
      url: 'https://openrouter.ai/api/v1/chat/completions',
      method: 'POST',
      requestBody: JSON.stringify({
        model: 'google/gemini-3.1-flash-image-preview',
        modalities: ['image', 'text'],
        messages: [
          { role: 'user', content: [{ type: 'text', text: fullPrompt }] },
        ],
      }),
    });

    if (!result.response.ok) {
      let errBody = '';
      try {
        errBody = await result.response.text();
      } catch {}
      throw new Error(
        `OpenRouter error ${result.response.status}: ${
          errBody || result.response.statusText
        }`,
      );
    }

    let responseData = await result.response.json();
    let message = responseData.choices?.[0]?.message;

    let dataUrl: string | undefined;
    if (message?.images && Array.isArray(message.images)) {
      dataUrl = message.images
        .map((img: any) => img.image_url?.url)
        .find((u: string) => u?.startsWith('data:image/'));
    }
    if (!dataUrl && Array.isArray(message?.content)) {
      dataUrl = (message.content as any[])
        .filter((p: any) => p.type === 'image_url')
        .map((p: any) => p.image_url?.url)
        .find((u: string) => u?.startsWith('data:image/'));
    }
    if (!dataUrl) {
      throw new Error(
        typeof message?.content === 'string'
          ? message.content
          : 'No image returned by the model.',
      );
    }

    let compressed = await compressDataUrl(dataUrl, 500 * 1024);
    let finalDataUrl = compressed ?? dataUrl;

    let commaIdx = finalDataUrl.indexOf(',');
    let prefix = finalDataUrl.slice(0, commaIdx);
    let mimeMatch = prefix.match(/^data:([^;]+);base64$/);
    let mimeType = mimeMatch?.[1] ?? 'image/png';
    let ext = mimeType.split('/')[1] ?? 'png';
    let base64Content = finalDataUrl.slice(commaIdx + 1);

    let filename = `invitation-${Date.now()}.${ext}`;
    let filePath = input.targetPath?.trim()
      ? `${input.targetPath.trim().replace(/\/$/, '')}/${filename}`
      : filename;

    let writeResult = await new WriteBinaryFileCommand(
      this.commandContext,
    ).execute({
      path: filePath,
      realm: input.targetRealmIdentifier,
      base64Content,
      contentType: mimeType,
      useNonConflictingFilename: true,
    });

    return new PosterOutput({
      imageUrl: writeResult?.fileIdentifier ?? '',
    });
  }
}
