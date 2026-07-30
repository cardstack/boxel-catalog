// Loop policy for the studio's generate/refine cycle. Separate from the
// transport because these are the knobs worth turning when the pipeline is
// too slow or not accurate enough, and they should be findable without
// reading the request code.

// auto refine passes after the initial generation (each costs one vision
// call and several minutes). Default 0: one generate = one model file; set
// >0 to re-enable the render-vs-reference correction loop.
export const AUTO_REFINE_ROUNDS = 0;
export const REFINE_TARGET_SCORE = 85;

// How many render-vs-reference "refine" passes the FIRST generation may run
// after the deterministic build + completeness audit. Each is a slow vision
// call, so this is deliberately small. Together with the completeness pass it
// bounds first generation to 2 AI correction passes total.
export const AUTO_VERIFY_ROUNDS = 1;
