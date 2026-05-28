// `relative-scale` — damped scaling for adornments + lifts in
// scalable host environments.
//
// THE PROBLEM
// ===========
//
// In any scalable rendering environment — a 2D canvas with pan/zoom,
// a 3D scene with a camera, a future timeline with a horizontal
// scale factor — host content scales with the environment, but
// SECONDARY UI (popovers, lifts, tooltips, resize handles, selection
// chrome) is typically rendered at viewport scale.
//
// A fixed-size popover at canvas zoom 0.5 LOOKS oversized (cell got
// smaller, popover stayed put). A fixed-size popover at zoom 2 looks
// shrunken (cell grew, popover stayed put). The optical illusion is
// that "the popover got bigger / smaller relative to the world."
//
// THE FIX
// =======
//
// Apply a DAMPED scale to lifts/adornments — they grow/shrink WITH
// the host but NOT 1:1. The damping is ASYMMETRIC by design:
//
//   - Zooming OUT: barely shrink. Once the lift hits a readable
//     minimum, freeze it there. Don't punish the user for a small
//     viewport — they need to read the popover.
//
//   - Zooming IN: scale up more aggressively. The user has zoomed
//     in for detail; their "sense of scale" expects the popover
//     to grow noticeably, otherwise the popover feels stuck.
//
// The curve uses TWO different exponents:
//
//   - z < 1 (zoomed out):  pow(z, 0.30)  — very shallow damping
//   - z >= 1 (zoomed in):  pow(z, 0.70)  — closer to linear growth
//
// Then clamps to a window the eye tolerates: [0.85, 1.8].
//
// Sample values (with default bounds):
//
//   raw    formula        result   note
//   0.25   pow(.25, .30)  0.660    clamped → 0.85 (floor)
//   0.50   pow(.50, .30)  0.812    clamped → 0.85 (floor)
//   0.75   pow(.75, .30)  0.917    0.917
//   1.00   1                       1.000
//   1.50   pow(1.5, .70)  1.343    1.343
//   2.00   pow(2.0, .70)  1.624    1.624
//   3.00   pow(3.0, .70)  2.158    clamped → 1.8 (cap)
//   4.00   pow(4.0, .70)  2.639    clamped → 1.8 (cap)
//
// Notice the asymmetry: at zoom 0.25 the lift only shrinks to 0.85
// (15% smaller), but at zoom 4 it grows to 1.8 (80% bigger). The
// shrink side floors quickly so popovers stay readable; the grow
// side opens up so they feel responsive to "I want to look closer."

/** Default lower bound. Below this, lift typography starts losing
 *  readability — we'd rather visual "stickiness" at a small viewport
 *  than hand the user an unreadable popover. */
export const DEFAULT_RELATIVE_SCALE_MIN = 0.85;

/** Default upper bound. Above this, lifts dominate the source
 *  content visually. The growth side is intentionally generous —
 *  users who've zoomed in WANT the popover to grow noticeably. */
export const DEFAULT_RELATIVE_SCALE_MAX = 1.8;

/** Exponent for the zoomed-OUT half (scale < 1). Shallow = very
 *  little shrinking. 0.30 means a 50% canvas zoom only damps the
 *  lift to ~80%. */
export const SHRINK_EXPONENT = 0.3;

/** Exponent for the zoomed-IN half (scale >= 1). Steeper than the
 *  shrink side so growth feels responsive. 0.70 keeps the damping
 *  visible (lift doesn't grow 1:1 with canvas) but doesn't flatten
 *  the way sqrt would. */
export const GROW_EXPONENT = 0.7;

/** Compute a damped multiplier from a raw environment scale.
 *
 *  Designed for canvas zoom + 3D-scene camera-distance + any other
 *  scalable host. Pass the environment's raw "how zoomed in are we"
 *  number; receive a multiplier suitable for adornment surfaces.
 *
 *  The default curve uses asymmetric exponents (gentler shrinking,
 *  more aggressive growing) and clamps to [0.85, 1.8]. See the
 *  module header for the rationale behind the asymmetry.
 *
 *  @param scale  raw environment scale (zoom, camera ratio, etc.)
 *  @param min    lower bound for the result. Defaults to 0.85.
 *  @param max    upper bound for the result. Defaults to 1.8.
 */
export function dampedRelativeScale(
  scale: number,
  min: number = DEFAULT_RELATIVE_SCALE_MIN,
  max: number = DEFAULT_RELATIVE_SCALE_MAX,
): number {
  if (!Number.isFinite(scale) || scale <= 0) return 1;
  if (scale === 1) return 1;
  const exponent = scale < 1 ? SHRINK_EXPONENT : GROW_EXPONENT;
  const damped = Math.pow(scale, exponent);
  if (damped < min) return min;
  if (damped > max) return max;
  return damped;
}
