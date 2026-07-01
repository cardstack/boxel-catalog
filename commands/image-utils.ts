// Shared, command-context-free helpers for image resolution + materialization.
// All network access here is plain `fetch()`, NOT the realm proxy: that proxy is a
// credentialed, JSON-only API gateway and can carry neither image bytes nor HTML.

const MIME_TO_EXT: Record<string, string> = {
  'image/png': 'png',
  'image/jpeg': 'jpg',
  'image/jpg': 'jpg',
  'image/webp': 'webp',
  'image/gif': 'gif',
  'image/svg+xml': 'svg',
  'image/avif': 'avif',
};

export function mimeToExt(mimeType: string): string {
  return MIME_TO_EXT[mimeType.split(';')[0].trim()] ?? 'png';
}

export function arrayBufferToBase64(buffer: ArrayBuffer): string {
  const maybeBuffer = (globalThis as any).Buffer;
  if (typeof maybeBuffer !== 'undefined') {
    return maybeBuffer.from(buffer).toString('base64');
  }
  let binary = '';
  const bytes = new Uint8Array(buffer);
  for (let i = 0; i < bytes.byteLength; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  if (typeof btoa !== 'undefined') {
    return btoa(binary);
  }
  throw new Error('Unable to base64-encode image bytes in this environment');
}

export function slugify(value: string): string {
  let slug = value
    .toLowerCase()
    .replace(/^https?:\/\//, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 40);
  return slug || 'image';
}

// The validation gate: fetch the URL and accept only a non-empty image response.
// CORS-blocked hosts throw and are treated as "not a usable image".
export async function fetchValidImage(
  url: string,
): Promise<{ bytes: ArrayBuffer; contentType: string } | undefined> {
  if (!/^https?:\/\//.test(url)) {
    return undefined;
  }
  try {
    let response = await fetch(url);
    if (!response.ok) {
      return undefined;
    }
    let contentType = (
      response.headers.get('content-type') ?? ''
    ).toLowerCase();
    if (!contentType.startsWith('image/')) {
      return undefined;
    }
    let bytes = await response.arrayBuffer();
    if (!bytes.byteLength) {
      return undefined;
    }
    return { bytes, contentType: contentType.split(';')[0].trim() };
  } catch {
    return undefined;
  }
}

export async function isValidImageUrl(url: string): Promise<boolean> {
  return Boolean(await fetchValidImage(url));
}

export async function fetchHtml(url: string): Promise<string | undefined> {
  if (!/^https?:\/\//.test(url)) {
    return undefined;
  }
  try {
    let response = await fetch(url);
    if (!response.ok) {
      return undefined;
    }
    return await response.text();
  } catch {
    return undefined;
  }
}

export function normalizeURL(
  value: string | null | undefined,
  baseUrl: string,
): string | undefined {
  if (!value) {
    return undefined;
  }
  let trimmed = value.trim();
  if (!trimmed || trimmed.startsWith('data:')) {
    return undefined;
  }
  try {
    if (trimmed.startsWith('//')) {
      return `${new URL(baseUrl).protocol}${trimmed}`;
    }
    return new URL(trimmed, baseUrl).href;
  } catch {
    return undefined;
  }
}

export function extractImageCandidates(
  html: string,
  baseUrl: string,
): string[] {
  if (typeof DOMParser === 'undefined') {
    return [];
  }
  let doc: Document;
  try {
    doc = new DOMParser().parseFromString(html, 'text/html');
  } catch {
    return [];
  }

  let candidates: string[] = [];
  let push = (value?: string | null) => {
    let normalized = normalizeURL(value, baseUrl);
    if (normalized && !candidates.includes(normalized)) {
      candidates.push(normalized);
    }
  };

  let metaSelectors = [
    'meta[property="og:image:secure_url"]',
    'meta[property="og:image"]',
    'meta[property="og:image:url"]',
    'meta[name="twitter:image"]',
    'meta[name="twitter:image:src"]',
  ];
  for (let selector of metaSelectors) {
    push(doc.querySelector(selector)?.getAttribute('content'));
  }

  push(doc.querySelector('link[rel="apple-touch-icon"]')?.getAttribute('href'));
  push(doc.querySelector('link[rel~="icon" i]')?.getAttribute('href'));

  for (let img of Array.from(doc.querySelectorAll('img')).slice(0, 10)) {
    push(img.getAttribute('src'));
  }

  return candidates;
}

export function deriveSearchQuery(sourceUrl: string, html?: string): string {
  if (html && typeof DOMParser !== 'undefined') {
    try {
      let title = new DOMParser()
        .parseFromString(html, 'text/html')
        .querySelector('title')
        ?.textContent?.trim();
      if (title) {
        return title;
      }
    } catch {
      // fall through to hostname
    }
  }
  try {
    return new URL(sourceUrl).hostname.replace(/^www\./, '');
  } catch {
    return sourceUrl;
  }
}

function logoSlugs(name: string): string[] {
  let base = name.toLowerCase().trim();
  let candidates = [
    base,
    base.replace(/\b(framework|language|lang|library)\b/g, '').trim(),
    base.split(/\s+/)[0],
  ];
  let slugs = candidates
    .map((candidate) => candidate.replace(/[^a-z0-9]/g, ''))
    .filter(Boolean);
  return [...new Set(slugs)];
}

// Canonical brand/tech logo via keyless, CORS-enabled, brand-colored logo CDNs.
// Tries a few name-slugs against devicon then Simple Icons; a miss 404s and is
// skipped, so a bad slug never blocks the chain. Returns undefined when no slug
// resolves (e.g. the name isn't a known brand).
export async function findLogoImageUrl(
  name: string,
): Promise<string | undefined> {
  for (let slug of logoSlugs(name)) {
    let devicon = `https://cdn.jsdelivr.net/gh/devicons/devicon/icons/${slug}/${slug}-original.svg`;
    if (await isValidImageUrl(devicon)) {
      return devicon;
    }
    let simpleIcon = `https://cdn.simpleicons.org/${slug}`;
    if (await isValidImageUrl(simpleIcon)) {
      return simpleIcon;
    }
  }
  return undefined;
}

// Wikipedia: free, keyless, CORS-enabled (origin=*). Returns the first lead image
// that passes the validation gate, or undefined.
export async function findWikipediaImageUrl(
  query: string,
): Promise<string | undefined> {
  let apiUrl =
    `https://en.wikipedia.org/w/api.php?action=query&generator=search` +
    `&gsrsearch=${encodeURIComponent(query)}&gsrlimit=3` +
    `&prop=pageimages&piprop=thumbnail&pithumbsize=512&format=json&origin=*`;
  let pages: Array<{ index?: number; thumbnail?: { source?: string } }>;
  try {
    let response = await fetch(apiUrl);
    if (!response.ok) {
      return undefined;
    }
    let json = await response.json();
    pages = Object.values(json?.query?.pages ?? {}) as typeof pages;
  } catch {
    return undefined;
  }
  let candidates = pages
    .sort((a, b) => (a.index ?? 0) - (b.index ?? 0))
    .map((page) => page.thumbnail?.source)
    .filter((source): source is string => Boolean(source));
  for (let candidate of candidates) {
    if (await isValidImageUrl(candidate)) {
      return candidate;
    }
  }
  return undefined;
}
