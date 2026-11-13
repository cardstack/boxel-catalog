// The Travel Helper's AI and data calls. Everything goes out through the
// host's request proxy (OpenRouter) or straight to free public APIs
// (Open-Meteo for places and weather), so nothing needs a key in the card.
import SendRequestViaProxyCommand from '@cardstack/boxel-host/tools/send-request-via-proxy';

export const VISION = 'google/gemini-2.5-flash'; // fast, cheap, and gives boxes
export const SCAN = 'google/gemini-2.5-flash-lite'; // live scanning: speed first
export const WRITER = 'google/gemini-2.5-flash';
export const RESEARCHER = 'google/gemini-2.5-flash:online'; // OpenRouter adds web search

export const SESSION_EXPIRED =
  'Your Boxel sign-in has expired. Reload the page; everything so far is saved.';

export const CATEGORIES = [
  'wardrobe',
  'electronics',
  'toiletries',
  'documents',
  'medicine',
  'other',
] as const;
export type Category = (typeof CATEGORIES)[number];
export const CATEGORY_NAMES: Record<Category, string> = {
  wardrobe: 'Wardrobe',
  electronics: 'Electronics',
  toiletries: 'Toiletries',
  documents: 'Documents & money',
  medicine: 'Medicine',
  other: 'Other',
};
export const asCategory = (c: any): Category =>
  CATEGORIES.includes(c) ? c : 'other';

export const toolCtx = (context: any) =>
  context?.toolContext ?? context?.commandContext;

async function proxyJson(ctx: any, body: any): Promise<any> {
  const result = await new SendRequestViaProxyCommand(ctx).execute({
    url: 'https://openrouter.ai/api/v1/chat/completions',
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'HTTP-Referer': globalThis.location?.origin ?? 'https://app.boxel.ai',
      'X-Title': 'Travel helper',
    },
    requestBody: JSON.stringify(body),
  } as any);
  const response = (result as any)?.response ?? result;
  if (response?.ok === false) {
    let text = '';
    try {
      text = await response.text();
    } catch {
      text = '';
    }
    if (/token expired/i.test(text)) throw new Error(SESSION_EXPIRED);
    throw new Error(`the AI said ${response.status}: ${text.slice(0, 160)}`);
  }
  return typeof response.json === 'function'
    ? await response.json()
    : JSON.parse((result as any).body ?? '{}');
}

function parseAnswer(data: any): any {
  const raw: string = data?.choices?.[0]?.message?.content ?? '';
  const text = raw.replace(/^```(json)?|```$/g, '').trim();
  const a = text.indexOf('{');
  const b = text.lastIndexOf('}');
  const body = a >= 0 && b > a ? text.slice(a, b + 1) : text;
  // as sent; without any talk around it; with raw line breaks inside strings escaped
  for (const t of [text, body, escapeControls(body)]) {
    try {
      return JSON.parse(t);
    } catch {
      // try the next repair
    }
  }
  throw new Error('the answer was not JSON');
}

// models sometimes put real line breaks or tabs inside a JSON string (a long
// markdown summary, say), which JSON.parse refuses
function escapeControls(text: string): string {
  let out = '';
  let inStr = false;
  let esc = false;
  for (const ch of text) {
    if (inStr) {
      if (esc) esc = false;
      else if (ch === '\\') esc = true;
      else if (ch === '"') inStr = false;
      else if (ch < ' ') {
        out +=
          ch === '\n'
            ? '\\n'
            : ch === '\r'
              ? '\\r'
              : ch === '\t'
                ? '\\t'
                : `\\u${ch.charCodeAt(0).toString(16).padStart(4, '0')}`;
        continue;
      }
    } else if (ch === '"') inStr = true;
    out += ch;
  }
  return out;
}

// one JSON answer; `images` are data: URLs
export async function askJson(
  ctx: any,
  system: string,
  user: string,
  opts: {
    images?: string[];
    files?: { name: string; data: string }[];
    model?: string;
    temperature?: number;
    json?: boolean;
    fast?: boolean;
  } = {},
) {
  const parts = [
    ...(opts.images ?? []).map((url) => ({
      type: 'image_url',
      image_url: { url },
    })),
    ...(opts.files ?? []).map((f) => ({
      type: 'file',
      file: { filename: f.name, file_data: f.data },
    })),
  ];
  const content: any = parts.length
    ? [{ type: 'text', text: user }, ...parts]
    : user;
  const body: any = {
    model: opts.model ?? WRITER,
    temperature: opts.temperature ?? 0.3,
    messages: [
      { role: 'system', content: system },
      { role: 'user', content },
    ],
  };
  if (opts.json !== false) body.response_format = { type: 'json_object' };
  // scanning wants speed over deliberation: no thinking; if the provider
  // refuses the setting, ask again without it
  let data: any;
  if (opts.fast) {
    try {
      data = await proxyJson(ctx, { ...body, reasoning: { max_tokens: 0 } });
    } catch (e: any) {
      if (e?.message === SESSION_EXPIRED) throw e;
      data = await proxyJson(ctx, body);
    }
  } else {
    data = await proxyJson(ctx, body);
  }
  const j = parseAnswer(data);
  // web search results come back as url_citation annotations
  const cites = (data?.choices?.[0]?.message?.annotations ?? [])
    .map((a: any) => a?.url_citation ?? a)
    .filter((c: any) => c?.url)
    .map((c: any) => ({ url: String(c.url), title: String(c.title ?? '') }));
  return { j, cites };
}

// ─── images ──────────────────────────────────────────────────────────────
export async function blobToBase64(blob: Blob): Promise<string> {
  const buf = new Uint8Array(await blob.arrayBuffer());
  let s = '';
  for (let i = 0; i < buf.length; i += 0x8000)
    s += String.fromCharCode(...buf.subarray(i, i + 0x8000));
  return btoa(s);
}

// phone photos are 12 MP; everything works from a JPEG this size
export async function shrink(
  src: Blob | ImageBitmap | HTMLVideoElement,
  max = 1600,
  quality = 0.85,
): Promise<{ blob: Blob; w: number; h: number }> {
  const bmp: any = src instanceof Blob ? await createImageBitmap(src) : src;
  const sw = bmp.videoWidth ?? bmp.width;
  const sh = bmp.videoHeight ?? bmp.height;
  const k = Math.min(1, max / Math.max(sw, sh));
  const w = Math.round(sw * k);
  const h = Math.round(sh * k);
  const c = document.createElement('canvas');
  c.width = w;
  c.height = h;
  c.getContext('2d')!.drawImage(bmp, 0, 0, w, h);
  const blob = await new Promise<Blob>((ok, fail) =>
    c.toBlob(
      (b) => (b ? ok(b) : fail(new Error('could not encode the photo'))),
      'image/jpeg',
      quality,
    ),
  );
  return { blob, w, h };
}

// a square-ish cutout around a box given in 0-1000 units [ymin, xmin, ymax, xmax]
export async function cutout(
  photo: Blob,
  box: number[],
  size = 360,
): Promise<Blob | null> {
  if (
    !Array.isArray(box) ||
    box.length !== 4 ||
    box.some((n) => !Number.isFinite(Number(n)))
  )
    return null;
  const bmp = await createImageBitmap(photo);
  let [y0, x0, y1, x1] = box.map(
    (n) => Math.max(0, Math.min(1000, Number(n))) / 1000,
  );
  if (y1 - y0 < 0.02 || x1 - x0 < 0.02) return null;
  const pad = 0.06;
  x0 = Math.max(0, x0 - pad * (x1 - x0));
  x1 = Math.min(1, x1 + pad * (x1 - x0));
  y0 = Math.max(0, y0 - pad * (y1 - y0));
  y1 = Math.min(1, y1 + pad * (y1 - y0));
  const sx = x0 * bmp.width;
  const sy = y0 * bmp.height;
  const sw = (x1 - x0) * bmp.width;
  const sh = (y1 - y0) * bmp.height;
  const side = Math.max(sw, sh);
  const c = document.createElement('canvas');
  c.width = size;
  c.height = size;
  const g = c.getContext('2d')!;
  g.fillStyle = '#f4f1ea';
  g.fillRect(0, 0, size, size);
  const k = size / side;
  g.drawImage(
    bmp,
    sx,
    sy,
    sw,
    sh,
    (size - sw * k) / 2,
    (size - sh * k) / 2,
    sw * k,
    sh * k,
  );
  return new Promise<Blob | null>((ok) =>
    c.toBlob((b) => ok(b), 'image/jpeg', 0.85),
  );
}

// ─── seeing things ───────────────────────────────────────────────────────
// the model gets short keys (i1, i2…), not card URLs it would garble
function keyed(known: KnownItem[]) {
  const byKey = new Map<string, KnownItem>();
  const rows = known.map((k, i) => {
    byKey.set(`i${i + 1}`, k);
    return `- i${i + 1} | ${k.name} | ${k.category}${k.status ? ` | ${k.status}` : ''}`;
  });
  const norm = (s: string) =>
    s
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, ' ')
      .trim();
  // a key, else the same name in the same category
  const resolve = (key: any, name: string, category: string): string | null => {
    const k = byKey.get(String(key ?? '').trim());
    if (k) return k.id;
    const same = known.find(
      (x) => norm(x.name) === norm(name) && asCategory(x.category) === category,
    );
    if (same) return same.id;
    // the fast model names one thing a little differently each read
    // ("travel toiletries" / "travel toiletries bag"): all the words of the
    // shorter name inside the longer, same category, counts as the same thing
    const words = (t: string) =>
      new Set(
        norm(t)
          .split(' ')
          .filter((w) => w.length > 2),
      );
    const mine = words(name);
    const near = known.find((x) => {
      if (asCategory(x.category) !== category) return false;
      const theirs = words(x.name);
      const [a, b] = mine.size <= theirs.size ? [mine, theirs] : [theirs, mine];
      return a.size >= 2 && [...a].every((w) => b.has(w));
    });
    return near?.id ?? null;
  };
  return { list: rows.join('\n') || '(none yet)', resolve };
}
export type SnapMode = 'items' | 'packing' | 'bag' | 'away';
export interface KnownItem {
  id: string;
  name: string;
  category: string;
  status: string;
}
export interface Seen {
  match: string | null; // id of a known item, if it is the same thing
  name: string;
  category: Category;
  qty: number;
  box: number[] | null;
  litres: number;
  kg: number;
  note: string;
}
export interface BagSeen {
  type: string;
  litres: number;
  kg: number;
  carryOn: boolean;
  note: string;
}

const SEE = `You look at a photo someone took while packing for a trip, and list the travel things in it.
- One entry per distinct thing. Identical things together get one entry with a count ("3 pairs of socks"). If you can't count a heap, give your best guess and say so in "note".
- Name things plainly and specifically, as the owner would ("black puffer jacket", "USB-C charger", "toothbrush"). Include colour for clothes.
- category: one of wardrobe (clothes, shoes, accessories worn), electronics (devices, chargers, cables, adapters), toiletries, documents (passport, cards, cash, tickets), medicine, other.
- box_2d: [ymin, xmin, ymax, xmax] around the thing, in 0-1000 units of the image.
- litres: rough packed volume of ONE of it, folded as it would go in a bag (a T-shirt 0.6, jeans 1.5, a puffer 6, a phone charger 0.1). kg: rough weight of ONE.
- KNOWN ITEMS are things already on their list (some still "needed", i.e. not found yet), and things they own from earlier trips (status "owned, not on this list"). If an entry is a known item, or fills a needed one (a black beanie fills "warm hat"; a USB-C charger fills "phone charger"), set "match" to its key (e.g. "i3") instead of making a near-duplicate; otherwise null. Prefer the exact thing they own over a needed line it could fill. Never match two entries to the same key.
- Ignore furniture, the bed, the floor, people, and the bag itself.
- Only list what you can actually see. Things buried in a pile that you can't make out are not entries; mention "probably more under the pile" in "notes".
Answer ONLY with JSON: {"items": [{"match": str|null, "name": str, "category": str, "qty": int, "box_2d": [int,int,int,int], "litres": number, "kg": number, "note": str}], "notes": str}`;

const AWAY = `
THIS PHOTO IS DIFFERENT: they are home from a trip, putting things back where they live. Also give "spot": where these things are being stored, as one short line they'd recognise a year later (which furniture, shelf, drawer, box or bag, and the room if you can tell), e.g. "grey vacuum bag, top shelf of the bedroom wardrobe". If you can't tell, describe what you see around them. Add "spot" to the JSON answer.`;

const SEE_BAG = `You look at a photo of a travel bag (empty or partly packed). Say what it is and estimate its capacity.
Answer ONLY with JSON: {"type": str (e.g. "cabin roller", "40 L backpack", "large check-in suitcase"), "litres": number (capacity), "kg": number (its own empty weight), "carryOn": bool (would most airlines take it in the cabin), "note": str (one short line: anything that matters for packing, e.g. "two compartments; front pocket for documents")}`;

export async function see(
  ctx: any,
  photo: string,
  mode: SnapMode,
  known: KnownItem[],
  opts: { fast?: boolean } = {},
): Promise<{
  items: Seen[];
  bag: BagSeen | null;
  notes: string;
  spot: string;
}> {
  if (mode === 'bag') {
    const { j } = await askJson(ctx, SEE_BAG, 'The bag:', {
      images: [photo],
      model: VISION,
      temperature: 0.2,
    });
    const litres = Number(j?.litres);
    return {
      items: [],
      bag: {
        type: String(j?.type ?? 'bag'),
        litres: Number.isFinite(litres) && litres > 0 ? litres : 40,
        kg: Number(j?.kg) || 0,
        carryOn: Boolean(j?.carryOn),
        note: String(j?.note ?? ''),
      },
      notes: '',
      spot: '',
    };
  }
  const { list, resolve } = keyed(known);
  const ask = `${mode === 'packing' ? 'These things are going INTO the bag.' : mode === 'away' ? 'These things are being put away at home after the trip.' : 'These things are laid out to decide what to bring.'}\n\nKNOWN ITEMS (key | name | category | status):\n${list}`;
  const SYS = mode === 'away' ? SEE + AWAY : SEE;
  let j: any;
  if (opts.fast) {
    try {
      ({ j } = await askJson(ctx, SYS, ask, {
        images: [photo],
        model: SCAN,
        temperature: 0.2,
      }));
    } catch (e: any) {
      if (e?.message === SESSION_EXPIRED) throw e;
      ({ j } = await askJson(ctx, SYS, ask, {
        images: [photo],
        model: VISION,
        temperature: 0.2,
        fast: true,
      }));
    }
  } else {
    ({ j } = await askJson(ctx, SYS, ask, {
      images: [photo],
      model: VISION,
      temperature: 0.2,
    }));
  }
  // one list line per thing: a second claim on the same line is its own thing
  const used = new Set<string>();
  const items: Seen[] = (Array.isArray(j?.items) ? j.items : [])
    .filter((x: any) => x?.name)
    .map((x: any) => {
      let match = resolve(
        x.match,
        String(x.name).trim(),
        asCategory(x.category),
      );
      if (match && used.has(match)) match = null;
      if (match) used.add(match);
      return {
        match,
        name: String(x.name).trim(),
        category: asCategory(x.category),
        qty: Math.max(1, Math.round(Number(x.qty) || 1)),
        box: Array.isArray(x.box_2d) ? x.box_2d.map(Number) : null,
        litres: Math.max(0, Number(x.litres) || 0),
        kg: Math.max(0, Number(x.kg) || 0),
        note: String(x.note ?? ''),
      };
    });
  return {
    items,
    bag: null,
    notes: String(j?.notes ?? ''),
    spot: String(j?.spot ?? '').trim(),
  };
}

// the live scan's fast model names things well but places boxes loosely; before
// a cutout is kept, a careful pass places the box for each new thing
const PLACE = `You get a photo and a numbered list of things in it. For each, give the tightest box around that one thing.
box_2d: [ymin, xmin, ymax, xmax] in 0-1000 units of the image. If you can't find a thing, use null.
Answer ONLY with JSON: {"boxes": [{"n": int, "box_2d": [int,int,int,int] | null}]}`;
export async function placeBoxes(
  ctx: any,
  photo: string,
  names: string[],
): Promise<(number[] | null)[]> {
  if (!names.length) return [];
  const { j } = await askJson(
    ctx,
    PLACE,
    names.map((n, i) => `${i + 1}. ${n}`).join('\n'),
    { images: [photo], model: VISION, temperature: 0 },
  );
  const out: (number[] | null)[] = names.map(() => null);
  for (const b of Array.isArray(j?.boxes) ? j.boxes : []) {
    const i = Number(b?.n) - 1;
    if (
      i >= 0 &&
      i < out.length &&
      Array.isArray(b?.box_2d) &&
      b.box_2d.length === 4 &&
      b.box_2d.every((x: any) => Number.isFinite(Number(x)))
    )
      out[i] = b.box_2d.map(Number);
  }
  return out;
}

// a photo they added of one of their things: one line to know this exact one by
const DESCRIBE = `You look at a photo of one of someone's belongings (named below). Write one short line, under 15 words, that would help them recognise this exact one later: colour, brand or model if you can read it, marks, anything attached. Only what you can see.
Answer ONLY with JSON: {"line": str}`;
export async function describe(
  ctx: any,
  photo: string,
  name: string,
): Promise<string> {
  const { j } = await askJson(ctx, DESCRIBE, `It's their: ${name}`, {
    images: [photo],
    model: VISION,
    temperature: 0.2,
  });
  return String(j?.line ?? '').trim();
}

// ─── a checklist they already have ─────────────────────────────────────────
// any format: the page reads text-like files itself; PDFs and pictures of a
// list go to the model as they are
const CHECKLIST = `You read someone's own travel checklist and turn it into lines for their packing list.
- One line per thing to bring, in their wording, tidied only enough to read as a name ("Phone charging cable"). Keep their quantities.
- category: wardrobe, electronics, toiletries, documents (passport, ID, cards, bookings, insurance), medicine, or other.
- kind: "item" for a thing to pack; "task" for something to do rather than pack ("arrange mobile data", "check charger compatibility").
- note: their own short remark about it, if any ("check expiry", "find it first"); else "".
- Leave out headings, instructions about the checklist itself, buttons and progress counts.
- KNOWN lines are already on their list: if a line is the same thing, set "match" to its key instead of repeating it; otherwise null.
Answer ONLY with JSON: {"title": str (a short name for the checklist), "lines": [{"name": str, "category": str, "kind": "item"|"task", "qty": int, "note": str, "match": str|null}]}`;
export interface ChecklistLine {
  name: string;
  category: Category;
  kind: 'item' | 'task';
  qty: number;
  note: string;
  match: string | null;
}
export async function readChecklist(
  ctx: any,
  src: {
    text?: string;
    images?: string[];
    files?: { name: string; data: string }[];
  },
  known: KnownItem[],
): Promise<{ title: string; lines: ChecklistLine[] }> {
  const { list, resolve } = keyed(known);
  const user = `KNOWN (key | name | category | status):\n${list}\n\nTHE CHECKLIST:\n${src.text ? src.text.slice(0, 30000) : '(attached)'}`;
  const { j } = await askJson(ctx, CHECKLIST, user, {
    images: src.images,
    files: src.files,
    model: VISION,
    temperature: 0.1,
  });
  const lines: ChecklistLine[] = (Array.isArray(j?.lines) ? j.lines : [])
    .filter((x: any) => String(x?.name ?? '').trim())
    .map((x: any) => {
      const name = String(x.name).trim();
      const category = asCategory(x.category);
      return {
        name,
        category,
        kind: x.kind === 'task' ? 'task' : 'item',
        qty: Math.max(1, Math.round(Number(x.qty) || 1)),
        note: String(x.note ?? ''),
        match: resolve(x.match, name, category),
      };
    });
  return { title: String(j?.title ?? '').trim() || 'my checklist', lines };
}

// ─── a list copied from an earlier trip ─────────────────────────────────────
const LEAVE = `Someone started the packing list for a new trip by copying the list from an earlier trip. From the new trip's place, dates, weather and plans, pick the lines that clearly don't fit it (winter clothing for somewhere hot, a plug adapter where their plugs already fit, ski gear with no skiing planned). Only clear cases: when unsure, leave the line on. why: a few words with the reason ("31°C in Penang").
Answer ONLY with JSON: {"leave": [{"key": str, "why": str}]}`;
export async function suggestLeave(
  ctx: any,
  trip: any,
  days: DayWeather[],
  lines: KnownItem[],
): Promise<{ id: string; why: string }[]> {
  if (!lines.length) return [];
  const { list, resolve } = keyed(lines);
  const user = [
    `NEW TRIP: ${trip.place}${trip.stops ? ` (stops: ${trip.stops})` : ''}, ${trip.startDate} to ${trip.endDate}. Home: ${trip.home || 'Malaysia'}. Plans: ${trip.plans || 'not given'}.`,
    `WEATHER:\n${days.map((d) => `${d.date} ${d.place}: ${Math.round(d.lo)} to ${Math.round(d.hi)}°C, ${sky(d.code, d.snow)}`).join('\n') || 'unknown'}`,
    `COPIED LINES (key | name | category):\n${list}`,
  ].join('\n\n');
  const { j } = await askJson(ctx, LEAVE, user, { temperature: 0.2 });
  return (Array.isArray(j?.leave) ? j.leave : [])
    .map((x: any) => ({
      id: resolve(x?.key, '', ''),
      why: String(x?.why ?? ''),
    }))
    .filter((x: any): x is { id: string; why: string } => Boolean(x.id));
}

// ─── the place ───────────────────────────────────────────────────────────
export interface DayWeather {
  date: string;
  place: string;
  hi: number;
  lo: number;
  rain: number; // mm
  snow: number; // cm
  code: number;
  typical: boolean; // last year's same day, not a forecast
}

async function getJson(url: string) {
  const r = await fetch(url);
  if (!r.ok) throw new Error(`${new URL(url).host} said ${r.status}`);
  return r.json();
}

export async function geocode(
  place: string,
): Promise<{ name: string; lat: number; lon: number; country: string } | null> {
  const j = await getJson(
    `https://geocoding-api.open-meteo.com/v1/search?count=1&language=en&format=json&name=${encodeURIComponent(place.split(',')[0].trim())}`,
  );
  const r = j?.results?.[0];
  return r
    ? {
        name: r.name,
        lat: r.latitude,
        lon: r.longitude,
        country: r.country ?? '',
      }
    : null;
}

const iso = (d: Date) => d.toISOString().slice(0, 10);
const addDays = (s: string, n: number) => {
  const d = new Date(`${s}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return iso(d);
};

// a real forecast when the dates are within 16 days; otherwise the same dates
// last year, marked "typical"
export async function weather(
  place: string,
  start: string,
  end: string,
): Promise<DayWeather[]> {
  const g = await geocode(place);
  if (!g) throw new Error(`couldn't find "${place}" on the map`);
  const today = iso(new Date());
  const horizon = addDays(today, 15);
  const daily =
    'temperature_2m_max,temperature_2m_min,precipitation_sum,snowfall_sum,weather_code';
  const out: DayWeather[] = [];
  const push = (j: any, typical: boolean, shift = 0) => {
    const d = j?.daily;
    (d?.time ?? []).forEach((t: string, i: number) =>
      out.push({
        date: shift ? addDays(t, shift) : t,
        place: g.name,
        hi: d.temperature_2m_max[i],
        lo: d.temperature_2m_min[i],
        rain: d.precipitation_sum[i] ?? 0,
        snow: d.snowfall_sum[i] ?? 0,
        code: d.weather_code[i] ?? 0,
        typical,
      }),
    );
  };
  const base = `latitude=${g.lat}&longitude=${g.lon}&daily=${daily}&timezone=auto`;
  if (start <= horizon) {
    const fEnd = end < horizon ? end : horizon;
    const fStart = start < today ? today : start;
    if (fStart <= fEnd)
      push(
        await getJson(
          `https://api.open-meteo.com/v1/forecast?${base}&start_date=${fStart}&end_date=${fEnd}`,
        ),
        false,
      );
  }
  if (end > horizon) {
    const tStart = start > horizon ? start : addDays(horizon, 1);
    const shift = 365;
    push(
      await getJson(
        `https://archive-api.open-meteo.com/v1/archive?${base}&start_date=${addDays(tStart, -shift)}&end_date=${addDays(end, -shift)}`,
      ),
      true,
      shift,
    );
  }
  return out;
}

export const sky = (code: number, snow: number) =>
  snow > 0.5
    ? 'Snow'
    : code >= 95
      ? 'Storms'
      : code >= 71 && code <= 77
        ? 'Snow'
        : code >= 51
          ? 'Rain'
          : code >= 45
            ? 'Fog'
            : code >= 2
              ? 'Cloudy'
              : 'Clear';

export interface Note {
  topic: string;
  text: string;
  source: string; // url
  asOf: string;
}

const RESEARCH = `You are a careful travel researcher. Use web search. For the trip below, find what a traveller from the given home country must know to PACK and PREPARE: power plugs and voltage (vs their home), rules on bringing common medicines, entry or visa basics, money (cash vs card, tax-free shopping rules), getting around, daylight hours, local etiquette that affects what to bring, and anything specific to their plans. Every note must be a fact you found, with the page you found it on. Keep each note to one or two sentences. If a rule is changing soon, say so. Skip anything you could not source.
Answer ONLY with JSON: {"notes": [{"topic": str (2-4 words), "text": str, "source": str (url)}]}`;

export async function research(
  ctx: any,
  t: {
    place: string;
    stops: string;
    start: string;
    end: string;
    home: string;
    plans: string;
  },
): Promise<Note[]> {
  const user = `Trip: ${t.place}${t.stops ? ` (stops: ${t.stops})` : ''}, ${t.start} to ${t.end}. Home country: ${t.home || 'Malaysia'}. Plans: ${t.plans || 'not given'}.`;
  const { j, cites } = await askJson(ctx, RESEARCH, user, {
    model: RESEARCHER,
    temperature: 0.2,
  });
  const asOf = iso(new Date());
  const notes: Note[] = (Array.isArray(j?.notes) ? j.notes : [])
    .filter((n: any) => n?.text)
    .map((n: any) => ({
      topic: String(n.topic ?? ''),
      text: String(n.text),
      source: String(n.source ?? ''),
      asOf,
    }));
  // a note without a link borrows a citation the search returned, if any
  return notes.map((n, i) =>
    n.source.startsWith('http') ? n : { ...n, source: cites[i]?.url ?? '' },
  );
}

// ─── the trip's colours ──────────────────────────────────────────────────
export interface Palette {
  name: string; // "Hokkaido in November: first snow, deep sea, lantern red"
  colors: { hex: string; what: string }[];
}
const PALETTE = `You choose the colours for one trip's travel card: what the place looks like at that time of year. Pick exactly 3 colours a traveller would recognise from there: its sky, its land or sea, and one thing the place is known for. Each a clear, fairly saturated colour, never grey, beige or near-black, and three clearly different hues (not two shades of one colour).
Answer ONLY with JSON: {"name": str (a short caption, "<place> in <month>: <three 1-3 word things>"), "colors": [{"hex": "#rrggbb", "what": str (1-3 words)}]}`;

export async function palette(
  ctx: any,
  place: string,
  start: string,
): Promise<Palette | null> {
  const month = /^\d{4}-\d{2}/.test(start ?? '')
    ? new Date(`${start.slice(0, 7)}-15T00:00:00Z`).toLocaleString('en', {
        month: 'long',
        timeZone: 'UTC',
      })
    : 'no particular month';
  const { j } = await askJson(
    ctx,
    PALETTE,
    `Place: ${place}. Month: ${month}.`,
    { model: WRITER, temperature: 0.4 },
  );
  const colors = (Array.isArray(j?.colors) ? j.colors : [])
    .filter((c: any) => /^#[0-9a-f]{6}$/i.test(c?.hex ?? ''))
    .slice(0, 3);
  return colors.length === 3
    ? {
        name: String(j?.name ?? place),
        colors: colors.map((c: any) => ({
          hex: c.hex,
          what: String(c.what ?? ''),
        })),
      }
    : null;
}

// ─── the list ────────────────────────────────────────────────────────────
export interface Need {
  match: string | null;
  name: string;
  category: Category;
  qty: number;
  why: string;
  litres: number;
  kg: number;
}
export interface Plan {
  needs: Need[];
  extras: { id: string; why: string }[]; // seen, but probably not worth bringing
  dossier: string;
}

const PLANNER = `You plan what someone should pack, from the trip, the weather, sourced notes about the place, and what they already own (things the camera has seen). You write the trip dossier: the short document any helper can pick the trip up from.
- needs: everything they should bring, by category (wardrobe, electronics, toiletries, documents, medicine, other). Counts follow the days and the weather, with re-wearing and one laundry for trips over 5 days (e.g. 7 days: 4 tops, 2 bottoms, 1 warm mid layer, 1 shell). Tie each need to its reason in a few words ("snow on day 3", "Type A plugs", "onsen: small towel"). If something ON THE LIST fills the need (whatever its status), set "match" to its key (e.g. "i4") so it isn't listed twice; otherwise null and name what to get or find.
- extras: items on the list with status "have", or "needed" lines copied from an earlier trip ("from an earlier trip"), that are clearly no use on this trip (sandals in snow, a swimsuit with no water plans): {"key", "why"}. These are only suggestions they'll see; when an item could plausibly be useful (a layer, something to wear out, a personal favourite), leave it off extras. Usually zero to two.
- Items with status "owned, not on this list" are things they own from earlier trips: when one fills a need, set "match" to its key rather than naming something new.
- Status "skip" means they decided not to bring it: don't list it as a need again unless the trip truly can't do without it, and then say why in a few words.
- Respect what they already decided; don't pile on generic advice. Be concrete for this place and these dates.
- Get local custom right, and don't make work: Japanese onsen are bathed in nude (no swimsuit; a small towel); most phone and laptop chargers are 100-240 V and need only a plug adapter, not a voltage converter. When unsure, say "check" rather than prescribe.
- dossier (markdown, under 300 words): # Trip: <place> · ## Trip (dates, plans, bag) · ## Weather (one line per stop: range, rain/snow days, whether forecast or typical) · ## Notes that matter (only the ones that change packing) · ## Packing state (counts per category, the gaps) · ## Next moves (1-3, e.g. "photograph shoes and toiletries").
Answer ONLY with JSON: {"needs": [{"match": str|null, "name": str, "category": str, "qty": int, "why": str, "litres": number (packed volume of one), "kg": number (one)}], "extras": [{"key": str, "why": str}], "dossier": str}`;

export async function plan(
  ctx: any,
  trip: any,
  days: DayWeather[],
  notes: Note[],
  owned: KnownItem[],
  bag: BagSeen | null,
): Promise<Plan> {
  const { list, resolve } = keyed(owned);
  const user = [
    `TRIP: ${trip.place}${trip.stops ? ` (stops: ${trip.stops})` : ''}, ${trip.startDate} to ${trip.endDate}. Home: ${trip.home || 'Malaysia'}. Travelling solo. Plans: ${trip.plans || 'not given'}.`,
    `BAG: ${bag ? `${bag.type}, about ${bag.litres} L${bag.carryOn ? ', cabin size' : ''}` : 'not photographed yet'}. Baggage allowance: ${trip.allowanceKg || 'unknown'} kg.`,
    `WEATHER:\n${days.map((d) => `${d.date} ${d.place}: ${Math.round(d.lo)} to ${Math.round(d.hi)}°C, ${sky(d.code, d.snow)}${d.snow > 0.5 ? `, ${d.snow.toFixed(0)} cm snow` : d.rain > 1 ? `, ${d.rain.toFixed(0)} mm rain` : ''}${d.typical ? ' (typical)' : ''}`).join('\n') || 'unknown'}`,
    `NOTES:\n${notes.map((n) => `- ${n.topic}: ${n.text}`).join('\n') || 'none yet'}`,
    `ON THE LIST (key | name | category | status):\n${list}`,
  ].join('\n\n');
  const { j } = await askJson(ctx, PLANNER, user, { temperature: 0.3 });
  return {
    needs: (Array.isArray(j?.needs) ? j.needs : [])
      .filter((n: any) => n?.name)
      .map((n: any) => ({
        match: resolve(n.match, String(n.name), asCategory(n.category)),
        name: String(n.name),
        category: asCategory(n.category),
        qty: Math.max(1, Math.round(Number(n.qty) || 1)),
        why: String(n.why ?? ''),
        litres: Math.max(0, Number(n.litres) || 0),
        kg: Math.max(0, Number(n.kg) || 0),
      })),
    extras: (Array.isArray(j?.extras) ? j.extras : [])
      .map((x: any) => ({
        id: resolve(x?.key ?? x?.id, '', ''),
        why: String(x?.why ?? ''),
      }))
      .filter((x: any): x is { id: string; why: string } => Boolean(x.id)),
    dossier: typeof j?.dossier === 'string' ? j.dossier : '',
  };
}
