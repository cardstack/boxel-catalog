// Shared image helpers for AI-image commands and cards: data-URL plumbing and
// canvas-based WebP compression, shared by the AI Image commands.

export function arrayBufferToBase64(buffer: ArrayBuffer): string {
  let binary = '';
  const bytes = new Uint8Array(buffer);
  for (let i = 0; i < bytes.byteLength; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary);
}

// Fetch a URL and return it as a data URL; data URLs pass through untouched.
export async function toDataUrl(url: string): Promise<string> {
  if (url.startsWith('data:image/')) return url;
  const res = await fetch(url);
  if (!res.ok) {
    throw new Error(`Failed to fetch image: ${res.statusText} (${url})`);
  }
  const contentType = res.headers.get('content-type') ?? 'image/jpeg';
  const b64 = arrayBufferToBase64(await res.arrayBuffer());
  return `data:${contentType};base64,${b64}`;
}

export function loadImage(dataUrl: string): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = () => reject(new Error('Failed to decode generated image.'));
    img.src = dataUrl;
  });
}

// Re-encode an image as WebP, lowering quality (and downscaling as a last
// resort) until it fits under maxBytes. Returns null when no canvas is
// available so the caller can fall back to the original data URL.
export async function compressDataUrl(
  dataUrl: string,
  maxBytes: number,
): Promise<string | null> {
  let img: HTMLImageElement;
  try {
    img = await loadImage(dataUrl);
  } catch {
    return null;
  }

  const width = img.naturalWidth || img.width;
  const height = img.naturalHeight || img.height;
  if (!width || !height) return null;

  // Keep the source format (PNG stays PNG, JPEG stays JPEG) instead of forcing
  // WebP — only fall back to WebP if the source type is unknown. For lossless
  // PNG the quality arg is ignored, so size is reduced by downscaling.
  const srcType = parseDataUrl(dataUrl).mimeType;
  const outType = /^image\/(png|jpeg|webp)$/.test(srcType)
    ? srcType
    : 'image/webp';

  const encode = (w: number, h: number, quality: number): string | null => {
    const canvas = document.createElement('canvas');
    canvas.width = w;
    canvas.height = h;
    const ctx = canvas.getContext('2d');
    if (!ctx) return null;
    ctx.drawImage(img, 0, 0, w, h);
    const url = canvas.toDataURL(outType, quality);
    return url.startsWith(`data:${outType}`) ? url : null;
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

// Center-crop an image to an exact width:height ratio (e.g. '16:9'). The Gemini
// image models ignore a prompt's aspect-ratio hint and return a square, so this
// enforces the requested framing deterministically after generation. Returns
// null when it can't run (no canvas / unparseable ratio / already correct) so
// the caller falls back to the original data URL unchanged.
export async function cropToAspectRatio(
  dataUrl: string,
  ratio: string | null | undefined,
): Promise<string | null> {
  if (!ratio) return null;
  let m = ratio.match(/^\s*(\d+(?:\.\d+)?)\s*[:/xX]\s*(\d+(?:\.\d+)?)\s*$/);
  if (!m) return null;
  let targetRatio = Number(m[1]) / Number(m[2]);
  if (!isFinite(targetRatio) || targetRatio <= 0) return null;

  let img: HTMLImageElement;
  try {
    img = await loadImage(dataUrl);
  } catch {
    return null;
  }
  let sw = img.naturalWidth || img.width;
  let sh = img.naturalHeight || img.height;
  if (!sw || !sh) return null;

  let srcRatio = sw / sh;
  // Already the requested ratio (within tolerance) — nothing to crop.
  if (Math.abs(srcRatio - targetRatio) < 0.01) return null;

  // Largest centered rectangle of the target ratio that fits in the source.
  let cw = sw;
  let ch = sh;
  if (srcRatio > targetRatio) {
    cw = Math.round(sh * targetRatio); // too wide → trim the sides
  } else {
    ch = Math.round(sw / targetRatio); // too tall → trim top/bottom
  }
  let sx = Math.round((sw - cw) / 2);
  let sy = Math.round((sh - ch) / 2);

  let srcType = parseDataUrl(dataUrl).mimeType;
  let outType = /^image\/(png|jpeg|webp)$/.test(srcType)
    ? srcType
    : 'image/png';

  let canvas = document.createElement('canvas');
  canvas.width = cw;
  canvas.height = ch;
  let ctx = canvas.getContext('2d');
  if (!ctx) return null;
  ctx.drawImage(img, sx, sy, cw, ch, 0, 0, cw, ch);
  let out = canvas.toDataURL(outType, 0.92);
  return out.startsWith('data:') ? out : null;
}

// Split a data URL into its mime type and base64 payload.
export function parseDataUrl(dataUrl: string): {
  mimeType: string;
  base64Content: string;
} {
  const commaIdx = dataUrl.indexOf(',');
  const mimeMatch = dataUrl.slice(0, commaIdx).match(/^data:([^;]+);base64$/);
  return {
    mimeType: mimeMatch?.[1] ?? 'image/png',
    base64Content: dataUrl.slice(commaIdx + 1),
  };
}

// Derive a readable file name from a persisted realm URL.
export function fileNameFromUrl(url: string): string {
  try {
    let path = new URL(url).pathname;
    return decodeURIComponent(path.split('/').pop() || 'image');
  } catch {
    return url.split('/').pop() || 'image';
  }
}
