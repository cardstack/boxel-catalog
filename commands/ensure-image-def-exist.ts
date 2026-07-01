import { Command } from '@cardstack/runtime-common';

import { CardDef, field, contains } from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import UrlField from 'https://cardstack.com/base/url';

import WriteBinaryFileCommand from '@cardstack/boxel-host/commands/write-binary-file';

import {
  fetchValidImage,
  mimeToExt,
  arrayBufferToBase64,
  slugify,
} from './image-utils';

export class EnsureImageDefInput extends CardDef {
  @field imageUrl = contains(UrlField, {
    description: 'A directly-loadable image URL.',
  });
  @field targetRealmUrl = contains(StringField, {
    description: 'Realm the image is written into.',
  });
  @field path = contains(StringField, {
    description: 'Optional directory within the realm. Defaults to images/.',
  });
}

export class EnsureImageDefResult extends CardDef {
  @field imageDefId = contains(StringField, {
    description:
      'Realm URL / id of the persisted ImageDef. Resolve it through the store (e.g. as a linksTo target) — it is a reference, not inline card data.',
  });
  @field contentType = contains(StringField);
}

// Persist a valid image as an ImageDef in the realm and return its id. Returns a
// reference, not a card data model: a plain Command cannot reach the store, so
// consumers resolve the id through the store (a linksTo set to it is hydrated by
// the store on read). Throws if the URL is not a loadable image.
export default class EnsureImageDefCommand extends Command<
  typeof EnsureImageDefInput,
  typeof EnsureImageDefResult
> {
  static actionVerb = 'Ensure';
  static displayName = 'Ensure Image Def Exists';
  description =
    'Fetch a valid image from a URL and persist it as an ImageDef in the target realm, returning the ImageDef id. The image is stored verbatim; no resizing is performed.';

  async getInputType() {
    return EnsureImageDefInput;
  }

  protected async run(
    input: EnsureImageDefInput,
  ): Promise<EnsureImageDefResult> {
    let imageUrl = input.imageUrl?.trim();
    if (!imageUrl) {
      throw new Error('imageUrl is required');
    }
    let targetRealmUrl = input.targetRealmUrl?.trim();
    if (!targetRealmUrl) {
      throw new Error('targetRealmUrl is required');
    }

    let image = await fetchValidImage(imageUrl);
    if (!image) {
      throw new Error(`"${imageUrl}" is not a loadable image`);
    }

    let ext = mimeToExt(image.contentType);
    let filename = `${slugify(imageUrl)}.${ext}`;
    let dir = (input.path?.trim() || 'images').replace(/^\/+|\/+$/g, '');
    let path = `${dir}/${filename}`;

    let writeResult = await new WriteBinaryFileCommand(
      this.commandContext,
    ).execute({
      path,
      realm: targetRealmUrl,
      base64Content: arrayBufferToBase64(image.bytes),
      contentType: image.contentType,
      useNonConflictingFilename: true,
    });

    if (!writeResult?.fileIdentifier) {
      throw new Error('Failed to write the image to the realm.');
    }

    return new EnsureImageDefResult({
      imageDefId: writeResult.fileIdentifier,
      contentType: image.contentType,
    });
  }
}
