// Shared image plumbing for the studio: encoding, naming, and persisting
// binary images into the realm as file-backed ImageDef cards.

import { ImageDef } from 'https://cardstack.com/base/card-api';
import WriteBinaryFileCommand from '@cardstack/boxel-host/tools/write-binary-file';

export function blobToDataUrl(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    let reader = new FileReader();
    reader.onload = () => resolve(reader.result as string);
    reader.onerror = () => reject(new Error('could not encode image'));
    reader.readAsDataURL(blob);
  });
}

export async function fetchAsDataUrl(url: string): Promise<string> {
  let response = await fetch(url);
  if (!response.ok) {
    throw new Error(`could not read image (${response.status})`);
  }
  return blobToDataUrl(await response.blob());
}

export function slugify(name: string, fallback = 'image'): string {
  return (
    name
      .toLowerCase()
      .replace(/\.[^.]+$/, '')
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-+|-+$/g, '') || fallback
  );
}

// writes base64 image bytes into the realm and returns a file-backed
// ImageDef (the file URL is the card id — no separate instance json)
export async function writeRealmImage(
  commandContext: any,
  options: {
    realm: string | undefined;
    path: string;
    base64: string;
    contentType: string;
  },
): Promise<any> {
  let result = await new WriteBinaryFileCommand(commandContext).execute({
    path: options.path,
    realm: options.realm,
    base64Content: options.base64,
    contentType: options.contentType,
    useNonConflictingFilename: true,
  });
  let url = (result as any)?.fileIdentifier;
  if (!url) return undefined;
  return new ImageDef({
    id: url,
    url,
    sourceUrl: url,
    name: url.split('/').pop() ?? 'image',
    contentType: options.contentType,
  } as any);
}
