import {
  CardDef,
  field,
  contains,
  containsMany,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import { Command } from '@cardstack/runtime-common';
import SendRequestViaProxyCommand from '@cardstack/boxel-host/commands/send-request-via-proxy';
import WriteBinaryFileCommand from '@cardstack/boxel-host/commands/write-binary-file';

class GenerateTryOnInput extends CardDef {
  @field prompt = contains(StringField);
  @field modelImageUrl = contains(StringField);
  @field garmentImageUrls = containsMany(StringField); // product images for each garment
  @field targetRealmIdentifier = contains(StringField);
  @field targetPath = contains(StringField);
}

class GenerateTryOnOutput extends CardDef {
  @field imageUrl = contains(StringField);
}

function arrayBufferToBase64(buffer: ArrayBuffer): string {
  let binary = '';
  const bytes = new Uint8Array(buffer);
  for (let i = 0; i < bytes.byteLength; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary);
}

async function toDataUrl(url: string): Promise<string> {
  if (url.startsWith('data:image/')) return url;
  const res = await fetch(url);
  if (!res.ok)
    throw new Error(`Failed to fetch image: ${res.statusText} (${url})`);
  const contentType = res.headers.get('content-type') ?? 'image/jpeg';
  const b64 = arrayBufferToBase64(await res.arrayBuffer());
  return `data:${contentType};base64,${b64}`;
}

function loadImage(dataUrl: string): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = () => reject(new Error('Failed to decode generated image.'));
    img.src = dataUrl;
  });
}

// Re-encode the generated image as WebP, lowering quality (and downscaling
// as a last resort) until it fits under maxBytes. Returns null if the
// browser can't produce a canvas (e.g. no DOM), so the caller can fall back
// to the original image.
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
    // Some browsers ignore unsupported types and silently return PNG;
    // signal that so the caller can fall back to the original.
    return url.startsWith('data:image/webp') ? url : null;
  };

  // base64 length * 0.75 ≈ byte size of the decoded payload
  const byteSize = (url: string) => {
    const idx = url.indexOf(',');
    return Math.floor((url.length - idx - 1) * 0.75);
  };

  let best: string | null = null;
  // Shrink dimensions in passes, sweeping quality down within each pass.
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

export class GenerateTryOnCommand extends Command<
  typeof GenerateTryOnInput,
  typeof GenerateTryOnOutput
> {
  static actionVerb = 'Generate';
  static displayName = 'Generate Try-On Image';

  async getInputType() {
    return GenerateTryOnInput;
  }

  protected async run(input: GenerateTryOnInput): Promise<GenerateTryOnOutput> {
    const {
      prompt,
      modelImageUrl,
      garmentImageUrls,
      targetRealmIdentifier,
      targetPath,
    } = input;

    if (!prompt?.trim()) {
      throw new Error('A prompt is required.');
    }

    // Build message: text prompt first, then model photo, then each garment image
    const userContent: any[] = [{ type: 'text', text: prompt.trim() }];

    if (modelImageUrl?.trim()) {
      const dataUrl = await toDataUrl(modelImageUrl.trim());
      userContent.push({
        type: 'image_url',
        image_url: { url: dataUrl },
      });
    }

    if (garmentImageUrls?.length) {
      for (const url of garmentImageUrls) {
        if (!url?.trim()) continue;
        try {
          const dataUrl = await toDataUrl(url.trim());
          userContent.push({
            type: 'image_url',
            image_url: { url: dataUrl },
          });
        } catch {
          // skip garment images that fail to load rather than aborting
        }
      }
    }

    const result = await new SendRequestViaProxyCommand(
      this.commandContext,
    ).execute({
      url: 'https://openrouter.ai/api/v1/chat/completions',
      method: 'POST',
      requestBody: JSON.stringify({
        model: 'google/gemini-3.1-flash-image-preview',
        modalities: ['image', 'text'],
        messages: [{ role: 'user', content: userContent }],
      }),
    });

    if (!result.response.ok) {
      let errBody = '';
      try {
        errBody = await result.response.text();
      } catch {
        // ignore — fall back to statusText below
      }
      throw new Error(
        `OpenRouter error ${result.response.status}: ${errBody || result.response.statusText}`,
      );
    }

    const responseData = await result.response.json();
    const message = responseData.choices?.[0]?.message;

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
      const errText =
        typeof message?.content === 'string'
          ? message.content
          : 'No image returned by model.';
      throw new Error(errText);
    }

    // Re-encode down to ~500kb before saving; fall back to the original
    // image if compression isn't possible in this environment.
    const compressed = await compressDataUrl(dataUrl, 500 * 1024);
    const finalDataUrl = compressed ?? dataUrl;

    const commaIdx = finalDataUrl.indexOf(',');
    const prefix = finalDataUrl.slice(0, commaIdx);
    const mimeMatch = prefix.match(/^data:([^;]+);base64$/);
    const mimeType = mimeMatch?.[1] ?? 'image/png';
    const ext = mimeType.split('/')[1] ?? 'png';
    const base64Content = finalDataUrl.slice(commaIdx + 1);

    const ts = Date.now();
    const filename = `try-on-${ts}.${ext}`;
    const filePath = targetPath?.trim()
      ? `${targetPath.trim().replace(/\/$/, '')}/${filename}`
      : filename;

    const writeResult = await new WriteBinaryFileCommand(
      this.commandContext,
    ).execute({
      path: filePath,
      realm: targetRealmIdentifier,
      base64Content,
      contentType: mimeType,
      useNonConflictingFilename: true,
    });

    return new GenerateTryOnOutput({
      imageUrl: writeResult?.fileIdentifier ?? dataUrl,
    });
  }
}
