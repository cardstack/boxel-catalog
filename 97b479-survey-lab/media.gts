// Getting the video in and frames out. Workspace files need the signed-in
// fetch, so the whole clip is fetched once and played from a blob URL, which
// also lets the canvas read its frames (for the timeline and the interviewer).

const cache = new Map<string, Promise<string>>();

export function inPrerender() {
  return Boolean((globalThis as any).__boxelRenderContext);
}

export function videoBlobUrl(
  url: string,
  onProgress?: (f: number) => void,
): Promise<string> {
  let hit = cache.get(url);
  if (hit) return hit;
  hit = (async () => {
    const r = await fetch(url);
    if (!r.ok || !r.body)
      throw new Error(`the video did not load (status ${r.status})`);
    const size = Number(r.headers.get('content-length')) || 0;
    const reader = r.body.getReader();
    const parts: BlobPart[] = [];
    let got = 0;
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      parts.push(value);
      got += value.length;
      if (size) onProgress?.(got / size);
    }
    return URL.createObjectURL(
      new Blob(parts, { type: r.headers.get('content-type') || 'video/mp4' }),
    );
  })();
  hit.catch(() => cache.delete(url));
  cache.set(url, hit);
  return hit;
}

// frames at the given times, as small JPEG data URLs
export async function grabFrames(
  src: string,
  times: number[],
  width = 480,
): Promise<string[]> {
  const v = document.createElement('video');
  v.muted = true;
  v.playsInline = true;
  v.preload = 'auto';
  v.src = src;
  await new Promise<void>((res, rej) => {
    v.onloadeddata = () => res();
    v.onerror = () => rej(new Error('the video would not load for frames'));
    setTimeout(
      () => rej(new Error('the video took too long to load for frames')),
      20000,
    );
  });
  const c = document.createElement('canvas');
  const scale = Math.min(1, width / (v.videoWidth || width));
  c.width = Math.round((v.videoWidth || width) * scale);
  c.height = Math.round((v.videoHeight || width * 0.5625) * scale);
  const g = c.getContext('2d')!;
  const out: string[] = [];
  for (const t of times) {
    v.currentTime = Math.min(Math.max(0, t), (v.duration || t) - 0.05);
    await new Promise<void>((res) => {
      v.onseeked = () => res();
      setTimeout(res, 4000);
    });
    g.drawImage(v, 0, 0, c.width, c.height);
    out.push(c.toDataURL('image/jpeg', 0.72));
  }
  v.removeAttribute('src');
  v.load();
  return out;
}

export function parse<T>(s: string | null | undefined, fallback: T): T {
  if (!s) return fallback;
  try {
    return JSON.parse(s) as T;
  } catch {
    return fallback;
  }
}

export async function blobToBase64(blob: Blob): Promise<string> {
  const buf = new Uint8Array(await blob.arrayBuffer());
  let s = '';
  for (let i = 0; i < buf.length; i += 0x8000)
    s += String.fromCharCode(...buf.subarray(i, i + 0x8000));
  return btoa(s);
}
