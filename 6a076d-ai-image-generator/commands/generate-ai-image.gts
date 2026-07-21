import {
  CardDef,
  CardInfoField,
  field,
  contains,
  linksTo,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import ImageDef from 'https://cardstack.com/base/image-file-def';
import { Command } from '@cardstack/runtime-common';
import SendRequestViaProxyCommand from '@cardstack/boxel-host/commands/send-request-via-proxy';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import WriteBinaryFileCommand from '@cardstack/boxel-host/commands/write-binary-file';
import {
  compressDataUrl,
  cropToAspectRatio,
  fileNameFromUrl,
  parseDataUrl,
  toDataUrl,
} from '../helpers/image';
import { AiImage, type AiImageMode } from '../ai-image';

// The single entry point for AI image generation. It runs the raw image engine
// (OpenRouter → WebP → persisted realm file) AND records the result as its own
// AI Image card with full provenance — prompt, mode, model, aspect ratio,
// source lineage, and the inpaint mask. Every caller (UI, card code, or an
// AI-assistant skill) goes through here so the generation record is a
// structural guarantee, not something each call site has to remember.

// GA (non-preview) image model — available on the production Vertex project.
// The gemini-3.x *-preview models 404 there unless the project is allowlisted,
// so the reliable default is the generally-available 2.5 Flash Image.
const DEFAULT_MODEL = 'google/gemini-2.5-flash-image';

// A plain-language hint appended to the prompt so models without an explicit
// size parameter still honour the requested framing.
function aspectRatioHint(ratio: string | null | undefined): string {
  const map: Record<string, string> = {
    '1:1': 'a square 1:1 aspect ratio',
    '16:9': 'a wide 16:9 landscape aspect ratio',
    '9:16': 'a tall 9:16 portrait aspect ratio',
    '4:3': 'a 4:3 landscape aspect ratio',
    '3:4': 'a 3:4 portrait aspect ratio',
    '4:5': 'a 4:5 portrait aspect ratio',
    '3:2': 'a 3:2 landscape aspect ratio',
    '2:3': 'a 2:3 portrait aspect ratio',
    '21:9': 'an ultrawide 21:9 cinematic aspect ratio',
  };
  const desc = ratio ? map[ratio] : undefined;
  return desc ? ` Compose the image with ${desc}.` : '';
}

// The raw image engine: build the OpenRouter request (generate / edit /
// inpaint), re-encode to WebP under ~500KB, and persist into the realm so the
// result survives the upstream API's ~1h expiry. Returns the persisted file URL
// and its content type. Kept as an internal function (not a separate Command)
// so there is one public command for the whole flow.
async function runImageEngine(
  commandContext: any,
  opts: {
    prompt: string;
    sourceImageUrls: string[];
    maskDataUrl: string;
    targetRealmIdentifier: string;
    targetPath: string;
    model?: string;
    aspectRatio?: string;
  },
): Promise<{ imageUrl: string; contentType: string }> {
  const promptText = opts.prompt.trim() + aspectRatioHint(opts.aspectRatio);
  const userContent: any[] = [{ type: 'text', text: promptText }];

  // Source images to edit / branch from (image 1, image 2, ...).
  for (const url of opts.sourceImageUrls) {
    if (!url?.trim()) continue;
    try {
      userContent.push({
        type: 'image_url',
        image_url: { url: await toDataUrl(url.trim()) },
      });
    } catch {
      // skip a source image that fails to load rather than aborting
    }
  }

  // Inpaint mask: hand the model a mask image and tell it what the white
  // pixels mean. The model repaints only the masked region.
  if (opts.maskDataUrl?.trim()) {
    userContent[0].text +=
      ' The final image provided is an inpaint MASK: repaint ONLY the WHITE region to satisfy the instruction above and keep every BLACK region pixel-identical to the source image.';
    try {
      userContent.push({
        type: 'image_url',
        image_url: { url: await toDataUrl(opts.maskDataUrl.trim()) },
      });
    } catch {
      // no mask available — degrade to a plain edit
    }
  }

  const result = await new SendRequestViaProxyCommand(commandContext).execute({
    url: 'https://openrouter.ai/api/v1/chat/completions',
    method: 'POST',
    requestBody: JSON.stringify({
      model: opts.model?.trim() || DEFAULT_MODEL,
      modalities: ['image', 'text'],
      messages: [{ role: 'user', content: userContent }],
    }),
  });

  if (!result.response.ok) {
    let errBody = '';
    try {
      errBody = await result.response.text();
    } catch {
      // ignore — fall back to statusText
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

  // Enforce the requested aspect ratio (the models return a square regardless
  // of the prompt hint), then shrink under ~500kb while preserving the source
  // format (a PNG stays a PNG). Each step falls back to its input if no canvas
  // is available.
  const framed =
    (await cropToAspectRatio(dataUrl, opts.aspectRatio)) ?? dataUrl;
  const finalDataUrl = (await compressDataUrl(framed, 500 * 1024)) ?? framed;
  const { mimeType, base64Content } = parseDataUrl(finalDataUrl);
  const ext = mimeType.split('/')[1] ?? 'png';
  const filename = `ai-image-${Date.now()}.${ext}`;
  const filePath = opts.targetPath?.trim()
    ? `${opts.targetPath.trim().replace(/\/$/, '')}/${filename}`
    : filename;

  const writeResult = await new WriteBinaryFileCommand(commandContext).execute({
    path: filePath,
    realm: opts.targetRealmIdentifier,
    base64Content,
    contentType: mimeType,
    useNonConflictingFilename: true,
  });

  return {
    imageUrl: writeResult?.fileIdentifier ?? dataUrl,
    contentType: mimeType,
  };
}

class GenerateAiImageInput extends CardDef {
  @field prompt = contains(StringField);
  // 'generate' | 'edit' | 'inpaint'. Optional — inferred from the inputs
  // (mask ⇒ inpaint, any source image ⇒ edit, otherwise generate).
  @field mode = contains(StringField);
  // The image being iterated on: its image is the edit source and it becomes
  // the new card's parent in the version tree.
  @field parent = linksTo(() => AiImage);
  @field maskDataUrl = contains(StringField); // white = repaint, black = keep
  @field model = contains(StringField); // OpenRouter image-generation model id
  @field aspectRatio = contains(StringField); // e.g. '1:1', '16:9'
  @field targetRealmIdentifier = contains(StringField);
  @field targetPath = contains(StringField); // defaults to 'generated'
}

class GenerateAiImageOutput extends CardDef {
  // The saved generation record.
  @field aiImage = linksTo(() => AiImage);
  @field imageUrl = contains(StringField); // persisted realm file URL
  @field contentType = contains(StringField); // e.g. 'image/webp'
}

export class GenerateAiImageCommand extends Command<
  typeof GenerateAiImageInput,
  typeof GenerateAiImageOutput
> {
  static actionVerb = 'Generate';
  static displayName = 'Generate AI Image Card';

  async getInputType() {
    return GenerateAiImageInput;
  }

  protected async run(
    input: GenerateAiImageInput,
  ): Promise<GenerateAiImageOutput> {
    const {
      prompt,
      mode,
      parent,
      maskDataUrl,
      model,
      aspectRatio,
      targetRealmIdentifier,
      targetPath,
    } = input;

    if (!prompt?.trim()) {
      throw new Error('A prompt is required.');
    }
    const realm = targetRealmIdentifier?.trim();
    if (!realm) {
      throw new Error(
        'A targetRealmIdentifier is required so the image and its record can be persisted.',
      );
    }
    const dir = targetPath?.trim() || 'generated';

    // The edit source is the parent's image (the one being iterated on).
    const parentUrl = parent?.image?.url;
    const engineSourceUrls: string[] = parentUrl ? [parentUrl] : [];

    const mask = maskDataUrl?.trim() ?? '';
    const effectiveMode: AiImageMode =
      (mode?.trim() as AiImageMode) ||
      (mask ? 'inpaint' : engineSourceUrls.length ? 'edit' : 'generate');

    const generated = await runImageEngine(this.commandContext, {
      prompt,
      sourceImageUrls: engineSourceUrls,
      maskDataUrl: mask,
      targetRealmIdentifier: realm,
      targetPath: dir,
      model,
      aspectRatio,
    });

    const imageUrl = generated.imageUrl;
    if (!imageUrl) {
      throw new Error('No image returned.');
    }
    const contentType = generated.contentType || 'image/webp';
    const image = new ImageDef({
      id: imageUrl,
      url: imageUrl,
      sourceUrl: imageUrl,
      name: fileNameFromUrl(imageUrl),
      contentType,
    } as any);

    // Persist the inpaint mask as its own realm file so the record captures
    // WHERE the repaint happened, not just that an inpaint occurred. A mask
    // that fails to persist degrades the record, never the generation.
    let maskImage: ImageDef | undefined;
    if (mask.startsWith('data:image/')) {
      try {
        const { mimeType, base64Content } = parseDataUrl(mask);
        const ext = mimeType.split('/')[1] ?? 'png';
        const writeResult = await new WriteBinaryFileCommand(
          this.commandContext,
        ).execute({
          path: `${dir}/ai-image-mask-${Date.now()}.${ext}`,
          realm,
          base64Content,
          contentType: mimeType,
          useNonConflictingFilename: true,
        });
        const maskUrl = writeResult?.fileIdentifier;
        if (maskUrl) {
          maskImage = new ImageDef({
            id: maskUrl,
            url: maskUrl,
            sourceUrl: maskUrl,
            name: fileNameFromUrl(maskUrl),
            contentType: mimeType,
          } as any);
        }
      } catch {
        // keep the generated image even if the mask can't be persisted
      }
    }

    const aiImage = new AiImage({
      cardInfo: new CardInfoField({ name: prompt.trim().slice(0, 60) }),
      prompt: prompt.trim(),
      mode: effectiveMode,
      image,
      mask: maskImage,
      parent: parent ?? undefined,
      llmModel: model,
      aspectRatio,
      createdAt: new Date(),
    });
    const saved = (await new SaveCardCommand(this.commandContext).execute({
      card: aiImage,
      realm,
    } as any)) as AiImage;

    return new GenerateAiImageOutput({
      aiImage: saved,
      imageUrl,
      contentType,
    });
  }
}
