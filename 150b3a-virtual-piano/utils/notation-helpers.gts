import { KEYBOARD_MAPPING } from './keyboard-helpers';

/* ═══════════════════════════════════════════════════════════════════════════
   BEAT PARSER
   VP.net notation rules:
     • Whitespace separates groups (phrase chunks)
     • Within a group, each CHARACTER = one beat played in sequence
     • [abc] inside a group = one chord beat (all keys simultaneously)
     • -  = rest beat (silence)
     • |  = phrase pause / timing separator
   ─────────────────────────────────────────────────────────────────────────
   Example: "pf[80wp]" → beat(p), beat(f), chord-beat(8,0,w,p)
   ═══════════════════════════════════════════════════════════════════════════ */
export interface Beat {
  keys: string[]; /* keys to press; empty = rest */
  isChord: boolean; /* true when multiple keys from [...] */
  isPause: boolean; /* rest or phrase divider */
  display: string; /* what to render in the sheet */
}

export function parseNotationBeats(notation: string): Beat[] {
  const beats: Beat[] = [];
  const chunks = notation.split(/\s+/).filter((t) => t.length > 0);
  for (const chunk of chunks) {
    let i = 0;
    while (i < chunk.length) {
      if (chunk[i] === '[') {
        const end = chunk.indexOf(']', i);
        if (end === -1) {
          i++;
          continue;
        }
        const inner = chunk.slice(i + 1, end);
        const keys = inner.split('').filter((k) => k in KEYBOARD_MAPPING);
        beats.push({
          keys,
          isChord: true,
          isPause: false,
          display: `[${inner}]`,
        });
        i = end + 1;
      } else if (chunk[i] === '-') {
        beats.push({ keys: [], isChord: false, isPause: true, display: '—' });
        i++;
      } else if (chunk[i] === '|') {
        beats.push({ keys: [], isChord: false, isPause: true, display: '|' });
        i++;
      } else {
        const k = chunk[i]!;
        if (k in KEYBOARD_MAPPING) {
          beats.push({ keys: [k], isChord: false, isPause: false, display: k });
        }
        i++;
      }
    }
  }
  return beats;
}
