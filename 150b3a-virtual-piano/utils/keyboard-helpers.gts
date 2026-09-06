/* ═══════════════════════════════════════════════════════════════════════════
   VP.NET KEYBOARD MAPPING — 61 keys C2–C7
   ─────────────────────────────────────────────────────────────────────────
   White keys per octave:
     Oct 2: 1 2 3 4 5 6 7
     Oct 3: 8 9 0 q w e r
     Oct 4: t y u i o p a        ← Middle C (t = C4)
     Oct 5: s d f g h j k
     Oct 6: l z x c v b n
     C7 only: m

   Black keys (Shift+key):
     Oct 2: ! @ $ % ^
     Oct 3: * ( Q W E
     Oct 4: T Y I O P
     Oct 5: S D G H J
     Oct 6: L Z C V B
   ═══════════════════════════════════════════════════════════════════════════ */
export const KEYBOARD_MAPPING: Record<
  string,
  { note: string; octave: number }
> = {
  /* oct 2 */ '1': { note: 'C', octave: 2 },
  '!': { note: 'C#', octave: 2 },
  '2': { note: 'D', octave: 2 },
  '@': { note: 'D#', octave: 2 },
  '3': { note: 'E', octave: 2 },
  '4': { note: 'F', octave: 2 },
  $: { note: 'F#', octave: 2 },
  '5': { note: 'G', octave: 2 },
  '%': { note: 'G#', octave: 2 },
  '6': { note: 'A', octave: 2 },
  '^': { note: 'A#', octave: 2 },
  '7': { note: 'B', octave: 2 },
  /* oct 3 */ '8': { note: 'C', octave: 3 },
  '*': { note: 'C#', octave: 3 },
  '9': { note: 'D', octave: 3 },
  '(': { note: 'D#', octave: 3 },
  '0': { note: 'E', octave: 3 },
  q: { note: 'F', octave: 3 },
  Q: { note: 'F#', octave: 3 },
  w: { note: 'G', octave: 3 },
  W: { note: 'G#', octave: 3 },
  e: { note: 'A', octave: 3 },
  E: { note: 'A#', octave: 3 },
  r: { note: 'B', octave: 3 },
  /* oct 4 */ t: { note: 'C', octave: 4 },
  T: { note: 'C#', octave: 4 },
  y: { note: 'D', octave: 4 },
  Y: { note: 'D#', octave: 4 },
  u: { note: 'E', octave: 4 },
  i: { note: 'F', octave: 4 },
  I: { note: 'F#', octave: 4 },
  o: { note: 'G', octave: 4 },
  O: { note: 'G#', octave: 4 },
  p: { note: 'A', octave: 4 },
  P: { note: 'A#', octave: 4 },
  a: { note: 'B', octave: 4 },
  /* oct 5 */ s: { note: 'C', octave: 5 },
  S: { note: 'C#', octave: 5 },
  d: { note: 'D', octave: 5 },
  D: { note: 'D#', octave: 5 },
  f: { note: 'E', octave: 5 },
  g: { note: 'F', octave: 5 },
  G: { note: 'F#', octave: 5 },
  h: { note: 'G', octave: 5 },
  H: { note: 'G#', octave: 5 },
  j: { note: 'A', octave: 5 },
  J: { note: 'A#', octave: 5 },
  k: { note: 'B', octave: 5 },
  /* oct 6 */ l: { note: 'C', octave: 6 },
  L: { note: 'C#', octave: 6 },
  z: { note: 'D', octave: 6 },
  Z: { note: 'D#', octave: 6 },
  x: { note: 'E', octave: 6 },
  c: { note: 'F', octave: 6 },
  C: { note: 'F#', octave: 6 },
  v: { note: 'G', octave: 6 },
  V: { note: 'G#', octave: 6 },
  b: { note: 'A', octave: 6 },
  B: { note: 'A#', octave: 6 },
  n: { note: 'B', octave: 6 },
  /* C7   */ m: { note: 'C', octave: 7 },
};

export const SHIFT_KEY_MAPPING: Record<string, string> = {
  Digit1: '!',
  Digit2: '@',
  Digit4: '$',
  Digit5: '%',
  Digit6: '^',
  Digit8: '*',
  Digit9: '(',
  KeyQ: 'Q',
  KeyW: 'W',
  KeyE: 'E',
  KeyT: 'T',
  KeyY: 'Y',
  KeyI: 'I',
  KeyO: 'O',
  KeyP: 'P',
  KeyS: 'S',
  KeyD: 'D',
  KeyG: 'G',
  KeyH: 'H',
  KeyJ: 'J',
  KeyL: 'L',
  KeyZ: 'Z',
  KeyC: 'C',
  KeyV: 'V',
  KeyB: 'B',
};

export function pianoKeyFromKeyboardEvent(e: KeyboardEvent): string {
  if (e.shiftKey) {
    return SHIFT_KEY_MAPPING[e.code] ?? e.key;
  }
  return e.key;
}

/* reverse map: "C4" → keyboard letter */
export const NOTE_TO_KEY: Record<string, string> = {};
for (const [k, v] of Object.entries(KEYBOARD_MAPPING)) {
  NOTE_TO_KEY[`${v.note}${v.octave}`] = k;
}

/* ── Piano key layout data ───────────────────────────────────────────── */
export interface KeyData {
  note: string;
  octave: number;
  isBlack: boolean;
  id: string;
  kbKey: string;
  leftPx?: number; /* absolute left offset (px) for black keys only */
}

export function buildKeyLayout(): KeyData[] {
  const WHITE_NOTES = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];
  const BLACK_AFTER: Record<string, string> = {
    C: 'C#',
    D: 'D#',
    F: 'F#',
    G: 'G#',
    A: 'A#',
  };
  /* WW = white-key slot width: key (38 px) + flex gap (2 px) = 40 px */
  const WW = 40;
  /* BW = black key visual width */
  const BW = 26;
  const keys: KeyData[] = [];
  let wIdx = 0; /* running white-key counter for leftPx */
  for (const oct of [2, 3, 4, 5, 6]) {
    for (const note of WHITE_NOTES) {
      const id = `${note}${oct}`;
      keys.push({
        note,
        octave: oct,
        isBlack: false,
        id,
        kbKey: NOTE_TO_KEY[id] ?? '',
      });
      if (BLACK_AFTER[note]) {
        const bNote = BLACK_AFTER[note]!;
        const bid = `${bNote}${oct}`;
        /* Centre black key over the boundary between this white key and the next:
           right edge of wIdx key = (wIdx+1)*WW (gap is included),
           minus half black-key width = centre over that boundary. */
        const leftPx = (wIdx + 1) * WW - Math.round(BW / 2);
        keys.push({
          note: bNote,
          octave: oct,
          isBlack: true,
          id: bid,
          kbKey: NOTE_TO_KEY[bid] ?? '',
          leftPx,
        });
      }
      wIdx++;
    }
  }
  keys.push({ note: 'C', octave: 7, isBlack: false, id: 'C7', kbKey: 'm' });
  return keys;
}

export const KEY_LAYOUT = buildKeyLayout();
export const WHITE_KEYS = KEY_LAYOUT.filter((k) => !k.isBlack);
export const BLACK_KEYS = KEY_LAYOUT.filter((k) => k.isBlack);
