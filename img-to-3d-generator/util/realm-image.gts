// Shared image plumbing for the studio: encoding, naming, and persisting
// binary images into the realm as file-backed ImageDef cards.

import { ImageDef } from 'https://cardstack.com/base/card-api';
import WriteBinaryFileCommand from '@cardstack/boxel-host/tools/write-binary-file';
import SendRequestViaProxyCommand from '@cardstack/boxel-host/tools/send-request-via-proxy';

function blobToDataUrl(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    let reader = new FileReader();
    reader.onload = () => resolve(reader.result as string);
    reader.onerror = () => reject(new Error('could not encode image'));
    reader.readAsDataURL(blob);
  });
}

// Vision models resize anything past roughly this on its long edge before they
// look at it, so pixels beyond it are thrown away by the provider — after being
// uploaded. A 2000px concept sheet is several megabytes, base64 adds another
// third, and the analysis stage sends up to SIX of them in one request that then
// runs for minutes. That is the request most likely to die halfway with "Failed
// to fetch": the browser abandons every in-flight fetch the moment the network
// blinks, and a bigger, slower request is simply exposed to more blinks.
const MAX_VISION_EDGE = 1568;

// The analysis stage only does structural perception — count the parts, read
// each part's normalized bbox, judge the camera. None of that needs full detail
// (the bboxes are resolution-independent fractions, and the real label pixels
// are cropped from the full-res image later, in the build/silhouette stage), so
// analysis sends a smaller image: fewer input vision tokens, faster time-to-
// first-token on the stage that gates everything downstream. The BUILD stage
// keeps MAX_VISION_EDGE so printed artwork still reproduces faithfully.
export const ANALYZE_MAX_EDGE = 1024;

// A pasted image URL points at somebody else's CDN, and a browser fetch to a
// third-party host fails with "Failed to fetch" unless that host sends
// Access-Control-Allow-Origin — which product-image CDNs essentially never do.
// The confusing part is that the thumbnail still appears: <img src> renders a
// cross-origin image happily, it just refuses to let script READ the bytes. So
// a URL reference looks fine and then dies the moment the pipeline needs pixels
// to send to the model or to trace a silhouette from.
//
// The bytes are reachable server-side, where CORS does not apply, and this app
// already has a server-side hop: the proxy that carries the model calls. Try the
// direct read first — same-realm uploads are same-origin and need no detour —
// and fall back to the proxy only when the browser refuses.
async function readAsDataUrl(
  url: string,
  commandContext?: any,
): Promise<string> {
  try {
    let response = await fetch(url);
    if (!response.ok) {
      throw new Error(`could not read image (${response.status})`);
    }
    return await blobToDataUrl(await response.blob());
  } catch (directError) {
    if (!commandContext) throw directError;
    let result = await new SendRequestViaProxyCommand(commandContext).execute({
      url,
      method: 'GET',
    } as any);
    let proxied = (result as any)?.response;
    if (!proxied || proxied.status >= 400) {
      throw new Error(
        `could not read that image URL (${proxied?.status ?? 'no response'}) — the host blocks direct reads; download it and add it with Link Image instead`,
      );
    }
    let blob = await proxied.blob();
    if (!blob?.size) {
      throw new Error(
        'that image URL returned no data — download it and add it with Link Image instead',
      );
    }
    return await blobToDataUrl(blob);
  }
}

function loadImageEl(src: string): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    let img = new Image();
    img.onload = () => resolve(img);
    img.onerror = () => reject(new Error('could not decode image'));
    img.src = src;
  });
}

// Re-encodes to WebP, which keeps alpha — a JPEG would turn a transparent
// product-shot background black. If the browser cannot produce WebP, toDataURL
// silently returns a PNG, which is still correct, just larger.
export async function fetchAsDataUrl(
  url: string,
  opts: { maxEdge?: number; commandContext?: any } = {},
): Promise<string> {
  let maxEdge = opts.maxEdge ?? MAX_VISION_EDGE;
  let original = await readAsDataUrl(url, opts.commandContext);
  if (!(maxEdge > 0)) return original;
  try {
    let img = await loadImageEl(original);
    let longEdge = Math.max(img.naturalWidth, img.naturalHeight);
    // already small enough — return the untouched bytes rather than re-encoding
    // and losing quality for nothing
    if (!longEdge || longEdge <= maxEdge) return original;
    let scale = maxEdge / longEdge;
    let canvas = document.createElement('canvas');
    canvas.width = Math.max(1, Math.round(img.naturalWidth * scale));
    canvas.height = Math.max(1, Math.round(img.naturalHeight * scale));
    let ctx = canvas.getContext('2d');
    if (!ctx) return original;
    ctx.imageSmoothingQuality = 'high';
    ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
    let shrunk = canvas.toDataURL('image/webp', 0.92);
    // a failed encode can come back tiny or as the wrong type; keep the original
    // rather than send something degraded
    if (!shrunk || shrunk.length < 512) return original;
    return shrunk.length < original.length ? shrunk : original;
  } catch {
    return original; // decoding is best-effort; never block a generation on it
  }
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
