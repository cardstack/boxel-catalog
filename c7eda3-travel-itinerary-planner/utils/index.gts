import { htmlSafe } from '@ember/template';

export const DEFAULT_STOP_COLOR = '#ff385c';

// The fixed set of trip categories. These drive the `category` enum field on
// each stop and the colour-coding on the map and stop rows. `value` is what's
// stored on the card; `label` (with the emoji) is what the dropdown shows.
export interface CategoryOption {
  value: string;
  label: string;
  emoji: string;
  color: string;
}

export const TRIP_CATEGORIES: CategoryOption[] = [
  { value: 'Food & Dining', emoji: '🍜', color: '#F97316' },
  { value: 'Culture & History', emoji: '🏛️', color: '#7C3AED' },
  { value: 'Nature & Outdoors', emoji: '🌿', color: '#16A34A' },
  { value: 'Sightseeing', emoji: '📸', color: '#3B82F6' },
  { value: 'Relaxation', emoji: '💆', color: '#0D9488' },
  { value: 'Café & Coffee', emoji: '☕', color: '#B45309' },
  { value: 'Museum', emoji: '🖼️', color: '#8B5CF6' },
  { value: 'Nightlife', emoji: '🌃', color: '#6366F1' },
  { value: 'Performance', emoji: '🎭', color: '#EC4899' },
  { value: 'Shopping', emoji: '🛍️', color: '#DB2777' },
].map((c) => ({ ...c, label: `${c.value} ${c.emoji}` }));

export function categoryOption(
  value?: string | null,
): CategoryOption | undefined {
  if (!value) return undefined;
  let key = value.trim().toLowerCase();
  return TRIP_CATEGORIES.find((c) => c.value.toLowerCase() === key);
}

// Common synonyms → canonical category, so a near-miss from the LLM (or a
// typed request like "temple", "spa", "bar") still maps to a real enum value.
const CATEGORY_KEYWORDS: { match: string; value: string }[] = [
  { match: 'temple', value: 'Culture & History' },
  { match: 'shrine', value: 'Culture & History' },
  { match: 'historic', value: 'Culture & History' },
  { match: 'history', value: 'Culture & History' },
  { match: 'culture', value: 'Culture & History' },
  { match: 'landmark', value: 'Sightseeing' },
  { match: 'monument', value: 'Sightseeing' },
  { match: 'viewpoint', value: 'Sightseeing' },
  { match: 'sightsee', value: 'Sightseeing' },
  { match: 'museum', value: 'Museum' },
  { match: 'gallery', value: 'Museum' },
  { match: 'exhibit', value: 'Museum' },
  { match: 'park', value: 'Nature & Outdoors' },
  { match: 'garden', value: 'Nature & Outdoors' },
  { match: 'beach', value: 'Nature & Outdoors' },
  { match: 'hike', value: 'Nature & Outdoors' },
  { match: 'nature', value: 'Nature & Outdoors' },
  { match: 'outdoor', value: 'Nature & Outdoors' },
  { match: 'coffee', value: 'Café & Coffee' },
  { match: 'cafe', value: 'Café & Coffee' },
  { match: 'tea', value: 'Café & Coffee' },
  { match: 'restaurant', value: 'Food & Dining' },
  { match: 'food', value: 'Food & Dining' },
  { match: 'dining', value: 'Food & Dining' },
  { match: 'dinner', value: 'Food & Dining' },
  { match: 'lunch', value: 'Food & Dining' },
  { match: 'breakfast', value: 'Food & Dining' },
  { match: 'bar', value: 'Nightlife' },
  { match: 'club', value: 'Nightlife' },
  { match: 'nightlife', value: 'Nightlife' },
  { match: 'shop', value: 'Shopping' },
  { match: 'market', value: 'Shopping' },
  { match: 'mall', value: 'Shopping' },
  { match: 'boutique', value: 'Shopping' },
  { match: 'show', value: 'Performance' },
  { match: 'concert', value: 'Performance' },
  { match: 'theater', value: 'Performance' },
  { match: 'theatre', value: 'Performance' },
  { match: 'performance', value: 'Performance' },
  { match: 'spa', value: 'Relaxation' },
  { match: 'relax', value: 'Relaxation' },
  { match: 'wellness', value: 'Relaxation' },
];

// Strip case, accents, emoji, and punctuation so "Café & Coffee", "cafe
// coffee", and "Cafe&Coffee ☕" all reduce to the same key.
function normalizeCategoryKey(s: string): string {
  // NFD splits accented letters into base + combining mark; the final filter
  // keeps only a–z/0–9, dropping the marks, emoji, spaces, and punctuation.
  return s
    .toLowerCase()
    .normalize('NFD')
    .replace(/[^a-z0-9]/g, '');
}

// Map an arbitrary category string back to a canonical enum value: exact
// (normalized) match first, then substring either way, then keyword synonyms.
// Returns undefined when nothing plausibly matches.
export function matchCategory(raw?: string | null): string | undefined {
  if (!raw) return undefined;
  let key = normalizeCategoryKey(raw);
  if (!key) return undefined;
  let exact = TRIP_CATEGORIES.find(
    (c) => normalizeCategoryKey(c.value) === key,
  );
  if (exact) return exact.value;
  let partial = TRIP_CATEGORIES.find((c) => {
    let ck = normalizeCategoryKey(c.value);
    return key.includes(ck) || ck.includes(key);
  });
  if (partial) return partial.value;
  let kw = CATEGORY_KEYWORDS.find((k) => key.includes(k.match));
  return kw?.value;
}

export function categoryColor(value?: string | null): string {
  return categoryOption(value)?.color || DEFAULT_STOP_COLOR;
}

export function accentStyle(color: string | undefined | null) {
  return htmlSafe(`--stop-color:${color || DEFAULT_STOP_COLOR}`);
}

// Convenience: build the `--stop-color` style straight from a category value.
export function categoryStyle(value: string | undefined | null) {
  return accentStyle(categoryColor(value));
}

export function addHours(time: string | undefined, hours: number) {
  let [hh, mm] = (time || '09:00').split(':').map(Number);
  let total = Math.min(23 * 60 + 59, (hh || 0) * 60 + (mm || 0) + hours * 60);
  let nh = Math.floor(total / 60);
  let nm = total % 60;
  return `${String(nh).padStart(2, '0')}:${String(nm).padStart(2, '0')}`;
}

export interface PlannedStop {
  day: number;
  name: string;
  // null when seeded from an existing stop that has no coordinates yet
  lat: number | null;
  lon: number | null;
  startTime: string;
  endTime: string;
  notes?: string;
  category?: string;
}

export function normalizeTime(value: unknown, fallback: string): string {
  if (typeof value !== 'string') return fallback;
  let m = value.trim().match(/^(\d{1,2}):(\d{2})/);
  if (!m) return fallback;
  let hh = Math.min(23, Number(m[1]));
  let mm = Math.min(59, Number(m[2]));
  return `${String(hh).padStart(2, '0')}:${String(mm).padStart(2, '0')}`;
}

// What the planner needs the traveller to pick before it can replan. Set on
// a revision when the request is too vague to act on (e.g. "change the vibe"
// without naming one) — the UI shows the matching control.
export type PlannerNeed = 'location' | 'dates' | 'vibe';

export interface PlannedTrip {
  // Short trip name the LLM proposes; applied to tripTitle + cardInfo.name.
  tripTitle?: string;
  // One short, human sentence describing the plan / what just changed.
  summary?: string;
  // The final plan's recap as bullet points, rendered as a <ul> beneath the
  // itinerary preview.
  summaryItems?: string[];
  // When set, the plan is unchanged and the UI must collect this input first.
  needs?: PlannerNeed;
  stops: PlannedStop[];
}

// The one-shot LLM is asked for strict JSON, but tolerate markdown fences
// and surrounding prose, and drop any stop missing a name or coordinates.
export function parsePlanJson(raw: string): PlannedTrip | null {
  if (!raw) return null;
  let text = raw.trim();
  let fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (fenced) text = fenced[1].trim();
  let parsed: any = null;
  try {
    parsed = JSON.parse(text);
  } catch {
    let start = text.indexOf('{');
    let end = text.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      parsed = JSON.parse(text.slice(start, end + 1));
    } catch {
      return null;
    }
  }
  let stops = Array.isArray(parsed) ? parsed : parsed?.stops;
  if (!Array.isArray(stops)) return null;
  let out: PlannedStop[] = [];
  for (let s of stops) {
    let name = typeof s?.name === 'string' ? s.name.trim() : '';
    let lat = Number(s?.lat);
    let lon = Number(s?.lon);
    if (!name || !Number.isFinite(lat) || !Number.isFinite(lon)) continue;
    let startTime = normalizeTime(s?.startTime, '09:00');
    out.push({
      day: Math.max(1, Math.round(Number(s?.day)) || 1),
      name,
      lat,
      lon,
      startTime,
      endTime: normalizeTime(s?.endTime, addHours(startTime, 2)),
      notes: typeof s?.notes === 'string' ? s.notes.trim() : undefined,
      category: typeof s?.category === 'string' ? s.category.trim() : undefined,
    });
  }
  if (!out.length) return null;
  out.sort((a, b) => a.day - b.day || a.startTime.localeCompare(b.startTime));
  let tripTitle =
    !Array.isArray(parsed) && typeof parsed?.tripTitle === 'string'
      ? parsed.tripTitle.trim() || undefined
      : undefined;
  let summary =
    !Array.isArray(parsed) && typeof parsed?.summary === 'string'
      ? parsed.summary.trim() || undefined
      : undefined;
  return { tripTitle, summary, stops: out };
}

// Great-circle distance in km between two points.
function haversineKm(
  a: { lat: number; lon: number },
  b: { lat: number; lon: number },
): number {
  let R = 6371;
  let toRad = (d: number) => (d * Math.PI) / 180;
  let dLat = toRad(b.lat - a.lat);
  let dLon = toRad(b.lon - a.lon);
  let h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(h)));
}

function isFiniteNum(n: unknown): n is number {
  return typeof n === 'number' && Number.isFinite(n);
}

// Resolve a place name to precise coordinates via Photon (komoot's free,
// CORS-enabled, OpenStreetMap-based geocoder — no API key, lenient limits).
// LLMs are unreliable at recalling exact lat/lon, so we trust them only for the
// place NAME and resolve real coordinates here. To stop a same-named place on
// another continent from winning (e.g. an "Imbi Market" in Kenya beating the
// one in Kuala Lumpur), pass an `anchor` (the trip's region centre) and a
// `maxKm` radius: candidates outside the radius are discarded, and proximity to
// the anchor breaks ties between equally-good name matches. Resolves to null on
// any failure (or when nothing falls inside the radius) so callers can fall
// back to whatever coordinates they already have.
export async function geocodePlace(
  name: string,
  opts?: {
    bias?: { lat?: number | null; lon?: number | null };
    context?: string; // destination/region to disambiguate (e.g. "Lombok, Indonesia")
    anchor?: { lat: number; lon: number }; // region centre to keep results near
    maxKm?: number; // discard candidates farther than this from the anchor
    maxBiasKm?: number; // when biased, reject a match that jumps farther than this from the bias (refine, don't relocate)
  },
): Promise<{ lat: number; lon: number } | null> {
  let name0 = name.trim();
  if (!name0) return null;
  // Including the destination steers the geocoder to the right region instead
  // of a same-named place on the other side of the world.
  let context = opts?.context?.trim();
  let q = context ? `${name0}, ${context}` : name0;
  let url = `https://photon.komoot.io/api/?q=${encodeURIComponent(q)}&limit=10`;
  let bias = opts?.bias;
  if (bias && isFiniteNum(bias.lat) && isFiniteNum(bias.lon)) {
    url += `&lat=${bias.lat}&lon=${bias.lon}`;
  }
  let anchor =
    opts?.anchor && isFiniteNum(opts.anchor.lat) && isFiniteNum(opts.anchor.lon)
      ? opts.anchor
      : undefined;
  // The per-stop bias (the LLM's rough coords for THIS place) locates the right
  // neighbourhood. Use it to break ties — never the region centre, which would
  // wrongly drag every ambiguous pin toward downtown.
  let biasPoint =
    bias && isFiniteNum(bias.lat) && isFiniteNum(bias.lon)
      ? { lat: bias.lat, lon: bias.lon }
      : undefined;
  try {
    let res = await fetch(url);
    if (!res.ok) return null;
    let data = await res.json();
    let features: any[] = Array.isArray(data?.features) ? data.features : [];
    if (!features.length) return null;

    let target = name0.toLowerCase();
    let nameScore = (f: any): number => {
      let fname = String(f?.properties?.name ?? '').toLowerCase();
      if (!fname) return 0;
      if (fname === target) return 3;
      if (fname.includes(target) || target.includes(fname)) return 2;
      return 1;
    };

    let scored = features
      .map((f) => {
        let coords = f?.geometry?.coordinates;
        let lon = Number(coords?.[0]);
        let lat = Number(coords?.[1]);
        let valid = isFiniteNum(lat) && isFiniteNum(lon);
        // distAnchor: distance to the region centre — used only for the radius
        // gate. tieDist: distance to the per-stop bias (fallback: the anchor) —
        // used to pick among equally-good name matches.
        let distAnchor =
          valid && anchor ? haversineKm({ lat, lon }, anchor) : Infinity;
        let tieDist = valid
          ? biasPoint
            ? haversineKm({ lat, lon }, biasPoint)
            : distAnchor
          : Infinity;
        return { lat, lon, valid, score: nameScore(f), distAnchor, tieDist };
      })
      .filter((c) => c.valid);
    if (!scored.length) return null;

    // With a trusted region anchor, drop anything outside the radius — better
    // to return null (and keep the caller's existing coords) than a far-flung
    // namesake.
    if (anchor && opts?.maxKm != null) {
      let inRegion = scored.filter((c) => c.distAnchor <= opts!.maxKm!);
      if (!inRegion.length) return null;
      scored = inRegion;
    }

    // Best name match wins; proximity to the stop's own rough coords breaks ties.
    let best = scored.sort(
      (a, b) => b.score - a.score || a.tieDist - b.tieDist,
    )[0];

    // When the stop already has rough coords, geocoding should only REFINE them,
    // not relocate the pin. If the only matches are weak (no real name match) or
    // the best match jumps far from the stop's own position, trust the existing
    // coords instead of a guess (return null → caller keeps them).
    if (biasPoint) {
      if (best.score < 2) return null;
      if (best.tieDist > (opts?.maxBiasKm ?? 25)) return null;
    }
    return { lat: best.lat, lon: best.lon };
  } catch {
    return null;
  }
}

// Drop accidental repeats — the same place named twice on the same day — while
// allowing the same place to legitimately recur on a different day.
function dedupeStops(stops: PlannedStop[]): PlannedStop[] {
  let seen = new Set<string>();
  let out: PlannedStop[] = [];
  for (let s of stops) {
    let key = `${s.day}::${(s.name ?? '').trim().toLowerCase()}`;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(s);
  }
  return out;
}

// Refine a plan's stops with real coordinates. First resolve the destination
// itself to a region centre, then geocode every stop anchored to that centre
// (within ~100km) so each lands on the correct same-named place. A stop that
// can't be resolved inside the region keeps its original coordinates.
export async function geocodePlannedStops(
  stops: PlannedStop[],
  context?: string,
): Promise<PlannedStop[]> {
  let deduped = dedupeStops(stops);
  let destAnchor = context ? await geocodePlace(context) : null;
  return Promise.all(
    deduped.map(async (s) => {
      let perStop =
        isFiniteNum(s.lat) && isFiniteNum(s.lon)
          ? { lat: s.lat, lon: s.lon }
          : undefined;
      let anchor = destAnchor ?? perStop;
      let resolved = await geocodePlace(s.name, {
        context,
        bias: { lat: s.lat, lon: s.lon },
        anchor: anchor ?? undefined,
        // Only hard-filter by radius when we trust the destination centre; a
        // per-stop fallback anchor just guides tie-breaking.
        maxKm: destAnchor ? 100 : undefined,
      });
      return resolved ? { ...s, lat: resolved.lat, lon: resolved.lon } : s;
    }),
  );
}
