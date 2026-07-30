// Whether the palette says anything.
//
// A reply that gives every part the same mid-grey has technically satisfied
// the schema and produced a model nobody can read. This reports a palette that
// has collapsed, so the caller can ask again rather than ship it.

// A reference of brass-gold plates, dark teal panels, black rubber, red hub
// lights and bare steel blades came back as twelve materials of which nine sat
// inside one 40° olive band — a uniformly muddy object. The cause is sampling:
// the analysis is told to take colours from the flattest-lit panel and instead
// read them off the warm-lit beauty render, where everything is the same colour
// of gold.
//
// Judging a palette by its hue spread would be wrong — plenty of objects really
// are monochrome, and a wine bottle's glass, paper and cap legitimately live near
// each other. What IS object-agnostic is near-duplicates: declaring two materials
// that nobody could tell apart means the spec spent two slots to describe one
// surface, and whatever distinction the reference drew between those parts has
// been lost. Report only — which of the two should change is a judgement about
// the photo, not the numbers.
export function flagFlatPalette(parsed: any): string[] {
  let logs: string[] = [];
  let materials: any[] = parsed?.materials ?? [];
  if (materials.length < 3) return logs;
  let rgb = (hex: any): [number, number, number] | undefined => {
    let s = String(hex ?? '').trim();
    if (!/^#[0-9a-fA-F]{6}$/.test(s)) return undefined;
    return [
      parseInt(s.slice(1, 3), 16),
      parseInt(s.slice(3, 5), 16),
      parseInt(s.slice(5, 7), 16),
    ];
  };
  let entries = materials
    .map((m: any) => ({
      id: m?.materialId,
      c: rgb(m?.baseColor),
      finish: m?.finish,
    }))
    .filter((e) => e.id && e.c) as {
    id: string;
    c: [number, number, number];
    finish?: string;
  }[];
  if (entries.length < 3) return logs;
  // a rough perceptual distance: weight green most, blue least, the way the eye
  // does. ~12 is about where two swatches stop being distinguishable side by side
  const INDISTINGUISHABLE = 12;
  let distance = (a: [number, number, number], b: [number, number, number]) => {
    let dr = a[0] - b[0];
    let dg = a[1] - b[1];
    let db = a[2] - b[2];
    return Math.sqrt(2 * dr * dr + 4 * dg * dg + 3 * db * db) / 3;
  };
  // hazard, camo and louver carry their colours INSIDE the painted map — the
  // interpreter neutralises the material's own colour to white for them — so two
  // such materials say nothing about each other's baseColor. worn, brushed,
  // patina, tread and knurl only modulate the paint underneath, so their base
  // colours are still what you see and remain comparable.
  let colourReplaced = (f: any) =>
    f === 'hazard' || f === 'camo' || f === 'louver';
  let pairs: string[] = [];
  for (let i = 0; i < entries.length; i++) {
    for (let j = i + 1; j < entries.length; j++) {
      if (
        colourReplaced(entries[i].finish) ||
        colourReplaced(entries[j].finish)
      ) {
        continue;
      }
      if (distance(entries[i].c, entries[j].c) < INDISTINGUISHABLE) {
        pairs.push(`'${entries[i].id}' and '${entries[j].id}'`);
      }
    }
  }
  if (pairs.length) {
    logs.push(
      `${pairs.length} material pair(s) are visually the same colour — ${pairs.slice(0, 3).join(', ')}${pairs.length > 3 ? ', …' : ''}: the reference likely draws a distinction here that the sampling lost`,
    );
  }

  // And the case a duplicate check structurally cannot catch: not two materials
  // being identical, but ALL of them living in one hue family. That is what turns
  // a brass-and-teal machine into uniform mud, and it comes from sampling a
  // warm-lit render instead of a flat panel. Whether it is WRONG depends on the
  // object — plenty of things really are monochrome — so this reports the
  // measurement and lets a human or the refine round judge it.
  let hue = ([r, g, b]: [number, number, number]) => {
    let max = Math.max(r, g, b);
    let min = Math.min(r, g, b);
    if (max === min) return undefined; // grey has no hue
    let d = max - min;
    let h =
      max === r
        ? ((g - b) / d) % 6
        : max === g
          ? (b - r) / d + 2
          : (r - g) / d + 4;
    return (((h * 60) % 360) + 360) % 360;
  };
  let hues = entries
    .filter((e) => !colourReplaced(e.finish))
    .map((e) => hue(e.c))
    .filter((h): h is number => h !== undefined);
  // below half a dozen hues the observation is not evidence of anything: a wine
  // bottle's olive glass, cream label, dark cap and gold band genuinely share the
  // warm band, and 3-of-4 would "prove" it was sampled badly when it was not
  if (hues.length >= 6) {
    // widest band containing the most hues, sliding a 40° window
    let best = 0;
    let bestAt = 0;
    for (let start = 0; start < 360; start += 5) {
      let inBand = hues.filter((h) => {
        let rel = (h - start + 360) % 360;
        return rel <= 40;
      }).length;
      if (inBand > best) {
        best = inBand;
        bestAt = start;
      }
    }
    if (best / hues.length >= 0.7) {
      logs.push(
        `${best} of ${hues.length} colours sit inside a single 40° hue band (${bestAt}°-${bestAt + 40}°) — if the reference is more varied than that, the palette was sampled from a lit render rather than a flat view`,
      );
    }
  }
  return logs;
}
