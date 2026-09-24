/* ── Frequency calculation ───────────────────────────────────────────── */
export const BASE_FREQS: Record<string, number> = {
  C: 261.63,
  'C#': 277.18,
  D: 293.66,
  'D#': 311.13,
  E: 329.63,
  F: 349.23,
  'F#': 369.99,
  G: 392.0,
  'G#': 415.3,
  A: 440.0,
  'A#': 466.16,
  B: 493.88,
};

export function noteFreq(note: string, octave: number): number {
  return (BASE_FREQS[note] ?? 440) * Math.pow(2, octave - 4);
}

/* ── Instrument profiles (harmonic stacking + ADSR) ─────────────────── */
export interface InstrumentProfile {
  harmonics: { ratio: number; gain: number; detune?: number }[];
  attack: number;
  decay: number;
  sustainLevel: number;
  releaseDecay: number; /* how fast the tail fades (seconds to near-zero) */
}

export const INSTRUMENT_PROFILES: Record<string, InstrumentProfile> = {
  classical: {
    /* Grand piano: inharmonic overtones (real strings are slightly sharp above
       fundamental), two detuned unison oscillators for natural "chorus".
       ADSR: very fast attack → rapid initial decay → slow long tail (piano
       strings don't have a flat sustain level — they just keep decaying). */
    harmonics: [
      { ratio: 1.0, gain: 0.5 } /* fundamental */,
      { ratio: 1.0, gain: 0.1, detune: 5 } /* unison +5 cents */,
      { ratio: 2.005, gain: 0.22 } /* 2nd harmonic slightly sharp */,
      { ratio: 3.015, gain: 0.1 } /* 3rd */,
      { ratio: 4.03, gain: 0.06 } /* 4th */,
      { ratio: 5.05, gain: 0.03 } /* 5th */,
      { ratio: 6.08, gain: 0.015 } /* 6th */,
      { ratio: 8.13, gain: 0.008 } /* 8th */,
    ],
    attack: 0.004,
    decay: 0.12,
    sustainLevel: 0.18 /* piano strings continue decaying — no flat sustain */,
    releaseDecay: 1.8,
  },
  electric: {
    /* Rhodes-style: mellow mid harmonics, slightly warmer detune */
    harmonics: [
      { ratio: 1.0, gain: 0.42 },
      { ratio: 1.0, gain: 0.08, detune: 3 },
      { ratio: 2.002, gain: 0.28 },
      { ratio: 3.005, gain: 0.15 },
      { ratio: 4.01, gain: 0.08 },
      { ratio: 5.02, gain: 0.04 },
    ],
    attack: 0.012,
    decay: 0.2,
    sustainLevel: 0.25,
    releaseDecay: 1.2,
  },
  organ: {
    /* Hammond-style: perfectly harmonic, steady sustain — NO decay */
    harmonics: [
      { ratio: 1.0, gain: 0.38 },
      { ratio: 2.0, gain: 0.28 },
      { ratio: 3.0, gain: 0.2 },
      { ratio: 4.0, gain: 0.1 },
      { ratio: 6.0, gain: 0.04 },
    ],
    attack: 0.006,
    decay: 0.01,
    sustainLevel: 0.45,
    releaseDecay: 0.06,
  },
  harpsichord: {
    /* Sharp percussive attack, fast decay, bright upper harmonics */
    harmonics: [
      { ratio: 1.0, gain: 0.48 },
      { ratio: 2.002, gain: 0.26 },
      { ratio: 4.008, gain: 0.16 },
      { ratio: 8.02, gain: 0.08 },
      { ratio: 16.05, gain: 0.03 },
    ],
    attack: 0.003,
    decay: 0.03,
    sustainLevel: 0.06,
    releaseDecay: 0.5,
  },
  felt: {
    /* Felt/soft piano: muted, warm — piano with felt strip on strings */
    harmonics: [
      { ratio: 1.0, gain: 0.48 },
      { ratio: 2.002, gain: 0.14 },
      { ratio: 3.01, gain: 0.06 },
      { ratio: 4.02, gain: 0.03 },
    ],
    attack: 0.008,
    decay: 0.18,
    sustainLevel: 0.22,
    releaseDecay: 2.4,
  },
  bright: {
    /* Bright piano: strong upper harmonics, crisp attack */
    harmonics: [
      { ratio: 1.0, gain: 0.42 },
      { ratio: 1.0, gain: 0.09, detune: 7 },
      { ratio: 2.005, gain: 0.26 },
      { ratio: 3.02, gain: 0.16 },
      { ratio: 4.04, gain: 0.12 },
      { ratio: 5.08, gain: 0.08 },
      { ratio: 6.12, gain: 0.05 },
      { ratio: 8.2, gain: 0.03 },
    ],
    attack: 0.002,
    decay: 0.08,
    sustainLevel: 0.14,
    releaseDecay: 1.5,
  },
  symphonic: {
    /* Symphonic / Concert Grand: rich overtones, long tail */
    harmonics: [
      { ratio: 1.0, gain: 0.45 },
      { ratio: 1.0, gain: 0.12, detune: 4 },
      { ratio: 2.004, gain: 0.24 },
      { ratio: 3.012, gain: 0.14 },
      { ratio: 4.025, gain: 0.09 },
      { ratio: 5.045, gain: 0.05 },
      { ratio: 6.07, gain: 0.03 },
      { ratio: 7.1, gain: 0.02 },
    ],
    attack: 0.005,
    decay: 0.15,
    sustainLevel: 0.2,
    releaseDecay: 3.2,
  },
  violin: {
    /* Violin: slow bow attack, flat sustain, expressive tail */
    harmonics: [
      { ratio: 1.0, gain: 0.4 },
      { ratio: 2.0, gain: 0.3 },
      { ratio: 3.0, gain: 0.18 },
      { ratio: 4.0, gain: 0.08 },
      { ratio: 5.0, gain: 0.04 },
    ],
    attack: 0.08,
    decay: 0.05,
    sustainLevel: 0.42,
    releaseDecay: 0.3,
  },
  harp: {
    /* Harp: plucked, clean fast attack, warm decay */
    harmonics: [
      { ratio: 1.0, gain: 0.5 },
      { ratio: 2.001, gain: 0.22 },
      { ratio: 3.004, gain: 0.12 },
      { ratio: 4.009, gain: 0.07 },
      { ratio: 5.016, gain: 0.04 },
      { ratio: 6.025, gain: 0.02 },
    ],
    attack: 0.003,
    decay: 0.05,
    sustainLevel: 0.1,
    releaseDecay: 2.8,
  },
};
