import { htmlSafe } from '@ember/template';

export const DEFAULT_STOP_COLOR = '#ff385c';

// Sentinel chip value on the destination step that reveals the free-text
// input instead of answering directly.
export const OTHER_DESTINATION = '__other__';

// The fixed set of trip categories. These drive the `category` enum field on
// each stop, the vibe chips in the AI planner, and the colour-coding on the
// map and stop rows. `value` is what's stored on the card; `label` (with the
// emoji) is what the dropdown / chips show.
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

export const CATEGORY_NAMES: string[] = TRIP_CATEGORIES.map((c) => c.value);

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

export function categoryEmoji(value?: string | null): string {
  return categoryOption(value)?.emoji || '';
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

export interface ChatMessage {
  role: 'ai' | 'user';
  text: string;
  kind?: 'error';
}

export interface ChipOption {
  label: string;
  value: string;
}

export type PlannerStep = 'destination' | 'days' | 'vibe' | 'ready';

export interface PlannerAnswers {
  destination?: string;
  days?: number;
  dates?: { start: Date; end: Date };
  vibe?: string;
}

export function formatShortDate(d: Date): string {
  return d.toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  });
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

// Resolve a place name to precise coordinates via Photon (komoot's free,
// CORS-enabled, OpenStreetMap-based geocoder — no API key, lenient limits). An
// optional bias point nudges the search toward the right area when a name is
// ambiguous (e.g. a café chain). LLMs are unreliable at recalling exact
// lat/lon, so we trust them only for the place NAME and resolve real
// coordinates here. Resolves to null on any failure so callers can fall back to
// whatever coordinates they already have.
export async function geocodePlace(
  name: string,
  opts?: {
    bias?: { lat?: number | null; lon?: number | null };
    context?: string; // destination/region to disambiguate (e.g. "Lombok, Indonesia")
  },
): Promise<{ lat: number; lon: number } | null> {
  let name0 = name.trim();
  if (!name0) return null;
  // Including the destination steers the geocoder to the right region instead
  // of a same-named place on the other side of the world.
  let context = opts?.context?.trim();
  let q = context ? `${name0}, ${context}` : name0;
  let url = `https://photon.komoot.io/api/?q=${encodeURIComponent(q)}&limit=5`;
  let bias = opts?.bias;
  if (
    bias &&
    typeof bias.lat === 'number' &&
    typeof bias.lon === 'number' &&
    Number.isFinite(bias.lat) &&
    Number.isFinite(bias.lon)
  ) {
    url += `&lat=${bias.lat}&lon=${bias.lon}`;
  }
  try {
    let res = await fetch(url);
    if (!res.ok) return null;
    let data = await res.json();
    let features: any[] = Array.isArray(data?.features) ? data.features : [];
    if (!features.length) return null;
    // Prefer the feature whose own name best matches the place name; the raw
    // first result is often a broader area or a weaker match.
    let target = name0.toLowerCase();
    let nameScore = (f: any): number => {
      let fname = String(f?.properties?.name ?? '').toLowerCase();
      if (!fname) return 0;
      if (fname === target) return 3;
      if (fname.includes(target) || target.includes(fname)) return 2;
      return 1;
    };
    let best = features
      .map((f) => ({ f, score: nameScore(f) }))
      .sort((a, b) => b.score - a.score)[0];
    let coords = best?.f?.geometry?.coordinates;
    if (!Array.isArray(coords) || coords.length < 2) return null;
    let lon = Number(coords[0]);
    let lat = Number(coords[1]);
    if (!Number.isFinite(lat) || !Number.isFinite(lon)) return null;
    return { lat, lon };
  } catch {
    return null;
  }
}

// Refine a plan's stops with real coordinates: geocode each stop by name
// (disambiguated by the trip destination, biased to the LLM's rough
// coordinates). A stop that fails to geocode keeps its original coordinates.
export async function geocodePlannedStops(
  stops: PlannedStop[],
  context?: string,
): Promise<PlannedStop[]> {
  return Promise.all(
    stops.map(async (s) => {
      let resolved = await geocodePlace(s.name, {
        bias: { lat: s.lat, lon: s.lon },
        context,
      });
      return resolved ? { ...s, lat: resolved.lat, lon: resolved.lon } : s;
    }),
  );
}
